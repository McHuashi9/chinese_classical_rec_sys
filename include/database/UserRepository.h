#ifndef USER_REPOSITORY_H
#define USER_REPOSITORY_H

#include "database/DatabaseManager.h"
#include "models/User.h"
#include <string>

/**
 * @brief 用户数据访问类
 * 
 * 处理用户相关的数据库操作
 */
class UserRepository {
public:
    UserRepository(DatabaseManager* dbManager);
    
    /**
     * @brief 初始化用户表（如果不存在则创建）
     */
    bool initTable();
    
    /**
     * @brief 获取当前用户信息
     * @param user 用于存储查询结果的 User 对象
     * @return true 找到用户，false 未找到或出错
     */
    bool getUser(User& user);
    
    /**
     * @brief 保存用户名（插入或更新）
     * @param userName 用户名
     * @return true 成功，false 失败
     */
    bool saveUserName(const std::string& userName);
    
    /**
     * @brief 保存完整用户信息（包括能力向量）
     * @param user 用户对象
     * @return true 成功，false 失败
     */
    bool saveUser(const User& user);
    
    /**
     * @brief 获取最后阅读时间
     * @return Unix时间戳，失败返回0
     */
    time_t getLastReadTime();
    
    /**
     * @brief 更新最后阅读时间
     * @param time Unix时间戳
     * @return true 成功，false 失败
     */
    bool updateLastReadTime(time_t time);
    
private:
    DatabaseManager* db;
};

#endif