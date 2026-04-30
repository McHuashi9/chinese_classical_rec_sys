#include <catch_amalgamated.hpp>
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "models/User.h"
#include "models/Text.h"
#include <ctime>
#include <string>
#include <vector>

/**
 * @brief 集成测试：数据库 Repository 层
 *
 * 使用内存 SQLite 数据库测试所有 Repository 的 CRUD 操作
 */

struct RepoTestFixture {
    DatabaseManager db;
    UserRepository userRepo{&db};
    TextRepository textRepo{&db};
    ReadingHistoryRepository historyRepo{&db};
    LearningIncrementRepository incrementRepo{&db};

    RepoTestFixture() {
        db.open(":memory:");
        userRepo.initTable();
        textRepo.initTable();
        historyRepo.initTable();
        incrementRepo.initTable();
    }

    ~RepoTestFixture() {
        db.close();
    }
};

// =============================================================================
// DatabaseManager 测试
// =============================================================================

TEST_CASE("DatabaseManager - 打开和关闭数据库", "[database]") {
    DatabaseManager dbm;
    REQUIRE(dbm.open(":memory:"));
    REQUIRE(dbm.getConnection() != nullptr);
    REQUIRE(dbm.getLastError().empty());
    dbm.close();
    REQUIRE(dbm.getConnection() == nullptr);
}

TEST_CASE("DatabaseManager - 执行 SQL 语句", "[database]") {
    DatabaseManager dbm;
    dbm.open(":memory:");
    REQUIRE(dbm.executeSQL("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);"));
    REQUIRE(dbm.executeSQL("INSERT INTO test (name) VALUES (?);", std::vector<std::string>{"hello"}));
    dbm.close();
}

TEST_CASE("DatabaseManager - 执行带 REAL 参数的 SQL", "[database]") {
    DatabaseManager dbm;
    dbm.open(":memory:");
    REQUIRE(dbm.executeSQL("CREATE TABLE test (id INTEGER PRIMARY KEY, val REAL);"));
    REQUIRE(dbm.executeSQL("INSERT INTO test (val) VALUES (?);", std::vector<double>{3.14}));
    dbm.close();
}

TEST_CASE("DatabaseManager - 执行混合参数 SQL", "[database]") {
    DatabaseManager dbm;
    dbm.open(":memory:");
    REQUIRE(dbm.executeSQL("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, val REAL);"));
    std::vector<std::string> textParams{"foo"};
    std::vector<double> realParams{2.718};
    REQUIRE(dbm.executeSQL("INSERT INTO test (name, val) VALUES (?, ?);", textParams, realParams));
    dbm.close();
}

TEST_CASE("DatabaseManager - 执行 SqlParam 参数 SQL", "[database]") {
    DatabaseManager dbm;
    dbm.open(":memory:");
    REQUIRE(dbm.executeSQL("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, val REAL, cnt INTEGER);"));
    std::vector<SqlParam> params{std::string("abc"), 1.5, 42};
    REQUIRE(dbm.executeSQL("INSERT INTO test (name, val, cnt) VALUES (?, ?, ?);", params));
    dbm.close();
}

TEST_CASE("DatabaseManager - 未打开时操作失败", "[database]") {
    DatabaseManager dbm;
    REQUIRE_FALSE(dbm.executeSQL("CREATE TABLE test (id INTEGER PRIMARY KEY);"));
    REQUIRE(dbm.getLastError() == "数据库未打开");
}

// =============================================================================
// UserRepository 测试
// =============================================================================

TEST_CASE_METHOD(RepoTestFixture, "UserRepository - 保存和获取用户名", "[repository][user]") {
    REQUIRE(userRepo.saveUserName("测试用户"));
    User user;
    REQUIRE(userRepo.getUser(user));
    REQUIRE(user.getName() == "测试用户");
}

TEST_CASE_METHOD(RepoTestFixture, "UserRepository - 保存完整用户", "[repository][user]") {
    User user;
    user.setName("完整测试");
    for (int i = 0; i < 10; i++) {
        user.setAbility(i, 0.3 + i * 0.01);
        user.setBaseAbility(i, 0.25);
    }
    user.setLastReadTime(1714435200);
    REQUIRE(userRepo.saveUser(user));

    User loaded;
    REQUIRE(userRepo.getUser(loaded));
    REQUIRE(loaded.getName() == "完整测试");
    for (int i = 0; i < 10; i++) {
        REQUIRE(std::abs(loaded.getAbility(i) - (0.3 + i * 0.01)) < 1e-4);
        REQUIRE(std::abs(loaded.getBaseAbility(i) - 0.25) < 1e-4);
    }
    REQUIRE(loaded.getLastReadTime() == 1714435200);
}

TEST_CASE_METHOD(RepoTestFixture, "UserRepository - 最后阅读时间", "[repository][user]") {
    REQUIRE(userRepo.getLastReadTime() == 0);
    userRepo.saveUserName("用户");
    time_t now = 1234567890;
    REQUIRE(userRepo.updateLastReadTime(now));
    REQUIRE(userRepo.getLastReadTime() == now);
}

// =============================================================================
// TextRepository 测试
// =============================================================================

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 空表状态", "[repository][text]") {
    REQUIRE(textRepo.isEmpty());
    REQUIRE(textRepo.getCount() == 0);
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 保存和查询古文", "[repository][text]") {
    Text text;
    text.setTitle("齐桓下拜受胙");
    text.setAuthor("左丘明");
    text.setDynasty("先秦");
    text.setContent("夏，会于葵丘...");
    for (int i = 0; i < 10; i++) {
        text.setDifficulty(i, 0.5 + i * 0.01);
    }
    REQUIRE(textRepo.saveText(text));

    REQUIRE(textRepo.getCount() == 1);
    REQUIRE_FALSE(textRepo.isEmpty());

    Text loaded;
    REQUIRE(textRepo.getTextById(1, loaded));
    REQUIRE(loaded.getTitle() == "齐桓下拜受胙");
    REQUIRE(loaded.getAuthor() == "左丘明");
    REQUIRE(loaded.getDynasty() == "先秦");
    for (int i = 0; i < 10; i++) {
        REQUIRE(std::abs(loaded.getDifficulty(i) - (0.5 + i * 0.01)) < 1e-4);
    }
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 更新古文", "[repository][text]") {
    Text text;
    text.setTitle("原文");
    text.setContent("内容1");
    for (int i = 0; i < 10; i++) text.setDifficulty(i, 0.1);
    textRepo.saveText(text);

    text.setId(1);
    text.setTitle("更新后");
    text.setContent("内容2");
    for (int i = 0; i < 10; i++) text.setDifficulty(i, 0.9);
    REQUIRE(textRepo.updateText(text));

    Text loaded;
    textRepo.getTextById(1, loaded);
    REQUIRE(loaded.getTitle() == "更新后");
    REQUIRE(std::abs(loaded.getDifficulty(0) - 0.9) < 1e-4);
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 删除古文", "[repository][text]") {
    Text text;
    text.setTitle("待删除");
    text.setContent("将被删除");
    textRepo.saveText(text);

    REQUIRE(textRepo.getCount() == 1);
    REQUIRE(textRepo.deleteText(1));
    REQUIRE(textRepo.getCount() == 0);
    REQUIRE(textRepo.isEmpty());
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 获取所有古文", "[repository][text]") {
    for (int i = 0; i < 3; i++) {
        Text text;
        text.setTitle("古文" + std::to_string(i + 1));
        text.setContent("内容" + std::to_string(i + 1));
        textRepo.saveText(text);
    }

    auto texts = textRepo.getAllTexts();
    REQUIRE(texts.size() == 3);
    REQUIRE(texts[0].getTitle() == "古文1");
    REQUIRE(texts[2].getTitle() == "古文3");
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 按 ID 区间查询", "[repository][text]") {
    for (int i = 0; i < 5; i++) {
        Text text;
        text.setTitle("古文" + std::to_string(i + 1));
        text.setContent("内容");
        textRepo.saveText(text);
    }

    auto texts = textRepo.getTextsByIdRange(2, 4);
    REQUIRE(texts.size() == 3);
    REQUIRE(texts[0].getTitle() == "古文2");
    REQUIRE(texts[2].getTitle() == "古文4");
}

TEST_CASE_METHOD(RepoTestFixture, "TextRepository - 查询不存在的 ID", "[repository][text]") {
    Text text;
    REQUIRE_FALSE(textRepo.getTextById(999, text));
}

// =============================================================================
// ReadingHistoryRepository 测试
// =============================================================================

TEST_CASE_METHOD(RepoTestFixture, "ReadingHistoryRepository - 添加和查询记录", "[repository][history]") {
    time_t now = std::time(nullptr);
    REQUIRE(historyRepo.addRecord(1, 120.5, now));
    REQUIRE(historyRepo.addRecord(2, 300.0, now - 3600));
    REQUIRE(historyRepo.getTotalReadCount() == 2);

    auto records = historyRepo.getRecentRecords(10);
    REQUIRE(records.size() == 2);
    REQUIRE(records[0].textId == 1);  // 最近的在前
    REQUIRE(std::abs(records[0].readTime - 120.5) < 1e-4);
}

TEST_CASE_METHOD(RepoTestFixture, "ReadingHistoryRepository - 限制查询数量", "[repository][history]") {
    for (int i = 1; i <= 5; i++) {
        historyRepo.addRecord(i, 60.0 * i, std::time(nullptr) - i * 3600);
    }
    auto records = historyRepo.getRecentRecords(3);
    REQUIRE(records.size() == 3);
}

TEST_CASE_METHOD(RepoTestFixture, "ReadingHistoryRepository - 空表状态", "[repository][history]") {
    REQUIRE(historyRepo.getTotalReadCount() == 0);
    auto records = historyRepo.getRecentRecords();
    REQUIRE(records.empty());
}

// =============================================================================
// LearningIncrementRepository 测试
// =============================================================================

TEST_CASE_METHOD(RepoTestFixture, "LearningIncrementRepository - 添加和查询增量", "[repository][increment]") {
    time_t t1 = 1714435200;
    time_t t2 = t1 + 86400;

    REQUIRE(incrementRepo.addIncrement(1, 1, 0.05, t1, "read"));
    REQUIRE(incrementRepo.addIncrement(1, 1, 0.03, t2, "quiz"));
    REQUIRE(incrementRepo.getIncrementCount(1) == 2);

    auto incs = incrementRepo.getIncrements(1, 1);
    REQUIRE(incs.size() == 2);
    REQUIRE(incs[0].dimension == 1);
    REQUIRE(std::abs(incs[0].delta - 0.05) < 1e-4);
    REQUIRE(incs[0].type == "read");
    REQUIRE(incs[0].timestamp == t1);
    REQUIRE(std::abs(incs[1].delta - 0.03) < 1e-4);
    REQUIRE(incs[1].type == "quiz");
    REQUIRE(incs[1].timestamp == t2);
}

TEST_CASE_METHOD(RepoTestFixture, "LearningIncrementRepository - 获取所有增量", "[repository][increment]") {
    time_t now = std::time(nullptr);
    incrementRepo.addIncrement(1, 1, 0.01, now, "read");
    incrementRepo.addIncrement(1, 2, 0.02, now, "read");
    incrementRepo.addIncrement(1, 3, 0.03, now, "quiz");

    auto all = incrementRepo.getAllIncrements(1);
    REQUIRE(all.size() == 3);
}

TEST_CASE_METHOD(RepoTestFixture, "LearningIncrementRepository - 删除增量", "[repository][increment]") {
    time_t now = std::time(nullptr);
    incrementRepo.addIncrement(1, 1, 0.01, now);
    incrementRepo.addIncrement(1, 1, 0.02, now + 1);
    incrementRepo.addIncrement(1, 1, 0.03, now + 2);

    auto incs = incrementRepo.getIncrements(1, 1);
    REQUIRE(incs.size() == 3);

    REQUIRE(incrementRepo.deleteIncrement(incs[0].id));
    REQUIRE(incrementRepo.getIncrementCount(1) == 2);
}

TEST_CASE_METHOD(RepoTestFixture, "LearningIncrementRepository - 批量删除", "[repository][increment]") {
    time_t now = std::time(nullptr);
    incrementRepo.addIncrement(1, 1, 0.01, now);
    incrementRepo.addIncrement(1, 2, 0.02, now);
    incrementRepo.addIncrement(1, 3, 0.03, now);

    auto incs1 = incrementRepo.getIncrements(1, 1);
    auto incs2 = incrementRepo.getIncrements(1, 2);
    std::vector<int> toDelete = {incs1[0].id, incs2[0].id};
    REQUIRE(incrementRepo.deleteIncrements(toDelete));
    REQUIRE(incrementRepo.getIncrementCount(1) == 1);
}

TEST_CASE_METHOD(RepoTestFixture, "LearningIncrementRepository - 空数据查询", "[repository][increment]") {
    REQUIRE(incrementRepo.getIncrementCount(1) == 0);
    auto incs = incrementRepo.getIncrements(1, 1);
    REQUIRE(incs.empty());
}
