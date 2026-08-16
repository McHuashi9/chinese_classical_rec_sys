#include <catch_amalgamated.hpp>
#include "c_types.h"
#include "test_helpers.h"
#include "database/UserRepository.h"
#include <sqlite3.h>

#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <set>
#include <map>
#include <sstream>

namespace fs = std::filesystem;

extern "C" {
    int db_open(const char* content_path, const char* user_path);
    void db_close();
    int db_replace(const char* new_db_path, const char* cur_db_path);
    int user_list(ProfileData* out, int max_count);
    int user_active_id();
    int user_create(const char* name);
    int user_create_inherit(const char* name, int source_id);
    int user_switch(int id);
    int user_rename(int id, const char* name);
    int user_delete(int id);
    int user_load(UserData* out);
    int user_save(const UserData* in);
    int user_is_initialized();
    int user_init_questions(QuestionData* out, int max_count);
    int user_init_apply(const int* qids, const int* choices, int count, int64_t timestamp, UserData* out_user);
    int history_add_record(int text_id, double read_time, int64_t timestamp);
    int history_get_total_count();
    int history_get_tracked_text_ids(int* out, int max_count);
    int text_get_count();
    int recommend(const UserData* user, int top_k, int* out_ids, double* out_probs, int out_ids_capacity, int out_probs_capacity);
    int question_get_by_text(int text_id, QuestionData* out, int max_count, int* answered_all);
    int tracker_apply_quiz(const UserData* user, int question_id, int user_choice,
                           int64_t timestamp, UserData* out_user, int* out_correct, int is_review);
}

namespace {

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

}  // namespace

TEST_CASE("多用户 - 默认档案与档案 CRUD（新档案未初始化）", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_crud");
    const std::string user = test_helpers::makeUserDb("mu_crud");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 新库：默认档案 id=1 已就位，但未完成初始化
    REQUIRE(user_active_id() == 1);
    REQUIRE(user_is_initialized() == 0);
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

    // 切换后 active id 更新，新档案未初始化，但能力显示默认先验（0.3）
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(user_active_id() == id2);
    REQUIRE(user_is_initialized() == 0);
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
    const std::string content = test_helpers::makeContentDb("mu_isolation");
    const std::string user = test_helpers::makeUserDb("mu_isolation");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 档案 1 制造阅读历史（history_add_record 不要求初始化）
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

TEST_CASE("多用户 - 旧开发版 user.db（db_version=0）拒绝启动", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_old_user");
    const std::string user = test_helpers::makeUserDb("mu_old_user");

    // 构造旧版 user.db（无 initialized 列、db_version=0）
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(user.c_str(), &db) == SQLITE_OK);
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
        sqlite3_close(db);
    }

    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_ERR_DB_VERSION);
    db_close();
}

TEST_CASE("多用户 - 重名拒绝与档案数上限", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_limits");
    const std::string user = test_helpers::makeUserDb("mu_limits");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

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
    const std::string content = test_helpers::makeContentDb("mu_cap");
    const std::string user = test_helpers::makeUserDb("mu_cap");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

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

TEST_CASE("多用户 - db_replace 内容库替换保留全部档案数据", "[multi_user]") {
    db_close();
    const std::string dir = test_helpers::workDir("mu_replace");
    const std::string content = test_helpers::makeContentDb("mu_replace");
    const std::string user = test_helpers::makeUserDb("mu_replace");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 档案 1 与档案 2 各写一条阅读历史
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);
    const int id2 = user_create("第二档案");
    REQUIRE(id2 > 1);
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(history_add_record(2, 90.0, 1700000001LL) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);
    db_close();

    // 新内容包 = 同目录纯内容库
    const std::string newContent = dir + "/new_classical.db";
    fs::copy_file(TEST_DB_PATH, newContent, fs::copy_options::overwrite_existing);
    {
        sqlite3* db = nullptr;
        REQUIRE(sqlite3_open(newContent.c_str(), &db) == SQLITE_OK);
        for (const char* t : {"profiles", "user", "reading_history", "text_tracking",
                              "learning_increments", "quiz_attempts", "review_items"}) {
            const std::string sql = "DROP TABLE IF EXISTS " + std::string(t) + ";";
            sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr);
        }
        sqlite3_exec(db, "PRAGMA user_version = 1;", nullptr, nullptr, nullptr);
        sqlite3_close(db);
    }

    REQUIRE(db_replace(newContent.c_str(), content.c_str()) == BRIDGE_OK);
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

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

TEST_CASE("多用户 - 能力全 0 但有学习痕迹的档案不被重置为默认", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_zero_keep");
    const std::string user = test_helpers::makeUserDb("mu_zero_keep");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 新档案首次切换会初始化默认 0.3
    const int id2 = user_create("差生档案");
    REQUIRE(id2 > 1);
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    UserData u;
    REQUIRE(user_load(&u) == BRIDGE_OK);
    REQUIRE(u.base_abilities[0] == Catch::Approx(0.3));

    // 模拟真实差生：能力被负增量打到全 0，但基础能力/答题痕迹/阅读时间仍在
    for (int i = 0; i < 10; ++i) {
        u.abilities[i] = 0.0;
        u.base_abilities[i] = 0.3;
        u.quiz_counts[i] = 1;
    }
    u.eta = 0.08;
    u.last_read_time = 1700000000LL;
    REQUIRE(user_save(&u) == BRIDGE_OK);

    // 切回默认再切回：不得因平均能力为 0 被静默重置
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(user_load(&u) == BRIDGE_OK);
    for (int i = 0; i < 10; ++i) {
        REQUIRE(u.abilities[i] == Catch::Approx(0.0));
        REQUIRE(u.base_abilities[i] == Catch::Approx(0.3));
        REQUIRE(u.quiz_counts[i] == 1);
    }
    REQUIRE(u.last_read_time == 1700000000LL);

    db_close();
}

TEST_CASE("用户初始化 - 未初始化时正常功能被拒，初始化后可用", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_init_gate");
    const std::string user = test_helpers::makeUserDb("mu_init_gate");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);
    REQUIRE(user_is_initialized() == 0);

    // 未初始化：推荐、普通取题、普通答题、复习通道均被拒
    UserData u;
    REQUIRE(user_load(&u) == BRIDGE_OK);
    int out_ids[4] = {0};
    double out_probs[4] = {0};
    REQUIRE(recommend(&u, 4, out_ids, out_probs, 4, 4) == BRIDGE_ERR_INIT_INCOMPLETE);
    QuestionData qs[8];
    REQUIRE(question_get_by_text(1, qs, 4, nullptr) == BRIDGE_ERR_INIT_INCOMPLETE);
    UserData out;
    int correct = -1;
    REQUIRE(tracker_apply_quiz(&u, 1, 0, 1700000000LL, &out, &correct, 0) == BRIDGE_ERR_INIT_INCOMPLETE);

    // 初始化题可取且可一次性提交
    REQUIRE(user_init_questions(qs, 8) == 6);
    int qids[6] = {0};
    int choices[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < 6; i++) qids[i] = qs[i].id;
    REQUIRE(user_init_apply(qids, choices, 6, 1700000000LL, &out) == BRIDGE_OK);
    REQUIRE(user_is_initialized() == 1);

    // 初始化后正常功能可用
    REQUIRE(recommend(&out, 4, out_ids, out_probs, 4, 4) == BRIDGE_OK);
    REQUIRE(question_get_by_text(1, qs, 4, nullptr) >= 0);
    REQUIRE(tracker_apply_quiz(&out, qs[0].id, 0, 1700000000LL, &out, &correct, 0) == BRIDGE_OK);

    db_close();
}

TEST_CASE("用户初始化 - 初始化题不进入复习队列且普通取题排除", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_init_no_review");
    const std::string user = test_helpers::makeUserDb("mu_init_no_review");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    QuestionData qs[8];
    REQUIRE(user_init_questions(qs, 8) == 6);
    int qids[6] = {0};
    int choices[6] = {1, 1, 1, 1, 1, 1};  // 全选 1，必有一些答错/答对
    for (int i = 0; i < 6; i++) qids[i] = qs[i].id;
    UserData out;
    REQUIRE(user_init_apply(qids, choices, 6, 1700000000LL, &out) == BRIDGE_OK);

    // 初始化题不进入 review_items
    sqlite3* db = nullptr;
    REQUIRE(sqlite3_open(user.c_str(), &db) == SQLITE_OK);
    sqlite3_stmt* stmt = nullptr;
    int reviewCount = -1;
    if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM review_items", -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) reviewCount = sqlite3_column_int(stmt, 0);
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
    REQUIRE(reviewCount == 0);

    // 初始化题已写入 quiz_attempts 且 is_init=1；普通取题按已答排除
    for (int i = 0; i < 6; i++) {
        REQUIRE(sqliteText(user, "SELECT is_init FROM quiz_attempts WHERE question_id = " + std::to_string(qids[i])) == "1");
    }

    db_close();
}

TEST_CASE("用户初始化 - 后验落库与 quizCounts 更新", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_init_posterior");
    const std::string user = test_helpers::makeUserDb("mu_init_posterior");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    QuestionData qs[8];
    REQUIRE(user_init_questions(qs, 8) == 6);
    std::set<int> covered;
    for (int i = 0; i < 6; i++) {
        std::istringstream ss(qs[i].dims);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) covered.insert(std::atoi(tok.c_str()));
        }
    }
    REQUIRE(covered.size() >= 1);

    int qids[6] = {0};
    int choices[6] = {0, 0, 0, 0, 0, 0};
    for (int i = 0; i < 6; i++) qids[i] = qs[i].id;
    UserData out;
    REQUIRE(user_init_apply(qids, choices, 6, 1700000000LL, &out) == BRIDGE_OK);

    // 覆盖维度 quizCount 更新为观察数；未覆盖维度保持先验 0.3
    std::map<int, int> dimCount;
    for (int i = 0; i < 6; i++) {
        std::istringstream ss(qs[i].dims);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) dimCount[std::atoi(tok.c_str())]++;
        }
    }
    for (int d = 0; d < 10; d++) {
        if (covered.count(d)) {
            REQUIRE(out.quiz_counts[d] == dimCount[d]);
            REQUIRE(out.base_abilities[d] == Catch::Approx(out.abilities[d]).margin(1e-9));
        } else {
            REQUIRE(out.quiz_counts[d] == 0);
            REQUIRE(out.abilities[d] == Catch::Approx(0.3));
        }
    }
    // eta 保持默认
    REQUIRE(out.eta == Catch::Approx(0.08));

    // 落库：user.initialized=1、quiz_attempts 6 条 is_init=1、review_items 空
    REQUIRE(user_is_initialized() == 1);
    REQUIRE(sqliteText(user, "SELECT COUNT(*) FROM quiz_attempts WHERE is_init = 1") == "6");
    REQUIRE(sqliteText(user, "SELECT COUNT(*) FROM review_items") == "0");

    db_close();
}

TEST_CASE("新建档案继承 - user_create_inherit 原子复制能力与历史", "[multi_user]") {
    db_close();
    const std::string content = test_helpers::makeContentDb("mu_inherit");
    const std::string user = test_helpers::makeUserDb("mu_inherit");
    REQUIRE(db_open(content.c_str(), user.c_str()) == BRIDGE_OK);

    // 初始化档案 1
    initDefaultProfile();
    UserData base;
    REQUIRE(user_load(&base) == BRIDGE_OK);
    REQUIRE(history_add_record(1, 60.0, 1700000000LL) == BRIDGE_OK);
    REQUIRE(user_save(&base) == BRIDGE_OK);

    // 继承创建
    const int id2 = user_create_inherit("继承者", 1);
    REQUIRE(id2 > 1);
    REQUIRE(user_is_initialized() == 1);  // 仍在档案 1，新档案尚未切换
    REQUIRE(user_switch(id2) == BRIDGE_OK);
    REQUIRE(user_is_initialized() == 1);

    UserData inherited;
    REQUIRE(user_load(&inherited) == BRIDGE_OK);
    for (int i = 0; i < 10; i++) {
        REQUIRE(inherited.base_abilities[i] == Catch::Approx(base.base_abilities[i]));
        REQUIRE(inherited.quiz_counts[i] == base.quiz_counts[i]);
    }
    REQUIRE(history_get_total_count() == 1);

    // 源档案数据仍在
    REQUIRE(user_switch(1) == BRIDGE_OK);
    REQUIRE(history_get_total_count() == 1);

    db_close();
}
