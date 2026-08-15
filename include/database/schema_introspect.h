#ifndef DATABASE_SCHEMA_INTROSPECT_H
#define DATABASE_SCHEMA_INTROSPECT_H

#include <sqlite3.h>

#include <set>
#include <string>
#include <vector>

#include "utils/Logger.h"

// 数据库结构内省工具：表存在性 / 建表语句 / 列名集合 / 共列复制。
// 多用户迁移（UserRepository / ReadingHistoryRepository）与 db_replace
// （bridge.cpp）共用，避免三处各写一份行为漂移；改这里时注意所有调用方。
namespace dbschema {

// 表是否存在（type='table'，排除 view/索引）
inline bool tableExists(sqlite3* db, const std::string& table)
{
    if (!db) return false;
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, table.c_str(), -1, SQLITE_TRANSIENT);
    const bool exists = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);
    return exists;
}

// 表原始建表语句（sqlite_master.sql）；无表/出错返回空串
inline std::string tableSql(sqlite3* db, const std::string& table)
{
    if (!db) return {};
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT sql FROM sqlite_master WHERE type='table' AND name=?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) return {};
    sqlite3_bind_text(stmt, 1, table.c_str(), -1, SQLITE_TRANSIENT);
    std::string out;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char* t = sqlite3_column_text(stmt, 0);
        if (t) out = reinterpret_cast<const char*>(t);
    }
    sqlite3_finalize(stmt);
    return out;
}

// 表列名集合（PRAGMA table_info）；无表/出错返回空集
inline std::set<std::string> tableColumns(sqlite3* db, const std::string& table)
{
    std::set<std::string> cols;
    if (!db) return cols;
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, ("PRAGMA table_info(" + table + ")").c_str(), -1, &stmt, nullptr)
        != SQLITE_OK) {
        return cols;
    }
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char* name = sqlite3_column_text(stmt, 1);
        if (name) cols.insert(reinterpret_cast<const char*>(name));
    }
    sqlite3_finalize(stmt);
    return cols;
}

// 把 from 表中与 to 表共有的列按名复制（to 缺列时取 to 默认值）。
// 仅复制列名集合，与 db_replace 的白名单容错同一思路。
inline bool copyCommonColumns(sqlite3* db, const std::string& from, const std::string& to)
{
    if (!db) return false;
    const std::set<std::string> fromCols = tableColumns(db, from);
    const std::set<std::string> toCols = tableColumns(db, to);
    std::vector<std::string> cols;
    for (const auto& c : fromCols) {
        if (toCols.count(c)) cols.push_back(c);
    }
    if (cols.empty()) return true;

    std::string sql = "INSERT INTO " + to + " (";
    for (size_t i = 0; i < cols.size(); i++) sql += (i ? ", " : "") + cols[i];
    sql += ") SELECT ";
    for (size_t i = 0; i < cols.size(); i++) sql += (i ? ", " : "") + cols[i];
    sql += " FROM " + from + ";";

    char* err = nullptr;
    const int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        LOG_ERROR("dbschema: 列复制失败 {} -> {}: {}", from, to, err ? err : "?");
        sqlite3_free(err);
        return false;
    }
    return true;
}

}  // namespace dbschema

#endif  // DATABASE_SCHEMA_INTROSPECT_H
