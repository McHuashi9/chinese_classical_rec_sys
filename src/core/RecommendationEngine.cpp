#include "core/RecommendationEngine.h"
#include "core/MathUtils.h"
#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"
#include <cmath>
#include <algorithm>

// CRITIC权重定义移入 Config.h

RecommendationEngine::RecommendationEngine() {}

double RecommendationEngine::gaussian(double x) const {
    return math_utils::gaussian(x);
}

double RecommendationEngine::calculateDifficultyGap(const User& user, const Text& text) const {
    // 公式20: δ = Σ_{j=1}^{10} w'_j · (d̂_j - u_j)
    // 已答题维度（quiz_count > 0）权重衰减 QUIZ_WEIGHT_FACTOR，再重新归一化，
    // 避免推荐集中于用户已答过题的维度
    auto features = FeatureExtractor::getNormalizedFeatures(text);

    double raw[10];
    double weightSum = 0.0;
    for (int j = 0; j < 10; j++) {
        raw[j] = Config::CRITIC_WEIGHTS[j] * (user.getQuizCount(j) > 0 ? Config::QUIZ_WEIGHT_FACTOR : 1.0);
        weightSum += raw[j];
    }
    if (weightSum <= 0.0) weightSum = 1.0;

    double delta = 0.0;
    for (int j = 0; j < 10; j++) {
        double d_j = features[j];
        double u_j = user.getAbility(j);  // 用户能力已在[0,1]范围
        delta += (raw[j] / weightSum) * (d_j - u_j);
    }
    
    return delta;
}

double RecommendationEngine::calculateProbability(const User& user, const Text& text) const {
    // 公式19: P_diff = exp(-(δ - δ*)² / 2σ²)
    double delta = calculateDifficultyGap(user, text);
    return gaussian(delta - Config::DELTA_STAR);
}

double RecommendationEngine::calculateLearningGain(double d_j, double u_j) const {
    return math_utils::calculateLearningGain(d_j, u_j);
}

double RecommendationEngine::calculateDynamicLearningRate(double avgAbility) const {
    return math_utils::calculateDynamicLearningRate(avgAbility, Config::ETA);
}

std::vector<std::pair<int, double>> RecommendationEngine::recommend(
    const User& user,
    const std::vector<Text>& texts,
    int topK
) const {
    if (topK <= 0) return {};

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
