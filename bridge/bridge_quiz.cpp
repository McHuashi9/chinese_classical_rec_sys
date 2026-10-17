// 桥层题目与复习域（v1.4.0 工作项 3；v1.6.0 增批量提交）：question_get_by_text /
// tracker_apply_quiz / tracker_apply_quiz_batch / quiz_get_review_items /
// quiz_get_due_review_count / quiz_get_review_count / quiz_get_questions_by_ids /
// quiz_get_attempt_summary，共 8 个导出符号。
//
// 工作项 2 下沉：取题池过滤 + 固定种子洗牌 → QuizRepository；review_items 读写（含悬空过滤）
// → ReviewRepository；间隔/掌握/到期边界 → ReviewScheduler。本文件不再直接访问原始连接。

#include "bridge_internal.h"

#include "core/ReviewScheduler.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

// 取题：按 text_id 返回该文题目（排除已答含复习记录 → 固定种子随机轮换，上限 max_count；
// 不下发 answer_index，判题只在 C++ 侧）
// 返回：题数（≥0）；文章不存在返回 BRIDGE_ERR_TEXT；参数非法返回 BRIDGE_ERR_GENERIC
// answered_all（可空）：1 = 该篇已无未答题；0 = 还有未答题或该篇无题
extern "C" CHINESE_CORE_EXPORT int question_get_by_text(int text_id, QuestionData* out,
                                                        int max_count, int* answered_all)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("question_get_by_text");
    if (initRc != BRIDGE_OK) return initRc;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;
    if (S().textIndex->find(text_id) == S().textIndex->end()) {
        LOG_WARN("bridge: question_get_by_text 文章不存在 text_id={}", text_id);
        return BRIDGE_ERR_TEXT;
    }
    if (answered_all) *answered_all = 0;

    const QuizQuestionPool pool =
        S().quizRepo->getUnansweredByText(S().activeUserId, text_id, max_count);
    if (pool.status == QuizStatus::MissingTable) {
        // questions 表缺失（手动替换的旧库/损坏资产）→ 按"无题"优雅降级
        LOG_WARN("bridge: question_get_by_text 无 questions 表，按无题处理 text_id={}", text_id);
        return 0;
    }
    if (pool.status != QuizStatus::Ok) return BRIDGE_ERR_GENERIC;
    if (pool.total == 0) return 0;
    if (pool.rows.empty()) {
        // 有题且全答完
        if (answered_all) *answered_all = 1;
        return 0;
    }

    const int count = static_cast<int>(pool.rows.size());
    for (int i = 0; i < count; i++) {
        fillQuestionRow(pool.rows[static_cast<size_t>(i)], out[i]);
    }
    LOG_INFO("bridge: question_get_by_text text_id={} → {} 题 (上限 {})", text_id, count, max_count);
    return count;
    });
}

namespace {

// 已校验的答题条目。批量入口先全量校验，再在同一事务内逐题应用，
// 确保参数/题目错误不会先写前几题。
struct PreparedQuizAnswer {
    int questionId = 0;
    int textId = 0;
    int answerIndex = 0;
    std::vector<int> dims;
    const Text* text = nullptr;
};

int prepareQuizAnswer(int questionId, int userChoice, const char* caller,
                      PreparedQuizAnswer& item)
{
    const QuizQuestionInfo info = S().quizRepo->getQuestionInfo(questionId);
    if (info.status == QuizStatus::MissingTable) {
        LOG_WARN("bridge: {} 无 questions 表 question_id={}", caller, questionId);
        return BRIDGE_ERR_TEXT;
    }
    if (info.status != QuizStatus::Ok) {
        LOG_ERROR("bridge: {} 题目查询失败: {}", caller, S().db->getLastError());
        return BRIDGE_ERR_GENERIC;
    }
    if (!info.found) {
        LOG_WARN("bridge: {} 题目不存在 question_id={}", caller, questionId);
        return BRIDGE_ERR_TEXT;
    }
    if ((info.nullFields & (QuizFieldTextId | QuizFieldAnswerIndex | QuizFieldDims)) != 0) {
        LOG_WARN("bridge: {} 题目字段缺失 question_id={}", caller, questionId);
        return BRIDGE_ERR_TEXT;
    }
    if (info.answerIndex < 0 || info.answerIndex > 3) {
        LOG_WARN("bridge: {} answer_index 越界 question_id={} idx={}", caller, questionId,
                 info.answerIndex);
        return BRIDGE_ERR_GENERIC;
    }
    if (userChoice < 0 || userChoice > 3) {
        LOG_WARN("bridge: {} user_choice 越界 question_id={} choice={}", caller, questionId,
                 userChoice);
        return BRIDGE_ERR_GENERIC;
    }

    auto it = S().textIndex->find(info.textId);
    if (it == S().textIndex->end()) {
        LOG_WARN("bridge: {} 文章不存在 question_id={} text_id={}", caller, questionId,
                 info.textId);
        return BRIDGE_ERR_TEXT;
    }

    std::vector<int> dims;
    {
        std::stringstream ss(info.dims);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (tok.empty()) continue;
            const int dim = std::atoi(tok.c_str());
            if (dim < 0 || dim >= 10) {
                LOG_WARN("bridge: {} 维度越界 question_id={} dim={}", caller, questionId, dim);
                return BRIDGE_ERR_GENERIC;
            }
            dims.push_back(dim);
        }
    }
    if (dims.empty()) {
        LOG_WARN("bridge: {} dims 为空 question_id={}", caller, questionId);
        return BRIDGE_ERR_GENERIC;
    }

    item.questionId = questionId;
    item.textId = info.textId;
    item.answerIndex = info.answerIndex;
    item.dims = std::move(dims);
    item.text = &(*S().texts)[it->second];
    return BRIDGE_OK;
}

// 在调用方事务与 g_mtx 内应用一题：能力效应（正式测验）→ 作答流水 → 复习状态。
// 仅返回 true 才表示该题的全部写库动作成功；调用方负责提交/回滚事务。
bool applyPreparedQuizAnswer(User& cppUser, const PreparedQuizAnswer& item, int correct,
                             int64_t answeredAt, bool isReview)
{
    if (!isReview) {
        S().tracker->applyQuizEffect(cppUser, *item.text, item.dims, correct,
                                     static_cast<time_t>(answeredAt));
    }

    bool ok = S().quizRepo->insertAttempt(
        S().activeUserId, item.questionId, item.textId, correct, isReview ? 1 : 0, 0,
        answeredAt);
    if (!ok) {
        LOG_ERROR("bridge: quiz_attempts 写入失败 question_id={}: {}", item.questionId,
                  S().db->getLastError());
        return false;
    }

    if (correct == 1) {
        if (!isReview) {
            // 正式测验答对 → 视为已掌握，从复习队列移除
            ok = S().reviewRepo->removeItem(S().activeUserId, item.questionId);
            if (!ok) {
                LOG_ERROR("bridge: review_items 删除失败 question_id={}: {}", item.questionId,
                          S().db->getLastError());
            }
        } else {
            // 复习答对 → streak+1，间隔翻倍；streak≥3 移除（视为掌握）
            int streak = 0;
            ok = S().reviewRepo->streak(S().activeUserId, item.questionId, streak);
            if (ok) {
                if (ReviewScheduler::isMasteredAfterCorrect(streak)) {
                    ok = S().reviewRepo->removeItem(S().activeUserId, item.questionId);
                } else {
                    ok = S().reviewRepo->bumpStreak(
                        S().activeUserId, item.questionId, streak + 1,
                        answeredAt + ReviewScheduler::intervalAfter(streak + 1));
                }
            }
            if (!ok) {
                LOG_ERROR("bridge: review_items 更新失败 question_id={}: {}", item.questionId,
                          S().db->getLastError());
            }
        }
    } else {
        // 答错（正式或复习均重置）：streak 清零、wrong_count+1、下次到期 = answered_at + base
        ok = S().reviewRepo->upsertWrong(
            S().activeUserId, item.questionId, item.textId,
            ReviewScheduler::dueAfterWrong(answeredAt));
        if (!ok) {
            LOG_ERROR("bridge: review_items upsert 失败 question_id={}: {}", item.questionId,
                      S().db->getLastError());
        }
    }
    return ok;
}

}  // namespace

// 单题答题（保留既有 ABI）：按 question_id 查题 → 判题 → 答题效应 + 作答流水 +
// 复习状态在同一事务内完成。失败时不写出参，且不产生半应用状态。
extern "C" CHINESE_CORE_EXPORT int tracker_apply_quiz(const UserData* user, int question_id,
                                      int user_choice, int64_t timestamp,
                                      UserData* out_user, int* out_correct, int is_review)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("tracker_apply_quiz");
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !out_user) return BRIDGE_ERR_GENERIC;

    PreparedQuizAnswer item;
    const int prepRc = prepareQuizAnswer(question_id, user_choice, "tracker_apply_quiz", item);
    if (prepRc != BRIDGE_OK) return prepRc;

    const bool review = is_review != 0;
    const int correct = (user_choice == item.answerIndex) ? 1 : 0;
    const int64_t effectiveTs =
        timestamp == 0 ? static_cast<int64_t>(time(nullptr)) : timestamp;

    User cppUser;
    c_to_user(user, cppUser);

    SqlTransaction tx(S().db.get(), "BEGIN");
    if (!tx.ok()) return BRIDGE_ERR_GENERIC;
    if (!applyPreparedQuizAnswer(cppUser, item, correct, effectiveTs, review)) {
        LOG_ERROR("bridge: tracker_apply_quiz 事务失败 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }
    if (!review && !S().userRepo->saveUser(cppUser, S().activeUserId)) {
        LOG_ERROR("bridge: 答题效应落库失败 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }
    if (!tx.commit()) {
        LOG_ERROR("bridge: tracker_apply_quiz 事务提交失败 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }

    if (out_correct) *out_correct = correct;
    user_to_c(cppUser, out_user);

    if (!review) {
        const double avgBefore = S().user ? S().user->getAverageAbility() : 0.0;
        S().user = std::make_unique<User>(cppUser);
        LOG_INFO("bridge: 答题效应完成 — question_id={}, correct={}, avg_ability={:.3f}→{:.3f}",
                 question_id, correct, avgBefore, cppUser.getAverageAbility());
    } else {
        LOG_INFO("bridge: 复习作答完成 — question_id={}, correct={}（无答题效应）",
                 question_id, correct);
    }
    return BRIDGE_OK;
    });
}

// 批量答题（v1.6.0）：Dart submitQuiz 的唯一 FFI 入口。
// 先校验全部题目/选项，再在一个 BEGIN IMMEDIATE 事务内逐题应用判分、能力效应、
// 作答流水与复习状态；任一题失败整批回滚，出参只在 COMMIT 成功后写入。
// out_ability_before 为可选扁平数组 count*10（每题作答前 10 维能力，行优先）。
extern "C" CHINESE_CORE_EXPORT int tracker_apply_quiz_batch(
    const UserData* user, const int* question_ids, const int* user_choices, int count,
    int64_t timestamp, UserData* out_user, int* out_correct, double* out_ability_before,
    int is_review)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("tracker_apply_quiz_batch");
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !question_ids || !user_choices || !out_user || count <= 0) {
        return BRIDGE_ERR_GENERIC;
    }

    const bool review = is_review != 0;
    const int64_t effectiveTs =
        timestamp == 0 ? static_cast<int64_t>(time(nullptr)) : timestamp;

    std::vector<PreparedQuizAnswer> items(static_cast<size_t>(count));
    for (int i = 0; i < count; i++) {
        const int rc = prepareQuizAnswer(question_ids[i], user_choices[i],
                                         "tracker_apply_quiz_batch", items[i]);
        if (rc != BRIDGE_OK) return rc;
    }

    User cppUser;
    c_to_user(user, cppUser);
    std::vector<int> correct(static_cast<size_t>(count), 0);
    std::vector<double> abilityBefore(static_cast<size_t>(count) * 10, 0.0);

    SqlTransaction tx(S().db.get(), "BEGIN IMMEDIATE");
    if (!tx.ok()) return BRIDGE_ERR_GENERIC;
    bool ok = true;
    for (int i = 0; i < count && ok; i++) {
        for (int dim = 0; dim < 10; dim++) {
            abilityBefore[static_cast<size_t>(i) * 10 + dim] = cppUser.getAbility(dim);
        }
        correct[static_cast<size_t>(i)] =
            (user_choices[i] == items[static_cast<size_t>(i)].answerIndex) ? 1 : 0;
        ok = applyPreparedQuizAnswer(cppUser, items[static_cast<size_t>(i)],
                                     correct[static_cast<size_t>(i)], effectiveTs, review);
        if (!ok) {
            LOG_ERROR("bridge: tracker_apply_quiz_batch 第 {} 题失败 question_id={}", i,
                      question_ids[i]);
        }
    }
    if (ok && !review && !S().userRepo->saveUser(cppUser, S().activeUserId)) {
        LOG_ERROR("bridge: tracker_apply_quiz_batch 用户落库失败");
        ok = false;
    }
    if (ok) ok = tx.commit();
    if (!ok) {
        LOG_ERROR("bridge: tracker_apply_quiz_batch 事务失败，整批回滚 count={}", count);
        return BRIDGE_ERR_GENERIC;
    }

    user_to_c(cppUser, out_user);
    if (out_correct) {
        for (int i = 0; i < count; i++) out_correct[i] = correct[static_cast<size_t>(i)];
    }
    if (out_ability_before) {
        for (size_t i = 0; i < abilityBefore.size(); i++) out_ability_before[i] = abilityBefore[i];
    }

    if (!review) {
        const double avgBefore = S().user ? S().user->getAverageAbility() : 0.0;
        S().user = std::make_unique<User>(cppUser);
        LOG_INFO("bridge: 批量答题完成 — {} 题, avg_ability={:.3f}→{:.3f}", count, avgBefore,
                 cppUser.getAverageAbility());
    } else {
        LOG_INFO("bridge: 批量复习作答完成 — {} 题（无答题效应）", count);
    }
    return BRIDGE_OK;
    });
}

// 到期错题列表：text_id=0 取全部，否则按篇过滤；只返回 next_review_at <= now 的条目，
// 按到期时间升序，上限 max_count。返回条数（≥0）
extern "C" CHINESE_CORE_EXPORT int quiz_get_review_items(int text_id, ReviewItemData* out,
                                                         int max_count)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("quiz_get_review_items");
    if (initRc != BRIDGE_OK) return initRc;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    // 悬空过滤（内容库删题后 review_items 引用已不存在 question_id）由 ReviewRepository
    // 单源负责，默认开启；见 include/database/ReviewRepository.h
    std::vector<ReviewItem> items;
    if (!S().reviewRepo->listDue(S().activeUserId, text_id,
                                 static_cast<int64_t>(time(nullptr)), max_count, items)) {
        return BRIDGE_ERR_GENERIC;
    }
    const int n = std::min(max_count, static_cast<int>(items.size()));
    for (int i = 0; i < n; i++) {
        ReviewItemData& r = out[i];
        std::memset(&r, 0, sizeof(r));
        r.question_id = items[static_cast<size_t>(i)].questionId;
        r.text_id = items[static_cast<size_t>(i)].textId;
        r.correct_streak = items[static_cast<size_t>(i)].correctStreak;
        r.wrong_count = items[static_cast<size_t>(i)].wrongCount;
        r.next_review_at = items[static_cast<size_t>(i)].nextReviewAt;
    }
    return n;
    });
}

// 到期错题总数：与 quiz_get_review_items 同一过滤条件（含悬空过滤），
// COUNT 聚合不走行缓冲 → 无上限截断，徽标数字真实（N15 方案 B：
// "总数"与"明细"语义分离，reviewCount 走此通道，列表仍走 quiz_get_review_items）
extern "C" CHINESE_CORE_EXPORT int quiz_get_due_review_count(int text_id)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("quiz_get_due_review_count");
    if (initRc != BRIDGE_OK) return initRc;
    if (text_id < 0) return BRIDGE_ERR_GENERIC;
    int count = 0;
    if (!S().reviewRepo->dueCount(S().activeUserId, text_id,
                                  static_cast<int64_t>(time(nullptr)), count)) {
        return BRIDGE_ERR_GENERIC;
    }
    return count;
    });
}

// 错题总数：当前用户 review_items 全部条目数（含未到期，过滤悬空题目）。
// 与到期数分离，MyPage“错题总数 Y 题”用此通道。
extern "C" CHINESE_CORE_EXPORT int quiz_get_review_count(int text_id)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("quiz_get_review_count");
    if (initRc != BRIDGE_OK) return initRc;
    if (text_id < 0) return BRIDGE_ERR_GENERIC;
    int count = 0;
    if (!S().reviewRepo->totalCount(S().activeUserId, text_id, count)) {
        return BRIDGE_ERR_GENERIC;
    }
    return count;
    });
}

// 按 id 取题专用通道（复习用）：复习题是已答题，question_get_by_text 排除已答后拿不到，
// 此通道不受排除已答影响。按输入顺序返回，上限 max_count（不校验 id 是否存在，
// 缺失 id 被跳过）。返回实际条数
extern "C" CHINESE_CORE_EXPORT int quiz_get_questions_by_ids(const int* ids, int count,
                                                             QuestionData* out, int max_count)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("quiz_get_questions_by_ids");
    if (initRc != BRIDGE_OK) return initRc;
    if (!ids || !out || count <= 0 || max_count <= 0) return BRIDGE_ERR_GENERIC;

    const QuizQuestions result = S().quizRepo->getByIds(ids, count, max_count);
    if (result.status != QuizStatus::Ok) return BRIDGE_ERR_GENERIC;

    const int n = static_cast<int>(result.rows.size());
    for (int i = 0; i < n; i++) {
        fillQuestionRow(result.rows[static_cast<size_t>(i)], out[i]);
    }
    return n;
    });
}

// 文章测验摘要：总题数/已答数/错题数（review_items 现役错题）一次查询。
// 文章不存在返回 BRIDGE_ERR_TEXT；out 指针可空（跳过对应统计）
extern "C" CHINESE_CORE_EXPORT int quiz_get_attempt_summary(int text_id, int* total,
                                                            int* answered, int* wrong)
{
    return bridge_guard(g_mtx, [&]() -> int {
    const int initRc = requireInitialized("quiz_get_attempt_summary");
    if (initRc != BRIDGE_OK) return initRc;
    if (S().textIndex->find(text_id) == S().textIndex->end()) return BRIDGE_ERR_TEXT;

    // 输出先归零：查询失败（如老库缺 questions 表）时返回 0 而非调用者初值，
    // 与"表缺失=优雅降级"协议一致（N3）
    if (total) *total = 0;
    if (answered) *answered = 0;
    if (wrong) *wrong = 0;

    QuizRepository::AttemptSummary summary;
    if (!S().quizRepo->attemptSummary(S().activeUserId, text_id, summary)) {
        return BRIDGE_ERR_GENERIC;
    }
    int wrongCount = 0;
    if (wrong && !S().reviewRepo->itemCountForText(S().activeUserId, text_id, wrongCount)) {
        return BRIDGE_ERR_GENERIC;
    }
    if (total) *total = summary.total;
    if (answered) *answered = summary.answered;
    if (wrong) *wrong = wrongCount;
    return BRIDGE_OK;
    });
}
