#include "utils/PathUtils.h"
#include <nowide/convert.hpp>
#include <limits.h>
#include <iostream>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <linux/limits.h>
#endif

namespace PathUtils {

std::filesystem::path getExeDir() {
#ifdef _WIN32
    // Windows 平台使用宽字符 API 获取可执行文件路径，正确处理中文路径
    wchar_t path[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        // 失败时回退到当前工作目录
        return std::filesystem::current_path();
    }
    // std::filesystem::path 内部正确处理宽字符，跨平台安全
    return std::filesystem::path(path).parent_path();
#else
    // Linux 平台使用 readlink 获取可执行文件路径
    char path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len == -1) {
        // 失败时回退到当前工作目录
        return std::filesystem::current_path();
    }
    path[len] = '\0';
    return std::filesystem::path(path).parent_path();
#endif
}

std::filesystem::path getDataDir() {
    return getExeDir() / "data";
}

std::filesystem::path getDbPath() {
    return getDataDir() / "classical.db";
}

std::filesystem::path getLogsDir() {
    return getExeDir() / "logs";
}

std::filesystem::path getHistoryFilePath() {
#ifdef _WIN32
    // Windows: 优先使用 %APPDATA%，回退到 %USERPROFILE%
    const char* appdata = std::getenv("APPDATA");
    if (appdata && appdata[0] != '\0') {
        std::filesystem::path dir = std::filesystem::path(appdata) / "chinese_classical_rec_sys";
        std::filesystem::create_directories(dir);
        return dir / "history.txt";
    }
    const char* userprofile = std::getenv("USERPROFILE");
    if (userprofile && userprofile[0] != '\0') {
        return std::filesystem::path(userprofile) / ".chinese_classical_history";
    }
#else
    // Linux/macOS: 使用 $HOME
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        return std::filesystem::path(home) / ".chinese_classical_history";
    }
#endif
    // 回退：可执行文件目录
    return getExeDir() / ".history";
}

} // namespace PathUtils
