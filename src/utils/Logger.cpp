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

namespace {
// A8：轮转参数提具名常量，取值与拆分前完全一致（100 KiB × 3）。
constexpr std::size_t kRotateMaxBytes = 100 * 1024;  // 单文件轮转阈值
constexpr std::size_t kRotateMaxFiles = 3;           // 保留的历史文件数
}  // namespace
#endif

Logger& Logger::getInstance() {
    static Logger instance;
    return instance;
}

bool Logger::init(const std::string& logDir, const std::string& logFileName) {
    (void)logDir;
    (void)logFileName;
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
            kRotateMaxBytes,
            kRotateMaxFiles
        );
        file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %s(%#) %v");
        logger_ = std::make_shared<spdlog::logger>("app", file_sink);
#endif
        
        // 设置为默认 logger
        spdlog::set_default_logger(logger_);
        
        // 设置默认日志级别为 INFO；A3：若 init 之前已显式下发过级别（UI prefs 前移），
        // 则沿用该级别，避免启动段被这里的默认 INFO 覆盖。
        applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
        
        // 启用调试宏
        spdlog::flush_on(spdlog::level::warn);
        
        initialized_ = true;
        
        // Session 标记 — 每次启动一条分隔线
#ifndef APP_VERSION
#define APP_VERSION ""
#endif
        LOG_INFO("===== v{} 启动 =====", APP_VERSION);
        
        return true;
        
    } catch (const std::exception& ex) {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, "chinese_core", "日志初始化失败: %s", ex.what());
#elif defined(__APPLE__)
        fprintf(stderr, "日志初始化失败: %s\n", ex.what());
#else
        // 文件日志不可用（如目录无写权限）时降级到 stderr，避免调用方异常
        nowide::cerr << "日志初始化失败: " << ex.what() << std::endl;
        try {
            logger_ = std::make_shared<spdlog::logger>(
                "app", std::make_shared<spdlog::sinks::stderr_color_sink_mt>());
            spdlog::set_default_logger(logger_);
        } catch (...) {}
#endif
        return false;
    }
}

void Logger::applyLevel(spdlog::level::level_enum level) {
    spdlog::set_level(level);
    if (logger_) {
        logger_->set_level(level);
    }
}

void Logger::setLevel(const std::string& level) {
    spdlog::level::level_enum target;
    if (level == "debug") {
        target = spdlog::level::debug;
    } else if (level == "info") {
        target = spdlog::level::info;
    } else if (level == "warn") {
        target = spdlog::level::warn;
    } else if (level == "error") {
        target = spdlog::level::err;
    } else {
        // 未知取值忽略（Dart 侧白名单归一属 A5，不在此处理）
        return;
    }

    // A3：记住显式级别，供之后才发生的 init 使用（P2-7「init 覆盖」）。
    levelOverride_ = target;
    hasLevelOverride_ = true;
    applyLevel(target);
}
