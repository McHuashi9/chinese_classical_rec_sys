#ifndef HELP_COMMAND_H
#define HELP_COMMAND_H

#include "core/Command.h"
#include <string>
#include <vector>

/**
 * @brief 帮助命令处理类
 * 
 * 显示系统支持的所有命令及用法
 */
class HelpCommand : public Command {
public:
    HelpCommand();
    
    /**
     * @brief 执行帮助命令
     * @param args 参数列表
     * @return true 继续运行程序
     */
    bool execute(const std::vector<std::string>& args) override;
    
private:
    /**
     * @brief 显示所有命令的帮助
     */
    void showAllHelp();
    
    /**
     * @brief 显示特定命令的帮助
     * @param cmd 命令名
     */
    void showCommandHelp(const std::string& cmd);
};

#endif