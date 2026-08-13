#include "core/KnowledgeTracker.h"
#include "core/MathUtils.h"
#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"
#include <cmath>
#include <algorithm>
#include <array>
#include <ctime>

KnowledgeTracker::KnowledgeTracker(LearningIncrementRepository* incrementRepo)
    : incrementRepo(incrementRepo) {}

double KnowledgeTracker::gaussian(double x) const {
    return math_utils::gaussian(x);
}

double KnowledgeTracker::calculateDynamicLearningRate(double avgAbility) const {
    return math_utils::calculateDynamicLearningRate(avgAbility, Config::ETA);
}

double KnowledgeTracker::calculateLearningGain(double d_j, double u_j) const {
    return math_utils::calculateLearningGain(d_j, u_j);
}

double KnowledgeTracker::calculateForgettingFactor(double deltaDays) const {
    // 公式18: ψ(Δt) = (1 + Δt/τ)^(-c)
    if (deltaDays <= 0) {
        if (deltaDays < 0) {
            LOG_WARN("负时间差 {:.4f} 天，可能是时钟回拨或脏数据", deltaDays);
        }
        return 1.0;
    }
    return std::pow(1.0 + deltaDays / Config::TAU, -Config::C);
}

void KnowledgeTracker::applyReadEffect(User& user, const Text& text, double readTime,
                                        time_t timestamp) {
    // 检查阅读时间是否达到阈值
    if (readTime < Config::MIN_READ_TIME) {
        LOG_DEBUG("阅读时间 {:.1f}s 未达到阈值 {}s，不触发知识追踪", readTime, Config::MIN_READ_TIME);
        return;
    }
    
    // 使用当前时间（如果未指定）
    if (timestamp == 0) {
        timestamp = std::time(nullptr);
    }
    
    // 计算动态学习率 η(t) = η·(1-ū)^γ（η 为悟性，随答题动态调整）
    double avgAbility = user.getAverageAbility();
    double eta_t = math_utils::calculateDynamicLearningRate(avgAbility, user.getEta());
    
    LOG_DEBUG("知识追踪触发: 文章ID={}, 阅读时间={:.1f}s, 平均能力={:.3f}, 动态学习率={:.4f}",
              text.getId(), readTime, avgAbility, eta_t);
    
    // 获取文章的10维特征
    auto features = FeatureExtractor::getNormalizedFeatures(text);
    
    // 对每个维度应用阅读效应，计算增量并记录
    for (int j = 0; j < 10; j++) {
        double u_j = user.getAbility(j);
        double d_j = features[j];
        
        // 计算学习增益 g_j
        double g_j = calculateLearningGain(d_j, u_j);
        
        // 计算能力增量 Δu_j
        double delta = eta_t * g_j * (1.0 - u_j);
        
        // 更新能力值
        double newAbility = std::clamp(u_j + delta, 0.0, 1.0);
        user.setAbility(j, newAbility);
        
        // 记录增量到数据库（如果 Repository 可用）
        if (incrementRepo && delta > Config::MIN_DELTA_THRESHOLD) {
            incrementRepo->addIncrement(1, j + 1, delta, timestamp, "read");
        }
    }
    
    LOG_DEBUG("知识追踪完成: 更新后平均能力={:.3f}", user.getAverageAbility());
}

void KnowledgeTracker::applyQuizEffect(User& user, const Text& text,
                                       const std::vector<int>& dims, int correct,
                                       time_t timestamp) {
    if (dims.empty()) {
        LOG_WARN("答题效应: dims 为空，跳过");
        return;
    }
    // 防御：dims 去重（正常题库每题型维度不重复；若脏数据含重复维度，
    // 不去重会导致该维被应用两次、答题次数 N_j 自增两次，静默污染）
    std::vector<int> uniqueDims(dims);
    std::sort(uniqueDims.begin(), uniqueDims.end());
    uniqueDims.erase(std::unique(uniqueDims.begin(), uniqueDims.end()),
                     uniqueDims.end());
    if (timestamp == 0) {
        timestamp = std::time(nullptr);
    }
    const double s = (correct != 0) ? 1.0 : 0.0;
    // 预期正确率的参考点 d̂_j 取文章第 j 维标准化特征（0~1）。
    // 题目 difficulty 字段是同篇文章各维特征的加权摘要，篇内同题型没有区分度，
    // 因此答题效应不按题目 difficulty 计算，统一以文章特征为参考；
    // difficulty 仅用于题目展示与跨篇聚合，不参与答题效应。
    auto features = FeatureExtractor::getNormalizedFeatures(text);
    double sumError = 0.0;
    int applied = 0;

    for (int j : uniqueDims) {
        if (j < 0 || j >= 10) {
            LOG_WARN("答题效应: 维度越界 {}", j);
            continue;
        }
        double u_j = user.getAbility(j);
        double d_j = features[j];
        int n_j = user.getQuizCount(j);

        // 论文§5.3: E[s_j] = sigmoid(β·(u_j - d̂_j))
        double e = math_utils::expectedAccuracy(u_j, d_j);
        // K_j(t) = max(K_min, K_0/(1 + λ_K·N_j))（用答题前 N_j）
        double k_j = math_utils::quizLearningRate(n_j);
        // Δu_j = K_j(t)·(s - E[s_j])
        double delta = k_j * (s - e);

        double newAbility = std::clamp(u_j + delta, 0.0, 1.0);
        user.setAbility(j, newAbility);

        sumError += (s - e);
        applied++;

        // 累计答题次数自增（答对答错都计）
        user.incrementQuizCount(j);

        // 记录增量（答题增量可为负——答错真实拉低能力，负数也入库）
        if (incrementRepo && std::abs(delta) > Config::MIN_DELTA_THRESHOLD) {
            incrementRepo->addIncrement(1, j + 1, delta, timestamp, "quiz");
        }
    }

    // 悟性动态调整（每题一次，按 dims 平均误差）：η ← clip(η + α_η·mean(s-E[s_j]), η_min, η_max)
    if (applied > 0) {
        user.setEta(user.getEta() + Config::ALPHA_ETA * (sumError / applied));
    }

    std::string dimStr;
    for (int j : uniqueDims) dimStr += std::to_string(j) + " ";
    LOG_DEBUG("答题效应完成: dims=[{}], s={}, 更新后平均能力={:.3f}, η={:.3f}",
              dimStr, s, user.getAverageAbility(), user.getEta());
}

double KnowledgeTracker::calculateCurrentAbility(const User& user, int dimension,
                                                  const std::vector<LearningIncrement>& increments,
                                                  time_t currentTime) const {
    // 论文公式17: u_j(t) = u_j^base + Σ Δu_j^(k) · ψ(t - t_k)
    
    // 基础能力（维度索引从0开始，数据库从1开始）
    double u_base = user.getBaseAbility(dimension);
    
    // 计算增量的遗忘后总和
    double sumDelta = 0.0;
    
    for (const auto& inc : increments) {
        // 计算时间差（天数）
        double deltaSeconds = static_cast<double>(currentTime - inc.timestamp);
        double deltaDays = deltaSeconds / 86400.0;
        
        // 计算遗忘因子
        double psi = calculateForgettingFactor(deltaDays);
        
        // 累加衰减后的增量
        sumDelta += inc.delta * psi;
    }
    
    // 总能力
    double u_total = u_base + sumDelta;
    
    // 约束在 [0, 1] 范围内
    return std::clamp(u_total, 0.0, 1.0);
}

void KnowledgeTracker::applyForgettingEffect(User& user, time_t currentTime) const {
    if (!incrementRepo) {
        LOG_WARN("LearningIncrementRepository 未初始化，无法应用遗忘效应");
        return;
    }
    
    // 获取所有增量
    std::vector<LearningIncrement> allIncrements = incrementRepo->getAllIncrements(1);
    
    if (allIncrements.empty()) {
        LOG_DEBUG("无增量记录，跳过遗忘效应");
        return;
    }
    
    // 单次遍历按维度分区（O(n) 替代原 O(10*n)）
    std::array<std::vector<LearningIncrement>, 10> dimGroups;
    for (const auto& inc : allIncrements) {
        if (inc.dimension >= 1 && inc.dimension <= 10) {
            dimGroups[inc.dimension - 1].push_back(inc);
        }
    }
    
    // 对每个维度计算当前能力
    for (int j = 0; j < 10; j++) {
        double currentAbility = calculateCurrentAbility(user, j, dimGroups[j], currentTime);
        user.setAbility(j, currentAbility);
    }
    
    LOG_INFO("遗忘效应应用完成: 平均能力={:.3f}", user.getAverageAbility());
}

int KnowledgeTracker::pruneOldIncrements(User& user, time_t currentTime) const {
    if (!incrementRepo) {
        return 0;
    }
    
    // 获取所有增量
    std::vector<LearningIncrement> allIncrements = incrementRepo->getAllIncrements(1);
    
    std::vector<int> toDelete;
    std::array<double, 10> baseAbilityAdditions = {0};
    
    for (const auto& inc : allIncrements) {
        // 计算时间差（天数）
        double deltaSeconds = static_cast<double>(currentTime - inc.timestamp);
        double deltaDays = deltaSeconds / 86400.0;
        
        // 计算遗忘因子
        double psi = calculateForgettingFactor(deltaDays);
        
        // 如果遗忘因子低于阈值，合并到基础能力并标记删除
        if (psi < Config::PSI_MIN) {
            int dimIndex = inc.dimension - 1;  // 转换为0-based索引
            if (dimIndex >= 0 && dimIndex < 10) {
                // 遗忘后的增量值
                double forgottenDelta = inc.delta * psi;
                baseAbilityAdditions[dimIndex] += forgottenDelta;
                toDelete.push_back(inc.id);
                
                LOG_DEBUG("清理增量: ID={}, 维度={}, psi={:.4f}, 合并到基础能力={:.6f}",
                          inc.id, inc.dimension, psi, forgottenDelta);
            }
        }
    }
    
    // 更新基础能力（负增量也合并——quiz 答错拉低能力同样会被遗忘吸收）
    for (int j = 0; j < 10; j++) {
        if (baseAbilityAdditions[j] != 0.0) {
            double newBase = user.getBaseAbility(j) + baseAbilityAdditions[j];
            user.setBaseAbility(j, std::clamp(newBase, 0.0, 1.0));
        }
    }
    
    // 删除过期增量
    if (!toDelete.empty()) {
        incrementRepo->deleteIncrements(toDelete);
        LOG_INFO("清理了 {} 个过期增量，合并到基础能力", toDelete.size());
    }
    
    return static_cast<int>(toDelete.size());
}