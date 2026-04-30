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
    

};

#endif
