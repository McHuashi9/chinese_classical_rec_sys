#include "database/TextRepository.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <unordered_map>
#include <functional>
#include <utility>

#define TEXT_SELECT_COLUMNS \
    "id, title, author, dynasty, background, source, content, char_count, " \
    "f1_avg_sentence_length, f3_sentence_count, " \
    "f5_function_word_ratio, f6_avg_char_log_freq, " \
    "f8_tongjiazi_density, f9_ppl_ancient, f10_ppl_modern, " \
    "f11_mattr, f12_allusion_density, f13_semantic_complexity"

// （saveText/updateText/deleteText/getTextById/getTextsByIdRange 为死代码，
// 已于 08-14 清理，TEXT_INSERT_COLUMNS / TEXT_UPDATE_SET 宏随之移除）

TextRepository::TextRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool TextRepository::initTable() {
    // 10维特征表结构（与论文Table 3一致）
    const char* sql = 
        "CREATE TABLE IF NOT EXISTS classical_text ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "title TEXT, "
        "author TEXT, "
        "dynasty TEXT, "
        "background TEXT DEFAULT '', "
        "source TEXT DEFAULT '', "
        "content TEXT NOT NULL, "
        "char_count INTEGER DEFAULT 0, "
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

static void populateTextFromRow(const Row& row, Text& text) {
    // 字段映射表：列名 -> setter函数（收敛自原 sqlite3_exec C 回调，去掉了 const_cast 的来源）
    static const std::unordered_map<std::string, std::function<void(Text*, const Row&)>> fieldMap = {
        {"id", [](Text* t, const Row& r) { t->setId(static_cast<int>(r.integer("id"))); }},
        {"title", [](Text* t, const Row& r) { t->setTitle(r.text("title")); }},
        {"author", [](Text* t, const Row& r) { t->setAuthor(r.text("author")); }},
        {"dynasty", [](Text* t, const Row& r) { t->setDynasty(r.text("dynasty")); }},
        {"background", [](Text* t, const Row& r) { t->setBackground(r.text("background")); }},
        {"source", [](Text* t, const Row& r) { t->setSource(r.text("source")); }},
        {"content", [](Text* t, const Row& r) { t->setContent(r.text("content")); }},
        {"char_count", [](Text* t, const Row& r) { t->setCharCount(static_cast<int>(r.integer("char_count"))); }},
        {"f1_avg_sentence_length", [](Text* t, const Row& r) { t->setDifficulty(0, r.real("f1_avg_sentence_length")); }},
        {"f3_sentence_count", [](Text* t, const Row& r) { t->setDifficulty(1, r.real("f3_sentence_count")); }},
        {"f5_function_word_ratio", [](Text* t, const Row& r) { t->setDifficulty(2, r.real("f5_function_word_ratio")); }},
        {"f6_avg_char_log_freq", [](Text* t, const Row& r) { t->setDifficulty(3, r.real("f6_avg_char_log_freq")); }},
        {"f8_tongjiazi_density", [](Text* t, const Row& r) { t->setDifficulty(4, r.real("f8_tongjiazi_density")); }},
        {"f9_ppl_ancient", [](Text* t, const Row& r) { t->setDifficulty(5, r.real("f9_ppl_ancient")); }},
        {"f10_ppl_modern", [](Text* t, const Row& r) { t->setDifficulty(6, r.real("f10_ppl_modern")); }},
        {"f11_mattr", [](Text* t, const Row& r) { t->setDifficulty(7, r.real("f11_mattr")); }},
        {"f12_allusion_density", [](Text* t, const Row& r) { t->setDifficulty(8, r.real("f12_allusion_density")); }},
        {"f13_semantic_complexity", [](Text* t, const Row& r) { t->setDifficulty(9, r.real("f13_semantic_complexity")); }}
    };
    
    for (int i = 0; i < row.columnCount(); ++i) {
        // 旧回调只在 argv[i] != nullptr 时赋值：NULL 列保持模型默认值
        if (row.isNull(i)) continue;
        auto it = fieldMap.find(row.columnName(i));
        if (it != fieldMap.end()) {
            it->second(&text, row);
        }
    }
}

std::vector<Text> TextRepository::getAllTexts() {
    std::vector<Text> texts;
    
    if (!db || !db->getConnection()) {
        return texts;
    }
    
    const char* sql = 
        "SELECT " TEXT_SELECT_COLUMNS " FROM classical_text ORDER BY id;";

    std::vector<Row> rows;
    if (!db->queryRows(sql, rows)) {
        LOG_ERROR("查询古文列表失败: {}", db->getLastError());
        return texts;
    }

    texts.reserve(rows.size());
    for (const Row& row : rows) {
        Text text;
        populateTextFromRow(row, text);
        texts.push_back(std::move(text));
    }

    return texts;
}

bool TextRepository::isEmpty() {
    return getCount() == 0;
}

bool TextRepository::getSingleColumn(int id, const char* column, std::string& out) {
    out.clear();
    if (!db || !db->getConnection()) {
        return false;
    }

    const std::string sql =
        std::string("SELECT ") + column + " FROM classical_text WHERE id = ?";

    std::vector<Row> rows;
    if (!db->queryRows(sql, std::vector<SqlParam>{id}, rows)) {
        LOG_ERROR("查询 classical_text.{} 失败: {}", column, db->getLastError());
        return false;
    }
    if (rows.empty()) {
        return false;  // 无该行（对应原 ROW 未命中 → BRIDGE_ERR_TEXT）
    }
    // NULL 列由 Row::text 返回空串，语义与原实现一致（空串 + BRIDGE_OK）
    out = rows[0].text(column);
    return true;
}

bool TextRepository::getAnnotationsRaw(int id, std::string& out) {
    return getSingleColumn(id, "annotations_raw", out);
}

bool TextRepository::getTranslation(int id, std::string& out) {
    return getSingleColumn(id, "translation", out);
}

int TextRepository::getCount() {
    if (!db || !db->getConnection()) {
        return 0;
    }
    
    const char* sql = "SELECT COUNT(*) FROM classical_text;";
    char* errMsg = nullptr;
    int count = 0;
    
    auto callback = [](void* data, int argc, char** argv, char** azColName) -> int {
        (void)azColName;
        int* cnt = static_cast<int*>(data);
        if (argc > 0 && argv[0]) {
            *cnt = std::atoi(argv[0]);
        }
        return 0;
    };
    
    // 批次 4（明示排除）：裸 sqlite3_exec + C 回调节点；失败且未分配时 errMsg 为 nullptr，
    // 下面的 LOG_ERROR(..., errMsg) 有空指针风险（recon-db-access.md §5.1），本次工作项 1 不动。
    int rc = sqlite3_exec(db->getConnection(), sql, callback, &count, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询古文数量失败: {}", errMsg);
        sqlite3_free(errMsg);
        return 0;
    }
    
    return count;
}

