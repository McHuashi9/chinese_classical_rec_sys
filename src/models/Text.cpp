#include "models/Text.h"

Text::Text() : id(0), title(""), author(""), dynasty(""), content(""),
               f1AvgSentenceLength(0.0), f3SentenceCount(0.0),
               f5FunctionWordRatio(0.0), f6AvgCharLogFreq(0.0),
               f8TongjiaziDensity(0.0), f9PplAncient(0.0),
               f10PplModern(0.0), f11Mattr(0.0), f12AllusionDensity(0.0),
               f13SemanticComplexity(0.0) {}

void Text::setId(int id) {
    this->id = id;
}

int Text::getId() const {
    return id;
}

void Text::setTitle(const std::string& title) {
    this->title = title;
}

std::string Text::getTitle() const {
    return title;
}

void Text::setAuthor(const std::string& author) {
    this->author = author;
}

std::string Text::getAuthor() const {
    return author;
}

void Text::setDynasty(const std::string& dynasty) {
    this->dynasty = dynasty;
}

std::string Text::getDynasty() const {
    return dynasty;
}

void Text::setContent(const std::string& content) {
    this->content = content;
}

std::string Text::getContent() const {
    return content;
}

double Text::getDifficulty(int index) const {
    switch (index) {
        case 0: return f1AvgSentenceLength;   // d1
        case 1: return f3SentenceCount;       // d2
        case 2: return f5FunctionWordRatio;   // d3
        case 3: return f6AvgCharLogFreq;      // d4
        case 4: return f8TongjiaziDensity;    // d5
        case 5: return f9PplAncient;          // d6
        case 6: return f10PplModern;          // d7
        case 7: return f11Mattr;              // d8
        case 8: return f12AllusionDensity;    // d9
        case 9: return f13SemanticComplexity; // d10
        default: return 0.0;
    }
}

void Text::setDifficulty(int index, double value) {
    switch (index) {
        case 0: f1AvgSentenceLength = value;   break; // d1
        case 1: f3SentenceCount = value;       break; // d2
        case 2: f5FunctionWordRatio = value;   break; // d3
        case 3: f6AvgCharLogFreq = value;      break; // d4
        case 4: f8TongjiaziDensity = value;    break; // d5
        case 5: f9PplAncient = value;          break; // d6
        case 6: f10PplModern = value;          break; // d7
        case 7: f11Mattr = value;              break; // d8
        case 8: f12AllusionDensity = value;    break; // d9
        case 9: f13SemanticComplexity = value; break; // d10
        default: break;
    }
}

// d1: 平均句长
void Text::setF1AvgSentenceLength(double v) {
    this->f1AvgSentenceLength = v;
}

double Text::getF1AvgSentenceLength() const {
    return f1AvgSentenceLength;
}

// d2: 句子数
void Text::setF3SentenceCount(double v) {
    this->f3SentenceCount = v;
}

double Text::getF3SentenceCount() const {
    return f3SentenceCount;
}

// d3: 虚词比例
void Text::setF5FunctionWordRatio(double v) {
    this->f5FunctionWordRatio = v;
}

double Text::getF5FunctionWordRatio() const {
    return f5FunctionWordRatio;
}

// d4: 字平均对数频次
void Text::setF6AvgCharLogFreq(double v) {
    this->f6AvgCharLogFreq = v;
}

double Text::getF6AvgCharLogFreq() const {
    return f6AvgCharLogFreq;
}

// d5: 通假字密度
void Text::setF8TongjiaziDensity(double v) {
    this->f8TongjiaziDensity = v;
}

double Text::getF8TongjiaziDensity() const {
    return f8TongjiaziDensity;
}

// d6: 古汉语困惑度
void Text::setF9PplAncient(double v) {
    this->f9PplAncient = v;
}

double Text::getF9PplAncient() const {
    return f9PplAncient;
}

// d7: 今汉语困惑度
void Text::setF10PplModern(double v) {
    this->f10PplModern = v;
}

double Text::getF10PplModern() const {
    return f10PplModern;
}

// d8: MATTR词汇多样性
void Text::setF11Mattr(double v) {
    this->f11Mattr = v;
}

double Text::getF11Mattr() const {
    return f11Mattr;
}

// d9: 典故密度
void Text::setF12AllusionDensity(double v) {
    this->f12AllusionDensity = v;
}

double Text::getF12AllusionDensity() const {
    return f12AllusionDensity;
}

// d10: 语义复杂度
void Text::setF13SemanticComplexity(double v) {
    this->f13SemanticComplexity = v;
}

double Text::getF13SemanticComplexity() const {
    return f13SemanticComplexity;
}