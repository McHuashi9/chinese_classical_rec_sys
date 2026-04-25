#pragma once
#include <QAbstractListModel>
#include <vector>

class RecommendationModel : public QAbstractListModel {
    Q_OBJECT
public:
    struct Item {
        int textId;
        QString title;
        QString author;
        QString dynasty;
        double probability;
    };

    enum Roles {
        TextIdRole = Qt::UserRole + 1,
        TitleRole,
        AuthorRole,
        DynastyRole,
        ProbabilityRole
    };

    explicit RecommendationModel(QObject *parent = nullptr);

    void setItems(const std::vector<Item> &items);
    void clear();

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    std::vector<Item> m_items;
};
