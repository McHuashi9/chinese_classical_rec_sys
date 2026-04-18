#include <iostream>
#include <string>
#include <sstream>
#include <memory>
#include <clocale>
#include <nowide/iostream.hpp>
#ifdef _WIN32
#include <windows.h>
#endif
#include "replxx.hxx"
#include "utils/Logger.h"
#include "utils/CommandParser.h"
#include "utils/PathUtils.h"
#include "core/CommandRegistry.h"
#include "core/HelpCommand.h"
#include "core/LibraryCommand.h"
#include "core/ExitCommand.h"
#include "core/RecommendCommand.h"
#include "core/ReadCommand.h"
#include "core/LogCommand.h"
#include "core/KnowledgeTracker.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "models/User.h"
#include <tabulate.hpp>
#include "utils/TableFormatter.h"
#include <iomanip>
#include <sstream>


void initUser(UserRepository& userRepo, User& currentUser);
std::string promptUserName();
void displayUserAbilities(const User& user);

#ifdef _WIN32
void checkConsoleFont() {
    CONSOLE_FONT_INFOEX fontInfo;
    fontInfo.cbSize = sizeof(CONSOLE_FONT_INFOEX);
    HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
    if (GetCurrentConsoleFontEx(hConsole, FALSE, &fontInfo)) {
        if (!(fontInfo.FontFamily & TMPF_TRUETYPE)) {
            nowide::cout << "提示：当前控制台字体可能影响表格显示，建议使用 TrueType 等宽字体（如 Consolas）。" << std::endl;
        }
    }
}
#endif

int main() {
#ifdef _WIN32
    // 设置 Windows 控制台编码为 UTF-8
    SetConsoleOutputCP(65001);
    SetConsoleCP(65001);
    // 检查控制台字体
    checkConsoleFont();
#endif
    // 设置 C++ locale 以支持宽字符
    std::setlocale(LC_ALL, "");
    
    // 设置 nowide::cout 为无缓冲模式，确保输出立即显示
    nowide::cout << std::unitbuf;
    
    // 初始化日志系统
    std::string logsDir = PathUtils::getLogsDir().string();
    if (!Logger::getInstance().init(logsDir, "app.log")) {
        nowide::cerr << "日志系统初始化失败" << std::endl;
        return 1;
    }
    LOG_INFO("程序启动");
    
    std::string dbPath = PathUtils::getDbPath().string();
    DatabaseManager dbManager;
    if (!dbManager.open(dbPath)) {
        LOG_ERROR("无法打开数据库: {}", dbPath);
        nowide::cerr << "无法打开数据库: " << dbPath << std::endl;
        return 1;
    }
    LOG_INFO("数据库连接成功: {}", dbPath);
    
    UserRepository userRepo(&dbManager);
    if (!userRepo.initTable()) {
        LOG_ERROR("初始化用户表失败: {}", dbManager.getLastError());
        nowide::cerr << "初始化用户表失败: " << dbManager.getLastError() << std::endl;
        return 1;
    }
    
    TextRepository textRepo(&dbManager);
    if (!textRepo.initTable()) {
        LOG_ERROR("初始化古文表失败: {}", dbManager.getLastError());
        nowide::cerr << "初始化古文表失败: " << dbManager.getLastError() << std::endl;
        return 1;
    }
    
    ReadingHistoryRepository historyRepo(&dbManager);
    if (!historyRepo.initTable()) {
        LOG_ERROR("初始化阅读历史表失败: {}", dbManager.getLastError());
        nowide::cerr << "初始化阅读历史表失败: " << dbManager.getLastError() << std::endl;
        return 1;
    }
    
    LearningIncrementRepository incrementRepo(&dbManager);
    if (!incrementRepo.initTable()) {
        LOG_ERROR("初始化增量表失败: {}", dbManager.getLastError());
        nowide::cerr << "初始化增量表失败: " << dbManager.getLastError() << std::endl;
        return 1;
    }
    
    User currentUser;
    initUser(userRepo, currentUser);
    
    nowide::cout << "\n欢迎，" << currentUser.getName() << "！\n";
    nowide::cout << "输入 'help' 查看帮助，输入 'exit' 退出\n\n";
    
    // 创建知识追踪器（传入增量仓库）
    KnowledgeTracker knowledgeTracker(&incrementRepo);
    
    CommandRegistry registry;
    registry.registerCommand("help", std::make_unique<HelpCommand>());
    registry.registerCommand("library", std::make_unique<LibraryCommand>(&textRepo));
    registry.registerCommand("recommend", std::make_unique<RecommendCommand>(&userRepo, &textRepo, &incrementRepo, &knowledgeTracker));
    registry.registerCommand("read", std::make_unique<ReadCommand>(&userRepo, &textRepo, &historyRepo, &incrementRepo, &knowledgeTracker));
    registry.registerCommand("log", std::make_unique<LogCommand>());
    registry.registerCommand("exit", std::make_unique<ExitCommand>());
    
    CommandParser parser;
    std::string input;
    bool running = true;
    
    // 创建 replxx 实例
    replxx::Replxx rx;
    
    // 设置命令自动补全
    rx.set_completion_callback([](std::string const& context, int& contextLen) {
        replxx::Replxx::completions_t completions;
        std::vector<std::string> commands = {
            "help", "library", "recommend", "read", "log", "exit"
        };
        // 获取当前输入的单词
        std::string prefix = context;
        if (contextLen > 0 && static_cast<size_t>(contextLen) <= context.length()) {
            prefix = context.substr(context.length() - contextLen);
        }
        for (auto const& cmd : commands) {
            if (cmd.compare(0, prefix.size(), prefix) == 0) {
                completions.emplace_back(cmd);
            }
        }
        return completions;
    });
    
    // 加载命令历史
    std::string historyPath = PathUtils::getHistoryFilePath().string();
    rx.history_load(historyPath);
    rx.set_max_history_size(1000);  // 最多保存 1000 条历史
    
    while (running) {
        char const* line = rx.input("> ");
        if (!line) {
            // Ctrl+D 退出
            running = false;
            break;
        }
        
        input = line;
        // replxx 自动管理内存，无需手动释放
        
        // 添加非空输入到历史
        if (!input.empty()) {
            rx.history_add(input);
        }
        
        parser.parse(input);
        
        if (parser.isEmpty()) {
            continue;
        }
        
        running = registry.executeCommand(parser.getCommand(), parser.getArgs());
    }
    
    // 保存命令历史
    rx.history_sync(historyPath);
    
    dbManager.close();
    LOG_INFO("程序退出");
    
    return 0;
}

void displayUserAbilities(const User& user) {
    tabulate::Table table = TableFormatter::createStyledTable();
    
    // 格式化 lambda
    auto formatDouble = [](double value) -> std::string {
        std::ostringstream oss;
        oss << std::fixed << std::setprecision(3) << value;
        return oss.str();
    };
    
    table.add_row({"维度", "能力值"});
    TableFormatter::styleHeader(table);
    
    table.add_row({"d1 (平均句长)", formatDouble(user.getAbility(0))});
    table.add_row({"d2 (句子数)", formatDouble(user.getAbility(1))});
    table.add_row({"d3 (虚词比例)", formatDouble(user.getAbility(2))});
    table.add_row({"d4 (字平均对数频次)", formatDouble(user.getAbility(3))});
    table.add_row({"d5 (通假字密度)", formatDouble(user.getAbility(4))});
    table.add_row({"d6 (古汉语困惑度)", formatDouble(user.getAbility(5))});
    table.add_row({"d7 (今汉语困惑度)", formatDouble(user.getAbility(6))});
    table.add_row({"d8 (词汇多样性)", formatDouble(user.getAbility(7))});
    table.add_row({"d9 (典故密度)", formatDouble(user.getAbility(8))});
    table.add_row({"d10 (语义复杂度)", formatDouble(user.getAbility(9))});
    
    // 数值列右对齐
    table.column(1).format().font_align(tabulate::FontAlign::right);

    // 应用边框样式
    TableFormatter::applyBorderStyle(table);
        
    nowide::cout << table << std::endl;
}

std::string promptUserName() {
    nowide::cout << "初次使用，请输入你的名字：\n";
    
    while (true) {
        nowide::cout << "> ";
        std::string name;
        std::getline(nowide::cin, name);
        
        if (!name.empty()) {
            return name;
        }
        
        nowide::cout << "名字不能为空，请重新输入：\n";
    }
}



void initUser(UserRepository& userRepo, User& currentUser) {
    if (userRepo.getUser(currentUser)) {
        nowide::cout << "欢迎回来，" << currentUser.getName() << "！\n";
        displayUserAbilities(currentUser);
        return;
    }
    
    std::string name = promptUserName();
    currentUser.setName(name);
    
    // 使用贝叶斯先验均值初始化能力值：u_j(0) = 0.3
    currentUser.initializeDefault();
    nowide::cout << "已使用默认能力值初始化（贝叶斯先验均值 0.3）\n";
    
    if (userRepo.saveUser(currentUser)) {
        nowide::cout << "好的，" << name << "，已保存你的信息。\n";
        displayUserAbilities(currentUser);
    } else {
        nowide::cout << "保存失败。\n";
    }
}