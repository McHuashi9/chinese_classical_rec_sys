#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFontDatabase>
#include <QQuickStyle>
#include <filesystem>
#include "utils/Logger.h"
#include "utils/PathUtils.h"
#include "viewmodel/AppViewModel.h"

int main(int argc, char *argv[])
{
    Logger::getInstance().init(PathUtils::getLogsDir().string());
    LOG_INFO("日志系统已初始化，输出目录: {}", PathUtils::getLogsDir().string());

    QGuiApplication app(argc, argv);
    app.setOrganizationName("ClassicalReader");
    app.setApplicationName("ClassicalReader");

    QQuickStyle::setStyle("Fusion");

    // 首次启动时从捆绑目录复制数据库到可写目录
    auto writableDb = PathUtils::getDbPath();
    auto bundledDb = PathUtils::getBundledDbPath();
    if (!std::filesystem::exists(writableDb) && std::filesystem::exists(bundledDb)) {
        std::filesystem::create_directories(writableDb.parent_path());
        std::filesystem::copy_file(bundledDb, writableDb);
        LOG_INFO("数据库已复制: {} → {}", bundledDb.string(), writableDb.string());
    }

    const QString fontsPath = QString::fromStdWString(PathUtils::getFontsDir().wstring()) + u'/';

    auto loadFont = [&](const QString &relPath) {
        int id = QFontDatabase::addApplicationFont(fontsPath + relPath);
        if (id < 0) {
            LOG_WARN("字体加载失败: {}", (fontsPath + relPath).toStdString());
        }
    };

    loadFont("HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf");
    loadFont("HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf");
    loadFont("LXGWWenKai-Regular/LXGWWenKai-Regular.ttf");
    loadFont("LXGWWenKai-Regular/LXGWWenKai-Light.ttf");
    loadFont("LXGWWenKai-Regular/LXGWWenKai-Medium.ttf");
    loadFont("SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf");
    loadFont("SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Light.otf");
    loadFont("SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf");

    // Log available font families for debugging
    {
        const auto families = QFontDatabase::families();
        LOG_INFO("已注册字体族: {} 个", families.size());
        for (const QString &fam : {"HarmonyOS Sans SC", "LXGW WenKai", "Source Han Serif SC"}) {
            LOG_INFO("  {} → {}", fam.toStdString(), families.contains(fam) ? "可用" : "不可用");
        }
    }

    AppViewModel viewModel;

    const QString dbPath = QString::fromStdWString(writableDb.wstring());
    viewModel.initialize(dbPath);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appViewModel", &viewModel);
    engine.rootContext()->setContextProperty("fontDir", fontsPath);
    engine.load("qrc:/qml/MainWindow.qml");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
