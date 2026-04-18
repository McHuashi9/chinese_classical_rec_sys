#include "core/LibraryCommand.h"
#include "utils/Logger.h"
#include <nowide/iostream.hpp>
#include <iomanip>
#include <sstream>
#include <cmath>
#include <tabulate.hpp>


LibraryCommand::LibraryCommand(TextRepository* textRepo) : textRepo(textRepo) {}

bool LibraryCommand::execute(const std::vector<std::string>& args) {
    if (!textRepo) {
        nowide::cout << "错误：数据访问未初始化。\n";
        return true;
    }
    
    int totalCount = textRepo->getCount();
    
    if (totalCount == 0) {
        nowide::cout << "\n古文库为空。\n";
        nowide::cout << "可运行 'python3 scripts/utils/init_data.py' 初始化数据。\n\n";
        LOG_WARN("古文库为空");
        return true;
    }
    
    LOG_INFO("浏览古文库: 共 {} 篇", totalCount);
    
    nowide::cout << "\n古文库（共 " << totalCount << " 篇）\n\n";
    
    int displayCount = std::min(PAGE_SIZE, totalCount);
    std::vector<Text> texts = textRepo->getTextsByIdRange(1, displayCount);
    displayTexts(texts);
    
    if (totalCount > PAGE_SIZE) {
        nowide::cout << "\n显示前 " << displayCount << " 篇，共 " << totalCount << " 篇。\n";
        nowide::cout << "输入 ID 区间查看更多（如 6-10），或输入 q 退出: ";
        
        std::string input;
        while (std::getline(nowide::cin, input)) {
            size_t start = input.find_first_not_of(" \t");
            size_t end = input.find_last_not_of(" \t");
            if (start == std::string::npos) {
                nowide::cout << "输入 ID 区间（如 6-10），或 q 退出: ";
                continue;
            }
            input = input.substr(start, end - start + 1);
            
            if (input == "q" || input == "quit" || input == "exit") {
                break;
            }
            
            int rangeStart, rangeEnd;
            if (!parseIdRange(input, rangeStart, rangeEnd)) {
                nowide::cout << "格式错误，请输入如 6-10 的区间，或 q 退出: ";
                continue;
            }
            
            if (rangeStart < 1 || rangeEnd < 1) {
                nowide::cout << "ID 必须大于 0，请重新输入: ";
                continue;
            }
            
            if (rangeStart > totalCount) {
                nowide::cout << "起始 ID 超出范围，当前有效范围：1-" << totalCount << "，请重新输入: ";
                continue;
            }
            
            if (rangeEnd > totalCount) {
                rangeEnd = totalCount;
            }
            
            if (rangeStart > rangeEnd) {
                std::swap(rangeStart, rangeEnd);
            }
            
            std::vector<Text> rangeTexts = textRepo->getTextsByIdRange(rangeStart, rangeEnd);
            if (rangeTexts.empty()) {
                nowide::cout << "该范围内没有找到文章。\n";
            } else {
                LOG_DEBUG("区间查询: {}-{}, 返回 {} 篇", rangeStart, rangeEnd, rangeTexts.size());
                nowide::cout << "\nID " << rangeStart << "-" << rangeEnd << " 的文章：\n\n";
                displayTexts(rangeTexts);
            }
            
            nowide::cout << "\n输入 ID 区间查看更多（如 1-5），或输入 q 退出: ";
        }
    }
    
    nowide::cout << "\n";
    return true;
}

double LibraryCommand::calculateCompositeDifficulty(const Text& text) {
    // 使用10维特征计算综合难度
    // d1=f1, d2=f3, d3=f5, d4=f6, d5=f8, d6=f9, d7=f10, d8=f11, d9=f12, d10=f13
    double sum = 0.0;
    int count = 0;
    
    // d1: 平均句长
    sum += text.getF1AvgSentenceLength();
    count++;
    // d2: 句子数（取对数归一化）
    sum += std::log(text.getF3SentenceCount() + 1);
    count++;
    // d3: 虚词比例
    sum += text.getF5FunctionWordRatio() * 100;
    count++;
    // d4: 字平均对数频次（取负值，越小越难）
    sum += text.getF6AvgCharLogFreq() * -30;
    count++;
    // d5: 通假字密度
    sum += text.getF8TongjiaziDensity() * 1000;
    count++;
    // d6: 古汉语困惑度
    sum += text.getF9PplAncient() / 10;
    count++;
    // d7: 今汉语困惑度
    sum += text.getF10PplModern() / 10;
    count++;
    // d8: MATTR词汇多样性
    sum += (1.0 - text.getF11Mattr()) * 100;
    count++;
    // d9: 典故密度
    sum += text.getF12AllusionDensity() * 1000;
    count++;
    // d10: 语义复杂度
    sum += text.getF13SemanticComplexity() * 100;
    count++;
    
    return sum / count;
}

void LibraryCommand::displayTexts(const std::vector<Text>& texts) {
    tabulate::Table table;
    
    // 启用多字节字符支持（必须！否则中文宽度计算错误）
    table.format().multi_byte_characters(true).locale("");
    
    // 添加表头
    table.add_row({"ID", "标题", "作者", "朝代", "综合难度"});
    
    // 表头样式：加粗、黄色、居中
    table[0].format()
        .font_style({tabulate::FontStyle::bold})
        .font_color(tabulate::Color::yellow)
        .font_align(tabulate::FontAlign::center);
    
    // 添加数据行
    for (const auto& text : texts) {
        std::ostringstream diffStream;
        diffStream << std::fixed << std::setprecision(1) << calculateCompositeDifficulty(text);
        table.add_row({
            std::to_string(text.getId()),
            text.getTitle().empty() ? "(无题)" : text.getTitle(),
            text.getAuthor().empty() ? "(不详)" : text.getAuthor(),
            text.getDynasty().empty() ? "-" : text.getDynasty(),
            diffStream.str()
        });
    }
    
    // 列对齐设置：ID 和难度右对齐，标题左对齐
    table.column(0).format().font_align(tabulate::FontAlign::right);
    table.column(1).format().font_align(tabulate::FontAlign::left);
    table.column(4).format().font_align(tabulate::FontAlign::right);
    
    // 边框样式（使用 Unicode 框线字符，若终端不支持可改为 ASCII）
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
}



bool LibraryCommand::parseIdRange(const std::string& input, int& start, int& end) {
    size_t pos = input.find('-');
    if (pos == std::string::npos || pos == 0 || pos == input.length() - 1) {
        return false;
    }
    
    std::string startStr = input.substr(0, pos);
    std::string endStr = input.substr(pos + 1);
    
    try {
        start = std::stoi(startStr);
        end = std::stoi(endStr);
        return true;
    } catch (...) {
        return false;
    }
}
