#include <catch_amalgamated.hpp>
#include "core/KnowledgeTracker.h"
#include "core/Config.h"
#include "database/DatabaseManager.h"
#include "database/LearningIncrementRepository.h"
#include "models/User.h"
#include "models/Text.h"
#include <cmath>
#include <ctime>
#include <vector>

/**
 * @brief 集成测试：知识追踪器
 *
 * 测试范围：
 * - calculateCurrentAbility 基于历史增量的能力计算
 * - applyForgettingEffect 遗忘效应应用
 * - pruneOldIncrements 增量清理与合并
 * - 综合场景：完整学习增量工作流
 */

constexpr double EPSILON = 1e-4;

struct TrackerTestFixture {
    DatabaseManager db;
    LearningIncrementRepository incrementRepo{&db};
    KnowledgeTracker tracker{&incrementRepo};

    TrackerTestFixture() {
        db.open(":memory:");
        incrementRepo.initTable();
    }

    ~TrackerTestFixture() {
        db.close();
    }
};

// =============================================================================
// calculateCurrentAbility 测试
// =============================================================================

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::calculateCurrentAbility - 无增量时回复基础能力", "[tracker]") {
    User user;
    user.initializeDefault();
    std::vector<LearningIncrement> empty;
    double ability = tracker.calculateCurrentAbility(user, 0, empty, std::time(nullptr));
    REQUIRE(std::abs(ability - 0.3) < EPSILON);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::calculateCurrentAbility - 有增量时能力增加", "[tracker]") {
    time_t now = std::time(nullptr);
    time_t t0 = now - 3600;  // 1小时前

    incrementRepo.addIncrement(1, 1, 0.05, t0, "read");

    User user;
    user.initializeDefault();
    user.setBaseAbility(0, 0.3);
    user.setAbility(0, 0.3);

    auto incs = incrementRepo.getIncrements(1, 1);
    REQUIRE(incs.size() == 1);

    double ability = tracker.calculateCurrentAbility(user, 0, incs, now);
    // 1小时内遗忘很小，所以能力应该 > 基础能力
    REQUIRE(ability > 0.3);
    REQUIRE(ability <= 1.0);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::calculateCurrentAbility - 增量随遗忘衰减", "[tracker]") {
    time_t now = 1714435200;  // 固定时间

    // 添加很久以前的增量
    time_t oldTime = now - 30 * 86400;  // 30天前
    incrementRepo.addIncrement(1, 1, 0.05, oldTime, "read");

    // 添加最近的增量
    time_t recentTime = now - 3600;  // 1小时前
    incrementRepo.addIncrement(1, 1, 0.05, recentTime, "read");

    User user;
    user.initializeDefault();
    user.setBaseAbility(0, 0.3);
    user.setAbility(0, 0.3);

    auto incs = incrementRepo.getIncrements(1, 1);
    REQUIRE(incs.size() == 2);

    double ability = tracker.calculateCurrentAbility(user, 0, incs, now);
    REQUIRE(ability > 0.3);
    REQUIRE(ability <= 1.0);

    // 有遗忘的系统应该 < 无遗忘的总和 (0.3 + 0.05 + 0.05 = 0.4)
    REQUIRE(ability < 0.4);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::calculateCurrentAbility - 约束在 [0, 1]", "[tracker]") {
    time_t now = std::time(nullptr);

    // 大量增量
    for (int i = 0; i < 100; i++) {
        incrementRepo.addIncrement(1, 1, 0.1, now, "read");
    }

    User user;
    user.setBaseAbility(0, 0.8);
    user.setAbility(0, 0.8);

    auto incs = incrementRepo.getIncrements(1, 1);
    double ability = tracker.calculateCurrentAbility(user, 0, incs, now);
    REQUIRE(ability >= 0.0);
    REQUIRE(ability <= 1.0);
}

// =============================================================================
// applyForgettingEffect 测试
// =============================================================================

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyForgettingEffect - 无增量时能力不变", "[tracker]") {
    User user;
    user.initializeDefault();
    double before = user.getAverageAbility();

    tracker.applyForgettingEffect(user, std::time(nullptr));

    double after = user.getAverageAbility();
    REQUIRE(std::abs(before - after) < EPSILON);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyForgettingEffect - 近期增量维持高能力", "[tracker]") {
    time_t now = std::time(nullptr);
    time_t t0 = now - 60;  // 1分钟前

    for (int j = 0; j < 10; j++) {
        incrementRepo.addIncrement(1, j + 1, 0.05, t0, "read");
    }

    User user;
    user.initializeDefault();

    double before = user.getAverageAbility();
    tracker.applyForgettingEffect(user, now);
    double after = user.getAverageAbility();

    // 近期增量应使能力上升
    REQUIRE(after > before);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyForgettingEffect - 远久增量能力下降", "[tracker]") {
    time_t now = 1714435200;
    time_t oldTime = now - 100 * 86400;  // 100天前

    for (int j = 0; j < 10; j++) {
        incrementRepo.addIncrement(1, j + 1, 0.05, oldTime, "read");
    }

    User user;
    user.initializeDefault();

    tracker.applyForgettingEffect(user, now);
    double after = user.getAverageAbility();

    // 100天后，增量遗忘接近完全，能力应接近基础能力 0.3
    REQUIRE(after >= 0.29);
    REQUIRE(after < 0.32);
}

// =============================================================================
// pruneOldIncrements 测试
// =============================================================================

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::pruneOldIncrements - 过期增量被清理", "[tracker]") {
    time_t now = 1714435200;
    time_t veryOld = now - 1000 * 86400;  // 1000天前

    // 添加一些很旧的增量
    incrementRepo.addIncrement(1, 1, 0.05, veryOld, "read");
    incrementRepo.addIncrement(1, 2, 0.03, veryOld, "read");

    int countBefore = incrementRepo.getIncrementCount(1);
    REQUIRE(countBefore == 2);

    User user;
    user.initializeDefault();

    int pruned = tracker.pruneOldIncrements(user, now);
    REQUIRE(pruned == 2);  // 两条都过期

    // 增量应被删除
    REQUIRE(incrementRepo.getIncrementCount(1) == 0);

    // 基础能力应更新
    // 1000天后 psi < PSI_MIN (0.05)，所以增量被合并到基础能力
    REQUIRE(user.getBaseAbility(0) > 0.3);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::pruneOldIncrements - 近期增量不被清理", "[tracker]") {
    time_t now = std::time(nullptr);
    time_t recent = now - 3600;  // 1小时前

    incrementRepo.addIncrement(1, 1, 0.05, recent, "read");

    User user;
    user.initializeDefault();

    int pruned = tracker.pruneOldIncrements(user, now);
    REQUIRE(pruned == 0);  // 近期增量不应被清理
    REQUIRE(incrementRepo.getIncrementCount(1) == 1);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::pruneOldIncrements - 无增量时返回 0", "[tracker]") {
    User user;
    user.initializeDefault();

    int pruned = tracker.pruneOldIncrements(user, std::time(nullptr));
    REQUIRE(pruned == 0);
}

// =============================================================================
// applyReadEffect 综合测试
// =============================================================================

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyReadEffect - 阅读触发能力更新", "[tracker]") {
    User user;
    user.initializeDefault();

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.43);  // 略高于用户初始能力
    }

    double before = user.getAverageAbility();
    tracker.applyReadEffect(user, text, Config::MIN_READ_TIME, std::time(nullptr));
    double after = user.getAverageAbility();

    // 阅读应使能力提升
    REQUIRE(after > before);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyReadEffect - 阅读时间不足阈值时不触发", "[tracker]") {
    User user;
    user.initializeDefault();

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.5);
    }

    double before = user.getAverageAbility();
    tracker.applyReadEffect(user, text, Config::MIN_READ_TIME - 1, std::time(nullptr));
    double after = user.getAverageAbility();

    // 阅读时间不足，能力应不变
    REQUIRE(std::abs(before - after) < EPSILON);
}

TEST_CASE_METHOD(TrackerTestFixture, "KnowledgeTracker::applyReadEffect - 有意义的增量被记录", "[tracker]") {
    User user;
    user.initializeDefault();

    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.5);
    }

    int countBefore = incrementRepo.getIncrementCount(1);
    tracker.applyReadEffect(user, text, Config::MIN_READ_TIME, std::time(nullptr));
    int countAfter = incrementRepo.getIncrementCount(1);

    REQUIRE(countAfter >= countBefore + 1);  // 应有增量被记录
}

// =============================================================================
// 完整工作流测试
// =============================================================================

TEST_CASE_METHOD(TrackerTestFixture, "知识追踪完整工作流", "[tracker][integration]") {
    time_t now = std::time(nullptr);

    // 1. 初始化用户
    User user;
    user.initializeDefault();
    REQUIRE(std::abs(user.getAverageAbility() - 0.3) < EPSILON);

    // 2. 阅读文章 (难度略高于能力)
    Text text;
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.43);
    }
    tracker.applyReadEffect(user, text, Config::MIN_READ_TIME, now);

    double abilityAfterRead = user.getAverageAbility();
    REQUIRE(abilityAfterRead > 0.3);  // 能力提升

    // 3. 应用遗忘效应（短期内不影响）
    tracker.applyForgettingEffect(user, now + 86400);  // 1天后
    double abilityAfter1Day = user.getAverageAbility();
    REQUIRE(abilityAfter1Day >= 0.3);  // 1天遗忘轻微

    // 4. 清理过期增量（短期不应清理）
    int pruned = tracker.pruneOldIncrements(user, now + 86400);
    REQUIRE(pruned == 0);  // 不应清理
    REQUIRE(incrementRepo.getIncrementCount(1) >= 1);

    // 5. 远未来清理过期增量
    time_t farFuture = now + 1000 * 86400;  // 1000天后
    int prunedLater = tracker.pruneOldIncrements(user, farFuture);
    REQUIRE(prunedLater > 0);  // 应该清理了
    REQUIRE(incrementRepo.getIncrementCount(1) == 0);

    // 基础能力应已更新
    bool baseUpdated = false;
    for (int i = 0; i < 10; i++) {
        if (user.getBaseAbility(i) > 0.3) {
            baseUpdated = true;
            break;
        }
    }
    REQUIRE(baseUpdated);
}
