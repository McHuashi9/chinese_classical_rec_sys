#ifndef TEXT_REPOSITORY_H
#define TEXT_REPOSITORY_H

#include "database/DatabaseManager.h"
#include "models/Text.h"
#include <vector>
#include <string>

/**
 * @brief 古文数据访问类
 * 
 * 处理古文相关的数据库操作
 */
class TextRepository {
public:
    TextRepository(DatabaseManager* dbManager);
    
    /**
     * @brief 初始化古文表（如果不存在则创建）
     */
    bool initTable();
    
    /**
     * @brief 获取所有古文
     * @return 古文列表
     */
    std::vector<Text> getAllTexts();
    
    /**
     * @brief 检查表是否为空
     * @return true 为空，false 不为空或出错
     */
    bool isEmpty();
    
    /**
     * @brief 获取古文总数
     * @return 古文总数，出错返回0
     */
    int getCount();
    
private:
    DatabaseManager* db;
};

#endif
