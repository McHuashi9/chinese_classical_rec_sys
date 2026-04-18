#include "core/HelpCommand.h"
#include <nowide/iostream.hpp>

HelpCommand::HelpCommand() {}

bool HelpCommand::execute(const std::vector<std::string>& args) {
    if (args.empty()) {
        showAllHelp();
    } else {
        showCommandHelp(args[0]);
    }
    return true;
}

void HelpCommand::showAllHelp() {
    nowide::cout << "\n可用命令：\n";
    nowide::cout << "  help [命令]       显示帮助信息\n";
    nowide::cout << "  library           显示古文库中的文章列表\n";
    nowide::cout << "  recommend [N]     推荐适合您能力水平的文章（默认10篇）\n";
    nowide::cout << "  read <文章ID>     阅读指定文章并更新能力值\n";
    nowide::cout << "  log [等级]        设置日志等级（debug/info/warn/error）\n";
    nowide::cout << "  exit              退出程序\n\n";

    nowide::cout << "输入 'help 命令名' 查看特定命令的详细用法。\n";
}


void HelpCommand::showCommandHelp(const std::string& cmd) {
    if (cmd == "help") {
        nowide::cout << "用法: help [命令名]\n";
        nowide::cout << "说明: 显示系统帮助信息。如果不指定命令名，显示所有命令列表。\n";
    } else if (cmd == "library") {
        nowide::cout << "用法: library\n";
        nowide::cout << "说明: 显示古文库中的文章列表。\n";
        nowide::cout << "      文章信息包括：ID、标题、作者、朝代和四维难度值。\n";
        nowide::cout << "      默认显示前 5 篇，可输入 ID 区间（如 1-5）查看指定范围的文章。\n";
    } else if (cmd == "exit") {
        nowide::cout << "用法: exit\n";
        nowide::cout << "说明: 退出程序。\n";
    } else if (cmd == "recommend") {
        nowide::cout << "用法: recommend [N]\n";
        nowide::cout << "说明: 根据您的能力水平推荐适合的古文文章。\n";
        nowide::cout << "      N: 可选参数，指定推荐数量（默认10篇）。\n";
        nowide::cout << "      推荐基于论文中的高斯概率i+1算法实现。\n";
        nowide::cout << "      匹配度越高，文章难度越适合您当前能力。\n";
    } else if (cmd == "read") {
        nowide::cout << "用法: read <文章ID>\n";
        nowide::cout << "说明: 阅读指定文章，阅读后自动更新能力值。\n";
        nowide::cout << "      文章ID: 必填参数，可通过 library 命令查看。\n";
        nowide::cout << "      阅读时间超过30秒才会触发能力更新。\n";
        nowide::cout << "      能力更新基于论文中的阅读效应公式。\n";
        nowide::cout << "示例: read 1\n";
    } else if (cmd == "log") {
        nowide::cout << "用法: log [等级]\n";
        nowide::cout << "说明: 设置日志输出等级。\n";
        nowide::cout << "      debug - 显示所有日志（调试用）\n";
        nowide::cout << "      info  - 显示信息及更高级别（默认）\n";
        nowide::cout << "      warn  - 显示警告和错误\n";
        nowide::cout << "      error - 仅显示错误\n";
        nowide::cout << "      不带参数则显示当前用法。\n";
        nowide::cout << "示例: log debug\n";
    } else {
        nowide::cout << "未知命令: " << cmd << "\n";
        nowide::cout << "输入 'help' 查看所有可用命令。\n";
    }
}