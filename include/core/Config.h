#ifndef CONFIG_H
#define CONFIG_H

#include <cmath>

/**
 * @brief 算法参数配置
 * 
 * 存储论文中定义的算法参数默认值
 * 参数值来自 E7 敏感度分析调优结果
 */
struct Config {
    // i+1推荐算法参数（论文Section 6，E7调优）
    static constexpr double DELTA_STAR = 0.13;    // 理想难度差距 δ*
    static constexpr double SIGMA = 0.25;         // 容差参数 σ
    
    // 状态更新参数（论文Section 5.3）
    static constexpr double ETA = 0.08;           // 基础学习率 η（悟性）
    static constexpr double GAMMA = 1.5;          // 学习率衰减指数 γ
    static constexpr double TAU = 10.0;           // 遗忘时间常数 τ (天)
    static constexpr double C = 0.70;             // 幂律遗忘指数 c
    static constexpr double U_FLOOR = 0.15;       // 遗忘保留底线
    static constexpr double PSI_MIN = 0.05;       // 增量清理阈值（遗忘因子低于此值时合并到基础能力）
    
    // 动态权重参数
    static constexpr double ALPHA_0 = 0.40;       // 初始难度/兴趣权重 α₀
    static constexpr double U_TARGET = 0.80;      // 目标能力阈值
    
    // 最小阅读时间阈值（秒）
    static constexpr int MIN_READ_TIME = 30;
};

/**
 * @brief 高斯函数（公式19）
 *        exp(-x² / 2σ²)
 */
inline double gaussian(double x) {
    return std::exp(-x * x / (2.0 * Config::SIGMA * Config::SIGMA));
}

/**
 * @brief 动态学习率（公式13）
 *        η(t) = η · (1 - ū(t))^γ
 */
inline double calculateDynamicLearningRate(double avgAbility) {
    return Config::ETA * std::pow(1.0 - avgAbility, Config::GAMMA);
}

/**
 * @brief 学习增益（公式14）
 *        g_j = exp(-(d̂_j - u_j - δ*)² / 2σ²)
 */
inline double calculateLearningGain(double d_j, double u_j) {
    return gaussian(d_j - u_j - Config::DELTA_STAR);
}

#endif
