#include "database/QuizRepository.h"

#include "database/schema_introspect.h"
#include "utils/Logger.h"

#include <algorithm>
#include <random>

using dbschema::tableExists;

namespace {

// questions 表完整列清单（三处 SELECT 的唯一来源）。
// 表达式列必须显式 AS optN，Row 才能具名访问（见 include/database/Statement.h 的 Row 约定）；
// 桥层 fillQuestionRow 按 stem/opt0..opt3/dims/... 回填 QuestionData。
#define QUESTION_SELECT_COLUMNS                                                          \
    "id, text_id, q_type, stem, "                                                       \
    "json_extract(options, '$[0]') AS opt0, json_extract(options, '$[1]') AS opt1, "    \
    "json_extract(options, '$[2]') AS opt2, json_extract(options, '$[3]') AS opt3, "    \
    "dims, explanation, difficulty, context, mark_start, mark_len"

// 取题随机轮换的固定种子（Catch2 可复现；轮换由"排除已答"驱动，种子只保证批次内顺序确定）
constexpr uint32_t kQuizShuffleSeed = 42;

}  // namespace

// 单一来源：与 scripts/project/check_content_db.py 的 INIT_Q_KEYS 对拍（见头文件注释）。
const std::vector<std::string>& initQKeys()
{
    static const std::vector<std::string> keys = {
        "d648b695e1579dbe", "28a1103b477177ee", "6dcbeb434a04bb29",
        "5f465c9792081778", "f6e064465d0da521", "638f4ed6d813d2f8",
    };
    return keys;
}

QuizRepository::QuizRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool QuizRepository::questionsTableExists() const
{
    return db && db->getConnection() && tableExists(db->getConnection(), "questions");
}

QuizQuestionPool QuizRepository::getUnansweredByText(int userId, int textId, int maxCount)
{
    QuizQuestionPool result;
    if (!db || !db->getConnection()) {
        result.status = QuizStatus::Error;
        return result;
    }

    // 1. 该篇总题数（answered_all 判定基准）
    std::vector<Row> rows;
    if (!db->queryRows("SELECT COUNT(*) AS cnt FROM questions WHERE text_id = ?",
                       std::vector<SqlParam>{textId}, rows)) {
        if (!questionsTableExists()) {
            result.status = QuizStatus::MissingTable;
            return result;
        }
        LOG_ERROR("bridge: question_get_by_text count 查询失败: {}", db->getLastError());
        result.status = QuizStatus::Error;
        return result;
    }
    result.total = rows.empty() ? 0 : static_cast<int>(rows[0].integer("cnt"));
    if (result.total == 0) {
        result.status = QuizStatus::Ok;
        return result;
    }

    // 2. 取未答题（排除已答含复习记录——答过就不重复考，复习队列是错题唯一回收通道）
    const std::string sql = std::string("SELECT ") + QUESTION_SELECT_COLUMNS +
                            " FROM questions WHERE text_id = ?1 AND id NOT IN "
                            "(SELECT question_id FROM quiz_attempts WHERE text_id = ?2 AND user_id = ?3) "
                            "ORDER BY seq, id";
    if (!db->queryRows(sql, std::vector<SqlParam>{textId, textId, userId}, result.rows)) {
        LOG_ERROR("bridge: question_get_by_text 取题查询失败: {}", db->getLastError());
        result.status = QuizStatus::Error;
        result.rows.clear();
        return result;
    }

    // 3. 固定种子洗牌（Catch2 可复现）+ 截断到 maxCount；
    //    同一篇连续作答自然轮换：已答题被排除，剩余题随机抽取直到答完
    std::mt19937 rng(kQuizShuffleSeed);
    std::shuffle(result.rows.begin(), result.rows.end(), rng);
    if (maxCount >= 0 && static_cast<int>(result.rows.size()) > maxCount) {
        result.rows.resize(static_cast<size_t>(maxCount));
    }

    result.status = QuizStatus::Ok;
    return result;
}

QuizQuestions QuizRepository::getByIds(const int* ids, int count, int maxCount)
{
    QuizQuestions result;
    if (!db || !db->getConnection() || !ids || count <= 0 || maxCount <= 0) {
        result.status = QuizStatus::Error;
        return result;
    }

    const std::string sql = std::string("SELECT ") + QUESTION_SELECT_COLUMNS +
                            " FROM questions WHERE id = ?";
    // 复用同一预处理语句（原 quiz_get_questions_by_ids 的 sqlite3_reset 复用语义）
    Statement stmt(db->getConnection(), sql);
    if (!stmt.ok()) {
        LOG_ERROR("bridge: quiz_get_questions_by_ids prepare 失败: {}", stmt.error());
        result.status = QuizStatus::Error;
        return result;
    }

    const int n = count < maxCount ? count : maxCount;
    for (int i = 0; i < n; i++) {
        stmt.reset();
        if (!stmt.bind(std::vector<SqlParam>{ids[i]})) continue;
        if (stmt.step() != SQLITE_ROW) continue;  // 缺失 id：跳过
        Row row;
        stmt.readRow(row);
        result.rows.push_back(std::move(row));
    }

    result.status = QuizStatus::Ok;
    return result;
}

QuizQuestions QuizRepository::getInitQuestions(int maxCount)
{
    QuizQuestions result;
    if (!db || !db->getConnection()) {
        result.status = QuizStatus::Error;
        return result;
    }
    if (maxCount <= 0) {
        result.status = QuizStatus::Ok;
        return result;
    }

    const auto& keys = initQKeys();
    // 单条 IN 查询取代原「按 6 个 q_key 逐个 prepare」（recon-db-access.md §3.2 附带项）；
    // q_key 有部分唯一索引，结果按 initQKeys() 顺序重排后再截断。
    std::string sql = std::string("SELECT ") + QUESTION_SELECT_COLUMNS + ", q_key FROM questions WHERE q_key IN (";
    for (size_t i = 0; i < keys.size(); i++) {
        sql += (i == 0) ? "?" : ", ?";
    }
    sql += ")";

    std::vector<SqlParam> params;
    params.reserve(keys.size());
    for (const auto& key : keys) {
        params.emplace_back(key);
    }

    std::vector<Row> rows;
    if (!db->queryRows(sql, params, rows)) {
        LOG_ERROR("bridge: user_init_questions 查询失败: {}", db->getLastError());
        result.status = QuizStatus::Error;
        return result;
    }

    for (const auto& key : keys) {
        if (static_cast<int>(result.rows.size()) >= maxCount) break;
        bool found = false;
        for (const Row& row : rows) {
            if (row.text("q_key") == key) {
                result.rows.push_back(row);
                found = true;
                break;
            }
        }
        if (!found) {
            result.missingKey = key;
            result.status = QuizStatus::Error;
            result.rows.clear();
            return result;
        }
    }

    result.status = QuizStatus::Ok;
    return result;
}

QuizQuestionInfo QuizRepository::getQuestionInfo(int questionId)
{
    QuizQuestionInfo info;
    if (!db || !db->getConnection()) {
        info.status = QuizStatus::Error;
        return info;
    }

    std::vector<Row> rows;
    if (!db->queryRows("SELECT q_key, text_id, answer_index, dims FROM questions WHERE id = ?",
                       std::vector<SqlParam>{questionId}, rows)) {
        if (!questionsTableExists()) {
            info.status = QuizStatus::MissingTable;
            return info;
        }
        LOG_ERROR("bridge: 题目查询失败 question_id={}: {}", questionId, db->getLastError());
        info.status = QuizStatus::Error;
        return info;
    }
    if (rows.empty()) {
        info.status = QuizStatus::Ok;
        info.found = false;
        return info;
    }

    const Row& row = rows[0];
    info.found = true;
    if (row.isNull("q_key")) info.nullFields |= QuizFieldQKey;
    if (row.isNull("text_id")) info.nullFields |= QuizFieldTextId;
    if (row.isNull("answer_index")) info.nullFields |= QuizFieldAnswerIndex;
    if (row.isNull("dims")) info.nullFields |= QuizFieldDims;
    info.qKey = row.text("q_key");
    info.textId = static_cast<int>(row.integer("text_id"));
    info.answerIndex = static_cast<int>(row.integer("answer_index"));
    info.dims = row.text("dims");
    info.status = QuizStatus::Ok;
    return info;
}

bool QuizRepository::insertAttempt(int userId, int questionId, int textId, int correct, int isReview,
                                   int isInit, int64_t answeredAt)
{
    if (!db || !db->getConnection()) return false;
    return db->executeSQL(
        "INSERT INTO quiz_attempts(user_id, question_id, text_id, correct, is_review, is_init, answered_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?);",
        std::vector<SqlParam>{userId, questionId, textId, correct, isReview, isInit, answeredAt});
}

QuizRepository::AttemptSummary QuizRepository::attemptSummary(int userId, int textId)
{
    AttemptSummary summary;
    if (!db || !db->getConnection()) return summary;

    // 与原 quiz_get_attempt_summary 一致：单条查询失败静默保留 0（"表缺失=优雅降级"协议）
    std::vector<Row> rows;
    if (db->queryRows("SELECT COUNT(*) AS cnt FROM questions WHERE text_id = ?",
                      std::vector<SqlParam>{textId}, rows) &&
        !rows.empty()) {
        summary.total = static_cast<int>(rows[0].integer("cnt"));
    }
    if (db->queryRows("SELECT COUNT(DISTINCT question_id) AS cnt FROM quiz_attempts "
                      "WHERE text_id = ? AND user_id = ?",
                      std::vector<SqlParam>{textId, userId}, rows) &&
        !rows.empty()) {
        summary.answered = static_cast<int>(rows[0].integer("cnt"));
    }
    return summary;
}
