#pragma once

#include <filesystem>
#include <string>

namespace PathUtils {

/**
 * @brief 获取可执行文件所在目录
 * @return 可执行文件目录的绝对路径
 */
std::filesystem::path getExeDir();

/**
 * @brief 获取 data 目录路径
 * @return data 目录的绝对路径
 */
std::filesystem::path getDataDir();

/**
 * @brief 获取数据库文件完整路径
 * @return 数据库文件的绝对路径
 */
std::filesystem::path getDbPath();

/**
 * @brief 获取日志目录路径
 * @return logs 目录的绝对路径
 */
std::filesystem::path getLogsDir();

/**
 * @brief 获取命令历史文件路径（跨平台）
 * - Windows: %APPDATA%/chinese_classical_rec_sys/history.txt
 * - Linux/macOS: ~/.chinese_classical_history
 * - 回退: <exe_dir>/.history
 * @return 历史文件的绝对路径
 */
std::filesystem::path getHistoryFilePath();

} // namespace PathUtils
