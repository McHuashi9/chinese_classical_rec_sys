#include <catch_amalgamated.hpp>
#include "models/User.h"
#include "models/Text.h"
#include "utils/FeatureExtractor.h"
#include <cmath>

constexpr double EPS = 1e-4;

TEST_CASE("User 模型", "[model]") {
    SECTION("默认构造") {
        User u;
        for (int j = 0; j < 10; j++) {
            REQUIRE(std::abs(u.getAbility(j)) < EPS);
            REQUIRE(std::abs(u.getBaseAbility(j)) < EPS);
        }
        REQUIRE(std::abs(u.getAverageAbility()) < EPS);
    }

    SECTION("initializeDefault") {
        User u;
        u.initializeDefault();
        for (int j = 0; j < 10; j++) {
            REQUIRE(std::abs(u.getAbility(j) - 0.3) < EPS);
            REQUIRE(std::abs(u.getBaseAbility(j) - 0.3) < EPS);
        }
        REQUIRE(std::abs(u.getAverageAbility() - 0.3) < EPS);
    }

    SECTION("hasAnyNonDefaultField") {
        User fresh;
        REQUIRE_FALSE(fresh.hasAnyNonDefaultField());

        User learned;
        learned.initializeDefault();
        REQUIRE(learned.hasAnyNonDefaultField());

        User allZeroButBase;
        allZeroButBase.setBaseAbility(0, 0.3);
        REQUIRE(allZeroButBase.hasAnyNonDefaultField());

        User withHistory;
        withHistory.setLastReadTime(1);
        REQUIRE(withHistory.hasAnyNonDefaultField());

        User withQuiz;
        withQuiz.setQuizCount(5, 2);
        REQUIRE(withQuiz.hasAnyNonDefaultField());
    }

    SECTION("set/getAbility") {
        User u;
        u.setAbility(3, 0.75);
        REQUIRE(std::abs(u.getAbility(3) - 0.75) < EPS);
        for (int j = 0; j < 10; j++) {
            if (j != 3)
                REQUIRE(std::abs(u.getAbility(j)) < EPS);
        }
    }

    SECTION("越界索引 set") {
        User u;
        u.setAbility(-1, 0.5);
        u.setAbility(10, 0.5);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(u.getAbility(j)) < EPS);
    }

    SECTION("越界索引 get") {
        User u;
        REQUIRE(std::abs(u.getAbility(-1)) < EPS);
        REQUIRE(std::abs(u.getAbility(10)) < EPS);
    }

    SECTION("能力 clamp 上限") {
        User u;
        u.setAbility(0, 1.5);
        REQUIRE(std::abs(u.getAbility(0) - 1.0) < EPS);
    }

    SECTION("能力 clamp 下限") {
        User u;
        u.setAbility(1, -0.5);
        REQUIRE(std::abs(u.getAbility(1)) < EPS);
    }

    SECTION("基础能力独立存储") {
        User u;
        u.setAbility(0, 0.9);
        u.setBaseAbility(0, 0.3);
        REQUIRE(std::abs(u.getAbility(0) - 0.9) < EPS);
        REQUIRE(std::abs(u.getBaseAbility(0) - 0.3) < EPS);
    }

    SECTION("getAverageAbility") {
        User u;
        for (int j = 0; j < 10; j++)
            u.setAbility(j, (j + 1) * 0.1);
        REQUIRE(std::abs(u.getAverageAbility() - 0.55) < EPS);
    }
}

TEST_CASE("Text 模型", "[model]") {
    SECTION("默认构造") {
        Text t;
        REQUIRE(t.getId() == 0);
        REQUIRE(t.getCharCount() == 0);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(t.getDifficulty(j)) < EPS);
    }

    SECTION("setId/getId") {
        Text t;
        t.setId(42);
        REQUIRE(t.getId() == 42);
    }

    SECTION("getter/setter") {
        Text t;
        t.setTitle("标题");
        t.setAuthor("作者");
        t.setDynasty("唐代");
        t.setCharCount(500);
        REQUIRE(t.getTitle() == "标题");
        REQUIRE(t.getAuthor() == "作者");
        REQUIRE(t.getDynasty() == "唐代");
        REQUIRE(t.getCharCount() == 500);
    }

    SECTION("setDifficulty/getDifficulty") {
        Text t;
        t.setDifficulty(5, 0.8);
        REQUIRE(std::abs(t.getDifficulty(5) - 0.8) < EPS);
        for (int j = 0; j < 10; j++) {
            if (j != 5)
                REQUIRE(std::abs(t.getDifficulty(j)) < EPS);
        }
    }

    SECTION("越界 set") {
        Text t;
        t.setDifficulty(-1, 0.5);
        t.setDifficulty(10, 0.5);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(t.getDifficulty(j)) < EPS);
    }

    SECTION("越界 get") {
        Text t;
        REQUIRE(std::abs(t.getDifficulty(-1)) < EPS);
        REQUIRE(std::abs(t.getDifficulty(10)) < EPS);
    }

    SECTION("10 维独立") {
        Text t;
        for (int j = 0; j < 10; j++)
            t.setDifficulty(j, (j + 1) * 0.1);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(t.getDifficulty(j) - (j + 1) * 0.1) < EPS);
    }
}

TEST_CASE("FeatureExtractor", "[model]") {
    SECTION("返回 10 维") {
        Text t;
        for (int j = 0; j < 10; j++)
            t.setDifficulty(j, (j + 1) * 0.1);
        auto features = FeatureExtractor::getNormalizedFeatures(t);
        REQUIRE(features.size() == 10);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(features[j] - (j + 1) * 0.1) < EPS);
    }
}
