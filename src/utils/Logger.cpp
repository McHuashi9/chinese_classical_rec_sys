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

namespace {
#ifdef __ANDROID__
constexpr const char* kAndroidTag = "chinese_core";
#elif !defined(__APPLE__)
// 轮转参数（100 KiB × 3）提为具名常量。
constexpr std::size_t kRotateMaxBytes = 100 * 1024;  // 单文件轮转阈值
constexpr std::size_t kRotateMaxFiles = 3;           // 保留的历史文件数

std::string normalizeDesktopLogDir(const std::string& logDir)
{
    try {
        return std::filesystem::absolute(logDir).lexically_normal().string();
    } catch (...) {
        return logDir;
    }
}

std::shared_ptr<spdlog::logger> makeDesktopFileLogger(
    const std::string& logPath, const std::string& logFileName)
{
    std::filesystem::create_directories(logPath);
#ifdef _WIN32
    const std::wstring logFilePath = (std::filesystem::path(logPath) / logFileName).wstring();
#else
    const std::string logFilePath = (std::filesystem::path(logPath) / logFileName).string();
#endif
    auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
        logFilePath, kRotateMaxBytes, kRotateMaxFiles);
    file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %s(%#) %v");
    return std::make_shared<spdlog::logger>("app", file_sink);
}
#endif
}  // namespace

Logger& Logger::getInstance() {
    static Logger instance;
    return instance;
}

bool Logger::init(const std::string& logDir, const std::string& logFileName) {
    std::lock_guard<std::mutex> lock(mutex_);

#ifdef __ANDROID__
    (void)logDir;
    (void)logFileName;
    if (initialized_) {
        return true;
    }
    try {
        auto android_sink = std::make_shared<spdlog::sinks::android_sink_mt>(kAndroidTag);
        android_sink->set_pattern("%v");
        logger_ = std::make_shared<spdlog::logger>("app", android_sink);
        spdlog::set_default_logger(logger_);
        applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
        spdlog::flush_on(spdlog::level::warn);
        initialized_ = true;
#ifndef APP_VERSION
#define APP_VERSION ""
#endif
        LOG_INFO("===== v{} 启动 =====", APP_VERSION);
        return true;
    } catch (const std::exception& ex) {
        __android_log_print(ANDROID_LOG_ERROR, kAndroidTag, "日志初始化失败: %s", ex.what());
        return false;
    }
#elif defined(__APPLE__)
    (void)logDir;
    (void)logFileName;
    if (initialized_) {
        return true;
    }
    try {
        auto os_sink = std::make_shared<ios_log_sink_mt>();
        os_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
        logger_ = std::make_shared<spdlog::logger>("app", os_sink);
        spdlog::set_default_logger(logger_);
        applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
        spdlog::flush_on(spdlog::level::warn);
        initialized_ = true;
#ifndef APP_VERSION
#define APP_VERSION ""
#endif
        LOG_INFO("===== v{} 启动 =====", APP_VERSION);
        return true;
    } catch (const std::exception& ex) {
        fprintf(stderr, "日志初始化失败: %s\n", ex.what());
        return false;
    }
#else
    const std::string normalizedDir = normalizeDesktopLogDir(logDir);

    // 同目录幂等；异目录先建新 sink，成功后再替换，失败保留旧 sink。
    if (initialized_) {
        if (currentLogDir_ == normalizedDir) {
            return true;
        }
        try {
            auto nextLogger = makeDesktopFileLogger(normalizedDir, logFileName);
            logger_ = std::move(nextLogger);
            currentLogDir_ = normalizedDir;
            spdlog::set_default_logger(logger_);
            applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
            spdlog::flush_on(spdlog::level::warn);
            LOG_INFO("===== 日志目录切换 =====");
            return true;
        } catch (const std::exception&) {
            // 保留旧 logger/sink，调用方可据返回值记录失败。
            return false;
        }
    }

    try {
        logger_ = makeDesktopFileLogger(normalizedDir, logFileName);
        currentLogDir_ = normalizedDir;
        spdlog::set_default_logger(logger_);
        applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
        spdlog::flush_on(spdlog::level::warn);
        initialized_ = true;
#ifndef APP_VERSION
#define APP_VERSION ""
#endif
        LOG_INFO("===== v{} 启动 =====", APP_VERSION);
        return true;
    } catch (const std::exception& ex) {
        // 文件日志不可用（如目录无写权限）时降级到 stderr，避免调用方异常。
        nowide::cerr << "日志初始化失败: " << ex.what() << std::endl;
        try {
            logger_ = std::make_shared<spdlog::logger>(
                "app", std::make_shared<spdlog::sinks::stderr_color_sink_mt>());
            spdlog::set_default_logger(logger_);
            applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
        } catch (...) {}
        currentLogDir_.clear();
        initialized_ = false;
        return false;
    }
#endif
}

void Logger::applyLevel(spdlog::level::level_enum level) {
    spdlog::set_level(level);
    if (logger_) {
        logger_->set_level(level);
    }
}

void Logger::setLevel(const std::string& level) {
    std::lock_guard<std::mutex> lock(mutex_);
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
        // 未知取值忽略（Dart 侧白名单归一，不在此处理）
        return;
    }

    // 记住显式级别，供之后才发生的 init 使用（否则 init 会把级别覆盖回默认）。
    levelOverride_ = target;
    hasLevelOverride_ = true;
    applyLevel(target);
}

void Logger::resetForTest() {
    std::lock_guard<std::mutex> lock(mutex_);
    logger_.reset();
    initialized_ = false;
    currentLogDir_.clear();
    hasLevelOverride_ = false;
    levelOverride_ = spdlog::level::info;
}
