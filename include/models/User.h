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
    // 维度便捷接口 (Dimension Convenience API)
    // ============================================
    // 设计说明：
    // 虽然存在统一接口 getAbility/setAbility，但保留这些命名
    // getter/setter 是有意的，原因如下：
    // 1. 类型安全：避免数组越界风险
    // 2. 可读性：调用方代码更清晰 (如 user.getD1Ability())
    // 3. IDE 支持：自动补全和类型提示更友好
    // 4. 兼容性：不破坏现有调用代码
    // ============================================
    
    // d1: 平均句长能力 (f1)
    void setD1Ability(double ability);
    double getD1Ability() const;
    
    // d2: 句子数能力 (f3)
    void setD2Ability(double ability);
    double getD2Ability() const;
    
    // d3: 虚词比例能力 (f5)
    void setD3Ability(double ability);
    double getD3Ability() const;
    
    // d4: 字平均对数频次能力 (f6)
    void setD4Ability(double ability);
    double getD4Ability() const;
    
    // d5: 通假字密度能力 (f8)
    void setD5Ability(double ability);
    double getD5Ability() const;
    
    // d6: 古汉语困惑度能力 (f9)
    void setD6Ability(double ability);
    double getD6Ability() const;
    
    // d7: 今汉语困惑度能力 (f10)
    void setD7Ability(double ability);
    double getD7Ability() const;
    
    // d8: MATTR词汇多样性能力 (f11)
    void setD8Ability(double ability);
    double getD8Ability() const;
    
    // d9: 典故密度能力 (f12)
    void setD9Ability(double ability);
    double getD9Ability() const;
    
    // d10: 语义复杂度能力 (f13)
    void setD10Ability(double ability);
    double getD10Ability() const;
    
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