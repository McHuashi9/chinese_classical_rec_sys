#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"

std::vector<double> FeatureExtractor::getNormalizedFeatures(const Text& text) {
    LOG_DEBUG("提取特征: 文章ID={}", text.getId());
    
    // 论文 Table 3: 10 维标准化特征映射
    // 注意：特征已在 Python 预处理阶段标准化到 [0,1]
    return {
        text.getF1AvgSentenceLength(),   // d1
        text.getF3SentenceCount(),       // d2
        text.getF5FunctionWordRatio(),   // d3
        text.getF6AvgCharLogFreq(),      // d4
        text.getF8TongjiaziDensity(),    // d5
        text.getF9PplAncient(),          // d6
        text.getF10PplModern(),          // d7
        text.getF11Mattr(),              // d8
        text.getF12AllusionDensity(),    // d9
        text.getF13SemanticComplexity()  // d10
    };
}
