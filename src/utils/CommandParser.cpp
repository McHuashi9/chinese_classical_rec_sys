#include "utils/CommandParser.h"
#include "utils/Logger.h"
#include <algorithm>
#include <sstream>

CommandParser::CommandParser() : command("") {}

void CommandParser::parse(const std::string& input) {
    // 清空之前的结果
    command.clear();
    args.clear();
    
    if (input.empty()) {
        return;
    }
    
    std::istringstream iss(input);
    std::string token;
    
    // 第一个单词是命令
    if (iss >> token) {
        // 转为小写，使命令大小写不敏感
        std::transform(token.begin(), token.end(), token.begin(), ::tolower);
        command = token;
        
        // 剩余的都是参数
        while (iss >> token) {
            args.push_back(token);
        }
    }
    
    LOG_DEBUG("命令解析: cmd={}, 参数数={}", command, args.size());
}

std::string CommandParser::getCommand() const {
    return command;
}

std::vector<std::string> CommandParser::getArgs() const {
    return args;
}

bool CommandParser::isEmpty() const {
    return command.empty();
}