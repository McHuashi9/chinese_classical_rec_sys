#include "utils/Logger.h"

#ifdef __ANDROID__
#include <spdlog/sinks/android_sink.h>
#elif defined(__APPLE__)
#include "bridge/ios_log_sink.h"
#else
#include <nowide/iostream.hpp>
#include <nowide/convert.hpp>
#include <spdlog/sinks/stdout_color_sinks.h>
#endif

#include <spdlog/sinks/rotating_file_sink.h>
#include <filesystem>
#include <string>

#if defined(__ANDROID__) || defined(__APPLE__)
#include <spdlog/sinks/dist_sink.h>
#endif

namespace {
// 轮转参数（100 KiB × 3）提为具名常量。
constexpr std::size_t kRotateMaxBytes = 100 * 1024;  // 单文件轮转阈值
constexpr std::size_t kRotateMaxFiles = 3;           // 保留的历史文件数

#ifdef __ANDROID__
constexpr const char* kAndroidTag = "chinese_core";
#endif

std::string normalizeLogDir(const std::string& logDir)
{
    try {
        return std::filesystem::absolute(logDir).lexically_normal().string();
    } catch (...) {
        return logDir;
    }
}

std::shared_ptr<spdlog::sinks::sink> makeFileSink(
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
    return file_sink;
}

#if !defined(__ANDROID__) && !defined(__APPLE__)
std::shared_ptr<spdlog::logger> makeFileLogger(
    const std::string& logPath, const std::string& logFileName)
{
    return std::make_shared<spdlog::logger>("app", makeFileSink(logPath, logFileName));
}
#endif

#if defined(__ANDROID__) || defined(__APPLE__)
std::shared_ptr<spdlog::sinks::sink> makeSystemSink()
{
#ifdef __ANDROID__
    auto sink = std::make_shared<spdlog::sinks::android_sink_mt>(kAndroidTag);
    sink->set_pattern("%v");
#else
    auto sink = std::make_shared<ios_log_sink_mt>();
    sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
#endif
    return sink;
}
#endif
}  // namespace

Logger& Logger::getInstance() {
    static Logger instance;
    return instance;
}

bool Logger::init(const std::string& logDir, const std::string& logFileName) {
    std::lock_guard<std::mutex> lock(mutex_);

#if defined(__ANDROID__) || defined(__APPLE__)
    const std::string normalizedDir = normalizeLogDir(logDir);

    // 同目录且文件 sink 可用时幂等；上次文件 sink 失败（currentLogDir_ 为空）会重试。
    if (initialized_ && !currentLogDir_.empty() && currentLogDir_ == normalizedDir) {
        return true;
    }

    std::shared_ptr<spdlog::sinks::sink> systemSink;
    try {
        systemSink = makeSystemSink();
    } catch (const std::exception& ex) {
        if (initialized_) {
            LOG_WARN("日志系统 sink 重建失败，保留旧 sink: {}", ex.what());
            return false;
        }
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, kAndroidTag, "日志初始化失败: %s", ex.what());
#else
        fprintf(stderr, "日志初始化失败: %s\n", ex.what());
#endif
        return false;
    }

    std::shared_ptr<spdlog::logger> nextLogger;
    bool fileReady = false;
    std::string fileError;
    try {
        auto dist = std::make_shared<spdlog::sinks::dist_sink_mt>();
        dist->add_sink(systemSink);
        dist->add_sink(makeFileSink(normalizedDir, logFileName));
        nextLogger = std::make_shared<spdlog::logger>("app", dist);
        fileReady = true;
    } catch (const std::exception& ex) {
        fileError = ex.what();
        if (initialized_) {
            // 已有可用 logger 时，重建失败保留旧 sink。
            LOG_WARN("日志文件 sink 重建失败，保留旧 sink: {}", fileError);
            return false;
        }
        try {
            nextLogger = std::make_shared<spdlog::logger>("app", systemSink);
        } catch (const std::exception& ex2) {
#ifdef __ANDROID__
            __android_log_print(ANDROID_LOG_ERROR, kAndroidTag, "日志初始化失败: %s", ex2.what());
#else
            fprintf(stderr, "日志初始化失败: %s\n", ex2.what());
#endif
            return false;
        }
    }

    logger_ = std::move(nextLogger);
    spdlog::set_default_logger(logger_);
    applyLevel(hasLevelOverride_ ? levelOverride_ : spdlog::level::info);
    spdlog::flush_on(spdlog::level::warn);
    initialized_ = true;
    currentLogDir_ = fileReady ? normalizedDir : std::string();

    if (!fileReady) {
        LOG_WARN("日志文件 sink 初始化失败，降级到系统日志: {}", fileError);
        return false;
    }

#ifndef APP_VERSION
#define APP_VERSION ""
#endif
    LOG_INFO("===== v{} 启动 =====", APP_VERSION);
    return true;
#else
    const std::string normalizedDir = normalizeLogDir(logDir);

    // 同目录幂等；异目录先建新 sink，成功后再替换，失败保留旧 sink。
    if (initialized_) {
        if (currentLogDir_ == normalizedDir) {
            return true;
        }
        try {
            auto nextLogger = makeFileLogger(normalizedDir, logFileName);
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
        logger_ = makeFileLogger(normalizedDir, logFileName);
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
