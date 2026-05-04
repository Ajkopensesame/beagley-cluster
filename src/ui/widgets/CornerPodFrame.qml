import QtQuick 2.15

Item {
    id: root

    property string corner: "topLeft"
    property string effectLevel: "high"
    property bool active: true
    property real bleedFraction: 0.18
    property color accentColor: "#0A0C12"
    property color secondaryAccentColor: "#232838"

    readonly property real side: Math.min(width, height)
    readonly property int faceInset: Math.round(side * 0.190)
    readonly property int contentDiameter: Math.round(side * 0.56)
    readonly property int labelWidth: Math.round(side * 0.58)
    readonly property int iconSize: Math.round(side * 0.31)

    default property alias content: contentLayer.data

    CornerCircleShell {
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.active
        accentColor: root.accentColor
        secondaryAccentColor: root.secondaryAccentColor
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.max(2, Math.round(root.side * 0.014))
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Math.round(root.side * 0.018))
        border.color: Qt.rgba(0.86, 0.90, 0.98, root.active ? 0.24 : 0.18)
        opacity: 0.92
        z: 1
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: root.faceInset
        radius: width / 2
        color: "#020409"
        border.width: 1
        border.color: Qt.rgba(0.86, 0.90, 0.98, root.active ? 0.18 : 0.11)
        opacity: 0.94
        z: 1
    }

    Item {
        id: contentLayer
        anchors.fill: parent
        z: 2
    }
}
