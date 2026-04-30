pragma Singleton

import QtQuick

QtObject {
    property bool darkMode: false

    // ── Color Tokens ──
    readonly property color paper: darkMode ? "#1C1812" : "#F5F0E8"
    readonly property color card: darkMode ? "#2A251D" : "#FFFDF7"
    readonly property color ink: darkMode ? "#D4C9A8" : "#2C2416"
    readonly property color inkSecondary: darkMode ? "#9A9278" : "#5A5245"
    readonly property color vermilion: darkMode ? "#C75B5B" : "#B33A3A"
    readonly property color vermilionHover: darkMode ? "#A84848" : "#932E2E"
    readonly property color stoneGreen: darkMode ? "#4A6B3A" : "#5B7B4A"
    readonly property color border: darkMode ? "#5A5245" : "#C2B28F"
    readonly property color borderLight: darkMode ? "#4A4235" : "#D4C9A8"
    readonly property color overlay: darkMode ? Qt.rgba(0, 0, 0, 0.80) : Qt.rgba(28/255, 24/255, 18/255, 0.80)
    readonly property color shadow: darkMode ? Qt.rgba(0, 0, 0, 0.20) : Qt.rgba(44/255, 36/255, 22/255, 0.08)

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
