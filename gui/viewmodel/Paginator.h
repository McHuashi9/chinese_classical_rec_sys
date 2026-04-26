#pragma once

#include <QString>
#include <QFont>
#include <vector>

struct Page {
    int index;       // 0-based page index
    QString text;    // pre-broken text with \n at line endings
    int charStart;   // start character index in original full text
    int charEnd;     // end character index (exclusive) in original full text
};

class Paginator {
public:
    /**
     * @brief Paginate plain text into fixed-size pages.
     * @param text              Full original text (may contain \n for paragraph breaks)
     * @param font              QFont with family and pixelSize set
     * @param lineHeight        Line height multiplier (e.g. 1.8)
     * @param availableWidth    Available text width in pixels
     * @param availableHeight   Available text height in pixels
     * @return Vector of Page structs, sorted by index
     */
    static std::vector<Page> paginate(
        const QString &text,
        const QFont &font,
        double lineHeight,
        double availableWidth,
        double availableHeight
    );

    /**
     * @brief Find the page index that contains the given character position.
     * Used after recalculating pagination (font size / window resize) to restore position.
     * @param pages   Newly paginated pages
     * @param charPos Character index in the original full text
     * @return Closest valid page index (0-based), clamped to [0, pages.size()-1]
     */
    static int findPageForCharPos(
        const std::vector<Page> &pages,
        int charPos
    );

private:
    static void flushPage(
        std::vector<Page> &pages,
        QStringList &pageLines,
        int pageStart,
        int charEnd
    );
};
