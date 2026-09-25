#include "database/Statement.h"

#include <charconv>
#include <cstdlib>
#include <type_traits>
#include <utility>

namespace {

// TEXT 列的数值强制转换沿用 sqlite3_column_int64 / column_double 语义：
// 非数字前缀返回 0，数字前缀按 strtoll/strtod 解析。
int64_t coerceInteger(const SqlParam& value)
{
    if (const auto* i64 = std::get_if<int64_t>(&value)) return *i64;
    if (const auto* i = std::get_if<int>(&value)) return static_cast<int64_t>(*i);
    if (const auto* d = std::get_if<double>(&value)) return static_cast<int64_t>(*d);
    if (const auto* s = std::get_if<std::string>(&value)) return std::strtoll(s->c_str(), nullptr, 10);
    return 0;
}

double coerceReal(const SqlParam& value)
{
    if (const auto* d = std::get_if<double>(&value)) return *d;
    if (const auto* i64 = std::get_if<int64_t>(&value)) return static_cast<double>(*i64);
    if (const auto* i = std::get_if<int>(&value)) return static_cast<double>(*i);
    if (const auto* s = std::get_if<std::string>(&value)) return std::strtod(s->c_str(), nullptr);
    return 0.0;
}

}  // namespace

std::string Row::columnName(int col) const
{
    if (col < 0 || col >= columnCount()) return {};
    return names_[static_cast<size_t>(col)];
}

int Row::columnIndex(const std::string& name) const
{
    for (size_t i = 0; i < names_.size(); ++i) {
        if (names_[i] == name) return static_cast<int>(i);
    }
    return -1;
}

bool Row::isNull(int col) const
{
    if (col < 0 || col >= columnCount()) return true;
    return nulls_[static_cast<size_t>(col)];
}

std::string Row::text(int col) const
{
    if (col < 0 || col >= columnCount()) return {};
    if (nulls_[static_cast<size_t>(col)]) return {};

    const SqlParam& value = values_[static_cast<size_t>(col)];
    if (const auto* s = std::get_if<std::string>(&value)) return *s;
    if (const auto* i64 = std::get_if<int64_t>(&value)) return std::to_string(*i64);
    if (const auto* i = std::get_if<int>(&value)) return std::to_string(*i);
    if (const auto* d = std::get_if<double>(&value)) {
        char buf[40];
        const auto res = std::to_chars(buf, buf + sizeof(buf), *d);
        if (res.ec == std::errc()) return std::string(buf, res.ptr);
        return std::to_string(*d);
    }
    return {};
}

int64_t Row::integer(int col) const
{
    if (col < 0 || col >= columnCount()) return 0;
    if (nulls_[static_cast<size_t>(col)]) return 0;
    return coerceInteger(values_[static_cast<size_t>(col)]);
}

double Row::real(int col) const
{
    if (col < 0 || col >= columnCount()) return 0.0;
    if (nulls_[static_cast<size_t>(col)]) return 0.0;
    return coerceReal(values_[static_cast<size_t>(col)]);
}

Statement::Statement(sqlite3* db, const std::string& sql, std::string* errOut)
    : db_(db), errOut_(errOut)
{
    if (!db_) {
        err_ = "数据库未打开";
        if (errOut_) *errOut_ = err_;
        return;
    }
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt_, nullptr) != SQLITE_OK) {
        stmt_ = nullptr;
        setError("预处理语句失败");
    }
}

Statement::~Statement()
{
    finalize();
}

Statement::Statement(Statement&& other) noexcept
    : db_(other.db_),
      stmt_(other.stmt_),
      err_(std::move(other.err_)),
      errOut_(other.errOut_)
{
    other.db_ = nullptr;
    other.stmt_ = nullptr;
    other.errOut_ = nullptr;
}

Statement& Statement::operator=(Statement&& other) noexcept
{
    if (this != &other) {
        finalize();  // 先释放自己持有的句柄，避免覆盖即泄漏
        db_ = other.db_;
        stmt_ = other.stmt_;
        err_ = std::move(other.err_);
        errOut_ = other.errOut_;
        other.db_ = nullptr;
        other.stmt_ = nullptr;
        other.errOut_ = nullptr;
    }
    return *this;
}

void Statement::finalize() noexcept
{
    if (stmt_) {
        sqlite3_finalize(stmt_);  // 全仓唯一调用点（批 1 范围内）
        stmt_ = nullptr;
    }
}

void Statement::setError(const char* fallback)
{
    const char* msg = db_ ? sqlite3_errmsg(db_) : nullptr;
    err_ = msg ? msg : (fallback ? fallback : "未知错误");
    if (errOut_) *errOut_ = err_;
}

int Statement::step()
{
    if (!stmt_) return SQLITE_MISUSE;
    const int rc = sqlite3_step(stmt_);
    if (rc != SQLITE_ROW && rc != SQLITE_DONE) {
        setError("执行语句失败");
    }
    return rc;
}

bool Statement::reset()
{
    if (!stmt_) return false;
    if (sqlite3_reset(stmt_) != SQLITE_OK) {
        setError("重置语句失败");
        return false;
    }
    return true;
}

bool Statement::bind(const std::vector<SqlParam>& params)
{
    if (!stmt_) return false;

    for (size_t i = 0; i < params.size(); ++i) {
        const int index = static_cast<int>(i + 1);
        int rc = SQLITE_OK;

        std::visit([&rc, this, index](auto&& arg) {
            using T = std::decay_t<decltype(arg)>;
            if constexpr (std::is_same_v<T, std::string>) {
                rc = sqlite3_bind_text(stmt_, index, arg.c_str(), -1, SQLITE_TRANSIENT);
            } else if constexpr (std::is_same_v<T, double>) {
                rc = sqlite3_bind_double(stmt_, index, arg);
            } else if constexpr (std::is_same_v<T, int>) {
                rc = sqlite3_bind_int(stmt_, index, arg);
            } else if constexpr (std::is_same_v<T, int64_t>) {
                rc = sqlite3_bind_int64(stmt_, index, arg);
            }
        }, params[i]);

        if (rc != SQLITE_OK) {
            setError("参数绑定失败");
            return false;
        }
    }
    return true;
}

int Statement::columnCount() const
{
    return stmt_ ? sqlite3_column_count(stmt_) : 0;
}

std::string Statement::columnName(int col) const
{
    if (!stmt_ || col < 0) return {};
    const char* name = sqlite3_column_name(stmt_, col);
    return name ? name : "";
}

void Statement::readRow(Row& out) const
{
    out.names_.clear();
    out.values_.clear();
    out.nulls_.clear();
    if (!stmt_) return;

    const int count = sqlite3_column_count(stmt_);
    out.names_.reserve(static_cast<size_t>(count));
    out.values_.reserve(static_cast<size_t>(count));
    out.nulls_.reserve(static_cast<size_t>(count));

    for (int i = 0; i < count; ++i) {
        const char* name = sqlite3_column_name(stmt_, i);
        out.names_.emplace_back(name ? name : "");

        const int type = sqlite3_column_type(stmt_, i);
        out.nulls_.push_back(type == SQLITE_NULL);

        switch (type) {
            case SQLITE_INTEGER:
                out.values_.emplace_back(static_cast<int64_t>(sqlite3_column_int64(stmt_, i)));
                break;
            case SQLITE_FLOAT:
                out.values_.emplace_back(sqlite3_column_double(stmt_, i));
                break;
            case SQLITE_TEXT: {
                const unsigned char* text = sqlite3_column_text(stmt_, i);
                out.values_.emplace_back(text ? std::string(reinterpret_cast<const char*>(text))
                                              : std::string());
                break;
            }
            default:  // SQLITE_NULL / SQLITE_BLOB（BLOB 不建模，按空串占位）
                out.values_.emplace_back(std::string());
                break;
        }
    }
}
