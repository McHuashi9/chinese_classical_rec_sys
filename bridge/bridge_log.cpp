// 桥层日志域：log_write / log_set_level，共 2 个导出符号。

#include "bridge_internal.h"

extern "C" CHINESE_CORE_EXPORT void log_write(int level, const char* message)
{
    bridge_guard_void(g_mtx, [&] {
    switch (level) {
        case 0: LOG_DEBUG("{}", message); break;
        case 1: LOG_INFO("{}", message);  break;
        case 2: LOG_WARN("{}", message);  break;
        case 3: LOG_ERROR("{}", message); break;
        default: LOG_INFO("{}", message); break;
    }
    });
}

extern "C" CHINESE_CORE_EXPORT void log_set_level(const char* level)
{
    bridge_guard_void(g_mtx, [&] {
    Logger::getInstance().setLevel(level);
    // A3：回执必须不被“刚切到的级别”自己过滤掉——切到 error 时若用 INFO 打，
    // 这条回执会消失、切换无据可查。用 ERROR 级保证任何合法级别下都可见
    //（不新增导出符号；级别值域仍是 debug/info/warn/error 四档）。
    LOG_ERROR("bridge: 日志级别切换为 {}", level);
    });
}
