#ifndef TEXT_H
#define TEXT_H

#include <string>

/**
 * @brief 古文模型类
 * 
 * 存储古文的信息，包括标题、作者、朝代、内容和10维难度向量
 * 
 * 特征维度（与论文Table 3一致）：
 * d1/f1: avg_sentence_length (平均句长)
 * d2/f3: sentence_count (句子数)
 * d3/f5: function_word_ratio (虚词比例)
 * d4/f6: avg_char_log_freq (平均字符对数频率)
 * d5/f8: tongjiazi_density (通假字密度)
 * d6/f9: ppl_ancient (古文困惑度)
 * d7/f10: ppl_modern (现代文困惑度)
 * d8/f11: mattr (词汇多样性)
 * d9/f12: allusion_density (典故密度)
 * d10/f13: semantic_complexity (语义复杂度)
 * 
 * 排除：f2(字数)、f4(总词数)、f7(生僻字密度)
 */
class Text {
public:
    Text();
    
    void setId(int id);
    int getId() const;
    
    void setTitle(const std::string& title);
    std::string getTitle() const;
    
    void setAuthor(const std::string& author);
    std::string getAuthor() const;
    
    void setDynasty(const std::string& dynasty);
    std::string getDynasty() const;
    
    void setContent(const std::string& content);
    std::string getContent() const;
    
    /**
     * @brief 统一接口：通过索引访问难度值 (0-9 对应 d1-d10)
     * @param index 维度索引 (0-9)
     * @return 该维度的难度值
     * @note 与 User::getAbility 对应，保持 API 一致性
     */
    double getDifficulty(int index) const;
    void setDifficulty(int index, double value);
    
    // ============================================
    // 维度便捷接口 (Dimension Convenience API)
    // ============================================
    // 设计说明：
    // 虽然存在统一接口 getDifficulty/setDifficulty，但保留这些命名
    // getter/setter 是有意的，原因如下：
    // 1. 类型安全：避免数组越界风险
    // 2. 可读性：调用方代码更清晰 (如 text.getF1AvgSentenceLength())
    // 3. IDE 支持：自动补全和类型提示更友好
    // 4. 兼容性：不破坏现有调用代码
    // ============================================
    
    // d1: 平均句长
    void setF1AvgSentenceLength(double v);
    double getF1AvgSentenceLength() const;
    
    // d2: 句子数
    void setF3SentenceCount(double v);
    double getF3SentenceCount() const;
    
    // d3: 虚词比例
    void setF5FunctionWordRatio(double v);
    double getF5FunctionWordRatio() const;
    
    // d4: 字平均对数频次
    void setF6AvgCharLogFreq(double v);
    double getF6AvgCharLogFreq() const;
    
    // d5: 通假字密度
    void setF8TongjiaziDensity(double v);
    double getF8TongjiaziDensity() const;
    
    // d6: 古汉语困惑度
    void setF9PplAncient(double v);
    double getF9PplAncient() const;
    
    // d7: 今汉语困惑度
    void setF10PplModern(double v);
    double getF10PplModern() const;
    
    // d8: MATTR词汇多样性
    void setF11Mattr(double v);
    double getF11Mattr() const;
    
    // d9: 典故密度
    void setF12AllusionDensity(double v);
    double getF12AllusionDensity() const;
    
    // d10: 语义复杂度
    void setF13SemanticComplexity(double v);
    double getF13SemanticComplexity() const;
    
private:
    int id;
    std::string title;
    std::string author;
    std::string dynasty;
    std::string content;
    
    // 10维特征
    double f1AvgSentenceLength;    // d1
    double f3SentenceCount;        // d2
    double f5FunctionWordRatio;    // d3
    double f6AvgCharLogFreq;       // d4
    double f8TongjiaziDensity;     // d5
    double f9PplAncient;           // d6
    double f10PplModern;           // d7
    double f11Mattr;               // d8
    double f12AllusionDensity;     // d9
    double f13SemanticComplexity;  // d10
};

#endif