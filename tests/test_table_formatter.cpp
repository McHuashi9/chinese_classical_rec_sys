#include <catch_amalgamated.hpp>
#include "utils/TableFormatter.h"
#include <tabulate.hpp>

/**
 * @brief 单元测试：表格格式化工具
 * 
 * 测试范围：
 * - TableFormatter::createStyledTable 创建有效表格
 * - TableFormatter::styleHeader 设置表头样式
 * - TableFormatter::applyBorderStyle 设置边框样式
 */

TEST_CASE("TableFormatter::createStyledTable - 创建有效表格", "[ui]") {
    SECTION("返回非空表格对象") {
        tabulate::Table table = TableFormatter::createStyledTable();
        REQUIRE(table.size() == 0); // 新表格应无行
        
        // 添加行后大小应更新
        table.add_row({"列1", "列2"});
        REQUIRE(table.size() == 1);
        REQUIRE(table[0].size() == 2);
    }
    
    SECTION("设置多字节字符支持") {
        tabulate::Table table = TableFormatter::createStyledTable();
        // 无法直接访问 format 内部状态，但可验证表格可用
        REQUIRE_NOTHROW(table.add_row({"中文测试", "✓"}));
    }
}

TEST_CASE("TableFormatter::styleHeader - 设置表头样式", "[ui]") {
    tabulate::Table table = TableFormatter::createStyledTable();
    table.add_row({"标题1", "标题2"});
    table.add_row({"数据1", "数据2"});
    
    SECTION("不抛出异常") {
        REQUIRE_NOTHROW(TableFormatter::styleHeader(table));
    }
    
    SECTION("多次调用安全") {
        TableFormatter::styleHeader(table);
        REQUIRE_NOTHROW(TableFormatter::styleHeader(table)); // 二次调用应安全
    }
    
    SECTION("表头存在时工作") {
        REQUIRE(table.size() >= 1);
        REQUIRE_NOTHROW(TableFormatter::styleHeader(table));
    }
}

TEST_CASE("TableFormatter::applyBorderStyle - 设置边框样式", "[ui]") {
    tabulate::Table table = TableFormatter::createStyledTable();
    table.add_row({"A", "B"});
    table.add_row({"1", "2"});
    
    SECTION("不抛出异常") {
        REQUIRE_NOTHROW(TableFormatter::applyBorderStyle(table));
    }
    
    SECTION("空表格也安全") {
        tabulate::Table emptyTable = TableFormatter::createStyledTable();
        REQUIRE_NOTHROW(TableFormatter::applyBorderStyle(emptyTable));
    }
    
    SECTION("多次调用安全") {
        TableFormatter::applyBorderStyle(table);
        REQUIRE_NOTHROW(TableFormatter::applyBorderStyle(table)); // 二次调用应安全
    }
}

TEST_CASE("TableFormatter 组合使用", "[ui]") {
    SECTION("完整工作流程") {
        tabulate::Table table = TableFormatter::createStyledTable();
        table.add_row({"维度", "能力值"});
        table.add_row({"d1", "0.300"});
        
        REQUIRE_NOTHROW(TableFormatter::styleHeader(table));
        REQUIRE_NOTHROW(TableFormatter::applyBorderStyle(table));
        
        REQUIRE(table.size() == 2);
        REQUIRE(table[0].size() == 2);
    }
    
    SECTION("模拟 LibraryCommand 使用场景") {
        tabulate::Table table = TableFormatter::createStyledTable();
        table.add_row({"ID", "标题", "作者", "朝代", "综合难度"});
        TableFormatter::styleHeader(table);
        
        table.add_row({"1", "齐桓下拜受胙", "(不详)", "-", "11.4"});
        table.add_row({"2", "书洛阳名园记后", "(不详)", "-", "11.4"});
        
        // 列对齐设置
        table.column(0).format().font_align(tabulate::FontAlign::right);
        table.column(1).format().font_align(tabulate::FontAlign::left);
        table.column(4).format().font_align(tabulate::FontAlign::right);
        
        TableFormatter::applyBorderStyle(table);
        
        REQUIRE(table.size() == 3);
        REQUIRE(table[0].size() == 5);
    }
}