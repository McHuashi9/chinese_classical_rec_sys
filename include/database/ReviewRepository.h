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
 * @brief 错题复习队列数据访问
 *
 * review_items 的 WHERE 片段在本仓储内单源生成，到期列表、到期计数与总数共用同一口径。
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

    /** @brief 到期错题列表；true=成功（out 可为空），false=查询失败 */
    bool listDue(int userId, int textId, int64_t now, int maxCount,
                 std::vector<ReviewItem>& out);

    /** @brief 到期错题总数；true=成功（out 可为 0），false=查询失败 */
    bool dueCount(int userId, int textId, int64_t now, int& out);

    /** @brief 当前用户错题总数（含未到期）；true=成功（out 可为 0），false=查询失败 */
    bool totalCount(int userId, int textId, int& out);

    /** @brief 指定文章现役错题数；true=成功（out 可为 0），false=查询失败 */
    bool itemCountForText(int userId, int textId, int& out);

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
