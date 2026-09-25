#include "database/UserRepository.h"
#include "database/schema_introspect.h"
#include "utils/Logger.h"
#include <sqlite3.h>
#include <iostream>
#include <sstream>
#include <cstdlib>
#include <ctime>
#include <set>
#include <unordered_map>
#include <functional>
#include <utility>
#include <vector>

using dbschema::copyCommonColumns;
using dbschema::tableColumns;
using dbschema::tableExists;
using dbschema::tableSql;

UserRepository::UserRepository(DatabaseManager* dbManager) : db(dbManager) {}

bool UserRepository::initTable() {
    sqlite3* c = db->getConnection();
    if (!c) return false;

    // 论文10维能力向量：d1-d10；多用户化：id 为普通主键，无 CHECK(id=1)
    const char* newUserSql =
        "CREATE TABLE IF NOT EXISTS user ("
        "id INTEGER PRIMARY KEY, "
        "d1_ability REAL DEFAULT 0.0, "  // f1 平均句长
        "d2_ability REAL DEFAULT 0.0, "  // f3 句子数
        "d3_ability REAL DEFAULT 0.0, "  // f5 虚词比例
        "d4_ability REAL DEFAULT 0.0, "  // f6 字平均对数频次
        "d5_ability REAL DEFAULT 0.0, "  // f8 通假字密度
        "d6_ability REAL DEFAULT 0.0, "  // f9 古汉语困惑度
        "d7_ability REAL DEFAULT 0.0, "  // f10 今汉语困惑度
        "d8_ability REAL DEFAULT 0.0, "  // f11 MATTR词汇多样性
        "d9_ability REAL DEFAULT 0.0, "  // f12 典故密度
        "d10_ability REAL DEFAULT 0.0, " // f13 语义复杂度
        "d1_base_ability REAL DEFAULT 0.0, "  // d1 基础能力
        "d2_base_ability REAL DEFAULT 0.0, "  // d2 基础能力
        "d3_base_ability REAL DEFAULT 0.0, "  // d3 基础能力
        "d4_base_ability REAL DEFAULT 0.0, "  // d4 基础能力
        "d5_base_ability REAL DEFAULT 0.0, "  // d5 基础能力
        "d6_base_ability REAL DEFAULT 0.0, "  // d6 基础能力
        "d7_base_ability REAL DEFAULT 0.0, "  // d7 基础能力
        "d8_base_ability REAL DEFAULT 0.0, "  // d8 基础能力
        "d9_base_ability REAL DEFAULT 0.0, "  // d9 基础能力
        "d10_base_ability REAL DEFAULT 0.0, " // d10 基础能力
        "eta REAL DEFAULT 0.08, "            // 悟性（答题效应动态调整）
        "d1_quiz_count INTEGER DEFAULT 0, "
        "d2_quiz_count INTEGER DEFAULT 0, "
        "d3_quiz_count INTEGER DEFAULT 0, "
        "d4_quiz_count INTEGER DEFAULT 0, "
        "d5_quiz_count INTEGER DEFAULT 0, "
        "d6_quiz_count INTEGER DEFAULT 0, "
        "d7_quiz_count INTEGER DEFAULT 0, "
        "d8_quiz_count INTEGER DEFAULT 0, "
        "d9_quiz_count INTEGER DEFAULT 0, "
        "d10_quiz_count INTEGER DEFAULT 0, "
        "last_read_time INTEGER DEFAULT 0, "  // 最后阅读时间戳
        "initialized INTEGER NOT NULL DEFAULT 0"  // 强制初始化完成标记
        ");";

    // 档案元数据表（多用户）
    const char* profilesSql =
        "CREATE TABLE IF NOT EXISTS profiles ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "name TEXT NOT NULL, "
        "created_at INTEGER NOT NULL, "
        "last_used_at INTEGER NOT NULL, "
        "deleted INTEGER NOT NULL DEFAULT 0"
        ");";

    if (!db->executeSQL(profilesSql)) {
        LOG_ERROR("UserRepository::initTable profiles failed: {}", db->getLastError());
        return false;
    }

    // 老库迁移：user 表带 CHECK(id=1) → 重建为普通主键多行表（SQLite 无法直接删 CHECK）
    if (tableExists(c, "user")) {
        const std::string oldSql = tableSql(c, "user");
        if (oldSql.find("CHECK") != std::string::npos) {
            LOG_INFO("UserRepository: 检测到 user 表 CHECK(id=1)，迁移为多用户 schema");
            if (!db->executeSQL("ALTER TABLE user RENAME TO user_old;")) {
                LOG_ERROR("UserRepository: user 重命名失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL(newUserSql)) {
                LOG_ERROR("UserRepository: 新 user 表创建失败: {}", db->getLastError());
                return false;
            }
            if (!copyCommonColumns(c, "user_old", "user")) {
                return false;
            }
            if (!db->executeSQL("DROP TABLE user_old;")) {
                LOG_ERROR("UserRepository: 删除 user_old 失败: {}", db->getLastError());
                return false;
            }
        }
    } else if (!db->executeSQL(newUserSql)) {
        LOG_ERROR("UserRepository::initTable user failed: {}", db->getLastError());
        return false;
    }

    // ── 迁移：按列存在性补/删列（v1.4.0 工作项 1）─────────────────────────────
    // 设计定稿：不提 PRAGMA user_version（它是 bridge 的打开门控，提升会让旧版二进制
    // 拒绝打开用户库），也不再用「盲执行 ALTER + 忽略错误」；改用 dbschema::tableColumns()
    // 内省。对已存在库的最终 schema 与旧实现等价（旧实现对已存在列执行 ALTER 失败即忽略），
    // 且可重复执行、幂等。注：本仓代码原无「版本号快路径短路」，此项是「不引入」，无删除动作。
    {
        const std::set<std::string> userCols = tableColumns(c, "user");
        const auto addUserColumn = [&](const std::string& column, const std::string& ddl) {
            if (userCols.count(column)) return;
            if (!db->executeSQL(ddl)) {
                LOG_WARN("UserRepository: user 表补列 {} 失败: {}", column, db->getLastError());
            }
        };

        addUserColumn("last_read_time", "ALTER TABLE user ADD COLUMN last_read_time INTEGER DEFAULT 0;");
        // v1.0.0：强制初始化标记
        addUserColumn("initialized",
                      "ALTER TABLE user ADD COLUMN initialized INTEGER NOT NULL DEFAULT 0;");

        // 迁移：添加基础能力字段
        for (int i = 1; i <= 10; ++i) {
            const std::string suffix = std::to_string(i) + "_base_ability";
            addUserColumn("d" + suffix,
                          "ALTER TABLE user ADD COLUMN d" + suffix + " REAL DEFAULT 0.0;");
        }
        // 迁移：悟性 η 与累计答题次数 N_j（答题效应，论文§5.3）
        addUserColumn("eta", "ALTER TABLE user ADD COLUMN eta REAL DEFAULT 0.08;");
        for (int i = 1; i <= 10; ++i) {
            const std::string suffix = std::to_string(i) + "_quiz_count";
            addUserColumn("d" + suffix,
                          "ALTER TABLE user ADD COLUMN d" + suffix + " INTEGER DEFAULT 0;");
        }

        // 迁移：移除已弃用的 name 列（如果存在）
        if (userCols.count("name")) {
            // SQLite < 3.35.0 不支持 DROP COLUMN，与旧实现一样忽略失败
            db->executeSQL("ALTER TABLE user DROP COLUMN name;");
        }
    }

    // 测验闭环（作答流水 + 错题复习状态）：CREATE IF NOT EXISTS 幂等建表 + 按列内省补列，
    // 旧库打开即自动迁移
    const char* quizAttemptsSql =
        "CREATE TABLE IF NOT EXISTS quiz_attempts ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "user_id INTEGER NOT NULL DEFAULT 1, "   // 多用户：当前档案 id
        "question_id INTEGER NOT NULL, "          // questions.id（内容库）
        "text_id INTEGER NOT NULL, "
        "correct INTEGER NOT NULL, "              // 0/1
        "is_review INTEGER DEFAULT 0, "           // 0=正式测验 1=错题复习
        "is_init INTEGER DEFAULT 0, "             // 1=强制初始化题（不再普通出现）
        "answered_at INTEGER NOT NULL"            // unix 秒
        ");";
    const char* reviewItemsSql =
        "CREATE TABLE IF NOT EXISTS review_items ("
        "question_id INTEGER NOT NULL, "          // 错题（quiz_attempts 中答错过的题）
        "user_id INTEGER NOT NULL DEFAULT 1, "    // 多用户：当前档案 id
        "text_id INTEGER NOT NULL, "
        "correct_streak INTEGER DEFAULT 0, "      // 连续答对次数（调度翻倍用）
        "wrong_count INTEGER DEFAULT 0, "
        "next_review_at INTEGER NOT NULL, "       // 下次到期时间
        "PRIMARY KEY (user_id, question_id)"
        ");";
    const char* quizAttemptsIdxSql =
        "CREATE INDEX IF NOT EXISTS idx_quiz_attempts_text ON quiz_attempts(text_id, question_id);";
    const char* quizAttemptsUserIdxSql =
        "CREATE INDEX IF NOT EXISTS idx_quiz_attempts_user_text ON quiz_attempts(user_id, text_id, question_id);";

    if (!db->executeSQL(quizAttemptsSql) || !db->executeSQL(reviewItemsSql)) {
        LOG_ERROR("UserRepository::initTable quiz tables failed: {}", db->getLastError());
        return false;
    }

    // 旧 quiz_attempts 表补列（必须先于依赖该列的索引创建）
    {
        const std::set<std::string> attemptCols = tableColumns(c, "quiz_attempts");
        const auto addAttemptColumn = [&](const std::string& column, const std::string& ddl) {
            if (attemptCols.count(column)) return;
            if (!db->executeSQL(ddl)) {
                LOG_WARN("UserRepository: quiz_attempts 补列 {} 失败: {}", column, db->getLastError());
            }
        };
        addAttemptColumn("user_id",
                         "ALTER TABLE quiz_attempts ADD COLUMN user_id INTEGER NOT NULL DEFAULT 1;");
        // v1.0.0：初始化题标记
        addAttemptColumn("is_init", "ALTER TABLE quiz_attempts ADD COLUMN is_init INTEGER DEFAULT 0;");
    }

    if (!db->executeSQL(quizAttemptsIdxSql) || !db->executeSQL(quizAttemptsUserIdxSql)) {
        LOG_ERROR("UserRepository::initTable quiz index failed: {}", db->getLastError());
        return false;
    }

    // 旧 review_items 表（单列主键 question_id）→ 重建为复合主键 (user_id, question_id)
    if (tableExists(c, "review_items")) {
        const std::string oldSql = tableSql(c, "review_items");
        const bool oldPk = oldSql.find("question_id INTEGER PRIMARY KEY") != std::string::npos;
        const bool hasUserId = tableColumns(c, "review_items").count("user_id") != 0;
        if (oldPk || !hasUserId) {
            LOG_INFO("UserRepository: 检测到 review_items 旧主键，迁移为 (user_id, question_id)");
            if (!db->executeSQL("ALTER TABLE review_items RENAME TO review_items_old;")) {
                LOG_ERROR("UserRepository: review_items 重命名失败: {}", db->getLastError());
                return false;
            }
            if (!db->executeSQL(reviewItemsSql)) {
                LOG_ERROR("UserRepository: 新 review_items 创建失败: {}", db->getLastError());
                return false;
            }
            if (!copyCommonColumns(c, "review_items_old", "review_items")) {
                return false;
            }
            if (!db->executeSQL("DROP TABLE review_items_old;")) {
                LOG_ERROR("UserRepository: 删除 review_items_old 失败: {}", db->getLastError());
                return false;
            }
        }
    }

    // 档案行与 user 行对齐：老库 id=1 数据归入"默认用户"档案
    if (!db->executeSQL(
        "INSERT OR IGNORE INTO profiles (id, name, created_at, last_used_at, deleted) "
        "SELECT id, '默认用户', strftime('%s','now'), strftime('%s','now'), 0 FROM user;")) {
        LOG_ERROR("UserRepository::initTable 档案对齐失败: {}", db->getLastError());
        return false;
    }

    return true;
}

static int getUserCallback(void* data, int argc, char** argv, char** azColName) {
    struct GetUserData {
        User* user;
        bool found;
    };
    auto* gd = static_cast<GetUserData*>(data);
    User* user = gd->user;
    gd->found = true;
    
    // 字段映射表：列名 -> setter函数
    static const std::unordered_map<std::string, std::function<void(User*, const char*)>> fieldMap = {
        {"d1_ability", [](User* u, const char* v) { u->setAbility(0, std::atof(v)); }},
        {"d2_ability", [](User* u, const char* v) { u->setAbility(1, std::atof(v)); }},
        {"d3_ability", [](User* u, const char* v) { u->setAbility(2, std::atof(v)); }},
        {"d4_ability", [](User* u, const char* v) { u->setAbility(3, std::atof(v)); }},
        {"d5_ability", [](User* u, const char* v) { u->setAbility(4, std::atof(v)); }},
        {"d6_ability", [](User* u, const char* v) { u->setAbility(5, std::atof(v)); }},
        {"d7_ability", [](User* u, const char* v) { u->setAbility(6, std::atof(v)); }},
        {"d8_ability", [](User* u, const char* v) { u->setAbility(7, std::atof(v)); }},
        {"d9_ability", [](User* u, const char* v) { u->setAbility(8, std::atof(v)); }},
        {"d10_ability", [](User* u, const char* v) { u->setAbility(9, std::atof(v)); }},
        {"d1_base_ability", [](User* u, const char* v) { u->setBaseAbility(0, std::atof(v)); }},
        {"d2_base_ability", [](User* u, const char* v) { u->setBaseAbility(1, std::atof(v)); }},
        {"d3_base_ability", [](User* u, const char* v) { u->setBaseAbility(2, std::atof(v)); }},
        {"d4_base_ability", [](User* u, const char* v) { u->setBaseAbility(3, std::atof(v)); }},
        {"d5_base_ability", [](User* u, const char* v) { u->setBaseAbility(4, std::atof(v)); }},
        {"d6_base_ability", [](User* u, const char* v) { u->setBaseAbility(5, std::atof(v)); }},
        {"d7_base_ability", [](User* u, const char* v) { u->setBaseAbility(6, std::atof(v)); }},
        {"d8_base_ability", [](User* u, const char* v) { u->setBaseAbility(7, std::atof(v)); }},
        {"d9_base_ability", [](User* u, const char* v) { u->setBaseAbility(8, std::atof(v)); }},
        {"d10_base_ability", [](User* u, const char* v) { u->setBaseAbility(9, std::atof(v)); }},
        {"eta", [](User* u, const char* v) { u->setEta(std::atof(v)); }},
        {"d1_quiz_count", [](User* u, const char* v) { u->setQuizCount(0, std::atoi(v)); }},
        {"d2_quiz_count", [](User* u, const char* v) { u->setQuizCount(1, std::atoi(v)); }},
        {"d3_quiz_count", [](User* u, const char* v) { u->setQuizCount(2, std::atoi(v)); }},
        {"d4_quiz_count", [](User* u, const char* v) { u->setQuizCount(3, std::atoi(v)); }},
        {"d5_quiz_count", [](User* u, const char* v) { u->setQuizCount(4, std::atoi(v)); }},
        {"d6_quiz_count", [](User* u, const char* v) { u->setQuizCount(5, std::atoi(v)); }},
        {"d7_quiz_count", [](User* u, const char* v) { u->setQuizCount(6, std::atoi(v)); }},
        {"d8_quiz_count", [](User* u, const char* v) { u->setQuizCount(7, std::atoi(v)); }},
        {"d9_quiz_count", [](User* u, const char* v) { u->setQuizCount(8, std::atoi(v)); }},
        {"d10_quiz_count", [](User* u, const char* v) { u->setQuizCount(9, std::atoi(v)); }},
        {"last_read_time", [](User* u, const char* v) { u->setLastReadTime(static_cast<time_t>(std::atol(v))); }}
    };
    
    for (int i = 0; i < argc; i++) {
        if (argv[i]) {
            auto it = fieldMap.find(azColName[i]);
            if (it != fieldMap.end()) {
                it->second(user, argv[i]);
            }
        }
    }
    
    return 0;
}

bool UserRepository::getUser(User& user, int userId) {
    if (!db || !db->getConnection()) {
        return false;
    }
    
    const std::string sql = "SELECT d1_ability, d2_ability, d3_ability, d4_ability, "
                      "d5_ability, d6_ability, d7_ability, d8_ability, d9_ability, d10_ability, "
                      "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
                      "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
                      "d9_base_ability, d10_base_ability, eta, "
                      "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
                      "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
                      "last_read_time "
                      "FROM user WHERE id = " + std::to_string(userId) + ";";
    char* errMsg = nullptr;

    struct GetUserData { User* user; bool found = false; } gd = {&user, false};

    // 批次 4（明示排除）：裸 sqlite3_exec + C 回调 + errMsg 空指针风险，本次工作项 1 不动。
    // 该路径的 id 仍是字符串拼接 SQL（userId 为 int，无注入面），随批次 4 一并处理。
    int rc = sqlite3_exec(db->getConnection(), sql.c_str(), getUserCallback, &gd, &errMsg);
    
    if (rc != SQLITE_OK) {
        LOG_ERROR("查询用户失败: {}", errMsg);
        sqlite3_free(errMsg);
        return false;
    }
    
    return gd.found;
}

bool UserRepository::saveUser(const User& user, int userId) {
    // 单条 UPSERT：UPDATE 分支用 excluded.<col> 引用 INSERT 值，
    // 占位符只需一份（id + 32 能力列），避免手写两遍参数列表错位（N-x）
    std::vector<SqlParam> params;
    params.emplace_back(userId);
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getAbility(i));
    }
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getBaseAbility(i));
    }
    params.emplace_back(user.getEta());
    for (int i = 0; i < 10; ++i) {
        params.emplace_back(user.getQuizCount(i));
    }
    // 批次 4（明示排除）：last_read_time 列是 INTEGER，这里仍按 double 绑定
    // （recon-db-access.md §5.5）；改 int64 是可测的行为变化，不属本版「不改行为」边界。
    params.emplace_back(static_cast<double>(user.getLastReadTime()));

    return db->executeSQL(
"INSERT INTO user (id, "
        "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
        "d7_ability, d8_ability, d9_ability, d10_ability, "
        "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
        "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
        "d9_base_ability, d10_base_ability, eta, "
        "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
        "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
        "last_read_time) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
        "?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET "
        "d1_ability = excluded.d1_ability, d2_ability = excluded.d2_ability, "
        "d3_ability = excluded.d3_ability, d4_ability = excluded.d4_ability, "
        "d5_ability = excluded.d5_ability, d6_ability = excluded.d6_ability, "
        "d7_ability = excluded.d7_ability, d8_ability = excluded.d8_ability, "
        "d9_ability = excluded.d9_ability, d10_ability = excluded.d10_ability, "
        "d1_base_ability = excluded.d1_base_ability, "
        "d2_base_ability = excluded.d2_base_ability, "
        "d3_base_ability = excluded.d3_base_ability, "
        "d4_base_ability = excluded.d4_base_ability, "
        "d5_base_ability = excluded.d5_base_ability, "
        "d6_base_ability = excluded.d6_base_ability, "
        "d7_base_ability = excluded.d7_base_ability, "
        "d8_base_ability = excluded.d8_base_ability, "
        "d9_base_ability = excluded.d9_base_ability, "
        "d10_base_ability = excluded.d10_base_ability, "
        "eta = excluded.eta, "
        "d1_quiz_count = excluded.d1_quiz_count, "
        "d2_quiz_count = excluded.d2_quiz_count, "
        "d3_quiz_count = excluded.d3_quiz_count, "
        "d4_quiz_count = excluded.d4_quiz_count, "
        "d5_quiz_count = excluded.d5_quiz_count, "
        "d6_quiz_count = excluded.d6_quiz_count, "
        "d7_quiz_count = excluded.d7_quiz_count, "
        "d8_quiz_count = excluded.d8_quiz_count, "
        "d9_quiz_count = excluded.d9_quiz_count, "
        "d10_quiz_count = excluded.d10_quiz_count, "
        "last_read_time = excluded.last_read_time;",
        params
    );
}

namespace {

// 未删除档案数。返回 false = 查询失败（等价旧实现的 count < 0）。
// 有意不在 helper 内打日志：失败语义由调用点决定（createProfile 静默失败、
// createProfileInherit 与超限共用一条误导日志，见 recon-db-access.md §4.2）。
bool profileCountOk(DatabaseManager* db, int& count)
{
    std::vector<Row> rows;
    if (!db->queryRows("SELECT COUNT(*) FROM profiles WHERE deleted = 0;", rows) || rows.empty()) {
        return false;
    }
    count = static_cast<int>(rows[0].integer(0));
    return true;
}

// 未删除档案名是否可用。返回 false = 查询失败；available 仅在返回 true 时有效。
bool profileNameAvailable(DatabaseManager* db, const std::string& name, bool& available)
{
    std::vector<Row> rows;
    if (!db->queryRows("SELECT 1 FROM profiles WHERE deleted = 0 AND name = ?;",
                       std::vector<SqlParam>{name}, rows)) {
        return false;
    }
    available = rows.empty();
    return true;
}

}  // namespace

std::vector<ProfileInfo> UserRepository::listProfiles() {
    std::vector<ProfileInfo> out;
    if (!db || !db->getConnection()) return out;

    const char* sql = "SELECT id, name, deleted, created_at, last_used_at "
                      "FROM profiles WHERE deleted = 0 ORDER BY id ASC;";
    std::vector<Row> rows;
    if (!db->queryRows(sql, rows)) {
        LOG_ERROR("查询档案列表失败: {}", db->getLastError());
        return out;
    }

    out.reserve(rows.size());
    for (const Row& row : rows) {
        ProfileInfo p;
        p.id = static_cast<int>(row.integer("id"));
        p.name = row.text("name");  // NULL 列取空串，与旧回调的 if (name) 行为一致
        p.deleted = static_cast<int>(row.integer("deleted"));
        p.createdAt = row.integer("created_at");
        p.lastUsedAt = row.integer("last_used_at");
        out.push_back(std::move(p));
    }
    return out;
}

bool UserRepository::createProfile(const std::string& name, int& outId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    // 批次 4（明示排除）：裸 sqlite3_exec 事务控制 + err 空指针风险，本次不动
    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("createProfile BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    // 上限保护（防 UI 绕过/未来多端并发）：查询失败与旧实现一致——静默失败，不并进「已达上限」
    int count = 0;
    if (!profileCountOk(db, count)) {
        ok = false;
    } else if (count >= kMaxProfiles) {
        LOG_WARN("createProfile 已达上限 {} 个档案，拒绝创建 {}", kMaxProfiles, name);
        ok = false;
    }
    // 未删除档案同名拒绝（软删档案名可复用）
    if (ok) {
        bool available = false;
        if (!profileNameAvailable(db, name, available)) {
            ok = false;  // 查询失败：与旧 prepare 失败一致，不并进「重名拒绝」
        } else if (!available) {
            LOG_WARN("createProfile 重名拒绝: {}", name);
            ok = false;
        }
    }

    const int64_t now = static_cast<int64_t>(time(nullptr));
    if (ok && !db->executeSQL("INSERT INTO profiles(name, created_at, last_used_at, deleted) "
                              "VALUES (?, ?, ?, 0);",
                              std::vector<SqlParam>{name, now, now})) {
        ok = false;
    }
    if (ok) {
        outId = static_cast<int>(sqlite3_last_insert_rowid(c));
        // 能力等数据仍按 id 存 user 表：先建默认行，切换/首读时再初始化能力默认值
        if (!db->executeSQL("INSERT OR IGNORE INTO user(id) VALUES (?);",
                            std::vector<SqlParam>{outId})) {
            ok = false;
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::renameProfile(int userId, const std::string& name) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    // 同名拒绝（排除自身，仅未删除档案参与比较）
    const char* sql =
        "UPDATE profiles SET name = ? "
        "WHERE id = ? AND deleted = 0 "
        "AND NOT EXISTS (SELECT 1 FROM profiles WHERE deleted = 0 AND name = ? AND id <> ?);";
    Statement stmt(c, sql);
    if (!stmt.ok()) {
        LOG_ERROR("renameProfile prepare 失败: {}", stmt.error());
        return false;
    }
    if (!stmt.bind({name, userId, name, userId})) {
        return false;
    }
    const int rc = stmt.step();
    const int changes = sqlite3_changes(c);
    return rc == SQLITE_DONE && changes > 0;
}

namespace {

// 删除某档案在全部用户表中的数据（不含 profiles 行本身）。
bool deleteUserDataRows(sqlite3* c, int userId)
{
    const char* statements[] = {
        "DELETE FROM user WHERE id = ?;",
        "DELETE FROM reading_history WHERE user_id = ?;",
        "DELETE FROM text_tracking WHERE user_id = ?;",
        "DELETE FROM learning_increments WHERE user_id = ?;",
        "DELETE FROM quiz_attempts WHERE user_id = ?;",
        "DELETE FROM review_items WHERE user_id = ?;",
    };
    for (const char* sql : statements) {
        Statement stmt(c, sql);
        if (!stmt.ok()) {
            LOG_ERROR("deleteUserDataRows prepare 失败: {}", stmt.error());
            return false;
        }
        if (!stmt.bind({userId})) {
            LOG_ERROR("deleteUserDataRows 绑定失败: {}", stmt.error());
            return false;
        }
        const int rc = stmt.step();
        if (rc != SQLITE_DONE) {
            LOG_ERROR("deleteUserDataRows 执行失败 rc={}", rc);
            return false;
        }
    }
    return true;
}

}  // namespace

bool UserRepository::deleteProfile(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("deleteProfile BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    {
        Statement stmt(c, "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;");
        if (!stmt.ok()) {
            ok = false;
        } else if (!stmt.bind({userId})) {
            ok = false;
        } else {
            ok = stmt.step() == SQLITE_ROW;
        }
    }
    if (ok) {
        ok = deleteUserDataRows(c, userId);
    }
    if (ok) {
        Statement stmt(c, "DELETE FROM profiles WHERE id = ? AND deleted = 0;");
        if (!stmt.ok()) {
            ok = false;
        } else if (!stmt.bind({userId})) {
            ok = false;
        } else {
            const int rc = stmt.step();
            const int changes = sqlite3_changes(c);
            ok = rc == SQLITE_DONE && changes > 0;
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::purgeDeletedProfiles() {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    std::vector<int> ids;
    {
        std::vector<Row> rows;
        if (!db->queryRows("SELECT id FROM profiles WHERE deleted = 1;", rows)) {
            LOG_ERROR("purgeDeletedProfiles 查询失败: {}", db->getLastError());
            return false;
        }
        ids.reserve(rows.size());
        for (const Row& row : rows) {
            ids.push_back(static_cast<int>(row.integer("id")));
        }
    }
    if (ids.empty()) return true;

    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("purgeDeletedProfiles BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    for (const int id : ids) {
        if (!deleteUserDataRows(c, id)) {
            ok = false;
            break;
        }
        Statement del(c, "DELETE FROM profiles WHERE id = ? AND deleted = 1;");
        if (!del.ok()) {
            ok = false;
            break;
        }
        if (!del.bind({id})) {
            ok = false;
            break;
        }
        if (del.step() != SQLITE_DONE) {
            ok = false;
        }
        if (!ok) break;
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}

bool UserRepository::isProfileActive(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    Statement stmt(c, "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;");
    if (!stmt.ok()) return false;
    if (!stmt.bind({userId})) return false;
    return stmt.step() == SQLITE_ROW;
}

bool UserRepository::touchProfile(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    Statement stmt(c, "UPDATE profiles SET last_used_at = ? WHERE id = ? AND deleted = 0;");
    if (!stmt.ok()) return false;
    if (!stmt.bind({static_cast<int64_t>(time(nullptr)), userId})) return false;
    return stmt.step() == SQLITE_DONE;
}

bool UserRepository::ensureProfileExists(int userId, const std::string& name) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    const int64_t now = static_cast<int64_t>(time(nullptr));
    Statement stmt(c, "INSERT OR IGNORE INTO profiles(id, name, created_at, last_used_at, deleted) "
                      "VALUES (?, ?, ?, ?, 0);");
    if (!stmt.ok()) return false;
    if (!stmt.bind({userId, name, now, now})) return false;
    return stmt.step() == SQLITE_DONE;
}

bool UserRepository::isInitialized(int userId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();
    Statement stmt(c, "SELECT initialized FROM user WHERE id = ?;");
    if (!stmt.ok()) return false;
    if (!stmt.bind({userId})) return false;
    if (stmt.step() != SQLITE_ROW) return false;
    Row row;
    stmt.readRow(row);
    return row.integer("initialized") != 0;
}

bool UserRepository::setInitialized(int userId) {
    if (!db || !db->getConnection()) return false;
    return db->executeSQL(
        "UPDATE user SET initialized = 1 WHERE id = ?;",
        std::vector<SqlParam>{userId}
    );
}

bool UserRepository::createProfileInherit(const std::string& name, int sourceId, int& outId) {
    if (!db || !db->getConnection()) return false;
    sqlite3* c = db->getConnection();

    char* err = nullptr;
    if (sqlite3_exec(c, "BEGIN IMMEDIATE", nullptr, nullptr, &err) != SQLITE_OK) {
        LOG_ERROR("createProfileInherit BEGIN 失败: {}", err ? err : "?");
        sqlite3_free(err);
        return false;
    }

    bool ok = true;
    // 与 createProfile 相同的约束：上限、未删除档案重名拒绝。
    // 现状语义（recon §4.2）：查询失败与超限共用同一条「已达上限」误导日志；
    // 该合并只保留在调用点，helper 保持中性（返回是否查询成功）。
    int count = 0;
    if (!profileCountOk(db, count) || count >= kMaxProfiles) {
        LOG_WARN("createProfileInherit 已达上限 {} 个档案，拒绝创建 {}", kMaxProfiles, name);
        ok = false;
    }
    if (ok) {
        bool available = false;
        if (!profileNameAvailable(db, name, available)) {
            ok = false;
        } else if (!available) {
            LOG_WARN("createProfileInherit 重名拒绝: {}", name);
            ok = false;
        }
    }
    // 源档案必须存在、未删除
    if (ok) {
        Statement stmt(c, "SELECT 1 FROM profiles WHERE id = ? AND deleted = 0;");
        if (!stmt.ok()) {
            ok = false;
        } else if (!stmt.bind({sourceId})) {
            ok = false;
        } else if (stmt.step() != SQLITE_ROW) {
            LOG_WARN("createProfileInherit 源档案不存在或已删除 id={}", sourceId);
            ok = false;
        }
    }
    // 且已完成初始化
    if (ok) {
        Statement stmt(c, "SELECT initialized FROM user WHERE id = ?;");
        if (!stmt.ok()) {
            ok = false;
        } else if (!stmt.bind({sourceId})) {
            ok = false;
        } else {
            Row row;
            const bool hasRow = stmt.step() == SQLITE_ROW;
            if (hasRow) stmt.readRow(row);
            const bool initialized = hasRow && row.integer("initialized") != 0;
            if (!initialized) {
                LOG_WARN("createProfileInherit 源档案未完成初始化 id={}", sourceId);
                ok = false;
            }
        }
    }

    const int64_t now = static_cast<int64_t>(time(nullptr));
    if (ok && !db->executeSQL("INSERT INTO profiles(name, created_at, last_used_at, deleted) "
                              "VALUES (?, ?, ?, 0);",
                              std::vector<SqlParam>{name, now, now})) {
        ok = false;
    }
    if (ok) {
        outId = static_cast<int>(sqlite3_last_insert_rowid(c));
    }

    // 复制 user 能力（新档案 initialized=1）
    if (ok) {
        const char* sql =
            "INSERT INTO user (id, "
            "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
            "d7_ability, d8_ability, d9_ability, d10_ability, "
            "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
            "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
            "d9_base_ability, d10_base_ability, eta, "
            "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
            "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
            "last_read_time, initialized) "
            "SELECT ?, "
            "d1_ability, d2_ability, d3_ability, d4_ability, d5_ability, d6_ability, "
            "d7_ability, d8_ability, d9_ability, d10_ability, "
            "d1_base_ability, d2_base_ability, d3_base_ability, d4_base_ability, "
            "d5_base_ability, d6_base_ability, d7_base_ability, d8_base_ability, "
            "d9_base_ability, d10_base_ability, eta, "
            "d1_quiz_count, d2_quiz_count, d3_quiz_count, d4_quiz_count, d5_quiz_count, "
            "d6_quiz_count, d7_quiz_count, d8_quiz_count, d9_quiz_count, d10_quiz_count, "
            "last_read_time, 1 FROM user WHERE id = ?;";
        Statement u(c, sql);
        if (!u.ok()) {
            LOG_ERROR("createProfileInherit 复制 user 准备失败: {}", u.error());
            ok = false;
        } else if (!u.bind({outId, sourceId})) {
            ok = false;
        } else {
            ok = u.step() == SQLITE_DONE;
        }
    }

    // 复制各历史表（自增 id 不复制，user_id 改新档案 id）
    if (ok) {
        const char* copies[] = {
            "INSERT INTO reading_history (user_id, text_id, read_time, read_timestamp) "
            "SELECT ?, text_id, read_time, read_timestamp FROM reading_history WHERE user_id = ?;",
            "INSERT OR IGNORE INTO text_tracking (user_id, text_id, tracked_at) "
            "SELECT ?, text_id, tracked_at FROM text_tracking WHERE user_id = ?;",
            "INSERT INTO learning_increments (user_id, dimension, delta, timestamp, type) "
            "SELECT ?, dimension, delta, timestamp, type FROM learning_increments WHERE user_id = ?;",
            "INSERT INTO quiz_attempts (user_id, question_id, text_id, correct, is_review, is_init, answered_at) "
            "SELECT ?, question_id, text_id, correct, is_review, is_init, answered_at FROM quiz_attempts WHERE user_id = ?;",
            "INSERT OR IGNORE INTO review_items (user_id, question_id, text_id, correct_streak, wrong_count, next_review_at) "
            "SELECT ?, question_id, text_id, correct_streak, wrong_count, next_review_at FROM review_items WHERE user_id = ?;",
        };
        for (const char* sql : copies) {
            Statement s(c, sql);
            if (!s.ok()) {
                LOG_ERROR("createProfileInherit 复制表准备失败: {}", s.error());
                ok = false;
                break;
            }
            if (!s.bind({outId, sourceId})) {
                LOG_ERROR("createProfileInherit 复制表绑定失败: {}", s.error());
                ok = false;
                break;
            }
            if (s.step() != SQLITE_DONE) {
                LOG_ERROR("createProfileInherit 复制表失败: {}", s.error());
                ok = false;
            }
            if (!ok) break;
        }
    }

    // 自增序列对齐（profiles 已由 AUTOINCREMENT 自动维护，其余显式插入后保险对齐）
    if (ok) {
        // 批次 4（明示排除）：裸 sqlite3_exec（拼接表名，来源为硬编码白名单）
        for (const char* seqTable : {"reading_history", "learning_increments", "quiz_attempts", "profiles"}) {
            const std::string upd = "UPDATE sqlite_sequence SET seq = "
                "(SELECT COALESCE(MAX(id),0) FROM " + std::string(seqTable) + ") "
                "WHERE name='" + std::string(seqTable) + "'";
            sqlite3_exec(c, upd.c_str(), nullptr, nullptr, nullptr);  // 失败忽略（无序列条目正常）
        }
    }

    if (ok) {
        ok = sqlite3_exec(c, "COMMIT", nullptr, nullptr, &err) == SQLITE_OK;
    } else {
        sqlite3_exec(c, "ROLLBACK", nullptr, nullptr, nullptr);
    }
    sqlite3_free(err);
    return ok;
}
