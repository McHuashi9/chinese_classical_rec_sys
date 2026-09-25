#ifndef REVIEW_SCHEDULER_H
#define REVIEW_SCHEDULER_H

#include <cstdint>

/**
 * @brief 错题复习调度纯逻辑（无 DB 依赖）
 *
 * v1.4.0 工作项 2：自 `bridge/bridge.cpp` 下沉。原 `reviewIntervalAfter`（:1385-1393）、
 * 掌握判定（:1563 `streak + 1 >= REVIEW_MASTER_STREAK`）、答错后的首次到期（:1611-1612
 * `answered_at + REVIEW_BASE_INTERVAL`）与到期边界（:1656/:1700 `next_review_at <= now`）
 * 都只依赖已读配置 `Config::REVIEW_*`（include/core/Config.h:39-41），因此保持静态方法、
 * 不持有任何状态。数据读写留在 ReviewRepository。
 */
class ReviewScheduler {
public:
    /**
     * @brief 复习间隔：base · 2^streak，封顶 REVIEW_MAX_INTERVAL（逐字保留原实现语义）
     */
    static int64_t intervalAfter(int streak);

    /** @brief 当前连续答对 currentStreak 次后再答对一次是否达到掌握（可从队列移除） */
    static bool isMasteredAfterCorrect(int currentStreak);

    /** @brief 到期边界：next_review_at <= now */
    static bool isDue(int64_t nextReviewAt, int64_t now);

    /** @brief 答错后的下次到期时间 = answeredAt + REVIEW_BASE_INTERVAL */
    static int64_t dueAfterWrong(int64_t answeredAt);
};

#endif
