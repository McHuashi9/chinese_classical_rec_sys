#include "core/CommandRegistry.h"
#include "utils/Logger.h"
#include <nowide/iostream.hpp>

CommandRegistry::CommandRegistry() {}

void CommandRegistry::registerCommand(const std::string& name, std::unique_ptr<Command> command) {
    commands_[name] = std::move(command);
}

bool CommandRegistry::executeCommand(const std::string& name, const std::vector<std::string>& args) {
    auto it = commands_.find(name);
    if (it == commands_.end()) {
        nowide::cout << "未知命令: " << name << "\n";
        nowide::cout << "输入 'help' 查看可用命令。\n";
        LOG_WARN("未知命令: {}", name);
        return true;
    }
    LOG_DEBUG("执行命令: {}", name);
    return it->second->execute(args);
}

bool CommandRegistry::hasCommand(const std::string& name) const {
    return commands_.find(name) != commands_.end();
}
