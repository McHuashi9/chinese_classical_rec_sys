#include <catch_amalgamated.hpp>

#include "core/Config.h"
#include "core/ReviewScheduler.h"
#include "database/QuizRepository.h"

#include <fstream>
#include <iterator>
#include <set>
#include <string>
#include <vector>

// v1.4.0 工作项 2/3 的纯逻辑验收：
// - ReviewScheduler：间隔倍增/封顶、掌握判定、到期边界、答错后首次到期（无 DB 依赖）
// - q_key 单一来源：C++ 侧 initQKeys() 与 scripts/project/check_content_db.py 的 INIT_Q_KEYS 对拍
//   （路径由 tests/CMakeLists.txt 的 CHECK_CONTENT_DB_PATH 注入）

TEST_CASE("ReviewScheduler - 间隔倍增与封顶", "[core][scheduler]") {
    constexpr int64_t base = Config::REVIEW_BASE_INTERVAL;
    constexpr int64_t maxInterval = Config::REVIEW_MAX_INTERVAL;

    REQUIRE(ReviewScheduler::intervalAfter(0) == base);
    REQUIRE(ReviewScheduler::intervalAfter(1) == base * 2);
    REQUIRE(ReviewScheduler::intervalAfter(2) == base * 4);
    REQUIRE(ReviewScheduler::intervalAfter(3) == base * 8);
    // 4 次翻倍 = 48 天 > 30 天封顶 → 直接返回封顶值
    REQUIRE(ReviewScheduler::intervalAfter(4) == maxInterval);
    REQUIRE(ReviewScheduler::intervalAfter(10) == maxInterval);
    // 超过循环上限（10 次）仍封顶，不溢出
    REQUIRE(ReviewScheduler::intervalAfter(1000) == maxInterval);
    // 负数 streak 视为 0（仅基础间隔）
    REQUIRE(ReviewScheduler::intervalAfter(-1) == base);
}

TEST_CASE("ReviewScheduler - 掌握判定与到期边界", "[core][scheduler]") {
    const int masterStreak = Config::REVIEW_MASTER_STREAK;
    REQUIRE(masterStreak >= 1);

    // 再答对一次达到/超过阈值即视为掌握（原 bridge 条件：streak + 1 >= REVIEW_MASTER_STREAK）
    REQUIRE(ReviewScheduler::isMasteredAfterCorrect(masterStreak - 1));
    REQUIRE(ReviewScheduler::isMasteredAfterCorrect(masterStreak));
    if (masterStreak >= 2) {
        REQUIRE_FALSE(ReviewScheduler::isMasteredAfterCorrect(masterStreak - 2));
    }

    REQUIRE(ReviewScheduler::isDue(100, 100));
    REQUIRE(ReviewScheduler::isDue(99, 100));
    REQUIRE_FALSE(ReviewScheduler::isDue(101, 100));

    REQUIRE(ReviewScheduler::dueAfterWrong(1000) == 1000 + Config::REVIEW_BASE_INTERVAL);
}

TEST_CASE("q_key 单一来源与 check_content_db.py INIT_Q_KEYS 对拍", "[database][qkey]") {
    const std::vector<std::string>& cppKeys = initQKeys();
    REQUIRE(cppKeys.size() == 6);
    const std::set<std::string> uniqueKeys(cppKeys.begin(), cppKeys.end());
    REQUIRE(uniqueKeys.size() == cppKeys.size());
    for (const auto& key : cppKeys) {
        REQUIRE_FALSE(key.empty());
    }

    std::ifstream in(CHECK_CONTENT_DB_PATH);
    REQUIRE(in.good());
    const std::string content((std::istreambuf_iterator<char>(in)),
                              std::istreambuf_iterator<char>());

    const size_t start = content.find("INIT_Q_KEYS = [");
    REQUIRE(start != std::string::npos);
    const size_t end = content.find(']', start);
    REQUIRE(end != std::string::npos);
    const std::string block = content.substr(start, end - start);

    std::vector<std::string> pythonKeys;
    size_t pos = 0;
    while ((pos = block.find('"', pos)) != std::string::npos) {
        const size_t close = block.find('"', pos + 1);
        REQUIRE(close != std::string::npos);
        pythonKeys.push_back(block.substr(pos + 1, close - pos - 1));
        pos = close + 1;
    }

    REQUIRE(pythonKeys == cppKeys);
}
