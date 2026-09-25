#include "database/ReviewRepository.h"

#include "database/schema_introspect.h"
#include "utils/Logger.h"

#include <string>

using dbschema::tableExists;

namespace {

// review_items 过滤子句的单源形状（三处查询共用）：
//   user_id = ? [AND next_review_at <= ?] AND (? = 0 OR text_id = ?) [悬空过滤]
// 参数顺序：user_id → [now] → text_id → text_id → [LIMIT]
const char* kReviewWhereBase = " FROM review_items WHERE user_id = ?";
const char* kReviewWhereDue = " AND next_review_at <= ?";
const char* kReviewWhereText = " AND (? = 0 OR text_id = ?)";

}  // namespace

ReviewRepository::ReviewRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool ReviewRepository::questionsTableExists() const
{
    return db && db->getConnection() && tableExists(db->getConnection(), "questions");
}

std::string ReviewRepository::danglingSuffix() const
{
    if (!danglingFilter_) return std::string();
    if (!questionsTableExists()) return std::string();
    return " AND question_id IN (SELECT id FROM questions)";
}

std::vector<ReviewItem> ReviewRepository::listDue(int userId, int textId, int64_t now, int maxCount)
{
    std::vector<ReviewItem> items;
    if (!db || !db->getConnection() || maxCount <= 0) return items;

    const std::string sql = std::string("SELECT question_id, text_id, correct_streak, wrong_count, "
                                        "next_review_at") +
                            kReviewWhereBase + kReviewWhereDue + kReviewWhereText + danglingSuffix() +
                            " ORDER BY next_review_at ASC LIMIT ?";

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId, now, textId, textId, maxCount}, rows)) {
        LOG_ERROR("bridge: quiz_get_review_items 查询失败: {}", db->getLastError());
        return items;
    }

    items.reserve(rows.size());
    for (const Row& row : rows) {
        ReviewItem item;
        item.questionId = static_cast<int>(row.integer("question_id"));
        item.textId = static_cast<int>(row.integer("text_id"));
        item.correctStreak = static_cast<int>(row.integer("correct_streak"));
        item.wrongCount = static_cast<int>(row.integer("wrong_count"));
        item.nextReviewAt = row.integer("next_review_at");
        items.push_back(item);
    }
    return items;
}

int ReviewRepository::dueCount(int userId, int textId, int64_t now)
{
    if (!db || !db->getConnection()) return 0;

    const std::string sql =
        std::string("SELECT COUNT(*) AS cnt") + kReviewWhereBase + kReviewWhereDue +
        kReviewWhereText + danglingSuffix();

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId, now, textId, textId}, rows) || rows.empty()) {
        LOG_ERROR("bridge: quiz_get_due_review_count 查询失败: {}", db->getLastError());
        return 0;
    }
    return static_cast<int>(rows[0].integer("cnt"));
}

int ReviewRepository::totalCount(int userId, int textId)
{
    if (!db || !db->getConnection()) return 0;

    const std::string sql =
        std::string("SELECT COUNT(*) AS cnt") + kReviewWhereBase + kReviewWhereText + danglingSuffix();

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{userId, textId, textId}, rows) || rows.empty()) {
        LOG_ERROR("bridge: quiz_get_review_count 查询失败: {}", db->getLastError());
        return 0;
    }
    return static_cast<int>(rows[0].integer("cnt"));
}

int ReviewRepository::itemCountForText(int userId, int textId)
{
    if (!db || !db->getConnection()) return 0;

    // 与原 quiz_get_attempt_summary 的 wrong 通道一致：按 text_id + user_id，不加悬空过滤/到期过滤
    std::vector<Row> rows;
    if (!db->queryRows("SELECT COUNT(*) AS cnt FROM review_items WHERE text_id = ? AND user_id = ?",
                       std::vector<SqlParam>{textId, userId}, rows) ||
        rows.empty()) {
        return 0;
    }
    return static_cast<int>(rows[0].integer("cnt"));
}

bool ReviewRepository::upsertWrong(int userId, int questionId, int textId, int64_t nextReviewAt)
{
    if (!db || !db->getConnection()) return false;
    return db->executeSQL(
        "INSERT INTO review_items(user_id, question_id, text_id, correct_streak, wrong_count, next_review_at) "
        "VALUES (?, ?, ?, 0, COALESCE((SELECT wrong_count FROM review_items WHERE user_id = ? AND question_id = ?), 0) + 1, ?) "
        "ON CONFLICT(user_id, question_id) DO UPDATE SET "
        "correct_streak = 0, "
        "wrong_count = review_items.wrong_count + 1, "
        "next_review_at = excluded.next_review_at",
        std::vector<SqlParam>{userId, questionId, textId, userId, questionId, nextReviewAt});
}

bool ReviewRepository::streak(int userId, int questionId, int& streakOut)
{
    streakOut = 0;
    if (!db || !db->getConnection()) return false;

    std::vector<Row> rows;
    if (!db->queryRows("SELECT correct_streak FROM review_items WHERE user_id = ? AND question_id = ?",
                       std::vector<SqlParam>{userId, questionId}, rows)) {
        return false;
    }
    if (!rows.empty()) streakOut = static_cast<int>(rows[0].integer("correct_streak"));
    return true;
}

bool ReviewRepository::removeItem(int userId, int questionId)
{
    if (!db || !db->getConnection()) return false;
    return db->executeSQL("DELETE FROM review_items WHERE user_id = ? AND question_id = ?",
                          std::vector<SqlParam>{userId, questionId});
}

bool ReviewRepository::bumpStreak(int userId, int questionId, int streak, int64_t nextReviewAt)
{
    if (!db || !db->getConnection()) return false;
    return db->executeSQL(
        "UPDATE review_items SET correct_streak = ?, next_review_at = ? "
        "WHERE user_id = ? AND question_id = ?",
        std::vector<SqlParam>{streak, nextReviewAt, userId, questionId});
}
