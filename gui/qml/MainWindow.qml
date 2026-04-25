import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

ApplicationWindow {
    title: "古典文学阅读推荐"
    minimumWidth: 1024
    minimumHeight: 768
    visible: true

    FontLoader { source: fontDir + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf" }
    FontLoader { source: fontDir + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf" }
    FontLoader { source: fontDir + "LXGWWenKai-Regular/LXGWWenKai-Regular.ttf" }
    FontLoader { source: fontDir + "LXGWWenKai-Regular/LXGWWenKai-Light.ttf" }
    FontLoader { source: fontDir + "LXGWWenKai-Regular/LXGWWenKai-Medium.ttf" }
    FontLoader { source: fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf" }
    FontLoader { source: fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Light.otf" }
    FontLoader { source: fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf" }

    Component {
        id: libraryPage
        LibraryPage {}
    }
    Component {
        id: recommendPage
        RecommendPage {}
    }
    Component {
        id: readPage
        ReadPage {}
    }
    Component {
        id: abilityPage
        AbilityPage {}
    }
    Component {
        id: settingsPage
        SettingsPage {}
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.preferredWidth: 220
            Layout.fillHeight: true
            currentIndex: 0

            onClicked: function(index) {
                switch (index) {
                    case 0: contentStack.replace(libraryPage); break;
                    case 1: contentStack.replace(recommendPage); break;
                    case 2: contentStack.replace(abilityPage); break;
                    case 3: contentStack.replace(settingsPage); break;
                }
            }
        }

        StackView {
            id: contentStack
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: libraryPage
        }
    }
}
