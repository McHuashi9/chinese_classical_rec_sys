#include "database/TextRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <unordered_map>
#include <functional>

TextRepository::TextRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool TextRepository::initTable() {
    // 10维特征表结构（与论文Table 3一致）
    const char* sql = 
        "CREATE TABLE IF NOT EXISTS classical_text ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "title TEXT, "
        "author TEXT, "
        "dynasty TEXT, "
        "content TEXT NOT NULL, "
        "f1_avg_sentence_length REAL DEFAULT 0.0, "
        "f3_sentence_count REAL DEFAULT 0.0, "
        "f5_function_word_ratio REAL DEFAULT 0.0, "
        "f6_avg_char_log_freq REAL DEFAULT 0.0, "
        "f8_tongjiazi_density REAL DEFAULT 0.0, "
        "f9_ppl_ancient REAL DEFAULT 0.0, "
        "f10_ppl_modern REAL DEFAULT 0.0, "
        "f11_mattr REAL DEFAULT 0.0, "
        "f12_allusion_density REAL DEFAULT 0.0, "
        "f13_semantic_complexity REAL DEFAULT 0.0"
        ");";
    
    if (!db->executeSQL(sql)) {
        return false;
    }
    
    return true;
}

static void populateTextFromRow(Text& text, int argc, char** argv, char** azColName) {
    // 字段映射表：列名 -> setter函数
    static const std::unordered_map<std::string, std::function<void(Text*, const char*)>> fieldMap = {
        {"id", [](Text* t, const char* v) { t->setId(std::atoi(v)); }},
        {"title", [](Text* t, const char* v) { t->setTitle(v); }},
        {"author", [](Text* t, const char* v) { t->setAuthor(v); }},
        {"dynasty", [](Text* t, const char* v) { t->setDynasty(v); }},
        {"content", [](Text* t, const char* v) { t->setContent(v); }},
        {"f1_avg_sentence_length", [](Text* t, const char* v) { t->setF1AvgSentenceLength(std::atof(v)); }},
        {"f3_sentence_count", [](Text* t, const char* v) { t->setF3SentenceCount(std::atof(v)); }},
        {"f5_function_word_ratio", [](Text* t, const char* v) { t->setF5FunctionWordRatio(std::atof(v)); }},
        {"f6_avg_char_log_freq", [](Text* t, const char* v) { t->setF6AvgCharLogFreq(std::atof(v)); }},
        {"f8_tongjiazi_density", [](Text* t, const char* v) { t->setF8TongjiaziDensity(std::atof(v)); }},
        {"f9_ppl_ancient", [](Text* t, const char* v) { t->setF9PplAncient(std::atof(v)); }},
        {"f10_ppl_modern", [](Text* t, const char* v) { t->setF10PplModern(std::atof(v)); }},
        {"f11_mattr", [](Text* t, const char* v) { t->setF11Mattr(std::atof(v)); }},
        {"f12_allusion_density", [](Text* t, const char* v) { t->setF12AllusionDensity(std::atof(v)); }},
        {"f13_semantic_complexity", [](Text* t, const char* v) { t->setF13SemanticComplexity(std::atof(v)); }}
    };
    
    for (int i = 0; i < argc; i++) {
        if (argv[i]) {
            auto it = fieldMap.find(azColName[i]);
            if (it != fieldMap.end()) {
                it->second(&text, argv[i]);
            }
        }
    }
}

static int textCallback(void* data, int argc, char** argv, char** azColName) {
    Text* text = static_cast<Text*>(data);
    populateTextFromRow(*text, argc, argv, azColName);
    return 0;
}

static int textsCallback(void* data, int argc, char** argv, char** azColName) {
    std::vector<Text>* texts = static_cast<std::vector<Text>*>(data);
    Text text;
    populateTextFromRow(text, argc, argv, azColName);
    texts->push_back(text);
    return 0;
}

bool TextRepository::getTextById(int id, Text& text) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    // 10维特征查询
    const char* sql = 
        "SELECT id, title, author, dynasty, content, "
        "f1_avg_sentence_length, f3_sentence_count, "
        "f5_function_word_ratio, f6_avg_char_log_freq, "
        "f8_tongjiazi_density, f9_ppl_ancient, f10_ppl_modern, "
        "f11_mattr, f12_allusion_density, f13_semantic_complexity "
        "FROM classical_text WHERE id = ?;";
    
    std::vector<double> params = {static_cast<double>(id)};
    
    if (!db->executeQuery(sql, std::vector<std::string>(), params, textCallback, &text)) {
        LOG_ERROR("查询古文失败: {}", db->getLastError());
        return false;
    }
    
    return text.getId() != 0;
}

std::vector<Text> TextRepository::getAllTexts() {
    std::vector<Text> texts;
    
    if (!db || !db->getConnection()) {
        return texts;
    }
    
    // 10维特征查询
    const char* sql = 
        "SELECT id, title, author, dynasty, content, "
        "f1_avg_sentence_length, f3_sentence_count, "
        "f5_function_word_ratio, f6_avg_char_log_freq, "
        "f8_tongjiazi_density, f9_ppl_ancient, f10_ppl_modern, "
        "f11_mattr, f12_allusion_density, f13_semantic_complexity "
        "FROM classical_text ORDER BY id;";
    
    if (!db->executeQuery(sql, std::vector<std::string>(), std::vector<double>(), textsCallback, &texts)) {
        LOG_ERROR("查询古文列表失败: {}", db->getLastError());
    }
    
    return texts;
}

bool TextRepository::saveText(const Text& text) {
    std::vector<std::string> textParams = {
        text.getTitle(),
        text.getAuthor(),
        text.getDynasty(),
        text.getContent()
    };
    
    // 10维特征参数
    std::vector<double> realParams = {
        text.getF1AvgSentenceLength(), text.getF3SentenceCount(),
        text.getF5FunctionWordRatio(), text.getF6AvgCharLogFreq(),
        text.getF8TongjiaziDensity(), text.getF9PplAncient(),
        text.getF10PplModern(), text.getF11Mattr(),
        text.getF12AllusionDensity(), text.getF13SemanticComplexity()
    };
    
    return db->executeSQL(
        "INSERT INTO classical_text (title, author, dynasty, content, "
        "f1_avg_sentence_length, f3_sentence_count, "
        "f5_function_word_ratio, f6_avg_char_log_freq, "
        "f8_tongjiazi_density, f9_ppl_ancient, f10_ppl_modern, "
        "f11_mattr, f12_allusion_density, f13_semantic_complexity) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
        textParams,
        realParams
    );
}

bool TextRepository::updateText(const Text& text) {
    std::vector<std::string> textParams = {
        text.getTitle(),
        text.getAuthor(),
        text.getDynasty(),
        text.getContent()
    };
    
    // 10维特征参数 + id
    std::vector<double> realParams = {
        text.getF1AvgSentenceLength(), text.getF3SentenceCount(),
        text.getF5FunctionWordRatio(), text.getF6AvgCharLogFreq(),
        text.getF8TongjiaziDensity(), text.getF9PplAncient(),
        text.getF10PplModern(), text.getF11Mattr(),
        text.getF12AllusionDensity(), text.getF13SemanticComplexity(),
        static_cast<double>(text.getId())
    };
    
    return db->executeSQL(
        "UPDATE classical_text SET "
        "title = ?, author = ?, dynasty = ?, content = ?, "
        "f1_avg_sentence_length = ?, f3_sentence_count = ?, "
        "f5_function_word_ratio = ?, f6_avg_char_log_freq = ?, "
        "f8_tongjiazi_density = ?, f9_ppl_ancient = ?, f10_ppl_modern = ?, "
        "f11_mattr = ?, f12_allusion_density = ?, f13_semantic_complexity = ? "
        "WHERE id = ?;",
        textParams,
        realParams
    );
}

bool TextRepository::deleteText(int id) {
    std::vector<double> params = {static_cast<double>(id)};
    return db->executeSQL(
        "DELETE FROM classical_text WHERE id = ?;",
        params
    );
}

bool TextRepository::isEmpty() {
    return getCount() == 0;
}

int TextRepository::getCount() {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM classical_text;";
    char* errMsg = nullptr;
    int count = 0;
    
    auto callback = [](void* data, int argc, char** argv, char** azColName) -> int {
        int* cnt = static_cast<int*>(data);
        if (argc > 0 && argv[0]) {
            *cnt = std::atoi(argv[0]);
        }
        return 0;
    };
    
    int rc = sqlite3_exec(db->getConnection(), sql, callback, &count, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询古文数量失败: {}", errMsg);
        sqlite3_free(errMsg);
        return 0;
    }
    
    return count;
}

std::vector<Text> TextRepository::getTextsByIdRange(int startId, int endId) {
    std::vector<Text> texts;
    
    if (!db || !db->getConnection()) {
        return texts;
    }
    
    // 10维特征查询
    const char* sql = 
        "SELECT id, title, author, dynasty, content, "
        "f1_avg_sentence_length, f3_sentence_count, "
        "f5_function_word_ratio, f6_avg_char_log_freq, "
        "f8_tongjiazi_density, f9_ppl_ancient, f10_ppl_modern, "
        "f11_mattr, f12_allusion_density, f13_semantic_complexity "
        "FROM classical_text WHERE id >= ? AND id <= ? ORDER BY id;";
    
    std::vector<double> params = {static_cast<double>(startId), static_cast<double>(endId)};
    
    if (!db->executeQuery(sql, std::vector<std::string>(), params, textsCallback, &texts)) {
        LOG_ERROR("查询古文区间失败: {}", db->getLastError());
    }
    
    return texts;
}