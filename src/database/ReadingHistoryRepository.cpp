#include "database/ReadingHistoryRepository.h"
#include "database/schema_introspect.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <set>
#include <string>

using dbschema::tableColumns;
using dbschema::tableExists;
using dbschema::tableSql;

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

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId, limit}, rows)) {
        LOG_ERROR("查询阅读历史失败: {}", db->getLastError());
        return records;
    }

    records.reserve(rows.size());
    for (const Row& row : rows) {
        ReadingRecord record;
        record.id = static_cast<int>(row.integer("id"));
        record.textId = static_cast<int>(row.integer("text_id"));
        record.readTime = row.real("read_time");
        record.timestamp = static_cast<time_t>(row.integer("read_timestamp"));
        records.push_back(record);
    }

    return records;
}

int ReadingHistoryRepository::getTotalReadCount(int userId) {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM reading_history WHERE user_id = ?;";

    // 出错与空结果都返回 0（与旧实现一致：prepare 失败/无行均静默 0）
    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId}, rows) || rows.empty()) {
        return 0;
    }

    return static_cast<int>(rows[0].integer(0));
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

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId}, rows)) {
        LOG_ERROR("查询已追踪文本失败: {}", db->getLastError());
        return ids;
    }

    ids.reserve(rows.size());
    for (const Row& row : rows) {
        ids.push_back(static_cast<int>(row.integer("text_id")));
    }

    return ids;
}
