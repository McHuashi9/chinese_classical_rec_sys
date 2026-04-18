#include "core/ExitCommand.h"
#include <nowide/iostream.hpp>

ExitCommand::ExitCommand() {}

bool ExitCommand::execute(const std::vector<std::string>& args) {
    nowide::cout << "感谢使用，再见！\n";
    return false;
}
