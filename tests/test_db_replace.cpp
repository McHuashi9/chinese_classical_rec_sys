#include <catch_amalgamated.hpp>
#include "c_types.h"
#include <sqlite3.h>

#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>

extern "C" {
    int db_open(const char* db_path);
    void db_close();
    int db_replace(const char* new_db_path, const char* cur_db_path);
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int text_get_count();
    int tracker_apply_read(const UserData* user, int text_id, double read_time, int64_t timestamp, UserData* out_user);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_recent(int limit, ReadingRecordData* out, int max_count);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
}

namespace {

namespace fs = std::filesystem;

// 每个用例独立的临时工作库（拷贝自测试资产，避免用例间相互污染）
std::string makeWorkDb(const std::string& tag)
{
    const std::string path = std::string(TEST_DB_PATH) + "." + tag + ".db";
    fs::copy_file(TEST_DB_PATH, path, fs::copy_options::overwrite_existing);
    fs::remove(path + ".bak");
    return path;
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

std::string sqliteText(const std::string& dbPath, const std::string& sql)
{
    sqlite3* db = nullptr;
    if (sqlite3_open(dbPath.c_str(), &db) != SQLITE_OK) return "ERR_OPEN";
    sqlite3_stmt* stmt = nullptr;
    std::string result;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char* t = sqlite3_column_text(stmt, 0);
            if (t) result = reinterpret_cast<const char*>(t);
        }
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    return result;
}

double sqliteDouble(const std::string& dbPath, const std::string& sql)
{
    const std::string t = sqliteText(dbPath, sql);
    return t.empty() ? -1e18 : std::strtod(t.c_str(), nullptr);
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

}  // namespace

TEST_CASE("db_replace - 同步场景：整库替换保留用户数据（新库缺 text_tracking 表）", "[db_replace]") {
    db_close();
    const std::string work = makeWorkDb("sync");

    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 制造用户数据：基础能力 + 阅读记录 + 追踪标记 + 学习增量
    UserData u;
    writeUserBase(u, 0.3);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);

    const int64_t now = 1700000100LL;
    UserData out;
    REQUIRE(tracker_apply_read(&u, 2, 300.0, now, &out) == BRIDGE_OK);

    // 新库 = 资产副本（无 text_tracking 表、用户表为空）
    const std::string newDb = work + ".new";
    fs::copy_file(TEST_DB_PATH, newDb, fs::copy_options::overwrite_existing);

    REQUIRE(db_replace(newDb.c_str(), work.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 文本内容来自新库
    REQUIRE(text_get_count() == 270);

    // 用户数据保留：基础能力原样（遗忘只改当前能力，不改基础）
    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(loaded.base_abilities[i] == Catch::Approx(out.base_abilities[i]));
        // 当前能力 = 基础能力 + 增量×遗忘衰减；重开时按真实当前时间衰减，只会 ≤ tracker 结果
        REQUIRE(loaded.abilities[i] >= loaded.base_abilities[i] - 1e-12);
        REQUIRE(loaded.abilities[i] <= out.abilities[i] + 1e-12);
    }

    // 阅读历史保留（tracker_apply_read + history_add_record 各 1 条）
    ReadingRecordData recs[10];
    const int n = history_get_recent(10, recs, 10);
    REQUIRE(n == 2);
    REQUIRE(history_get_total_count() == 2);

    // 追踪标记保留（新库原本没有 text_tracking 表，替换时补建）
    int tracked[16];
    const int t = history_get_tracked_text_ids(tracked, 16);
    REQUIRE(t == 1);
    REQUIRE(tracked[0] == 2);

    // 学习增量保留（10 维）
    REQUIRE(sqliteCount(work, "SELECT COUNT(*) FROM learning_increments") == 10);
    REQUIRE(sqliteCount(work, "SELECT COUNT(*) FROM text_tracking") == 1);

    // 自增序列对齐：替换后新记录 id 不与导入的 id 冲突
    REQUIRE(history_add_record(3, 30.0, now + 10) == BRIDGE_OK);
    ReadingRecordData recs2[10];
    const int n2 = history_get_recent(10, recs2, 10);
    REQUIRE(n2 == 3);
    REQUIRE(recs2[0].id > 2);  // 最新记录 id 大于导入的最大 id（2）

    db_close();
}

TEST_CASE("db_replace - 启动场景：库未打开时只读导出并合并", "[db_replace]") {
    db_close();
    const std::string work = makeWorkDb("startup");

    // 第一次打开制造数据后关闭（模拟上次会话结束）
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData u;
    writeUserBase(u, 0.5);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(7, 120.0, 1700000000LL) == BRIDGE_OK);
    db_close();

    // 启动场景：db 未打开，直接替换
    const std::string newDb = work + ".new";
    fs::copy_file(TEST_DB_PATH, newDb, fs::copy_options::overwrite_existing);
    REQUIRE(db_replace(newDb.c_str(), work.c_str()) == BRIDGE_OK);

    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
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
    const std::string work = makeWorkDb("rollback");

    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData u;
    writeUserBase(u, 0.8);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(3, 30.0, 1700000000LL) == BRIDGE_OK);

    // 伪造损坏的新库
    const std::string badDb = work + ".bad";
    {
        std::ofstream f(badDb, std::ios::binary);
        f << "this is not a sqlite database at all....";
    }

    const int rc = db_replace(badDb.c_str(), work.c_str());
    REQUIRE(rc != BRIDGE_OK);

    // 旧库已回滚，数据完好
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(loaded.base_abilities[i] == Catch::Approx(u.base_abilities[i]));
    }
    REQUIRE(history_get_total_count() == 1);

    db_close();
}

TEST_CASE("db_replace - schema 漂移：源库缺列时按白名单容错，缺列取默认", "[db_replace]") {
    db_close();
    // 构造旧版 schema 的独立用户库（新文件，不含资产里已有的完整表）
    const std::string work = makeWorkDb("drift");
    fs::remove(work);  // 从头创建旧 schema
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(work.c_str(), &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db, "CREATE TABLE user ("
            "id INTEGER PRIMARY KEY CHECK (id = 1), "
            "d1_ability REAL DEFAULT 0.0, d2_ability REAL DEFAULT 0.0, "
            "d3_ability REAL DEFAULT 0.0, d4_ability REAL DEFAULT 0.0, "
            "d5_ability REAL DEFAULT 0.0, d6_ability REAL DEFAULT 0.0, "
            "d7_ability REAL DEFAULT 0.0, d8_ability REAL DEFAULT 0.0, "
            "d9_ability REAL DEFAULT 0.0, d10_ability REAL DEFAULT 0.0, "
            "d1_base_ability REAL DEFAULT 0.0, d2_base_ability REAL DEFAULT 0.0, "
            "d3_base_ability REAL DEFAULT 0.0, d4_base_ability REAL DEFAULT 0.0, "
            "d5_base_ability REAL DEFAULT 0.0, d6_base_ability REAL DEFAULT 0.0, "
            "d7_base_ability REAL DEFAULT 0.0, d8_base_ability REAL DEFAULT 0.0, "
            "d9_base_ability REAL DEFAULT 0.0);", nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "INSERT INTO user (id, d1_ability, d1_base_ability, d9_base_ability) "
            "VALUES (1, 0.9, 0.61, 0.77);", nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "CREATE TABLE reading_history ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL DEFAULT 1, "
            "text_id INTEGER NOT NULL, read_time REAL NOT NULL, read_timestamp INTEGER NOT NULL);",
            nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "INSERT INTO reading_history (text_id, read_time, read_timestamp) "
            "VALUES (9, 45.0, 1700000000);", nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(db);
    }

    // 新库 = 完整资产（含全部列）
    const std::string newDb = work + ".new";
    fs::copy_file(TEST_DB_PATH, newDb, fs::copy_options::overwrite_existing);

    REQUIRE(db_replace(newDb.c_str(), work.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    UserData loaded;
    REQUIRE(user_load(&loaded) == BRIDGE_OK);
    // 源库存在的列按值保留
    REQUIRE(loaded.base_abilities[0] == Catch::Approx(0.61));
    REQUIRE(loaded.base_abilities[8] == Catch::Approx(0.77));
    // 源库缺列 → 目标库默认值
    REQUIRE(loaded.base_abilities[9] == Catch::Approx(0.0));
    REQUIRE(loaded.last_read_time == 0);
    // 阅读历史保留
    REQUIRE(history_get_total_count() == 1);
    REQUIRE(text_get_count() == 270);

    db_close();
}

TEST_CASE("db_replace - 目标缺列：tmp 打开时表迁移补列，导入交集列全部保真", "[db_replace]") {
    db_close();
    // 目标库 = 资产副本，但 user 表退化为旧版 schema（缺 d10_base_ability / last_read_time）；
    // openDatabase 的表迁移会幂等补列（默认 0），导入再把源值全覆盖回，整表数据不丢不硬失败
    const std::string work = makeWorkDb("tgtcols");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);
    UserData u;
    writeUserBase(u, 0.4);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);

    // 目标库 = 资产副本，但 user 表退化为旧版 schema（缺 d10_base_ability / last_read_time）
    const std::string newDb = work + ".new";
    fs::remove(newDb);
    fs::copy_file(TEST_DB_PATH, newDb, fs::copy_options::overwrite_existing);
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(newDb.c_str(), &db) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "ALTER TABLE user RENAME TO user_old; "
            "CREATE TABLE user ("
            "id INTEGER PRIMARY KEY CHECK (id = 1), "
            "d1_ability REAL DEFAULT 0.0, d2_ability REAL DEFAULT 0.0, "
            "d3_ability REAL DEFAULT 0.0, d4_ability REAL DEFAULT 0.0, "
            "d5_ability REAL DEFAULT 0.0, d6_ability REAL DEFAULT 0.0, "
            "d7_ability REAL DEFAULT 0.0, d8_ability REAL DEFAULT 0.0, "
            "d9_ability REAL DEFAULT 0.0, "
            "d1_base_ability REAL DEFAULT 0.0, d2_base_ability REAL DEFAULT 0.0, "
            "d3_base_ability REAL DEFAULT 0.0, d4_base_ability REAL DEFAULT 0.0, "
            "d5_base_ability REAL DEFAULT 0.0, d6_base_ability REAL DEFAULT 0.0, "
            "d7_base_ability REAL DEFAULT 0.0, d8_base_ability REAL DEFAULT 0.0, "
            "d9_base_ability REAL DEFAULT 0.0); "
            "INSERT INTO user (id) SELECT id FROM user_old; "
            "DROP TABLE user_old;", nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(db);
    }

    // 替换必须成功（目标缺列不硬失败）
    REQUIRE(db_replace(newDb.c_str(), work.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    REQUIRE(text_get_count() == 270);
    REQUIRE(history_get_total_count() == 1);

    // 目标缺列会被 db_open 的表迁移幂等补齐（默认 0），随后导入把源值全覆盖回
    REQUIRE(sqliteDouble(work, "SELECT d1_base_ability FROM user WHERE id=1") == Catch::Approx(0.40).margin(1e-6));
    REQUIRE(sqliteDouble(work, "SELECT d9_base_ability FROM user WHERE id=1") == Catch::Approx(0.48).margin(1e-6));
    REQUIRE(sqliteDouble(work, "SELECT d10_base_ability FROM user WHERE id=1") == Catch::Approx(0.49).margin(1e-6));
    REQUIRE(sqliteCount(work, "SELECT last_read_time FROM user WHERE id=1") == 1700000000LL);

    db_close();
}
