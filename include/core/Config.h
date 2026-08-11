#ifndef CONFIG_H
#define CONFIG_H

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
    static constexpr double ETA = 0.08;           // 初始学习率 η（悟性，user.eta 随答题动态调整）
    static constexpr double GAMMA = 1.5;          // 学习率衰减指数 γ
    static constexpr double TAU = 10.0;           // 遗忘时间常数 τ (天)
    static constexpr double C = 0.70;             // 幂律遗忘指数 c
    static constexpr double U_FLOOR = 0.15;       // 遗忘保留底线
    static constexpr double PSI_MIN = 0.05;       // 增量清理阈值（遗忘因子低于此值时合并到基础能力）

    // 答题效应参数（论文Section 5.3 + E4 默认值表 tab:e4_params）
    static constexpr double QUIZ_K0 = 0.40;       // 答题效应初始K因子 K₀
    static constexpr double QUIZ_K_MIN = 0.05;    // K因子下限 K_min
    static constexpr double QUIZ_LAMBDA_K = 0.08; // K因子衰减速率 λ_K
    static constexpr double QUIZ_BETA = 4.0;      // Sigmoid区分度 β（预期正确率陡峭度）
    static constexpr double ALPHA_ETA = 0.02;     // 悟性调整系数 α_η
    static constexpr double ETA_MIN = 0.02;       // 悟性下限 η_min
    static constexpr double ETA_MAX = 0.15;       // 悟性上限 η_max
    static constexpr double QUIZ_WEIGHT_FACTOR = 0.5; // 已答题维度的推荐权重衰减因子（降权后重新归一化）
    
    // 动态权重参数
    static constexpr double ALPHA_0 = 0.40;       // 初始难度/兴趣权重 α₀
    static constexpr double U_TARGET = 0.80;      // 目标能力阈值
    
    // 最小阅读时间阈值（秒）
    static constexpr int MIN_READ_TIME = 30;
    
    // 增量过滤阈值（低于此值的有意义增量记录将被忽略）
    static constexpr double MIN_DELTA_THRESHOLD = 0.0001;

    // CRITIC法权重（来自 data/critic_weights.json，归一化，∑ w_j = 1）
    static constexpr double CRITIC_WEIGHTS[10] = {
        0.09215147849158459,   // d1 平均句长
        0.09381903520884108,   // d2 句子数
        0.13107376305655005,   // d3 虚词比例
        0.09247110185289635,   // d4 字平均对数频次
        0.10340632494506398,   // d5 通假字密度
        0.11624060937033848,   // d6 古汉语困惑度
        0.08774914762423046,   // d7 今汉语困惑度
        0.08543906673127047,   // d8 MATTR词汇多样性
        0.10087872345819664,   // d9 典故密度
        0.09677074926102798    // d10 语义复杂度
    };
};

#endif
