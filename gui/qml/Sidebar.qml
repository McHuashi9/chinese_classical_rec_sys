import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Rectangle {
    id: root

    required property int currentIndex
    signal clicked(int index)

    implicitWidth: 220
    color: Theme.paper

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.border
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        readonly property var labels: [
            "文  库",
            "推  荐",
            "我的能力",
            "设  置"
        ]

        Repeater {
            model: 4

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 48

                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 3
                    color: Theme.vermilion
                    visible: mouseArea.containsMouse || root.currentIndex === index
                }

                Rectangle {
                    anchors.fill: parent
                    color: (mouseArea.containsMouse || root.currentIndex === index)
                           ? Theme.card : "transparent"
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: parent.parent.labels[index]
                    font.family: Theme.fontTitle
                    font.pixelSize: Theme.sizeH2
                    font.bold: root.currentIndex === index
                    color: Theme.ink
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clicked(index)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
