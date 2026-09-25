// v1.4.0 工作项 1：RAII Statement / Row / queryRows 的单测，以及用户库迁移的幂等性守卫。
// 覆盖：Statement 析构必 finalize（sqlite3_next_stmt 计数）、queryRows 区分空结果与出错、
// 多类型参数绑定、Row typed accessor 边界（NULL 列、越界列名/下标）。
#include <catch_amalgamated.hpp>

#include "database/DatabaseManager.h"
#include "database/LearningIncrementRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/Statement.h"
#include "database/UserRepository.h"

#include <sqlite3.h>

#include <cstdint>
#include <filesystem>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

// 连接上仍存活（未 finalize）的预处理语句数
int countOpenStatements(sqlite3* db)
{
    int count = 0;
    for (sqlite3_stmt* stmt = sqlite3_next_stmt(db, nullptr); stmt != nullptr;
         stmt = sqlite3_next_stmt(db, stmt)) {
        ++count;
    }
    return count;
}

std::string workDir(const std::string& tag)
{
    const std::string dir = std::string(TEST_DB_PATH) + "." + tag + ".dir";
    std::error_code ec;
    fs::create_directories(dir, ec);
    return dir;
}

void execRaw(sqlite3* db, const char* sql)
{
    char* err = nullptr;
    const int rc = sqlite3_exec(db, sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        const std::string message = err ? err : "?";
        sqlite3_free(err);
        FAIL("sqlite3_exec 失败: " << message);
    }
}

// sqlite_master 摘要：对象名 -> "type: ddl"（用于比对新旧实施/重复执行的 schema 等价性）
using ObjectMap = std::map<std::string, std::string>;

ObjectMap readSchema(const std::string& path)
{
    ObjectMap objects;
    DatabaseManager db;
    if (!db.open(path)) return objects;
    std::vector<Row> rows;
    if (!db.queryRows(
            "SELECT type, name, COALESCE(sql, '') AS ddl FROM sqlite_master ORDER BY type, name;",
            rows)) {
        return objects;
    }
    for (const Row& row : rows) {
        objects[row.text("name")] = row.text("type") + ": " + row.text("ddl");
    }
    return objects;
}

std::set<std::string> columnsOf(const std::string& path, const std::string& table)
{
    std::set<std::string> columns;
    DatabaseManager db;
    if (!db.open(path)) return columns;
    std::vector<Row> rows;
    if (!db.queryRows("PRAGMA table_info(" + table + ");", rows)) return columns;
    for (const Row& row : rows) columns.insert(row.text("name"));
    return columns;
}

int userVersionOf(const std::string& path)
{
    DatabaseManager db;
    if (!db.open(path)) return -1;
    return db.getUserVersion();
}

// 仓库层迁移入口（与 bridge db_open 同序）
bool runRepositories(const std::string& path)
{
    DatabaseManager db;
    if (!db.open(path)) return false;
    UserRepository users(&db);
    ReadingHistoryRepository history(&db);
    LearningIncrementRepository increments(&db);
    if (!users.initTable()) return false;
    if (!history.initTable()) return false;
    if (!increments.initTable()) return false;
    db.close();
    return true;
}

}  // namespace

TEST_CASE("Statement：析构即 finalize，未 step/移动/预处理失败均无泄漏", "[statement]") {
    sqlite3* raw = nullptr;
    REQUIRE(sqlite3_open(":memory:", &raw) == SQLITE_OK);
    REQUIRE(countOpenStatements(raw) == 0);

    SECTION("作用域退出即 finalize") {
        {
            Statement stmt(raw, "CREATE TABLE t (id INTEGER, name TEXT);");
            REQUIRE(stmt.ok());
            REQUIRE(stmt.error().empty());
            REQUIRE(stmt.step() == SQLITE_DONE);
            REQUIRE(countOpenStatements(raw) == 1);  // 未析构时确实还挂着
        }
        REQUIRE(countOpenStatements(raw) == 0);
    }

    SECTION("未 step 即析构同样 finalize") {
        {
            Statement keep(raw, "CREATE TABLE t (id INTEGER, name TEXT);");
            REQUIRE(keep.ok());
            REQUIRE(keep.step() == SQLITE_DONE);
            {
                Statement neverStepped(raw, "SELECT * FROM t;");
                REQUIRE(neverStepped.ok());
                REQUIRE(countOpenStatements(raw) == 2);
            }
            REQUIRE(countOpenStatements(raw) == 1);
        }
        REQUIRE(countOpenStatements(raw) == 0);
    }

    SECTION("移动构造/移动赋值后句柄唯一，全部析构后归零") {
        {
            Statement a(raw, "SELECT 1;");
            REQUIRE(a.ok());
            Statement b(std::move(a));
            REQUIRE_FALSE(a.ok());
            REQUIRE(b.ok());
            REQUIRE(b.step() == SQLITE_ROW);
            Row row;
            b.readRow(row);
            REQUIRE(row.integer(0) == 1);

            Statement c(raw, "SELECT 2;");
            c = std::move(b);  // 释放 c 原句柄 + 接管 b 的句柄
            REQUIRE_FALSE(b.ok());
            REQUIRE(c.ok());
            REQUIRE(c.reset());  // 移动过来的语句保留原句柄，可 reset 后重新 step
            REQUIRE(c.step() == SQLITE_ROW);
            REQUIRE(countOpenStatements(raw) == 1);
        }
        REQUIRE(countOpenStatements(raw) == 0);
    }

    SECTION("预处理失败 ok()==false 且不持有句柄") {
        Statement bad(raw, "SELEC 1;");
        REQUIRE_FALSE(bad.ok());
        REQUIRE_FALSE(bad.error().empty());
        REQUIRE(bad.step() == SQLITE_MISUSE);
        REQUIRE(countOpenStatements(raw) == 0);
    }

    REQUIRE(countOpenStatements(raw) == 0);
    sqlite3_close(raw);
}

TEST_CASE("queryRows：空结果与出错可区分，失败不残留半截结果", "[statement]") {
    DatabaseManager db;
    REQUIRE(db.open(":memory:"));
    REQUIRE(db.executeSQL("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);"));

    std::vector<Row> rows;
    // 空表：成功 + 空结果
    REQUIRE(db.queryRows("SELECT id, name FROM t;", rows));
    REQUIRE(rows.empty());
    // 带参数命中 0 行：成功 + 空结果
    REQUIRE(db.queryRows("SELECT id, name FROM t WHERE id = ?;", std::vector<SqlParam>{42}, rows));
    REQUIRE(rows.empty());
    // 语法错误：失败 + 清空 out + lastError 可用
    REQUIRE_FALSE(db.queryRows("SELEC id FROM t;", rows));
    REQUIRE(rows.empty());
    REQUIRE_FALSE(db.getLastError().empty());
    // 表不存在：失败
    REQUIRE_FALSE(db.queryRows("SELECT id FROM no_such_table;", rows));
    REQUIRE(rows.empty());
    // 连接未打开：失败（不是"空结果"）
    DatabaseManager closed;
    REQUIRE_FALSE(closed.queryRows("SELECT 1;", rows));
    REQUIRE(rows.empty());

    // 中途 step 出错：已收集的行也必须被清空
    REQUIRE(db.executeSQL("INSERT INTO t (id, name) VALUES (1, 'a'), (2, 'b'), (3, 'c');"));
    REQUIRE_FALSE(db.queryRows(
        "SELECT abs(CASE WHEN id = 2 THEN -9223372036854775808 ELSE 1 END) AS v "
        "FROM t ORDER BY id;",
        rows));
    REQUIRE(rows.empty());

    // 成功查询会覆盖上一次内容（不追加）
    REQUIRE(db.queryRows("SELECT id FROM t ORDER BY id;", rows));
    REQUIRE(rows.size() == 3);
    REQUIRE(db.queryRows("SELECT id FROM t WHERE id = 1;", rows));
    REQUIRE(rows.size() == 1);
}

TEST_CASE("queryRows：多类型参数绑定与类型化取值", "[statement]") {
    DatabaseManager db;
    REQUIRE(db.open(":memory:"));
    REQUIRE(db.executeSQL("CREATE TABLE t (s TEXT, r REAL, i INTEGER, big INTEGER);"));

    const int64_t big = 9007199254740993LL;  // 2^53+1，经 double 会丢精度
    REQUIRE(db.executeSQL("INSERT INTO t (s, r, i, big) VALUES (?, ?, ?, ?);",
                          std::vector<SqlParam>{std::string("文言文"), 1.5, 7, big}));

    std::vector<Row> rows;
    REQUIRE(db.queryRows("SELECT s, r, i, big FROM t "
                         "WHERE s = ? AND r = ? AND i = ? AND big = ?;",
                         std::vector<SqlParam>{std::string("文言文"), 1.5, 7, big}, rows));
    REQUIRE(rows.size() == 1);
    const Row& row = rows[0];
    REQUIRE(row.columnCount() == 4);
    REQUIRE(row.text("s") == "文言文");
    REQUIRE(row.real("r") == 1.5);
    REQUIRE(row.integer("i") == 7);
    REQUIRE(row.integer("big") == big);  // int64 绑定无精度回环
    // 具名列与下标访问等价
    REQUIRE(row.columnIndex("big") == 3);
    REQUIRE(row.columnName(3) == "big");
    REQUIRE(row.text(0) == row.text("s"));
    REQUIRE(row.integer(3) == row.integer("big"));
}

TEST_CASE("Row：NULL 列与越界列名/下标的取值边界", "[statement]") {
    DatabaseManager db;
    REQUIRE(db.open(":memory:"));
    REQUIRE(db.executeSQL("CREATE TABLE t (a INTEGER, b TEXT);"));
    REQUIRE(db.executeSQL("INSERT INTO t (a, b) VALUES (NULL, NULL);"));

    std::vector<Row> rows;
    REQUIRE(db.queryRows("SELECT a, b, 42 AS c, 'x' AS d FROM t;", rows));
    REQUIRE(rows.size() == 1);
    const Row& row = rows[0];

    REQUIRE(row.columnCount() == 4);
    REQUIRE(row.hasColumn("a"));
    REQUIRE_FALSE(row.hasColumn("zzz"));
    REQUIRE(row.columnIndex("zzz") == -1);

    // NULL 列：isNull 为真，取值走默认值
    REQUIRE(row.isNull("a"));
    REQUIRE(row.isNull(0));
    REQUIRE(row.isNull("b"));
    REQUIRE(row.text("a").empty());
    REQUIRE(row.integer("a") == 0);
    REQUIRE(row.real("a") == 0.0);

    // 越界下标 / 未知列名：不崩、返回默认值
    REQUIRE(row.isNull(-1));
    REQUIRE(row.isNull(99));
    REQUIRE(row.isNull("zzz"));
    REQUIRE(row.text(-1).empty());
    REQUIRE(row.text(99).empty());
    REQUIRE(row.text("zzz").empty());
    REQUIRE(row.integer(99) == 0);
    REQUIRE(row.integer("zzz") == 0);
    REQUIRE(row.real(-1) == 0.0);
    REQUIRE(row.columnName(99).empty());
    REQUIRE(row.columnName(-1).empty());

    // 表达式列按别名访问 + 数值列 text() 转换
    REQUIRE(row.integer("c") == 42);
    REQUIRE(row.text("c") == "42");
    REQUIRE(row.text("d") == "x");
}

TEST_CASE("迁移：内容库副本重复 initTable 幂等，版本号与内容表不变", "[statement][migration]") {
    const std::string dir = workDir("statement_migrate");
    const std::string copy = dir + "/asset_copy.db";
    std::error_code ec;
    fs::remove(copy, ec);
    fs::copy_file(TEST_DB_PATH, copy, fs::copy_options::overwrite_existing);

    const ObjectMap before = readSchema(copy);
    REQUIRE(before.count("classical_text") == 1);
    REQUIRE(before.count("questions") == 1);
    const int versionBefore = userVersionOf(copy);

    REQUIRE(runRepositories(copy));
    const ObjectMap afterFirst = readSchema(copy);
    REQUIRE(runRepositories(copy));
    const ObjectMap afterSecond = readSchema(copy);

    // 幂等：第二次执行无任何 schema 变更
    REQUIRE(afterFirst == afterSecond);
    // 内容库表结构不被用户库迁移触碰
    REQUIRE(afterFirst.count("classical_text") == 1);
    REQUIRE(afterFirst.at("classical_text") == before.at("classical_text"));
    REQUIRE(afterFirst.at("questions") == before.at("questions"));
    // 版本号是 bridge 的打开门控，仓库层迁移不提升
    REQUIRE(userVersionOf(copy) == versionBefore);

    const std::set<std::string> userCols = columnsOf(copy, "user");
    for (const char* column : {"id", "d1_ability", "d10_ability", "d1_base_ability",
                               "d10_base_ability", "eta", "d1_quiz_count", "d10_quiz_count",
                               "last_read_time", "initialized"}) {
        INFO("user 缺列: " << column);
        REQUIRE(userCols.count(column) == 1);
    }
    REQUIRE(userCols.count("name") == 0);
    const std::set<std::string> attemptCols = columnsOf(copy, "quiz_attempts");
    REQUIRE(attemptCols.count("user_id") == 1);
    REQUIRE(attemptCols.count("is_init") == 1);
    const std::set<std::string> reviewCols = columnsOf(copy, "review_items");
    REQUIRE(reviewCols.count("user_id") == 1);
    REQUIRE(reviewCols.count("question_id") == 1);
}

TEST_CASE("迁移：旧库缺列补齐/旧主键重建，数据保留且重复执行无变更", "[statement][migration]") {
    const std::string dir = workDir("statement_legacy");
    const std::string legacy = dir + "/legacy_user.db";
    std::error_code ec;
    fs::remove(legacy, ec);

    sqlite3* raw = nullptr;
    REQUIRE(sqlite3_open(legacy.c_str(), &raw) == SQLITE_OK);
    execRaw(raw,
            "CREATE TABLE user ("
            "id INTEGER PRIMARY KEY, "
            "d1_ability REAL DEFAULT 0.0, d2_ability REAL DEFAULT 0.0, "
            "d3_ability REAL DEFAULT 0.0, d4_ability REAL DEFAULT 0.0, "
            "d5_ability REAL DEFAULT 0.0, d6_ability REAL DEFAULT 0.0, "
            "d7_ability REAL DEFAULT 0.0, d8_ability REAL DEFAULT 0.0, "
            "d9_ability REAL DEFAULT 0.0, d10_ability REAL DEFAULT 0.0, "
            "name TEXT, last_read_time INTEGER DEFAULT 0);");
    execRaw(raw, "INSERT INTO user (id, d1_ability, name) VALUES (1, 0.5, '旧档案');");
    execRaw(raw,
            "CREATE TABLE quiz_attempts ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, question_id INTEGER NOT NULL, "
            "text_id INTEGER NOT NULL, correct INTEGER NOT NULL, "
            "is_review INTEGER DEFAULT 0, answered_at INTEGER NOT NULL);");
    execRaw(raw,
            "CREATE TABLE review_items ("
            "question_id INTEGER PRIMARY KEY, text_id INTEGER NOT NULL, "
            "correct_streak INTEGER DEFAULT 0, wrong_count INTEGER DEFAULT 0, "
            "next_review_at INTEGER NOT NULL);");
    execRaw(raw, "INSERT INTO review_items (question_id, text_id, next_review_at) VALUES (7, 3, 100);");
    execRaw(raw, "PRAGMA user_version = 1;");
    sqlite3_close(raw);

    REQUIRE(runRepositories(legacy));
    const ObjectMap afterFirst = readSchema(legacy);
    REQUIRE(runRepositories(legacy));
    REQUIRE(readSchema(legacy) == afterFirst);  // 第二次无变更

    const std::set<std::string> userCols = columnsOf(legacy, "user");
    for (const char* column : {"d1_base_ability", "d10_base_ability", "eta", "d1_quiz_count",
                               "d10_quiz_count", "initialized"}) {
        INFO("user 缺列: " << column);
        REQUIRE(userCols.count(column) == 1);
    }
    REQUIRE(userCols.count("name") == 0);
    const std::set<std::string> attemptCols = columnsOf(legacy, "quiz_attempts");
    REQUIRE(attemptCols.count("user_id") == 1);
    REQUIRE(attemptCols.count("is_init") == 1);
    const std::set<std::string> reviewCols = columnsOf(legacy, "review_items");
    REQUIRE(reviewCols.count("user_id") == 1);
    REQUIRE(reviewCols.count("next_review_at") == 1);
    REQUIRE(userVersionOf(legacy) == 1);

    // 数据保留：旧 user 行不被重建丢失；默认档案对齐；旧错题经主键重建保留
    DatabaseManager db;
    REQUIRE(db.open(legacy));
    std::vector<Row> rows;
    REQUIRE(db.queryRows("SELECT d1_ability FROM user WHERE id = 1;", rows));
    REQUIRE(rows.size() == 1);
    REQUIRE(rows[0].real("d1_ability") == 0.5);
    REQUIRE(db.queryRows("SELECT COUNT(*) FROM profiles WHERE deleted = 0;", rows));
    REQUIRE(rows.size() == 1);
    REQUIRE(rows[0].integer(0) == 1);
    REQUIRE(db.queryRows("SELECT COUNT(*) FROM review_items WHERE question_id = 7;", rows));
    REQUIRE(rows.size() == 1);
    REQUIRE(rows[0].integer(0) == 1);
}
