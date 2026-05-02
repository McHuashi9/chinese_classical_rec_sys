#ifndef C_TYPES_H
#define C_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief C ABI 用户数据结构
 *
 * 对应 C++ User 类，10维能力向量 + 基础能力 + 姓名 + 最近阅读时间
 * dart:ffi 使用 @Packed(1) 确保与 C struct 字节对齐一致
 */
typedef struct {
    char name[128];              ///< 用户名 (UTF-8)
    double abilities[10];        ///< d1-d10 当前能力值 [0, 1]
    double base_abilities[10];   ///< d1-d10 基础能力值 (遗忘极慢)
    int64_t last_read_time;      ///< 最后阅读时间 (Unix 时间戳)
} UserData;

/**
 * @brief C ABI 文本摘要结构 (用于列表展示)
 */
typedef struct {
    int id;                      ///< 文本ID
    char title[256];             ///< 标题 (UTF-8)
    char author[128];            ///< 作者 (UTF-8)
    char dynasty[64];            ///< 朝代 (UTF-8)
} TextInfo;

/**
 * @brief C ABI 文本详情结构 (含全文 + 难度向量)
 */
typedef struct {
    int id;                      ///< 文本ID
    char title[256];             ///< 标题 (UTF-8)
    char author[128];            ///< 作者 (UTF-8)
    char dynasty[64];            ///< 朝代 (UTF-8)
    char content[65536];         ///< 正文 (UTF-8, 64KB)
    double difficulties[10];     ///< d1-d10 难度特征值
} TextDetail;

/**
 * @brief 错误码
 */
#define BRIDGE_OK              0   ///< 成功
#define BRIDGE_ERR_GENERIC    -1   ///< 通用错误
#define BRIDGE_ERR_NOT_INIT   -2   ///< 未初始化 (未调用 db_open)
#define BRIDGE_ERR_USER       -3   ///< 用户不存在
#define BRIDGE_ERR_TEXT       -4   ///< 文本不存在

#ifdef __cplusplus
}
#endif

#endif // C_TYPES_H
