#ifndef LIBRARY_COMMAND_H
#define LIBRARY_COMMAND_H

#include "core/Command.h"
#include "database/TextRepository.h"
#include "models/Text.h"
#include <vector>
#include <string>

/**
 * @brief 古文库显示命令
 * 
 * 显示古文库中的文章列表，支持分页浏览
 */
class LibraryCommand : public Command {
public:
    /**
     * @brief 构造函数
     * @param textRepo 古文数据访问对象指针
     */
    LibraryCommand(TextRepository* textRepo);
    
    /**
     * @brief 执行 library 命令
     * @param args 参数列表（暂未使用）
     * @return true 继续运行程序
     */
    bool execute(const std::vector<std::string>& args) override;

private:
    TextRepository* textRepo;
    inline static const int PAGE_SIZE = 5;  ///< 每页显示的文章数
    
    /**
     * @brief 显示文章列表
     * @param texts 要显示的文章列表
     */
    void displayTexts(const std::vector<Text>& texts);
    
    /**
     * @brief 显示单篇文章的简要信息
     * @param text 文章对象
     */
    void displayTextBrief(const Text& text);
    
    /**
     * @brief 解析 ID 区间字符串
     * @param input 用户输入的区间字符串（如 "1-5"）
     * @param start 输出参数：起始 ID
     * @param end 输出参数：结束 ID
     * @return true 解析成功，false 格式错误
     */
    bool parseIdRange(const std::string& input, int& start, int& end);
    
    /**
     * @brief 计算文章综合难度分数
     * @param text 文章对象
     * @return 综合难度分数
     */
    double calculateCompositeDifficulty(const Text& text);
};

#endif
