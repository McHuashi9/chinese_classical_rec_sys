#include "database/UserRepository.h"
#include "database/schema_introspect.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <ctime>
#include <set>
#include <unordered_map>
#include <functional>
#include <utility>
#include <vector>

using dbschema::copyCommonColumns;
using dbschema::tableColumns;
using dbschema::tableExists;
using dbschema::tableSql;

UserRepository::UserRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool UserRepository::initTable() {
    sqlite3* c = db->getConnection();
    if (!c) return false;

    // 论文10维能力向量：d1-d10；多用户化：id 为普通主键，无 CHECK(id=1)
    const char* newUserSql =
        "CREATE TABLE IF NOT EXISTS user ("
        "id INTEGER PRIMARY KEY, "
        "d1_ability REAL DEFAULT 0.0, "  // f1 平均句长
        "d2_ability REAL DEFAULT 0.0, "  // f3 句子数
        "d3_ability REAL DEFAULT 0.0, "  // f5 虚词比例
        "d4_ability REAL DEFAULT 0.0, "  // f6 字平均对数频次
        "d5_ability REAL DEFAULT 0.0, "  // f8 通假字密度
        "d6_ability REAL DEFAULT 0.0, "  // f9 古汉语困惑度
        "d7_ability REAL DEFAULT 0.0, "  // f10 今汉语困惑度
        "d8_ability REAL DEFAULT 0.0, "  // f11 MATTR词汇多样性
        "d9_ability REAL DEFAULT 0.0, "  // f12 典故密度
        "d10_ability REAL DEFAULT 0.0, " // f13 语义复杂度
        "d1_base_ability REAL DEFAULT 0.0, "  // d1 基础能力
        "d2_base_ability REAL DEFAULT 0.0, "  // d2 基础能力
        "d3_base_ability REAL DEFAULT 0.0, "  // d3 基础能力
        "d4_base_ability REAL DEFAULT 0.0, "  // d4 基础能力
        "d5_base_ability REAL DEFAULT 0.0, "  // d5 基础能力
        "d6_base_ability REAL DEFAULT 0.0, "  // d6 基础能力
        "d7_base_ability REAL DEFAULT 0.0, "  // d7 基础能力
        "d8_base_ability REAL DEFAULT 0.0, "  // d8 基础能力
        "d9_base_ability REAL DEFAULT 0.0, "  // d9 基础能力
        "d10_base_ability REAL DEFAULT 0.0, " // d10 基础能力
        "eta REAL DEFAULT 0.08, "            // 悟性（答题效应动态调整）
        "d1_quiz_count INTEGER DEFAULT 0, "
        "d2_quiz_count INTEGER DEFAULT 0, "
        "d3_quiz_count INTEGER DEFAULT 0, "
        "d4_quiz_count INTEGER DEFAULT 0, "
        "d5_quiz_count INTEGER DEFAULT 0, "
        "d6_quiz_count INTEGER DEFAULT 0, "
        "d7_quiz_count INTEGER DEFAULT 0, "
        "d8_quiz_count INTEGER DEFAULT 0, "
        "d9_quiz_count INTEGER DEFAULT 0, "
        "d10_quiz_count INTEGER DEFAULT 0, "
        "last_read_time INTEGER DEFAULT 0, "  // 最后阅读时间戳
        "initialized INTEGER NOT NULL DEFAULT 0"  // 强制初始化完成标记
        ");";

    // 档案元数据表（多用户）
    const char* profilesSql =
        "CREATE TABLE IF NOT EXISTS profiles ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "name TEXT NOT NULL, "
        "created_at INTEGER NOT NULL, "
        "last_used_at INTEGER NOT NULL, "
        "deleted INTEGER NOT NULL DEFAULT 0"
        ");";

    if (!db->executeSQL(profilesSql)) {
        LOG_ERROR("UserRepository::initTable profiles failed: {}", db->getLastError());
        return false;
    }

    // 老库迁移：user 表带 CHECK(id=1) → 重建为普通主键多行表（SQLite 无法直接删 CHECK）
    if (tableExists(c, "user")) {
        const std::string oldSql = tableSql(c, "user");
        if (oldSql.find("CHECK") != std::string::npos) {
            LOG_INFO("UserRepository: 检测到 user 表 CHECK(id=1)，迁移为多用户 schema");
            if (!db->executeSQL("ALTER TABLE user RENAME TO user_old;")) {
                LOG_ERROR("UserRepository: user 重命名失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL(newUserSql)) {
                LOG_ERROR("UserRepository: 新 user 表创建失败: {}", db->getLastError());
                return false;
            }
            if (!copyCommonColumns(c, "user_old", "user")) {
                return false;
            }
            if (!db->executeSQL("DROP TABLE user_old;")) {
                LOG_ERROR("UserRepository: 删除 user_old 失败: {}", db->getLastError());
                return false;
            }
        }
    } else if (!db->executeSQL(newUserSql)) {
        LOG_ERROR("UserRepository::initTable user failed: {}", db->getLastError());
        return false;
    }

    // 迁移：为旧数据库添加 last_read_time 列（如果不存在）
    db->executeSQL("ALTER TABLE user ADD COLUMN last_read_time INTEGER DEFAULT 0;");  // 忽略错误

    // v1.0.0：强制初始化标记（仅版本 1 用户库可能缺列时补，旧 0 版会在 db_open 阶段被拒）
    db->executeSQL("ALTER TABLE user ADD COLUMN initialized INTEGER NOT NULL DEFAULT 0;");  // 忽略错误

    // 迁移：移除已弃用的 name 列（如果存在）
    db->executeSQL("ALTER TABLE user DROP COLUMN name;");  // 忽略错误（列不存在或 SQLite < 3.35.0）

    // 迁移：添加基础能力字段（如果不存在）
    const char* baseAbilityMigrations[] = {
        "ALTER TABLE user ADD COLUMN d1_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d2_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d3_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d4_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d5_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d6_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d7_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d8_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d9_base_ability REAL DEFAULT 0.0;",
        "ALTER TABLE user ADD COLUMN d10_base_ability REAL DEFAULT 0.0;"
    };
    for (const char* migrate : baseAbilityMigrations) {
        db->executeSQL(migrate);  // 忽略错误（列已存在时会失败）
    }

    // 迁移：悟性 η 与累计答题次数 N_j（答题效应，论文§5.3）
    const char* quizMigrations[] = {
        "ALTER TABLE user ADD COLUMN eta REAL DEFAULT 0.08;",
        "ALTER TABLE user ADD COLUMN d1_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d2_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d3_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d4_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d5_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d6_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d7_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d8_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d9_quiz_count INTEGER DEFAULT 0;",
        "ALTER TABLE user ADD COLUMN d10_quiz_count INTEGER DEFAULT 0;"
    };
    for (const char* migrate : quizMigrations) {
        db->executeSQL(migrate);  // 忽略错误（列已存在时会失败）
    }

    // 测验闭环（作答流水 + 错题复习状态）：用户库无版本号机制，
    // CREATE IF NOT EXISTS 幂等建表 + ALTER 补列，旧库打开即自动迁移
    const char* quizAttemptsSql =
        "CREATE TABLE IF NOT EXISTS quiz_attempts ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "user_id INTEGER NOT NULL DEFAULT 1, "   // 多用户：当前档案 id
        "question_id INTEGER NOT NULL, "          // questions.id（内容库）
        "text_id INTEGER NOT NULL, "
        "correct INTEGER NOT NULL, "              // 0/1
        "is_review INTEGER DEFAULT 0, "           // 0=正式测验 1=错题复习
        "is_init INTEGER DEFAULT 0, "             // 1=强制初始化题（不再普通出现）
        "answered_at INTEGER NOT NULL"            // unix 秒
        ");";
    const char* reviewItemsSql =
        "CREATE TABLE IF NOT EXISTS review_items ("
        "question_id INTEGER NOT NULL, "          // 错题（quiz_attempts 中答错过的题）
        "user_id INTEGER NOT NULL DEFAULT 1, "    // 多用户：当前档案 id
        "text_id INTEGER NOT NULL, "
        "correct_streak INTEGER DEFAULT 0, "      // 连续答对次数（调度翻倍用）
        "wrong_count INTEGER DEFAULT 0, "
        "next_review_at INTEGER NOT NULL, "       // 下次到期时间
        "PRIMARY KEY (user_id, question_id)"
        ");";
    const char* quizAttemptsIdxSql =
        "CREATE INDEX IF NOT EXISTS idx_quiz_attempts_text ON quiz_attempts(text_id, question_id);";
    const char* quizAttemptsUserIdxSql =
        "CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user_text ON quiz_attempts(user_id, text_id, question_id);";

    if (!db->executeSQL(quizAttemptsSql) || !db->executeSQL(reviewItemsSql)) {
        LOG_ERROR("UserRepository::initTable quiz tables failed: {}", db->getLastError());
        return false;
    }

    // 旧 quiz_attempts 表补 user_id 列（必须先于依赖该列的索引创建）
    db->executeSQL("ALTER TABLE quiz_attempts ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1;");  // 忽略错误

    // v1.0.0：初始化题标记
    db->executeSQL("ALTER TABLE quiz_attempts ADD COLUMN is_init INTEGER DEFAULT 0;");  // 忽略错误

    if (!db->executeSQL(quizAttemptsIdxSql) || !db->executeSQL(quizAttemptsUserIdxSql)) {
        LOG_ERROR("UserRepository::initTable quiz index failed: {}", db->getLastError());
        return false;
    }

    // 旧 review_items 表（单列主键 question_id）→ 重建为复合主键 (user_id, question_id)
    if (tableExists(c, "review_items")) {
        const std::string oldSql = tableSql(c, "review_items");
        const bool oldPk = oldSql.find("question_id INTEGER PRIMARY KEY") != std::string::npos;
        const bool hasUserId = tableColumns(c, "review_items").count("user_id") != 0;
        if (oldPk || !hasUserId) {
            LOG_INFO("UserRepository: 检测到 review_items 旧主键，迁移为 (user_id, question_id)");
            if (!db->executeSQL("ALTER TABLE review_items RENAME TO review_items_old;")) {
                LOG_ERROR("UserRepository: review_items 重命名失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL(reviewItemsSql)) {
                LOG_ERROR("UserRepository: 新 review_items 创建失败: {}", db->getLastError());
                return false;
            }
            if (!copyCommonColumns(c, "review_items_old", "review_items")) {
                return false;
            }
            if (!db->executeSQL("DROP TABLE review_items_old;")) {
                LOG_ERROR("UserRepository: 删除 review_items_old 失败: {}", db->getLastError());
                return false;
            }
        }
    }

    // 档案行与 user 行对齐：老库 id=1 数据归入"默认用户"档案
    if (!db->executeSQL(
        "INSERT OR IGNORE INTO profiles (id, name, created_at, last_used_at, deleted) "
        "SELECT id, '默认用户', strftime('%s','now'), strftime('%s','now'), 0 FROM user;")) {
        LOG_ERROR("UserRepository::initTable 档案对齐失败: {}", db->getLastError());
        return false;
    }

    return true;
}

static int getUserCallback(void* data, int argc, char** argv, char** azColName) {
    struct GetUserData {
        User* user;
        bool found;
    };
    auto* gd = static_cast<GetUserData*>(data);
    User* user = gd->user;
    gd->found = true;
    
    // 字段映射表：列名 -> setter函数
    static const std::unordered_map<std::string, std::function<void(User*, const char*)>> fieldMap = {
        {"d1_ability", [](User* u, const char* v) { u->setAbility(0, std::atof(v)); }},
        {"d2_ability", [](User* u, const char* v) { u->setAbility(1, std::atof(v)); }},
        {"d3_ability", [](User* u, const char* v) { u->setAbility(2, std::atof(v)); }},
        {"d4_ability", [](User* u, const char* v) { u->setAbility(3, std::atof(v)); }},
        {"d5_ability", [](User* u, const char* v) { u->setAbility(4, std::atof(v)); }},
        {"d6_ability", [](User* u, const char* v) { u->setAbility(5, std::atof(v)); }},
        {"d7_ability", [](User* u, const char* v) { u->setAbility(6, std::atof(v)); }},
        {"d8_ability", [](User* u, const char* v) { u->setAbility(7, std::atof(v)); }},
        {"d9_ability", [](User* u, const char* v) { u->setAbility(8, std::atof(v)); }},
        {"d10_ability", [](User* u, const char* v) { u->setAbility(9, std::atof(v)); }},
        {"d1_base_ability", [](User* u, const char* v) { u->setBaseAbility(0, std::atof(v)); }},
        {"d2_base_ability", [](User* u, const char* v) { u->setBaseAbility(1, std::atof(v)); }},
        {"d3_base_ability", [](User* u, const char* v) { u->setBaseAbility(2, std::atof(v)); }},
        {"d4_base_ability", [](User* u, const char* v) { u->setBaseAbility(3, std::atof(v)); }},
        {"d5_base_ability", [](User* u, const char* v) { u->setBaseAbility(4, std::atof(v)); }},
        {"d6_base_ability", [](User* u, const char* v) { u->setBaseAbility(5, std::atof(v)); }},
        {"d7_base_ability", [](User* u, const char* v) { u->setBaseAbility(6, std::atof(v)); }},
        {"d8_base_ability", [](User* u, const char* v) { u->setBaseAbility(7, std::atof(v)); }},
        {"d9_base_ability", [](User* u, const char* v) { u->setBaseAbility(8, std::atof(v)); }},
        {"d10_base_ability", [](User* u, const char* v) { u->setBaseAbility(9, std::atof(v)); }},
        {"eta", [](User* u, const char* v) { u->setEta(std::atof(v)); }},
        {"d1_quiz_count", [](User* u, const char* v) { u->setQuizCount(0, std::atoi(v)); }},
        {"d2_quiz_count", [](User* u, const char* v) { u->setQuizCount(1, std::atoi(v)); }},
        {"d3_quiz_count", [](User* u, const char* v) { u->setQuizCount(2, std::atoi(v)); }},
        {"d4_quiz_count", [](User* u, const char* v) { u->setQuizCount(3, std::atoi(v)); }},
        {"d5_quiz_count", [](User* u, const char* v) { u->setQuizCount(4, std::atoi(v)); }},
        {"d6_quiz_count", [](User* u, const char* v) { u->setQuizCount(5, std::atoi(v)); }},
        {"d7_quiz_count", [](User* u, const char* v) { u->setQuizCount(6, std::atoi(v)); }},
        {"d8_quiz_count", [](User* u, const char* v) { u->setQuizCount(7, std::atoi(v)); }},
        {"d9_quiz_count", [](User* u, const char* v) { u->setQuizCount(8, std::atoi(v)); }},
        {"d10_quiz_count", [](User* u, const char* v) { u->setQuizCount(9, std::atoi(v)); }},
        {"last_read_time", [](User* u, const char* v) { u->setLastReadTime(static_cast<time_t>(std::atol(v))); }}
    };
    
    for (int i = 0; i < argc; i++) {
        if (argv[i]) {
            auto it = fieldMap.find(azColName[i]);
            if (it != fieldMap.end()) {
                it->second(user, argv[i]);
            }
        }
    }
    
    return 0;
}

bool UserRepository::getUser(User& user, int userId) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    const std::string sql = "SELECT d1_ability, d2_ability, d3_ability, d4_ability, "
                      "d5_ability, d6_ability, d7_ability, d8_ability, d9_ability, d10_ability, "
                      "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
                      "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
                      "d9_base_ability, d10_base_ability, eta, "
                      "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
                      "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
                      "last_read_time "
                      "FROM user WHERE id = " + std::to_string(userId) + ";";
    char* errMsg = nullptr;

    struct GetUserData { User* user; bool found = false; } gd = {&user, false};
    
    int rc = sqlite3_exec(db->getConnection(), sql.c_str(), getUserCallback, &gd, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询用户失败: {}", errMsg);
        sqlite3_free(errMsg);
        return false;
    }
    
    return gd.found;
}

bool UserRepository::saveUser(const User& user, int userId) {
    // 单条 UPSERT：UPDATE 分支用 excluded.<col> 引用 INSERT 值，
    // 占位符只需一份（id + 32 能力列），避免手写两遍参数列表错位（N-x）
    std::vector<SqlParam> params;
    params.emplace_back(userId);
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getAbility(i));
    }
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getBaseAbility(i));
    }
    params.emplace_back(user.getEta());
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getQuizCount(i));
    }
    params.emplace_back(static_cast<double>(user.getLastReadTime()));

    return db->executeSQL(
"INSERT INTO user (id, "
        "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
        "d7_ability, d8_ability, d9_ability, d10_ability, "
        "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
        "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
        "d9_base_ability, d10_base_ability, eta, "
        "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
        "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
        "last_read_time) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
        "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "d1_ability = excluded.d1_ability, d2_ability = excluded.d2_ability, "
        "d3_ability = excluded.d3_ability, d4_ability = excluded.d4_ability, "
        "d5_ability = excluded.d5_ability, d6_ability = excluded.d6_ability, "
        "d7_ability = excluded.d7_ability, d8_ability = excluded.d8_ability, "
        "d9_ability = excluded.d9_ability, d10_ability = excluded.d10_ability, "
        "d1_base_ability = excluded.d1_base_ability, "
        "d2_base_ability = excluded.d2_base_ability, "
        "d3_base_ability = excluded.d3_base_ability, "
        "d4_base_ability = excluded.d4_base_ability, "
        "d5_base_ability = excluded.d5_base_ability, "
        "d6_base_ability = excluded.d6_base_ability, "
        "d7_base_ability = excluded.d7_base_ability, "
        "d8_base_ability = excluded.d8_base_ability, "
        "d9_base_ability = excluded.d9_base_ability, "
        "d10_base_ability = excluded.d10_base_ability, "
        "eta = excluded.eta, "
        "d1_quiz_count = excluded.d1_quiz_count, "
        "d2_quiz_count = excluded.d2_quiz_count, "
        "d3_quiz_count = excluded.d3_quiz_count, "
        "d4_quiz_count = excluded.d4_quiz_count, "
        "d5_quiz_count = excluded.d5_quiz_count, "
        "d6_quiz_count = excluded.d6_quiz_count, "
        "d7_quiz_count = excluded.d7_quiz_count, "
        "d8_quiz_count = excluded.d8_quiz_count, "
        "d9_quiz_count = excluded.d9_quiz_count, "
        "d10_quiz_count = excluded.d10_quiz_count, "
        "last_read_time = excluded.last_read_time;",
        params
    );
}

std::vector<ProfileInfo> UserRepository::listProfiles() {
    std::vector<ProfileInfo> out;
    if (!db || !db->getConnection()) return out;

    const char* sql = "SELECT id, name, deleted, created_at, last_used_at "
                      "FROM profiles WHERE deleted = 0 ORDER BY id ASC;";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("查询档案列表失败: {}", db->getLastError());
        return out;
    }
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ProfileInfo p;
        p.id = sqlite3_column_int(stmt, 0);
        const unsigned char* name = sqlite3_column_text(stmt, 1);
        if (name) p.name = reinterpret_cast<const char*>(name);
        p.deleted = sqlite3_column_int(stmt, 2);
        p.createdAt = sqlite3_column_int64(stmt, 3);
        p.lastUsedAt = sqlite3_column_int64(stmt, 4);
        out.push_back(std::move(p));
    }
    sqlite3_finalize(stmt);
    return out;
}

bool UserRepository::createProfile(const std::string& name, int& outId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("createProfile BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    // 未删除档案同名拒绝（软删档案名可复用）；上限保护（防 UI 绕过/未来多端并发）
    {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT COUNT(*) FROM profiles WHERE deleted = 0;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            const int count = (sqlite3_step(chk) == SQLITE_ROW) ? sqlite3_column_int(chk, 0) : -1;
            sqlite3_finalize(chk);
            if (count < 0) {
                ok = false;
            } else if (count >= kMaxProfiles) {
                LOG_WARN("createProfile 已达上限 {} 个档案，拒绝创建 {}", kMaxProfiles, name);
                ok = false;
            }
        }
    }
    if (ok) {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT 1 FROM profiles WHERE deleted = 0 AND name = ?;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_text(chk, 1, name.c_str(), -1, SQLITE_TRANSIENT);
            const bool dup = (sqlite3_step(chk) == SQLITE_ROW);
            sqlite3_finalize(chk);
            if (dup) {
                LOG_WARN("createProfile 重名拒绝: {}", name);
                ok = false;
            }
        }
    }

    sqlite3_stmt* stmt = nullptr;
    const int64_t now = static_cast<int64_t>(time(nullptr));
    if (ok && sqlite3_prepare_v2(c, "INSERT INTO profiles(name, created_at, last_used_at, deleted) "
                              "VALUES (?, ?, ?, 0);", -1, &stmt, nullptr) != SQLITE_OK) {
        ok = false;
    } else if (ok) {
        sqlite3_bind_text(stmt, 1, name.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, now);
        sqlite3_bind_int64(stmt, 3, now);
        ok = sqlite3_step(stmt) == SQLITE_DONE;
        sqlite3_finalize(stmt);
    }
    if (ok) {
        outId = static_cast<int>(sqlite3_last_insert_rowid(c));
        // 能力等数据仍按 id 存 user 表：先建默认行，切换/首读时再初始化能力默认值
        sqlite3_stmt* u = nullptr;
        if (sqlite3_prepare_v2(c, "INSERT OR IGNORE INTO user(id) VALUES (?);", -1, &u, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_int(u, 1, outId);
            ok = sqlite3_step(u) == SQLITE_DONE;
            sqlite3_finalize(u);
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::renameProfile(int userId, const std::string& name) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    sqlite3_stmt* stmt = nullptr;
    // 同名拒绝（排除自身，仅未删除档案参与比较）
    const char* sql =
        "UPDATE profiles SET name = ? "
        "WHERE id = ? AND deleted = 0 "
        "AND NOT EXISTS (SELECT 1 FROM profiles WHERE deleted = 0 AND name = ? AND id <> ?);";
    if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("renameProfile prepare 失败: {}", sqlite3_errmsg(c));
        return false;
    }
    sqlite3_bind_text(stmt, 1, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, userId);
    sqlite3_bind_text(stmt, 3, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 4, userId);
    const int rc = sqlite3_step(stmt);
    const int changes = sqlite3_changes(c);
    sqlite3_finalize(stmt);
    return rc == SQLITE_DONE && changes > 0;
}

namespace {

// 删除某档案在全部用户表中的数据（不含 profiles 行本身）。
bool deleteUserDataRows(sqlite3* c, int userId)
{
    const char* statements[] = {
        "DELETE FROM user WHERE id = ?;",
        "DELETE FROM reading_history WHERE user_id = ?;",
        "DELETE FROM text_tracking WHERE user_id = ?;",
        "DELETE FROM learning_increments WHERE user_id = ?;",
        "DELETE FROM quiz_attempts WHERE user_id = ?;",
        "DELETE FROM review_items WHERE user_id = ?;",
    };
    for (const char* sql : statements) {
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("deleteUserDataRows prepare 失败: {}", sqlite3_errmsg(c));
            return false;
        }
        sqlite3_bind_int(stmt, 1, userId);
        const int rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        if (rc != SQLITE_DONE) {
            LOG_ERROR("deleteUserDataRows 执行失败 rc={}", rc);
            return false;
        }
    }
    return true;
}

}  // namespace

bool UserRepository::deleteProfile(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("deleteProfile BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;",
                               -1, &chk, nullptr) != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_int(chk, 1, userId);
            ok = sqlite3_step(chk) == SQLITE_ROW;
            sqlite3_finalize(chk);
        }
    }
    if (ok) {
        ok = deleteUserDataRows(c, userId);
    }
    if (ok) {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "DELETE FROM profiles WHERE id = ? AND deleted = 0;";
        if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_int(stmt, 1, userId);
            const int rc = sqlite3_step(stmt);
            const int changes = sqlite3_changes(c);
            sqlite3_finalize(stmt);
            ok = rc == SQLITE_DONE && changes > 0;
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::purgeDeletedProfiles() {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    std::vector<int> ids;
    {
        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT id FROM profiles WHERE deleted = 1;",
                               -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("purgeDeletedProfiles 查询失败: {}", sqlite3_errmsg(c));
            return false;
        }
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            ids.push_back(sqlite3_column_int(stmt, 0));
        }
        sqlite3_finalize(stmt);
    }
    if (ids.empty()) return true;

    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("purgeDeletedProfiles BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    for (const int id : ids) {
        if (!deleteUserDataRows(c, id)) {
            ok = false;
            break;
        }
        sqlite3_stmt* del = nullptr;
        const char* sql = "DELETE FROM profiles WHERE id = ? AND deleted = 1;";
        if (sqlite3_prepare_v2(c, sql, -1, &del, nullptr) != SQLITE_OK) {
            ok = false;
            break;
        }
        sqlite3_bind_int(del, 1, id);
        if (sqlite3_step(del) != SQLITE_DONE) {
            ok = false;
        }
        sqlite3_finalize(del);
        if (!ok) break;
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::isProfileActive(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;";
    if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int(stmt, 1, userId);
    const bool active = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);
    return active;
}

bool UserRepository::touchProfile(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "UPDATE profiles SET last_used_at = ? WHERE id = ? AND deleted = 0;";
    if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, static_cast<int64_t>(time(nullptr)));
    sqlite3_bind_int(stmt, 2, userId);
    const bool ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

bool UserRepository::ensureProfileExists(int userId, const std::string& name) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    sqlite3_stmt* stmt = nullptr;
    const int64_t now = static_cast<int64_t>(time(nullptr));
    const char* sql = "INSERT OR IGNORE INTO profiles(id, name, created_at, last_used_at, deleted) "
                      "VALUES (?, ?, ?, ?, 0);";
    if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int(stmt, 1, userId);
    sqlite3_bind_text(stmt, 2, name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 3, now);
    sqlite3_bind_int64(stmt, 4, now);
    const bool ok = sqlite3_step(stmt) == SQLITE_DONE;
    sqlite3_finalize(stmt);
    return ok;
}

bool UserRepository::isInitialized(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT initialized FROM user WHERE id = ?;";
    if (sqlite3_prepare_v2(c, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int(stmt, 1, userId);
    bool initialized = false;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        initialized = sqlite3_column_int(stmt, 0) != 0;
    }
    sqlite3_finalize(stmt);
    return initialized;
}

bool UserRepository::setInitialized(int userId) {
    if (!db || !db->getConnection()) return false;
    return db->executeSQL(
        "UPDATE user SET initialized = 1 WHERE id = ?;",
        std::vector<SqlParam>{userId}
    );
}

bool UserRepository::createProfileInherit(const std::string& name, int sourceId, int& outId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("createProfileInherit BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    // 与 createProfile 相同的约束：上限、未删除档案重名拒绝
    {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT COUNT(*) FROM profiles WHERE deleted = 0;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            const int count = (sqlite3_step(chk) == SQLITE_ROW) ? sqlite3_column_int(chk, 0) : -1;
            sqlite3_finalize(chk);
            if (count < 0 || count >= kMaxProfiles) {
                LOG_WARN("createProfileInherit 已达上限 {} 个档案，拒绝创建 {}", kMaxProfiles, name);
                ok = false;
            }
        }
    }
    if (ok) {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT 1 FROM profiles WHERE deleted = 0 AND name = ?;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_text(chk, 1, name.c_str(), -1, SQLITE_TRANSIENT);
            const bool dup = (sqlite3_step(chk) == SQLITE_ROW);
            sqlite3_finalize(chk);
            if (dup) {
                LOG_WARN("createProfileInherit 重名拒绝: {}", name);
                ok = false;
            }
        }
    }
    // 源档案必须存在、未删除且已完成初始化
    if (ok) {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_int(chk, 1, sourceId);
            const bool active = (sqlite3_step(chk) == SQLITE_ROW);
            sqlite3_finalize(chk);
            if (!active) {
                LOG_WARN("createProfileInherit 源档案不存在或已删除 id={}", sourceId);
                ok = false;
            }
        }
    }
    if (ok) {
        sqlite3_stmt* chk = nullptr;
        if (sqlite3_prepare_v2(c, "SELECT initialized FROM user WHERE id = ?;", -1, &chk, nullptr)
            != SQLITE_OK) {
            ok = false;
        } else {
            sqlite3_bind_int(chk, 1, sourceId);
            const bool initialized = (sqlite3_step(chk) == SQLITE_ROW) && sqlite3_column_int(chk, 0) != 0;
            sqlite3_finalize(chk);
            if (!initialized) {
                LOG_WARN("createProfileInherit 源档案未完成初始化 id={}", sourceId);
                ok = false;
            }
        }
    }

    const int64_t now = static_cast<int64_t>(time(nullptr));
    sqlite3_stmt* stmt = nullptr;
    if (ok && sqlite3_prepare_v2(c, "INSERT INTO profiles(name, created_at, last_used_at, deleted) "
                               "VALUES (?, ?, ?, 0);", -1, &stmt, nullptr) != SQLITE_OK) {
        ok = false;
    } else if (ok) {
        sqlite3_bind_text(stmt, 1, name.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int64(stmt, 2, now);
        sqlite3_bind_int64(stmt, 3, now);
        ok = sqlite3_step(stmt) == SQLITE_DONE;
        sqlite3_finalize(stmt);
    }
    if (ok) {
        outId = static_cast<int>(sqlite3_last_insert_rowid(c));
    }

    // 复制 user 能力（新档案 initialized=1）
    if (ok) {
        const char* sql =
            "INSERT INTO user (id, "
            "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
            "d7_ability, d8_ability, d9_ability, d10_ability, "
            "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
            "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
            "d9_base_ability, d10_base_ability, eta, "
            "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
            "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
            "last_read_time, initialized) "
            "SELECT ?, "
            "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
            "d7_ability, d8_ability, d9_ability, d10_ability, "
            "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
            "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
            "d9_base_ability, d10_base_ability, eta, "
            "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
            "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
            "last_read_time, 1 FROM user WHERE id = ?;";
        sqlite3_stmt* u = nullptr;
        if (sqlite3_prepare_v2(c, sql, -1, &u, nullptr) != SQLITE_OK) {
            LOG_ERROR("createProfileInherit 复制 user 准备失败: {}", sqlite3_errmsg(c));
            ok = false;
        } else {
            sqlite3_bind_int(u, 1, outId);
            sqlite3_bind_int(u, 2, sourceId);
            ok = sqlite3_step(u) == SQLITE_DONE;
            sqlite3_finalize(u);
        }
    }

    // 复制各历史表（自增 id 不复制，user_id 改新档案 id）
    if (ok) {
        const char* copies[] = {
            "INSERT INTO reading_history (user_id, text_id, read_time, read_timestamp) "
            "SELECT ?, text_id, read_time, read_timestamp FROM reading_history WHERE user_id = ?;",
            "INSERT OR IGNORE INTO text_tracking (user_id, text_id, tracked_at) "
            "SELECT ?, text_id, tracked_at FROM text_tracking WHERE user_id = ?;",
            "INSERT INTO learning_increments (user_id, dimension, delta, timestamp, type) "
            "SELECT ?, dimension, delta, timestamp, type FROM learning_increments WHERE user_id = ?;",
            "INSERT INTO quiz_attempts (user_id, question_id, text_id, correct, is_review, is_init, answered_at) "
            "SELECT ?, question_id, text_id, correct, is_review, is_init, answered_at FROM quiz_attempts WHERE user_id = ?;",
            "INSERT OR IGNORE INTO review_items (user_id, question_id, text_id, correct_streak, wrong_count, next_review_at) "
            "SELECT ?, question_id, text_id, correct_streak, wrong_count, next_review_at FROM review_items WHERE user_id = ?;",
        };
        for (const char* sql : copies) {
            sqlite3_stmt* s = nullptr;
            if (sqlite3_prepare_v2(c, sql, -1, &s, nullptr) != SQLITE_OK) {
                LOG_ERROR("createProfileInherit 复制表准备失败: {}", sqlite3_errmsg(c));
                ok = false;
                break;
            }
            sqlite3_bind_int(s, 1, outId);
            sqlite3_bind_int(s, 2, sourceId);
            if (sqlite3_step(s) != SQLITE_DONE) {
                LOG_ERROR("createProfileInherit 复制表失败: {}", sqlite3_errmsg(c));
                ok = false;
            }
            sqlite3_finalize(s);
            if (!ok) break;
        }
    }

    // 自增序列对齐（profiles 已由 AUTOINCREMENT 自动维护，其余显式插入后保险对齐）
    if (ok) {
        for (const char* seqTable : {"reading_history", "learning_increments", "quiz_attempts", "profiles"}) {
            const std::string upd = "UPDATE sqlite_sequence SET seq = "
                "(SELECT COALESCE(MAX(id),0) FROM " + std::string(seqTable) + ") "
                "WHERE name='" + std::string(seqTable) + "'";
            sqlite3_exec(c, upd.c_str(), nullptr, nullptr, nullptr);  // 失败忽略（无序列条目正常）
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}
