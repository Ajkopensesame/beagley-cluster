import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "red"

    readonly property real s: Math.min(width, height)
    readonly property real strokeW: Math.max(3, s * 0.07)
    readonly property real pad: Math.max(6, s * 0.12)

    // Battery body (outline)
    Rectangle {
        id: body
        anchors.centerIn: parent
        width: root.s - (root.pad * 2)
        height: root.s * 0.54
        radius: Math.round(root.s * 0.07)
        color: "transparent"
        border.width: root.strokeW
        border.color: root.color
        opacity: 0.95
    }

    // Terminals (top posts)
    Rectangle {
        width: root.s * 0.16
        height: root.strokeW * 1.25
        radius: height / 2
        color: root.color
        opacity: 0.95
        anchors.bottom: body.top
        anchors.bottomMargin: root.strokeW * 0.15
        x: body.x + body.width * 0.18
    }

    Rectangle {
        width: root.s * 0.16
        height: root.strokeW * 1.25
        radius: height / 2
        color: root.color
        opacity: 0.95
        anchors.bottom: body.top
        anchors.bottomMargin: root.strokeW * 0.15
        x: body.x + body.width * 0.66
    }

    // Minus (left)
    Rectangle {
        width: root.s * 0.18
        height: root.strokeW * 0.95
        radius: height / 2
        color: root.color
        opacity: 0.90
        anchors.verticalCenter: body.verticalCenter
        x: body.x + body.width * 0.18
    }

    // Plus (right)
    Item {
        width: root.s * 0.18
        height: root.s * 0.18
        anchors.verticalCenter: body.verticalCenter
        x: body.x + body.width * 0.66

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: root.strokeW * 0.95
            radius: height / 2
            color: root.color
            opacity: 0.90
        }
        Rectangle {
            anchors.centerIn: parent
            width: root.strokeW * 0.95
            height: parent.height
            radius: width / 2
            color: root.color
            opacity: 0.90
        }
    }
}
