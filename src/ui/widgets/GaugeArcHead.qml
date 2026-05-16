import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property bool scared: false
    property bool lowEffectMode: false
    property real headRadius: 11.5

    readonly property real padding: Math.max(6, headRadius * 0.36)
    readonly property real badgeExtent: Math.ceil((headRadius + padding) * 2)
    readonly property color faceColor: Qt.color("#FFD84A")
    readonly property color faceEdge: Qt.color("#4A2300")
    readonly property color inkColor: Qt.color("#070A0F")
    readonly property color tearColor: Qt.color("#63C9FF")

    width: badgeExtent
    height: badgeExtent
    visible: headRadius > 0.1

    Rectangle {
        anchors.centerIn: parent
        width: root.headRadius * 2.58
        height: width
        radius: width / 2
        color: root.scared ? "#FF394A" : root.faceColor
        opacity: root.lowEffectMode ? 0.16 : 0.24
    }

    Rectangle {
        id: face
        anchors.centerIn: parent
        width: root.headRadius * 2
        height: width
        radius: width / 2
        color: root.faceColor
        border.width: Math.max(1.2, root.headRadius * 0.12)
        border.color: root.faceEdge

        Rectangle {
            width: parent.width * 0.42
            height: parent.height * 0.18
            x: parent.width * 0.12
            y: parent.height * 0.27
            radius: height * 0.34
            visible: !root.scared
            color: root.inkColor
        }

        Rectangle {
            width: parent.width * 0.42
            height: parent.height * 0.18
            x: parent.width * 0.46
            y: parent.height * 0.27
            radius: height * 0.34
            visible: !root.scared
            color: root.inkColor
        }

        Rectangle {
            width: parent.width * 0.20
            height: Math.max(1.2, parent.height * 0.055)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.34
            radius: height / 2
            visible: !root.scared
            color: root.inkColor
        }

        Shape {
            width: parent.width * 0.74
            height: parent.height * 0.36
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.43
            visible: !root.scared
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.faceEdge
                strokeWidth: Math.max(1.2, root.headRadius * 0.13)
                capStyle: ShapePath.RoundCap
                startX: parent.width * 0.18
                startY: parent.height * 0.42
                PathCubic {
                    control1X: parent.width * 0.32
                    control1Y: parent.height * 0.78
                    control2X: parent.width * 0.68
                    control2Y: parent.height * 0.78
                    x: parent.width * 0.82
                    y: parent.height * 0.42
                }
            }
        }

        Rectangle {
            width: parent.width * 0.40
            height: Math.max(1.2, parent.height * 0.065)
            x: parent.width * 0.14
            y: parent.height * 0.22
            radius: height / 2
            visible: root.scared
            color: root.faceEdge
            rotation: 17
        }

        Rectangle {
            width: parent.width * 0.40
            height: Math.max(1.2, parent.height * 0.065)
            x: parent.width * 0.46
            y: parent.height * 0.22
            radius: height / 2
            visible: root.scared
            color: root.faceEdge
            rotation: -17
        }

        Rectangle {
            width: parent.width * 0.24
            height: width
            radius: width / 2
            x: parent.width * 0.22
            y: parent.height * 0.33
            visible: root.scared
            color: "#FFFFFF"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.42
                height: width
                radius: width / 2
                color: root.inkColor
            }
        }

        Rectangle {
            width: parent.width * 0.24
            height: width
            radius: width / 2
            x: parent.width * 0.54
            y: parent.height * 0.33
            visible: root.scared
            color: "#FFFFFF"

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.42
                height: width
                radius: width / 2
                color: root.inkColor
            }
        }

        Rectangle {
            width: parent.width * 0.28
            height: parent.height * 0.34
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.56
            visible: root.scared
            color: root.inkColor
        }

        Rectangle {
            width: parent.width * 0.18
            height: parent.height * 0.28
            radius: width / 2
            x: parent.width * 0.72
            y: parent.height * 0.47
            visible: root.scared
            color: root.tearColor
            rotation: -18
        }
    }
}
