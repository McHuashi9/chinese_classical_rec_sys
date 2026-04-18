#ifndef USER_H
#define USER_H

#include <string>
#include <array>
#include <ctime>

/**
 * @brief 用户模型类
 * 
 * 存储当前用户的信息，包括用户名和10维能力向量
 * 论文Table 3定义的10维映射：
 * d1 = f1 (平均句长)
 * d2 = f3 (句子数)
 * d3 = f5 (虚词比例)
 * d4 = f6 (字平均对数频次)
 * d5 = f8 (通假字密度)
 * d6 = f9 (古汉语困惑度)
 * d7 = f10 (今汉语困惑度)
 * d8 = f11 (MATTR词汇多样性)
 * d9 = f12 (典故密度)
 * d10 = f13 (语义复杂度)
 */
class User {
public:
    User();
    
    void setName(const std::string& name);
    std::string getName() const;
    bool isEmpty() const;
    
    /**
     * @brief 统一接口：通过索引访问能力值 (0-9 对应 d1-d10)
     * @param index 维度索引 (0-9)
     * @return 该维度的能力值
     */
    void setAbility(int index, double value);
    double getAbility(int index) const;
    
    // ============================================
    // 注意：已移除维度便捷接口以遵循 DRY 原则
    // ============================================
    // 设计说明：
    // 原设计包含 d1-d10 的独立 getter/setter 方法 (20处重复)。
    // 根据 L3 代码审查 (DRY 阈值：最多3次重复)，已移除这些方法。
    // 请使用统一的 getAbility/setAbility 接口，通过索引访问。
    // 维度映射：d1=0, d2=1, ..., d10=9
    // ============================================
    

    
    /**
     * @brief 获取平均能力值
     * @return 10维能力值的平均
     */
    double getAverageAbility() const;
    
    /**
     * @brief 使用贝叶斯先验均值初始化能力值
     * 论文定义：无入学测试时，u_j(0) = α_0 / (α_0 + β_0) = 0.3
     */
    void initializeDefault();
    
    /**
     * @brief 获取最后阅读时间
     * @return Unix时间戳
     */
    time_t getLastReadTime() const;
    
    /**
     * @brief 设置最后阅读时间
     * @param time Unix时间戳
     */
    void setLastReadTime(time_t time);
    
    /**
     * @brief 通过索引访问基础能力值 (0-9 对应 d1-d10)
     * 基础能力是早期积累的知识，遗忘极慢
     */
    void setBaseAbility(int index, double value);
    double getBaseAbility(int index) const;
    
private:
    std::string name;
    std::array<double, 10> abilities;      // d1-d10 当前能力
    std::array<double, 10> baseAbilities;  // d1-d10 基础能力（遗忘极慢）
    time_t lastReadTime;                   // 最后阅读时间戳
};

#endif