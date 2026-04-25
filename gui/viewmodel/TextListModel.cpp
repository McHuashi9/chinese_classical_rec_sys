#include "TextListModel.h"

TextListModel::TextListModel(QObject *parent)
    : QAbstractListModel(parent) {}

void TextListModel::setTexts(const std::vector<Text> &texts)
{
    beginResetModel();
    m_texts = texts;
    endResetModel();
}

void TextListModel::clear()
{
    beginResetModel();
    m_texts.clear();
    endResetModel();
}

int TextListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return static_cast<int>(m_texts.size());
}

QVariant TextListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= static_cast<int>(m_texts.size()))
        return {};

    const Text &t = m_texts[index.row()];

    switch (role) {
    case TextIdRole:
        return t.getId();
    case TitleRole:
        return QString::fromStdString(t.getTitle());
    case AuthorRole:
        return QString::fromStdString(t.getAuthor());
    case DynastyRole:
        return QString::fromStdString(t.getDynasty());
    case DifficultyRole: {
        double sum = 0.0;
        for (int i = 0; i < 10; ++i)
            sum += t.getDifficulty(i);
        return QString::number(sum / 10.0, 'f', 2);
    }
    default:
        return {};
    }
}

QHash<int, QByteArray> TextListModel::roleNames() const
{
    return {
        {TextIdRole,   "textId"},
        {TitleRole,    "title"},
        {AuthorRole,   "author"},
        {DynastyRole,  "dynasty"},
        {DifficultyRole, "difficulty"}
    };
}
