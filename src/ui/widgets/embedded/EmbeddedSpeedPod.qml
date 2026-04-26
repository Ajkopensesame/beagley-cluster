import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property string fontFamily: "sans-serif"
    property color panelFill: "#081220"
    property color panelStroke: "#14324A"
    property color needleColor: "#FFB03B"
    readonly property real speedValue: root.cluster ? Number(root.cluster.speedKph || 0) : 0
    readonly property real fuelValue: root.cluster ? Number(root.cluster.fuelPct || 0) : 0
    readonly property real coolantValue: root.cluster ? Number(root.cluster.coolantC || 0) : 0

    radius: 34
    color: panelFill
    border.color: panelStroke
    border.width: 1

    EmbeddedAnalogGauge {
        id: gauge
        width: Math.max(1, Math.min(parent.width - 40, parent.height - 130))
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 18
        value: root.speedValue
        maxValue: 140
        dangerStart: 116
        minorStep: 10
        majorStep: 20
        labelStep: 20
        labelDivisor: 1
        valueText: String(Math.round(displayValue))
        unitText: "KM/H"
        labelText: "SPEED"
        valueFontSize: 104
        unitFontSize: 23
        fontFamily: root.fontFamily
        accentColor: root.needleColor
        dangerColor: "#E34848"
        trackColor: "#31546C"
        mutedTextColor: "#91B7D5"
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 22
        spacing: 16

        Repeater {
            model: [
                { label: "FUEL", value: Math.round(root.fuelValue) + "%", fill: Math.max(0, Math.min(1, root.fuelValue / 100.0)), color: "#4CD9FF" },
                { label: "COOLANT", value: Math.round(root.coolantValue) + " C", fill: Math.max(0, Math.min(1, (root.coolantValue - 40.0) / 70.0)), color: root.coolantValue >= 105 ? "#E34848" : "#FFB03B" }
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
                        font.family: root.fontFamily
                        font.pixelSize: 16
                        text: modelData.label
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: "white"
                        font.family: root.fontFamily
                        font.pixelSize: 34
                        font.bold: true
                        text: modelData.value
                    }

                    Rectangle {
                        width: 128
                        height: 7
                        radius: 4
                        color: "#142435"
                        antialiasing: true

                        Rectangle {
                            width: parent.width * modelData.fill
                            height: parent.height
                            radius: parent.radius
                            color: modelData.color
                            antialiasing: true

                            Behavior on width {
                                NumberAnimation {
                                    duration: 140
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
