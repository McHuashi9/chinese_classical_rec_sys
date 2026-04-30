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
        id: navColumn
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

            ItemDelegate {
                id: navItem
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                hoverEnabled: true

                background: Rectangle {
                    color: (navItem.hovered || root.currentIndex === index)
                           ? Theme.card : "transparent"

                    Rectangle {
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: 3
                        color: Theme.vermilion
                        visible: navItem.hovered || root.currentIndex === index
                    }
                }

                contentItem: Text {
                    text: navColumn.labels[index]
                    font.family: Theme.fontTitle
                    font.pixelSize: Theme.sizeH2
                    font.bold: root.currentIndex === index
                    color: Theme.ink
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 16
                }

                onClicked: root.clicked(index)
            }
        }

        Item { Layout.fillHeight: true }
    }
}
