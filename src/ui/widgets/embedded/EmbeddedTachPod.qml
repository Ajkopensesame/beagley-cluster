import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property string fontFamily: "sans-serif"
    property color panelFill: "#081220"
    property color panelStroke: "#14324A"
    property color needleColor: "#4CD9FF"
    readonly property real rpmAngle: -126 + Math.min(252, Math.max(0, (root.cluster.rpm / 6000.0) * 252.0))

    radius: 34
    color: panelFill
    border.color: panelStroke
    border.width: 1

    Rectangle {
        width: 360
        height: 360
        radius: 180
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 26
        color: "#071019"
        border.color: "#1C4867"
        border.width: 2

        Repeater {
            model: 13

            delegate: Rectangle {
                width: index % 3 === 0 ? 30 : 18
                height: 3
                radius: 2
                color: index < 10 ? "#FFB03B" : "#6A3840"
                anchors.centerIn: parent
                transform: [
                    Translate { y: -150 },
                    Rotation {
                        origin.x: width / 2
                        origin.y: 150 + height / 2
                        angle: -126 + (index * 21)
                    }
                ]
            }
        }

        Rectangle {
            width: 120
            height: 6
            radius: 3
            color: root.needleColor
            anchors.centerIn: parent
            transform: Rotation {
                origin.x: 18
                origin.y: 3
                angle: root.rpmAngle
            }
            x: parent.width / 2 - 18
            y: parent.height / 2 - 3
        }

        Rectangle {
            width: 22
            height: 22
            radius: 11
            color: root.needleColor
            anchors.centerIn: parent
        }

        Column {
            anchors.centerIn: parent
            spacing: 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 88
                font.bold: true
                text: Math.round(root.cluster.rpm)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#7BA5C9"
                font.family: root.fontFamily
                font.pixelSize: 24
                text: "RPM"
            }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        spacing: 14

        Rectangle {
            width: parent.width
            height: 76
            radius: 22
            color: root.cluster.activeWarnings > 0 ? "#351414" : "#0C1A17"
            border.color: root.cluster.activeWarnings > 0 ? "#B64040" : "#2DA56A"
            border.width: 1

            Text {
                anchors.centerIn: parent
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 24
                font.bold: true
                elide: Text.ElideRight
                width: parent.width - 28
                horizontalAlignment: Text.AlignHCenter
                text: root.cluster.warningSummary
            }
        }

        Row {
            spacing: 16

            Repeater {
                model: [
                    { label: "L", active: root.cluster.leftIndicator, color: "#49D86B" },
                    { label: "R", active: root.cluster.rightIndicator, color: "#49D86B" }
                ]

                delegate: Rectangle {
                    width: 194
                    height: 64
                    radius: 18
                    color: modelData.active ? "#12331E" : "#0B1620"
                    border.color: modelData.active ? modelData.color : "#1E3342"
                    border.width: 1
                    opacity: modelData.active ? 1.0 : 0.65

                    Text {
                        anchors.centerIn: parent
                        color: modelData.active ? modelData.color : "#5F7586"
                        font.family: root.fontFamily
                        font.pixelSize: 28
                        font.bold: true
                        text: modelData.label + " TURN"
                    }
                }
            }
        }
    }
}
