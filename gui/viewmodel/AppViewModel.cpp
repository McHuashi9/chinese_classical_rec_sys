#include "AppViewModel.h"
#include "TextListModel.h"
#include "RecommendationModel.h"
#include "core/KnowledgeTracker.h"
#include "core/Config.h"
#include "database/DatabaseManager.h"
#include "database/UserRepository.h"
#include "database/TextRepository.h"
#include "database/ReadingHistoryRepository.h"
#include "database/LearningIncrementRepository.h"
#include "utils/Logger.h"

#include <QSettings>
#include <ctime>

AppViewModel::AppViewModel(QObject *parent)
    : QObject(parent)
    , m_textListModel(new TextListModel(this))
    , m_recommendationModel(new RecommendationModel(this))
    , m_libraryProxy(new TextFilterProxyModel(this))
    , m_initialized(false)
    , m_darkMode(false)
    , m_logLevel("INFO")
    , m_currentPage(-1)
    , m_readingTextId(-1)
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
        LOG_INFO("已加载 {} 篇古文", m_allTexts.size());
        m_textListModel->setTexts(m_allTexts);
        m_libraryProxy->setSourceModel(m_textListModel);

        m_tracker = std::make_unique<KnowledgeTracker>(m_incrementRepo.get());

        m_initialized = true;
        emit initializedChanged();

        // 恢复主题偏好
        QSettings settings;
        m_darkMode = settings.value("theme/darkMode", false).toBool();

        emit userNameChanged();
        emit abilityChanged();
        emit statsChanged();
        emit darkModeChanged();

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

    if (!m_initialized) {
        emit errorOccurred("系统未初始化");
        return result;
    }

    time_t now = time(nullptr);
    m_tracker->applyForgettingEffect(m_user, now);
    m_tracker->pruneOldIncrements(m_user, now);

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

QVariantMap AppViewModel::getTextDetail(int textId)
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

    emit errorOccurred("未找到该篇目");
    return detail;
}

bool AppViewModel::recordReading(int textId, double readTime)
{
    if (!m_initialized) {
        emit errorOccurred("系统未初始化");
        return false;
    }

    LOG_INFO("阅读记录: textId={}, readTime={:.0f}s", textId, readTime);

    if (readTime < Config::MIN_READ_TIME) {
        LOG_INFO("阅读时长 {}s 不足 {}s，跳过记录", readTime, Config::MIN_READ_TIME);
        return false;
    }

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
    m_tracker->pruneOldIncrements(m_user, now);
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

bool AppViewModel::darkMode() const
{
    return m_darkMode;
}

void AppViewModel::setDarkMode(bool mode)
{
    if (m_darkMode != mode) {
        m_darkMode = mode;
        QSettings settings;
        settings.setValue("theme/darkMode", mode);
        emit darkModeChanged();
    }
}

QString AppViewModel::logLevel() const
{
    return m_logLevel;
}

void AppViewModel::setLogLevel(const QString &level)
{
    if (m_logLevel != level) {
        m_logLevel = level;
        Logger::getInstance().setLevel(level.toLower().toStdString());
        LOG_INFO("日志级别已切换为: {}", level.toStdString());
        emit logLevelChanged();
    }
}

void AppViewModel::loadTextForReading(int textId, int availWidth, int availHeight)
{
    if (availWidth <= 0 || availHeight <= 0) {
        emit errorOccurred("页面尺寸无效");
        return;
    }

    // fetch full text content
    QVariantMap detail = getTextDetail(textId);
    if (detail.isEmpty())
        return;  // getTextDetail 已 emit errorOccurred

    m_fullContent = detail["content"].toString();
    if (m_fullContent.isEmpty()) {
        emit errorOccurred("篇目内容为空");
        return;
    }

    m_readingTextId = textId;

    constexpr int kReadingFontSize = 18;
    QFont font("Source Han Serif SC");
    font.setPixelSize(kReadingFontSize);

    constexpr double kLineHeight = 1.8;
    constexpr int kFramePadding = 16;
    const int innerW = availWidth - 2 * kFramePadding;
    const int innerH = availHeight - 2 * kFramePadding;

    m_pages = Paginator::paginate(m_fullContent, font, kLineHeight, innerW, innerH);

    if (m_pages.empty()) {
        m_currentPage = -1;
        m_readingTextId = -1;
        emit currentPageChanged();
        emit pageLayoutChanged();
        return;
    }

    m_currentPage = 0;
    emit currentPageChanged();
    emit pageLayoutChanged();
}

void AppViewModel::nextPage()
{
    if (m_currentPage < 0 || m_pages.empty())
        return;

    int nxt = m_currentPage + 1;
    if (nxt >= static_cast<int>(m_pages.size()))
        return;

    m_currentPage = nxt;
    emit currentPageChanged();
}

void AppViewModel::prevPage()
{
    if (m_currentPage <= 0)
        return;

    m_currentPage--;
    emit currentPageChanged();
}

void AppViewModel::recalcPagination(int newWidth, int newHeight)
{
    if (m_readingTextId < 0 || m_fullContent.isEmpty())
        return;

    const int oldCharPos = (m_currentPage >= 0 && m_currentPage < static_cast<int>(m_pages.size()))
        ? m_pages[m_currentPage].charStart
        : 0;

    constexpr int kReadingFontSize = 18;
    QFont font("Source Han Serif SC");
    font.setPixelSize(kReadingFontSize);

    constexpr double kLineHeight = 1.8;
    constexpr int kFramePadding = 16;
    const int innerW = newWidth - 2 * kFramePadding;
    const int innerH = newHeight - 2 * kFramePadding;

    m_pages = Paginator::paginate(m_fullContent, font, kLineHeight, innerW, innerH);

    if (m_pages.empty()) {
        m_currentPage = -1;
        emit currentPageChanged();
        emit pageLayoutChanged();
        return;
    }

    m_currentPage = Paginator::findPageForCharPos(m_pages, oldCharPos);
    emit currentPageChanged();
    emit pageLayoutChanged();
}

int AppViewModel::currentPage() const
{
    return m_currentPage;
}

int AppViewModel::totalPages() const
{
    return static_cast<int>(m_pages.size());
}

QString AppViewModel::currentPageText() const
{
    if (m_currentPage < 0 || m_currentPage >= static_cast<int>(m_pages.size()))
        return QString();

    return m_pages[m_currentPage].text;
}

QString AppViewModel::currentPageNumberLabel() const
{
    if (m_currentPage < 0 || m_pages.empty())
        return QString();

    return QString::number(m_currentPage + 1) + " / " + QString::number(m_pages.size());
}
