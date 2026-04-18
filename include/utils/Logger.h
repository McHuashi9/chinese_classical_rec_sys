#ifndef LOGGER_H
#define LOGGER_H

#include <spdlog/spdlog.h>
#include <memory>
#include <string>

/**
 * @brief 日志系统封装类（单例模式）
 * 
 * 基于 spdlog 实现文件日志输出，支持 DEBUG/INFO/WARN/ERROR 四个级别。
 * 日志输出到 logs/app.log 文件。
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
     * @brief 获取底层 spdlog logger
     * @return std::shared_ptr<spdlog::logger> logger 智能指针
     */
    std::shared_ptr<spdlog::logger> getLogger() const;
    
    /**
     * @brief 设置日志级别
     * @param level 日志级别（debug/info/warn/error）
     */
    void setLevel(const std::string& level);
    
    // 禁止拷贝和赋值
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
    
private:
    Logger() = default;
    ~Logger() = default;
    
    std::shared_ptr<spdlog::logger> logger_;
    bool initialized_ = false;
};

// 便捷日志宏
#define LOG_DEBUG(...)    SPDLOG_DEBUG(__VA_ARGS__)
#define LOG_INFO(...)     SPDLOG_INFO(__VA_ARGS__)
#define LOG_WARN(...)     SPDLOG_WARN(__VA_ARGS__)
#define LOG_ERROR(...)    SPDLOG_ERROR(__VA_ARGS__)

#endif // LOGGER_H
