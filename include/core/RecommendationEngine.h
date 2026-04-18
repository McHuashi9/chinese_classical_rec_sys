#ifndef RECOMMENDATION_ENGINE_H
#define RECOMMENDATION_ENGINE_H

#include "models/User.h"
#include "models/Text.h"
#include "core/Config.h"
#include <vector>
#include <utility>

/**
 * @brief 推荐引擎类
 * 
 * 实现论文第6节的高斯概率i+1推荐算法
 */
class RecommendationEngine {
public:
    RecommendationEngine();
    
    /**
     * @brief 计算文章的推荐概率
     * @param user 用户状态
     * @param text 文章特征
     * @return 推荐概率 P_diff ∈ (0, 1]
     */
    double calculateProbability(const User& user, const Text& text) const;
    
    /**
     * @brief 计算难度差距 δ
     * @param user 用户状态
     * @param text 文章特征
     * @return 难度差距 δ
     */
    double calculateDifficultyGap(const User& user, const Text& text) const;
    
    /**
     * @brief 推荐文章列表
     * @param user 用户状态
     * @param texts 候选文章列表
     * @param topK 返回前K篇
     * @return 推荐列表 (文章ID, 概率)，按概率降序排列
     */
    std::vector<std::pair<int, double>> recommend(
        const User& user,
        const std::vector<Text>& texts,
        int topK = 10
    ) const;
    
    /**
     * @brief 计算学习增益 g_j（式10）
     * @param d_j 文章第j维难度
     * @param u_j 用户第j维能力
     * @return 学习增益 g_j
     */
    double calculateLearningGain(double d_j, double u_j) const;
    
    /**
     * @brief 计算动态学习率 η(t)（式9）
     * @param avgAbility 用户平均能力
     * @return 动态学习率 η(t)
     */
    double calculateDynamicLearningRate(double avgAbility) const;
    
private:
    /**
     * @brief 高斯函数
     * @param x 输入值
     * @return exp(-x² / 2σ²)
     */
    double gaussian(double x) const;
};

#endif
