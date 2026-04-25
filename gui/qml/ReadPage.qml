import QtQuick
import QtQuick.Controls
import "qrc:/qml"

Page {
    required property int textId

    background: Rectangle { color: Theme.paper }

    readonly property var detail: appViewModel.getTextDetail(textId)

    Label {
        anchors.centerIn: parent
        text: detail.title || "阅读"
        font.family: Theme.fontTitle
        font.pixelSize: Theme.sizeH1
        color: Theme.ink
    }
}
