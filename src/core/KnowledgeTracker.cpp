#include "core/KnowledgeTracker.h"
#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"
#include <cmath>
#include <algorithm>
#include <ctime>

KnowledgeTracker::KnowledgeTracker(LearningIncrementRepository* incrementRepo)
    : incrementRepo(incrementRepo) {}

double KnowledgeTracker::gaussian(double x) const {
    return std::exp(-x * x / (2.0 * Config::SIGMA * Config::SIGMA));
}

double KnowledgeTracker::calculateDynamicLearningRate(double avgAbility) const {
    // 公式13: η(t) = η · (1 - ū(t))^γ
    return Config::ETA * std::pow(1.0 - avgAbility, Config::GAMMA);
}

double KnowledgeTracker::calculateLearningGain(double d_j, double u_j) const {
    // 公式14: g_j = exp(-(d̂_j - u_j - δ*)² / 2σ²)
    return gaussian(d_j - u_j - Config::DELTA_STAR);
}

double KnowledgeTracker::calculateForgettingFactor(double deltaDays) const {
    // 公式18: ψ(Δt) = (1 + Δt/τ)^(-c)
    if (deltaDays <= 0) {
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
    
    // 计算动态学习率 η(t)
    double avgAbility = user.getAverageAbility();
    double eta_t = calculateDynamicLearningRate(avgAbility);
    
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
        if (incrementRepo && delta > 0.0001) {  // 只记录有意义的增量
            incrementRepo->addIncrement(1, j + 1, delta, timestamp, "read");
        }
    }
    
    LOG_DEBUG("知识追踪完成: 更新后平均能力={:.3f}", user.getAverageAbility());
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
        // inc.dimension 是 1-10，需要与 dimension 匹配
        if (inc.dimension != dimension + 1) {
            continue;
        }
        
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
    
    // 对每个维度计算当前能力
    for (int j = 0; j < 10; j++) {
        // 获取该维度的增量
        std::vector<LearningIncrement> dimIncrements;
        for (const auto& inc : allIncrements) {
            if (inc.dimension == j + 1) {
                dimIncrements.push_back(inc);
            }
        }
        
        // 计算当前能力
        double currentAbility = calculateCurrentAbility(user, j, dimIncrements, currentTime);
        user.setAbility(j, currentAbility);
    }
    
    LOG_DEBUG("遗忘效应应用完成: 平均能力={:.3f}", user.getAverageAbility());
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
    
    // 更新基础能力
    for (int j = 0; j < 10; j++) {
        if (baseAbilityAdditions[j] > 0) {
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