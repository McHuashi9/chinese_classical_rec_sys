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

    SECTION("负增量（quiz 答错）同样被合并进基础能力") {
        repo.addIncrement(USER_ID, 1, -0.06, 0, "quiz");
        time_t currentTime = 800 * 86400;
        double psi = std::pow(1.0 + 800.0 / Config::TAU, -Config::C);
        int pruned = tracker.pruneOldIncrements(user, currentTime);
        REQUIRE(pruned == 1);
        double expectedBase = 0.3 - 0.06 * psi;
        REQUIRE(std::abs(user.getBaseAbility(0) - expectedBase) < EPS);
        REQUIRE(repo.getIncrementCount(USER_ID) == 0);
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

// =============================================================================
// 答题效应（论文§5.3：Δu_j^quiz = K_j(t)·(s - E[s_j])）
// =============================================================================

TEST_CASE_METHOD(KTFixture, "applyQuizEffect", "[tracker][quiz]") {
    const std::vector<int> dims = {3, 4, 9};  // shici 题型：d4, d5, d10（0-based）

    SECTION("答对上调能力") {
        tracker.applyQuizEffect(user, text, dims, 1, now);
        for (int j : dims) {
            REQUIRE(user.getAbility(j) > 0.3);
            REQUIRE(user.getQuizCount(j) == 1);
        }
        REQUIRE(user.getEta() > Config::ETA);  // 答对 → 悟性提升
    }

    SECTION("答错下调能力（校正性修正）") {
        tracker.applyQuizEffect(user, text, dims, 0, now);
        for (int j : dims) {
            REQUIRE(user.getAbility(j) < 0.3);
            REQUIRE(user.getQuizCount(j) == 1);
        }
        REQUIRE(user.getEta() < Config::ETA);  // 答错 → 悟性下降
    }

    SECTION("能力=难度时 E[s]=0.5，增量 = ±K0/2") {
        // u_j = d_j = 0.5 → E[s_j] = 0.5；K = K0（N_j=0）
        for (int j : dims)
            user.setAbility(j, 0.5);
        tracker.applyQuizEffect(user, text, dims, 1, now);
        double expected = 0.5 + Config::QUIZ_K0 * 0.5;
        for (int j : dims)
            REQUIRE(std::abs(user.getAbility(j) - expected) < EPS);
    }

    SECTION("K 因子随答题次数衰减") {
        // 第 1 次答题：K = K0；第 N 次：K = max(K_min, K0/(1+λK·N))
        for (int j : dims)
            user.setQuizCount(j, 10);
        tracker.applyQuizEffect(user, text, dims, 1, now);
        double k_expected = std::max(Config::QUIZ_K_MIN,
                                     Config::QUIZ_K0 / (1.0 + Config::QUIZ_LAMBDA_K * 10));
        // 此处 u_j = 0.3（先验），d_j = 0.5（text 特征）
        double e = 1.0 / (1.0 + std::exp(-Config::QUIZ_BETA * (0.3 - 0.5)));
        double expected = 0.3 + k_expected * (1.0 - e);
        for (int j : dims)
            REQUIRE(std::abs(user.getAbility(j) - expected) < EPS);
    }

    SECTION("负增量入库（答错真实拉低能力）") {
        tracker.applyQuizEffect(user, text, dims, 0, now);
        auto incs = repo.getAllIncrements(USER_ID);
        REQUIRE(incs.size() == dims.size());
        for (const auto& inc : incs) {
            REQUIRE(inc.type == "quiz");
            REQUIRE(inc.delta < 0);
        }
    }

    SECTION("悟性有界（连答错 → η 触及下限）") {
        user.setEta(Config::ETA_MIN + 0.001);
        tracker.applyQuizEffect(user, text, dims, 0, now);
        REQUIRE(user.getEta() >= Config::ETA_MIN);
        REQUIRE(user.getEta() <= Config::ETA_MAX);
    }

    SECTION("重复维度去重（防脏数据重复应用/计数）") {
        const std::vector<int> dupDims = {3, 3, 4, 4, 9};
        tracker.applyQuizEffect(user, text, dupDims, 1, now);
        for (int j : dims) {
            REQUIRE(user.getQuizCount(j) == 1);  // 只计一次
        }
        // 效果与单次应用一致（非重复应用两倍增量）
        for (int j : dims) {
            REQUIRE(user.getAbility(j) > 0.3);
            REQUIRE(user.getAbility(j) < 0.3 + Config::QUIZ_K0 + EPS);
        }
        REQUIRE(repo.getIncrementCount(USER_ID) == static_cast<int>(dims.size()));
    }
}

// =============================================================================
// 跨效应状态流：read → quiz → forgetting → prune 连续多步
// =============================================================================

TEST_CASE_METHOD(KTFixture, "跨效应状态流：主链 read→quiz对→forgetting→prune", "[tracker][quiz]") {
    const std::vector<int> dims = {3, 4, 9};

    // 预计算期望值（与各单测同一公式，验证跨效应叠加）
    const double u0 = 0.3;
    const double eta_t = 0.08 * std::pow(1.0 - u0, 1.5);
    const double g3 = std::exp(-((0.5 - u0) - Config::DELTA_STAR) *
                               ((0.5 - u0) - Config::DELTA_STAR) /
                               (2 * Config::SIGMA * Config::SIGMA));
    const double readDelta3 = eta_t * g3 * (1.0 - u0);
    const double uAfterRead3 = u0 + readDelta3;
    const double e3 = 1.0 / (1.0 + std::exp(-Config::QUIZ_BETA * (uAfterRead3 - 0.5)));
    const double quizDelta3 = Config::QUIZ_K0 * (1.0 - e3);
    const double psi10 = std::pow(1.0 + 10.0 / Config::TAU, -Config::C);
    const double psi800 = std::pow(1.0 + 800.0 / Config::TAU, -Config::C);

    // 1) 阅读：全 10 维正增量
    tracker.applyReadEffect(user, text, 60.0, now);
    REQUIRE(repo.getIncrementCount(USER_ID) == 10);
    REQUIRE(std::abs(user.getAbility(3) - uAfterRead3) < EPS);

    // 2) 答对：d3 与已有 read 增量共存（13 = 10 read + 3 quiz）
    tracker.applyQuizEffect(user, text, dims, 1, now);
    REQUIRE(repo.getIncrementCount(USER_ID) == 13);
    REQUIRE(user.getQuizCount(3) == 1);
    REQUIRE(std::abs(user.getAbility(3) - (uAfterRead3 + quizDelta3)) < EPS);

    // 3) 遗忘：增量按 ψ(10d) 衰减但不删除（10 天 ψ≈0.615 > PSI_MIN）
    tracker.applyForgettingEffect(user, now + 10 * 86400);
    REQUIRE(repo.getIncrementCount(USER_ID) == 13);
    REQUIRE(std::abs(user.getAbility(3) -
                     (u0 + (readDelta3 + quizDelta3) * psi10)) < EPS);

    // 4) 裁剪：800 天 ψ<PSI_MIN，全部合并进基础能力（正负都合）
    const int pruned = tracker.pruneOldIncrements(user, now + 800 * 86400);
    REQUIRE(pruned == 13);
    REQUIRE(repo.getIncrementCount(USER_ID) == 0);
    REQUIRE(std::abs(user.getBaseAbility(3) -
                     (u0 + (readDelta3 + quizDelta3) * psi800)) < EPS);
    REQUIRE(user.getQuizCount(3) == 1);  // quiz_count 不随裁剪丢失
}

TEST_CASE_METHOD(KTFixture, "跨效应状态流：分支 quiz答错 → 同维正负增量共存", "[tracker][quiz]") {
    const std::vector<int> dims = {3, 4, 9};

    // 1) 阅读后答错：d3 同时有 read 正增量与 quiz 负增量
    tracker.applyReadEffect(user, text, 60.0, now);
    const double uAfterRead3 = user.getAbility(3);
    tracker.applyQuizEffect(user, text, dims, 0, now);
    REQUIRE(user.getAbility(3) < uAfterRead3);  // 答错真实拉低（覆盖正增量）

    // 同维正负增量在 repo 中共存
    const auto incs = repo.getAllIncrements(USER_ID);
    int d3Read = 0, d3QuizNeg = 0;
    for (const auto& inc : incs) {
        if (inc.dimension == 4) {  // 1-based: 维度 3
            if (inc.type == "read" && inc.delta > 0) d3Read++;
            if (inc.type == "quiz" && inc.delta < 0) d3QuizNeg++;
        }
    }
    REQUIRE(d3Read == 1);
    REQUIRE(d3QuizNeg == 1);

    // 2) 裁剪：净值合入基础能力（quiz 负增量占优 → 基础能力低于先验）
    const int pruned = tracker.pruneOldIncrements(user, now + 800 * 86400);
    REQUIRE(pruned == 13);
    REQUIRE(user.getBaseAbility(3) < 0.3 - EPS);
    // 纯 quiz 负增量的维度也低于先验
    REQUIRE(user.getBaseAbility(4) < 0.3 - EPS);
    // 纯 read 维度（无 quiz）：仅正增量合入
    const double psi800 = std::pow(1.0 + 800.0 / Config::TAU, -Config::C);
    const double u0 = 0.3;
    const double eta_t = 0.08 * std::pow(1.0 - u0, 1.5);
    const double g = std::exp(-((0.5 - u0) - Config::DELTA_STAR) *
                              ((0.5 - u0) - Config::DELTA_STAR) /
                              (2 * Config::SIGMA * Config::SIGMA));
    const double readDelta = eta_t * g * (1.0 - u0);
    REQUIRE(std::abs(user.getBaseAbility(0) - (u0 + readDelta * psi800)) < EPS);
}
