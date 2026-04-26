import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Page {
    id: root
    required property int textId

    background: Rectangle { color: Theme.paper }

    readonly property var detail: appViewModel.getTextDetail(textId)
    property int elapsedSeconds: 0

    function fmtTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function recordAndPop() {
        if (elapsedSeconds >= 30)
            appViewModel.recordReading(textId, elapsedSeconds)
        root.StackView.view.pop()
    }

    Timer {
        id: readTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: elapsedSeconds++
    }

    Component.onDestruction: {
        if (elapsedSeconds >= 30)
            appViewModel.recordReading(textId, elapsedSeconds)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Theme.baseUnit * 3
        }
        width: Math.min(parent.width, 900)

        // Back button
        Text {
            text: "< 返回"
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeCaption
            color: mouse.containsMouse ? Theme.vermilionHover : Theme.vermilion

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: recordAndPop()
            }
        }

        // Title
        Text {
            Layout.topMargin: Theme.baseUnit * 2
            text: detail.title || ""
            font.family: Theme.fontTitle
            font.pixelSize: Theme.sizeH1
            color: Theme.ink
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Author & Dynasty
        Text {
            text: (detail.author && detail.dynasty)
                  ? detail.author + " · " + detail.dynasty
                  : (detail.author || detail.dynasty || "")
            font.family: Theme.fontBody
            font.pixelSize: Theme.sizeCaption
            color: Theme.inkSecondary
        }

        // Reading frame
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Theme.baseUnit * 2
            Layout.bottomMargin: Theme.baseUnit * 2
            color: Theme.card
            border {
                width: 1
                color: Theme.border
            }
            radius: 4

            Flickable {
                id: flick
                anchors {
                    fill: parent
                    margins: Theme.cardPadding
                }
                clip: true
                contentWidth: width
                contentHeight: contentText.implicitHeight

                Text {
                    id: contentText
                    width: flick.width
                    text: detail.content || ""
                    font.family: Theme.fontBody
                    font.pixelSize: 18
                    lineHeight: 1.8
                    color: Theme.ink
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }
            }

        }

        // ── Timer ──
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: fmtTime(elapsedSeconds)
            font.family: Theme.fontUI
            font.pixelSize: Theme.sizeBody
            color: Theme.inkSecondary
        }
    }
}
