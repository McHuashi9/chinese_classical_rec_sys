import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Page {
    id: root
    background: Rectangle { color: Theme.paper }

    signal openText(int textId)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.baseUnit * 3
        spacing: Theme.baseUnit * 2

        // ── Centered content ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width, 900)
                spacing: Theme.baseUnit * 2

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.baseUnit * 2

                    Text {
                        text: "文库"
                        font.family: Theme.fontTitle
                        font.pixelSize: Theme.sizeDisplay
                        color: Theme.ink
                    }

                    Text {
                        text: "(" + listView.count + "篇)"
                        font.family: Theme.fontBody
                        font.pixelSize: Theme.sizeBody
                        color: Theme.inkSecondary
                    }

                    Item { Layout.fillWidth: true }

                    TextField {
                        id: searchField
                        Layout.preferredWidth: 260
                        placeholderText: "搜索篇目或作者…"
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeBody
                        color: Theme.ink

                        background: Rectangle {
                            color: "transparent"
                            Rectangle {
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                height: searchField.activeFocus ? 2 : 1
                                color: searchField.activeFocus ? Theme.vermilion : Theme.border
                            }
                        }

                        leftPadding: Theme.baseUnit
                        rightPadding: Theme.baseUnit

                        onDisplayTextChanged: appViewModel.setLibraryFilter(displayText)
                    }
                }

                // ── Divider ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                }

                // ── List ──
                ListView {
                    id: listView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.listSpacing
                    model: appViewModel.libraryProxyModel

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Item {
                        width: listView.width
                        height: cardLayout.implicitHeight + Theme.baseUnit * 2

                        // Shadow
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1
                            anchors.leftMargin: 1
                            color: Qt.rgba(44/255, 36/255, 22/255, mouseArea.containsMouse ? 0.12 : 0.08)
                            radius: 4
                        }

                        // Card
                        Rectangle {
                            anchors.fill: parent
                            color: mouseArea.containsMouse ? Theme.card : Theme.card
                            border.color: Theme.border
                            border.width: 1
                            radius: 4
                        }

                        RowLayout {
                            id: cardLayout
                            anchors {
                                left: parent.left
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.cardPadding
                                rightMargin: Theme.cardPadding
                            }
                            spacing: Theme.baseUnit

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: model.title
                                    font.family: Theme.fontTitle
                                    font.pixelSize: Theme.sizeBody
                                    color: Theme.ink
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: model.author + " · " + model.dynasty
                                    font.family: Theme.fontBody
                                    font.pixelSize: Theme.sizeCaption
                                    color: Theme.inkSecondary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Text {
                                text: model.difficulty
                                font.family: Theme.fontUI
                                font.pixelSize: Theme.sizeSmall
                                color: Theme.inkSecondary
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openText(model.textId)
                        }
                    }
                }
            }
        }
    }
}
