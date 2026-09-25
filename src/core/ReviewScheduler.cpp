#include "core/ReviewScheduler.h"

#include "core/Config.h"

int64_t ReviewScheduler::intervalAfter(int streak)
{
    int64_t interval = Config::REVIEW_BASE_INTERVAL;
    for (int i = 0; i < streak && i < 10; i++) {
        interval *= 2;
        if (interval >= Config::REVIEW_MAX_INTERVAL) return Config::REVIEW_MAX_INTERVAL;
    }
    return interval > Config::REVIEW_MAX_INTERVAL ? Config::REVIEW_MAX_INTERVAL : interval;
}

bool ReviewScheduler::isMasteredAfterCorrect(int currentStreak)
{
    return currentStreak + 1 >= Config::REVIEW_MASTER_STREAK;
}

bool ReviewScheduler::isDue(int64_t nextReviewAt, int64_t now)
{
    return nextReviewAt <= now;
}

int64_t ReviewScheduler::dueAfterWrong(int64_t answeredAt)
{
    return answeredAt + Config::REVIEW_BASE_INTERVAL;
}
