#include "utils/Logger.h"

#ifdef __ANDROID__
#include <spdlog/sinks/android_sink.h>
#elif defined(__APPLE__)
#include "bridge/ios_log_sink.h"
#else
#include <nowide/iostream.hpp>
#include <nowide/convert.hpp>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <filesystem>
#include <chrono>
#endif

Logger& Logger::getInstance() {
    static Logger instance;
    return instance;
}

bool Logger::init(const std::string& logDir, const std::string& logFileName) {
    if (initialized_) {
        return true;
    }
    
    try {
#ifdef __ANDROID__
        auto android_sink = std::make_shared<spdlog::sinks::android_sink_mt>("chinese_core");
        android_sink->set_pattern("%v");
        logger_ = std::make_shared<spdlog::logger>("app", android_sink);
#elif defined(__APPLE__)
        auto os_sink = std::make_shared<ios_log_sink_mt>();
        os_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
        logger_ = std::make_shared<spdlog::logger>("app", os_sink);
#else
        std::filesystem::path logPath = std::filesystem::current_path() / logDir;
        if (!std::filesystem::exists(logPath)) {
            std::filesystem::create_directories(logPath);
        }
        
#ifdef _WIN32
        std::wstring logFilePath = (logPath / logFileName).wstring();
#else
        std::string logFilePath = (logPath / logFileName).string();
#endif
        
        auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
            logFilePath,
            100 * 1024,       // 100 KiB 轮转阈值
            3                  // 保留 3 个历史文件
        );
        file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %s(%#) %v");
        logger_ = std::make_shared<spdlog::logger>("app", file_sink);
#endif
        
        // 设置为默认 logger
        spdlog::set_default_logger(logger_);
        
        // 设置默认日志级别为 INFO
        spdlog::set_level(spdlog::level::info);
        
        // 启用调试宏
        spdlog::flush_on(spdlog::level::warn);
        
        initialized_ = true;
        
        // Session 标记 — 每次启动一条分隔线
        LOG_INFO("===== v{} 启动 =====", APP_VERSION);
        
        return true;
        
    } catch (const spdlog::spdlog_ex& ex) {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, "chinese_core", "日志初始化失败: %s", ex.what());
#elif defined(__APPLE__)
        fprintf(stderr, "日志初始化失败: %s\n", ex.what());
#else
        nowide::cerr << "日志初始化失败: " << ex.what() << std::endl;
#endif
        return false;
    }
}

std::shared_ptr<spdlog::logger> Logger::getLogger() const {
    return logger_;
}

void Logger::setLevel(const std::string& level) {
    if (level == "debug") {
        spdlog::set_level(spdlog::level::debug);
    } else if (level == "info") {
        spdlog::set_level(spdlog::level::info);
    } else if (level == "warn") {
        spdlog::set_level(spdlog::level::warn);
    } else if (level == "error") {
        spdlog::set_level(spdlog::level::err);
    }
}
