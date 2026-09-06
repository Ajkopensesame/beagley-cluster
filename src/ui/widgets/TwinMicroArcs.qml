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
    function css(c, a) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
            + Math.round(c.b * 255) + "," + a + ")"
    }

    // Left micro-arc: fuel (E → F)
    Item {
        id: fuelPod
        width: parent.width * 0.28
        height: parent.height * 0.24
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.17
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.11

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

        Canvas {
            id: fuelIcon
            renderTarget: Qt.platform.os === "linux" ? Canvas.Image : Canvas.FramebufferObject
            antialiasing: true
            width: Math.max(18, parent.width * 0.28)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -parent.height * 0.02
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const sw = Math.max(1.8, width * 0.10)
                ctx.strokeStyle = root.css(root.pearl, 0.95)
                ctx.lineWidth = sw
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                // pump body
                const x = width * 0.22, y = height * 0.18, w = width * 0.38, h = height * 0.64, r = width * 0.06
                ctx.beginPath()
                ctx.moveTo(x + r, y)
                ctx.arcTo(x + w, y, x + w, y + h, r)
                ctx.arcTo(x + w, y + h, x, y + h, r)
                ctx.arcTo(x, y + h, x, y, r)
                ctx.arcTo(x, y, x + w, y, r)
                ctx.closePath()
                ctx.stroke()
                // window
                ctx.strokeRect(x + w * 0.18, y + h * 0.16, w * 0.64, h * 0.18)
                // hose
                ctx.beginPath()
                ctx.moveTo(x + w, y + h * 0.38)
                ctx.bezierCurveTo(width * 0.72, height * 0.40, width * 0.80, height * 0.52, width * 0.72, height * 0.72)
                ctx.stroke()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.00
            text: Math.round(root.fuelPct) + "%"
            color: root.fuelColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(11, parent.width * 0.15)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "E"
            color: root.pearl
            opacity: 0.72
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.095)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "F"
            color: root.pearl
            opacity: 0.72
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.095)
            font.bold: true
        }
    }

    // Right micro-arc: coolant (C → H)
    Item {
        id: tempPod
        width: parent.width * 0.28
        height: parent.height * 0.24
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.17
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.11

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

        Canvas {
            id: thermoIcon
            renderTarget: Qt.platform.os === "linux" ? Canvas.Image : Canvas.FramebufferObject
            antialiasing: true
            width: Math.max(16, parent.width * 0.22)
            height: width * 1.35
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -parent.height * 0.02
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cx = width * 0.5
                const stemTop = height * 0.08
                const stemBot = height * 0.62
                const stemW = Math.max(2.5, width * 0.18)
                const bulbR = Math.max(3.5, width * 0.28)
                ctx.strokeStyle = root.css(root.pearl, 0.95)
                ctx.fillStyle = root.css(root.tempColor, 0.90)
                ctx.lineWidth = Math.max(1.5, width * 0.10)
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(cx - stemW * 0.5, stemTop)
                ctx.lineTo(cx + stemW * 0.5, stemTop)
                ctx.lineTo(cx + stemW * 0.5, stemBot)
                ctx.lineTo(cx - stemW * 0.5, stemBot)
                ctx.closePath()
                ctx.stroke()
                const fillTop = stemTop + (stemBot - stemTop) * (1.0 - Math.max(0.15, Math.min(1, root.coolantNorm)))
                ctx.fillRect(cx - stemW * 0.35, fillTop, stemW * 0.7, stemBot - fillTop)
                ctx.beginPath()
                ctx.arc(cx, stemBot + bulbR * 0.55, bulbR, 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.00
            text: Math.round(root.coolantC) + "°C"
            color: root.tempColor
            font.family: "Oxanium"
            font.pixelSize: Math.max(11, parent.width * 0.15)
            font.bold: true
            style: Text.Outline
            styleColor: "#E0000000"
        }
        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: "C"
            color: root.pearl
            opacity: 0.72
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.095)
            font.bold: true
        }
        Text {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "H"
            color: root.pearl
            opacity: 0.72
            font.family: "Oxanium"
            font.pixelSize: Math.max(9, parent.width * 0.095)
            font.bold: true
        }
    }
}
