#ifndef LEARNING_INCREMENT_REPOSITORY_H
#define LEARNING_INCREMENT_REPOSITORY_H

#include "database/DatabaseManager.h"
#include <vector>
#include <ctime>

/**
 * @brief 学习增量结构
 * 
 * 存储单次学习产生的增量记录
 */
struct LearningIncrement {
    int id;              ///< 记录ID
    int userId;          ///< 用户ID
    int dimension;       ///< 维度索引 (1-10)
    double delta;        ///< 增量值 Δu_j^(k)
    time_t timestamp;    ///< 学习时刻 t_k
    std::string type;    ///< 增量类型 (read/quiz)
};

/**
 * @brief 学习增量数据访问类
 * 
 * 管理学习增量的存储、查询和清理
 * 支持论文公式17的增量历史追踪模型
 */
class LearningIncrementRepository {
public:
    LearningIncrementRepository(DatabaseManager* dbManager);
    
    /**
     * @brief 初始化增量表（如果不存在则创建）
     */
    bool initTable();
    
    /**
     * @brief 添加学习增量
     * @param userId 用户ID
     * @param dimension 维度索引 (1-10)
     * @param delta 增量值
     * @param timestamp 学习时刻
     * @param type 增量类型
     * @return true 成功
     */
    bool addIncrement(int userId, int dimension, double delta, 
                      time_t timestamp, const std::string& type = "read");
    
    /**
     * @brief 获取某维度的所有增量
     * @param userId 用户ID
     * @param dimension 维度索引 (1-10)
     * @return 增量列表
     */
    std::vector<LearningIncrement> getIncrements(int userId, int dimension);
    
    /**
     * @brief 获取用户所有增量
     * @param userId 用户ID
     * @return 增量列表
     */
    std::vector<LearningIncrement> getAllIncrements(int userId);
    
    /**
     * @brief 删除单个增量
     * @param id 增量ID
     * @return true 成功
     */
    bool deleteIncrement(int id);
    
    /**
     * @brief 批量删除增量
     * @param ids 增量ID列表
     * @return true 成功
     */
    bool deleteIncrements(const std::vector<int>& ids);
    
    /**
     * @brief 获取用户的增量总数
     * @param userId 用户ID
     * @return 增量数量
     */
    int getIncrementCount(int userId);
    
private:
    DatabaseManager* db;
};

#endif
