#ifndef C_TYPES_H
#define C_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 1)

/**
 * @brief C ABI 用户数据结构
 *
 * 对应 C++ User 类，10维能力向量 + 基础能力 + 姓名 + 最近阅读时间
 * dart:ffi 使用 @Packed(1) 确保与 C struct 字节对齐一致
 */
typedef struct {
    double abilities[10];        ///< d1-d10 当前能力值 [0, 1]
    double base_abilities[10];   ///< d1-d10 基础能力值 (遗忘极慢)
    double eta;                  ///< 悟性 η（答题效应动态调整，[0.02, 0.15]）
    int quiz_counts[10];         ///< d1-d10 累计答题次数 N_j
    int64_t last_read_time;      ///< 最后阅读时间 (Unix 时间戳)
} UserData;

/**
 * @brief C ABI 档案元数据结构（本地多用户）
 */
typedef struct {
    int id;                      ///< 档案 id（= user.id）
    char name[64];               ///< 档案名 (UTF-8)
    int64_t created_at;          ///< 创建时间 (Unix 时间戳)
    int64_t last_used_at;        ///< 最近使用时间 (Unix 时间戳)
    int deleted;                 ///< 软删标记（0=正常 1=已删除，列表仅返回未删除）
} ProfileData;

/**
 * @brief C ABI 文本摘要结构 (用于列表展示)
 */
typedef struct {
    int id;                      ///< 文本ID
    char title[256];             ///< 标题 (UTF-8)
    char author[128];            ///< 作者 (UTF-8)
    char dynasty[64];            ///< 朝代 (UTF-8)
    char source[64];             ///< 来源 (UTF-8)
} TextInfo;

/**
 * @brief C ABI 文本详情结构 (含全文 + 难度向量)
 */
typedef struct {
    int id;                      ///< 文本ID
    char title[256];             ///< 标题 (UTF-8)
    char author[128];            ///< 作者 (UTF-8)
    char dynasty[64];            ///< 朝代 (UTF-8)
    char source[64];             ///< 来源 (UTF-8)
    char background[2048];       ///< 背景介绍 (UTF-8)
    char content[65536];         ///< 正文 (UTF-8, 64KB)
    int char_count;              ///< 纯字数（去空白后）
    double difficulties[10];     ///< d1-d10 难度特征值
} TextDetail;

/**
 * @brief C ABI 阅读记录结构
 */
typedef struct {
    int id;
    int text_id;
    double read_time;
    int64_t timestamp;
} ReadingRecordData;

/**
 * @brief C ABI 题目结构（出题用，不下发 answer_index —— 判题只在 C++ 侧）
 */
typedef struct {
    int id;                       ///< 题 id（tracker_apply_quiz 判题用）
    char q_type[16];              ///< 题型 (shici / tongjia / fanyi)
    char stem[1024];              ///< 题干 (UTF-8)
    char options[4][512];         ///< 4 个选项 (UTF-8)
    char dims[64];                ///< dims CSV（0-based，如 "3,4,9"）
    char explanation[2048];       ///< 解析 (UTF-8，答完后展示)
    double difficulty;            ///< 题目难度 D_q
    char context[1024];           ///< 划线词所在原句 (UTF-8，空串表示无)
    int mark_start;               ///< 划线区间起点（context 内下标，无则 -1）
    int mark_len;                 ///< 划线区间长度（无则 0）
} QuestionData;

/**
 * @brief C ABI 复习条目结构（错题复习队列，quiz_get_review_items 用）
 */
typedef struct {
    int question_id;              ///< 错题 id（questions.id）
    int text_id;                  ///< 所属文章 id（复习列表按篇分组）
    int correct_streak;           ///< 连续答对次数（调度翻倍用）
    int wrong_count;              ///< 累计答错次数
    int64_t next_review_at;       ///< 下次到期时间（Unix 秒）
} ReviewItemData;

/**
 * @brief 错误码
 */
#define BRIDGE_OK              0   ///< 成功
#define BRIDGE_ERR_GENERIC    -1   ///< 通用错误
#define BRIDGE_ERR_NOT_INIT   -2   ///< 未初始化 (未调用 db_open)
#define BRIDGE_ERR_USER       -3   ///< 用户不存在
#define BRIDGE_ERR_TEXT       -4   ///< 文本不存在
#define BRIDGE_ERR_INIT       -5   ///< 初始化失败 (initTable 等)
#define BRIDGE_ERR_DB_CONTENT -6   ///< 内容库缺失/损坏/缺表/含旧用户表
#define BRIDGE_ERR_DB_USER    -7   ///< 用户库缺失/损坏
#define BRIDGE_ERR_DB_VERSION -8   ///< db_version 不兼容（0 或 >1）
#define BRIDGE_ERR_DB_SAME_PATH -9 ///< user.db 与 classical.db 同路径
#define BRIDGE_ERR_INIT_INCOMPLETE -10 ///< 强制初始化未完成时使用被禁止的功能

#pragma pack(pop)

#ifdef __cplusplus
}
#endif

#endif // C_TYPES_H
