#ifndef BRIDGE_LOG_REDACT_H
#define BRIDGE_LOG_REDACT_H

#include <string>

namespace bridge_log {

/// 日志脱敏：绝对/相对文件路径只保留 basename，避免写入用户名与完整目录。
/// 同时处理 POSIX `/` 与 Windows `\` 分隔符，便于跨平台测试。
inline std::string redactPath(const std::string& path)
{
    if (path.empty()) return "<path>";
    const auto pos = path.find_last_of("/\\");
    const std::string base = (pos == std::string::npos) ? path : path.substr(pos + 1);
    return base.empty() ? "<path>" : ("<appdata>/" + base);
}

}  // namespace bridge_log

#endif  // BRIDGE_LOG_REDACT_H
