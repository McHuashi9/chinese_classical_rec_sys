import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

ApplicationWindow {
    title: "古典文学阅读推荐"
    minimumWidth: 1024
    minimumHeight: 768
    visible: true

    Component.onCompleted: Theme.darkMode = appViewModel.darkMode

    FontLoader { source: "file://" + fontDir + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Regular.ttf" }
    FontLoader { source: "file://" + fontDir + "HarmonyOS Sans 字体/HarmonyOS_SansSC/HarmonyOS_SansSC_Bold.ttf" }
    FontLoader { source: "file://" + fontDir + "LXGWWenKai-Regular/LXGWWenKai-Regular.ttf" }
    FontLoader { source: "file://" + fontDir + "LXGWWenKai-Regular/LXGWWenKai-Light.ttf" }
    FontLoader { source: "file://" + fontDir + "LXGWWenKai-Regular/LXGWWenKai-Medium.ttf" }
    FontLoader { source: "file://" + fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Regular.otf" }
    FontLoader { source: "file://" + fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Light.otf" }
    FontLoader { source: "file://" + fontDir + "SourceHanSerifSC/OTF/SimplifiedChinese/SourceHanSerifSC-Bold.otf" }

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
        ReadPage { textId: 0 }
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

            // ── Transitions: sidebar nav → horizontal slide ──
            replaceEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: contentStack.width * 0.3
                    to: 0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 200
                }
            }
            replaceExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -contentStack.width * 0.2
                    duration: 200
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: 200
                }
            }

            // ── Transitions: push/pop → crossfade ──
            pushEnter: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            pushExit: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            popEnter: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
            popExit: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            function openText(textId) {
                var props = {"textId": textId}
                push(readPage.createObject(contentStack, props))
            }
        }
    }
}
