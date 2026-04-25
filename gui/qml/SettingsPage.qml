import QtQuick
import QtQuick.Controls
import "qrc:/qml"

Page {
    background: Rectangle { color: Theme.paper }

    Label {
        anchors.centerIn: parent
        text: "设置"
        font.family: Theme.fontTitle
        font.pixelSize: Theme.sizeH1
        color: Theme.ink
    }
}
