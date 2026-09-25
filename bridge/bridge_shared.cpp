// 桥层共享域（v1.4.0 工作项 3）：EngineState/S()/g_mtx + 跨域 helper + 事务 RAII。
//
// 本文件必须留在 `chinese_core` target 内（hidden visibility），见 bridge_internal.h 顶部说明。
// execRawSql 与 SqlTransaction 必须同址：原 SqlTransaction（bridge.cpp:142）依赖物理落在 quiz
// 域的 execRawSql（bridge.cpp:1395），按域直搬即断链（recon-bridge.md §5.1）。

#include "bridge_internal.h"

#include <algorithm>
#include <cstring>

namespace {

// 仅经 S() 暴露，避免 g_state 成为跨 TU 的可见全局符号
EngineState g_engine;

// 执行不返回结果集的 SQL；失败记日志（原 bridge.cpp:1395-1405）
bool execRawSql(sqlite3* db, const char* sql)
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

}  // namespace

EngineState& S()
{
    return g_engine;
}

std::mutex g_mtx;

// ─── helpers ───────────────────────────────────────────────────────────────────

void copyCString(char* dst, size_t dstSize, const char* src)
{
    if (!src || dstSize == 0) return;
    const size_t len = std::min(dstSize - 1, std::strlen(src));
    std::memcpy(dst, src, len);
    dst[len] = '\0';
}

void fillQuestionRow(const Row& row, QuestionData& out)
{
    std::memset(&out, 0, sizeof(out));
    out.id = static_cast<int>(row.integer("id"));
    out.text_id = static_cast<int>(row.integer("text_id"));
    copyCString(out.q_type, sizeof(out.q_type), row.text("q_type").c_str());
    copyCString(out.stem, sizeof(out.stem), row.text("stem").c_str());
    for (int i = 0; i < 4; i++) {
        copyCString(out.options[i], sizeof(out.options[0]),
                    row.text("opt" + std::to_string(i)).c_str());
    }
    copyCString(out.dims, sizeof(out.dims), row.text("dims").c_str());
    copyCString(out.explanation, sizeof(out.explanation), row.text("explanation").c_str());
    out.difficulty = row.real("difficulty");
    copyCString(out.context, sizeof(out.context), row.text("context").c_str());
    out.mark_start = static_cast<int>(row.integer("mark_start"));
    out.mark_len = static_cast<int>(row.integer("mark_len"));
}

void user_to_c(const User& src, UserData* dst)
{
    for (int i = 0; i < 10; i++) {
        dst->abilities[i] = src.getAbility(i);
        dst->base_abilities[i] = src.getBaseAbility(i);
        dst->quiz_counts[i] = src.getQuizCount(i);
    }
    dst->eta = src.getEta();
    dst->last_read_time = static_cast<int64_t>(src.getLastReadTime());
}

void c_to_user(const UserData* src, User& dst)
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
bool loadUserForActive(int userId)
{
    if (!S().initialized || !S().userRepo || !S().tracker) return false;

    User loaded;
    if (S().userRepo->getUser(loaded, userId)) {
        if (!loaded.hasAnyNonDefaultField()) {
            loaded.initializeDefault();
        }
    } else {
        loaded.initializeDefault();
    }

    S().tracker->setUserId(userId);
    S().tracker->applyForgettingEffect(loaded, time(nullptr));

    if (!S().userRepo->saveUser(loaded, userId)) {
        LOG_ERROR("bridge: 档案 {} 切换落库失败", userId);
        return false;
    }
    S().userRepo->touchProfile(userId);
    S().user = std::make_unique<User>(loaded);
    S().activeUserId = userId;
    LOG_INFO("bridge: 当前档案切换为 id={}", userId);
    return true;
}

// 强制初始化闸门：未初始化时返回 BRIDGE_ERR_INIT_INCOMPLETE（调用方负责持锁）
int requireInitialized()
{
    if (!S().initialized) return BRIDGE_ERR_NOT_INIT;
    if (!S().userRepo || !S().userRepo->isInitialized(S().activeUserId)) {
        return BRIDGE_ERR_INIT_INCOMPLETE;
    }
    return BRIDGE_OK;
}

// ─── 事务 RAII ─────────────────────────────────────────────────────────────────

SqlTransaction::SqlTransaction(DatabaseManager* dbManager, const char* beginSql)
    : db_(dbManager ? dbManager->getConnection() : nullptr),
      active_(db_ != nullptr && execRawSql(db_, beginSql))
{
}

SqlTransaction::~SqlTransaction()
{
    if (active_) execRawSql(db_, "ROLLBACK");
}

bool SqlTransaction::ok() const
{
    return active_;
}

bool SqlTransaction::commit()
{
    if (!active_) return false;
    if (execRawSql(db_, "COMMIT")) {
        active_ = false;
        return true;
    }
    return false;
}
