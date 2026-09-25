// 桥层题目与复习域（v1.4.0 工作项 3）：question_get_by_text / tracker_apply_quiz /
// quiz_get_review_items / quiz_get_due_review_count / quiz_get_review_count /
// quiz_get_questions_by_ids / quiz_get_attempt_summary，共 7 个导出符号。
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
#include <vector>

// 取题：按 text_id 返回该文题目（排除已答含复习记录 → 固定种子随机轮换，上限 max_count；
// 不下发 answer_index，判题只在 C++ 侧）
// 返回：题数（≥0）；文章不存在返回 BRIDGE_ERR_TEXT；参数非法返回 BRIDGE_ERR_GENERIC
// answered_all（可空）：1 = 该篇已无未答题；0 = 还有未答题或该篇无题
extern "C" CHINESE_CORE_EXPORT int question_get_by_text(int text_id, QuestionData* out,
                                                        int max_count, int* answered_all)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
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

// 答题：按 question_id 查题 → 判题（用户选项 vs answer_index）→ applyQuizEffect（正式测验）
// + 写作答流水 quiz_attempts + upsert 复习状态 review_items（同锁同事务）
// is_review=1（错题复习）：跳过 applyQuizEffect（不更新能力/eta/quiz_count，防刷分），
// 只判题 + 写流水 + 更新复习状态。
extern "C" CHINESE_CORE_EXPORT int tracker_apply_quiz(const UserData* user, int question_id,
                                      int user_choice, int64_t timestamp,
                                      UserData* out_user, int* out_correct, int is_review)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!user || !out_user) return BRIDGE_ERR_GENERIC;

    // 1. 查询题目（text_id / answer_index / dims CSV）
    const QuizQuestionInfo info = S().quizRepo->getQuestionInfo(question_id);
    if (info.status == QuizStatus::MissingTable) {
        LOG_WARN("bridge: tracker_apply_quiz 无 questions 表 question_id={}", question_id);
        return BRIDGE_ERR_TEXT;
    }
    if (info.status != QuizStatus::Ok) {
        LOG_ERROR("bridge: tracker_apply_quiz 题目查询失败: {}", S().db->getLastError());
        return BRIDGE_ERR_GENERIC;
    }
    if (!info.found) {
        LOG_WARN("bridge: 题目不存在 question_id={}", question_id);
        return BRIDGE_ERR_TEXT;
    }
    if ((info.nullFields & (QuizFieldTextId | QuizFieldAnswerIndex | QuizFieldDims)) != 0) {
        LOG_WARN("bridge: 题目字段缺失 question_id={}", question_id);
        return BRIDGE_ERR_TEXT;
    }

    const int tid = info.textId;
    const int ans_idx = info.answerIndex;
    if (ans_idx < 0 || ans_idx > 3) {
        LOG_WARN("bridge: answer_index 越界 question_id={} idx={}", question_id, ans_idx);
        return BRIDGE_ERR_GENERIC;
    }
    if (user_choice < 0 || user_choice > 3) {
        LOG_WARN("bridge: user_choice 越界 question_id={} choice={}", question_id, user_choice);
        return BRIDGE_ERR_GENERIC;
    }

    auto it = S().textIndex->find(tid);
    if (it == S().textIndex->end()) return BRIDGE_ERR_TEXT;

    // 2. 解析 dims CSV（如 "3,4,9" 表示 0-based 维度）
    std::vector<int> dim_list;
    {
        std::stringstream ss(info.dims);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) dim_list.push_back(std::atoi(tok.c_str()));
        }
    }
    if (dim_list.empty()) {
        LOG_WARN("bridge: dims 为空 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }

    // 3. 判题（答题效应在步骤 4 事务内应用）
    User cpp_user;
    c_to_user(user, cpp_user);

    const int correct = (user_choice == ans_idx) ? 1 : 0;
    if (out_correct) *out_correct = correct;
    time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);

    // 4. 答题效应 + 落库 + 作答流水 + 复习状态（同一事务；失败回滚且返回错误）。
    // 防双计：若事务失败，能力/quiz_count/eta/增量与流水一起回滚，用户重试同一题不会二次生效
    SqlTransaction tx(S().db.get(), "BEGIN");
    if (!tx.ok()) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    if (!is_review) {
        S().tracker->applyQuizEffect(cpp_user, (*S().texts)[it->second], dim_list,
                                     correct, effective_ts);
        user_to_c(cpp_user, out_user);
        if (!S().userRepo->saveUser(cpp_user, S().activeUserId)) {
            LOG_ERROR("bridge: 答题效应落库失败 question_id={}", question_id);
            return BRIDGE_ERR_GENERIC;
        }
    } else {
        // 复习无效应：原样回传（调用方仍按契约接管返回的 user 内存）
        user_to_c(cpp_user, out_user);
    }

    ok = S().quizRepo->insertAttempt(S().activeUserId, question_id, tid, correct,
                                     is_review ? 1 : 0, 0,
                                     static_cast<int64_t>(effective_ts));
    if (!ok) {
        LOG_ERROR("bridge: quiz_attempts 写入失败 question_id={}: {}", question_id,
                  S().db->getLastError());
    }

    if (ok && correct == 1) {
        if (!is_review) {
            // 正式测验答对 → 视为已掌握，从复习队列移除
            ok = S().reviewRepo->removeItem(S().activeUserId, question_id);
            if (!ok) {
                LOG_ERROR("bridge: review_items 删除失败 question_id={}: {}", question_id,
                          S().db->getLastError());
            }
        } else {
            // 复习答对 → streak+1，间隔翻倍；streak≥3 移除（视为掌握）
            int streak = 0;
            ok = S().reviewRepo->streak(S().activeUserId, question_id, streak);
            if (ok) {
                if (ReviewScheduler::isMasteredAfterCorrect(streak)) {
                    ok = S().reviewRepo->removeItem(S().activeUserId, question_id);
                } else {
                    ok = S().reviewRepo->bumpStreak(
                        S().activeUserId, question_id, streak + 1,
                        static_cast<int64_t>(effective_ts) +
                            ReviewScheduler::intervalAfter(streak + 1));
                }
            }
            if (!ok) {
                LOG_ERROR("bridge: review_items 更新失败 question_id={}: {}", question_id,
                          S().db->getLastError());
            }
        }
    } else if (ok && correct == 0) {
        // 答错（正式或复习均重置）：streak 清零、wrong_count+1、下次到期 = answered_at + base
        ok = S().reviewRepo->upsertWrong(
            S().activeUserId, question_id, tid,
            ReviewScheduler::dueAfterWrong(static_cast<int64_t>(effective_ts)));
        if (!ok) {
            LOG_ERROR("bridge: review_items upsert 失败 question_id={}: {}", question_id,
                      S().db->getLastError());
        }
    }

    if (ok) ok = tx.commit();
    if (!ok) {
        LOG_ERROR("bridge: tracker_apply_quiz 事务失败 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }

    // 事务成功后才更新内存态（与磁盘一致；失败时保持旧值，重试不会双计）
    if (!is_review) {
        const double avg_before = S().user->getAverageAbility();
        S().user = std::make_unique<User>(cpp_user);
        LOG_INFO("bridge: 答题效应完成 — question_id={}, correct={}, avg_ability={:.3f}→{:.3f}",
                 question_id, correct, avg_before, cpp_user.getAverageAbility());
    } else {
        LOG_INFO("bridge: 复习作答完成 — question_id={}, correct={}（无答题效应）",
                 question_id, correct);
    }
    return BRIDGE_OK;
    });
}

// 到期错题列表：text_id=0 取全部，否则按篇过滤；只返回 next_review_at <= now 的条目，
// 按到期时间升序，上限 max_count。返回条数（≥0）
extern "C" CHINESE_CORE_EXPORT int quiz_get_review_items(int text_id, ReviewItemData* out,
                                                         int max_count)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    // 悬空过滤（内容库删题后 review_items 引用已不存在 question_id）由 ReviewRepository
    // 单源负责，默认开启；见 include/database/ReviewRepository.h
    const auto items = S().reviewRepo->listDue(S().activeUserId, text_id,
                                               static_cast<int64_t>(time(nullptr)), max_count);
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
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (text_id < 0) return BRIDGE_ERR_GENERIC;
    return S().reviewRepo->dueCount(S().activeUserId, text_id,
                                    static_cast<int64_t>(time(nullptr)));
    });
}

// 错题总数：当前用户 review_items 全部条目数（含未到期，过滤悬空题目）。
// 与到期数分离，MyPage“错题总数 Y 题”用此通道。
extern "C" CHINESE_CORE_EXPORT int quiz_get_review_count(int text_id)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (text_id < 0) return BRIDGE_ERR_GENERIC;
    return S().reviewRepo->totalCount(S().activeUserId, text_id);
    });
}

// 按 id 取题专用通道（复习用）：复习题是已答题，question_get_by_text 排除已答后拿不到，
// 此通道不受排除已答影响。按输入顺序返回，上限 max_count（不校验 id 是否存在，
// 缺失 id 被跳过）。返回实际条数
extern "C" CHINESE_CORE_EXPORT int quiz_get_questions_by_ids(const int* ids, int count,
                                                             QuestionData* out, int max_count)
{
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
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
    return bridge_guard(g_mtx, [&] {
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (S().textIndex->find(text_id) == S().textIndex->end()) return BRIDGE_ERR_TEXT;

    // 输出先归零：查询失败（如老库缺 questions 表）时返回 0 而非调用者初值，
    // 与"表缺失=优雅降级"协议一致（N3）
    if (total) *total = 0;
    if (answered) *answered = 0;
    if (wrong) *wrong = 0;

    const QuizRepository::AttemptSummary summary =
        S().quizRepo->attemptSummary(S().activeUserId, text_id);
    if (total) *total = summary.total;
    if (answered) *answered = summary.answered;
    if (wrong) *wrong = S().reviewRepo->itemCountForText(S().activeUserId, text_id);
    return BRIDGE_OK;
    });
}
