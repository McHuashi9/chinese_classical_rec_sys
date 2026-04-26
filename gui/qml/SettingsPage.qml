import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Page {
    id: root
    background: Rectangle { color: Theme.paper }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.baseUnit * 6
        clip: true

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: contentColumn
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: Theme.baseUnit * 3
            }
            width: Math.min(parent.width, 900)
            spacing: Theme.baseUnit * 2

            // ── Header ──
            Text {
                text: "设置"
                font.family: Theme.fontTitle
                font.pixelSize: Theme.sizeDisplay
                color: Theme.ink
            }

            // ── Divider ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // ── Card: Appearance ──
            Rectangle {
                id: appearanceCard
                Layout.fillWidth: true
                implicitHeight: appearanceRow.implicitHeight + Theme.cardPadding * 2
                color: "transparent"

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.leftMargin: 1
                    color: Qt.rgba(44/255, 36/255, 22/255, 0.08)
                    radius: 4
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.card
                    border.color: Theme.border
                    border.width: 1
                    radius: 4

                    RowLayout {
                        id: appearanceRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.cardPadding
                            rightMargin: Theme.cardPadding
                        }
                        spacing: Theme.baseUnit * 2

                        Text {
                            text: "外观"
                            font.family: Theme.fontTitle
                            font.pixelSize: Theme.sizeH2
                            color: Theme.ink
                        }

                        Text {
                            text: "主题"
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeBody
                            color: Theme.inkSecondary
                        }

                        Item { Layout.fillWidth: true }

                        // ── Segmented theme toggle ──
                        RowLayout {
                            spacing: 0

                            Rectangle {
                                id: lightSegment
                                width: 56
                                height: 32

                                readonly property bool selected: !Theme.darkMode
                                color: selected ? Theme.vermilion : "transparent"
                                border.color: Theme.border
                                border.width: 1
                                radius: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "亮色"
                                    font.family: Theme.fontUI
                                    font.pixelSize: Theme.sizeCaption
                                    color: lightSegment.selected ? "#FFFFFF" : Theme.ink
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Theme.darkMode = false
                                        appViewModel.darkMode = false
                                    }
                                }
                            }

                            Rectangle {
                                id: darkSegment
                                width: 56
                                height: 32

                                readonly property bool selected: Theme.darkMode
                                color: selected ? Theme.vermilion : "transparent"
                                border.color: Theme.border
                                border.width: 1
                                radius: 0

                                Text {
                                    anchors.centerIn: parent
                                    text: "暗色"
                                    font.family: Theme.fontUI
                                    font.pixelSize: Theme.sizeCaption
                                    color: darkSegment.selected ? "#FFFFFF" : Theme.ink
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Theme.darkMode = true
                                        appViewModel.darkMode = true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Card: Logging ──
            Rectangle {
                id: loggingCard
                Layout.fillWidth: true
                implicitHeight: loggingRow.implicitHeight + Theme.cardPadding * 2

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 1
                    anchors.leftMargin: 1
                    color: Qt.rgba(44/255, 36/255, 22/255, 0.08)
                    radius: 4
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.card
                    border.color: Theme.border
                    border.width: 1
                    radius: 4

                    RowLayout {
                        id: loggingRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.cardPadding
                            rightMargin: Theme.cardPadding
                        }
                        spacing: Theme.baseUnit * 2

                        Text {
                            text: "日志"
                            font.family: Theme.fontTitle
                            font.pixelSize: Theme.sizeH2
                            color: Theme.ink
                        }

                        Text {
                            text: "日志级别"
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeBody
                            color: Theme.inkSecondary
                        }

                        Item { Layout.fillWidth: true }

                        ComboBox {
                            id: logLevelCombo
                            width: 140
                            model: ["INFO", "DEBUG", "WARNING", "ERROR"]
                            currentIndex: 0

                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeBody

                            contentItem: Text {
                                text: logLevelCombo.displayText
                                font: logLevelCombo.font
                                color: Theme.ink
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: Theme.baseUnit
                            }

                            background: Rectangle {
                                color: "transparent"
                                Rectangle {
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        bottom: parent.bottom
                                    }
                                    height: logLevelCombo.activeFocus ? 2 : 1
                                    color: logLevelCombo.activeFocus ? Theme.vermilion : Theme.border
                                }
                            }

                            indicator: Text {
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: Theme.baseUnit
                                }
                                text: "▾"
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeSmall
                                color: Theme.inkSecondary
                            }

                            delegate: ItemDelegate {
                                width: logLevelCombo.width
                                contentItem: Text {
                                    text: modelData
                                    font: logLevelCombo.font
                                    color: highlighted ? Theme.vermilion : Theme.ink
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle {
                                    color: highlighted ? Qt.rgba(179/255, 58/255, 58/255, 0.08) : "transparent"
                                }
                                highlighted: logLevelCombo.highlightedIndex === index
                            }

                            popup: Popup {
                                y: logLevelCombo.height
                                width: logLevelCombo.width
                                implicitHeight: contentItem.implicitHeight
                                padding: 4

                                contentItem: ListView {
                                    implicitHeight: contentHeight
                                    clip: true
                                    model: logLevelCombo.popup.visible ? logLevelCombo.delegateModel : null
                                    currentIndex: logLevelCombo.highlightedIndex
                                }

                                background: Rectangle {
                                    color: Theme.card
                                    border.color: Theme.border
                                    border.width: 1
                                    radius: 4
                                }
                            }

                            onActivated: {
                                appViewModel.setLogLevel(currentText)
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
