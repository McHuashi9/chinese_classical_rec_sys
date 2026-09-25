// 桥层生命周期域（v1.4.0 工作项 3）：db_open / db_close / user_export / db_replace /
// db_get_schema_versions，共 5 个导出符号。
//
// 本域保留 5 处原始连接访问（PRAGMA 读取 / 整库备份判断 / 内容库校验），
// 与验收口径「残留 6 处 = 生命周期 5 + 共享事务 helper 1」对应。

#include "bridge_internal.h"
#include "user_tables.h"

#include <filesystem>
#include <set>
#include <string>

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

    // 6 个强制初始化 q_key 必须存在（启动期拒绝，避免初始化流程卡死）。
    // 清单单一来源 = initQKeys()（原 bridge.cpp:241 的 kInitQKeys[] 已删除）。
    for (const auto& qkey : initQKeys()) {
        const std::string sql = "SELECT 1 FROM " + prefix + "questions WHERE q_key = ? LIMIT 1;";
        sqlite3_stmt* q = nullptr;
        if (sqlite3_prepare_v2(db, sql.c_str(), -1, &q, nullptr) != SQLITE_OK) {
            LOG_ERROR("bridge: 内容库 questions.q_key 校验失败: {}", sqlite3_errmsg(db));
            return BRIDGE_ERR_DB_CONTENT;
        }
        sqlite3_bind_text(q, 1, qkey.c_str(), -1, SQLITE_TRANSIENT);
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
    S() = {};
    if (!content_path || !user_path) return BRIDGE_ERR_GENERIC;
    if (samePath(content_path, user_path)) {
        LOG_ERROR("bridge: user.db 与 classical.db 同路径: {}", content_path);
        return BRIDGE_ERR_DB_SAME_PATH;
    }

    const bool userExisted = std::filesystem::exists(user_path);
    S().db = std::make_unique<DatabaseManager>();
    if (!S().db->open(user_path)) {
        LOG_ERROR("bridge: user.db 打开失败: {}", S().db->getLastError());
        S().db.reset();
        return BRIDGE_ERR_DB_USER;
    }

    // 先判断 SQLite 可读性/损坏，再判断版本：损坏/非 SQLite 文件不应误报“版本不兼容”
    if (userExisted && !S().db->isReadable()) {
        LOG_ERROR("bridge: user.db 不是可读 SQLite 或已损坏: {}", S().db->getLastError());
        S() = {};
        return BRIDGE_ERR_DB_USER;
    }

    // 旧开发版 user.db（db_version=0）不做升级，直接拒绝；>1 也拒绝
    if (userExisted && S().db->getUserVersion() != 1) {
        LOG_ERROR("bridge: user.db db_version={} 不兼容，仅支持 1", S().db->getUserVersion());
        S() = {};
        return BRIDGE_ERR_DB_VERSION;
    }

    S().userRepo = std::make_unique<UserRepository>(S().db.get());
    S().textRepo = std::make_unique<TextRepository>(S().db.get());
    S().historyRepo = std::make_unique<ReadingHistoryRepository>(S().db.get());
    S().incrementRepo = std::make_unique<LearningIncrementRepository>(S().db.get());
    S().quizRepo = std::make_unique<QuizRepository>(S().db.get());
    S().reviewRepo = std::make_unique<ReviewRepository>(S().db.get());

    // 用户库三张域表幂等建全（内容表属于内容库，不在此初始化）
    if (!S().userRepo->initTable() ||
        !S().historyRepo->initTable() ||
        !S().incrementRepo->initTable()) {
        LOG_ERROR("bridge: 用户表初始化失败");
        S() = {};
        return BRIDGE_ERR_INIT;
    }

    // 已决策“删除不可恢复”：清理历史遗留的软删除档案，避免隐藏数据残留
    if (!S().userRepo->purgeDeletedProfiles()) {
        LOG_ERROR("bridge: 清理历史软删除档案失败");
        S() = {};
        return BRIDGE_ERR_INIT;
    }

    // 全新用户库建表后写入 db_version=1；已存在且在版本检查通过的保持原值
    if (!userExisted && !S().db->setUserVersion(1)) {
        LOG_ERROR("bridge: 写入 user.db db_version 失败");
        S() = {};
        return BRIDGE_ERR_INIT;
    }

    // 内容库：先独立校验文件，再挂载到主连接
    const int contentRc = validateContentFile(content_path);
    if (contentRc != BRIDGE_OK) {
        S() = {};
        return contentRc;
    }
    if (!S().db->attachDatabase("content", content_path)) {
        LOG_ERROR("bridge: 挂载内容库失败: {}", S().db->getLastError());
        S() = {};
        return BRIDGE_ERR_DB_CONTENT;
    }

    S().engine = std::make_unique<RecommendationEngine>();
    S().user = std::make_unique<User>();
    S().texts = std::make_unique<std::vector<Text>>(S().textRepo->getAllTexts());

    // 构建 O(1) 文本索引 (id → vector 下标)
    S().textIndex = std::make_unique<std::unordered_map<int, size_t>>();
    for (size_t i = 0; i < S().texts->size(); i++) {
        (*S().textIndex)[(*S().texts)[i].getId()] = i;
    }

    S().tracker = std::make_unique<KnowledgeTracker>(S().incrementRepo.get());

    // 确保默认档案存在（新库默认档案 initialized=0，进入强制初始化流程）
    S().userRepo->ensureProfileExists(1, "默认用户");
    S().initialized = true;
    if (!loadUserForActive(1)) {
        LOG_ERROR("bridge: 默认档案加载失败");
        S() = {};
        return BRIDGE_ERR_INIT;
    }

    LOG_INFO("bridge: 数据库已打开 — {} 篇文本已加载, user.db={}, content.db={}",
             S().texts->size(), user_path, content_path);
    return BRIDGE_OK;
}

extern "C" CHINESE_CORE_EXPORT int db_open(const char* content_path, const char* user_path)
{
    return bridge_guard(g_mtx, [&] {
    // 日志目录跟随用户库所在目录（App 数据目录），避免随 cwd 漂移
    const std::filesystem::path dbDir = std::filesystem::path(user_path).parent_path();
    Logger::getInstance().init((dbDir / "logs").string());
    LOG_INFO("bridge: 日志系统已初始化, 输出到 logs/app.log");

    return openDatabase(content_path, user_path);
    });
}

extern "C" CHINESE_CORE_EXPORT void db_close()
{
    bridge_guard_void(g_mtx, [&] {
    S() = {};
    LOG_INFO("bridge: db_close 完成");
    });
}

// 整库快照（sqlite3_backup 编排下沉至 DatabaseManager::backupTo；v1.4.0 工作项 2）
extern "C" CHINESE_CORE_EXPORT int user_export(const char* dest_path)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized || !S().db) return BRIDGE_ERR_NOT_INIT;
    if (!dest_path || !*dest_path) return BRIDGE_ERR_GENERIC;

    if (!S().db->backupTo(dest_path)) {
        LOG_ERROR("bridge: user_export 失败: {}", S().db->getLastError());
        return BRIDGE_ERR_GENERIC;
    }
    return BRIDGE_OK;
    });
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
    return bridge_guard(g_mtx, [&] {
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
    const bool engineOpen = S().initialized && S().db && S().db->getConnection();

    // 2. 引擎打开时先卸载内容库，保证文件可替换
    if (engineOpen) {
        if (!S().db->detachDatabase("content")) {
            LOG_ERROR("db_replace: DETACH content 失败: {}", S().db->getLastError());
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
            if (engineOpen) S().db->attachDatabase("content", curStr);
            return BRIDGE_ERR_GENERIC;
        }
    }
    std::filesystem::rename(new_db_path, curStr, ec);
    if (ec) {
        LOG_ERROR("db_replace: 移动新内容库失败: {}", ec.message());
        if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
        if (engineOpen) S().db->attachDatabase("content", curStr);
        return BRIDGE_ERR_GENERIC;
    }

    // 4. 引擎打开时重新挂载 + 重载文本/索引；失败回滚
    if (engineOpen) {
        const bool attachOk = S().db->attachDatabase("content", curStr);
        if (!attachOk) {
            LOG_ERROR("db_replace: 重新挂载新内容库失败: {}", S().db->getLastError());
            // 回滚：移除新库，恢复 .bak
            std::filesystem::remove(curStr, ec);
            if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
            S().db->attachDatabase("content", curStr);
            return BRIDGE_ERR_GENERIC;
        }
        const int contentRc = validateContentConnection(S().db->getConnection(), "content");
        if (contentRc != BRIDGE_OK) {
            LOG_ERROR("db_replace: 挂载后内容库校验失败 rc={}，回滚", contentRc);
            S().db->detachDatabase("content");
            std::filesystem::remove(curStr, ec);
            if (std::filesystem::exists(bakStr)) std::filesystem::rename(bakStr, curStr, ec);
            S().db->attachDatabase("content", curStr);
            return contentRc;
        }
        S().texts = std::make_unique<std::vector<Text>>(S().textRepo->getAllTexts());
        S().textIndex = std::make_unique<std::unordered_map<int, size_t>>();
        for (size_t i = 0; i < S().texts->size(); i++) {
            (*S().textIndex)[(*S().texts)[i].getId()] = i;
        }
        LOG_INFO("db_replace: 内容库替换完成并重载 — {} 篇文本", S().texts->size());
    } else {
        LOG_INFO("db_replace: 内容库文件替换完成（引擎未打开，等待 db_open）");
    }

    // 5. 成功后清理 .bak
    std::filesystem::remove(bakStr, ec);
    return BRIDGE_OK;
    });
}

// ─── schema 版本查询（设置页数据状态展示） ─────────────────────────────────────

extern "C" CHINESE_CORE_EXPORT int db_get_schema_versions(int* user_version,
                                                          int* content_version)
{
    return bridge_guard(g_mtx, [&] {
    if (!S().initialized || !S().db || !S().db->getConnection()) {
        return BRIDGE_ERR_NOT_INIT;
    }
    if (!user_version || !content_version) return BRIDGE_ERR_GENERIC;
    *user_version = S().db->getUserVersion();
    *content_version = pragmaUserVersion(S().db->getConnection(), "content");
    if (*content_version < 0) return BRIDGE_ERR_DB_CONTENT;
    return BRIDGE_OK;
    });
}
