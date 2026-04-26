import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property string fontFamily: "sans-serif"
    property color panelFill: "#081220"
    property color panelStroke: "#14324A"
    property color needleColor: "#4CD9FF"
    readonly property real rpmValue: root.cluster ? Number(root.cluster.rpm || 0) : 0
    readonly property bool warningActive: !!(root.cluster && root.cluster.activeWarnings > 0)

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
        value: root.rpmValue
        maxValue: 6000
        dangerStart: 5000
        minorStep: 500
        majorStep: 1000
        labelStep: 1000
        labelDivisor: 1000
        valueText: (displayValue / 1000.0).toFixed(1)
        unitText: "x1000 RPM"
        labelText: "TACH"
        valueFontSize: 94
        unitFontSize: 22
        fontFamily: root.fontFamily
        accentColor: root.needleColor
        dangerColor: "#E34848"
        trackColor: "#31546C"
        mutedTextColor: "#91B7D5"
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
            color: root.warningActive ? "#351414" : "#0C1A17"
            border.color: root.warningActive ? "#B64040" : "#2DA56A"
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
                text: root.cluster ? root.cluster.warningSummary : "LINK DOWN"
            }
        }

        Row {
            spacing: 16

            Repeater {
                model: [
                    { label: "L", active: !!(root.cluster && root.cluster.leftIndicator), color: "#49D86B" },
                    { label: "R", active: !!(root.cluster && root.cluster.rightIndicator), color: "#49D86B" }
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
