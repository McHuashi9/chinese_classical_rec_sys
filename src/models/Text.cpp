#include "models/Text.h"

Text::Text() : id(0), title(""), author(""), dynasty(""), content(""),
               charCount(0),
               f1AvgSentenceLength(0.0), f3SentenceCount(0.0),
               f5FunctionWordRatio(0.0), f6AvgCharLogFreq(0.0),
               f8TongjiaziDensity(0.0), f9PplAncient(0.0),
               f10PplModern(0.0), f11Mattr(0.0), f12AllusionDensity(0.0),
               f13SemanticComplexity(0.0) {}

void Text::setId(int newId) {
    this->id = newId;
}

int Text::getId() const {
    return id;
}

void Text::setTitle(const std::string& newTitle) {
    this->title = newTitle;
}

std::string Text::getTitle() const {
    return title;
}

void Text::setAuthor(const std::string& newAuthor) {
    this->author = newAuthor;
}

std::string Text::getAuthor() const {
    return author;
}

void Text::setDynasty(const std::string& newDynasty) {
    this->dynasty = newDynasty;
}

std::string Text::getDynasty() const {
    return dynasty;
}

void Text::setContent(const std::string& newContent) {
    this->content = newContent;
}

std::string Text::getContent() const {
    return content;
}

void Text::setBackground(const std::string& bg) {
    this->background = bg;
}

std::string Text::getBackground() const {
    return background;
}

void Text::setSource(const std::string& s) {
    this->source = s;
}

std::string Text::getSource() const {
    return source;
}

void Text::setCharCount(int count) {
    this->charCount = count;
}

int Text::getCharCount() const {
    return charCount;
}

double Text::getDifficulty(int index) const {
    switch (index) {
        case 0: return f1AvgSentenceLength;
        case 1: return f3SentenceCount;
        case 2: return f5FunctionWordRatio;
        case 3: return f6AvgCharLogFreq;
        case 4: return f8TongjiaziDensity;
        case 5: return f9PplAncient;
        case 6: return f10PplModern;
        case 7: return f11Mattr;
        case 8: return f12AllusionDensity;
        case 9: return f13SemanticComplexity;
        default: return 0.0;
    }
}

void Text::setDifficulty(int index, double value) {
    switch (index) {
        case 0: f1AvgSentenceLength = value;   break;
        case 1: f3SentenceCount = value;       break;
        case 2: f5FunctionWordRatio = value;   break;
        case 3: f6AvgCharLogFreq = value;      break;
        case 4: f8TongjiaziDensity = value;    break;
        case 5: f9PplAncient = value;          break;
        case 6: f10PplModern = value;          break;
        case 7: f11Mattr = value;              break;
        case 8: f12AllusionDensity = value;    break;
        case 9: f13SemanticComplexity = value; break;
        default: break;
    }
}

