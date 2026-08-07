#include "c_types.h"
#include "export.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "models/User.h"
#include "models/Text.h"
#include "utils/Logger.h"

#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <vector>
#include <unordered_map>
#include <algorithm>

static struct {
    std::unique_ptr<DatabaseManager> db;
    std::unique_ptr<UserRepository> userRepo;
    std::unique_ptr<TextRepository> textRepo;
    std::unique_ptr<ReadingHistoryRepository> historyRepo;
    std::unique_ptr<LearningIncrementRepository> incrementRepo;
    std::unique_ptr<RecommendationEngine> engine;
    std::unique_ptr<KnowledgeTracker> tracker;
    std::unique_ptr<User> user;
    std::unique_ptr<std::vector<Text>> texts;
    std::unique_ptr<std::unordered_map<int, size_t>> textIndex;
    bool initialized = false;
} g_state;
static std::mutex g_mtx;

// ─── helpers ───────────────────────────────────────────────────────────────────

static void user_to_c(const User& src, UserData* dst)
{
    for (int i = 0; i < 10; i++) {
        dst->abilities[i] = src.getAbility(i);
        dst->base_abilities[i] = src.getBaseAbility(i);
    }
    dst->last_read_time = static_cast<int64_t>(src.getLastReadTime());
}

static void c_to_user(const UserData* src, User& dst)
{
    for (int i = 0; i < 10; i++) {
        dst.setAbility(i, src->abilities[i]);
        dst.setBaseAbility(i, src->base_abilities[i]);
    }
    dst.setLastReadTime(static_cast<time_t>(src->last_read_time));
}

// ─── lifecycle ─────────────────────────────────────────────────────────────────

// 全部生命周期共享的初始化逻辑：打开库 → 建表（幂等）→ 载入文本/用户 → 应用遗忘。
// 返回 BRIDGE_OK 或错误码。调用方负责持有 g_mtx 与日志目录初始化。
static int openDatabase(const char* db_path)
{
    g_state = {};

    g_state.db = std::make_unique<DatabaseManager>();
    if (!g_state.db->open(db_path)) {
        LOG_ERROR("bridge: db_open 失败: {}", g_state.db->getLastError());
        g_state.db.reset();
        return BRIDGE_ERR_GENERIC;
    }

    g_state.userRepo = std::make_unique<UserRepository>(g_state.db.get());
    g_state.textRepo = std::make_unique<TextRepository>(g_state.db.get());
    g_state.historyRepo = std::make_unique<ReadingHistoryRepository>(g_state.db.get());
    g_state.incrementRepo = std::make_unique<LearningIncrementRepository>(g_state.db.get());

    // 四张表幂等建全；缺表时启用（防止远端/发布物缺表导致静默失败）
    if (!g_state.userRepo->initTable() || !g_state.textRepo->initTable() ||
        !g_state.historyRepo->initTable() || !g_state.incrementRepo->initTable()) {
        LOG_ERROR("bridge: 表初始化失败");
        g_state = {};
        return BRIDGE_ERR_INIT;
    }

    g_state.engine = std::make_unique<RecommendationEngine>();
    g_state.user = std::make_unique<User>();
    g_state.texts = std::make_unique<std::vector<Text>>(g_state.textRepo->getAllTexts());

    // 构建 O(1) 文本索引 (id → vector 下标)
    g_state.textIndex = std::make_unique<std::unordered_map<int, size_t>>();
    for (size_t i = 0; i < g_state.texts->size(); i++) {
        (*g_state.textIndex)[(*g_state.texts)[i].getId()] = i;
    }

    g_state.tracker = std::make_unique<KnowledgeTracker>(g_state.incrementRepo.get());

    // 加载用户或初始化默认
    if (g_state.userRepo->getUser(*g_state.user)) {
        if (g_state.user->getAverageAbility() <= 0.001) {
            g_state.user->initializeDefault();
        }
    } else {
        g_state.user->initializeDefault();
    }
    g_state.tracker->applyForgettingEffect(*g_state.user, time(nullptr));
    g_state.userRepo->saveUser(*g_state.user);

    g_state.initialized = true;
    LOG_INFO("bridge: 数据库已打开 — {} 篇文本已加载", g_state.texts->size());
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int db_open(const char* db_path)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    // 日志目录跟随 DB 所在目录（App 数据目录），避免随 cwd 漂移
    const std::filesystem::path dbDir = std::filesystem::path(db_path).parent_path();
    Logger::getInstance().init((dbDir / "logs").string());
    LOG_INFO("bridge: 日志系统已初始化, 输出到 logs/app.log");

    return openDatabase(db_path);
}

extern "C" CHINESE_CORE_EXPORT void db_close()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    g_state = {};
    LOG_INFO("bridge: db_close 完成");
}

// ─── db_replace（整库替换 + 用户数据合并） ─────────────────────────────────────

namespace {

struct ExportedTable {
    std::string name;
    std::vector<std::string> columns;  // 白名单 ∩ 源库实际列（保持白名单顺序）
    std::vector<std::vector<std::optional<std::string>>> rows;  // 值按列对齐；null = SQL NULL
};

// 需要跨替换保留的用户数据表及其列白名单（未来 schema 漂移：未知列忽略、缺列取默认）
const std::unordered_map<std::string, std::vector<std::string>> kUserTableColumns = {
    {"user", {"id",
              "d1_ability", "d2_ability", "d3_ability", "d4_ability", "d5_ability",
              "d6_ability", "d7_ability", "d8_ability", "d9_ability", "d10_ability",
              "d1_base_ability", "d2_base_ability", "d3_base_ability", "d4_base_ability",
              "d5_base_ability", "d6_base_ability", "d7_base_ability", "d8_base_ability",
              "d9_base_ability", "d10_base_ability", "last_read_time"}},
    {"reading_history", {"id", "user_id", "text_id", "read_time", "read_timestamp"}},
    {"text_tracking", {"text_id", "tracked_at"}},
    {"learning_increments", {"id", "user_id", "dimension", "delta", "timestamp", "type"}},
};

static bool sqliteExec(sqlite3* db, const char* sql)
{
    char* err = nullptr;
    if (sqlite3_exec(db, sql, nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("db_replace: SQL 失败: {} — {}", sql, err ? err : "unknown");
        sqlite3_free(err);
        return false;
    }
    return true;
}

static bool tableExists(sqlite3* db, const std::string& table)
{
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, table.c_str(), -1, SQLITE_TRANSIENT);
    bool exists = (sqlite3_step(stmt) == SQLITE_ROW);
    sqlite3_finalize(stmt);
    return exists;
}

static std::set<std::string> tableColumns(sqlite3* db, const std::string& table)
{
    std::set<std::string> cols;
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, ("PRAGMA table_info(" + table + ")").c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        return cols;
    }
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const char* name = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
        if (name) cols.insert(name);
    }
    sqlite3_finalize(stmt);
    return cols;
}

// 从已打开的源库导出用户数据表（列名白名单容错）
static bool exportUserTables(sqlite3* db, std::vector<ExportedTable>& out)
{
    for (const auto& [table, whitelist] : kUserTableColumns) {
        if (!tableExists(db, table)) {
            LOG_WARN("db_replace: 源库无表 {}，跳过导出", table);
            continue;
        }
        const std::set<std::string> present = tableColumns(db, table);
        std::vector<std::string> cols;
        for (const auto& c : whitelist) {
            if (present.count(c)) cols.push_back(c);
        }
        if (cols.empty()) {
            LOG_WARN("db_replace: 源表 {} 无可用白名单列，跳过导出", table);
            continue;
        }

        std::string select = "SELECT ";
        for (size_t i = 0; i < cols.size(); i++) {
            select += (i ? ", " : "") + cols[i];
        }
        select += " FROM " + table;

        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db, select.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("db_replace: 导出 {} 失败: {}", table, sqlite3_errmsg(db));
            return false;
        }
        ExportedTable t;
        t.name = table;
        t.columns = cols;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            std::vector<std::optional<std::string>> row;
            row.reserve(cols.size());
            for (int i = 0; i < static_cast<int>(cols.size()); i++) {
                const char* v = reinterpret_cast<const char*>(sqlite3_column_text(stmt, i));
                row.push_back(v ? std::optional<std::string>(v) : std::nullopt);
            }
            t.rows.push_back(std::move(row));
        }
        sqlite3_finalize(stmt);
        out.push_back(std::move(t));
        LOG_INFO("db_replace: 导出 {} 共 {} 行 / {} 列", t.name, t.rows.size(), t.columns.size());
    }
    return true;
}

// 导入到已打开的目标库（表幂等存在 + 清空默认 + 逐行按列名插入，事务由调用方包裹）
static bool importUserTables(sqlite3* db, const std::vector<ExportedTable>& tables)
{
    for (const auto& t : tables) {
        if (!tableExists(db, t.name)) {
            LOG_WARN("db_replace: 目标库缺表 {}，跳过导入", t.name);
            continue;
        }
        if (!sqliteExec(db, ("DELETE FROM " + t.name).c_str())) return false;
        if (t.rows.empty()) continue;

        // 只导入源列与目标列都存在的列（缺列取目标默认值），与导出侧的白名单容错对称
        const std::set<std::string> targetCols = tableColumns(db, t.name);
        std::vector<size_t> keepIdx;  // t.columns 中需要保留的列下标
        std::vector<std::string> keepCols;
        for (size_t i = 0; i < t.columns.size(); i++) {
            if (targetCols.count(t.columns[i])) {
                keepIdx.push_back(i);
                keepCols.push_back(t.columns[i]);
            }
        }
        if (keepCols.empty()) {
            LOG_WARN("db_replace: 目标库表 {} 无可导入列，保留目标默认值", t.name);
            continue;
        }

        std::string sql = "INSERT INTO " + t.name + " (";
        for (size_t i = 0; i < keepCols.size(); i++) sql += (i ? ", " : "") + keepCols[i];
        sql += ") VALUES (";
        for (size_t i = 0; i < keepCols.size(); i++) sql += (i ? ", ?" : "?");
        sql += ")";

        sqlite3_stmt* stmt = nullptr;
        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("db_replace: 导入 {} 准备失败: {}", t.name, sqlite3_errmsg(db));
            return false;
        }
        for (const auto& row : t.rows) {
            sqlite3_reset(stmt);
            sqlite3_clear_bindings(stmt);
            for (size_t k = 0; k < keepIdx.size(); k++) {
                const size_t i = keepIdx[k];
                if (i < row.size() && row[i]) {
                    sqlite3_bind_text(stmt, static_cast<int>(k + 1), row[i]->c_str(), -1, SQLITE_TRANSIENT);
                } else {
                    sqlite3_bind_null(stmt, static_cast<int>(k + 1));
                }
            }
            if (sqlite3_step(stmt) != SQLITE_DONE) {
                LOG_ERROR("db_replace: 导入 {} 失败: {}", t.name, sqlite3_errmsg(db));
                sqlite3_finalize(stmt);
                return false;
            }
        }
        sqlite3_finalize(stmt);
    }

    // 自增序列对齐（防止 id 显式导入后 AUTOINCREMENT 复用旧 id）
    for (const char* seqTable : {"reading_history", "learning_increments"}) {
        if (tableExists(db, seqTable)) {
            const std::string upd = "UPDATE sqlite_sequence SET seq = "
                "(SELECT COALESCE(MAX(id),0) FROM " + std::string(seqTable) + ") "
                "WHERE name='" + std::string(seqTable) + "'";
            sqliteExec(db, upd.c_str());  // 失败忽略（无序列条目属正常）
        }
    }
    return true;
}

}  // namespace

// 原子替换：将 cur_db_path 换为 new_db_path 的内容，并跨替换保留用户数据。
// 顺序（崩溃安全）：先在临时文件上完成"打开新库 + 事务导入用户表"，再做文件层替换。
// - 替换前 g_state 已打开：直接从当前连接导出；未打开：只读打开 cur_db_path 导出。
// - 因为导入发生在正式位替换之前，任意时刻崩溃，旧库都保持不动（数据零丢失）；
//   文件层替换是同目录原子 rename（旧库 → .bak 兜底，新库 → 正式位）。
// - 替换完成或失败后 g_state 一律关闭（由调用方重新 db_open）。
extern "C" CHINESE_CORE_EXPORT int db_replace(const char* new_db_path, const char* cur_db_path)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const std::filesystem::path dbDir = std::filesystem::path(cur_db_path).parent_path();
    Logger::getInstance().init((dbDir / "logs").string());

    // 1. 导出用户数据表（源库不动）
    std::vector<ExportedTable> userTables;
    if (g_state.initialized && g_state.db && g_state.db->getConnection()) {
        if (!exportUserTables(g_state.db->getConnection(), userTables)) {
            LOG_ERROR("db_replace: 当前库导出失败，中止替换（引擎保持可用）");
            return BRIDGE_ERR_GENERIC;
        }
    } else {
        sqlite3* old = nullptr;
        const int rc = sqlite3_open_v2(cur_db_path, &old, SQLITE_OPEN_READONLY, nullptr);
        if (rc == SQLITE_OK) {
            if (!exportUserTables(old, userTables)) {
                LOG_ERROR("db_replace: 只读打开导出失败，中止替换");
                sqlite3_close(old);
                return BRIDGE_ERR_GENERIC;
            }
            sqlite3_close(old);
        } else if (rc != SQLITE_CANTOPEN) {
            LOG_ERROR("db_replace: 只读打开 {} 失败 rc={}", cur_db_path, rc);
            return BRIDGE_ERR_GENERIC;
        }
        // SQLITE_CANTOPEN：旧库不存在（全新安装），无用户数据可保留
    }
    LOG_INFO("db_replace: 导出完成（共 {} 张用户表）", userTables.size());

    // 2. 关闭当前库连接
    g_state = {};

    // 3. 在数据文件（tmp，尚未成为正式库）上完成"打开 + 合并"，崩溃时旧库不动
    const int openRc = openDatabase(new_db_path);
    if (openRc != BRIDGE_OK) {
        LOG_ERROR("db_replace: 新库校验/初始化失败 rc={}（旧库未动）", openRc);
        return openRc;
    }
    if (g_state.db) {
        if (!sqliteExec(g_state.db->getConnection(), "BEGIN IMMEDIATE")) {
            g_state = {};
            return BRIDGE_ERR_GENERIC;
        }
        const bool importOk = importUserTables(g_state.db->getConnection(), userTables);
        if (!sqliteExec(g_state.db->getConnection(), importOk ? "COMMIT" : "ROLLBACK")) {
            g_state = {};
            return BRIDGE_ERR_GENERIC;
        }
        if (!importOk) {
            LOG_ERROR("db_replace: 用户表合并失败（旧库未动）");
            g_state = {};
            return BRIDGE_ERR_GENERIC;
        }
    }
    LOG_INFO("db_replace: 数据合并完成（{} 张用户表）", userTables.size());

    // 4. 关闭合并好的 tmp，执行文件层替换：旧库 → .bak；合并库 → 正式位
    g_state = {};
    const std::string curStr(cur_db_path);
    const std::string bakStr = curStr + ".bak";
    std::error_code ec;
    std::filesystem::remove(bakStr, ec);
    if (std::filesystem::exists(curStr)) {
        std::filesystem::rename(curStr, bakStr, ec);
        if (ec) {
            LOG_ERROR("db_replace: 备份旧库到 .bak 失败: {}", ec.message());
            return BRIDGE_ERR_GENERIC;
        }
    }
    std::filesystem::rename(new_db_path, curStr, ec);
    if (ec) {
        LOG_ERROR("db_replace: 移动新库失败: {}", ec.message());
        if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
        return BRIDGE_ERR_GENERIC;
    }
    LOG_INFO("db_replace: 替换完成 — 新库已就位（旧库在 .bak），用户数据已合并");

    // 5. 保证 g_state 关闭，由调用方统一 db_open
    return BRIDGE_OK;
}

// ─── user ──────────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int user_load(UserData* out)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    user_to_c(*g_state.user, out);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int user_save(const UserData* in)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    c_to_user(in, *g_state.user);
    if (g_state.userRepo->saveUser(*g_state.user)) {
        return BRIDGE_OK;
    }
    LOG_ERROR("bridge: user_save 失败");
    return BRIDGE_ERR_GENERIC;
}

extern "C" CHINESE_CORE_EXPORT int user_init_default()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    g_state.user->initializeDefault();
    if (g_state.userRepo->saveUser(*g_state.user)) {
        return BRIDGE_OK;
    }
    return BRIDGE_ERR_GENERIC;
}

// ─── text ──────────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int text_get_count()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    return static_cast<int>(g_state.texts->size());
}

extern "C" CHINESE_CORE_EXPORT void text_get_all(TextInfo* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !out) return;
    int n = std::min(max_count, static_cast<int>(g_state.texts->size()));
    for (int i = 0; i < n; i++) {
        const auto& t = (*g_state.texts)[i];
        out[i].id = t.getId();
        std::strncpy(out[i].title, t.getTitle().c_str(), 255);
        out[i].title[255] = '\0';
        std::strncpy(out[i].author, t.getAuthor().c_str(), 127);
        out[i].author[127] = '\0';
        std::strncpy(out[i].dynasty, t.getDynasty().c_str(), 63);
        out[i].dynasty[63] = '\0';
        std::strncpy(out[i].source, t.getSource().c_str(), 63);
        out[i].source[63] = '\0';
    }
}

extern "C" CHINESE_CORE_EXPORT int text_get_detail(int id, TextDetail* out)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out) return BRIDGE_ERR_GENERIC;

    auto it = g_state.textIndex->find(id);
    if (it == g_state.textIndex->end()) {
        return BRIDGE_ERR_TEXT;
    }

    const auto& text = (*g_state.texts)[it->second];
    out->id = text.getId();
    std::strncpy(out->title, text.getTitle().c_str(), 255);
    out->title[255] = '\0';
    std::strncpy(out->author, text.getAuthor().c_str(), 127);
    out->author[127] = '\0';
    std::strncpy(out->dynasty, text.getDynasty().c_str(), 63);
    out->dynasty[63] = '\0';
    std::strncpy(out->source, text.getSource().c_str(), 63);
    out->source[63] = '\0';
    std::strncpy(out->background, text.getBackground().c_str(), 2047);
    out->background[2047] = '\0';
    if (text.getContent().size() > 65535) {
        LOG_WARN("bridge: text_id={} 内容截断 ({} > 65535 字节)", id, text.getContent().size());
    }
    std::strncpy(out->content, text.getContent().c_str(), 65535);
    out->content[65535] = '\0';
    out->char_count = text.getCharCount();
    for (int i = 0; i < 10; i++) {
        out->difficulties[i] = text.getDifficulty(i);
    }
    return BRIDGE_OK;
}

// ─── annotations ──────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int text_get_annotations(int id, char* out, int max_len)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_len <= 0) return BRIDGE_ERR_GENERIC;

    sqlite3* db = g_state.db->getConnection();
    if (!db) return BRIDGE_ERR_GENERIC;

    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT annotations_raw FROM classical_text WHERE id = ?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: text_get_annotations 准备失败: {}", sqlite3_errmsg(db));
        return BRIDGE_ERR_GENERIC;
    }

    sqlite3_bind_int(stmt, 1, id);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const char* text = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        int len = text ? static_cast<int>(strlen(text)) : 0;
        if (len >= max_len) {
            LOG_WARN("bridge: text_id={} annotations_raw 截断 ({} > {} 字节)", id, len, max_len - 1);
            len = max_len - 1;
        }
        if (text && len > 0) {
            std::strncpy(out, text, len);
            out[len] = '\0';
        } else {
            out[0] = '\0';
        }
    } else {
        out[0] = '\0';
        sqlite3_finalize(stmt);
        return BRIDGE_ERR_TEXT;
    }

    sqlite3_finalize(stmt);
    return BRIDGE_OK;
}

// ─── recommend ─────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int recommend(const UserData* user, int top_k,
                           int* out_ids, double* out_probs,
                           int out_ids_capacity, int out_probs_capacity)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!user || !out_ids || !out_probs) return BRIDGE_ERR_GENERIC;

    User cpp_user;
    c_to_user(user, cpp_user);

    auto results = g_state.engine->recommend(cpp_user, *g_state.texts, top_k);

    size_t n = results.size();
    if (static_cast<int>(n) > out_ids_capacity) n = out_ids_capacity;
    if (static_cast<int>(n) > out_probs_capacity) n = out_probs_capacity;
    for (size_t i = 0; i < n; i++) {
        out_ids[i] = results[i].first;
        out_probs[i] = results[i].second;
    }
    LOG_INFO("bridge: 推荐完成 — 返回 {} 篇 (top_k={})", results.size(), top_k);
    return BRIDGE_OK;
}

// ─── knowledge tracker ─────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int tracker_apply_read(const UserData* user, int text_id,
                                   double read_time, int64_t timestamp,
                                   UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    auto it = g_state.textIndex->find(text_id);
    if (it == g_state.textIndex->end()) return BRIDGE_ERR_TEXT;

    User cpp_user;
    c_to_user(user, cpp_user);

    time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);
    g_state.tracker->applyReadEffect(cpp_user, (*g_state.texts)[it->second], read_time,
                                     effective_ts);
    user_to_c(cpp_user, out_user);

    g_state.historyRepo->markAsTracked(text_id);
    g_state.historyRepo->addRecord(text_id, read_time, effective_ts);
    LOG_INFO("bridge: 知识追踪完成 — text_id={}, read_time={:.1f}s, avg_ability={:.3f}→{:.3f}",
             text_id, read_time, g_state.user->getAverageAbility(), cpp_user.getAverageAbility());

    // 持久化
    g_state.userRepo->saveUser(cpp_user);
    g_state.user = std::make_unique<User>(cpp_user);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int tracker_apply_forgetting(const UserData* user, int64_t now,
                                         UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->applyForgettingEffect(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int tracker_prune(const UserData* user, int64_t now, UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->pruneOldIncrements(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);

    // 持久化修剪后的状态
    g_state.userRepo->saveUser(cpp_user);
    g_state.user = std::make_unique<User>(cpp_user);
    return BRIDGE_OK;
}

// ─── history ──────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int history_add_record(int text_id, double read_time, int64_t timestamp)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    bool ok = g_state.historyRepo->addRecord(text_id, read_time, static_cast<time_t>(timestamp));
    if (ok) {
        LOG_INFO("bridge: history_add_record text_id={} read_time={:.1f}s", text_id, read_time);
    }
    return ok ? BRIDGE_OK : BRIDGE_ERR_GENERIC;
}

extern "C" CHINESE_CORE_EXPORT int history_get_recent(int limit, ReadingRecordData* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !out) return BRIDGE_ERR_NOT_INIT;

    auto records = g_state.historyRepo->getRecentRecords(limit);
    int n = std::min(static_cast<int>(records.size()), max_count);

    for (int i = 0; i < n; i++) {
        out[i].id = records[i].id;
        out[i].text_id = records[i].textId;
        out[i].read_time = records[i].readTime;
        out[i].timestamp = static_cast<int64_t>(records[i].timestamp);
    }
    return n;
}

extern "C" CHINESE_CORE_EXPORT int history_get_total_count()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return 0;
    return g_state.historyRepo->getTotalReadCount();
}

extern "C" CHINESE_CORE_EXPORT int history_get_tracked_text_ids(int* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !out) return 0;

    auto ids = g_state.historyRepo->getTrackedTextIds();
    int n = std::min(static_cast<int>(ids.size()), max_count);

    for (int i = 0; i < n; i++) {
        out[i] = ids[i];
    }
    return n;
}

// ─── logging ──────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT void log_write(int level, const char* message)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    switch (level) {
        case 0: LOG_DEBUG("{}", message); break;
        case 1: LOG_INFO("{}", message);  break;
        case 2: LOG_WARN("{}", message);  break;
        case 3: LOG_ERROR("{}", message); break;
        default: LOG_INFO("{}", message); break;
    }
}

extern "C" CHINESE_CORE_EXPORT void log_set_level(const char* level)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    Logger::getInstance().setLevel(level);
    LOG_INFO("bridge: 日志级别切换为 {}", level);
}
