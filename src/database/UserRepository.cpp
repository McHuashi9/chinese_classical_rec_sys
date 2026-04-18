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
        "name TEXT NOT NULL, "
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
    
    return true;
}

static int getUserCallback(void* data, int argc, char** argv, char** azColName) {
    User* user = static_cast<User*>(data);
    
    // 字段映射表：列名 -> setter函数
    static const std::unordered_map<std::string, std::function<void(User*, const char*)>> fieldMap = {
        {"name", [](User* u, const char* v) { u->setName(v); }},
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
    
    const char* sql = "SELECT name, d1_ability, d2_ability, d3_ability, d4_ability, "
                      "d5_ability, d6_ability, d7_ability, d8_ability, d9_ability, d10_ability, "
                      "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
                      "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
                      "d9_base_ability, d10_base_ability, last_read_time "
                      "FROM user WHERE id = 1;";
    char* errMsg = nullptr;
    
    int rc = sqlite3_exec(db->getConnection(), sql, getUserCallback, &user, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询用户失败: {}", errMsg);
        sqlite3_free(errMsg);
        return false;
    }
    
    return !user.isEmpty();
}

bool UserRepository::saveUserName(const std::string& userName) {
    return db->executeSQL(
        "INSERT INTO user (id, name) VALUES (1, ?) "
        "ON CONFLICT(id) DO UPDATE SET name = ?;",
        std::vector<std::string>{userName, userName}
    );
}

bool UserRepository::saveUser(const User& user) {
    std::vector<SqlParam> params;
    
    // INSERT 部分的参数
    params.push_back(user.getName());  // name
    for (int i = 0; i < 10; ++i) {
        params.push_back(user.getAbility(i));
    }
    params.push_back(user.getBaseAbility(0));
    params.push_back(user.getBaseAbility(1));
    params.push_back(user.getBaseAbility(2));
    params.push_back(user.getBaseAbility(3));
    params.push_back(user.getBaseAbility(4));
    params.push_back(user.getBaseAbility(5));
    params.push_back(user.getBaseAbility(6));
    params.push_back(user.getBaseAbility(7));
    params.push_back(user.getBaseAbility(8));
    params.push_back(user.getBaseAbility(9));
    params.push_back(static_cast<double>(user.getLastReadTime()));
    
    // UPDATE 部分的参数
    params.push_back(user.getName());  // name
    for (int i = 0; i < 10; ++i) {
        params.push_back(user.getAbility(i));
    }
    params.push_back(user.getBaseAbility(0));
    params.push_back(user.getBaseAbility(1));
    params.push_back(user.getBaseAbility(2));
    params.push_back(user.getBaseAbility(3));
    params.push_back(user.getBaseAbility(4));
    params.push_back(user.getBaseAbility(5));
    params.push_back(user.getBaseAbility(6));
    params.push_back(user.getBaseAbility(7));
    params.push_back(user.getBaseAbility(8));
    params.push_back(user.getBaseAbility(9));
    params.push_back(static_cast<double>(user.getLastReadTime()));
    
    return db->executeSQL(
        "INSERT INTO user (id, name, "
        "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
        "d7_ability, d8_ability, d9_ability, d10_ability, "
        "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
        "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
        "d9_base_ability, d10_base_ability, last_read_time) "
        "VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "name = ?, "
        "d1_ability = ?, d2_ability = ?, d3_ability = ?, d4_ability = ?, "
        "d5_ability = ?, d6_ability = ?, d7_ability = ?, d8_ability = ?, "
        "d9_ability = ?, d10_ability = ?, "
        "d1_base_ability = ?, d2_base_ability = ?, d3_base_ability = ?, d4_base_ability = ?, "
        "d5_base_ability = ?, d6_base_ability = ?, d7_base_ability = ?, d8_base_ability = ?, "
        "d9_base_ability = ?, d10_base_ability = ?, "
        "last_read_time = ?;",
        params
    );
}

time_t UserRepository::getLastReadTime() {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT last_read_time FROM user WHERE id = 1;";
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        return 0;
    }
    
    time_t result = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        result = static_cast<time_t>(sqlite3_column_int64(stmt, 0));
    }
    
    sqlite3_finalize(stmt);
    return result;
}

bool UserRepository::updateLastReadTime(time_t time) {
    return db->executeSQL(
        "UPDATE user SET last_read_time = ? WHERE id = 1;",
        std::vector<double>{static_cast<double>(time)}
    );
}