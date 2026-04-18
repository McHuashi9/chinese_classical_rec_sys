#ifndef RECOMMEND_COMMAND_H
#define RECOMMEND_COMMAND_H

#include "core/Command.h"
#include "core/RecommendationEngine.h"
#include "core/KnowledgeTracker.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/LearningIncrementRepository.h"
#include "models/User.h"

/**
 * @brief 推荐命令
 * 
 * 根据用户能力状态推荐适合的古文文章
 */
class RecommendCommand : public Command {
public:
    /**
     * @brief 构造函数
     * @param userRepo 用户数据访问对象指针
     * @param textRepo 古文数据访问对象指针
     * @param incrementRepo 增量数据访问对象指针
     * @param tracker 知识追踪器指针
     */
    RecommendCommand(UserRepository* userRepo, TextRepository* textRepo,
                     LearningIncrementRepository* incrementRepo, KnowledgeTracker* tracker);
    
    /**
     * @brief 执行 recommend 命令
     * @param args 参数列表（可选：指定返回数量）
     * @return true 继续运行程序
     */
    bool execute(const std::vector<std::string>& args) override;

private:
    UserRepository* userRepo;
    TextRepository* textRepo;
    LearningIncrementRepository* incrementRepo;
    KnowledgeTracker* tracker;
    RecommendationEngine engine;
    inline static const int DEFAULT_TOP_K = 10;  ///< 默认推荐数量
    
    void displayRecommendations(
        const std::vector<std::pair<int, double>>& recommendations,
        const std::vector<Text>& allTexts
    );
};

#endif
