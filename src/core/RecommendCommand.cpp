#include "core/RecommendCommand.h"
#include "utils/Logger.h"
#include <nowide/iostream.hpp>
#include <iomanip>
#include <sstream>
#include <map>
#include <ctime>
#include <tabulate.hpp>


RecommendCommand::RecommendCommand(UserRepository* userRepo, TextRepository* textRepo,
                                   LearningIncrementRepository* incrementRepo, KnowledgeTracker* tracker)
    : userRepo(userRepo), textRepo(textRepo), incrementRepo(incrementRepo), tracker(tracker) {}

bool RecommendCommand::execute(const std::vector<std::string>& args) {
    // 获取当前用户
    User currentUser;
    if (!userRepo->getUser(currentUser)) {
        nowide::cout << "请先设置用户信息。\n";
        return true;
    }
    
    time_t now = std::time(nullptr);
    
    // 应用遗忘效应（论文版本：从增量历史计算当前能力）
    if (tracker && incrementRepo) {
        // 先清理过期增量（遗忘因子 < PSI_MIN）
        tracker->pruneOldIncrements(currentUser, now);
        
        // 从增量历史计算当前能力
        tracker->applyForgettingEffect(currentUser, now);
        
        // 保存用户状态
        userRepo->saveUser(currentUser);
    }
    
    // 解析参数：推荐数量
    int topK = DEFAULT_TOP_K;
    if (!args.empty()) {
        try {
            topK = std::stoi(args[0]);
            if (topK <= 0) topK = DEFAULT_TOP_K;
        } catch (...) {
            // 参数解析失败，使用默认值
        }
    }
    
    // 获取所有文章
    std::vector<Text> allTexts = textRepo->getAllTexts();
    
    if (allTexts.empty()) {
        nowide::cout << "古文库为空，请先导入数据。\n";
        return true;
    }
    
    LOG_DEBUG("推荐计算: topK={}, 文章数={}", topK, allTexts.size());
    
    // 计算推荐
    nowide::cout << "\n正在计算推荐...\n";
    auto recommendations = engine.recommend(currentUser, allTexts, topK);
    
    LOG_INFO("推荐完成: 返回 {} 篇文章", recommendations.size());
    
    // 显示结果
    displayRecommendations(recommendations, allTexts);
    
    return true;
}

void RecommendCommand::displayRecommendations(
    const std::vector<std::pair<int, double>>& recommendations,
    const std::vector<Text>& allTexts
) {
    if (recommendations.empty()) {
        nowide::cout << "没有找到合适的推荐。\n";
        return;
    }
    
    // 创建 ID -> Text 映射
    std::map<int, const Text*> textMap;
    for (const auto& text : allTexts) {
        textMap[text.getId()] = &text;
    }
    
    tabulate::Table table;
    table.format().multi_byte_characters(true).locale("");
    
    // 表头
    table.add_row({"序号", "标题", "作者", "匹配度"});
    table[0].format()
        .font_style({tabulate::FontStyle::bold})
        .font_color(tabulate::Color::yellow)
        .font_align(tabulate::FontAlign::center);
    
    // 数据行
    int rank = 1;
    for (const auto& [textId, prob] : recommendations) {
        auto it = textMap.find(textId);
        if (it != textMap.end()) {
            const Text* text = it->second;
            std::ostringstream probStream;
            probStream << std::fixed << std::setprecision(4) << prob;
            table.add_row({
                std::to_string(rank++),
                text->getTitle(),
                text->getAuthor().empty() ? "(不详)" : text->getAuthor(),
                probStream.str()
            });
        }
    }
    
    // 对齐：序号、匹配度右对齐，标题左对齐
    table.column(0).format().font_align(tabulate::FontAlign::right);
    table.column(1).format().font_align(tabulate::FontAlign::left);
    table.column(3).format().font_align(tabulate::FontAlign::right);
    
    // 边框样式（可复用 LibraryCommand 中的设置，或单独定义）
    table.format()
        .border_top("─")
        .border_bottom("─")
        .border_left("│")
        .border_right("│")
        .corner_top_left("┌")
        .corner_top_right("┐")
        .corner_bottom_left("└")
        .corner_bottom_right("┘");
        
    nowide::cout << table << std::endl;
    nowide::cout << "匹配度越高，文章难度越适合您当前的能力水平。\n";
}