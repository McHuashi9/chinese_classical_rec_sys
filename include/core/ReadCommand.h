#ifndef READ_COMMAND_H
#define READ_COMMAND_H

#include "core/Command.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "core/KnowledgeTracker.h"
#include <vector>
#include <string>

/**
 * @brief 阅读命令类
 * 
 * 实现文章阅读功能：
 * 1. 显示文章内容（标题、作者、朝代、正文）
 * 2. 记录阅读时间
 * 3. 触发阅读效应更新用户能力
 * 4. 记录阅读历史和增量
 * 5. 更新最后阅读时间戳
 * 
 * 命令格式：read <文章ID>
 */
class ReadCommand : public Command {
public:
    ReadCommand(UserRepository* userRepo, 
                TextRepository* textRepo,
                ReadingHistoryRepository* historyRepo,
                LearningIncrementRepository* incrementRepo,
                KnowledgeTracker* tracker);
    
    bool execute(const std::vector<std::string>& args) override;

private:
    UserRepository* userRepo;
    TextRepository* textRepo;
    ReadingHistoryRepository* historyRepo;
    LearningIncrementRepository* incrementRepo;
    KnowledgeTracker* tracker;
    
    double displayText(const Text& text);
    void displayMetaInfo(const Text& text);
    double displayContent(const std::string& content);
    int calculateLineCount(const std::string& content) const;
    void displayWithPagination(int totalLines, int linesPerPage);
    void waitForUserExit() const;
};

#endif
