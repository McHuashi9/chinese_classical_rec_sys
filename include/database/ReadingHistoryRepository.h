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
     * @param userId 用户ID
     * @param textId 文章ID
     * @param readTime 阅读时长（秒）
     * @param timestamp 阅读时间戳
     * @return true 成功，false 失败
     */
    bool addRecord(int userId, int textId, double readTime, time_t timestamp);
    
    /**
     * @brief 获取最近阅读记录
     * @param userId 用户ID
     * @param limit 记录数量限制
     * @param out 成功时写入阅读记录列表
     * @return false = 查询失败；true = 成功（out 可为空）
     */
    bool getRecentRecords(int userId, int limit, std::vector<ReadingRecord>& out);
    
    /**
     * @brief 获取用户总阅读次数
     * @param userId 用户ID
     * @param out 成功时写入阅读次数
     * @return false = 查询失败；true = 成功（out 可为 0）
     */
    bool getTotalReadCount(int userId, int& out);

    /**
     * @brief 标记文章已追踪（INSERT OR IGNORE）
     * @param userId 用户ID
     * @param textId 文章ID
     * @return true 成功，false 失败
     */
    bool markAsTracked(int userId, int textId);

    /**
     * @brief 获取已追踪的文章ID列表
     * @param userId 用户ID
     * @param out 成功时写入文章ID列表
     * @return false = 查询失败；true = 成功（out 可为空）
     */
    bool getTrackedTextIds(int userId, std::vector<int>& out);
    
private:
    DatabaseManager* db;
};

#endif
