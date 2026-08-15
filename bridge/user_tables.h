#ifndef USER_TABLES_H
#define USER_TABLES_H

#include <string>
#include <unordered_map>
#include <vector>

// db_replace 需要跨替换保留的用户数据表及其列白名单（未来 schema 漂移：未知列忽略、缺列取默认）。
// 铁律：新增用户表必须同步补白名单 + 自增序列对齐（漏掉会静默清空用户数据）；
// 完整性由 tests/test_db_replace.cpp 的"白名单 == 资产库用户表集合"断言兜底。
inline const std::unordered_map<std::string, std::vector<std::string>> kUserTableColumns = {
    // 档案元数据（多用户）：新表，db_replace 整表合并
    {"profiles", {"id", "name", "created_at", "last_used_at", "deleted"}},
    {"user", {"id",
              "d1_ability", "d2_ability", "d3_ability", "d4_ability", "d5_ability",
              "d6_ability", "d7_ability", "d8_ability", "d9_ability", "d10_ability",
              "d1_base_ability", "d2_base_ability", "d3_base_ability", "d4_base_ability",
              "d5_base_ability", "d6_base_ability", "d7_base_ability", "d8_base_ability",
              "d9_base_ability", "d10_base_ability", "eta",
              "d1_quiz_count", "d2_quiz_count", "d3_quiz_count", "d4_quiz_count",
              "d5_quiz_count", "d6_quiz_count", "d7_quiz_count", "d8_quiz_count",
              "d9_quiz_count", "d10_quiz_count", "last_read_time"}},
    {"reading_history", {"id", "user_id", "text_id", "read_time", "read_timestamp"}},
    {"text_tracking", {"user_id", "text_id", "tracked_at"}},
    {"learning_increments", {"id", "user_id", "dimension", "delta", "timestamp", "type"}},
    // 测验闭环（quiz_attempts 作答流水 / review_items 错题复习队列）：
    // 缺表则跳过导出（源库表不存在时兼容旧库），导入侧由 openDatabase 的 initTable 幂等建表
    {"quiz_attempts", {"id", "user_id", "question_id", "text_id", "correct", "is_review", "answered_at"}},
    {"review_items", {"user_id", "question_id", "text_id", "correct_streak", "wrong_count", "next_review_at"}},
};

#endif  // USER_TABLES_H
