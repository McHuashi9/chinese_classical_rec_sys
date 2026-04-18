#include "core/ReadCommand.h"
#include "utils/Logger.h"
#include <nowide/iostream.hpp>
#include <iomanip>
#include <chrono>
#include <thread>
#include <string>
#include <ctime>

ReadCommand::ReadCommand(UserRepository* userRepo, 
                         TextRepository* textRepo,
                         ReadingHistoryRepository* historyRepo,
                         LearningIncrementRepository* incrementRepo,
                         KnowledgeTracker* tracker)
    : userRepo(userRepo), textRepo(textRepo), historyRepo(historyRepo),
      incrementRepo(incrementRepo), tracker(tracker) {}

bool ReadCommand::execute(const std::vector<std::string>& args) {
    // 检查参数
    if (args.empty()) {
        nowide::cout << "用法：read <文章ID>\n";
        nowide::cout << "示例：read 1\n";
        nowide::cout << "使用 'library' 命令查看文章列表。\n";
        return true;
    }
    
    // 检查依赖
    if (!textRepo || !userRepo || !tracker) {
        nowide::cout << "错误：系统初始化不完整。\n";
        return true;
    }
    
    // 解析文章ID
    int textId;
    try {
        textId = std::stoi(args[0]);
    } catch (...) {
        nowide::cout << "错误：无效的文章ID。\n";
        return true;
    }
    
    // 获取文章
    Text text;
    if (!textRepo->getTextById(textId, text)) {
        nowide::cout << "未找到ID为 " << textId << " 的文章。\n";
        nowide::cout << "使用 'library' 命令查看可用文章列表。\n";
        LOG_WARN("未找到文章: ID={}", textId);
        return true;
    }
    
    LOG_INFO("阅读文章: ID={}, 标题={}", textId, text.getTitle());
    
    // 显示文章并记录阅读时间
    double readTime = displayText(text);
    
    // 获取当前时间戳
    time_t currentTimestamp = std::time(nullptr);
    
    // 记录阅读历史
    if (historyRepo) {
        historyRepo->addRecord(textId, readTime, currentTimestamp);
        LOG_DEBUG("记录阅读历史: 文章ID={}, 阅读时间={:.1f}s", textId, readTime);
    }
    
    // 触发阅读效应更新
    User user;
    if (userRepo->getUser(user)) {
        // 论文版本：先清理过期增量，再应用遗忘效应
        if (incrementRepo) {
            tracker->pruneOldIncrements(user, currentTimestamp);
            tracker->applyForgettingEffect(user, currentTimestamp);
        }
        
        double oldAbility = user.getAverageAbility();
        
        // 应用阅读效应，记录增量
        tracker->applyReadEffect(user, text, readTime, currentTimestamp);
        
        // 更新最后阅读时间
        user.setLastReadTime(currentTimestamp);
        userRepo->saveUser(user);
        
        if (readTime >= Config::MIN_READ_TIME) {
            LOG_INFO("能力更新: {:.3f} -> {:.3f}", oldAbility, user.getAverageAbility());
            nowide::cout << "\n阅读完成！能力已更新。\n";
            nowide::cout << "新平均能力：" << std::fixed << std::setprecision(3) 
                      << user.getAverageAbility() << "\n";
        } else {
            nowide::cout << "\n阅读时间不足 " << Config::MIN_READ_TIME 
                      << " 秒，能力未更新。\n";
        }
    }
    
    return true;
}

double ReadCommand::displayText(const Text& text) {
    displayMetaInfo(text);
    double readTime = displayContent(text.getContent());
    return readTime;
}

void ReadCommand::displayMetaInfo(const Text& text) {
    nowide::cout << "\n";
    nowide::cout << "═══════════════════════════════════════════════════\n";
    nowide::cout << "  " << text.getTitle() << "\n";
    nowide::cout << "───────────────────────────────────────────────────\n";
    
    if (!text.getAuthor().empty() || !text.getDynasty().empty()) {
        nowide::cout << "  ";
        if (!text.getDynasty().empty()) {
            nowide::cout << "【" << text.getDynasty() << "】";
        }
        if (!text.getAuthor().empty()) {
            nowide::cout << text.getAuthor();
        }
        nowide::cout << "\n";
    }
    
    nowide::cout << "═══════════════════════════════════════════════════\n\n";
}

double ReadCommand::displayContent(const std::string& content) {
    if (content.empty()) {
        nowide::cout << "（文章内容为空）\n";
        return 0.0;
    }
    
    auto startTime = std::chrono::steady_clock::now();
    nowide::cout << content;
    auto endTime = std::chrono::steady_clock::now();
    
    const int linesPerPage = 20;
    int totalLines = calculateLineCount(content);
    displayWithPagination(totalLines, linesPerPage);
    
    return std::chrono::duration<double>(endTime - startTime).count();
}

int ReadCommand::calculateLineCount(const std::string& content) const {
    if (content.empty()) {
        return 0;
    }
    
    int count = 0;
    for (char c : content) {
        if (c == '\n') {
            count++;
        }
    }
    
    if (content.back() != '\n') {
        count++;
    }
    
    return count;
}

void ReadCommand::displayWithPagination(int totalLines, int linesPerPage) {
    if (totalLines <= linesPerPage) {
        waitForUserExit();
    } else {
        nowide::cout << "\n\n--- 按Enter继续，输入q退出 ---";
        std::string input;
        std::getline(nowide::cin, input);
    }
}

void ReadCommand::waitForUserExit() const {
    nowide::cout << "\n\n按 Enter 退出...";
    std::string dummy;
    std::getline(nowide::cin, dummy);
}