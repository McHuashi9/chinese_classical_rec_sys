#include <catch_amalgamated.hpp>
#include "core/KnowledgeTracker.h"
#include "core/Config.h"
#include "models/User.h"
#include "models/Text.h"
#include "database/DatabaseManager.h"
#include "database/LearningIncrementRepository.h"
#include <cmath>
#include <vector>
#include <ctime>

constexpr double EPS = 1e-4;
constexpr int USER_ID = 1;

struct KTFixture {
    DatabaseManager db;
    LearningIncrementRepository repo;
    KnowledgeTracker tracker;
    User user;
    Text text;
    time_t now;

    KTFixture()
        : repo(&db), tracker(&repo), now(1000000) {
        db.open(":memory:");
        repo.initTable();
        user.initializeDefault();
        text.setId(1);
        for (int i = 0; i < 10; i++)
            text.setDifficulty(i, 0.5);
    }
};

TEST_CASE_METHOD(KTFixture, "applyReadEffect", "[tracker]") {
    SECTION("阅读时间不足") {
        tracker.applyReadEffect(user, text, 10.0, now);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(user.getAbility(j) - 0.3) < EPS);
        REQUIRE(repo.getIncrementCount(USER_ID) == 0);
    }

    SECTION("正常阅读") {
        tracker.applyReadEffect(user, text, 60.0, now);
        double u_j = user.getAbility(0);
        double d_j = 0.5;
        double avgAbility = 0.3;
        double eta_t = 0.08 * std::pow(1.0 - avgAbility, 1.5);
        double g_j = std::exp(-((d_j - 0.3) - Config::DELTA_STAR) *
                              ((d_j - 0.3) - Config::DELTA_STAR) /
                              (2 * Config::SIGMA * Config::SIGMA));
        double delta = eta_t * g_j * (1.0 - 0.3);
        double expected = 0.3 + delta;
        REQUIRE(std::abs(u_j - expected) < EPS);
        REQUIRE(repo.getIncrementCount(USER_ID) == 10);
    }

    SECTION("已达上限不增长") {
        for (int j = 0; j < 10; j++)
            user.setAbility(j, 1.0);
        tracker.applyReadEffect(user, text, 60.0, now);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(user.getAbility(j) - 1.0) < EPS);
        REQUIRE(repo.getIncrementCount(USER_ID) == 0);
    }

    SECTION("delta 小于阈值不入库") {
        for (int j = 0; j < 10; j++)
            user.setAbility(j, 0.95);
        tracker.applyReadEffect(user, text, 60.0, now);
        REQUIRE(repo.getIncrementCount(USER_ID) == 0);
    }
}

TEST_CASE_METHOD(KTFixture, "calculateCurrentAbility", "[tracker]") {
    SECTION("无增量") {
        std::vector<LearningIncrement> increments;
        double result = tracker.calculateCurrentAbility(user, 0, increments, now);
        REQUIRE(std::abs(result - 0.3) < EPS);
    }

    SECTION("单增量刚发生") {
        LearningIncrement inc;
        inc.id = 1;
        inc.userId = USER_ID;
        inc.dimension = 1;
        inc.delta = 0.05;
        inc.timestamp = now;
        inc.type = "read";
        std::vector<LearningIncrement> increments = {inc};
        double result = tracker.calculateCurrentAbility(user, 0, increments, now);
        REQUIRE(std::abs(result - 0.35) < EPS);
    }

    SECTION("单增量加 psi 衰减") {
        LearningIncrement inc;
        inc.id = 1;
        inc.userId = USER_ID;
        inc.dimension = 1;
        inc.delta = 0.05;
        inc.timestamp = 0;
        inc.type = "read";
        std::vector<LearningIncrement> increments = {inc};
        time_t currentTime = 10 * 86400;
        double psi = std::pow(1.0 + 10.0 / Config::TAU, -Config::C);
        double expected = 0.3 + 0.05 * psi;
        double result = tracker.calculateCurrentAbility(user, 0, increments, currentTime);
        REQUIRE(std::abs(result - expected) < EPS);
    }

    SECTION("两增量不同时间") {
        user.setBaseAbility(0, 0.2);
        LearningIncrement inc1;
        inc1.id = 1;
        inc1.userId = USER_ID;
        inc1.dimension = 1;
        inc1.delta = 0.03;
        inc1.timestamp = now - 5 * 86400;
        inc1.type = "read";
        LearningIncrement inc2;
        inc2.id = 2;
        inc2.userId = USER_ID;
        inc2.dimension = 1;
        inc2.delta = 0.04;
        inc2.timestamp = now - 30 * 86400;
        inc2.type = "read";
        std::vector<LearningIncrement> increments = {inc1, inc2};
        double psi5 = std::pow(1.0 + 5.0 / Config::TAU, -Config::C);
        double psi30 = std::pow(1.0 + 30.0 / Config::TAU, -Config::C);
        double expected = 0.2 + 0.03 * psi5 + 0.04 * psi30;
        double result = tracker.calculateCurrentAbility(user, 0, increments, now);
        REQUIRE(std::abs(result - expected) < EPS);
    }

    SECTION("clamp 上限") {
        user.setBaseAbility(0, 0.9);
        LearningIncrement inc;
        inc.id = 1;
        inc.userId = USER_ID;
        inc.dimension = 1;
        inc.delta = 0.20;
        inc.timestamp = now;
        inc.type = "read";
        std::vector<LearningIncrement> increments = {inc};
        double result = tracker.calculateCurrentAbility(user, 0, increments, now);
        REQUIRE(std::abs(result - 1.0) < EPS);
    }
}

TEST_CASE_METHOD(KTFixture, "applyForgettingEffect", "[tracker]") {
    SECTION("空 repo 早返回") {
        for (int j = 0; j < 10; j++)
            user.setAbility(j, 0.5);
        tracker.applyForgettingEffect(user, now);
        for (int j = 0; j < 10; j++)
            REQUIRE(std::abs(user.getAbility(j) - 0.5) < EPS);
    }

    SECTION("单维增量") {
        repo.addIncrement(USER_ID, 1, 0.05, now, "read");
        tracker.applyForgettingEffect(user, now);
        REQUIRE(std::abs(user.getAbility(0) - 0.35) < EPS);
        for (int j = 1; j < 10; j++)
            REQUIRE(std::abs(user.getAbility(j) - 0.3) < EPS);
    }
}

TEST_CASE_METHOD(KTFixture, "pruneOldIncrements", "[tracker]") {
    SECTION("空 repo") {
        int pruned = tracker.pruneOldIncrements(user, now);
        REQUIRE(pruned == 0);
        REQUIRE(std::abs(user.getBaseAbility(0) - 0.3) < EPS);
    }

    SECTION("新增量不裁剪") {
        repo.addIncrement(USER_ID, 1, 0.05, now, "read");
        int pruned = tracker.pruneOldIncrements(user, now);
        REQUIRE(pruned == 0);
    }

    SECTION("老增量裁剪合并") {
        repo.addIncrement(USER_ID, 1, 0.05, 0, "read");
        time_t currentTime = 800 * 86400;
        double psi = std::pow(1.0 + 800.0 / Config::TAU, -Config::C);
        int pruned = tracker.pruneOldIncrements(user, currentTime);
        REQUIRE(pruned == 1);
        double expectedBase = 0.3 + 0.05 * psi;
        REQUIRE(std::abs(user.getBaseAbility(0) - expectedBase) < EPS);
        REQUIRE(repo.getIncrementCount(USER_ID) == 0);
    }

    SECTION("新老混合") {
        time_t pruneTime = 800 * 86400;
        repo.addIncrement(USER_ID, 1, 0.05, 0, "read");
        repo.addIncrement(USER_ID, 2, 0.03, pruneTime, "read");
        int pruned = tracker.pruneOldIncrements(user, pruneTime);
        REQUIRE(pruned == 1);
        REQUIRE(repo.getIncrementCount(USER_ID) == 1);
        double psi = std::pow(1.0 + 800.0 / Config::TAU, -Config::C);
        double expectedBase = 0.3 + 0.05 * psi;
        REQUIRE(std::abs(user.getBaseAbility(0) - expectedBase) < EPS);
    }
}

TEST_CASE("KnowledgeTracker nullptr repo", "[tracker]") {
    KnowledgeTracker tracker(nullptr);
    User user;
    Text text;
    tracker.applyReadEffect(user, text, 60.0, 0);
    tracker.applyForgettingEffect(user, 0);
    REQUIRE(tracker.pruneOldIncrements(user, 0) == 0);
}
