#include "database/ReadingHistoryRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <set>
#include <string>

namespace {

bool tableExists(sqlite3* db, const std::string& table)
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

std::string tableSql(sqlite3* db, const std::string& table)
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

std::set<std::string> tableColumns(sqlite3* db, const std::string& table)
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

}  // namespace

ReadingHistoryRepository::ReadingHistoryRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool ReadingHistoryRepository::initTable() {
    const char* sql1 = 
        "CREATE TABLE IF NOT EXISTS reading_history ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "user_id INTEGER NOT NULL DEFAULT 1, "
        "text_id INTEGER NOT NULL, "
        "read_time REAL NOT NULL, "
        "read_timestamp INTEGER NOT NULL"
        ");";
    
    if (!db->executeSQL(sql1)) {
        LOG_ERROR("ReadingHistoryRepository::initTable reading_history failed: {}", db->getLastError());
        return false;
    }

    const char* sql2 = 
        "CREATE TABLE IF NOT EXISTS text_tracking ("
        "user_id INTEGER NOT NULL DEFAULT 1, "
        "text_id INTEGER NOT NULL, "
        "tracked_at INTEGER NOT NULL, "
        "PRIMARY KEY (user_id, text_id)"
        ");";

    // 老库迁移：text_tracking 单列主键 text_id → 复合主键 (user_id, text_id)
    sqlite3* c = db->getConnection();
    if (tableExists(c, "text_tracking")) {
        const std::string oldSql = tableSql(c, "text_tracking");
        const bool hasUserId = tableColumns(c, "text_tracking").count("user_id") != 0;
        if (!hasUserId || oldSql.find("text_id INTEGER PRIMARY KEY") != std::string::npos) {
            LOG_INFO("ReadingHistoryRepository: 检测到 text_tracking 旧主键，迁移为 (user_id, text_id)");
            if (!db->executeSQL("ALTER TABLE text_tracking RENAME TO text_tracking_old;")) {
                LOG_ERROR("ReadingHistoryRepository::initTable text_tracking 重命名失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL(sql2)) {
                LOG_ERROR("ReadingHistoryRepository::initTable 新 text_tracking 创建失败: {}", db->getLastError());
                return false;
            }
            // 老表无 user_id 时取 1（老数据归入默认档案）；有则原样保留
            const char* copySql = hasUserId
                ? "INSERT INTO text_tracking (user_id, text_id, tracked_at) "
                  "SELECT user_id, text_id, tracked_at FROM text_tracking_old;"
                : "INSERT INTO text_tracking (user_id, text_id, tracked_at) "
                  "SELECT 1, text_id, tracked_at FROM text_tracking_old;";
            if (!db->executeSQL(copySql)) {
                LOG_ERROR("ReadingHistoryRepository::initTable text_tracking 数据迁移失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL("DROP TABLE text_tracking_old;")) {
                LOG_ERROR("ReadingHistoryRepository::initTable 删除 text_tracking_old 失败: {}", db->getLastError());
                return false;
            }
        }
    } else {
        if (!db->executeSQL(sql2)) {
            LOG_ERROR("ReadingHistoryRepository::initTable text_tracking failed: {}", db->getLastError());
            return false;
        }
    }

    return true;
}

bool ReadingHistoryRepository::addRecord(int userId, int textId, double readTime, time_t timestamp) {
    if (!db || !db->getConnection()) return false;
    // textId/timestamp 按整数绑定（int64_t），避免 double 泛型绑定的精度回环（N6）
    return db->executeSQL(
        "INSERT INTO reading_history (user_id, text_id, read_time, read_timestamp) "
        "VALUES (?, ?, ?, ?);",
        std::vector<SqlParam>{userId, textId, readTime, static_cast<int64_t>(timestamp)}
    );
}

std::vector<ReadingRecord> ReadingHistoryRepository::getRecentRecords(int userId, int limit) {
    std::vector<ReadingRecord> records;
    
    if (!db || !db->getConnection()) {
        return records;
    }
    
    const char* sql = "SELECT id, text_id, read_time, read_timestamp "
                      "FROM reading_history "
                      "WHERE user_id = ? "
                      "ORDER BY read_timestamp DESC LIMIT ?;";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询阅读历史失败: {}", db->getLastError());
        return records;
    }
    
    sqlite3_bind_int(stmt, 1, userId);
    sqlite3_bind_int(stmt, 2, limit);
    
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        ReadingRecord record;
        record.id = sqlite3_column_int(stmt, 0);
        record.textId = sqlite3_column_int(stmt, 1);
        record.readTime = sqlite3_column_double(stmt, 2);
        record.timestamp = static_cast<time_t>(sqlite3_column_int64(stmt, 3));
        records.push_back(record);
    }
    
    sqlite3_finalize(stmt);
    return records;
}

int ReadingHistoryRepository::getTotalReadCount(int userId) {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM reading_history WHERE user_id = ?;";
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        return 0;
    }
    
    sqlite3_bind_int(stmt, 1, userId);

    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    }
    
    sqlite3_finalize(stmt);
    return count;
}

bool ReadingHistoryRepository::markAsTracked(int userId, int textId) {
    if (!db || !db->getConnection()) return false;
    time_t now = time(nullptr);
    return db->executeSQL(
        "INSERT OR IGNORE INTO text_tracking (user_id, text_id, tracked_at) VALUES (?, ?, ?);",
        std::vector<SqlParam>{userId, textId, static_cast<int64_t>(now)}
    );
}

std::vector<int> ReadingHistoryRepository::getTrackedTextIds(int userId) {
    std::vector<int> ids;
    if (!db || !db->getConnection()) {
        return ids;
    }

    const char* sql = "SELECT text_id FROM text_tracking WHERE user_id = ?;";
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);

    if (rc != SQLITE_OK) {
        LOG_ERROR("查询已追踪文本失败: {}", db->getLastError());
        return ids;
    }

    sqlite3_bind_int(stmt, 1, userId);

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        ids.push_back(sqlite3_column_int(stmt, 0));
    }

    sqlite3_finalize(stmt);
    return ids;
}
