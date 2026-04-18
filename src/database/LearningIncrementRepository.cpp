#include "database/LearningIncrementRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>

LearningIncrementRepository::LearningIncrementRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool LearningIncrementRepository::initTable() {
    const char* sql = 
        "CREATE TABLE IF NOT EXISTS learning_increments ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "user_id INTEGER NOT NULL DEFAULT 1, "
        "dimension INTEGER NOT NULL, "      // 维度索引 1-10
        "delta REAL NOT NULL, "             // 增量值 Δu_j^(k)
        "timestamp INTEGER NOT NULL, "      // 学习时刻 t_k
        "type TEXT DEFAULT 'read'"          // 增量类型
        ");";
    
    bool result = db->executeSQL(sql);
    if (!result) {
        LOG_ERROR("LearningIncrementRepository::initTable failed: {}", db->getLastError());
        return false;
    }
    
    // 创建索引加速查询
    const char* indexSql = 
        "CREATE INDEX IF NOT EXISTS idx_learning_increments_user_dim "
        "ON learning_increments(user_id, dimension);";
    db->executeSQL(indexSql);
    
    return true;
}

bool LearningIncrementRepository::addIncrement(int userId, int dimension, double delta,
                                               time_t timestamp, const std::string& type) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    const char* sql = "INSERT INTO learning_increments (user_id, dimension, delta, timestamp, type) "
                      "VALUES (?, ?, ?, ?, ?);";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("准备插入增量语句失败: {}", sqlite3_errmsg(db->getConnection()));
        return false;
    }
    
    sqlite3_bind_int(stmt, 1, userId);
    sqlite3_bind_int(stmt, 2, dimension);
    sqlite3_bind_double(stmt, 3, delta);
    sqlite3_bind_int64(stmt, 4, static_cast<sqlite3_int64>(timestamp));
    sqlite3_bind_text(stmt, 5, type.c_str(), -1, SQLITE_TRANSIENT);
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        LOG_ERROR("插入增量失败: {}", sqlite3_errmsg(db->getConnection()));
        return false;
    }
    
    LOG_DEBUG("记录增量: 维度={}, delta={:.6f}, type={}", dimension, delta, type);
    return true;
}

std::vector<LearningIncrement> LearningIncrementRepository::getIncrements(int userId, int dimension) {
    std::vector<LearningIncrement> increments;
    
    if (!db || !db->getConnection()) {
        return increments;
    }
    
    const char* sql = "SELECT id, user_id, dimension, delta, timestamp, type "
                      "FROM learning_increments WHERE user_id = ? AND dimension = ? "
                      "ORDER BY timestamp ASC;";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("准备查询增量语句失败: {}", sqlite3_errmsg(db->getConnection()));
        return increments;
    }
    
    sqlite3_bind_int(stmt, 1, userId);
    sqlite3_bind_int(stmt, 2, dimension);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        LearningIncrement inc;
        inc.id = sqlite3_column_int(stmt, 0);
        inc.userId = sqlite3_column_int(stmt, 1);
        inc.dimension = sqlite3_column_int(stmt, 2);
        inc.delta = sqlite3_column_double(stmt, 3);
        inc.timestamp = static_cast<time_t>(sqlite3_column_int64(stmt, 4));
        const char* typeStr = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5));
        inc.type = typeStr ? typeStr : "read";
        increments.push_back(inc);
    }
    
    sqlite3_finalize(stmt);
    return increments;
}

std::vector<LearningIncrement> LearningIncrementRepository::getAllIncrements(int userId) {
    std::vector<LearningIncrement> increments;
    
    if (!db || !db->getConnection()) {
        return increments;
    }
    
    const char* sql = "SELECT id, user_id, dimension, delta, timestamp, type "
                      "FROM learning_increments WHERE user_id = ? "
                      "ORDER BY dimension, timestamp ASC;";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("准备查询所有增量语句失败: {}", sqlite3_errmsg(db->getConnection()));
        return increments;
    }
    
    sqlite3_bind_int(stmt, 1, userId);
    
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        LearningIncrement inc;
        inc.id = sqlite3_column_int(stmt, 0);
        inc.userId = sqlite3_column_int(stmt, 1);
        inc.dimension = sqlite3_column_int(stmt, 2);
        inc.delta = sqlite3_column_double(stmt, 3);
        inc.timestamp = static_cast<time_t>(sqlite3_column_int64(stmt, 4));
        const char* typeStr = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 5));
        inc.type = typeStr ? typeStr : "read";
        increments.push_back(inc);
    }
    
    sqlite3_finalize(stmt);
    return increments;
}

bool LearningIncrementRepository::deleteIncrement(int id) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    const char* sql = "DELETE FROM learning_increments WHERE id = ?;";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql, -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        return false;
    }
    
    sqlite3_bind_int(stmt, 1, id);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    return rc == SQLITE_DONE;
}

bool LearningIncrementRepository::deleteIncrements(const std::vector<int>& ids) {
    if (ids.empty()) {
        return true;
    }
    
    if (!db || !db->getConnection()) {
        return false;
    }
    
    // 构建批量删除 SQL: DELETE FROM learning_increments WHERE id IN (?, ?, ...);
    std::string sql = "DELETE FROM learning_increments WHERE id IN (";
    for (size_t i = 0; i < ids.size(); ++i) {
        sql += (i > 0) ? ", ?" : "?";
    }
    sql += ");";
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db->getConnection(), sql.c_str(), -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("准备批量删除增量语句失败: {}", sqlite3_errmsg(db->getConnection()));
        return false;
    }
    
    // 绑定所有参数
    for (size_t i = 0; i < ids.size(); ++i) {
        sqlite3_bind_int(stmt, static_cast<int>(i + 1), ids[i]);
    }
    
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        LOG_ERROR("批量删除增量失败: {}", sqlite3_errmsg(db->getConnection()));
        return false;
    }
    
    LOG_DEBUG("批量删除 {} 条增量", ids.size());
    return true;
}

int LearningIncrementRepository::getIncrementCount(int userId) {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM learning_increments WHERE user_id = ?;";
    
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
