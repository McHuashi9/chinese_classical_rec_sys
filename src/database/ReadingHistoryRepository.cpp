#include "database/ReadingHistoryRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>

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
        "text_id INTEGER PRIMARY KEY, "
        "tracked_at INTEGER NOT NULL"
        ");";

    if (!db->executeSQL(sql2)) {
        LOG_ERROR("ReadingHistoryRepository::initTable text_tracking failed: {}", db->getLastError());
        return false;
    }

    return true;
}

bool ReadingHistoryRepository::addRecord(int textId, double readTime, time_t timestamp) {
    return db->executeSQL(
        "INSERT INTO reading_history (user_id, text_id, read_time, read_timestamp) "
        "VALUES (1, ?, ?, ?);",
        std::vector<double>{static_cast<double>(textId), readTime, static_cast<double>(timestamp)}
    );
}

std::vector<ReadingRecord> ReadingHistoryRepository::getRecentRecords(int limit) {
    std::vector<ReadingRecord> records;
    
    if (!db || !db->getConnection()) {
        return records;
    }
    
    const char* sql = "SELECT id, text_id, read_time, read_timestamp "
                      "FROM reading_history "
                      "WHERE user_id = 1 "
                      "ORDER BY read_timestamp DESC LIMIT ?;";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询阅读历史失败: {}", db->getLastError());
        return records;
    }
    
    sqlite3_bind_int(stmt, 1, limit);
    
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

int ReadingHistoryRepository::getTotalReadCount() {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM reading_history WHERE user_id = 1;";
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        return 0;
    }
    
    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    }
    
    sqlite3_finalize(stmt);
    return count;
}

bool ReadingHistoryRepository::markAsTracked(int textId) {
    time_t now = time(nullptr);
    return db->executeSQL(
        "INSERT OR IGNORE INTO text_tracking (text_id, tracked_at) VALUES (?, ?);",
        std::vector<double>{static_cast<double>(textId), static_cast<double>(now)}
    );
}

std::vector<int> ReadingHistoryRepository::getTrackedTextIds() {
    std::vector<int> ids;
    if (!db || !db->getConnection()) {
        return ids;
    }

    const char* sql = "SELECT text_id FROM text_tracking;";
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);

    if (rc != SQLITE_OK) {
        LOG_ERROR("查询已追踪文本失败: {}", db->getLastError());
        return ids;
    }

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        ids.push_back(sqlite3_column_int(stmt, 0));
    }

    sqlite3_finalize(stmt);
    return ids;
}
