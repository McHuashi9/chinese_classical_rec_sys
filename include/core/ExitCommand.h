#ifndef EXIT_COMMAND_H
#define EXIT_COMMAND_H

#include "core/Command.h"
#include <string>
#include <vector>

/**
 * @brief 退出命令处理类
 * 
 * 处理程序退出逻辑
 */
class ExitCommand : public Command {
public:
    ExitCommand();
    
    /**
     * @brief 执行退出命令
     * @param args 参数列表
     * @return false 表示退出程序
     */
    bool execute(const std::vector<std::string>& args) override;
};

#endif
