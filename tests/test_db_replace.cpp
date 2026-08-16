#include <catch_amalgamated.hpp>
#include "c_types.h"
#include "test_helpers.h"
#include "user_tables.h"
#include <sqlite3.h>

#include <cstring>
#include <filesystem>
#include <fstream>
#include <set>
#include <string>
#include <vector>

extern "C" {
    int db_open(const char* content_path, const char* user_path);
    void db_close();
    int db_replace(const char* new_db_path, const char* cur_db_path);
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int text_get_count();
    int tracker_apply_read(const UserData* user, int text_id, double read_time, int64_t timestamp, UserData* out_user, int skip_effect);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
    int user_is_initialized();
    int user_init_questions(QuestionData* out, int max_count);
    int user_init_apply(const int* qids, const int* choices, int count, int64_t timestamp, UserData* out_user);
}

namespace {

namespace fs = std::filesystem;

void initDefaultProfile()
{
    QuestionData qs[8];
    const int n = user_init_questions(qs, 8);
    REQUIRE(n == 6);
    int qids[6] = {0};
    int choices[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < n; i++) qids[i] = qs[i].id;
    UserData out;
    REQUIRE(user_init_apply(qids, choices, n, 1700000000LL, &out) == BRIDGE_OK);
}

void writeUserBase(UserData& u, double base)
{
    std::memset(&u, 0, sizeof(u));
    for (int i = 0; i < 10; i++) {
        u.abilities[i] = base + i * 0.01;
        u.base_abilities[i] = base + i * 0.01;
    }
    u.last_read_time = 1700000000LL;
}

// 在指定目录生成一个纯内容库文件（可指定文件名）
std::string makeContentFile(const std::string& dir, const std::string& filename)
{
    const std::string path = dir + "/" + filename;
    std::error_code ec;
    fs::remove(path, ec);
    fs::copy_file(TEST_DB_PATH, path, fs::copy_options::overwrite_existing);
    sqlite3* db = nullptr;
    if (sqlite3_open(path.c_str(), &db) != SQLITE_OK) return {};
    for (const std::string& t : kUserTableNames) {
        const std::string sql = "DROP TABLE IF EXISTS " + t + ";";
        sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr);
    }
    sqlite3_exec(db, "PRAGMA user_version = 1;", nullptr, nullptr, nullptr);
    sqlite3_close(db);
    return path;
}

void setUserVersion(const std::string& path, int version)
{
    sqlite3* db = nullptr;
    REQUIRE(sqlite3_open(path.c_str(), &db) == SQLITE_OK);
    const std::string sql = "PRAGMA user_version = " + std::to_string(version) + ";";
    REQUIRE(sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr) == SQLITE_OK);
    sqlite3_close(db);
}

long long sqliteCount(const std::string& dbPath, const std::string& sql)
{
    sqlite3* db = nullptr;
    if (sqlite3_open(dbPath.c_str(), &db) != SQLITE_OK) return -1;
    sqlite3_stmt* stmt = nullptr;
    long long result = -1;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            result = sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return result;
}

}  // namespace

TEST_CASE("db_replace - 同步场景：内容库替换后用户库数据零变化、引擎不重开", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("replace_sync");
    const std::string content = test_helpers::makeContentDb("replace_sync");
    const std::string user = test_helpers::makeUserDb("replace_sync");

    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    initDefaultProfile();

    // 制造用户数据：基础能力 + 阅读记录 + 追踪标记 + 学习增量
    UserData u;
    writeUserBase(u, 0.3);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);

    UserData out;
    REQUIRE(tracker_apply_read(&u, 2, 300.0, 1700000100LL, &out, 0) == BRIDGE_OK);

    // 新内容包 = 同目录另一个纯内容库文件
    const std::string newContent = makeContentFile(dir, "new_classical.db");
    REQUIRE(db_replace(newContent.c_str(), content.c_str()) == BRIDGE_OK);

    // 引擎未重开，文本立即来自新库
    REQUIRE(text_get_count() == 270);

    // 用户数据零变化：基础能力原样、阅读历史 2 条、追踪标记保留
    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(loaded.base_abilities[i] == Catch::Approx(out.base_abilities[i]));
    }
    REQUIRE(history_get_total_count() == 2);
    int tracked[16];
    const int t = history_get_tracked_text_ids(tracked, 16);
    REQUIRE(t == 1);
    REQUIRE(tracked[0] == 2);

    // user.db 物理文件不包含内容表
    REQUIRE(sqliteCount(user, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='classical_text'") == 0);
    REQUIRE(sqliteCount(user, "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='questions'") == 0);

    db_close();
}

TEST_CASE("db_replace - 启动场景：库未打开时替换内容库", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("replace_startup");
    const std::string content = test_helpers::makeContentDb("replace_startup");
    const std::string user = test_helpers::makeUserDb("replace_startup");

    // 第一次打开制造数据后关闭（模拟上次会话结束）
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    UserData u;
    writeUserBase(u, 0.5);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(7, 120.0, 1700000000LL) == BRIDGE_OK);
    db_close();

    const std::string newContent = makeContentFile(dir, "new_classical.db");
    REQUIRE(db_replace(newContent.c_str(), content.c_str()) == BRIDGE_OK);

    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(loaded.base_abilities[i] == Catch::Approx(u.base_abilities[i]));
    }
    REQUIRE(history_get_total_count() == 1);
    REQUIRE(text_get_count() == 270);

    db_close();
}

TEST_CASE("db_replace - 无效新库回滚，旧库完好", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("replace_rollback");
    const std::string content = test_helpers::makeContentDb("replace_rollback");
    const std::string user = test_helpers::makeUserDb("replace_rollback");

    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    UserData u;
    writeUserBase(u, 0.8);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(3, 30.0, 1700000000LL) == BRIDGE_OK);

    // 伪造损坏的新内容库
    const std::string badDb = dir + "/bad.db";
    {
        std::ofstream f(badDb, std::ios::binary);
        f << "this is not a sqlite database at all....";
    }

    const int rc = db_replace(badDb.c_str(), content.c_str());
    REQUIRE(rc == BRIDGE_ERR_DB_CONTENT);

    // 校验失败发生在任何文件操作之前：引擎仍打开、旧内容库仍挂载
    REQUIRE(text_get_count() == 270);
    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(loaded.base_abilities[i] == Catch::Approx(u.base_abilities[i]));
    }
    REQUIRE(history_get_total_count() == 1);

    db_close();
}

TEST_CASE("db_replace - 新内容库带旧用户表被拒", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("replace_blacklist");
    const std::string content = test_helpers::makeContentDb("replace_blacklist");
    const std::string user = test_helpers::makeUserDb("replace_blacklist");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 新包 = 未剥离用户表的混装库，但把 db_version 改成 1（纯净校验仍应拒绝）
    const std::string mixed = dir + "/mixed.db";
    fs::copy_file(TEST_DB_PATH, mixed, fs::copy_options::overwrite_existing);
    setUserVersion(mixed, 1);

    REQUIRE(db_replace(mixed.c_str(), content.c_str()) == BRIDGE_ERR_DB_CONTENT);
    REQUIRE(text_get_count() == 270);  // 旧库未动
    db_close();
}

TEST_CASE("db_replace - 新内容库 db_version 不匹配被拒", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("replace_version");
    const std::string content = test_helpers::makeContentDb("replace_version");
    const std::string user = test_helpers::makeUserDb("replace_version");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    const std::string v0 = makeContentFile(dir, "v0.db");
    setUserVersion(v0, 0);
    REQUIRE(db_replace(v0.c_str(), content.c_str()) == BRIDGE_ERR_DB_VERSION);

    const std::string v2 = makeContentFile(dir, "v2.db");
    setUserVersion(v2, 2);
    REQUIRE(db_replace(v2.c_str(), content.c_str()) == BRIDGE_ERR_DB_VERSION);
    REQUIRE(text_get_count() == 270);

    db_close();
}

TEST_CASE("db_open - user.db 与 classical.db 同路径拒绝", "[db_replace]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("same_path");
    REQUIRE(db_open(content.c_str(), content.c_str()) == BRIDGE_ERR_DB_SAME_PATH);
    db_close();
}

TEST_CASE("db_open - user.db db_version 过高拒绝", "[db_replace]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("open_user_v2");
    const std::string user = test_helpers::makeUserDb("open_user_v2");
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(user.c_str(), &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db, "PRAGMA user_version = 2;", nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(db);
    }
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_ERR_DB_VERSION);
    db_close();
}

TEST_CASE("db_open - 内容库 db_version=0 旧开发版拒绝", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("open_v0");
    const std::string content = test_helpers::makeContentDb("open_v0");
    const std::string user = test_helpers::makeUserDb("open_v0");
    setUserVersion(content, 0);
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_ERR_DB_VERSION);
    db_close();
}

TEST_CASE("db_open - 内容库缺初始化 q_key 拒绝", "[db_replace]") {
    db_close();
    const std::string dir = test_helpers::workDir("open_qkey");
    const std::string content = test_helpers::makeContentDb("open_qkey");
    const std::string user = test_helpers::makeUserDb("open_qkey");
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(content.c_str(), &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "DELETE FROM questions WHERE q_key = 'd648b695e1579dbe';",
            nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(db);
    }
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_ERR_DB_CONTENT);
    db_close();
}

TEST_CASE("db_open/db_replace - 路径转义：中文/空格/单引号/反斜杠", "[db_replace]") {
    db_close();
    // Linux 下这些字符都是合法文件名字符；Windows 反斜杠是分隔符，路径绑定参数在 Windows 上也应安全。
    const std::string weird = "中文 空格 '单引号' \\反斜杠";
    const std::string dir = test_helpers::workDir("path_escape") + "/" + weird;
    std::error_code ec;
    fs::create_directories(dir, ec);

    const std::string content = dir + "/classical.db";
    const std::string user = dir + "/user.db";
    fs::copy_file(TEST_DB_PATH, content, fs::copy_options::overwrite_existing);
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(content.c_str(), &db) == SQLITE_OK);
        for (const std::string& t : kUserTableNames) {
            const std::string sql = "DROP TABLE IF EXISTS " + t + ";";
            sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr);
        }
        sqlite3_exec(db, "PRAGMA user_version = 1;", nullptr, nullptr, nullptr);
        sqlite3_close(db);
    }

    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    REQUIRE(text_get_count() == 270);
    db_close();

    // 替换同样经过带特殊字符路径
    const std::string newContent = dir + "/new db.db";
    fs::copy_file(TEST_DB_PATH, newContent, fs::copy_options::overwrite_existing);
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(newContent.c_str(), &db) == SQLITE_OK);
        for (const std::string& t : kUserTableNames) {
            const std::string sql = "DROP TABLE IF EXISTS " + t + ";";
            sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr);
        }
        sqlite3_exec(db, "PRAGMA user_version = 1;", nullptr, nullptr, nullptr);
        sqlite3_close(db);
    }
    REQUIRE(db_replace(newContent.c_str(), content.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    REQUIRE(text_get_count() == 270);
    db_close();
}
