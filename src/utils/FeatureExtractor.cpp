#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"

std::vector<double> FeatureExtractor::getNormalizedFeatures(const Text& text) {
    LOG_DEBUG("提取特征: 文章ID={}", text.getId());
    
    // 论文 Table 3: 10 维标准化特征映射
    // 注意：特征已在 Python 预处理阶段标准化到 [0,1]
    std::vector<double> features;
    for (int i = 0; i < 10; i++) {
        features.push_back(text.getDifficulty(i));
    }
    return features;
}
