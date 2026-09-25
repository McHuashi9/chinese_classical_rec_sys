#ifndef REVIEW_REPOSITORY_H
#define REVIEW_REPOSITORY_H

#include "database/DatabaseManager.h"

#include <cstdint>
#include <string>
#include <vector>

/**
 * @brief review_items 单行（错题复习队列条目）
 */
struct ReviewItem {
    int questionId = 0;
    int textId = 0;
    int correctStreak = 0;
    int wrongCount = 0;
    int64_t nextReviewAt = 0;
};

/**
 * @brief 错题复习队列数据访问（v1.4.0 工作项 2：自 bridge.cpp 下沉）
 *
 * 收敛原 bridge.cpp 中三处近似重复的 review_items WHERE 片段
 * （:1655-1659 到期列表 / :1700-1702 到期计数 / :1734-1736 总数）为单源。
 *
 * **悬空过滤作为可开关策略**：内容库删题后 review_items 会留下引用已不存在 question_id 的
 * 条目（db_replace 合并内容库后尤其明显）→ 默认开启过滤（且 questions 表存在时才生效），
 * 可用 setDanglingFilter(false) 关闭以观察原始队列。
 */
class ReviewRepository {
public:
    explicit ReviewRepository(DatabaseManager* dbManager);

    void setDanglingFilter(bool enabled) { danglingFilter_ = enabled; }
    bool danglingFilter() const { return danglingFilter_; }

    /** @brief 到期错题列表：next_review_at <= now，按到期时间升序，上限 maxCount */
    std::vector<ReviewItem> listDue(int userId, int textId, int64_t now, int maxCount);

    /** @brief 到期错题总数（COUNT 聚合，不受列表上限截断；与 listDue 同过滤条件） */
    int dueCount(int userId, int textId, int64_t now);

    /** @brief 当前用户错题总数（含未到期） */
    int totalCount(int userId, int textId);

    /** @brief 指定文章的现役错题数（quiz_get_attempt_summary 的 wrong 通道） */
    int itemCountForText(int userId, int textId);

    /**
     * @brief 答错入队/累计：streak 清零、wrong_count+1、next_review_at = nextReviewAt
     * @param nextReviewAt 由 ReviewScheduler::dueAfterWrong 计算（answered_at + base）
     */
    bool upsertWrong(int userId, int questionId, int textId, int64_t nextReviewAt);

    /** @brief 读取当前连续答对次数；无该行时 streakOut=0；查询出错返回 false */
    bool streak(int userId, int questionId, int& streakOut);

    /** @brief 从复习队列移除（正式测验答对视为掌握 / 复习达到掌握阈值） */
    bool removeItem(int userId, int questionId);

    /** @brief 复习答对 → 更新 streak 与下次到期 */
    bool bumpStreak(int userId, int questionId, int streak, int64_t nextReviewAt);

private:
    bool questionsTableExists() const;

    /** 悬空过滤后缀：开关开启且 questions 表存在时生效（单源，三处查询共用） */
    std::string danglingSuffix() const;

    DatabaseManager* db;
    bool danglingFilter_ = true;
};

#endif
