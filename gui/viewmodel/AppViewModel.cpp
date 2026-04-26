#include "AppViewModel.h"
#include "TextListModel.h"
#include "RecommendationModel.h"
#include "core/KnowledgeTracker.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"

#include <ctime>

AppViewModel::AppViewModel(QObject *parent)
    : QObject(parent)
    , m_textListModel(new TextListModel(this))
    , m_recommendationModel(new RecommendationModel(this))
    , m_libraryProxy(new TextFilterProxyModel(this))
    , m_initialized(false)
{
}

AppViewModel::~AppViewModel() = default;

bool AppViewModel::initialize(const QString &dbPath)
{
    try {
        m_dbMgr = std::make_unique<DatabaseManager>();
        if (!m_dbMgr->open(dbPath.toStdString())) {
            const QString err = QString::fromStdString("无法打开数据库: " + m_dbMgr->getLastError());
            fprintf(stderr, "[AppViewModel] %s\n", qPrintable(err));
            emit errorOccurred(err);
            return false;
        }

        m_userRepo = std::make_unique<UserRepository>(m_dbMgr.get());
        m_textRepo = std::make_unique<TextRepository>(m_dbMgr.get());
        m_historyRepo = std::make_unique<ReadingHistoryRepository>(m_dbMgr.get());
        m_incrementRepo = std::make_unique<LearningIncrementRepository>(m_dbMgr.get());

        if (!m_userRepo->getUser(m_user)) {
            m_user.initializeDefault();
            m_user.setName("佚名");
            m_userRepo->saveUser(m_user);
        }

        m_allTexts = m_textRepo->getAllTexts();
        fprintf(stderr, "[AppViewModel] 已加载 %zu 篇古文\n", m_allTexts.size());
        m_textListModel->setTexts(m_allTexts);
        m_libraryProxy->setSourceModel(m_textListModel);

        m_tracker = std::make_unique<KnowledgeTracker>(m_incrementRepo.get());

        m_initialized = true;
        emit initializedChanged();

        emit userNameChanged();
        emit abilityChanged();
        emit statsChanged();

        return true;
    } catch (const std::exception &e) {
        const QString err = QString::fromStdString(std::string("初始化失败: ") + e.what());
        fprintf(stderr, "[AppViewModel] %s\n", qPrintable(err));
        emit errorOccurred(err);
        return false;
    }
}

QVariantList AppViewModel::getRecommendations(int topK)
{
    QVariantList result;

    if (!m_initialized)
        return result;

    time_t now = time(nullptr);
    m_tracker->applyForgettingEffect(m_user, now);

    auto recs = m_engine.recommend(m_user, m_allTexts, topK);

    std::vector<RecommendationModel::Item> items;
    items.reserve(recs.size());

    for (const auto &[textId, prob] : recs) {
        RecommendationModel::Item item;
        item.textId = textId;
        item.probability = prob;

        for (const Text &t : m_allTexts) {
            if (t.getId() == textId) {
                item.title = QString::fromStdString(t.getTitle());
                item.author = QString::fromStdString(t.getAuthor());
                item.dynasty = QString::fromStdString(t.getDynasty());
                break;
            }
        }

        items.push_back(std::move(item));

        QVariantMap map;
        map["textId"] = textId;
        map["title"] = item.title;
        map["author"] = item.author;
        map["dynasty"] = item.dynasty;
        map["probability"] = prob;
        result.append(map);
    }

    m_recommendationModel->setItems(items);

    return result;
}

QVariantMap AppViewModel::getTextDetail(int textId) const
{
    QVariantMap detail;

    for (const Text &t : m_allTexts) {
        if (t.getId() == textId) {
            detail["textId"]   = t.getId();
            detail["title"]    = QString::fromStdString(t.getTitle());
            detail["author"]   = QString::fromStdString(t.getAuthor());
            detail["dynasty"]  = QString::fromStdString(t.getDynasty());
            detail["content"]  = QString::fromStdString(t.getContent());
            return detail;
        }
    }

    return detail;
}

bool AppViewModel::recordReading(int textId, double readTime)
{
    if (!m_initialized)
        return false;

    Text targetText;
    bool found = false;
    for (const Text &t : m_allTexts) {
        if (t.getId() == textId) {
            targetText = t;
            found = true;
            break;
        }
    }

    if (!found) {
        emit errorOccurred("未找到该篇目");
        return false;
    }

    time_t now = time(nullptr);

    m_tracker->applyForgettingEffect(m_user, now);
    m_tracker->applyReadEffect(m_user, targetText, readTime, now);

    m_userRepo->saveUser(m_user);

    m_historyRepo->addRecord(textId, readTime, now);

    emit abilityChanged();
    emit statsChanged();

    return true;
}

QVariantMap AppViewModel::getAbilityBreakdown() const
{
    QVariantMap map;

    constexpr const char *kDimNames[] = {
        "avg_sentence_length",
        "sentence_count",
        "function_word_ratio",
        "avg_char_log_freq",
        "tongjiazi_density",
        "ppl_ancient",
        "ppl_modern",
        "mattr",
        "allusion_density",
        "semantic_complexity"
    };

    for (int i = 0; i < 10; ++i) {
        map[QString::fromLatin1(kDimNames[i])] = m_user.getAbility(i);
    }

    return map;
}

void AppViewModel::setLibraryFilter(const QString &filter)
{
    m_libraryProxy->setFilterText(filter);
}

QObject* AppViewModel::libraryProxyModel()
{
    return m_libraryProxy;
}

QString AppViewModel::userName() const
{
    return QString::fromStdString(m_user.getName());
}

double AppViewModel::averageAbility() const
{
    return m_user.getAverageAbility();
}

int AppViewModel::totalReadCount() const
{
    return m_historyRepo ? m_historyRepo->getTotalReadCount() : 0;
}

QObject* AppViewModel::textListModel()
{
    return m_textListModel;
}

QObject* AppViewModel::recommendationModel()
{
    return m_recommendationModel;
}

bool AppViewModel::initialized() const
{
    return m_initialized;
}
