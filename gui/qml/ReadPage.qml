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
    property bool readingRecorded: false

    function fmtTime(secs) {
        var m = Math.floor(secs / 60)
        var s = secs % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function recordAndPop() {
        if (elapsedSeconds >= 30) {
            appViewModel.recordReading(textId, elapsedSeconds)
            readingRecorded = true
        }
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
        if (!readingRecorded && elapsedSeconds >= 30)
            appViewModel.recordReading(textId, elapsedSeconds)
    }

    // ── trigger pagination after first layout ──
    property bool pagesLoaded: false

    // ── debounced repagination on resize ──
    Timer {
        id: resizeTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (pagesLoaded)
                appViewModel.recalcPagination(frame.width, frame.height)
        }
    }

    // ── Keyboard navigation ──
    Keys.onLeftPressed: appViewModel.prevPage()
    Keys.onRightPressed: appViewModel.nextPage()

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
            font.underline: mouse.containsMouse

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
            id: frame
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

            onHeightChanged: {
                if (height > 0 && width > 0 && !pagesLoaded) {
                    pagesLoaded = true
                    appViewModel.loadTextForReading(textId, width, height)
                }
                if (pagesLoaded)
                    resizeTimer.restart()
            }
            onWidthChanged: { if (pagesLoaded) resizeTimer.restart() }

            Text {
                id: contentText
                anchors {
                    fill: parent
                    margins: Theme.cardPadding
                }
                text: appViewModel.currentPageText
                font.family: Theme.fontBody
                font.pixelSize: 18
                lineHeight: 1.8
                color: Theme.ink
                wrapMode: Text.NoWrap
                textFormat: Text.PlainText
                clip: true
            }
        }

        // ── Navigation + Timer ──
        RowLayout {
            Layout.fillWidth: true

            // ◀ 上一页
            ItemDelegate {
                id: prevBtn
                Layout.preferredWidth: 80
                enabled: appViewModel.currentPage > 0
                opacity: enabled ? 1.0 : 0.4

                contentItem: Text {
                    text: "◀ 上一页"
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeCaption
                    color: parent.hovered && parent.enabled ? Theme.vermilionHover : Theme.inkSecondary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: prevBtn.hovered && prevBtn.enabled ? Theme.borderLight : "transparent"
                    radius: 4
                }

                onClicked: { if (enabled) appViewModel.prevPage() }
            }

            // Timer
            Text {
                Layout.fillWidth: true
                text: fmtTime(elapsedSeconds)
                font.family: Theme.fontUI
                font.pixelSize: Theme.sizeBody
                color: Theme.inkSecondary
                horizontalAlignment: Text.AlignHCenter
            }

            // 下一页 ▶
            ItemDelegate {
                id: nextBtn
                Layout.preferredWidth: 80
                enabled: appViewModel.currentPage < appViewModel.totalPages - 1
                opacity: enabled ? 1.0 : 0.4

                contentItem: Text {
                    text: "下一页 ▶"
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeCaption
                    color: parent.hovered && parent.enabled ? Theme.vermilionHover : Theme.inkSecondary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    color: nextBtn.hovered && nextBtn.enabled ? Theme.borderLight : "transparent"
                    radius: 4
                }

                onClicked: { if (enabled) appViewModel.nextPage() }
            }
        }

        // Page number
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: appViewModel.currentPageNumberLabel
            font.family: Theme.fontBody
            font.pixelSize: Theme.sizeCaption
            color: Theme.border
            visible: appViewModel.currentPage >= 0
        }
    }
}
