// 桥层日志域（v1.4.0 工作项 3）：log_write / log_set_level，共 2 个导出符号。

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
    LOG_INFO("bridge: 日志级别切换为 {}", level);
    });
}
