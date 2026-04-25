#pragma once
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QSortFilterProxyModel>
#include <QRegularExpression>
#include <memory>

// forward declarations
class DatabaseManager;
class UserRepository;
class TextRepository;
class ReadingHistoryRepository;
class LearningIncrementRepository;
#include "core/RecommendationEngine.h"
class KnowledgeTracker;
#include "models/User.h"
#include "models/Text.h"

#include "TextListModel.h"
class RecommendationModel;

class TextFilterProxyModel : public QSortFilterProxyModel {
    Q_OBJECT
public:
    explicit TextFilterProxyModel(QObject *parent = nullptr)
        : QSortFilterProxyModel(parent) {
    }

    void setFilterText(const QString &text) {
        m_filterText = text;
        invalidateFilter();
    }

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override {
        if (m_filterText.isEmpty())
            return true;
        QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);
        QString title = sourceModel()->data(idx, TextListModel::TitleRole).toString();
        QString author = sourceModel()->data(idx, TextListModel::AuthorRole).toString();
        return title.contains(m_filterText, Qt::CaseInsensitive)
            || author.contains(m_filterText, Qt::CaseInsensitive);
    }

private:
    QString m_filterText;
};

class AppViewModel : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString userName READ userName NOTIFY userNameChanged)
    Q_PROPERTY(double averageAbility READ averageAbility NOTIFY abilityChanged)
    Q_PROPERTY(int totalReadCount READ totalReadCount NOTIFY statsChanged)
    Q_PROPERTY(QObject* textListModel READ textListModel CONSTANT)
    Q_PROPERTY(QObject* recommendationModel READ recommendationModel CONSTANT)
    Q_PROPERTY(QObject* libraryProxyModel READ libraryProxyModel CONSTANT)
    Q_PROPERTY(bool initialized READ initialized NOTIFY initializedChanged)

public:
    explicit AppViewModel(QObject *parent = nullptr);
    ~AppViewModel() override;

    Q_INVOKABLE bool initialize(const QString &dbPath);

    Q_INVOKABLE QVariantList getRecommendations(int topK = 10);

    Q_INVOKABLE QVariantMap getTextDetail(int textId) const;

    Q_INVOKABLE bool recordReading(int textId, double readTime);

    Q_INVOKABLE QVariantMap getAbilityBreakdown() const;

    Q_INVOKABLE void setLibraryFilter(const QString &filter);

    QString userName() const;
    double averageAbility() const;
    int totalReadCount() const;
    QObject* textListModel();
    QObject* recommendationModel();
    QObject* libraryProxyModel();
    bool initialized() const;

signals:
    void userNameChanged();
    void abilityChanged();
    void statsChanged();
    void initializedChanged();
    void errorOccurred(const QString &message);

private:
    // core components
    std::unique_ptr<DatabaseManager> m_dbMgr;
    std::unique_ptr<UserRepository> m_userRepo;
    std::unique_ptr<TextRepository> m_textRepo;
    std::unique_ptr<ReadingHistoryRepository> m_historyRepo;
    std::unique_ptr<LearningIncrementRepository> m_incrementRepo;

    RecommendationEngine m_engine;
    std::unique_ptr<KnowledgeTracker> m_tracker;

    // data
    User m_user;
    std::vector<Text> m_allTexts;

    // QML-exposed models (owned by this)
    TextListModel *m_textListModel;
    RecommendationModel *m_recommendationModel;
    TextFilterProxyModel *m_libraryProxy;

    bool m_initialized;
};
