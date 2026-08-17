#ifndef USER_TABLES_H
#define USER_TABLES_H

#include <string>
#include <vector>

// 拆双库后，用户表只存在于 user.db；classical.db 必须是纯内容库。
// 该清单退役为“内容库禁止出现的旧用户表名黑名单”，用于 db_open / db_replace
// 的内容库纯净校验。新增用户表时必须同步补在这里（否则混装内容库可能绕过校验）。
inline const std::vector<std::string> kUserTableNames = {
    "profiles",
    "user",
    "reading_history",
    "text_tracking",
    "learning_increments",
    "quiz_attempts",
    "review_items",
};

#endif  // USER_TABLES_H
