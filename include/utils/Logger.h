#ifndef LOGGER_H
#define LOGGER_H

#include <spdlog/spdlog.h>
#include <memory>
#include <mutex>
#include <string>

/**
 * @brief 日志系统封装类（单例模式）
 *
 * 基于 spdlog 实现文件日志输出，支持 DEBUG/INFO/WARN/ERROR 四个级别。
 * 实际日志目录跟随 [init] 的 logDir 参数，不写死 logs/app.log。
 */
class Logger {
public:
    /**
     * @brief 获取 Logger 单例实例
     * @return Logger& 单例引用
     */
    static Logger& getInstance();

    /**
     * @brief 初始化日志系统
     * @param logDir 日志目录路径，默认为 "logs"
     * @param logFileName 日志文件名，默认为 "app.log"
     * @return true 全部 sink 就绪；false 初始化失败或文件 sink 降级（系统 sink 可能仍可用）
     *
     * 桌面端：同目录重复 init 幂等；目录变化时创建新 sink，成功后替换，
     * 失败保留旧 sink。
     *
     * Android/iOS：系统 sink + 文件 sink 双写。同目录且文件 sink 可用时幂等；
     * 目录变化时先建新 sink，成功后替换，失败保留旧 sink。文件 sink 失败但系统
     * sink 可用时，日志仍写入系统日志，返回 false 供调用方记录降级。
     */
    bool init(const std::string& logDir = "logs",
              const std::string& logFileName = "app.log");

    /**
     * @brief 设置日志级别
     * @param level 日志级别（debug/info/warn/error）；未知取值忽略
     *
     * A3：级别会被记住，供之后才发生的 [init] 使用（避免启动段被默认 INFO 覆盖）。
     */
    void setLevel(const std::string& level);

    /**
     * @brief 测试专用：清空单例内部 sink 与初始化状态。
     *
     * 不导出 C ABI；仅供 Catch2 用例隔离 Logger 单例状态。生产代码不应调用。
     */
    void resetForTest();

    // 禁止拷贝和赋值
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;

private:
    Logger() = default;
    ~Logger() = default;

    /** @brief 同时作用于 spdlog 全局级别与当前 logger */
    void applyLevel(spdlog::level::level_enum level);

    std::mutex mutex_;
    std::shared_ptr<spdlog::logger> logger_;
    bool initialized_ = false;
    /// 当前文件 sink 对应的规范化目录；文件 sink 不可用时为空。
    std::string currentLogDir_;
    /// A3：init 之前是否已显式下发过级别，以及该级别。
    bool hasLevelOverride_ = false;
    spdlog::level::level_enum levelOverride_ = spdlog::level::info;
};

// 便捷日志宏
#define LOG_DEBUG(...)    SPDLOG_DEBUG(__VA_ARGS__)
#define LOG_INFO(...)     SPDLOG_INFO(__VA_ARGS__)
#define LOG_WARN(...)     SPDLOG_WARN(__VA_ARGS__)
#define LOG_ERROR(...)    SPDLOG_ERROR(__VA_ARGS__)

#endif // LOGGER_H
