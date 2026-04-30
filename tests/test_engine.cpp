#include <catch_amalgamated.hpp>
#include "core/RecommendationEngine.h"
#include "models/User.h"
#include "models/Text.h"
#include <vector>
#include <cmath>

/**
 * @brief 集成测试：推荐引擎
 *
 * 测试范围：
 * - calculateDifficultyGap 加权难度差距计算
 * - calculateProbability 推荐概率计算
 * - recommend 推荐列表排序
 */

constexpr double EPSILON = 1e-4;

// =============================================================================
// calculateDifficultyGap 测试
// =============================================================================

TEST_CASE("RecommendationEngine::calculateDifficultyGap - 能力与难度相等时差距为零", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();  // 所有维度 = 0.3

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.3);  // 与用户能力相同
    }

    double gap = engine.calculateDifficultyGap(user, text);
    REQUIRE(std::abs(gap) < EPSILON);
}

TEST_CASE("RecommendationEngine::calculateDifficultyGap - 难度高于能力时差距为正", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.8);
    }

    double gap = engine.calculateDifficultyGap(user, text);
    REQUIRE(gap > 0.0);
}

TEST_CASE("RecommendationEngine::calculateDifficultyGap - 难度低于能力时差距为负", "[engine]") {
    RecommendationEngine engine;
    User user;
    for (int i = 0; i < 10; i++) {
        user.setAbility(i, 0.7);
    }

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.2);
    }

    double gap = engine.calculateDifficultyGap(user, text);
    REQUIRE(gap < 0.0);
}

// =============================================================================
// calculateProbability 测试
// =============================================================================

TEST_CASE("RecommendationEngine::calculateProbability - 理想难度差距处概率最大", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();  // 所有维度 = 0.3

    Text text;
    // 设置难度使加权差距 δ ≈ δ* = 0.13
    // δ = Σ w_j * (d_j - u_j) = 0.13
    // 如果所有 d_j 相同，则 δ = (d - 0.3) * Σ w_j = (d - 0.3) * 1.0 (因为 ∑ w_j = 1)
    // 所以 d = 0.3 + 0.13 = 0.43
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.43);
    }

    double prob = engine.calculateProbability(user, text);
    REQUIRE(std::abs(prob - 1.0) < EPSILON);
}

TEST_CASE("RecommendationEngine::calculateProbability - 难度差距过大时概率降低", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    Text text_near;
    Text text_far;
    for (int i = 0; i < 10; i++) {
        text_near.setDifficulty(i, 0.43);
        text_far.setDifficulty(i, 0.9);
    }

    double prob_near = engine.calculateProbability(user, text_near);
    double prob_far = engine.calculateProbability(user, text_far);
    REQUIRE(prob_near > prob_far);
}

TEST_CASE("RecommendationEngine::calculateProbability - 概率范围在 (0, 1]", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    for (double diff = 0.0; diff <= 1.0; diff += 0.25) {
        Text text;
        for (int i = 0; i < 10; i++) {
            text.setDifficulty(i, diff);
        }
        double prob = engine.calculateProbability(user, text);
        REQUIRE(prob > 0.0);
        REQUIRE(prob <= 1.0);
    }
}

// =============================================================================
// recommend 测试
// =============================================================================

TEST_CASE("RecommendationEngine::recommend - 按概率降序排列", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    std::vector<Text> texts;
    for (int i = 0; i < 5; i++) {
        Text text;
        text.setId(i + 1);
        text.setTitle("文章" + std::to_string(i + 1));
        double diff = 0.3 + i * 0.1;
        for (int j = 0; j < 10; j++) {
            text.setDifficulty(j, diff);
        }
        texts.push_back(text);
    }

    auto scores = engine.recommend(user, texts, 5);
    REQUIRE(scores.size() == 5);

    // 验证按概率降序排列
    for (size_t i = 1; i < scores.size(); i++) {
        REQUIRE(scores[i - 1].second >= scores[i].second);
    }
}

TEST_CASE("RecommendationEngine::recommend - TopK 限制", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    std::vector<Text> texts;
    for (int i = 0; i < 10; i++) {
        Text text;
        text.setId(i + 1);
        for (int j = 0; j < 10; j++) {
            text.setDifficulty(j, 0.3 + i * 0.05);
        }
        texts.push_back(text);
    }

    auto scores = engine.recommend(user, texts, 3);
    REQUIRE(scores.size() == 3);
}

TEST_CASE("RecommendationEngine::recommend - 空列表", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();
    std::vector<Text> emptyTexts;

    auto scores = engine.recommend(user, emptyTexts, 10);
    REQUIRE(scores.empty());
}

TEST_CASE("RecommendationEngine::recommend - 当 TopK 大于文本数时返回全部", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    std::vector<Text> texts;
    for (int i = 0; i < 3; i++) {
        Text text;
        text.setId(i + 1);
        for (int j = 0; j < 10; j++) {
            text.setDifficulty(j, 0.5);
        }
        texts.push_back(text);
    }

    auto scores = engine.recommend(user, texts, 100);
    REQUIRE(scores.size() == 3);
}

// =============================================================================
// 综合场景测试
// =============================================================================

TEST_CASE("RecommendationEngine - 综合场景：能力高的用户被推荐更难的文章", "[engine]") {
    RecommendationEngine engine;

    User beginner;
    beginner.initializeDefault();  // 所有维度 = 0.3

    User advanced;
    for (int i = 0; i < 10; i++) {
        advanced.setAbility(i, 0.8);
    }

    Text hardText;
    for (int i = 0; i < 10; i++) {
        hardText.setDifficulty(i, 0.8);
    }

    double prob_beginner = engine.calculateProbability(beginner, hardText);
    double prob_advanced = engine.calculateProbability(advanced, hardText);

    // 高级用户对难文章有更高概率
    REQUIRE(prob_advanced > prob_beginner);
}

TEST_CASE("RecommendationEngine - 综合场景：加权差距影响排序", "[engine]") {
    RecommendationEngine engine;
    User user;
    user.initializeDefault();

    std::vector<Text> texts;
    for (int i = 0; i < 4; i++) {
        Text text;
        text.setId(i + 1);
        for (int j = 0; j < 10; j++) {
            text.setDifficulty(j, 0.3 + i * 0.05);
        }
        texts.push_back(text);
    }

    auto scores = engine.recommend(user, texts, 4);
    REQUIRE(scores.size() == 4);

    // 难度最接近 δ* 的排最前面
    double bestGap = engine.calculateDifficultyGap(user, texts[scores[0].first - 1]);
    for (size_t i = 1; i < scores.size(); i++) {
        double curGap = engine.calculateDifficultyGap(user, texts[scores[i].first - 1]);
        double bestDist = std::abs(bestGap - 0.13);
        double curDist = std::abs(curGap - 0.13);
        REQUIRE(bestDist <= curDist + EPSILON);
    }
}
