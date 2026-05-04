import QtQuick 2.15

Item {
    id: root

    property bool active: true
    property color primaryColor: active ? "#F7FBFF" : Qt.rgba(0.96, 0.98, 1.0, 0.70)
    property color accentColor: active ? "#58FFE1" : Qt.rgba(1.0, 0.82, 0.42, 0.88)

    readonly property real stroke: Math.max(2.2, Math.min(width, height) * 0.075)

    Repeater {
        model: [0.34, 0.58, 0.82]
        Rectangle {
            width: Math.min(root.width, root.height) * modelData
            height: width
            radius: width / 2
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.height * 0.06
            color: "transparent"
            border.width: Math.max(1.2, root.stroke * 0.42)
            border.color: root.primaryColor
            opacity: 0.42 + index * 0.18
        }
    }

    Rectangle {
        width: Math.max(5, Math.min(root.width, root.height) * 0.15)
        height: width
        radius: width / 2
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.height * 0.06
        color: root.accentColor
    }

    Rectangle {
        width: Math.max(4, Math.min(root.width, root.height) * 0.11)
        height: width
        radius: width / 2
        x: root.width * 0.68 - width / 2
        y: root.height * 0.31 - height / 2
        color: root.accentColor
        opacity: 0.90
    }
}
