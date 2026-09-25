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

    /**
     * @brief 读取 classical_text.annotations_raw 单列
     *
     * v1.4.0 工作项 2：自 bridge 的 text_get_annotations 下沉（原手写 stmt）。
     * @param id 文章 id
     * @param out 输出（NULL 列按空串；调用方进入前无需清空）
     * @return true = 该行存在（查询成功）；false = 无该行或查询失败
     */
    bool getAnnotationsRaw(int id, std::string& out);

    /**
     * @brief 读取 classical_text.translation 单列（对应 bridge 的 text_get_translation）
     */
    bool getTranslation(int id, std::string& out);

private:
    /** 单列读取实现：column 为受控常量列名（annotations_raw / translation） */
    bool getSingleColumn(int id, const char* column, std::string& out);

    DatabaseManager* db;
};

#endif
