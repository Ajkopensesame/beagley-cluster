import QtQuick 2.15
import BeagleY 1.0

// Skin v2: fuel% + coolant°C twin lower arcs inside tach (concept pods + icons).
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
            : (theme?.lavaOrange ?? Qt.color("#FF7A14")))

    function colorWithAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    Item {
        id: fuelPod
        width: parent.width * 0.28
        height: parent.height * 0.26
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.18
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.115
        z: 2

        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 205
            sweepAngleDeg: 130
            startProgress: 0.0
            endProgress: 1.0
            radiusFactor: 0.40
            strokeWidth: root.lowEffectMode ? 4 : 6
            color: root.colorWithAlpha(root.pearl, 0.16)
            segments: 24
            roundedCaps: true
        }
        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 205
            sweepAngleDeg: 130
            startProgress: 0.0
            endProgress: Math.max(0.02, Math.min(1, root.fuelNorm))
            radiusFactor: 0.40
            strokeWidth: root.lowEffectMode ? 5 : 7
            color: root.colorWithAlpha(root.fuelColor, 0.92)
            segments: 24
            roundedCaps: true
        }

        // Scene-graph silhouette (no Canvas) — readable at arm's length
        Item {
            id: fuelGlyph
            width: Math.max(34, parent.width * 0.48)
            height: width
            z: 6
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: fuelPctText.top
            anchors.bottomMargin: 1

            Rectangle {
                id: pumpBody
                x: parent.width * 0.18
                y: parent.height * 0.14
                width: parent.width * 0.44
                height: parent.height * 0.66
                radius: parent.width * 0.07
                color: "#28F2EAFF"
                border.color: "#A8F2EAFF"
                border.width: Math.max(1.5, parent.width * 0.05)
            }
            Rectangle {
                x: pumpBody.x + pumpBody.width * 0.18
                y: pumpBody.y + pumpBody.height * 0.16
                width: pumpBody.width * 0.64
                height: pumpBody.height * 0.20
                radius: 2
                color: root.fuelColor
                border.color: "#F2EAFF"
                border.width: 1
            }
            Rectangle {
                x: pumpBody.x + pumpBody.width - 2
                y: pumpBody.y + pumpBody.height * 0.34
                width: parent.width * 0.20
                height: Math.max(3, parent.width * 0.08)
                radius: height / 2
                color: root.fuelColor
                rotation: 28
                transformOrigin: Item.Left
            }
            Rectangle {
                x: pumpBody.x + pumpBody.width * 0.85
                y: pumpBody.y + pumpBody.height * 0.55
                width: Math.max(3, parent.width * 0.08)
                height: parent.height * 0.28
                radius: width / 2
                color: "#F2EAFF"
            }
            Rectangle {
                x: pumpBody.x - parent.width * 0.04
                y: pumpBody.y + pumpBody.height - 2
                width: pumpBody.width + parent.width * 0.08
                height: Math.max(3, parent.width * 0.07)
                radius: 1
                color: "#F2EAFF"
            }
        }

        Text {
            id: fuelPctText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            z: 6
            text: Math.round(root.fuelPct) + "%"
            color: root.fuelColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(12, parent.width * 0.16)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "E"
            color: root.pearl
            opacity: 0.80
            font.family: "Oxanium"
            font.pixelSize: Math.max(10, parent.width * 0.105)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "F"
            color: root.pearl
            opacity: 0.80
            font.family: "Oxanium"
            font.pixelSize: Math.max(10, parent.width * 0.105)
            font.bold: true
        }
    }

    Item {
        id: tempPod
        width: parent.width * 0.28
        height: parent.height * 0.26
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.18
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.115
        z: 2

        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 205
            sweepAngleDeg: 130
            startProgress: 0.0
            endProgress: 1.0
            radiusFactor: 0.40
            strokeWidth: root.lowEffectMode ? 4 : 6
            color: root.colorWithAlpha(root.pearl, 0.16)
            segments: 24
            roundedCaps: true
        }
        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: 205
            sweepAngleDeg: 130
            startProgress: 0.0
            endProgress: Math.max(0.02, Math.min(1, root.coolantNorm))
            radiusFactor: 0.40
            strokeWidth: root.lowEffectMode ? 5 : 7
            color: root.colorWithAlpha(root.tempColor, 0.92)
            segments: 24
            roundedCaps: true
        }

        Item {
            id: thermoGlyph
            width: Math.max(28, parent.width * 0.40)
            height: width * 1.35
            z: 6
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: tempPctText.top
            anchors.bottomMargin: 1

            Rectangle {
                id: stem
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.04
                width: Math.max(8, parent.width * 0.30)
                height: parent.height * 0.55
                radius: width / 2
                color: "#28F2EAFF"
                border.color: "#A8F2EAFF"
                border.width: Math.max(1.5, parent.width * 0.055)
            }
            Rectangle {
                anchors.horizontalCenter: stem.horizontalCenter
                anchors.bottom: stem.bottom
                anchors.bottomMargin: stem.border.width
                width: stem.width - stem.border.width * 2
                height: Math.max(stem.height * 0.35, stem.height * Math.max(0.2, Math.min(1, root.coolantNorm)))
                radius: width / 2
                color: root.tempColor
            }
            // stem ticks
            Repeater {
                model: 3
                Rectangle {
                    x: stem.x + stem.width + 2
                    y: stem.y + stem.height * (0.22 + index * 0.2)
                    width: Math.max(4, thermoGlyph.width * 0.16)
                    height: Math.max(2, thermoGlyph.width * 0.06)
                    color: "#F2EAFF"
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: stem.bottom
                anchors.topMargin: -parent.width * 0.12
                width: Math.max(16, parent.width * 0.62)
                height: width
                radius: width / 2
                color: root.tempColor
                border.color: "#A8F2EAFF"
                border.width: Math.max(1.5, parent.width * 0.055)
            }
        }

        Text {
            id: tempPctText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            z: 6
            text: Math.round(root.coolantC) + "°C"
            color: root.tempColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(12, parent.width * 0.16)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "C"
            color: root.pearl
            opacity: 0.80
            font.family: "Oxanium"
            font.pixelSize: Math.max(10, parent.width * 0.105)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "H"
            color: root.pearl
            opacity: 0.80
            font.family: "Oxanium"
            font.pixelSize: Math.max(10, parent.width * 0.105)
            font.bold: true
        }
    }
}
