#ifndef DATABASE_MANAGER_H
#define DATABASE_MANAGER_H

#include "database/Statement.h"

#include <sqlite3.h>
#include <string>
#include <vector>

// SqlParam（绑定参数类型）自 v1.4.0 工作项 1 起定义在 Statement.h，此处传递性导出。

/**
 * @brief 简单的 SQLite 数据库管理器
 * 
 * 功能：
 * 1. 打开/关闭数据库连接
 * 2. 执行 SQL 语句
 */
class DatabaseManager {
public:
    DatabaseManager();
    ~DatabaseManager();
    
    /**
     * @brief 打开数据库文件
     * @param dbPath 数据库文件路径
     * @return true 成功，false 失败
     */
    bool open(const std::string& dbPath);
    
    /**
     * @brief 关闭数据库连接
     */
    void close();

    /**
     * @brief 检查已打开的主库是否为可读 SQLite 数据库
     *
     * 空文件（0 字节）会被 SQLite 当作空库，属于可读；非 SQLite/损坏文件
     * 在访问 sqlite_master 时会返回 SQLITE_NOTADB，视为不可读。
     */
    bool isReadable();

    /**
     * @brief 挂载附属数据库（ATTACH）
     * @param alias 附属库别名（调用方传入受控标识，如 "content"）
     * @param dbPath 附属库文件路径（绑定参数传递，避免转义问题）
     * @return true 成功，false 失败
     */
    bool attachDatabase(const std::string& alias, const std::string& dbPath);

    /**
     * @brief 卸载附属数据库（DETACH）
     * @param alias 附属库别名（调用方传入受控标识）
     * @return true 成功，false 失败
     */
    bool detachDatabase(const std::string& alias);

    /**
     * @brief 读取主库 PRAGMA user_version
     */
    int getUserVersion() const;

    /**
     * @brief 写入主库 PRAGMA user_version
     */
    bool setUserVersion(int version);

    /**
     * @brief 执行不返回结果的 SQL 语句（如 CREATE, INSERT, UPDATE）
     * @param sql SQL 语句
     * @return true 成功，false 失败
     */
    bool executeSQL(const std::string& sql);

    /**
     * @brief 执行带参数的 SQL 语句（使用预处理语句，防止 SQL 注入）
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param params 参数列表（按顺序绑定）
     * @return true 成功，false 失败
     */
    bool executeSQL(const std::string& sql, const std::vector<std::string>& params);

    /**
     * @brief 执行带参数的 SQL 语句（REAL 类型参数）
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param params 参数列表（按顺序绑定，REAL 类型）
     * @return true 成功，false 失败
     */
    bool executeSQL(const std::string& sql, const std::vector<double>& params);

    /**
     * @brief 执行带参数的 SQL 语句（混合类型参数）
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param textParams 文本参数（按顺序绑定）
     * @param realParams REAL 参数（接在文本参数之后绑定）
     * @return true 成功，false 失败
     */
    bool executeSQL(const std::string& sql,
                    const std::vector<std::string>& textParams,
                    const std::vector<double>& realParams);

    /**
     * @brief 执行带参数的 SQL 语句（混合类型参数，按顺序绑定）
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param params 参数列表，按 SQL 中出现顺序绑定
     * @return true 成功，false 失败
     */
    bool executeSQL(const std::string& sql, const std::vector<SqlParam>& params);

    /**
     * @brief 执行无参数 SELECT 查询，按行收集到 out
     * @param sql SQL 语句
     * @param out 输出行集合（进入时清空；失败时保持为空）
     * @return true 查询完成（含空结果集），false 失败（lastError 已置）
     */
    bool queryRows(const std::string& sql, std::vector<Row>& out);

    /**
     * @brief 执行带参数 SELECT 查询，按行收集到 out
     *
     * 契约：返回值区分「空结果」与「出错」——成功且无行时返回 true 且 out 为空；
     * 出错返回 false，out 被清空，lastError 可用（消费方 `LOG_ERROR(getLastError())`）。
     *
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param params 参数列表，按 SQL 中出现顺序绑定
     * @param out 输出行集合（进入时清空；失败时保持为空）
     */
    bool queryRows(const std::string& sql, const std::vector<SqlParam>& params,
                   std::vector<Row>& out);

    /**
     * @brief 整库快照备份（sqlite3_backup）：把当前主库完整复制到 destPath
     *
     * v1.4.0 工作项 2：自 bridge 的 user_export 下沉（原 bridge.cpp:410-442 的
     * sqlite3_open/sqlite3_backup_init/step/finish/close 编排），使桥层不再直接持有原始连接。
     * 失败返回 false，lastError 可用于 `LOG_ERROR(getLastError())`。
     *
     * @param destPath 目标文件路径（已存在时按 SQLite 语义覆盖）
     * @return true 成功
     */
    bool backupTo(const std::string& destPath);

    /**
     * @brief 获取最后一次错误信息
     */
    std::string getLastError() const;
    
    /**
     * @brief 获取数据库连接指针（用于需要回调的查询）
     */
    sqlite3* getConnection() const;
    
private:
    sqlite3* db;
    std::string lastError;
};

#endif