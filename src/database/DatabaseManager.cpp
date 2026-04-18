#include "database/DatabaseManager.h"
#include "utils/Logger.h"
#include <nowide/convert.hpp>
#include <iostream>

#ifdef _WIN32
#include <windows.h>
#endif

DatabaseManager::DatabaseManager() : db(nullptr) {}

DatabaseManager::~DatabaseManager() {
    close();
}

bool DatabaseManager::open(const std::string& dbPath) {
    int rc;
#ifdef _WIN32
    // Windows 平台使用宽字符 API 以支持中文路径
    std::wstring wpath = nowide::widen(dbPath);
    rc = sqlite3_open16(wpath.c_str(), &db);
#else
    rc = sqlite3_open(dbPath.c_str(), &db);
#endif
    if (rc != SQLITE_OK) {
        lastError = sqlite3_errmsg(db);
        LOG_ERROR("无法打开数据库: {}", lastError);
        return false;
    }
    return true;
}

void DatabaseManager::close() {
    if (db) {
        sqlite3_close(db);
        db = nullptr;
    }
}

bool DatabaseManager::executeSQL(const std::string& sql) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    
    char* errMsg = nullptr;
    int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &errMsg);
    
    if (rc != SQLITE_OK) {
        lastError = errMsg;
        sqlite3_free(errMsg);
        return false;
    }
    
    return true;
}

bool DatabaseManager::executeSQL(const std::string& sql, const std::vector<std::string>& params) {
    std::vector<double> emptyReal;
    return executeSQL(sql, params, emptyReal);
}

bool DatabaseManager::executeSQL(const std::string& sql, const std::vector<double>& params) {
    std::vector<std::string> emptyText;
    return executeSQL(sql, emptyText, params);
}

bool DatabaseManager::executeQuery(const std::string& sql,
                                    const std::vector<std::string>& textParams,
                                    const std::vector<double>& realParams,
                                    int (*callback)(void*, int, char**, char**),
                                    void* callbackData) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    // 绑定参数
    if (!bindParameters(stmt, textParams, realParams)) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    // 执行查询并处理结果
    int colCount = sqlite3_column_count(stmt);
    std::vector<std::string> values(colCount);
    std::vector<char*> valuePtrs(colCount);
    std::vector<std::string> colNames(colCount);
    std::vector<char*> colNamePtrs(colCount);
    
    // 列名只需获取一次
    for (int i = 0; i < colCount; ++i) {
        const char* name = sqlite3_column_name(stmt, i);
        colNames[i] = name ? name : "";
        colNamePtrs[i] = const_cast<char*>(colNames[i].c_str());
    }
    
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        for (int i = 0; i < colCount; ++i) {
            const unsigned char* text = sqlite3_column_text(stmt, i);
            values[i] = text ? reinterpret_cast<const char*>(text) : "";
            valuePtrs[i] = const_cast<char*>(values[i].c_str());
        }
        
        if (callbackData && callback) {
            callback(callbackData, colCount, valuePtrs.data(), colNamePtrs.data());
        }
    }
    
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    return true;
}

bool DatabaseManager::executeSQL(const std::string& sql,
                                  const std::vector<std::string>& textParams,
                                  const std::vector<double>& realParams) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    // 绑定参数
    if (!bindParameters(stmt, textParams, realParams)) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    // 执行语句
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    return true;
}

bool DatabaseManager::bindParameters(sqlite3_stmt* stmt,
                                     const std::vector<std::string>& textParams,
                                     const std::vector<double>& realParams) {
    int rc = SQLITE_OK;
    
    // 绑定文本参数
    for (size_t i = 0; i < textParams.size(); ++i) {
        rc = sqlite3_bind_text(stmt, static_cast<int>(i + 1),
                               textParams[i].c_str(), -1, SQLITE_TRANSIENT);
        if (rc != SQLITE_OK) {
            lastError = sqlite3_errmsg(db);
            return false;
        }
    }
    
    // 绑定REAL参数
    for (size_t i = 0; i < realParams.size(); ++i) {
        int paramIndex = static_cast<int>(textParams.size() + i + 1);
        rc = sqlite3_bind_double(stmt, paramIndex, realParams[i]);
        if (rc != SQLITE_OK) {
            lastError = sqlite3_errmsg(db);
            return false;
        }
    }
    
    return true;
}

bool DatabaseManager::bindMixedParameters(sqlite3_stmt* stmt,
                                          const std::vector<SqlParam>& params) {
    int rc = SQLITE_OK;
    
    for (size_t i = 0; i < params.size(); ++i) {
        int paramIndex = static_cast<int>(i + 1);
        
        std::visit([this, &rc, stmt, paramIndex](auto&& arg) {
            using T = std::decay_t<decltype(arg)>;
            if constexpr (std::is_same_v<T, std::string>) {
                rc = sqlite3_bind_text(stmt, paramIndex, arg.c_str(), -1, SQLITE_TRANSIENT);
            } else if constexpr (std::is_same_v<T, double>) {
                rc = sqlite3_bind_double(stmt, paramIndex, arg);
            } else if constexpr (std::is_same_v<T, int>) {
                rc = sqlite3_bind_int(stmt, paramIndex, arg);
            }
        }, params[i]);
        
        if (rc != SQLITE_OK) {
            lastError = sqlite3_errmsg(db);
            return false;
        }
    }
    
    return true;
}

bool DatabaseManager::executeSQL(const std::string& sql, const std::vector<SqlParam>& params) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    
    sqlite3_stmt* stmt = nullptr;
    int rc = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr);
    
    if (rc != SQLITE_OK) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    // 绑定参数
    if (!bindMixedParameters(stmt, params)) {
        sqlite3_finalize(stmt);
        return false;
    }
    
    // 执行语句
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    
    if (rc != SQLITE_DONE) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    
    return true;
}

std::string DatabaseManager::getLastError() const {
    return lastError;
}

sqlite3* DatabaseManager::getConnection() const {
    return db;
}