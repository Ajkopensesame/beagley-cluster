import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property color panelFill: "#081220"
    property color panelStroke: "#14324A"
    property color needleColor: "#FFB03B"
    readonly property real speedAngle: -126 + Math.min(252, Math.max(0, root.cluster.speedKph * 2.1))

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
                color: index < 7 ? "#4CD9FF" : "#35556E"
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
                angle: root.speedAngle
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
                font.pixelSize: 108
                font.bold: true
                text: Math.round(root.cluster.speedKph)
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#7BA5C9"
                font.pixelSize: 24
                text: "KM/H"
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        spacing: 16

        Repeater {
            model: [
                { label: "FUEL", value: Math.round(root.cluster.fuelPct) + "%" },
                { label: "COOLANT", value: Math.round(root.cluster.coolantC) + " C" }
            ]

            delegate: Rectangle {
                width: 196
                height: 94
                radius: 22
                color: "#0B1827"
                border.color: "#21455F"
                border.width: 1

                Column {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "#7BA5C9"
                        font.pixelSize: 16
                        text: modelData.label
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "white"
                        font.pixelSize: 34
                        font.bold: true
                        text: modelData.value
                    }
                }
            }
        }
    }
}
