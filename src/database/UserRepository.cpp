#include "database/UserRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <unordered_map>
#include <functional>

UserRepository::UserRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool UserRepository::initTable() {
    // 论文10维能力向量：d1-d10
    const char* sql = 
        "CREATE TABLE IF NOT EXISTS user ("
        "id INTEGER PRIMARY KEY CHECK (id = 1), "
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
        "last_read_time INTEGER DEFAULT 0"  // 最后阅读时间戳
        ");";
    
    bool result = db->executeSQL(sql);
    if (!result) {
        LOG_ERROR("UserRepository::initTable failed: {}", db->getLastError());
        return false;
    }
    
    // 迁移：为旧数据库添加 last_read_time 列（如果不存在）
    const char* migrateSql = "ALTER TABLE user ADD COLUMN last_read_time INTEGER DEFAULT 0;";
    db->executeSQL(migrateSql);  // 忽略错误

    // 迁移：移除已弃用的 name 列（如果存在）
    const char* dropNameSql = "ALTER TABLE user DROP COLUMN name;";
    db->executeSQL(dropNameSql);  // 忽略错误（列不存在或 SQLite < 3.35.0）
    
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
    // CREATE IF NOT EXISTS 幂等建表，旧库打开即自动迁移
    const char* quizAttemptsSql =
        "CREATE TABLE IF NOT EXISTS quiz_attempts ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "question_id INTEGER NOT NULL, "     // questions.id（内容库）
        "text_id INTEGER NOT NULL, "
        "correct INTEGER NOT NULL, "         // 0/1
        "is_review INTEGER DEFAULT 0, "      // 0=正式测验 1=错题复习
        "answered_at INTEGER NOT NULL"       // unix 秒
        ");";
    const char* reviewItemsSql =
        "CREATE TABLE IF NOT EXISTS review_items ("
        "question_id INTEGER PRIMARY KEY, "  // 错题（quiz_attempts 中答错过的题）
        "text_id INTEGER NOT NULL, "
        "correct_streak INTEGER DEFAULT 0, " // 连续答对次数（调度翻倍用）
        "wrong_count INTEGER DEFAULT 0, "
        "next_review_at INTEGER NOT NULL"    // 下次到期时间
        ");";
    const char* quizAttemptsIdxSql =
        "CREATE INDEX IF NOT EXISTS idx_quiz_attempts_text ON quiz_attempts(text_id, question_id);";

    if (!db->executeSQL(quizAttemptsSql) || !db->executeSQL(reviewItemsSql) ||
        !db->executeSQL(quizAttemptsIdxSql)) {
        LOG_ERROR("UserRepository::initTable quiz tables failed: {}", db->getLastError());
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

bool UserRepository::getUser(User& user) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    const char* sql = "SELECT d1_ability, d2_ability, d3_ability, d4_ability, "
                      "d5_ability, d6_ability, d7_ability, d8_ability, d9_ability, d10_ability, "
                      "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
                      "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
                      "d9_base_ability, d10_base_ability, eta, "
                      "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
                      "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
                      "last_read_time "
                      "FROM user WHERE id = 1;";
    char* errMsg = nullptr;

    struct GetUserData { User* user; bool found = false; } gd = {&user, false};
    
    int rc = sqlite3_exec(db->getConnection(), sql, getUserCallback, &gd, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询用户失败: {}", errMsg);
        sqlite3_free(errMsg);
        return false;
    }
    
    return gd.found;
}

bool UserRepository::saveUser(const User& user) {
    auto buildUserParams = [&user]() -> std::vector<SqlParam> {
        std::vector<SqlParam> p;
        for (int i = 0; i < 10; ++i) {
            p.emplace_back(user.getAbility(i));
        }
        for (int i = 0; i < 10; ++i) {
            p.emplace_back(user.getBaseAbility(i));
        }
        p.emplace_back(user.getEta());
        for (int i = 0; i < 10; ++i) {
            p.emplace_back(user.getQuizCount(i));
        }
        p.emplace_back(static_cast<double>(user.getLastReadTime()));
        return p;
    };

    auto userParams = buildUserParams();
    std::vector<SqlParam> params;
    params.insert(params.end(), userParams.begin(), userParams.end());
    params.insert(params.end(), userParams.begin(), userParams.end());
    
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
        "VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
        "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "d1_ability = ?, d2_ability = ?, d3_ability = ?, d4_ability = ?, "
        "d5_ability = ?, d6_ability = ?, d7_ability = ?, d8_ability = ?, "
        "d9_ability = ?, d10_ability = ?, "
        "d1_base_ability = ?, d2_base_ability = ?, d3_base_ability = ?, d4_base_ability = ?, "
        "d5_base_ability = ?, d6_base_ability = ?, d7_base_ability = ?, d8_base_ability = ?, "
        "d9_base_ability = ?, d10_base_ability = ?, eta = ?, "
        "d1_quiz_count = ?, d2_quiz_count = ?, d3_quiz_count = ?, d4_quiz_count = ?, "
        "d5_quiz_count = ?, d6_quiz_count = ?, d7_quiz_count = ?, d8_quiz_count = ?, "
        "d9_quiz_count = ?, d10_quiz_count = ?, "
        "last_read_time = ?;",
        params
    );
}

