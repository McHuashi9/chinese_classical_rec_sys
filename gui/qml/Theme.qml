pragma Singleton

import QtQuick

QtObject {
    // ── Color Tokens ──
    readonly property color paper: "#F5F0E8"
    readonly property color card: "#FFFDF7"
    readonly property color ink: "#2C2416"
    readonly property color inkSecondary: "#5A5245"
    readonly property color vermilion: "#B33A3A"
    readonly property color vermilionHover: "#932E2E"
    readonly property color stoneGreen: "#5B7B4A"
    readonly property color border: "#C2B28F"
    readonly property color borderLight: "#D4C9A8"
    readonly property color overlay: Qt.rgba(28/255, 24/255, 18/255, 0.80)

    // ── Font Families ──
    readonly property string fontTitle: "LXGW WenKai"
    readonly property string fontBody: "Source Han Serif SC"
    readonly property string fontUI: "HarmonyOS Sans SC"

    // ── Type Scale (4px modulus) ──
    readonly property int sizeDisplay: 36
    readonly property int sizeH1: 24
    readonly property int sizeH2: 20
    readonly property int sizeBody: 16
    readonly property int sizeCaption: 14
    readonly property int sizeSmall: 12

    // ── Spacing (base 8px) ──
    readonly property int baseUnit: 8
    readonly property int cardPadding: 16
    readonly property int listSpacing: 8
    readonly property int framePadding: 12
}
