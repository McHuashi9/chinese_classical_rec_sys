#ifndef BRIDGE_INTERNAL_H
#define BRIDGE_INTERNAL_H

// bridge/ 内部分域头（v1.4.0 工作项 3）：承载 8 个域文件共享的
//   EngineState / S() / g_mtx / 共享 helper 声明 / SqlTransaction / 7 条 ABI static_assert。
//
// ⚠ 本头与 bridge_shared.cpp 必须留在 `chinese_core` target（CXX_VISIBILITY_PRESET hidden）内：
// 一旦把这些共享实现下沉到 src/，会以默认可见性泄漏新的 _Z* 符号，破坏 ABI 自检
// （见 recon-bridge.md §6；`src/` 只放 QuizRepository/ReviewRepository/ReviewScheduler 等
// 不含 QuestionData 等 FFI 结构体的纯数据/逻辑层）。

#include "c_types.h"
#include "bridge_guard.h"
#include "export.h"

#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "database/QuizRepository.h"
#include "database/ReviewRepository.h"
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "models/User.h"
#include "models/Text.h"
#include "utils/Logger.h"

#include <cstddef>
#include <ctime>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

// ─── 桥层全局状态 ───────────────────────────────────────────────────────────────
//
// 以 EngineState + S() 访问器取代裸 g_state：S() 定义于 bridge_shared.cpp，
// 避免 g_state 成为跨 TU 的可见全局符号（recon-bridge.md §5.5）。
// 字段 = 原 g_state 的 12 个 + 工作项 2 新增的 2 个仓储（quizRepo / reviewRepo）。
struct EngineState {
    std::unique_ptr<DatabaseManager> db;
    std::unique_ptr<UserRepository> userRepo;
    std::unique_ptr<TextRepository> textRepo;
    std::unique_ptr<ReadingHistoryRepository> historyRepo;
    std::unique_ptr<LearningIncrementRepository> incrementRepo;
    std::unique_ptr<QuizRepository> quizRepo;
    std::unique_ptr<ReviewRepository> reviewRepo;
    std::unique_ptr<RecommendationEngine> engine;
    std::unique_ptr<KnowledgeTracker> tracker;
    std::unique_ptr<User> user;
    std::unique_ptr<std::vector<Text>> texts;
    std::unique_ptr<std::unordered_map<int, size_t>> textIndex;
    int activeUserId = 1;
    bool initialized = false;
};

/** 全局状态访问器（定义于 bridge_shared.cpp） */
EngineState& S();

/** FFI 出口互斥锁（定义于 bridge_shared.cpp） */
extern std::mutex g_mtx;

// ─── C ABI 结构尺寸断言 ─────────────────────────────────────────────────────────
//
// 与 Dart @Packed(1) 布局保持一致（一旦 pack 丢失会静默错位）。
// 7 个结构全覆盖（Dart 侧见 flutter_app/test/engine/c_types_layout_test.dart 的 sizeOf 断言）。
// 8 个域 TU 各校验一次。
static_assert(sizeof(UserData) == 216, "UserData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(TextInfo) == 516, "TextInfo ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(TextDetail) == 68184, "TextDetail ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ReadingRecordData) == 24, "ReadingRecordData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(QuestionData) == 6248, "QuestionData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ReviewItemData) == 24, "ReviewItemData ABI 尺寸不符，检查 #pragma pack");
static_assert(sizeof(ProfileData) == 88, "ProfileData ABI 尺寸不符，检查 #pragma pack");

// ─── 跨域共享 helper（全部定义于 bridge_shared.cpp） ────────────────────────────

/** 定长缓冲拷贝：src 为 NULL/空串时只保证 dst 已被调用方清零 */
void copyCString(char* dst, size_t dstSize, const char* src);

/**
 * @brief Row → QuestionData 回填（工作项 4 去重：取代原三份 14 行逐字重复的映射体）
 *
 * 依赖 questions 查询的列清单见 src/database/QuizRepository.cpp 的
 * `QUESTION_SELECT_COLUMNS`（表达式列已 `AS opt0..opt3`）。进入时先 memset 清零。
 */
void fillQuestionRow(const Row& row, QuestionData& out);

void user_to_c(const User& src, UserData* dst);
void c_to_user(const UserData* src, User& dst);

/** 载入指定档案为当前用户（调用方负责持锁）；定义于 bridge_shared.cpp */
bool loadUserForActive(int userId);

/** 强制初始化闸门：未初始化/未完成初始化分别返回对应错误码（调用方负责持锁） */
int requireInitialized();

// ─── 事务 RAII ─────────────────────────────────────────────────────────────────

/**
 * @brief 事务 RAII：确保异常/提前退出时不会把事务悬空在 sqlite 连接上
 *
 * 正常提交后析构不再回滚；未提交析构自动 ROLLBACK。
 * v1.4.0 工作项 2/3：与 execRawSql 一起上提到 bridge_shared.cpp（原 SqlTransaction 在桥头、
 * execRawSql 却物理落在 quiz 域，直搬即断链——recon-bridge.md §5.1）。
 * 接收 DatabaseManager 而非裸 sqlite3*：桥层业务域不再直接取连接。
 */
class SqlTransaction {
public:
    SqlTransaction(DatabaseManager* dbManager, const char* beginSql);
    ~SqlTransaction();

    bool ok() const;
    bool commit();

private:
    sqlite3* db_;
    bool active_;
};

#endif  // BRIDGE_INTERNAL_H
