#ifndef USER_REPOSITORY_H
#define USER_REPOSITORY_H

#include "database/DatabaseManager.h"
#include "models/User.h"
#include <cstdint>
#include <string>
#include <vector>

/**
 * @brief 档案元数据（profiles 表行）
 */
struct ProfileInfo {
    int id = 0;
    std::string name;
    int deleted = 0;
    int64_t createdAt = 0;
    int64_t lastUsedAt = 0;
};

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
     * @brief 获取指定用户信息
     * @param user 用于存储查询结果的 User 对象
     * @param userId 用户 id（1-based，对应 user.id / profiles.id）
     * @return true 找到用户，false 未找到或出错
     */
    bool getUser(User& user, int userId);
    
    /**
     * @brief 保存完整用户信息（包括能力向量）
     * @param user 用户对象
     * @param userId 用户 id（写入 user.id）
     * @return true 成功，false 失败
     */
    bool saveUser(const User& user, int userId);

    /**
     * @brief 列出未删除档案（按 id 升序）
     */
    std::vector<ProfileInfo> listProfiles();

    /**
     * @brief 新建档案：profiles 行 + user 默认行，事务包裹
     * @param name 档案名（非空，UTF-8）
     * @param outId 输出新档案 id
     * @return true 成功
     */
    bool createProfile(const std::string& name, int& outId);

    /**
     * @brief 重命名未删除档案
     * @return true = 目标存在且已更新
     */
    bool renameProfile(int userId, const std::string& name);

    /**
     * @brief 软删档案（置 deleted=1，不清理数据）
     * @return true = 目标存在且已软删
     */
    bool deleteProfile(int userId);

    /**
     * @brief 档案是否存在且未删除
     */
    bool isProfileActive(int userId);

    /**
     * @brief 更新档案最近使用时间
     */
    bool touchProfile(int userId);

    /**
     * @brief 幂等确保档案行存在（老库 id=1 默认档案迁移用；已存在不覆盖）
     */
    bool ensureProfileExists(int userId, const std::string& name);
    
private:
    DatabaseManager* db;
};

#endif