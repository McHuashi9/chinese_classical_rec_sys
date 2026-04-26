#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFontDatabase>
#include <QDir>
#include "viewmodel/AppViewModel.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName("ClassicalReader");
    app.setApplicationName("ClassicalReader");

    const QString fontsPath = QCoreApplication::applicationDirPath() + "/fonts/";

    QFontDatabase::addApplicationFont(fontsPath + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf");
    QFontDatabase::addApplicationFont(fontsPath + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf");
    QFontDatabase::addApplicationFont(fontsPath + "LXGWWenKai-Regular/LXGWWenKai-Regular.ttf");
    QFontDatabase::addApplicationFont(fontsPath + "LXGWWenKai-Regular/LXGWWenKai-Light.ttf");
    QFontDatabase::addApplicationFont(fontsPath + "LXGWWenKai-Regular/LXGWWenKai-Medium.ttf");
    QFontDatabase::addApplicationFont(fontsPath + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf");
    QFontDatabase::addApplicationFont(fontsPath + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Light.otf");
    QFontDatabase::addApplicationFont(fontsPath + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf");

    AppViewModel viewModel;

    const QString dbPath = QCoreApplication::applicationDirPath() + "/data/classical.db";
    viewModel.initialize(dbPath);

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("appViewModel", &viewModel);
    engine.rootContext()->setContextProperty("fontDir", fontsPath);
    engine.load("qrc:/qml/MainWindow.qml");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
