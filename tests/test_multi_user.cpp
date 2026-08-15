#include <catch_amalgamated.hpp>
#include "c_types.h"
#include "database/UserRepository.h"
#include <sqlite3.h>

#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

extern "C" {
    int db_open(const char* db_path);
    void db_close();
    int db_replace(const char* new_db_path, const char* cur_db_path);
    int user_list(ProfileData* out, int max_count);
    int user_active_id();
    int user_create(const char* name);
    int user_switch(int id);
    int user_rename(int id, const char* name);
    int user_delete(int id);
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
    int text_get_count();
}

namespace {

std::string makeWorkDb(const std::string& tag)
{
    const std::string path = std::string(TEST_DB_PATH) + "." + tag + ".db";
    fs::copy_file(TEST_DB_PATH, path, fs::copy_options::overwrite_existing);
    fs::remove(path + ".bak");
    return path;
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

}  // namespace

TEST_CASE("多用户 - 默认档案与档案 CRUD", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_crud");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 新库：默认档案 id=1 已就位
    REQUIRE(user_active_id() == 1);
    ProfileData profiles[8];
    int n = user_list(profiles, 8);
    REQUIRE(n == 1);
    REQUIRE(profiles[0].id == 1);
    REQUIRE(std::string(profiles[0].name) == "默认用户");

    // 新建档案
    const int id2 = user_create("小明");
    REQUIRE(id2 > 1);
    REQUIRE(user_create("") == BRIDGE_ERR_GENERIC);
    REQUIRE(user_create("这个名字实在是太长太长太长太长太长太长太长太长太长太长太长太长太长太长太长太长太长太长太长了") == BRIDGE_ERR_GENERIC);

    // 切换后 active id 更新，且新档案能力初始化默认
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(user_active_id() == id2);
    UserData u;
    REQUIRE(user_load(&u) == BRIDGE_OK);
    bool hasAbility = false;
    for (int i = 0; i < 10; i++) {
        if (u.abilities[i] > 0.0) hasAbility = true;
    }
    REQUIRE(hasAbility);

    // 重命名
    REQUIRE(user_rename(id2, "小红") == BRIDGE_OK);
    n = user_list(profiles, 8);
    REQUIRE(n == 2);
    bool renamed = false;
    for (int i = 0; i < n; i++) {
        if (profiles[i].id == id2) renamed = std::string(profiles[i].name) == "小红";
    }
    REQUIRE(renamed);

    // 删除保护：不能删除当前档案
    REQUIRE(user_delete(id2) == BRIDGE_ERR_USER);
    // 切回默认后删除
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(user_delete(id2) == BRIDGE_OK);
    n = user_list(profiles, 8);
    REQUIRE(n == 1);
    REQUIRE(profiles[0].id == 1);
    // 已删除档案不可切换
    REQUIRE(user_switch(id2) == BRIDGE_ERR_USER);

    db_close();
}

TEST_CASE("多用户 - 阅读历史与已读标记按档案隔离", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_isolation");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 档案 1 制造阅读历史
    UserData u;
    REQUIRE(user_load(&u) == BRIDGE_OK);
    REQUIRE(user_save(&u) == BRIDGE_OK);
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);
    REQUIRE(history_add_record(2, 30.0, 1700000001LL) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 2);
    int ids[8];
    REQUIRE(history_get_tracked_text_ids(ids, 8) == 0);  // 直接 add_record 不写 text_tracking

    // 切到新档案 → 历史为空
    const int id2 = user_create("B");
    REQUIRE(id2 > 1);
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 0);
    REQUIRE(history_add_record(3, 90.0, 1700000002LL) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);

    // 切回档案 1 → 历史仍为 2，B 的历史不可见
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 2);

    db_close();
}

TEST_CASE("多用户 - 老库 CHECK(id=1)/旧主键迁移", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_migrate");
    fs::remove(work);

    // 构造旧 schema：user 带 CHECK(id=1)，text_tracking 单列主键，review_items 单列主键
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(work.c_str(), &db) == SQLITE_OK);
        const char* oldUser =
            "CREATE TABLE user ("
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
            "d9_base_ability REAL DEFAULT 0.0, d10_base_ability REAL DEFAULT 0.0, "
            "eta REAL DEFAULT 0.08, "
            "d1_quiz_count INTEGER DEFAULT 0, d2_quiz_count INTEGER DEFAULT 0, "
            "d3_quiz_count INTEGER DEFAULT 0, d4_quiz_count INTEGER DEFAULT 0, "
            "d5_quiz_count INTEGER DEFAULT 0, d6_quiz_count INTEGER DEFAULT 0, "
            "d7_quiz_count INTEGER DEFAULT 0, d8_quiz_count INTEGER DEFAULT 0, "
            "d9_quiz_count INTEGER DEFAULT 0, d10_quiz_count INTEGER DEFAULT 0, "
            "last_read_time INTEGER DEFAULT 0);";
        REQUIRE(sqlite3_exec(db, oldUser, nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "INSERT INTO user (id, d1_ability, d1_base_ability, last_read_time) "
            "VALUES (1, 0.7, 0.61, 1700000000);", nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "CREATE TABLE text_tracking (text_id INTEGER PRIMARY KEY, tracked_at INTEGER NOT NULL);"
            "INSERT INTO text_tracking (text_id, tracked_at) VALUES (123, 1700000000);",
            nullptr, nullptr, nullptr) == SQLITE_OK);
        REQUIRE(sqlite3_exec(db,
            "CREATE TABLE review_items ("
            "question_id INTEGER PRIMARY KEY, text_id INTEGER NOT NULL, "
            "correct_streak INTEGER DEFAULT 0, wrong_count INTEGER DEFAULT 0, "
            "next_review_at INTEGER NOT NULL);"
            "INSERT INTO review_items (question_id, text_id, correct_streak, wrong_count, next_review_at) "
            "VALUES (999, 1, 0, 1, 1700000000);",
            nullptr, nullptr, nullptr) == SQLITE_OK);
        sqlite3_close(db);
    }

    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // user 数据迁移到默认档案
    UserData u;
    REQUIRE(user_load(&u) == BRIDGE_OK);
    REQUIRE(u.base_abilities[0] == Catch::Approx(0.61));
    REQUIRE(u.last_read_time == 1700000000LL);
    REQUIRE(user_active_id() == 1);

    // profiles 表已补默认档案
    ProfileData profiles[8];
    REQUIRE(user_list(profiles, 8) == 1);
    REQUIRE(std::string(profiles[0].name) == "默认用户");

    // text_tracking 旧数据归入 user_id=1
    int tracked[8];
    REQUIRE(history_get_tracked_text_ids(tracked, 8) == 1);
    REQUIRE(tracked[0] == 123);

    // review_items 迁移为复合主键且数据保留
    const std::string reviewSql = sqliteText(work,
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='review_items';");
    REQUIRE(reviewSql.find("PRIMARY KEY (user_id, question_id)") != std::string::npos);
    REQUIRE(sqliteText(work, "SELECT wrong_count FROM review_items WHERE question_id = 999;") == "1");

    // 老库迁移后仍可新建档案
    const int id2 = user_create("迁移后新档");
    REQUIRE(id2 > 1);
    REQUIRE(user_switch(id2) == BRIDGE_OK);

    db_close();
}

TEST_CASE("多用户 - 重名拒绝与档案数上限", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_limits");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 重名创建拒绝（未删除档案同名）
    REQUIRE(user_create("默认用户") == BRIDGE_ERR_GENERIC);
    const int id2 = user_create("小明");
    REQUIRE(id2 > 1);
    REQUIRE(user_create("小明") == BRIDGE_ERR_GENERIC);

    // 重名重命名拒绝（C++ 侧不区分"不存在/重名"，统一拒绝非 OK）
    REQUIRE(user_rename(id2, "默认用户") != BRIDGE_OK);
    REQUIRE(user_rename(id2, "小红") == BRIDGE_OK);
    REQUIRE(user_rename(id2, "小红") == BRIDGE_OK);  // 名字不变仍成功

    // 软删后名字可复用（列表不可见，不构成重名）
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(user_delete(id2) == BRIDGE_OK);
    REQUIRE(user_create("小红") > 1);

    db_close();
}

TEST_CASE("多用户 - 档案数上限 kMaxProfiles", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_cap");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 默认档案占 1 个名额，补建到上限
    for (int i = 2; i <= kMaxProfiles; i++) {
        const int id = user_create(("用户" + std::to_string(i)).c_str());
        REQUIRE(id == i);
    }
    // 满员后拒绝
    REQUIRE(user_create("超额档案") == BRIDGE_ERR_GENERIC);

    // 软删一个后可再建
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(user_delete(2) == BRIDGE_OK);
    REQUIRE(user_create("替补档案") > 1);

    db_close();
}

TEST_CASE("多用户 - db_replace 整库替换保留全部档案数据", "[multi_user]") {
    db_close();
    const std::string work = makeWorkDb("mu_replace");
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    // 档案 1 与档案 2 各写一条阅读历史
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);
    const int id2 = user_create("第二档案");
    REQUIRE(id2 > 1);
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(history_add_record(2, 90.0, 1700000001LL) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);
    db_close();

    // 新库 = 资产副本（无用户数据）
    const std::string newDb = work + ".new";
    fs::copy_file(TEST_DB_PATH, newDb, fs::copy_options::overwrite_existing);

    REQUIRE(db_replace(newDb.c_str(), work.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(work.c_str()) == BRIDGE_OK);

    REQUIRE(text_get_count() > 0);
    ProfileData profiles[8];
    const int n = user_list(profiles, 8);
    REQUIRE(n == 2);
    // 档案 2 数据保留
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);
    // 档案 1 数据保留
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);

    db_close();
}
