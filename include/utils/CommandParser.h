#ifndef COMMAND_PARSER_H
#define COMMAND_PARSER_H

#include <string>
#include <vector>

/**
 * @brief 简单的命令解析器
 * 
 * 功能：
 * 1. 将用户输入的行解析为命令和参数
 * 2. 提供获取命令名和参数的方法
 */
class CommandParser {
public:
    CommandParser();
    
    /**
     * @brief 解析一行用户输入
     * @param input 用户输入的字符串
     */
    void parse(const std::string& input);
    
    /**
     * @return 命令名（小写形式）
     */
    std::string getCommand() const;
    
    /**
     * @return 参数列表
     */
    std::vector<std::string> getArgs() const;
    
    /**
     * @brief 检查命令是否为空
     */
    bool isEmpty() const;
    
private:
    std::string command;           // 命令名
    std::vector<std::string> args; // 参数列表
};

#endif