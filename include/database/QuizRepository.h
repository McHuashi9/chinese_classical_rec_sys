#ifndef QUIZ_REPOSITORY_H
#define QUIZ_REPOSITORY_H

#include "database/DatabaseManager.h"

#include <cstdint>
#include <string>
#include <vector>

/**
 * @brief 6 个强制初始化题目的 q_key 清单（v1.4.0 工作项 3 收敛为单一来源）
 *
 * 【对拍点】`scripts/project/check_content_db.py` 的 `INIT_Q_KEYS`（该文件 :44-51）必须与本清单
 * **逐字同序**一致；`tests/test_review_scheduler.cpp` 的「q_key 单源对拍」用例会在构建期路径下
 * 解析该 Python 文件并逐项比对（构建期路径由 tests/CMakeLists.txt 的
 * `CHECK_CONTENT_DB_PATH` 传入）。改动任一处必须同步另一处。
 *
 * 本函数取代了原 `bridge/bridge.cpp` 中重复的两份：`:241` 的 static `kInitQKeys[]`（内容库校验）
 * 与 `:596` 的 `initQKeyList()`（强制初始化），见 recon-bridge.md §3.3 跨域耦合表。
 */
const std::vector<std::string>& initQKeys();

/**
 * @brief questions 表查询状态：区分「表缺失（优雅降级）」与「真实错误」
 */
enum class QuizStatus { Ok, MissingTable, Error };

/**
 * @brief 取题池查询结果（question_get_by_text 通道）
 */
struct QuizQuestionPool {
    QuizStatus status = QuizStatus::Error;
    int total = 0;          ///< 该篇总题数（answered_all 判定基准）
    std::vector<Row> rows;  ///< 未答题行（固定种子洗牌 + 截断 maxCount 后）
};

/**
 * @brief 单题完整信息（tracker_apply_quiz / user_init_apply 通道）
 *
 * `nullFields` 记录哪些被选列是 NULL：原桥层两处调用点对 NULL 的处置不同
 * （判题视为「题目字段缺失」→ BRIDGE_ERR_TEXT；强制初始化沿用 column_int/column_text 的
 * 0/空串语义），因此这里保留原始信息由桥层各自判定。
 */
enum QuizQuestionField : unsigned {
    QuizFieldNone = 0u,
    QuizFieldQKey = 1u << 0,
    QuizFieldTextId = 1u << 1,
    QuizFieldAnswerIndex = 1u << 2,
    QuizFieldDims = 1u << 3,
};

struct QuizQuestionInfo {
    QuizStatus status = QuizStatus::Error;
    bool found = false;              ///< false = 该 id 无行（题目不存在）
    unsigned nullFields = QuizFieldNone;
    std::string qKey;
    int textId = 0;
    int answerIndex = 0;
    std::string dims;                ///< CSV，如 "3,4,9"（0-based 维度）
};

/**
 * @brief 按 id 取题结果（quiz_get_questions_by_ids 通道）
 */
struct QuizQuestions {
    QuizStatus status = QuizStatus::Error;
    std::vector<Row> rows;
    std::string missingKey;  ///< getInitQuestions 专用：缺失的初始化 q_key
};

/**
 * @brief questions 表相关读取（v1.4.0 工作项 2：自 bridge.cpp 下沉）
 *
 * 桥层只负责「取参 → 调库 → 回填 → 返回码」；本类承载取题池过滤/洗牌、按 id 取题、
 * 初始化取题、作答流水写入与文章作答摘要。
 */
class QuizRepository {
public:
    explicit QuizRepository(DatabaseManager* dbManager);

    /**
     * @brief 取未答题池：COUNT 总数 → 排除已答（含复习记录）→ 固定种子洗牌 → 截断 maxCount
     *
     * 契约（与原 question_get_by_text 一致）：
     * - 表缺失 → status = MissingTable（桥层按「无题」优雅降级，返回 0）
     * - total == 0 → status = Ok 且 rows 为空（该篇无题）
     * - total > 0 且 rows 为空 → 全答完（answered_all = 1）
     */
    QuizQuestionPool getUnansweredByText(int userId, int textId, int maxCount);

    /**
     * @brief 按 id 取题（复习通道）：按输入顺序返回，缺失 id 跳过；扫描上限 min(count, maxCount)
     *
     * 不受「排除已答」影响（复习题本身是已答题）。status = Error 仅表示查询不可用。
     */
    QuizQuestions getByIds(const int* ids, int count, int maxCount);

    /**
     * @brief 取强制初始化题：按 initQKeys() 顺序返回前 maxCount 题
     *
     * 任一需要的 q_key 缺失 → status = Error 且 missingKey 记录该键（桥层映射为
     * BRIDGE_ERR_DB_CONTENT，与原逐键 prepare 的行为一致）。
     */
    QuizQuestions getInitQuestions(int maxCount);

    /** @brief 单题信息（q_key/text_id/answer_index/dims） */
    QuizQuestionInfo getQuestionInfo(int questionId);

    /** @brief 写作答流水（isInit=1 用于强制初始化题；is_review/is_init 显式写入） */
    bool insertAttempt(int userId, int questionId, int textId, int correct, int isReview,
                       int isInit, int64_t answeredAt);

    /** @brief 文章作答摘要：总题数 + 去重已答数（错题数归 ReviewRepository） */
    struct AttemptSummary {
        int total = 0;
        int answered = 0;
    };
    AttemptSummary attemptSummary(int userId, int textId);

private:
    /** questions 表是否存在（手动替换的旧库/损坏资产 → 优雅降级判据） */
    bool questionsTableExists() const;

    DatabaseManager* db;
};

#endif
