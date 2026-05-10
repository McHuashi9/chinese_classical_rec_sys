#pragma once
#include <spdlog/sinks/base_sink.h>
#ifdef __APPLE__
#import <os/log.h>

template<typename Mutex>
class ios_log_sink final : public spdlog::sinks::base_sink<Mutex> {
protected:
    void sink_it_(const spdlog::details::log_msg& msg) override {
        spdlog::memory_buf_t formatted;
        spdlog::sinks::base_sink<Mutex>::formatter_->format(msg, formatted);
        formatted.push_back('\0');
        os_log_type_t osLevel = OS_LOG_TYPE_DEFAULT;
        switch (msg.level) {
            case spdlog::level::debug:   osLevel = OS_LOG_TYPE_DEBUG; break;
            case spdlog::level::info:    osLevel = OS_LOG_TYPE_INFO; break;
            case spdlog::level::warn:    osLevel = OS_LOG_TYPE_DEFAULT; break;
            case spdlog::level::err:     osLevel = OS_LOG_TYPE_ERROR; break;
            case spdlog::level::critical:osLevel = OS_LOG_TYPE_FAULT; break;
            default: break;
        }
        os_log_with_type(OS_LOG_DEFAULT, osLevel, "%{public}s", formatted.data());
    }
    void flush_() override {}
};
using ios_log_sink_mt = ios_log_sink<std::mutex>;
#endif
