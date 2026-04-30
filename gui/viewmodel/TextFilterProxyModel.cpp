#include "TextFilterProxyModel.h"
#include "TextListModel.h"

TextFilterProxyModel::TextFilterProxyModel(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

void TextFilterProxyModel::setFilterText(const QString &text)
{
    m_filterText = text;
    invalidateFilter();
}

bool TextFilterProxyModel::filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const
{
    if (m_filterText.isEmpty())
        return true;
    QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);
    QString title = sourceModel()->data(idx, TextListModel::TitleRole).toString();
    QString author = sourceModel()->data(idx, TextListModel::AuthorRole).toString();
    return title.contains(m_filterText, Qt::CaseInsensitive)
        || author.contains(m_filterText, Qt::CaseInsensitive);
}
