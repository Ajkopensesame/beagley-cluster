import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    property color color: "#C7B7FF"
    property string mode: "2wd"
    property bool locked: false

    readonly property real s: Math.min(width, height)
    readonly property real sw: Math.max(3, s * 0.070)
    readonly property real xShift: s * 0.03
    readonly property color dimColor: Qt.rgba(color.r, color.g, color.b, 0.18)
    readonly property bool frontActive: locked || String(mode).toLowerCase().indexOf("4") !== -1
    readonly property bool rearActive: true

    function axleColor(active) {
        return active ? root.color : root.dimColor
    }

    Rectangle {
        x: root.s * 0.16 + root.xShift
        y: root.s * 0.24
        width: root.s * 0.68
        height: root.sw * 0.85
        radius: height / 2
        color: axleColor(frontActive)
    }

    Rectangle {
        x: root.s * 0.16 + root.xShift
        y: root.s * 0.68
        width: root.s * 0.68
        height: root.sw * 0.85
        radius: height / 2
        color: axleColor(rearActive)
    }

    Rectangle {
        x: root.s * 0.48 + root.xShift
        y: root.s * 0.28
        width: root.sw * 0.85
        height: root.s * 0.42
        radius: width / 2
        color: axleColor(frontActive)
    }

    Repeater {
        model: [
            { x: 0.10, y: 0.18, active: root.frontActive },
            { x: 0.72, y: 0.18, active: root.frontActive },
            { x: 0.10, y: 0.62, active: root.rearActive },
            { x: 0.72, y: 0.62, active: root.rearActive }
        ]

        Rectangle {
            required property var modelData
            x: root.s * modelData.x + root.xShift
            y: root.s * modelData.y
            width: root.s * 0.18
            height: width
            radius: width / 2
            color: "transparent"
            border.width: root.sw * 0.72
            border.color: axleColor(modelData.active)
        }
    }

    Rectangle {
        x: root.s * 0.42 + root.xShift
        y: root.s * 0.18
        width: root.s * 0.14
        height: width
        radius: width / 2
        color: axleColor(frontActive)
    }

    Rectangle {
        x: root.s * 0.42 + root.xShift
        y: root.s * 0.62
        width: root.s * 0.14
        height: width
        radius: width / 2
        color: axleColor(rearActive)
    }

    Item {
        visible: root.locked
        x: root.s * 0.40 + root.xShift
        y: root.s * 0.38
        width: root.s * 0.20
        height: root.s * 0.20

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height * 0.62
            radius: root.sw * 0.55
            color: "transparent"
            border.width: root.sw * 0.75
            border.color: root.color
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: parent.width * 0.54
            height: parent.height * 0.46
            radius: width / 2
            color: "transparent"
            border.width: root.sw * 0.72
            border.color: root.color
        }
    }
}
