import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property string fontFamily: "sans-serif"
    property color fillColor: "#10261A"
    property color strokeColor: "#1F7A45"

    color: fillColor
    border.color: strokeColor
    border.width: 1

    Row {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 18

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: 28
            font.bold: true
            text: root.cluster.warningSummary
        }

        Item {
            width: 1
            height: 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            color: "#C7DAE8"
            font.family: root.fontFamily
            font.pixelSize: 24
            text: "SPD " + Math.round(root.cluster.speedKph) + "  |  RPM " + Math.round(root.cluster.rpm)
        }
    }
}
