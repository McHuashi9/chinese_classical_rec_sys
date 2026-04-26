#include "viewmodel/Paginator.h"
#include <QFontMetrics>
#include <QSet>
#include <algorithm>

void Paginator::flushPage(
    std::vector<Page> &pages,
    QStringList &pageLines,
    int pageStart,
    int charEnd
) {
    if (pageLines.isEmpty())
        return;

    Page p;
    p.index = static_cast<int>(pages.size());
    p.text = pageLines.join(QString());
    p.charStart = pageStart;
    p.charEnd = charEnd;
    pages.push_back(std::move(p));
    pageLines.clear();
}

std::vector<Page> Paginator::paginate(
    const QString &text,
    const QFont &font,
    double lineHeight,
    double availableWidth,
    double availableHeight
) {
    std::vector<Page> pages;

    if (text.isEmpty() || availableWidth <= 0 || availableHeight <= 0)
        return pages;

    QFontMetrics fm(font);

    const double effectiveLineHeight = font.pixelSize() * lineHeight;
    const int maxLinesPerPage = std::max(1, static_cast<int>(availableHeight / effectiveLineHeight));

    QStringList pageLines;
    QString currentLine;
    double currentLineWidth = 0;
    int linesInPage = 0;
    int pageStart = 0;

    const int len = text.length();
    int i = 0;
    while (i < len) {
        const QChar ch = text.at(i);

        if (ch == QLatin1Char('\n')) {
            // End current accumulated line (even if empty)
            if (!currentLine.isEmpty() || pageLines.isEmpty()) {
                currentLine.append(QLatin1Char('\n'));
                pageLines.append(currentLine);
                currentLine.clear();
                currentLineWidth = 0;
                linesInPage++;
            } else {
                // Previous line was also empty — append another empty line
                pageLines.append(QString(QLatin1Char('\n')));
                linesInPage++;
            }

            if (linesInPage >= maxLinesPerPage) {
                flushPage(pages, pageLines, pageStart, i + 1);
                linesInPage = 0;
                pageStart = i + 1;
            }
            i++;
            continue;
        }

        const double charWidth = fm.horizontalAdvance(ch);

        if (!currentLine.isEmpty() && currentLineWidth + charWidth > availableWidth) {
            // Line full — wrap
            currentLine.append(QLatin1Char('\n'));
            pageLines.append(currentLine);
            currentLine.clear();
            currentLineWidth = 0;
            linesInPage++;

            if (linesInPage >= maxLinesPerPage) {
                flushPage(pages, pageLines, pageStart, i);
                linesInPage = 0;
                pageStart = i;
            }
        }

        currentLine.append(ch);
        currentLineWidth += charWidth;
        i++;
    }

    // Flush the last accumulated line
    if (!currentLine.isEmpty()) {
        currentLine.append(QLatin1Char('\n'));
        pageLines.append(currentLine);
        linesInPage++;
    }

    // Flush final page
    if (!pageLines.isEmpty()) {
        flushPage(pages, pageLines, pageStart, len);
    }

    return pages;
}

int Paginator::findPageForCharPos(
    const std::vector<Page> &pages,
    int charPos
) {
    if (pages.empty())
        return 0;

    for (size_t i = 0; i < pages.size(); ++i) {
        if (charPos >= pages[i].charStart && charPos < pages[i].charEnd)
            return static_cast<int>(i);
    }

    // charPos past the end: return last page
    if (charPos >= pages.back().charEnd)
        return static_cast<int>(pages.size()) - 1;

    // charPos before the start: return first page
    return 0;
}
