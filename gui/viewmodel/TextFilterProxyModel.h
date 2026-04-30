#pragma once
#include <QSortFilterProxyModel>
#include <QString>

class TextFilterProxyModel : public QSortFilterProxyModel {
    Q_OBJECT
public:
    explicit TextFilterProxyModel(QObject *parent = nullptr);

    void setFilterText(const QString &text);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;

private:
    QString m_filterText;
};
