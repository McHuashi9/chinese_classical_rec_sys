#pragma once
#include <QAbstractListModel>
#include <vector>
#include "models/Text.h"

class TextListModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        TextIdRole = Qt::UserRole + 1,
        TitleRole,
        AuthorRole,
        DynastyRole,
        DifficultyRole
    };

    explicit TextListModel(QObject *parent = nullptr);

    void setTexts(const std::vector<Text> &texts);
    void clear();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    std::vector<Text> m_texts;
};
