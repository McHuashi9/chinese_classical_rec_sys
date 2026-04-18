#ifndef FEATURE_EXTRACTOR_H
#define FEATURE_EXTRACTOR_H

#include <vector>
#include "models/Text.h"

/**
 * @brief 特征提取工具类
 * 
 * 提供从 Text 对象提取 10 维标准化特征的静态方法
 * 用于 KnowledgeTracker 和 RecommendationEngine 共享特征提取逻辑
 * 
 * 特征维度（论文 Table 3）：
 * d1/f1: avg_sentence_length (平均句长)
 * d2/f3: sentence_count (句子数)
 * d3/f5: function_word_ratio (虚词比例)
 * d4/f6: avg_char_log_freq (字平均对数频次)
 * d5/f8: tongjiazi_density (通假字密度)
 * d6/f9: ppl_ancient (古汉语困惑度)
 * d7/f10: ppl_modern (现代文困惑度)
 * d8/f11: mattr (词汇多样性)
 * d9/f12: allusion_density (典故密度)
 * d10/f13: semantic_complexity (语义复杂度)
 */
class FeatureExtractor {
public:
    /**
     * @brief 从 Text 对象提取 10 维标准化特征向量
     * 
     * @param text 文本对象
     * @return std::vector<double> 包含 10 个标准化特征的向量（已在 Python 预处理阶段标准化到 [0,1]）
     */
    static std::vector<double> getNormalizedFeatures(const Text& text);
};

#endif
