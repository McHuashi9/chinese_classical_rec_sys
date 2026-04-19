#ifndef TABLEFORMATTER_H
#define TABLEFORMATTER_H

#include <tabulate.hpp>

namespace TableFormatter {

inline tabulate::Table createStyledTable() {
    tabulate::Table table;
    table.format()
        .multi_byte_characters(true)
        .locale("");
    return table;
}

inline void styleHeader(tabulate::Table& table) {
    table[0].format()
        .font_style({tabulate::FontStyle::bold})
        .font_color(tabulate::Color::yellow)
        .font_align(tabulate::FontAlign::center);
}

inline void applyBorderStyle(tabulate::Table& table) {
    table.format()
        .border_top(u8"─")
        .border_bottom(u8"─")
        .border_left(u8"│")
        .border_right(u8"│")
        .corner_top_left(u8"┌")
        .corner_top_right(u8"┐")
        .corner_bottom_left(u8"└")
        .corner_bottom_right(u8"┘");
}

} // namespace TableFormatter

#endif // TABLEFORMATTER_H