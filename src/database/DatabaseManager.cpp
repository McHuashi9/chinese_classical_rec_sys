#include "database/DatabaseManager.h"
#include "utils/Logger.h"
#include <nowide/convert.hpp>
#include <iostream>
#include <utility>

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
    // Windows 平台需要支持中文路径，但必须保持 SQLite 文本编码为 UTF-8：
    // sqlite3_open16() 新建的数据库默认编码是 UTF-16，ATTACH UTF-8 的 classical.db 会报
    // "attached databases must use the same text encoding as main database"。
    // 因此这里先转宽字符再转回 UTF-8，交给 sqlite3_open()（Windows 上文件名按 UTF-8 解释）。
    const std::wstring wpath = nowide::widen(dbPath);
    const std::string utf8Path = nowide::narrow(wpath);
    rc = sqlite3_open(utf8Path.c_str(), &db);
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

bool DatabaseManager::isReadable() {
    if (!db) return false;
    // 空库没有 sqlite_master 行，step 返回 SQLITE_DONE，仍属于可读 SQLite。
    Statement stmt(db, "SELECT name FROM sqlite_master LIMIT 1;", &lastError);
    if (!stmt.ok()) return false;
    const int stepRc = stmt.step();
    if (stepRc != SQLITE_ROW && stepRc != SQLITE_DONE) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

bool DatabaseManager::attachDatabase(const std::string& alias, const std::string& dbPath) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    const std::string sql = "ATTACH DATABASE ? AS " + alias + ";";
    Statement stmt(db, sql, &lastError);
    if (!stmt.ok()) return false;
    if (!stmt.bind({dbPath})) return false;
    if (stmt.step() != SQLITE_DONE) {
        lastError = sqlite3_errmsg(db);
        return false;
    }
    return true;
}

bool DatabaseManager::detachDatabase(const std::string& alias) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }
    const std::string sql = "DETACH DATABASE " + alias + ";";
    return executeSQL(sql);
}

int DatabaseManager::getUserVersion() const {
    if (!db) return 0;
    Statement stmt(db, "PRAGMA user_version;");
    if (!stmt.ok()) return 0;
    int version = 0;
    if (stmt.step() == SQLITE_ROW) {
        Row row;
        stmt.readRow(row);
        version = static_cast<int>(row.integer(0));
    }
    return version;
}

bool DatabaseManager::setUserVersion(int version) {
    return executeSQL("PRAGMA user_version = " + std::to_string(version) + ";");
}

bool DatabaseManager::executeSQL(const std::string& sql) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }

    // 批次 4（明示排除）：errMsg 在失败且未分配时为 nullptr，直接赋给 std::string 是 UB；
    // 属裸 sqlite3_exec 路径的独立条目（recon-db-access.md §5.1），本次工作项 1 不动。
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
    std::vector<SqlParam> mixed;
    mixed.reserve(params.size());
    for (const auto& param : params) {
        mixed.emplace_back(param);
    }
    return executeSQL(sql, mixed);
}

bool DatabaseManager::executeSQL(const std::string& sql, const std::vector<double>& params) {
    std::vector<SqlParam> mixed;
    mixed.reserve(params.size());
    for (double param : params) {
        mixed.emplace_back(param);
    }
    return executeSQL(sql, mixed);
}

bool DatabaseManager::executeSQL(const std::string& sql,
                                  const std::vector<std::string>& textParams,
                                  const std::vector<double>& realParams) {
    std::vector<SqlParam> mixed;
    mixed.reserve(textParams.size() + realParams.size());
    for (const auto& param : textParams) {
        mixed.emplace_back(param);
    }
    for (double param : realParams) {
        mixed.emplace_back(param);
    }
    return executeSQL(sql, mixed);
}

bool DatabaseManager::executeSQL(const std::string& sql, const std::vector<SqlParam>& params) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }

    Statement stmt(db, sql, &lastError);
    if (!stmt.ok()) return false;
    if (!stmt.bind(params)) return false;

    const int rc = stmt.step();
    if (rc != SQLITE_DONE) {
        lastError = stmt.error().empty() ? sqlite3_errmsg(db) : stmt.error();
        return false;
    }

    return true;
}

bool DatabaseManager::queryRows(const std::string& sql, std::vector<Row>& out) {
    return queryRows(sql, std::vector<SqlParam>{}, out);
}

bool DatabaseManager::queryRows(const std::string& sql, const std::vector<SqlParam>& params,
                                std::vector<Row>& out) {
    out.clear();
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }

    Statement stmt(db, sql, &lastError);
    if (!stmt.ok()) return false;
    if (!stmt.bind(params)) return false;

    int rc = SQLITE_DONE;
    while ((rc = stmt.step()) == SQLITE_ROW) {
        Row row;
        stmt.readRow(row);
        out.push_back(std::move(row));
    }

    if (rc != SQLITE_DONE) {
        out.clear();  // 失败不向调用方暴露半截结果集
        lastError = stmt.error().empty() ? sqlite3_errmsg(db) : stmt.error();
        return false;
    }

    return true;
}

bool DatabaseManager::backupTo(const std::string& destPath) {
    if (!db) {
        lastError = "数据库未打开";
        return false;
    }

    sqlite3* dest = nullptr;
    if (sqlite3_open(destPath.c_str(), &dest) != SQLITE_OK) {
        lastError = dest ? sqlite3_errmsg(dest) : "无法打开备份目标";
        if (dest) sqlite3_close(dest);
        return false;
    }

    sqlite3_backup* backup = sqlite3_backup_init(dest, "main", db, "main");
    if (!backup) {
        lastError = sqlite3_errmsg(dest);
        sqlite3_close(dest);
        return false;
    }

    const int stepRc = sqlite3_backup_step(backup, -1);
    if (stepRc == SQLITE_DONE) {
        lastError.clear();
    } else {
        lastError = sqlite3_errmsg(dest);
    }
    sqlite3_backup_finish(backup);
    sqlite3_close(dest);
    return stepRc == SQLITE_DONE;
}

std::string DatabaseManager::getLastError() const {
    return lastError;
}

sqlite3* DatabaseManager::getConnection() const {
    return db;
}
