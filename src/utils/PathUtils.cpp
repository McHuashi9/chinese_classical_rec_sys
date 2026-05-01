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
    wchar_t path[MAX_PATH];
    DWORD len = GetModuleFileNameW(NULL, path, MAX_PATH);
    if (len == 0 || len >= MAX_PATH) {
        return std::filesystem::current_path();
    }
    return std::filesystem::path(path).parent_path();
#else
    char path[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len == -1) {
        return std::filesystem::current_path();
    }
    path[len] = '\0';
    return std::filesystem::path(path).parent_path();
#endif
}

std::filesystem::path getWritableRoot() {
#ifdef _WIN32
    return getExeDir();
#else
    const char* appimage = std::getenv("APPIMAGE");
    if (appimage && appimage[0] != '\0') {
        return std::filesystem::path(appimage).parent_path();
    }
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0') {
        return std::filesystem::path(home) / ".local" / "share" / "chinese_classical_rec_sys";
    }
    return getExeDir();
#endif
}

std::filesystem::path getDataDir() {
    auto dir = getWritableRoot() / "data";
    std::filesystem::create_directories(dir);
    return dir;
}

std::filesystem::path getDbPath() {
    return getDataDir() / "classical.db";
}

std::filesystem::path getBundledDbPath() {
    return getExeDir() / "data" / "classical.db";
}

std::filesystem::path getLogsDir() {
    auto dir = getWritableRoot() / "logs";
    std::filesystem::create_directories(dir);
    return dir;
}

std::filesystem::path getFontsDir() {
    return getExeDir() / "fonts";
}

std::filesystem::path getHistoryFilePath() {
    return getWritableRoot() / "history.txt";
}

} // namespace PathUtils
