#include "database/ReadingHistoryRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>

ReadingHistoryRepository::ReadingHistoryRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool ReadingHistoryRepository::initTable() {
    const char* sql = 
        "CREATE TABLE IF NOT EXISTS reading_history ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "user_id INTEGER NOT NULL DEFAULT 1, "
        "text_id INTEGER NOT NULL, "
        "read_time REAL NOT NULL, "
        "read_timestamp INTEGER NOT NULL"
        ");";
    
    bool result = db->executeSQL(sql);
    if (!result) {
        LOG_ERROR("ReadingHistoryRepository::initTable failed: {}", db->getLastError());
    }
    return result;
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
    
    std::string sql = "SELECT id, text_id, read_time, read_timestamp "
                      "FROM reading_history "
                      "WHERE user_id = 1 "
                      "ORDER BY read_timestamp DESC LIMIT " + std::to_string(limit) + ";";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql.c_str(), -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询阅读历史失败: {}", db->getLastError());
        return records;
    }
    
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
