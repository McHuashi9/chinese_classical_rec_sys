#include "RecommendationModel.h"

RecommendationModel::RecommendationModel(QObject *parent)
    : QAbstractListModel(parent) {}

void RecommendationModel::setItems(const std::vector<Item> &items)
{
    beginResetModel();
    m_items = items;
    endResetModel();
}

void RecommendationModel::clear()
{
    beginResetModel();
    m_items.clear();
    endResetModel();
}

int RecommendationModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_items.size());
}

QVariant RecommendationModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= static_cast<int>(m_items.size()))
        return {};

    const Item &item = m_items[index.row()];

    switch (role) {
    case TextIdRole:
        return item.textId;
    case TitleRole:
        return item.title;
    case AuthorRole:
        return item.author;
    case DynastyRole:
        return item.dynasty;
    case ProbabilityRole:
        return item.probability;
    default:
        return {};
    }
}

QHash<int, QByteArray> RecommendationModel::roleNames() const
{
    return {
        {TextIdRole,      "textId"},
        {TitleRole,       "title"},
        {AuthorRole,      "author"},
        {DynastyRole,     "dynasty"},
        {ProbabilityRole, "probability"}
    };
}
