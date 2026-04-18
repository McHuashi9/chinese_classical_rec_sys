#include "core/RecommendationEngine.h"
#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"
#include <cmath>
#include <algorithm>

// CRITIC法权重（来自 data/critic_weights.json）
// 替代熵权法，避免稀疏特征权重过高的问题
// d1=f1, d2=f3, d3=f5, d4=f6, d5=f8, d6=f9, d7=f10, d8=f11, d9=f12, d10=f13
// 权重已归一化（∑ w_j = 1），符合论文公式定义
static constexpr double WEIGHTS[10] = {
    0.09215147849158459,   // d1 平均句长
    0.09381903520884108,   // d2 句子数
    0.13107376305655005,   // d3 虚词比例
    0.09247110185289635,   // d4 字平均对数频次
    0.10340632494506398,   // d5 通假字密度
    0.11624060937033848,   // d6 古汉语困惑度
    0.08774914762423046,   // d7 今汉语困惑度
    0.08543906673127047,   // d8 MATTR词汇多样性
    0.10087872345819664,   // d9 典故密度
    0.09677074926102798    // d10 语义复杂度
};

RecommendationEngine::RecommendationEngine() {}

double RecommendationEngine::gaussian(double x) const {
    return std::exp(-x * x / (2.0 * Config::SIGMA * Config::SIGMA));
}

double RecommendationEngine::calculateDifficultyGap(const User& user, const Text& text) const {
    // 公式20: δ = Σ_{j=1}^{10} w'_j · (d̂_j - u_j)
    // 由于 CRITIC 权重已归一化（∑ w_j = 1），w'_j = w_j
    auto features = FeatureExtractor::getNormalizedFeatures(text);
    double delta = 0.0;
    
    for (int j = 0; j < 10; j++) {
        double d_j = features[j];
        double u_j = user.getAbility(j);  // 用户能力已在[0,1]范围
        delta += WEIGHTS[j] * (d_j - u_j);
    }
    
    return delta;
}

double RecommendationEngine::calculateProbability(const User& user, const Text& text) const {
    // 公式19: P_diff = exp(-(δ - δ*)² / 2σ²)
    double delta = calculateDifficultyGap(user, text);
    return gaussian(delta - Config::DELTA_STAR);
}

double RecommendationEngine::calculateLearningGain(double d_j, double u_j) const {
    // 公式14: g_j = exp(-(d̂_j - u_j - δ*)² / 2σ²)
    return gaussian(d_j - u_j - Config::DELTA_STAR);
}

double RecommendationEngine::calculateDynamicLearningRate(double avgAbility) const {
    // 公式13: η(t) = η · (1 - ū(t))^γ
    return Config::ETA * std::pow(1.0 - avgAbility, Config::GAMMA);
}

std::vector<std::pair<int, double>> RecommendationEngine::recommend(
    const User& user,
    const std::vector<Text>& texts,
    int topK
) const {
    LOG_DEBUG("开始推荐计算，文章数量: {}, topK: {}", texts.size(), topK);
    
    std::vector<std::pair<int, double>> scores;
    scores.reserve(texts.size());
    
    for (const auto& text : texts) {
        double prob = calculateProbability(user, text);
        scores.emplace_back(text.getId(), prob);
    }
    
    // 按概率降序排序
    std::sort(scores.begin(), scores.end(),
        [](const auto& a, const auto& b) {
            return a.second > b.second;
        });
    
    if (static_cast<int>(scores.size()) > topK) {
        scores.resize(topK);
    }
    
    if (!scores.empty()) {
        LOG_DEBUG("推荐完成，最高概率: {:.4f} (文章ID: {})", scores[0].second, scores[0].first);
    }
    
    return scores;
}
