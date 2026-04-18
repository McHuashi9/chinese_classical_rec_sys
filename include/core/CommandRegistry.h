#ifndef COMMAND_REGISTRY_H
#define COMMAND_REGISTRY_H

#include "core/Command.h"
#include <string>
#include <unordered_map>
#include <memory>

/**
 * @brief 命令注册表
 * 
 * 管理所有可用命令的注册和分发
 */
class CommandRegistry {
public:
    CommandRegistry();
    
    /**
     * @brief 注册命令
     * @param name 命令名称
     * @param command 命令对象
     */
    void registerCommand(const std::string& name, std::unique_ptr<Command> command);
    
    /**
     * @brief 执行命令
     * @param name 命令名称
     * @param args 参数列表
     * @return true 继续运行程序，false 退出程序
     */
    bool executeCommand(const std::string& name, const std::vector<std::string>& args);
    
    /**
     * @brief 检查命令是否存在
     * @param name 命令名称
     * @return true 命令存在
     */
    bool hasCommand(const std::string& name) const;

private:
    std::unordered_map<std::string, std::unique_ptr<Command>> commands_;
};

#endif
