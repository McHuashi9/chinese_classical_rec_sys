#include "core/LogCommand.h"
#include "utils/Logger.h"
#include <nowide/iostream.hpp>
#include <algorithm>

LogCommand::LogCommand() {}

bool LogCommand::execute(const std::vector<std::string>& args) {
    if (args.empty()) {
        showUsage();
        return true;
    }
    
    std::string level = args[0];
    // 转换为小写
    std::transform(level.begin(), level.end(), level.begin(), ::tolower);
    
    if (level != "debug" && level != "info" && level != "warn" && level != "error") {
        nowide::cout << "无效的日志等级: " << args[0] << "\n";
        nowide::cout << "可用等级: debug, info, warn, error\n";
        return true;
    }
    
    Logger::getInstance().setLevel(level);
    nowide::cout << "日志等级已设置为: " << level << "\n";
    return true;
}

void LogCommand::showUsage() {
    nowide::cout << "用法: log [等级]\n";
    nowide::cout << "设置日志输出等级。\n\n";
    nowide::cout << "可用等级:\n";
    nowide::cout << "  debug - 显示所有日志（调试用）\n";
    nowide::cout << "  info  - 显示信息及更高级别（默认）\n";
    nowide::cout << "  warn  - 显示警告和错误\n";
    nowide::cout << "  error - 仅显示错误\n";
}
