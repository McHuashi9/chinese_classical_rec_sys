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

    Statement stmt(db->getConnection(), sql);
    if (!stmt.ok()) {
        LOG_ERROR("准备插入增量语句失败: {}", stmt.error());
        return false;
    }
    if (!stmt.bind({userId, dimension, delta, static_cast<int64_t>(timestamp), type})) {
        LOG_ERROR("绑定插入增量参数失败: {}", stmt.error());
        return false;
    }
    if (stmt.step() != SQLITE_DONE) {
        LOG_ERROR("插入增量失败: {}", stmt.error());
        return false;
    }
    
    LOG_DEBUG("记录增量: 维度={}, delta={:.6f}, type={}", dimension, delta, type);
    return true;
}

std::vector<LearningIncrement> LearningIncrementRepository::getAllIncrements(int userId) {
    std::vector<LearningIncrement> increments;
    
    if (!db || !db->getConnection()) {
        return increments;
    }
    
    const char* sql = "SELECT id, user_id, dimension, delta, timestamp, type "
                      "FROM learning_increments WHERE user_id = ? "
                      "ORDER BY dimension, timestamp ASC;";

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId}, rows)) {
        LOG_ERROR("准备查询所有增量语句失败: {}", db->getLastError());
        return increments;
    }

    increments.reserve(rows.size());
    for (const Row& row : rows) {
        LearningIncrement inc;
        inc.id = static_cast<int>(row.integer("id"));
        inc.userId = static_cast<int>(row.integer("user_id"));
        inc.dimension = static_cast<int>(row.integer("dimension"));
        inc.delta = row.real("delta");
        inc.timestamp = static_cast<time_t>(row.integer("timestamp"));
        // NULL 才回退 'read'（旧实现是 text 指针为空时回退，空串仍是空串）
        inc.type = row.isNull("type") ? std::string("read") : row.text("type");
        increments.push_back(inc);
    }

    return increments;
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

    std::vector<SqlParam> params;
    params.reserve(ids.size());
    for (const int id : ids) {
        params.emplace_back(id);
    }

    Statement stmt(db->getConnection(), sql);
    if (!stmt.ok()) {
        LOG_ERROR("准备批量删除增量语句失败: {}", stmt.error());
        return false;
    }
    if (!stmt.bind(params)) {
        LOG_ERROR("绑定批量删除增量参数失败: {}", stmt.error());
        return false;
    }
    if (stmt.step() != SQLITE_DONE) {
        LOG_ERROR("批量删除增量失败: {}", stmt.error());
        return false;
    }
    
    LOG_DEBUG("批量删除 {} 条增量", ids.size());
    return true;
}

bool LearningIncrementRepository::deleteByDimensions(int userId, const std::vector<int>& dimensions) {
    if (dimensions.empty()) {
        return true;
    }
    if (!db || !db->getConnection()) {
        return false;
    }

    // 与 bridge.cpp 原内联实现同形：user_id = ? AND dimension IN (?, ?, ...)
    std::string sql = "DELETE FROM learning_increments WHERE user_id = ? AND dimension IN (";
    for (size_t i = 0; i < dimensions.size(); ++i) {
        sql += (i > 0) ? ", ?" : "?";
    }
    sql += ");";

    std::vector<SqlParam> params;
    params.reserve(dimensions.size() + 1);
    params.emplace_back(userId);
    for (const int dimension : dimensions) {
        params.emplace_back(dimension);
    }

    return db->executeSQL(sql, params);
}

int LearningIncrementRepository::getIncrementCount(int userId) {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM learning_increments WHERE user_id = ?;";

    // 出错与空结果都返回 0（与旧实现一致：prepare 失败/无行均静默 0）
    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId}, rows) || rows.empty()) {
        return 0;
    }

    return static_cast<int>(rows[0].integer(0));
}
