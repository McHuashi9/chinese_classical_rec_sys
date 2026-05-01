#pragma once

#include <filesystem>
#include <string>

namespace PathUtils {

/**
 * @brief 获取可执行文件所在目录（只读，如 AppImage 挂载点或安装目录）
 * @return 可执行文件目录的绝对路径
 */
std::filesystem::path getExeDir();

/**
 * @brief 获取可写运行时数据根目录
 * - Linux AppImage: $APPIMAGE 父目录（同便携模式）
 * - Linux 安装版: $HOME/.local/share/chinese_classical_rec_sys
 * - Windows: 可执行文件所在目录
 * @return 可写根目录的绝对路径（自动创建）
 */
std::filesystem::path getWritableRoot();

/**
 * @brief 获取可写 data 目录路径
 * @return <可写根>/data 的绝对路径
 */
std::filesystem::path getDataDir();

/**
 * @brief 获取可写数据库文件路径
 * @return <可写根>/data/classical.db 的绝对路径
 */
std::filesystem::path getDbPath();

/**
 * @brief 获取捆绑（只读）数据库文件路径（用于首次复制）
 * @return <exe目录>/data/classical.db 的绝对路径
 */
std::filesystem::path getBundledDbPath();

/**
 * @brief 获取日志目录路径
 * @return <可写根>/logs 的绝对路径
 */
std::filesystem::path getLogsDir();

/**
 * @brief 获取字体目录路径（只读，随程序分发）
 * @return <exe目录>/fonts 的绝对路径
 */
std::filesystem::path getFontsDir();

/**
 * @brief 获取命令历史文件路径
 * @return <可写根>/history.txt 的绝对路径
 */
std::filesystem::path getHistoryFilePath();

} // namespace PathUtils
