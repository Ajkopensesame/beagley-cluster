import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    property color color: "red"

    readonly property real s: Math.min(width, height)
    readonly property real sw: Math.max(3, s * 0.08)
    readonly property real r:  root.s * 0.34

    Rectangle {
        anchors.centerIn: parent
        width: r * 2
        height: r * 2
        radius: r
        color: "transparent"
        border.width: sw
        border.color: root.color
        opacity: 0.95
    }

    Repeater {
        model: 6
        Rectangle {
            width: sw * 1.1
            height: root.s * 0.14
            radius: width / 2
            color: root.color
            opacity: 0.90
            anchors.centerIn: parent
            rotation: index * 60
            y: -r - height * 0.30
            transformOrigin: Item.Center
        }
    }

    Text {
        anchors.centerIn: parent
        text: "AT"
        color: root.color
        font.family: "DejaVu Sans Mono"
        font.bold: true
        font.pixelSize: Math.round(root.s * 0.26)
        opacity: 0.95
    }
}
