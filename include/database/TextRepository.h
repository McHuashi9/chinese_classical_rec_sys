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
     * @brief 根据ID获取古文
     * @param id 古文ID
     * @param text 用于存储查询结果的 Text 对象
     * @return true 找到古文，false 未找到或出错
     */
    bool getTextById(int id, Text& text);
    
    /**
     * @brief 获取所有古文
     * @return 古文列表
     */
    std::vector<Text> getAllTexts();
    
    /**
     * @brief 保存古文（插入新记录）
     * @param text 古文对象
     * @return true 成功，false 失败
     */
    bool saveText(const Text& text);
    
    /**
     * @brief 更新古文
     * @param text 古文对象
     * @return true 成功，false 失败
     */
    bool updateText(const Text& text);
    
    /**
     * @brief 删除古文
     * @param id 古文ID
     * @return true 成功，false 失败
     */
    bool deleteText(int id);
    
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
    
    /**
     * @brief 按 ID 区间获取古文（闭区间）
     * @param startId 起始 ID（包含）
     * @param endId 结束 ID（包含）
     * @return 古文列表
     */
    std::vector<Text> getTextsByIdRange(int startId, int endId);
    
private:
    DatabaseManager* db;
};

#endif
