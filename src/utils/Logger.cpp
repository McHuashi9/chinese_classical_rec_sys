#include "utils/Logger.h"
#include <nowide/iostream.hpp>
#include <nowide/convert.hpp>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <filesystem>

Logger& Logger::getInstance() {
    static Logger instance;
    return instance;
}

bool Logger::init(const std::string& logDir, const std::string& logFileName) {
    if (initialized_) {
        return true;
    }
    
    try {
        // 确保日志目录存在
        std::filesystem::path logPath = std::filesystem::current_path() / logDir;
        if (!std::filesystem::exists(logPath)) {
            std::filesystem::create_directories(logPath);
        }
        
#ifdef _WIN32
        // Windows 平台使用宽字符文件路径（配合 SPDLOG_WCHAR_FILENAMES）
        std::wstring logFilePath = (logPath / logFileName).wstring();
#else
        std::string logFilePath = (logPath / logFileName).string();
#endif
        
        // 创建文件日志 sink
        auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(logFilePath, true);
        
        // 设置日志格式: [时间] [级别] 消息
        file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
        
        // 创建 logger
        logger_ = std::make_shared<spdlog::logger>("app", file_sink);
        
        // 设置为默认 logger
        spdlog::set_default_logger(logger_);
        
        // 设置默认日志级别为 INFO
        spdlog::set_level(spdlog::level::info);
        
        // 启用调试宏
        spdlog::flush_on(spdlog::level::warn);
        
        initialized_ = true;
        return true;
        
    } catch (const spdlog::spdlog_ex& ex) {
        nowide::cerr << "日志初始化失败: " << ex.what() << std::endl;
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
