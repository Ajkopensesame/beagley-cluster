import QtQuick 2.15

Item {
    id: root

    // Tint color passed in from VicWarningIcon
    property color color: "red"

    // Outer circle stroke
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(3, width * 0.06)
        border.color: root.color
        opacity: 0.95
    }

    // Inner dot (optional “badge” feel)
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.12
        height: width
        radius: width / 2
        color: root.color
        opacity: 0.95
    }

    // Exclamation stem
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.22
        width: Math.max(4, parent.width * 0.10)
        height: parent.height * 0.42
        radius: width / 2
        color: root.color
        opacity: 0.95
    }

    // Exclamation dot
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.70
        width: Math.max(4, parent.width * 0.10)
        height: width
        radius: width / 2
        color: root.color
        opacity: 0.95
    }
}
