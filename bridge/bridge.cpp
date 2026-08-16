#include "c_types.h"
#include "export.h"
#include "user_tables.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "database/schema_introspect.h"
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "core/MathUtils.h"
#include "models/User.h"
#include "models/Text.h"
#include "utils/FeatureExtractor.h"
#include "utils/Logger.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <random>
#include <set>
#include <sstream>
#include <vector>
#include <unordered_map>

using dbschema::tableColumns;
using dbschema::tableExists;

static bool execRawSql(sqlite3* db, const char* sql);

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
    int activeUserId = 1;
    bool initialized = false;
} g_state;
static std::mutex g_mtx;

// 取题随机轮换的固定种子（Catch2 可复现；轮换由"排除已答"驱动，种子只保证批次内顺序确定）
static constexpr uint32_t kQuizShuffleSeed = 42;

// C ABI 结构尺寸断言：与 Dart @Packed(1) 布局保持一致（一旦 pack 丢失会静默错位）。
// 7 个结构全覆盖（Dart 侧见 flutter_app/test/engine/c_types_layout_test.dart 的 sizeOf 断言）
static_assert(sizeof(UserData) == 216, "UserData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(TextInfo) == 516, "TextInfo ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(TextDetail) == 68184, "TextDetail ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ReadingRecordData) == 24, "ReadingRecordData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(QuestionData) == 6244, "QuestionData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ReviewItemData) == 24, "ReviewItemData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ProfileData) == 88, "ProfileData ABI 尺寸不符，检查 #pragma pack");

// ─── helpers ───────────────────────────────────────────────────────────────────

static void copyCString(char* dst, size_t dstSize, const unsigned char* src)
{
    if (!src || dstSize == 0) return;
    const size_t len = std::min(dstSize - 1, std::strlen(reinterpret_cast<const char*>(src)));
    std::memcpy(dst, src, len);
    dst[len] = '\0';
}

static void user_to_c(const User& src, UserData* dst)
{
    for (int i = 0; i < 10; i++) {
        dst->abilities[i] = src.getAbility(i);
        dst->base_abilities[i] = src.getBaseAbility(i);
        dst->quiz_counts[i] = src.getQuizCount(i);
    }
    dst->eta = src.getEta();
    dst->last_read_time = static_cast<int64_t>(src.getLastReadTime());
}

static void c_to_user(const UserData* src, User& dst)
{
    for (int i = 0; i < 10; i++) {
        dst.setAbility(i, src->abilities[i]);
        dst.setBaseAbility(i, src->base_abilities[i]);
        dst.setQuizCount(i, src->quiz_counts[i]);
    }
    dst.setEta(src->eta);
    dst.setLastReadTime(static_cast<time_t>(src->last_read_time));
}

// 载入指定档案为当前用户：读 user 行 → 缺行/空行初始化默认 → 应用遗忘 → 落库 → 更新内存态。
// 注意：不能用平均能力≈0 判断"空行"——真实差生能力可因负增量累积到全 0，必须保留。
// 调用方负责持有 g_mtx。
static bool loadUserForActive(int userId)
{
    if (!g_state.initialized || !g_state.userRepo || !g_state.tracker) return false;

    User loaded;
    if (g_state.userRepo->getUser(loaded, userId)) {
        if (!loaded.hasAnyNonDefaultField()) {
            loaded.initializeDefault();
        }
    } else {
        loaded.initializeDefault();
    }

    g_state.tracker->setUserId(userId);
    g_state.tracker->applyForgettingEffect(loaded, time(nullptr));

    if (!g_state.userRepo->saveUser(loaded, userId)) {
        LOG_ERROR("bridge: 档案 {} 切换落库失败", userId);
        return false;
    }
    g_state.userRepo->touchProfile(userId);
    g_state.user = std::make_unique<User>(loaded);
    g_state.activeUserId = userId;
    LOG_INFO("bridge: 当前档案切换为 id={}", userId);
    return true;
}

// 强制初始化闸门：未初始化时返回 BRIDGE_ERR_INIT_INCOMPLETE（调用方负责持锁）
static int requireInitialized()
{
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!g_state.userRepo || !g_state.userRepo->isInitialized(g_state.activeUserId)) {
        return BRIDGE_ERR_INIT_INCOMPLETE;
    }
    return BRIDGE_OK;
}

// ─── lifecycle ─────────────────────────────────────────────────────────────────

namespace {

// 读取指定 schema 的 user_version（schema 为空 = 主库，否则如 "content"）
int pragmaUserVersion(sqlite3* db, const std::string& schema = "")
{
    if (!db) return -1;
    const std::string sql = schema.empty()
        ? "PRAGMA user_version;"
        : "PRAGMA \"" + schema + "\".user_version;";
    sqlite3_stmt* stmt = nullptr;
    int version = -1;
    if (sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        return -1;
    }
    const int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    } else if (rc != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        return -1;
    }
    sqlite3_finalize(stmt);
    return version;
}

// 校验已连接的纯内容库（schema 为空=直接连接，否则如 "content"）。
// 返回 BRIDGE_OK / BRIDGE_ERR_DB_CONTENT / BRIDGE_ERR_DB_VERSION。
int validateContentConnection(sqlite3* db, const std::string& schema = "")
{
    if (!db) return BRIDGE_ERR_DB_CONTENT;
    const int contentVersion = pragmaUserVersion(db, schema);
    if (contentVersion == -1) {
        LOG_ERROR("bridge: 内容库无法读取 db_version（损坏或非 SQLite）");
        return BRIDGE_ERR_DB_CONTENT;
    }
    if (contentVersion != 1) {
        LOG_ERROR("bridge: 内容库 db_version 必须为 1（当前 {}）", contentVersion);
        return BRIDGE_ERR_DB_VERSION;
    }

    const std::string prefix = schema.empty() ? "" : schema + ".";
    const std::string tableSql = "SELECT name FROM " + prefix + "sqlite_master WHERE type='table';";
    sqlite3_stmt* stmt = nullptr;
    std::set<std::string> tables;
    if (sqlite3_prepare_v2(db, tableSql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: 内容库表清单读取失败: {}", sqlite3_errmsg(db));
        return BRIDGE_ERR_DB_CONTENT;
    }
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char* t = sqlite3_column_text(stmt, 0);
        if (t) tables.insert(reinterpret_cast<const char*>(t));
    }
    sqlite3_finalize(stmt);

    // 旧用户表黑名单：内容库出现任何一张即拒绝
    for (const auto& t : kUserTableNames) {
        if (tables.count(t)) {
            LOG_ERROR("bridge: 内容库含旧用户表 {}，拒绝作为纯内容库", t);
            return BRIDGE_ERR_DB_CONTENT;
        }
    }

    if (!tables.count("classical_text") || !tables.count("questions")) {
        LOG_ERROR("bridge: 内容库缺少 classical_text/questions 表");
        return BRIDGE_ERR_DB_CONTENT;
    }

    // 6 个强制初始化 q_key 必须存在（启动期拒绝，避免初始化流程卡死）
    static const char* kInitQKeys[] = {
        "d648b695e1579dbe", "28a1103b477177ee", "6dcbeb434a04bb29",
        "5f465c9792081778", "f6e064465d0da521", "638f4ed6d813d2f8",
    };
    for (const char* qkey : kInitQKeys) {
        const std::string sql = "SELECT 1 FROM " + prefix + "questions WHERE q_key = ? LIMIT 1;";
        sqlite3_stmt* q = nullptr;
        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &q, nullptr) != SQLITE_OK) {
            LOG_ERROR("bridge: 内容库 questions.q_key 校验失败: {}", sqlite3_errmsg(db));
            return BRIDGE_ERR_DB_CONTENT;
        }
        sqlite3_bind_text(q, 1, qkey, -1, SQLITE_TRANSIENT);
        const bool found = (sqlite3_step(q) == SQLITE_ROW);
        sqlite3_finalize(q);
        if (!found) {
            LOG_ERROR("bridge: 内容库缺少初始化 q_key {}", qkey);
            return BRIDGE_ERR_DB_CONTENT;
        }
    }
    return BRIDGE_OK;
}

int validateContentFile(const std::string& path)
{
    if (!std::filesystem::exists(path)) {
        LOG_ERROR("bridge: 内容库文件不存在: {}", path);
        return BRIDGE_ERR_DB_CONTENT;
    }
    DatabaseManager tmp;
    if (!tmp.open(path)) {
        LOG_ERROR("bridge: 内容库打开失败: {}", tmp.getLastError());
        return BRIDGE_ERR_DB_CONTENT;
    }
    const int rc = validateContentConnection(tmp.getConnection());
    tmp.close();
    return rc;
}

bool samePath(const std::string& a, const std::string& b)
{
    std::error_code ec;
    const auto ca = std::filesystem::weakly_canonical(a, ec);
    ec.clear();
    const auto cb = std::filesystem::weakly_canonical(b, ec);
    return ca == cb;
}

}  // namespace

// 全部生命周期共享的初始化逻辑：打开 user.db（主连接）→ 建用户表（幂等）→
// 挂载 content.db → 校验纯内容库 → 载入文本/用户 → 应用遗忘。
// 返回 BRIDGE_OK 或错误码。调用方负责持有 g_mtx 与日志目录初始化。
static int openDatabase(const char* content_path, const char* user_path)
{
    g_state = {};
    if (!content_path || !user_path) return BRIDGE_ERR_GENERIC;
    if (samePath(content_path, user_path)) {
        LOG_ERROR("bridge: user.db 与 classical.db 同路径: {}", content_path);
        return BRIDGE_ERR_DB_SAME_PATH;
    }

    const bool userExisted = std::filesystem::exists(user_path);
    g_state.db = std::make_unique<DatabaseManager>();
    if (!g_state.db->open(user_path)) {
        LOG_ERROR("bridge: user.db 打开失败: {}", g_state.db->getLastError());
        g_state.db.reset();
        return BRIDGE_ERR_DB_USER;
    }

    // 旧开发版 user.db（db_version=0）不做升级，直接拒绝；>1 也拒绝
    if (userExisted && g_state.db->getUserVersion() != 1) {
        LOG_ERROR("bridge: user.db db_version={} 不兼容，仅支持 1", g_state.db->getUserVersion());
        g_state = {};
        return BRIDGE_ERR_DB_VERSION;
    }

    g_state.userRepo = std::make_unique<UserRepository>(g_state.db.get());
    g_state.textRepo = std::make_unique<TextRepository>(g_state.db.get());
    g_state.historyRepo = std::make_unique<ReadingHistoryRepository>(g_state.db.get());
    g_state.incrementRepo = std::make_unique<LearningIncrementRepository>(g_state.db.get());

    // 用户库三张域表幂等建全（内容表属于内容库，不在此初始化）
    if (!g_state.userRepo->initTable() ||
        !g_state.historyRepo->initTable() ||
        !g_state.incrementRepo->initTable()) {
        LOG_ERROR("bridge: 用户表初始化失败");
        g_state = {};
        return BRIDGE_ERR_INIT;
    }

    // 全新用户库建表后写入 db_version=1；已存在且在版本检查通过的保持原值
    if (!userExisted && !g_state.db->setUserVersion(1)) {
        LOG_ERROR("bridge: 写入 user.db db_version 失败");
        g_state = {};
        return BRIDGE_ERR_INIT;
    }

    // 内容库：先独立校验文件，再挂载到主连接
    const int contentRc = validateContentFile(content_path);
    if (contentRc != BRIDGE_OK) {
        g_state = {};
        return contentRc;
    }
    if (!g_state.db->attachDatabase("content", content_path)) {
        LOG_ERROR("bridge: 挂载内容库失败: {}", g_state.db->getLastError());
        g_state = {};
        return BRIDGE_ERR_DB_CONTENT;
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

    // 确保默认档案存在（新库默认档案 initialized=0，进入强制初始化流程）
    g_state.userRepo->ensureProfileExists(1, "默认用户");
    g_state.initialized = true;
    if (!loadUserForActive(1)) {
        LOG_ERROR("bridge: 默认档案加载失败");
        g_state = {};
        return BRIDGE_ERR_INIT;
    }

    LOG_INFO("bridge: 数据库已打开 — {} 篇文本已加载, user.db={}, content.db={}",
             g_state.texts->size(), user_path, content_path);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int db_open(const char* content_path, const char* user_path)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    // 日志目录跟随用户库所在目录（App 数据目录），避免随 cwd 漂移
    const std::filesystem::path dbDir = std::filesystem::path(user_path).parent_path();
    Logger::getInstance().init((dbDir / "logs").string());
    LOG_INFO("bridge: 日志系统已初始化, 输出到 logs/app.log");

    return openDatabase(content_path, user_path);
}

extern "C" CHINESE_CORE_EXPORT void db_close()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    g_state = {};
    LOG_INFO("bridge: db_close 完成");
}

// ─── db_replace（纯内容库替换，user.db 永不替换） ────────────────────────────────

// 原子替换：只替换 classical.db 内容库，user.db 连接全程保持（若引擎已打开）。
// 顺序（崩溃安全）：
//   1. 先校验新内容包（db_version=1、纯内容、含 6 个初始化 q_key）；未通过则不动任何文件。
//   2. 引擎已打开时 DETACH content，旧内容库改名 .bak，新库改名到正式位。
//   3. 重新 ATTACH 新内容库并重载文本/索引；任一步失败都回滚 .bak 并重新挂载旧库。
//   4. 全部成功后再删除 .bak。
// 引擎未打开（启动前替换）时只做文件层替换，由调用方稍后 db_open 校验。
extern "C" CHINESE_CORE_EXPORT int db_replace(const char* new_db_path, const char* cur_db_path)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!new_db_path || !cur_db_path) return BRIDGE_ERR_GENERIC;
    const std::filesystem::path dbDir = std::filesystem::path(cur_db_path).parent_path();
    Logger::getInstance().init((dbDir / "logs").string());

    // 1. 校验新内容包（只读，不动任何现有文件）
    const int validateRc = validateContentFile(new_db_path);
    if (validateRc != BRIDGE_OK) {
        LOG_ERROR("db_replace: 新内容包校验失败 rc={}（旧库未动）", validateRc);
        return validateRc;
    }

    const std::string curStr(cur_db_path);
    const std::string bakStr = curStr + ".bak";
    const std::string userPath = (std::filesystem::path(cur_db_path).parent_path() / "user.db").string();
    const bool engineOpen = g_state.initialized && g_state.db && g_state.db->getConnection();

    // 2. 引擎打开时先卸载内容库，保证文件可替换
    if (engineOpen) {
        if (!g_state.db->detachDatabase("content")) {
            LOG_ERROR("db_replace: DETACH content 失败: {}", g_state.db->getLastError());
            return BRIDGE_ERR_GENERIC;
        }
    }

    // 3. 文件层原子替换：旧库 → .bak；新库 → 正式位
    std::error_code ec;
    std::filesystem::remove(bakStr, ec);
    if (std::filesystem::exists(curStr)) {
        std::filesystem::rename(curStr, bakStr, ec);
        if (ec) {
            LOG_ERROR("db_replace: 备份旧内容库到 .bak 失败: {}", ec.message());
            if (engineOpen) g_state.db->attachDatabase("content", curStr);
            return BRIDGE_ERR_GENERIC;
        }
    }
    std::filesystem::rename(new_db_path, curStr, ec);
    if (ec) {
        LOG_ERROR("db_replace: 移动新内容库失败: {}", ec.message());
        if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
        if (engineOpen) g_state.db->attachDatabase("content", curStr);
        return BRIDGE_ERR_GENERIC;
    }

    // 4. 引擎打开时重新挂载 + 重载文本/索引；失败回滚
    if (engineOpen) {
        const bool attachOk = g_state.db->attachDatabase("content", curStr);
        if (!attachOk) {
            LOG_ERROR("db_replace: 重新挂载新内容库失败: {}", g_state.db->getLastError());
            // 回滚：移除新库，恢复 .bak
            std::filesystem::remove(curStr, ec);
            if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
            g_state.db->attachDatabase("content", curStr);
            return BRIDGE_ERR_GENERIC;
        }
        const int contentRc = validateContentConnection(g_state.db->getConnection(), "content");
        if (contentRc != BRIDGE_OK) {
            LOG_ERROR("db_replace: 挂载后内容库校验失败 rc={}，回滚", contentRc);
            g_state.db->detachDatabase("content");
            std::filesystem::remove(curStr, ec);
            if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
            g_state.db->attachDatabase("content", curStr);
            return contentRc;
        }
        g_state.texts = std::make_unique<std::vector<Text>>(g_state.textRepo->getAllTexts());
        g_state.textIndex = std::make_unique<std::unordered_map<int, size_t>>();
        for (size_t i = 0; i < g_state.texts->size(); i++) {
            (*g_state.textIndex)[(*g_state.texts)[i].getId()] = i;
        }
        LOG_INFO("db_replace: 内容库替换完成并重载 — {} 篇文本", g_state.texts->size());
    } else {
        LOG_INFO("db_replace: 内容库文件替换完成（引擎未打开，等待 db_open）");
    }

    // 5. 成功后清理 .bak
    std::filesystem::remove(bakStr, ec);
    return BRIDGE_OK;
}

// ─── schema 版本查询（设置页数据状态展示） ─────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int db_get_schema_versions(int* user_version,
                                                          int* content_version)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !g_state.db || !g_state.db->getConnection()) {
        return BRIDGE_ERR_NOT_INIT;
    }
    if (!user_version || !content_version) return BRIDGE_ERR_GENERIC;
    *user_version = g_state.db->getUserVersion();
    *content_version = pragmaUserVersion(g_state.db->getConnection(), "content");
    if (*content_version < 0) return BRIDGE_ERR_DB_CONTENT;
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
    if (g_state.userRepo->saveUser(*g_state.user, g_state.activeUserId)) {
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
    if (g_state.userRepo->saveUser(*g_state.user, g_state.activeUserId)) {
        return BRIDGE_OK;
    }
    return BRIDGE_ERR_GENERIC;
}

// ─── 强制用户初始化 ──────────────────────────────────────────────────────────────

namespace {

const std::vector<std::string>& initQKeyList()
{
    static const std::vector<std::string> keys = {
        "d648b695e1579dbe", "28a1103b477177ee", "6dcbeb434a04bb29",
        "5f465c9792081778", "f6e064465d0da521", "638f4ed6d813d2f8",
    };
    return keys;
}

bool isInitQKey(const std::string& key)
{
    const auto& keys = initQKeyList();
    return std::find(keys.begin(), keys.end(), key) != keys.end();
}

bool fetchQuestionByQKey(sqlite3* db, const std::string& qkey, QuestionData& out)
{
    const char* sql = "SELECT id, q_type, stem, "
                      "json_extract(options, '$[0]'), json_extract(options, '$[1]'), "
                      "json_extract(options, '$[2]'), json_extract(options, '$[3]'), "
                      "dims, explanation, difficulty, "
                      "context, mark_start, mark_len "
                      "FROM questions WHERE q_key = ?;";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_text(stmt, 1, qkey.c_str(), -1, SQLITE_TRANSIENT);
    const bool ok = sqlite3_step(stmt) == SQLITE_ROW;
    if (ok) {
        std::memset(&out, 0, sizeof(out));
        out.id = sqlite3_column_int(stmt, 0);
        copyCString(out.q_type, sizeof(out.q_type), sqlite3_column_text(stmt, 1));
        copyCString(out.stem, sizeof(out.stem), sqlite3_column_text(stmt, 2));
        for (int i = 0; i < 4; i++) {
            copyCString(out.options[i], sizeof(out.options[0]), sqlite3_column_text(stmt, 3 + i));
        }
        copyCString(out.dims, sizeof(out.dims), sqlite3_column_text(stmt, 7));
        copyCString(out.explanation, sizeof(out.explanation), sqlite3_column_text(stmt, 8));
        out.difficulty = sqlite3_column_double(stmt, 9);
        copyCString(out.context, sizeof(out.context), sqlite3_column_text(stmt, 10));
        out.mark_start = sqlite3_column_int(stmt, 11);
        out.mark_len = sqlite3_column_int(stmt, 12);
    }
    sqlite3_finalize(stmt);
    return ok;
}

// Beta(3,7) 先验密度（未归一化）：u^(α-1) (1-u)^(β-1)
double initPriorDensity(double u)
{
    return std::pow(u, 2.0) * std::pow(1.0 - u, 6.0);
}

// 对单个维度的一组 (题目难度 d_j, 是否答对) 观测求后验均值
double initPosteriorMean(const std::vector<std::pair<double, int>>& observations)
{
    constexpr double kStep = 0.001;
    double sum = 0.0;
    double norm = 0.0;
    for (double u = 0.0; u <= 1.0 + 1e-12; u += kStep) {
        double w = initPriorDensity(u);
        for (const auto& [d, correct] : observations) {
            const double p = math_utils::expectedAccuracy(u, d);
            w *= correct ? p : (1.0 - p);
        }
        sum += u * w;
        norm += w;
    }
    return norm > 0.0 ? sum / norm : 0.3;
}

}  // namespace

extern "C" CHINESE_CORE_EXPORT int user_is_initialized()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    return g_state.userRepo->isInitialized(g_state.activeUserId) ? 1 : 0;
}

extern "C" CHINESE_CORE_EXPORT int user_init_questions(QuestionData* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    sqlite3* db = g_state.db->getConnection();
    int filled = 0;
    for (const auto& key : initQKeyList()) {
        if (filled >= max_count) break;
        if (!fetchQuestionByQKey(db, key, out[filled])) {
            LOG_ERROR("bridge: user_init_questions 缺少初始化题 q_key={}", key);
            return BRIDGE_ERR_DB_CONTENT;
        }
        filled++;
    }
    return filled;
}

// 一次性完成 6 道初始化题：判题、写 quiz_attempts(is_init=1)、贝叶斯后验、
// 清空被覆盖维度增量、置 initialized=1。不写 review_items、不重复写阅读历史。
extern "C" CHINESE_CORE_EXPORT int user_init_apply(const int* qids, const int* choices,
                                                   int count, int64_t timestamp,
                                                   UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (g_state.userRepo->isInitialized(g_state.activeUserId)) {
        LOG_WARN("bridge: user_init_apply 拒绝：当前档案已完成初始化，无补测");
        return BRIDGE_ERR_GENERIC;
    }
    if (!qids || !choices || !out_user) return BRIDGE_ERR_GENERIC;
    if (count != static_cast<int>(initQKeyList().size())) {
        LOG_WARN("bridge: user_init_apply 必须一次性提交 {} 题，收到 {}", initQKeyList().size(), count);
        return BRIDGE_ERR_GENERIC;
    }

    struct InitItem {
        int qid;
        int textId;
        int answer;
        int correct;
        std::vector<int> dims;
    };
    std::vector<InitItem> items;
    items.reserve(count);
    std::map<int, std::vector<std::pair<double, int>>> dimObs;
    std::set<int> coveredDims;
    std::set<int> seenQids;

    sqlite3* db = g_state.db->getConnection();
    for (int i = 0; i < count; i++) {
        const int qid = qids[i];
        const int choice = choices[i];
        if (choice < 0 || choice > 3) {
            LOG_WARN("bridge: user_init_apply choice 越界 qid={} choice={}", qid, choice);
            return BRIDGE_ERR_GENERIC;
        }
        if (!seenQids.insert(qid).second) {
            LOG_WARN("bridge: user_init_apply 重复题 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }

        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT q_key, text_id, answer_index, dims FROM questions WHERE id = ?;";
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("bridge: user_init_apply 准备失败: {}", sqlite3_errmsg(db));
            return BRIDGE_ERR_GENERIC;
        }
        sqlite3_bind_int(stmt, 1, qid);
        if (sqlite3_step(stmt) != SQLITE_ROW) {
            sqlite3_finalize(stmt);
            LOG_WARN("bridge: user_init_apply 题目不存在 qid={}", qid);
            return BRIDGE_ERR_TEXT;
        }
        const char* qkey = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        const std::string qkeyStr = qkey ? qkey : "";
        const int textId = sqlite3_column_int(stmt, 1);
        const int answer = sqlite3_column_int(stmt, 2);
        const char* dimsCsv = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3));
        const std::string dimsStr = dimsCsv ? dimsCsv : "";
        sqlite3_finalize(stmt);

        if (!isInitQKey(qkeyStr)) {
            LOG_WARN("bridge: user_init_apply 非初始化题 qid={} q_key={}", qid, qkeyStr);
            return BRIDGE_ERR_GENERIC;
        }
        auto it = g_state.textIndex->find(textId);
        if (it == g_state.textIndex->end()) {
            LOG_WARN("bridge: user_init_apply 文章不存在 text_id={}", textId);
            return BRIDGE_ERR_TEXT;
        }
        if (answer < 0 || answer > 3) {
            LOG_WARN("bridge: user_init_apply answer_index 越界 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }

        InitItem item;
        item.qid = qid;
        item.textId = textId;
        item.answer = answer;
        item.correct = (choice == answer) ? 1 : 0;
        std::stringstream ss(dimsStr);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) item.dims.push_back(std::atoi(tok.c_str()));
        }
        if (item.dims.empty()) {
            LOG_WARN("bridge: user_init_apply dims 为空 qid={}", qid);
            return BRIDGE_ERR_GENERIC;
        }
        for (int d : item.dims) {
            if (d < 0 || d >= 10) {
                LOG_WARN("bridge: user_init_apply 维度越界 qid={} d={}", qid, d);
                return BRIDGE_ERR_GENERIC;
            }
            const double dj = FeatureExtractor::getNormalizedFeatures((*g_state.texts)[it->second])[d];
            dimObs[d].push_back({dj, item.correct});
            coveredDims.insert(d);
        }
        items.push_back(std::move(item));
    }

    // 计算贝叶斯后验
    User updated;
    updated.initializeDefault();
    for (int d : coveredDims) {
        const double posterior = initPosteriorMean(dimObs[d]);
        updated.setAbility(d, posterior);
        updated.setBaseAbility(d, posterior);
        updated.setQuizCount(d, static_cast<int>(dimObs[d].size()));
    }

    const time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);

    // 事务：写作答流水 + 清增量 + 落库 + 置 initialized
    if (!execRawSql(db, "BEGIN IMMEDIATE")) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    for (const auto& item : items) {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "INSERT INTO quiz_attempts(user_id, question_id, text_id, correct, is_review, is_init, answered_at) "
                          "VALUES (?, ?, ?, ?, 0, 1, ?);";
        ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
        if (ok) {
            sqlite3_bind_int(stmt, 1, g_state.activeUserId);
            sqlite3_bind_int(stmt, 2, item.qid);
            sqlite3_bind_int(stmt, 3, item.textId);
            sqlite3_bind_int(stmt, 4, item.correct);
            sqlite3_bind_int64(stmt, 5, static_cast<int64_t>(effective_ts));
            ok = sqlite3_step(stmt) == SQLITE_DONE;
        }
        sqlite3_finalize(stmt);
        if (!ok) {
            LOG_ERROR("bridge: user_init_apply 写 quiz_attempts 失败 qid={}: {}", item.qid,
                      sqlite3_errmsg(db));
            break;
        }
    }

    if (ok && !coveredDims.empty()) {
        std::string sql = "DELETE FROM learning_increments WHERE user_id = ? AND dimension IN (";
        for (size_t i = 0; i < coveredDims.size(); i++) sql += (i ? ", ?" : "?");
        sql += ");";
        sqlite3_stmt* stmt = nullptr;
        ok = sqlite3_prepare_v2(db, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK;
        if (ok) {
            sqlite3_bind_int(stmt, 1, g_state.activeUserId);
            size_t i = 0;
            for (int d : coveredDims) {
                sqlite3_bind_int(stmt, static_cast<int>(2 + i), d + 1);  // 库内 1-based
                i++;
            }
            ok = sqlite3_step(stmt) == SQLITE_DONE;
        }
        sqlite3_finalize(stmt);
        if (!ok) {
            LOG_ERROR("bridge: user_init_apply 清理 learning_increments 失败: {}", sqlite3_errmsg(db));
        }
    }

    if (ok && !g_state.userRepo->saveUser(updated, g_state.activeUserId)) {
        LOG_ERROR("bridge: user_init_apply 落库失败");
        ok = false;
    }
    if (ok && !g_state.userRepo->setInitialized(g_state.activeUserId)) {
        LOG_ERROR("bridge: user_init_apply 置 initialized 失败");
        ok = false;
    }

    if (ok) {
        ok = execRawSql(db, "COMMIT");
    }
    if (!ok) {
        execRawSql(db, "ROLLBACK");
        return BRIDGE_ERR_GENERIC;
    }

    g_state.user = std::make_unique<User>(updated);
    user_to_c(updated, out_user);
    LOG_INFO("bridge: 用户初始化完成 — user_id={}, 覆盖维度 {} 个", g_state.activeUserId,
             static_cast<int>(coveredDims.size()));
    return BRIDGE_OK;
}

// ─── user profiles（本地多档案） ───────────────────────────────────────────────

// 未删除档案列表（按 id 升序）。返回条数；out 为空/容量不足按 0 处理（无错误码）。
extern "C" CHINESE_CORE_EXPORT int user_list(ProfileData* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_count <= 0) return 0;

    const auto profiles = g_state.userRepo->listProfiles();
    const int n = std::min(max_count, static_cast<int>(profiles.size()));
    for (int i = 0; i < n; i++) {
        std::memset(&out[i], 0, sizeof(ProfileData));
        out[i].id = profiles[i].id;
        std::strncpy(out[i].name, profiles[i].name.c_str(), 63);
        out[i].name[63] = '\0';
        out[i].created_at = profiles[i].createdAt;
        out[i].last_used_at = profiles[i].lastUsedAt;
        out[i].deleted = profiles[i].deleted;
    }
    return n;
}

extern "C" CHINESE_CORE_EXPORT int user_active_id()
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return 0;
    return g_state.activeUserId;
}

extern "C" CHINESE_CORE_EXPORT int user_create(const char* name)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_create 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    int newId = 0;
    if (!g_state.userRepo->createProfile(name, newId)) {
        LOG_ERROR("bridge: user_create 失败 name={}", name);
        return BRIDGE_ERR_GENERIC;
    }
    LOG_INFO("bridge: 已创建档案 id={} name={}", newId, name);
    return newId;
}

extern "C" CHINESE_CORE_EXPORT int user_create_inherit(const char* name, int source_id)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_create_inherit 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    int newId = 0;
    if (!g_state.userRepo->createProfileInherit(name, source_id, newId)) {
        LOG_ERROR("bridge: user_create_inherit 失败 name={} source_id={}", name, source_id);
        return BRIDGE_ERR_GENERIC;
    }
    LOG_INFO("bridge: 已创建继承档案 id={} name={} source_id={}", newId, name, source_id);
    return newId;
}

extern "C" CHINESE_CORE_EXPORT int user_switch(int id)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (id <= 0 || !g_state.userRepo->isProfileActive(id)) {
        LOG_WARN("bridge: user_switch 档案不存在或已删除 id={}", id);
        return BRIDGE_ERR_USER;
    }
    if (id == g_state.activeUserId) {
        g_state.userRepo->touchProfile(id);
        return BRIDGE_OK;
    }
    if (!loadUserForActive(id)) {
        return BRIDGE_ERR_GENERIC;
    }
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int user_rename(int id, const char* name)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!name || std::strlen(name) == 0 || std::strlen(name) > 63) {
        LOG_WARN("bridge: user_rename 非法档案名（空或超 63 字节）");
        return BRIDGE_ERR_GENERIC;
    }
    if (!g_state.userRepo->renameProfile(id, name)) {
        LOG_WARN("bridge: user_rename 拒绝（档案不存在/已删除/与未删除档案重名） id={}", id);
        return BRIDGE_ERR_USER;
    }
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int user_delete(int id)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (id == g_state.activeUserId) {
        LOG_WARN("bridge: user_delete 拒绝删除当前档案 id={}", id);
        return BRIDGE_ERR_USER;
    }
    if (!g_state.userRepo->deleteProfile(id)) {
        LOG_WARN("bridge: user_delete 档案不存在或已删除 id={}", id);
        return BRIDGE_ERR_USER;
    }
    LOG_INFO("bridge: 档案已软删 id={}", id);
    return BRIDGE_OK;
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

extern "C" CHINESE_CORE_EXPORT int text_get_translation(int id, char* out, int max_len)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (!out || max_len <= 0) return BRIDGE_ERR_GENERIC;

    sqlite3* db = g_state.db->getConnection();
    if (!db) return BRIDGE_ERR_GENERIC;

    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT translation FROM classical_text WHERE id = ?";
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: text_get_translation 准备失败: {}", sqlite3_errmsg(db));
        return BRIDGE_ERR_GENERIC;
    }

    sqlite3_bind_int(stmt, 1, id);
    int rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW) {
        const char* text = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        int len = text ? static_cast<int>(strlen(text)) : 0;
        if (len >= max_len) {
            LOG_WARN("bridge: text_id={} translation 截断 ({} > {} 字节)", id, len, max_len - 1);
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
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
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
                                   UserData* out_user, int skip_effect)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    if (skip_effect == 0) {
        const int initRc = requireInitialized();
        if (initRc != BRIDGE_OK) return initRc;
    }

    auto it = g_state.textIndex->find(text_id);
    if (it == g_state.textIndex->end()) return BRIDGE_ERR_TEXT;

    User cpp_user;
    c_to_user(user, cpp_user);

    time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);
    // R7：阅读效应 + 历史写入 + 落库同事务；失败回滚，避免"效应已应用但历史没写"或反之
    sqlite3* db = g_state.db->getConnection();
    if (!execRawSql(db, "BEGIN")) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    if (skip_effect == 0) {
        g_state.tracker->applyReadEffect(cpp_user, (*g_state.texts)[it->second], read_time,
                                         effective_ts);
        user_to_c(cpp_user, out_user);
    } else {
        // skip_effect=1：只记录阅读历史/已读，不应用能力效应
        user_to_c(cpp_user, out_user);
    }

    ok = g_state.historyRepo->markAsTracked(g_state.activeUserId, text_id);
    if (ok) ok = g_state.historyRepo->addRecord(g_state.activeUserId, text_id, read_time, effective_ts);
    if (ok && skip_effect == 0) {
        ok = g_state.userRepo->saveUser(cpp_user, g_state.activeUserId);
        if (!ok) LOG_ERROR("bridge: 阅读效应落库失败 text_id={}", text_id);
    }
    if (ok) {
        ok = execRawSql(db, "COMMIT");
    }
    if (!ok) {
        execRawSql(db, "ROLLBACK");
        return BRIDGE_ERR_GENERIC;
    }

    if (skip_effect == 0) {
        g_state.user = std::make_unique<User>(cpp_user);
        LOG_INFO("bridge: 知识追踪完成 — text_id={}, read_time={:.1f}s, avg_ability={:.3f}→{:.3f}",
                 text_id, read_time, g_state.user->getAverageAbility(), cpp_user.getAverageAbility());
    } else {
        LOG_INFO("bridge: 初始化阅读记录完成 — text_id={}, read_time={:.1f}s（无能力效应）",
                 text_id, read_time);
    }
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int tracker_apply_forgetting(const UserData* user, int64_t now,
                                         UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->applyForgettingEffect(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int tracker_prune(const UserData* user, int64_t now, UserData* out_user)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;

    User cpp_user;
    c_to_user(user, cpp_user);

    g_state.tracker->pruneOldIncrements(cpp_user, static_cast<time_t>(now));
    user_to_c(cpp_user, out_user);

    // 持久化修剪后的状态
    g_state.userRepo->saveUser(cpp_user, g_state.activeUserId);
    g_state.user = std::make_unique<User>(cpp_user);
    return BRIDGE_OK;
}

// questions 表缺失（手动替换的旧库/损坏资产）时优雅降级：取题按"无题"、判题按"题目不存在"，
// 与 text_get_translation 的 Dart 侧空降级保持一致（不把"表缺失"当成 GENERIC 硬错误）
static bool questionsTableExists()
{
    if (!g_state.db || !g_state.db->getConnection()) return false;
    return tableExists(g_state.db->getConnection(), "questions");
}

// 取题：按 text_id 返回该文题目（排除已答含复习记录 → 固定种子随机轮换，上限 max_count；
// 不下发 answer_index，判题只在 C++ 侧）
// 返回：题数（≥0）；文章不存在返回 BRIDGE_ERR_TEXT；参数非法返回 BRIDGE_ERR_GENERIC
// answered_all（可空）：1 = 该篇已无未答题；0 = 还有未答题或该篇无题
extern "C" CHINESE_CORE_EXPORT int question_get_by_text(int text_id, QuestionData* out,
                                                        int max_count, int* answered_all)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;
    if (g_state.textIndex->find(text_id) == g_state.textIndex->end()) {
        LOG_WARN("bridge: question_get_by_text 文章不存在 text_id={}", text_id);
        return BRIDGE_ERR_TEXT;
    }
    if (answered_all) *answered_all = 0;

    // 1. 该篇总题数（answered_all 判定基准）
    int total = 0;
    {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT COUNT(*) FROM questions WHERE text_id = ?";
        if (sqlite3_prepare_v2(g_state.db->getConnection(), sql, -1, &stmt, nullptr) != SQLITE_OK) {
            if (!questionsTableExists()) {
                LOG_WARN("bridge: question_get_by_text 无 questions 表，按无题处理 text_id={}", text_id);
                return 0;
            }
            LOG_ERROR("bridge: question_get_by_text count prepare 失败: {}",
                      sqlite3_errmsg(g_state.db->getConnection()));
            return BRIDGE_ERR_GENERIC;
        }
        sqlite3_bind_int(stmt, 1, text_id);
        if (sqlite3_step(stmt) == SQLITE_ROW) total = sqlite3_column_int(stmt, 0);
        sqlite3_finalize(stmt);
    }
    if (total == 0) return 0;

    // 2. 取未答题（排除已答含复习记录——答过就不重复考，复习队列是错题唯一回收通道）
    std::vector<QuestionData> pool;
    {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT id, q_type, stem, "
                          "json_extract(options, '$[0]'), json_extract(options, '$[1]'), "
                          "json_extract(options, '$[2]'), json_extract(options, '$[3]'), "
                          "dims, explanation, difficulty, "
                          "context, mark_start, mark_len "
                          "FROM questions WHERE text_id = ?1 AND id NOT IN "
                          "(SELECT question_id FROM quiz_attempts WHERE text_id = ?2 AND user_id = ?3) "
                          "ORDER BY seq, id";
        if (sqlite3_prepare_v2(g_state.db->getConnection(), sql, -1, &stmt, nullptr) != SQLITE_OK) {
            LOG_ERROR("bridge: question_get_by_text prepare 失败: {}",
                      sqlite3_errmsg(g_state.db->getConnection()));
            return BRIDGE_ERR_GENERIC;
        }
        sqlite3_bind_int(stmt, 1, text_id);
        sqlite3_bind_int(stmt, 2, text_id);
        sqlite3_bind_int(stmt, 3, g_state.activeUserId);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            QuestionData q;
            std::memset(&q, 0, sizeof(q));
            q.id = sqlite3_column_int(stmt, 0);
            copyCString(q.q_type, sizeof(q.q_type), sqlite3_column_text(stmt, 1));
            copyCString(q.stem, sizeof(q.stem), sqlite3_column_text(stmt, 2));
            for (int i = 0; i < 4; i++) {
                copyCString(q.options[i], sizeof(q.options[0]), sqlite3_column_text(stmt, 3 + i));
            }
            copyCString(q.dims, sizeof(q.dims), sqlite3_column_text(stmt, 7));
            copyCString(q.explanation, sizeof(q.explanation), sqlite3_column_text(stmt, 8));
            q.difficulty = sqlite3_column_double(stmt, 9);
            copyCString(q.context, sizeof(q.context), sqlite3_column_text(stmt, 10));
            q.mark_start = sqlite3_column_int(stmt, 11);
            q.mark_len = sqlite3_column_int(stmt, 12);
            pool.push_back(q);
        }
        sqlite3_finalize(stmt);
    }

    if (pool.empty()) {
        // 有题且全答完
        if (answered_all) *answered_all = 1;
        return 0;
    }

    // 3. 固定种子洗牌（Catch2 可复现）+ 截断到 max_count；
    //    同一篇连续作答自然轮换：已答题被排除，剩余题随机抽取直到答完
    std::mt19937 rng(kQuizShuffleSeed);
    std::shuffle(pool.begin(), pool.end(), rng);
    const int count = static_cast<int>(std::min<size_t>(pool.size(),
                                                        static_cast<size_t>(max_count)));
    for (int i = 0; i < count; i++) out[i] = pool[i];

    LOG_INFO("bridge: question_get_by_text text_id={} → {} 题 (上限 {}, 剩余 {})",
             text_id, count, max_count, pool.size());
    return count;
}

// 复习间隔：base · 2^streak，封顶 REVIEW_MAX_INTERVAL
static int64_t reviewIntervalAfter(int streak)
{
    int64_t interval = Config::REVIEW_BASE_INTERVAL;
    for (int i = 0; i < streak && i < 10; i++) {
        interval *= 2;
        if (interval >= Config::REVIEW_MAX_INTERVAL) return Config::REVIEW_MAX_INTERVAL;
    }
    return interval > Config::REVIEW_MAX_INTERVAL ? Config::REVIEW_MAX_INTERVAL : interval;
}

static bool execRawSql(sqlite3* db, const char* sql)
{
    char* err = nullptr;
    const int rc = sqlite3_exec(db, sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        LOG_ERROR("bridge: execSql 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }
    return true;
}

// 答题：按 question_id 查题 → 判题（用户选项 vs answer_index）→ applyQuizEffect（正式测验）
// + 写作答流水 quiz_attempts + upsert 复习状态 review_items（同锁同事务）
// is_review=1（错题复习）：跳过 applyQuizEffect（不更新能力/eta/quiz_count，防刷分），
// 只判题 + 写流水 + 更新复习状态。
extern "C" CHINESE_CORE_EXPORT int tracker_apply_quiz(const UserData* user, int question_id,
                                      int user_choice, int64_t timestamp,
                                      UserData* out_user, int* out_correct, int is_review)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;

    // 1. 查询题目（text_id / answer_index / dims CSV）
    std::string text_id, answer_index, dims;
    {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT text_id, answer_index, dims FROM questions WHERE id = ?";
        if (sqlite3_prepare_v2(g_state.db->getConnection(), sql, -1, &stmt, nullptr) != SQLITE_OK) {
            if (!questionsTableExists()) {
                LOG_WARN("bridge: tracker_apply_quiz 无 questions 表 question_id={}", question_id);
                return BRIDGE_ERR_TEXT;
            }
            LOG_ERROR("bridge: tracker_apply_quiz prepare 失败: {}", sqlite3_errmsg(g_state.db->getConnection()));
            return BRIDGE_ERR_GENERIC;
        }
        sqlite3_bind_int(stmt, 1, question_id);
        if (sqlite3_step(stmt) != SQLITE_ROW) {
            sqlite3_finalize(stmt);
            LOG_WARN("bridge: 题目不存在 question_id={}", question_id);
            return BRIDGE_ERR_TEXT;
        }
        const char* v1 = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
        const char* v2 = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
        const char* v3 = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2));
        if (!v1 || !v2 || !v3) {
            sqlite3_finalize(stmt);
            LOG_WARN("bridge: 题目字段缺失 question_id={}", question_id);
            return BRIDGE_ERR_TEXT;
        }
        text_id = v1;
        answer_index = v2;
        dims = v3;
        sqlite3_finalize(stmt);
    }

    int tid = std::atoi(text_id.c_str());
    int ans_idx = std::atoi(answer_index.c_str());
    if (ans_idx < 0 || ans_idx > 3) {
        LOG_WARN("bridge: answer_index 越界 question_id={} idx={}", question_id, ans_idx);
        return BRIDGE_ERR_GENERIC;
    }
    if (user_choice < 0 || user_choice > 3) {
        LOG_WARN("bridge: user_choice 越界 question_id={} choice={}", question_id, user_choice);
        return BRIDGE_ERR_GENERIC;
    }

    auto it = g_state.textIndex->find(tid);
    if (it == g_state.textIndex->end()) return BRIDGE_ERR_TEXT;

    // 2. 解析 dims CSV（如 "3,4,9" 表示 0-based 维度）
    std::vector<int> dim_list;
    {
        std::stringstream ss(dims);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty()) dim_list.push_back(std::atoi(tok.c_str()));
        }
    }
    if (dim_list.empty()) {
        LOG_WARN("bridge: dims 为空 question_id={}", question_id);
        return BRIDGE_ERR_GENERIC;
    }

    // 3. 判题（答题效应在步骤 4 事务内应用）
    User cpp_user;
    c_to_user(user, cpp_user);

    const int correct = (user_choice == ans_idx) ? 1 : 0;
    if (out_correct) *out_correct = correct;
    time_t effective_ts = (timestamp == 0) ? time(nullptr) : static_cast<time_t>(timestamp);

    // 4. 答题效应 + 落库 + 作答流水 + 复习状态（同一事务；失败回滚且返回错误）。
    // 防双计：若事务失败，能力/quiz_count/eta/增量与流水一起回滚，用户重试同一题不会二次生效
    sqlite3* db = g_state.db->getConnection();
    if (!execRawSql(db, "BEGIN")) return BRIDGE_ERR_GENERIC;
    bool ok = true;

    if (!is_review) {
        g_state.tracker->applyQuizEffect(cpp_user, (*g_state.texts)[it->second], dim_list,
                                         correct, effective_ts);
        user_to_c(cpp_user, out_user);
        if (!g_state.userRepo->saveUser(cpp_user, g_state.activeUserId)) {
            LOG_ERROR("bridge: 答题效应落库失败 question_id={}", question_id);
            execRawSql(db, "ROLLBACK");
            return BRIDGE_ERR_GENERIC;
        }
    } else {
        // 复习无效应：原样回传（调用方仍按契约接管返回的 user 内存）
        user_to_c(cpp_user, out_user);
    }

    {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "INSERT INTO quiz_attempts(user_id, question_id, text_id, correct, is_review, answered_at) "
                          "VALUES (?, ?, ?, ?, ?, ?)";
        ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
        if (ok) {
            sqlite3_bind_int(stmt, 1, g_state.activeUserId);
            sqlite3_bind_int(stmt, 2, question_id);
            sqlite3_bind_int(stmt, 3, tid);
            sqlite3_bind_int(stmt, 4, correct);
            sqlite3_bind_int(stmt, 5, is_review ? 1 : 0);
            sqlite3_bind_int64(stmt, 6, static_cast<int64_t>(effective_ts));
            ok = sqlite3_step(stmt) == SQLITE_DONE;
        }
        if (!ok) {
            LOG_ERROR("bridge: quiz_attempts 写入失败 question_id={}: {}", question_id,
                      sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
    }

    if (ok && correct == 1) {
        if (!is_review) {
            // 正式测验答对 → 视为已掌握，从复习队列移除
            sqlite3_stmt* stmt = nullptr;
            const char* sql = "DELETE FROM review_items WHERE user_id = ? AND question_id = ?";
            ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
            if (ok) {
                sqlite3_bind_int(stmt, 1, g_state.activeUserId);
                sqlite3_bind_int(stmt, 2, question_id);
                ok = sqlite3_step(stmt) == SQLITE_DONE;
            }
            if (!ok) {
                LOG_ERROR("bridge: review_items 删除失败 question_id={}: {}", question_id,
                          sqlite3_errmsg(db));
            }
            sqlite3_finalize(stmt);
        } else {
            // 复习答对 → streak+1，间隔翻倍；streak≥3 移除（视为掌握）
            int streak = 0;
            {
                sqlite3_stmt* stmt = nullptr;
                const char* sql = "SELECT correct_streak FROM review_items WHERE user_id = ? AND question_id = ?";
                ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
                if (ok) {
                    sqlite3_bind_int(stmt, 1, g_state.activeUserId);
                    sqlite3_bind_int(stmt, 2, question_id);
                    const int rc = sqlite3_step(stmt);
                    if (rc == SQLITE_ROW) streak = sqlite3_column_int(stmt, 0);
                    else if (rc != SQLITE_DONE) ok = false;
                }
                sqlite3_finalize(stmt);
            }
            if (ok) {
                if (streak + 1 >= Config::REVIEW_MASTER_STREAK) {
                    sqlite3_stmt* stmt = nullptr;
                    const char* sql = "DELETE FROM review_items WHERE user_id = ? AND question_id = ?";
                    ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
                    if (ok) {
                        sqlite3_bind_int(stmt, 1, g_state.activeUserId);
                        sqlite3_bind_int(stmt, 2, question_id);
                        ok = sqlite3_step(stmt) == SQLITE_DONE;
                    }
                    sqlite3_finalize(stmt);
                } else {
                    sqlite3_stmt* stmt = nullptr;
                    const char* sql = "UPDATE review_items SET correct_streak = ?, next_review_at = ? "
                                      "WHERE user_id = ? AND question_id = ?";
                    ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
                    if (ok) {
                        sqlite3_bind_int(stmt, 1, streak + 1);
                        sqlite3_bind_int64(stmt, 2, static_cast<int64_t>(effective_ts) +
                                           reviewIntervalAfter(streak + 1));
                        sqlite3_bind_int(stmt, 3, g_state.activeUserId);
                        sqlite3_bind_int(stmt, 4, question_id);
                        ok = sqlite3_step(stmt) == SQLITE_DONE;
                    }
                    sqlite3_finalize(stmt);
                }
            }
            if (!ok) {
                LOG_ERROR("bridge: review_items 更新失败 question_id={}: {}", question_id,
                          sqlite3_errmsg(db));
            }
        }
    } else if (ok && correct == 0) {
        // 答错（正式或复习均重置）：streak 清零、wrong_count+1、下次到期 = answered_at + base
        sqlite3_stmt* stmt = nullptr;
        const char* sql =
            "INSERT INTO review_items(user_id, question_id, text_id, correct_streak, wrong_count, next_review_at) "
            "VALUES (?, ?, ?, 0, COALESCE((SELECT wrong_count FROM review_items WHERE user_id = ? AND question_id = ?), 0) + 1, ?) "
            "ON CONFLICT(user_id, question_id) DO UPDATE SET "
            "correct_streak = 0, "
            "wrong_count = review_items.wrong_count + 1, "
            "next_review_at = excluded.next_review_at";
        ok = sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK;
        if (ok) {
            sqlite3_bind_int(stmt, 1, g_state.activeUserId);
            sqlite3_bind_int(stmt, 2, question_id);
            sqlite3_bind_int(stmt, 3, tid);
            sqlite3_bind_int(stmt, 4, g_state.activeUserId);
            sqlite3_bind_int(stmt, 5, question_id);
            sqlite3_bind_int64(stmt, 6, static_cast<int64_t>(effective_ts) +
                               Config::REVIEW_BASE_INTERVAL);
            ok = sqlite3_step(stmt) == SQLITE_DONE;
        }
        if (!ok) {
            LOG_ERROR("bridge: review_items upsert 失败 question_id={}: {}", question_id,
                      sqlite3_errmsg(db));
        }
        sqlite3_finalize(stmt);
    }

    if (ok) {
        ok = execRawSql(db, "COMMIT");
    }
    if (!ok) {
        execRawSql(db, "ROLLBACK");
        return BRIDGE_ERR_GENERIC;
    }

    // 事务成功后才更新内存态（与磁盘一致；失败时保持旧值，重试不会双计）
    if (!is_review) {
        const double avg_before = g_state.user->getAverageAbility();
        g_state.user = std::make_unique<User>(cpp_user);
        LOG_INFO("bridge: 答题效应完成 — question_id={}, correct={}, avg_ability={:.3f}→{:.3f}",
                 question_id, correct, avg_before, cpp_user.getAverageAbility());
    } else {
        LOG_INFO("bridge: 复习作答完成 — question_id={}, correct={}（无答题效应）",
                 question_id, correct);
    }
    return BRIDGE_OK;
}

// 到期错题列表：text_id=0 取全部，否则按篇过滤；只返回 next_review_at <= now 的条目，
// 按到期时间升序，上限 max_count。返回条数（≥0）
extern "C" CHINESE_CORE_EXPORT int quiz_get_review_items(int text_id, ReviewItemData* out,
                                                         int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!out || max_count <= 0) return BRIDGE_ERR_GENERIC;

    // 内容库删题后 review_items 会留下悬空条目（db_replace 合并后引用已不存在的
    // question_id）→ questions 表存在时过滤掉，避免复习列表出现点击无效的"文章 #N"组
    const bool hasQuestions = questionsTableExists();
    std::string sql = "SELECT question_id, text_id, correct_streak, wrong_count, next_review_at "
                      "FROM review_items WHERE user_id = ? AND next_review_at <= ? "
                      "AND (? = 0 OR text_id = ?)";
    if (hasQuestions) sql += " AND question_id IN (SELECT id FROM questions)";
    sql += " ORDER BY next_review_at ASC LIMIT ?";

    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(g_state.db->getConnection(), sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: quiz_get_review_items prepare 失败: {}",
                  sqlite3_errmsg(g_state.db->getConnection()));
        return BRIDGE_ERR_GENERIC;
    }
    sqlite3_bind_int(stmt, 1, g_state.activeUserId);
    sqlite3_bind_int64(stmt, 2, static_cast<int64_t>(time(nullptr)));
    sqlite3_bind_int(stmt, 3, text_id);
    sqlite3_bind_int(stmt, 4, text_id);
    sqlite3_bind_int(stmt, 5, max_count);

    int count = 0;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        ReviewItemData& r = out[count];
        std::memset(&r, 0, sizeof(r));
        r.question_id = sqlite3_column_int(stmt, 0);
        r.text_id = sqlite3_column_int(stmt, 1);
        r.correct_streak = sqlite3_column_int(stmt, 2);
        r.wrong_count = sqlite3_column_int(stmt, 3);
        r.next_review_at = sqlite3_column_int64(stmt, 4);
        count++;
    }
    sqlite3_finalize(stmt);
    return count;
}

// 到期错题总数：与 quiz_get_review_items 同一过滤条件（含悬空过滤），
// COUNT 聚合不走行缓冲 → 无上限截断，徽标数字真实（N15 方案 B：
// "总数"与"明细"语义分离，reviewCount 走此通道，列表仍走 quiz_get_review_items）
extern "C" CHINESE_CORE_EXPORT int quiz_get_due_review_count(int text_id)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (text_id < 0) return BRIDGE_ERR_GENERIC;

    const bool hasQuestions = questionsTableExists();
    std::string sql = "SELECT COUNT(*) FROM review_items WHERE user_id = ? AND next_review_at <= ? "
                      "AND (? = 0 OR text_id = ?)";
    if (hasQuestions) sql += " AND question_id IN (SELECT id FROM questions)";

    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(g_state.db->getConnection(), sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: quiz_get_due_review_count prepare 失败: {}",
                  sqlite3_errmsg(g_state.db->getConnection()));
        return BRIDGE_ERR_GENERIC;
    }
    sqlite3_bind_int(stmt, 1, g_state.activeUserId);
    sqlite3_bind_int64(stmt, 2, static_cast<int64_t>(time(nullptr)));
    sqlite3_bind_int(stmt, 3, text_id);
    sqlite3_bind_int(stmt, 4, text_id);

    int count = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return count;
}
// 按 id 取题专用通道（复习用）：复习题是已答题，question_get_by_text 排除已答后拿不到，
// 此通道不受排除已答影响。按输入顺序返回，上限 max_count（不校验 id 是否存在，
// 缺失 id 被跳过）。返回实际条数
extern "C" CHINESE_CORE_EXPORT int quiz_get_questions_by_ids(const int* ids, int count,
                                                             QuestionData* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (!ids || !out || count <= 0 || max_count <= 0) return BRIDGE_ERR_GENERIC;

    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT id, q_type, stem, "
                      "json_extract(options, '$[0]'), json_extract(options, '$[1]'), "
                      "json_extract(options, '$[2]'), json_extract(options, '$[3]'), "
                      "dims, explanation, difficulty, "
                      "context, mark_start, mark_len "
                      "FROM questions WHERE id = ?";
    if (sqlite3_prepare_v2(g_state.db->getConnection(), sql, -1, &stmt, nullptr) != SQLITE_OK) {
        LOG_ERROR("bridge: quiz_get_questions_by_ids prepare 失败: {}",
                  sqlite3_errmsg(g_state.db->getConnection()));
        return BRIDGE_ERR_GENERIC;
    }

    int filled = 0;
    const int n = count < max_count ? count : max_count;
    for (int i = 0; i < n; i++) {
        sqlite3_reset(stmt);
        sqlite3_bind_int(stmt, 1, ids[i]);
        if (sqlite3_step(stmt) != SQLITE_ROW) continue;  // 缺失 id：跳过
        QuestionData& q = out[filled];
        std::memset(&q, 0, sizeof(q));
        q.id = sqlite3_column_int(stmt, 0);
        copyCString(q.q_type, sizeof(q.q_type), sqlite3_column_text(stmt, 1));
        copyCString(q.stem, sizeof(q.stem), sqlite3_column_text(stmt, 2));
        for (int k = 0; k < 4; k++) {
            copyCString(q.options[k], sizeof(q.options[0]), sqlite3_column_text(stmt, 3 + k));
        }
        copyCString(q.dims, sizeof(q.dims), sqlite3_column_text(stmt, 7));
        copyCString(q.explanation, sizeof(q.explanation), sqlite3_column_text(stmt, 8));
        q.difficulty = sqlite3_column_double(stmt, 9);
        copyCString(q.context, sizeof(q.context), sqlite3_column_text(stmt, 10));
        q.mark_start = sqlite3_column_int(stmt, 11);
        q.mark_len = sqlite3_column_int(stmt, 12);
        filled++;
    }
    sqlite3_finalize(stmt);
    return filled;
}

// 文章测验摘要：总题数/已答数/错题数（review_items 现役错题）一次查询。
// 文章不存在返回 BRIDGE_ERR_TEXT；out 指针可空（跳过对应统计）
extern "C" CHINESE_CORE_EXPORT int quiz_get_attempt_summary(int text_id, int* total,
                                                            int* answered, int* wrong)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    const int initRc = requireInitialized();
    if (initRc != BRIDGE_OK) return initRc;
    if (g_state.textIndex->find(text_id) == g_state.textIndex->end()) return BRIDGE_ERR_TEXT;

    sqlite3* db = g_state.db->getConnection();

    // 输出先归零：查询失败（如老库缺 questions 表）时返回 0 而非调用者初值，
    // 与"表缺失=优雅降级"协议一致（N3）
    if (total) *total = 0;
    if (answered) *answered = 0;
    if (wrong) *wrong = 0;

    if (total) {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT COUNT(*) FROM questions WHERE text_id = ?";
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, text_id);
            if (sqlite3_step(stmt) == SQLITE_ROW) *total = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    if (answered) {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT COUNT(DISTINCT question_id) FROM quiz_attempts WHERE text_id = ? AND user_id = ?";
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, text_id);
            sqlite3_bind_int(stmt, 2, g_state.activeUserId);
            if (sqlite3_step(stmt) == SQLITE_ROW) *answered = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    if (wrong) {
        sqlite3_stmt* stmt = nullptr;
        const char* sql = "SELECT COUNT(*) FROM review_items WHERE text_id = ? AND user_id = ?";
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int(stmt, 1, text_id);
            sqlite3_bind_int(stmt, 2, g_state.activeUserId);
            if (sqlite3_step(stmt) == SQLITE_ROW) *wrong = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    return BRIDGE_OK;
}

// ─── history ──────────────────────────────────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int history_add_record(int text_id, double read_time, int64_t timestamp)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized) return BRIDGE_ERR_NOT_INIT;
    bool ok = g_state.historyRepo->addRecord(g_state.activeUserId, text_id, read_time,
                                             static_cast<time_t>(timestamp));
    if (ok) {
        LOG_INFO("bridge: history_add_record text_id={} read_time={:.1f}s", text_id, read_time);
    }
    return ok ? BRIDGE_OK : BRIDGE_ERR_GENERIC;
}

extern "C" CHINESE_CORE_EXPORT int history_get_recent(int limit, ReadingRecordData* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !out) return BRIDGE_ERR_NOT_INIT;
    // 钳制：非正 limit/max_count 按"无结果"处理（SQLite LIMIT -1 视为无限制，必须拦下）
    if (limit <= 0 || max_count <= 0) return 0;

    auto records = g_state.historyRepo->getRecentRecords(g_state.activeUserId, limit);
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
    return g_state.historyRepo->getTotalReadCount(g_state.activeUserId);
}

extern "C" CHINESE_CORE_EXPORT int history_get_tracked_text_ids(int* out, int max_count)
{
    std::lock_guard<std::mutex> lock(g_mtx);
    if (!g_state.initialized || !out) return 0;

    auto ids = g_state.historyRepo->getTrackedTextIds(g_state.activeUserId);
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
