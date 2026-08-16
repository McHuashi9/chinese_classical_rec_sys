#ifndef TEST_HELPERS_H
#define TEST_HELPERS_H

#include <sqlite3.h>

#include <filesystem>
#include <string>

// Phase 1 双库测试辅助：每个用例使用独立目录，内容库固定叫 classical.db、
// 用户库固定叫 user.db（与真实 App 布局一致，db_replace 按 sibling user.db 推导）。
namespace test_helpers {

inline std::string workDir(const std::string& tag)
{
    const std::string dir = std::string(TEST_DB_PATH) + "." + tag + ".dir";
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    return dir;
}

// 从当前混装开发资产构造 db_version=1 的纯内容库（删除全部旧用户表）。
inline std::string makeContentDb(const std::string& tag)
{
    const std::string dir = workDir(tag);
    const std::string content = dir + "/classical.db";
    std::error_code ec;
    std::filesystem::remove(content, ec);
    std::filesystem::copy_file(TEST_DB_PATH, content, std::filesystem::copy_options::overwrite_existing);

    sqlite3* db = nullptr;
    if (sqlite3_open(content.c_str(), &db) != SQLITE_OK) return {};
    static const char* kOldUserTables[] = {
        "profiles", "user", "reading_history", "text_tracking",
        "learning_increments", "quiz_attempts", "review_items",
    };
    for (const char* t : kOldUserTables) {
        const std::string sql = "DROP TABLE IF EXISTS " + std::string(t) + ";";
        sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr);
    }
    sqlite3_exec(db, "PRAGMA user_version = 1;", nullptr, nullptr, nullptr);
    sqlite3_close(db);
    return content;
}

inline std::string makeUserDb(const std::string& tag)
{
    const std::string dir = workDir(tag);
    const std::string user = dir + "/user.db";
    std::error_code ec;
    std::filesystem::remove(user, ec);
    return user;
}

}  // namespace test_helpers

#endif  // TEST_HELPERS_H
