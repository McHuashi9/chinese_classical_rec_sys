#ifndef DATABASE_STATEMENT_H
#define DATABASE_STATEMENT_H

#include <sqlite3.h>

#include <cstdint>
#include <string>
#include <variant>
#include <vector>

/**
 * @brief SQL 参数类型（支持文本、实数、32 位整数、64 位整数——时间戳用 int64_t 绑定，避免 double 精度回环）
 *
 * v1.4.0 工作项 1 起随 Row/Statement 一起定义在本头文件；DatabaseManager.h 传递性导出该别名，
 * 既有调用方（含 bridge）无需改 include，绑定实现统一在 Statement::bind（原
 * DatabaseManager::bindMixedParameters）。
 */
using SqlParam = std::variant<std::string, double, int, int64_t>;

/**
 * @brief 一行查询结果：具名列访问 + 类型化取值（内部 C++，不进 FFI）
 *
 * **形态已定稿（v1.4.0 工作项 1）**：后续工作项 4 的 `fillQuestionRow(const Row&, QuestionData&)`
 * 直接以 Row 为参数，不再出现「先用 sqlite3_stmt* 抽取、之后再改签名」的中间态。
 *
 * 约定（新增使用方按此为准）：
 * - 列名取自 SQL 的列名/别名。表达式列（如 `json_extract(options,'$[0]')`）请在 SQL 里显式
 *   `AS opt0` 命名，否则只能按整型下标访问（整型下标恒定可用）。
 * - 越界下标或未知列名：hasColumn()==false、columnIndex()==-1、isNull()==true，
 *   取值返回空串/0/0.0 —— 不抛异常、不中断。
 * - NULL 列：isNull()==true，取值同上返回默认值；调用方需要区分「NULL」与「空串」时先查 isNull()。
 * - 数值取值沿用 sqlite3_column_int64 / sqlite3_column_double 的强制转换语义（REAL 截断、
 *   TEXT 尝试解析数字前缀）；text() 对数值列返回十进制字符串（整型精确，REAL 用最短往返表示）。
 *   BLOB 不建模，按空串处理。
 * - 行数据自有（拷贝成本与列数成正比），可安全存入容器或跨函数传递。
 */
class Row {
public:
    /** 列数 */
    int columnCount() const { return static_cast<int>(names_.size()); }

    /** 第 col 列的列名；越界返回空串 */
    std::string columnName(int col) const;

    /** 具名列下标；未知列名返回 -1 */
    int columnIndex(const std::string& name) const;

    /** 是否存在该具名列 */
    bool hasColumn(const std::string& name) const { return columnIndex(name) >= 0; }

    /** 第 col 列是否为 NULL（越界视为 NULL） */
    bool isNull(int col) const;

    /** 具名列是否为 NULL（未知列名视为 NULL） */
    bool isNull(const std::string& name) const { return isNull(columnIndex(name)); }

    /**
     * TEXT 取值（NULL/越界返回空串）
     *
     * 数值列返回**该值在 SQLite 中的文本形式**（SQLite 对 REAL 给出最短往返表示），
     * 与列实际存储格式一致；TEXT 列直接返回原串。
     */
    std::string text(int col) const;
    std::string text(const std::string& name) const { return text(columnIndex(name)); }

    /** INTEGER 取值（NULL/越界返回 0） */
    int64_t integer(int col) const;
    int64_t integer(const std::string& name) const { return integer(columnIndex(name)); }

    /** REAL 取值（NULL/越界返回 0.0） */
    double real(int col) const;
    double real(const std::string& name) const { return real(columnIndex(name)); }

private:
    friend class Statement;

    std::vector<std::string> names_;
    std::vector<SqlParam> values_;  // 与 names_ 等长；SQLITE_INTEGER 统一存 int64_t，NULL 存占位
    std::vector<bool> nulls_;
    // 与 names_ 等长的 SQLite 文本形式缓存（仅数值列非空；TEXT 列已在 values_ 中）。
    // 用途：text() 返回与 SQLite 一致的字符串。不用 std::to_chars 是刻意的——
    // libc++ 在 iOS < 16.3 上不提供浮点版 to_chars（CI 的 ios-build 曾因此编译失败）。
    std::vector<std::string> sqliteText_;
};

/**
 * @brief RAII 预处理语句：生命周期即 sqlite3_stmt 句柄的生命周期
 *
 * - 禁拷贝、可移动（移动后旧对象 ok()==false）；`sqlite3_finalize` 只在本类内调用一次
 *   （Statement::finalize），析构必经，提前 return / 异常展开都不会漏 finalize。
 * - 预处理或绑定失败不抛异常：ok()==false，错误文本经 error() 读取；构造时若传入 errOut，
 *   同一错误文本会同步写入该字符串（消费方沿用 `bool + lastError` 契约）。
 * - step() 原样返回 sqlite3_step 结果（SQLITE_ROW / SQLITE_DONE / 错误码），调用方自行判断
 *   「空结果（DONE）vs 出错」；reset() 保留参数绑定，可重新 step。
 */
class Statement {
public:
    /**
     * @param db 已打开的连接（为空则直接失败）
     * @param sql 单条 SQL（多条语句只执行第一条，与 sqlite3_prepare_v2 语义一致）
     * @param errOut 可选错误输出，失败时写入与 error() 相同的内容
     */
    Statement(sqlite3* db, const std::string& sql, std::string* errOut = nullptr);
    ~Statement();

    Statement(Statement&& other) noexcept;
    Statement& operator=(Statement&& other) noexcept;
    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    /** 预处理是否成功 */
    bool ok() const { return stmt_ != nullptr; }

    /** 最近一次预处理/绑定/step/reset 的错误文本（成功时为空串） */
    const std::string& error() const { return err_; }

    /** sqlite3_step；句柄不可用时返回 SQLITE_MISUSE */
    int step();

    /** sqlite3_reset（保留绑定）；失败返回 false */
    bool reset();

    /** 按顺序绑定第 1..N 个占位符；类型由 SqlParam 决定 */
    bool bind(const std::vector<SqlParam>& params);

    int columnCount() const;

    /** 第 col 列列名；越界/不可用返回空串 */
    std::string columnName(int col) const;

    /** 读取当前行到 out（覆盖 out 原内容）；须在 step()==SQLITE_ROW 后调用 */
    void readRow(Row& out) const;

private:
    /** 唯一的 sqlite3_finalize 调用点 */
    void finalize() noexcept;

    void setError(const char* fallback);

    sqlite3* db_ = nullptr;
    sqlite3_stmt* stmt_ = nullptr;
    std::string err_;
    std::string* errOut_ = nullptr;
};

#endif
