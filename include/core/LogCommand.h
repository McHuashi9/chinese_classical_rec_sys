#ifndef LOG_COMMAND_H
#define LOG_COMMAND_H

#include "Command.h"

/**
 * @brief 日志等级设置命令
 * 
 * 允许用户在运行时调整日志等级。
 * 用法: log [等级]
 * 等级: debug, info, warn, error
 */
class LogCommand : public Command {
public:
    LogCommand();
    
    /**
     * @brief 执行日志等级设置命令
     * @param args 参数列表，第一个参数为日志等级
     * @return true 继续运行程序
     */
    bool execute(const std::vector<std::string>& args) override;
    
private:
    /**
     * @brief 显示当前日志等级和可用等级
     */
    void showUsage();
};

#endif // LOG_COMMAND_H
