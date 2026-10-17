#ifndef BRIDGE_GUARD_H
#define BRIDGE_GUARD_H

#include <exception>
#include <mutex>
#include <utility>

#include "c_types.h"
#include "utils/Logger.h"

// 统一 FFI 出口门卫：加锁 + 异常防线。
// 目的：防止 C++ 异常穿越 extern "C" 边界造成 UB/进程崩溃。
// 各函数在业务体内先返回明确的业务错误码；ffi 层错误码单一权威源见 bridge/error_codes.def。
template <typename Fn>
int bridge_guard(std::mutex& mtx, Fn&& fn)
{
    std::lock_guard<std::mutex> lock(mtx);
    try {
        return std::forward<Fn>(fn)();
    } catch (const std::exception& e) {
        LOG_ERROR("bridge: 未捕获异常穿越 FFI 边界: {}", e.what());
    } catch (...) {
        LOG_ERROR("bridge: 未捕获未知异常穿越 FFI 边界");
    }
    return BRIDGE_ERR_GENERIC;
}

// void 返回符号的门卫重载：异常只记录，无法向调用方回错误码。
template <typename Fn>
void bridge_guard_void(std::mutex& mtx, Fn&& fn)
{
    std::lock_guard<std::mutex> lock(mtx);
    try {
        std::forward<Fn>(fn)();
    } catch (const std::exception& e) {
        LOG_ERROR("bridge: 未捕获异常穿越 FFI 边界: {}", e.what());
    } catch (...) {
        LOG_ERROR("bridge: 未捕获未知异常穿越 FFI 边界");
    }
}

#endif // BRIDGE_GUARD_H
