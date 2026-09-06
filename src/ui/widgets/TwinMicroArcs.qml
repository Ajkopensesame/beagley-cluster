import QtQuick 2.15
import BeagleY 1.0

// Skin v2: fuel% + coolant°C twin lower arcs inside tach (concept layout).
Item {
    id: root
    anchors.fill: parent

    property var theme
    property real fuelNorm: 0.62
    property real coolantNorm: 0.55
    property real fuelPct: 62
    property real coolantC: 78
    property bool lowEffectMode: false
    property string effectLevel: "high"

    readonly property color pearl: theme?.pearlLow ?? Qt.color("#D4C4FF")
    readonly property color fuelColor: (fuelNorm <= 0.12)
        ? (theme?.danger ?? Qt.color("#FF3B3B"))
        : pearl
    readonly property color tempColor: (coolantNorm >= 0.90)
        ? (theme?.danger ?? Qt.color("#FF3B3B"))
        : ((coolantNorm <= 0.15)
            ? (theme?.matrixCyan ?? Qt.color("#5FF7FF"))
            : (theme?.lavaOrange ?? Qt.color("#FF6A18")))

    function colorWithAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Left micro-arc: fuel (E → F)
    Item {
        id: fuelPod
        width: parent.width * 0.34
        height: parent.height * 0.28
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.10

        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 200
            sweepAngleDeg: 140
            startProgress: 0.0
            endProgress: 1.0
            radiusFactor: 0.42
            strokeWidth: root.lowEffectMode ? 5 : 7
            color: root.colorWithAlpha(root.pearl, 0.14)
            segments: 24
            roundedCaps: true
        }
        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 200
            sweepAngleDeg: 140
            startProgress: 0.0
            endProgress: Math.max(0.02, Math.min(1, root.fuelNorm))
            radiusFactor: 0.42
            strokeWidth: root.lowEffectMode ? 5 : 8
            color: root.colorWithAlpha(root.fuelColor, 0.90)
            segments: 24
            roundedCaps: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.18
            text: Math.round(root.fuelPct) + "%"
            color: root.fuelColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(11, parent.width * 0.14)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "E"
            color: root.pearl
            opacity: 0.7
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.09)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "F"
            color: root.pearl
            opacity: 0.7
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.09)
            font.bold: true
        }
    }

    // Right micro-arc: coolant (C → H)
    Item {
        id: tempPod
        width: parent.width * 0.34
        height: parent.height * 0.28
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.10

        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 200
            sweepAngleDeg: 140
            startProgress: 0.0
            endProgress: 1.0
            radiusFactor: 0.42
            strokeWidth: root.lowEffectMode ? 5 : 7
            color: root.colorWithAlpha(root.pearl, 0.14)
            segments: 24
            roundedCaps: true
        }
        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 200
            sweepAngleDeg: 140
            startProgress: 0.0
            endProgress: Math.max(0.02, Math.min(1, root.coolantNorm))
            radiusFactor: 0.42
            strokeWidth: root.lowEffectMode ? 5 : 8
            color: root.colorWithAlpha(root.tempColor, 0.90)
            segments: 24
            roundedCaps: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.18
            text: Math.round(root.coolantC) + "°C"
            color: root.tempColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(11, parent.width * 0.14)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "C"
            color: root.pearl
            opacity: 0.7
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.09)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "H"
            color: root.pearl
            opacity: 0.7
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.09)
            font.bold: true
        }
    }
}
