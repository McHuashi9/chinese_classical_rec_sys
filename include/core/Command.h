#ifndef COMMAND_H
#define COMMAND_H

#include <string>
#include <vector>

/**
 * @brief 命令接口
 * 
 * 所有命令类必须实现此接口
 */
class Command {
public:
    virtual ~Command() = default;
    
    /**
     * @brief 执行命令
     * @param args 参数列表
     * @return true 继续运行程序，false 退出程序
     */
    virtual bool execute(const std::vector<std::string>& args) = 0;
};

#endif
