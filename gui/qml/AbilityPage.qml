import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "qrc:/qml"

Page {
    id: root
    background: Rectangle { color: Theme.paper }

    readonly property var dimKeys: [
        "avg_sentence_length", "sentence_count", "function_word_ratio",
        "avg_char_log_freq", "tongjiazi_density", "ppl_ancient", "ppl_modern",
        "mattr", "allusion_density", "semantic_complexity"
    ]
    readonly property var dimLabels: [
        "平均句长", "句子数量", "虚词比例", "字频对数", "通假密度",
        "古PPL", "现PPL", "MATTR", "典故密度", "语义复杂度"
    ]

    property var breakdown: ({})
    property var animPrevValues: new Array(10).fill(0)
    property var animValues: new Array(10).fill(0)
    property real animT: 1.0

    function loadBreakdown() {
        var newBreakdown = appViewModel.getAbilityBreakdown()
        for (var i = 0; i < dimKeys.length; i++) {
            animPrevValues[i] = animValues[i]
        }
        breakdown = newBreakdown
        animT = 0
        animTimer.start()
    }

    Timer {
        id: animTimer
        interval: 16
        repeat: true
        property real startTime: 0

        onTriggered: {
            if (startTime === 0) startTime = Date.now()
            var elapsed = Date.now() - startTime
            var rawT = Math.min(1.0, elapsed / 500)
            animT = 1 - Math.pow(1 - rawT, 3)
            for (var i = 0; i < root.dimKeys.length; i++) {
                var target = root.breakdown[root.dimKeys[i]] || 0
                root.animValues[i] = root.animPrevValues[i] + (target - root.animPrevValues[i]) * animT
            }
            chart.requestPaint()
            if (rawT >= 1.0) {
                stop()
                startTime = 0
            }
        }
    }

    function abilityAt(idx) {
        return animValues[idx]
    }

    Component.onCompleted: loadBreakdown()

    Connections {
        target: appViewModel
        function onAbilityChanged() { loadBreakdown() }
    }

    Flickable {
        id: abilityFlick
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
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.baseUnit * 2

                Text {
                    text: "我的能力"
                    font.family: Theme.fontTitle
                    font.pixelSize: Theme.sizeDisplay
                    color: Theme.ink
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "综合: " + (appViewModel.averageAbility * 100).toFixed(1) + "%"
                    font.family: Theme.fontUI
                    font.pixelSize: Theme.sizeH2
                    color: Theme.inkSecondary
                }
            }

            // ── Divider ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // ── Radar chart ──
            Canvas {
                id: chart
                Layout.fillWidth: true
                implicitHeight: width * 0.7
                Layout.maximumWidth: 500
                Layout.maximumHeight: 350
                Layout.alignment: Qt.AlignHCenter
                antialiasing: true

                onPaint: {
                    var ctx = getContext("2d")
                    var w = width
                    var h = height
                    var cx = w / 2
                    var cy = h / 2
                    var radius = Math.min(cx, cy) * 0.58
                    var n = 10
                    var levels = 5

                    ctx.clearRect(0, 0, w, h)

                    // ── Grid polygons ──
                    for (var l = 1; l <= levels; l++) {
                        var fraction = l / levels
                        ctx.beginPath()
                        for (var i = 0; i < n; i++) {
                            var angle = -Math.PI / 2 + i * 2 * Math.PI / n
                            var gx = cx + fraction * radius * Math.cos(angle)
                            var gy = cy + fraction * radius * Math.sin(angle)
                            if (i === 0) ctx.moveTo(gx, gy)
                            else ctx.lineTo(gx, gy)
                        }
                        ctx.closePath()
                        ctx.strokeStyle = Theme.borderLight
                        ctx.lineWidth = 0.5
                        ctx.stroke()
                    }

                    // ── Axis lines ──
                    for (var j = 0; j < n; j++) {
                        var a = -Math.PI / 2 + j * 2 * Math.PI / n
                        ctx.beginPath()
                        ctx.moveTo(cx, cy)
                        ctx.lineTo(cx + radius * Math.cos(a), cy + radius * Math.sin(a))
                        ctx.strokeStyle = Theme.border
                        ctx.lineWidth = 1
                        ctx.stroke()
                    }

                    // ── Data polygon ──
                    ctx.beginPath()
                    for (var k = 0; k < n; k++) {
                        var dAngle = -Math.PI / 2 + k * 2 * Math.PI / n
                        var val = root.abilityAt(k)
                        var dx = cx + val * radius * Math.cos(dAngle)
                        var dy = cy + val * radius * Math.sin(dAngle)
                        if (k === 0) ctx.moveTo(dx, dy)
                        else ctx.lineTo(dx, dy)
                    }
                    ctx.closePath()
                    ctx.fillStyle = "rgba(" + Math.round(Theme.vermilion.r * 255) + ", " + Math.round(Theme.vermilion.g * 255) + ", " + Math.round(Theme.vermilion.b * 255) + ", 0.15)"
                    ctx.fill()
                    ctx.strokeStyle = Theme.vermilion
                    ctx.lineWidth = 2
                    ctx.stroke()

                    // ── Data points ──
                    for (var m = 0; m < n; m++) {
                        var pAngle = -Math.PI / 2 + m * 2 * Math.PI / n
                        var pVal = root.abilityAt(m)
                        var px = cx + pVal * radius * Math.cos(pAngle)
                        var py = cy + pVal * radius * Math.sin(pAngle)
                        ctx.beginPath()
                        ctx.arc(px, py, 3, 0, 2 * Math.PI)
                        ctx.fillStyle = Theme.vermilion
                        ctx.fill()
                    }

                    // ── Axis labels ──
                    var labelRadius = radius + 16
                    ctx.font = (Theme.sizeSmall - 1) + "px '" + Theme.fontUI + "'"
                    ctx.textAlign = "center"
                    ctx.textBaseline = "middle"
                    for (var r = 0; r < n; r++) {
                        var lAngle = -Math.PI / 2 + r * 2 * Math.PI / n
                        var lx = cx + labelRadius * Math.cos(lAngle)
                        var ly = cy + labelRadius * Math.sin(lAngle)
                        ctx.fillStyle = Theme.inkSecondary
                        ctx.fillText(root.dimLabels[r], lx, ly)
                    }
                }
            }

            // ── Dimension bars ──
            Repeater {
                model: root.dimKeys.length
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.baseUnit

                    Text {
                        Layout.preferredWidth: 72
                        text: root.dimLabels[index]
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeCaption
                        color: Theme.inkSecondary
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10
                        radius: 2
                        color: Qt.rgba(Theme.vermilion.r, Theme.vermilion.g, Theme.vermilion.b, 0.12)

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * root.abilityAt(index)
                            radius: 2
                            color: Theme.vermilion
                        }
                    }

                    Text {
                        Layout.preferredWidth: 40
                        text: (root.abilityAt(index) * 100).toFixed(0) + "%"
                        font.family: Theme.fontUI
                        font.pixelSize: Theme.sizeSmall
                        color: Theme.inkSecondary
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
