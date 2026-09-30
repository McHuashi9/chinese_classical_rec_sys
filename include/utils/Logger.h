#ifndef LOGGER_H
#define LOGGER_H

#include <spdlog/spdlog.h>
#include <memory>
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
     * @return true 初始化成功，false 初始化失败
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
    
    // 禁止拷贝和赋值
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
    
private:
    Logger() = default;
    ~Logger() = default;

    /** @brief 同时作用于 spdlog 全局级别与当前 logger */
    void applyLevel(spdlog::level::level_enum level);

    std::shared_ptr<spdlog::logger> logger_;
    bool initialized_ = false;
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
