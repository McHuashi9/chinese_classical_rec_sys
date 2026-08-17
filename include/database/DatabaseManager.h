#ifndef DATABASE_MANAGER_H
#define DATABASE_MANAGER_H

#include <sqlite3.h>
#include <string>
#include <vector>
#include <variant>

/**
 * @brief SQL 参数类型（支持文本、实数、32 位整数、64 位整数——时间戳用 int64_t 绑定，避免 double 精度回环）
 */
using SqlParam = std::variant<std::string, double, int, int64_t>;

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
     * @brief 执行带参数的 SELECT 查询（使用预处理语句，防止 SQL 注入）
     * @param sql SQL 语句，使用 ? 作为占位符
     * @param textParams 文本参数（按顺序绑定）
     * @param realParams REAL 参数（接在文本参数之后绑定）
     * @param callback SQLite 回调函数
     * @param callbackData 回调函数用户数据指针
     * @return true 成功，false 失败
     */
    bool executeQuery(const std::string& sql,
                      const std::vector<std::string>& textParams,
                      const std::vector<double>& realParams,
                      int (*callback)(void*, int, char**, char**),
                      void* callbackData);
    
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
    
    /**
     * @brief 绑定预处理语句参数
     * @param stmt 预处理语句指针
     * @param textParams 文本参数（按顺序绑定）
     * @param realParams REAL 参数（接在文本参数之后绑定）
     * @return true 成功，false 失败
     */
    bool bindParameters(sqlite3_stmt* stmt,
                        const std::vector<std::string>& textParams,
                        const std::vector<double>& realParams);

    /**
     * @brief 绑定预处理语句参数（混合类型）
     * @param stmt 预处理语句指针
     * @param params 参数列表（按顺序绑定）
     * @return true 成功，false 失败
     */
    bool bindMixedParameters(sqlite3_stmt* stmt, const std::vector<SqlParam>& params);
};

#endif