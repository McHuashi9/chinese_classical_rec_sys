#ifndef READING_HISTORY_REPOSITORY_H
#define READING_HISTORY_REPOSITORY_H

#include "database/DatabaseManager.h"
#include <ctime>

/**
 * @brief 阅读记录结构
 */
struct ReadingRecord {
    int id;              // 记录ID
    int textId;          // 文章ID
    double readTime;     // 阅读时长（秒）
    time_t timestamp;    // 阅读时间戳
};

/**
 * @brief 阅读历史数据访问类
 * 
 * 处理阅读历史记录的数据库操作
 */
class ReadingHistoryRepository {
public:
    ReadingHistoryRepository(DatabaseManager* dbManager);
    
    /**
     * @brief 初始化阅读历史表（如果不存在则创建）
     */
    bool initTable();
    
    /**
     * @brief 添加阅读记录
     * @param textId 文章ID
     * @param readTime 阅读时长（秒）
     * @param timestamp 阅读时间戳
     * @return true 成功，false 失败
     */
    bool addRecord(int textId, double readTime, time_t timestamp);
    
    /**
     * @brief 获取最近阅读记录
     * @param limit 记录数量限制
     * @return 阅读记录列表
     */
    std::vector<ReadingRecord> getRecentRecords(int limit = 10);
    
    /**
     * @brief 获取用户总阅读次数
     * @return 阅读次数
     */
    int getTotalReadCount();

    /**
     * @brief 标记文章已追踪（INSERT OR IGNORE）
     * @param textId 文章ID
     * @return true 成功，false 失败
     */
    bool markAsTracked(int textId);

    /**
     * @brief 获取已追踪的文章ID列表
     * @return 文章ID列表
     */
    std::vector<int> getTrackedTextIds();
    
private:
    DatabaseManager* db;
};

#endif
