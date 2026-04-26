import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Page {
    id: root
    background: Rectangle { color: Theme.paper }

    signal openText(int textId)

    function refresh() {
        appViewModel.getRecommendations(topKSpin.value)
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors {
            fill: parent
            margins: Theme.baseUnit * 3
        }

        // ── Centered content, max 900px ──
        ColumnLayout {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                bottom: parent.bottom
            }
            width: Math.min(parent.width, 900)
            spacing: Theme.baseUnit * 2

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.baseUnit * 2

                Text {
                    text: "为你推荐"
                    font.family: Theme.fontTitle
                    font.pixelSize: Theme.sizeDisplay
                    color: Theme.ink
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "篇数"
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeCaption
                    color: Theme.inkSecondary
                }

                SpinBox {
                    id: topKSpin
                    from: 1
                    to: 50
                    value: 10
                    editable: true
                    Layout.preferredWidth: 80

                    contentItem: TextInput {
                        text: topKSpin.displayText
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeBody
                        color: Theme.ink
                        horizontalAlignment: Qt.AlignHCenter
                        readOnly: !topKSpin.editable
                        validator: topKSpin.validator
                        inputMethodHints: Qt.ImhDigitsOnly
                    }

                    background: Rectangle {
                        color: "transparent"
                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            height: topKSpin.activeFocus ? 2 : 1
                            color: topKSpin.activeFocus ? Theme.vermilion : Theme.border
                        }
                    }
                }

                // Primary button
                Rectangle {
                    Layout.preferredWidth: btnText.implicitWidth + 24
                    Layout.preferredHeight: 36
                    color: btnMouse.pressed ? Theme.vermilionHover : Theme.vermilion
                    scale: btnMouse.pressed ? 0.98 : 1.0

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }

                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: "生成推荐"
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeCaption
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: refresh()
                    }
                }
            }

            // ── Divider ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // ── Empty state ──
            Text {
                visible: listView.count === 0
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                topPadding: Theme.baseUnit * 6
                text: "点击「生成推荐」获取个性化篇目"
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeBody
                color: Theme.inkSecondary
                horizontalAlignment: Text.AlignHCenter
            }

            // ── Result list ──
            ListView {
                id: listView
                visible: count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: appViewModel.recommendationModel

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Item {
                    width: listView.width
                    height: cardLayout.implicitHeight + Theme.cardPadding

                    Rectangle {
                        anchors {
                            fill: parent
                            topMargin: 1
                            leftMargin: 1
                        }
                        color: Qt.rgba(44/255, 36/255, 22/255, mouseArea.containsMouse ? 0.12 : 0.08)
                        radius: 4
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.card
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
                            text: (model.probability * 100).toFixed(1) + "%"
                            font.family: Theme.fontUI
                            font.pixelSize: Theme.sizeBody
                            font.bold: true
                            color: Theme.vermilion
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
