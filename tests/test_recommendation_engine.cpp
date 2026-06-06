#include <catch_amalgamated.hpp>
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "core/Config.h"
#include "models/User.h"
#include "models/Text.h"
#include <cmath>
#include <array>
#include <vector>

constexpr double EPS = 1e-4;

static User makeUser(double ability) {
    User u;
    for (int i = 0; i < 10; i++) u.setAbility(i, ability);
    return u;
}

static User makeUserNonUniform(const std::array<double, 10>& abilities) {
    User u;
    for (int i = 0; i < 10; i++) u.setAbility(i, abilities[i]);
    return u;
}

static Text makeText(int id, double diff) {
    Text t;
    t.setId(id);
    for (int i = 0; i < 10; i++) t.setDifficulty(i, diff);
    return t;
}

static Text makeTextNonUniform(int id, const std::array<double, 10>& diffs) {
    Text t;
    t.setId(id);
    for (int i = 0; i < 10; i++) t.setDifficulty(i, diffs[i]);
    return t;
}

double expectedProb(double ability, double difficulty) {
    double delta = difficulty - ability;
    return std::exp(-(delta - Config::DELTA_STAR) *
                     (delta - Config::DELTA_STAR) /
                     (2 * Config::SIGMA * Config::SIGMA));
}

TEST_CASE("calculateDifficultyGap", "[engine]") {
    RecommendationEngine engine;

    SECTION("d_j = u_j, delta = 0") {
        User u = makeUser(0.5);
        Text t = makeText(1, 0.5);
        double delta = engine.calculateDifficultyGap(u, t);
        REQUIRE(std::abs(delta) < EPS);
    }

    SECTION("d_j > u_j, delta > 0") {
        User u = makeUser(0.3);
        Text t = makeText(1, 0.5);
        double delta = engine.calculateDifficultyGap(u, t);
        REQUIRE(std::abs(delta - 0.2) < EPS);
    }

    SECTION("d_j < u_j, delta < 0") {
        User u = makeUser(0.7);
        Text t = makeText(1, 0.5);
        double delta = engine.calculateDifficultyGap(u, t);
        REQUIRE(std::abs(delta + 0.2) < EPS);
    }

    SECTION("CRITIC 权重加权") {
        std::array<double, 10> abilities = {0.8, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3};
        std::array<double, 10> diffs = {0.3, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8};
        User u = makeUserNonUniform(abilities);
        Text t = makeTextNonUniform(1, diffs);
        double delta = engine.calculateDifficultyGap(u, t);

        double expected = 0.0;
        for (int j = 0; j < 10; j++)
            expected += Config::CRITIC_WEIGHTS[j] * (diffs[j] - abilities[j]);
        REQUIRE(std::abs(delta - expected) < EPS);
    }
}

TEST_CASE("calculateProbability", "[engine]") {
    RecommendationEngine engine;

    SECTION("delta = delta_star, P = 1.0") {
        User u = makeUser(0.3);
        Text t = makeText(1, 0.43);
        double p = engine.calculateProbability(u, t);
        REQUIRE(std::abs(p - 1.0) < EPS);
    }

    SECTION("delta = delta_star + sigma") {
        User u = makeUser(0.3);
        Text t = makeText(1, 0.68);
        double p = engine.calculateProbability(u, t);
        REQUIRE(std::abs(p - std::exp(-0.5)) < EPS);
    }

    SECTION("delta = delta_star - sigma, 对称性") {
        User u = makeUser(0.55);
        Text t = makeText(1, 0.43);
        double p = engine.calculateProbability(u, t);
        REQUIRE(std::abs(p - std::exp(-0.5)) < EPS);
    }

    SECTION("delta = delta_star + 2*sigma") {
        User u = makeUser(0.3);
        Text t = makeText(1, 0.93);
        double p = engine.calculateProbability(u, t);
        REQUIRE(std::abs(p - std::exp(-2.0)) < EPS);
    }

    SECTION("最大 realistic gap") {
        User u = makeUser(0.0);
        Text t = makeText(1, 1.0);
        double p = engine.calculateProbability(u, t);
        REQUIRE(p < 0.01);
        REQUIRE(p > 0.001);
    }
}

TEST_CASE("recommend", "[engine]") {
    RecommendationEngine engine;
    User u = makeUser(0.5);

    double diffs[5] = {0.63, 0.50, 0.80, 0.88, 0.30};
    std::vector<Text> texts;
    for (int i = 0; i < 5; i++) {
        Text t;
        t.setId(i + 1);
        for (int j = 0; j < 10; j++)
            t.setDifficulty(j, diffs[i]);
        texts.push_back(t);
    }

    SECTION("正常排序 + topK") {
        auto result = engine.recommend(u, texts, 3);
        REQUIRE(result.size() == 3);
        REQUIRE(result[0].first == 1);
        REQUIRE(result[1].first == 2);
        REQUIRE(result[2].first == 3);
        REQUIRE(std::abs(result[0].second - expectedProb(0.5, 0.63)) < EPS);
        REQUIRE(std::abs(result[1].second - expectedProb(0.5, 0.50)) < EPS);
        REQUIRE(std::abs(result[2].second - expectedProb(0.5, 0.80)) < EPS);
    }

    SECTION("空列表") {
        std::vector<Text> empty;
        auto result = engine.recommend(u, empty, 10);
        REQUIRE(result.empty());
    }

    SECTION("topK > N") {
        std::vector<Text> few;
        for (int i = 0; i < 2; i++) {
            Text t;
            t.setId(i + 1);
            t.setDifficulty(0, 0.5);
            few.push_back(t);
        }
        auto result = engine.recommend(u, few, 10);
        REQUIRE(result.size() == 2);
    }

    SECTION("topK = 0") {
        auto result = engine.recommend(u, texts, 0);
        REQUIRE(result.empty());
    }
}
