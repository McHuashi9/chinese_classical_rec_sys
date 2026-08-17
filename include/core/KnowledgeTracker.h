#ifndef KNOWLEDGE_TRACKER_H
#define KNOWLEDGE_TRACKER_H

#include "models/User.h"
#include "models/Text.h"
#include "core/Config.h"
#include "database/LearningIncrementRepository.h"
#include <vector>

/**
 * @brief 知识追踪器类
 * 
 * 实现论文第5节的阅读效应更新算法和遗忘效应
 * 
 * 阅读效应（论文公式15）：
 * Δu_j^read = η(t) · g_j · (1 - u_j(t))
 * 
 * 遗忘效应（论文公式17、18）：
 * u_j(t) = u_j^base + Σ Δu_j^(k) · ψ(t - t_k)
 * ψ(Δt) = (1 + Δt/τ)^(-c)
 */
class KnowledgeTracker {
public:
    KnowledgeTracker(LearningIncrementRepository* incrementRepo = nullptr);
    
    /**
     * @brief 应用阅读效应，记录增量
     * 
     * 实现论文公式15，计算增量后存入数据库
     * 
     * @param user 用户对象（将被修改）
     * @param text 文章对象（提供难度特征）
     * @param readTime 阅读时长（秒），用于判断是否触发更新
     * @param timestamp 阅读时刻（默认为当前时间）
     */
    void applyReadEffect(User& user, const Text& text, double readTime, 
                         time_t timestamp = 0);

    /**
     * @brief 应用答题效应，记录增量（论文公式19-22）
     * 
     * 对题目 dims 覆盖的每个维度 j：
     *   E[s_j] = sigmoid(β·(u_j - d̂_j))                （预期正确率）
     *   K_j(t) = max(K_min, K_0/(1 + λ_K·N_j))          （动态学习率）
     *   Δu_j = K_j(t)·(s - E[s_j])                       （s=1 答对 / 0 答错）
     * 每题一次（按 dims 平均误差）：
     *   η ← clip(η + α_η·mean(s - E[s_j]), η_min, η_max)（悟性动态调整）
     * 增量可为负（答错拉低能力），|Δ| ≥ MIN_DELTA_THRESHOLD 时入库 type="quiz"；
     * 每维累计答题次数 N_j 自增。
     * 
     * @param user 用户对象（将被修改：能力/悟性/答题计数）
     * @param text 文章对象（提供 d̂_j 特征）
     * @param dims 题目涉及的维度（0-based，如 shici → {3,4,9}）
     * @param correct 本题是否正确（1/0）
     * @param timestamp 答题时刻（默认为当前时间）
     */
    void applyQuizEffect(User& user, const Text& text,
                         const std::vector<int>& dims, int correct,
                         time_t timestamp = 0);
    
    /**
     * @brief 计算当前能力（实现论文公式17）
     * 
     * u_j(t) = u_j^base + Σ Δu_j^(k) · ψ(t - t_k)
     * 
     * @param user 用户对象（包含基础能力）
     * @param increments 该维度的增量列表
     * @param currentTime 当前时刻
     * @return 当前能力值
     */
    double calculateCurrentAbility(const User& user, int dimension,
                                   const std::vector<LearningIncrement>& increments,
                                   time_t currentTime) const;
    
    /**
     * @brief 应用遗忘效应更新用户能力
     * 
     * 从增量历史计算当前能力，并更新用户对象
     * 
     * @param user 用户对象（将被修改）
     * @param currentTime 当前时刻
     */
    void applyForgettingEffect(User& user, time_t currentTime) const;
    
    /**
     * @brief 清理过期增量
     * 
     * 当增量的遗忘因子 ψ(Δt) < PSI_MIN 时，
     * 将增量合并到基础能力并删除记录
     * 
     * @param user 用户对象（基础能力将被修改）
     * @param currentTime 当前时刻
     * @return 清理的增量数量
     */
    int pruneOldIncrements(User& user, time_t currentTime) const;

    /**
     * @brief 设置当前用户 id（所有增量读写绑定该 id）
     */
    void setUserId(int userId) { userId_ = userId; }
    int getUserId() const { return userId_; }
    
    /**
     * @brief 计算动态学习率 η(t)
     */
    double calculateDynamicLearningRate(double avgAbility) const;
    
    /**
     * @brief 计算学习增益 g_j
     */
    double calculateLearningGain(double d_j, double u_j) const;
    
    /**
     * @brief 计算遗忘因子 ψ(Δt)
     */
    double calculateForgettingFactor(double deltaDays) const;
    
private:
    LearningIncrementRepository* incrementRepo;
    int userId_ = 1;
    
    double gaussian(double x) const;
};

#endif
