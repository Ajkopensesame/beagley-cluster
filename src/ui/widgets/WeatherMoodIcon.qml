import QtQuick 2.15

Item {
    id: root

    property string kind: "clear"
    property color primaryColor: "#FFD36B"
    property color secondaryColor: "#58FFE1"
    property color cloudColor: "#EEF4FF"
    property color faceColor: "#FFD36B"
    property color darkColor: "#05070D"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

    function normalizedKind() {
        const value = String(kind).toLowerCase()
        if (value.indexOf("storm") >= 0)
            return "storm"
        if (value.indexOf("rain") >= 0 || value.indexOf("shower") >= 0 || value.indexOf("drizzle") >= 0)
            return "rain"
        if (value.indexOf("snow") >= 0)
            return "snow"
        if (value.indexOf("fog") >= 0)
            return "fog"
        if (value.indexOf("cloud") >= 0)
            return "cloud"
        return "clear"
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function css(c, alpha) {
        return "rgba("
            + Math.round(clamp(c.r, 0, 1) * 255) + ","
            + Math.round(clamp(c.g, 0, 1) * 255) + ","
            + Math.round(clamp(c.b, 0, 1) * 255) + ","
            + clamp(alpha, 0, 1) + ")"
    }

    function requestCanvasPaint() {
        if (!embeddedSafeMode)
            moodCanvas.requestPaint()
    }

    onKindChanged: requestCanvasPaint()
    onPrimaryColorChanged: requestCanvasPaint()
    onSecondaryColorChanged: requestCanvasPaint()
    onCloudColorChanged: requestCanvasPaint()
    onFaceColorChanged: requestCanvasPaint()
    onDarkColorChanged: requestCanvasPaint()
    Component.onCompleted: requestCanvasPaint()

    Item {
        id: embeddedIcon
        anchors.fill: parent
        visible: root.embeddedSafeMode

        readonly property string weatherKind: root.normalizedKind()
        readonly property real side: Math.min(width, height)

        Item {
            id: embeddedSun
            width: embeddedIcon.side * 0.72
            height: width
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: embeddedIcon.weatherKind === "cloud" ? -embeddedIcon.side * 0.10 : 0
            anchors.verticalCenterOffset: embeddedIcon.weatherKind === "cloud" ? -embeddedIcon.side * 0.10 : 0
            visible: embeddedIcon.weatherKind === "clear" || embeddedIcon.weatherKind === "cloud"
            opacity: embeddedIcon.weatherKind === "cloud" ? 0.72 : 1.0

            Repeater {
                model: 12
                Rectangle {
                    width: Math.max(3, embeddedSun.width * 0.045)
                    height: embeddedSun.height * 0.18
                    radius: width / 2
                    x: embeddedSun.width / 2 - width / 2
                    y: embeddedSun.height * 0.02
                    color: root.primaryColor
                    opacity: 0.82
                    antialiasing: true
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: embeddedSun.height * 0.48
                        angle: index * 30
                    }
                }
            }

            Rectangle {
                width: embeddedSun.width * 0.58
                height: width
                radius: width / 2
                anchors.centerIn: parent
                color: root.faceColor
                border.width: Math.max(1, embeddedSun.width * 0.022)
                border.color: Qt.rgba(1.0, 0.72, 0.18, 0.92)
                antialiasing: true
            }

            Rectangle {
                width: embeddedSun.width * 0.17
                height: embeddedSun.height * 0.10
                radius: height * 0.28
                x: embeddedSun.width * 0.29
                y: embeddedSun.height * 0.43
                color: root.darkColor
                antialiasing: true
            }

            Rectangle {
                width: embeddedSun.width * 0.17
                height: embeddedSun.height * 0.10
                radius: height * 0.28
                x: embeddedSun.width * 0.54
                y: embeddedSun.height * 0.43
                color: root.darkColor
                antialiasing: true
            }

            Rectangle {
                width: embeddedSun.width * 0.14
                height: Math.max(2, embeddedSun.height * 0.025)
                radius: height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: embeddedSun.height * 0.47
                color: root.darkColor
                antialiasing: true
            }
        }

        Item {
            id: embeddedCloud
            width: embeddedIcon.side * 0.78
            height: embeddedIcon.side * 0.54
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: embeddedIcon.weatherKind === "cloud" ? embeddedIcon.side * 0.08 : -embeddedIcon.side * 0.02
            visible: embeddedIcon.weatherKind !== "clear"

            Rectangle {
                width: parent.width * 0.98
                height: parent.height * 0.45
                radius: height * 0.42
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                color: root.cloudColor
                antialiasing: true
            }

            Rectangle {
                width: parent.width * 0.40
                height: width
                radius: width / 2
                x: parent.width * 0.10
                y: parent.height * 0.24
                color: root.cloudColor
                antialiasing: true
            }

            Rectangle {
                width: parent.width * 0.48
                height: width
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.03
                color: root.cloudColor
                antialiasing: true
            }

            Rectangle {
                width: parent.width * 0.40
                height: width
                radius: width / 2
                x: parent.width * 0.50
                y: parent.height * 0.20
                color: root.cloudColor
                antialiasing: true
            }
        }

        Item {
            id: embeddedDrops
            width: embeddedIcon.side * 0.58
            height: embeddedIcon.side * 0.28
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: embeddedCloud.bottom
            anchors.topMargin: -embeddedIcon.side * 0.02
            visible: embeddedIcon.weatherKind === "rain" || embeddedIcon.weatherKind === "storm"

            Repeater {
                model: 4
                Rectangle {
                    width: Math.max(3, embeddedDrops.width * 0.055)
                    height: embeddedDrops.height * 0.62
                    radius: width / 2
                    x: embeddedDrops.width * (0.18 + index * 0.21)
                    y: (index % 2) * embeddedDrops.height * 0.16
                    rotation: 18
                    color: root.secondaryColor
                    opacity: 0.92
                    antialiasing: true
                }
            }
        }

        Rectangle {
            width: embeddedIcon.side * 0.16
            height: embeddedIcon.side * 0.46
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: embeddedIcon.side * 0.25
            visible: embeddedIcon.weatherKind === "storm"
            color: root.primaryColor
            rotation: 24
            radius: width * 0.12
            antialiasing: true
        }

        Column {
            width: embeddedIcon.side * 0.62
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: embeddedIcon.side * 0.22
            spacing: embeddedIcon.side * 0.08
            visible: embeddedIcon.weatherKind === "fog" || embeddedIcon.weatherKind === "snow"

            Repeater {
                model: embeddedIcon.weatherKind === "fog" ? 3 : 2
                Rectangle {
                    width: parent.width
                    height: Math.max(2, embeddedIcon.side * 0.035)
                    radius: height / 2
                    color: root.secondaryColor
                    opacity: embeddedIcon.weatherKind === "fog" ? 0.62 : 0.92
                    antialiasing: true
                }
            }
        }
    }

    Canvas {
        id: moodCanvas
        anchors.fill: parent
        visible: !root.embeddedSafeMode
        renderTarget: Canvas.FramebufferObject
        antialiasing: true
        smooth: true

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const side = Math.min(width, height)
            const cx = width / 2
            const cy = height / 2
            const kind = root.normalizedKind()

            function roundedRect(x, y, w, h, r) {
                const rr = Math.min(r, w / 2, h / 2)
                ctx.beginPath()
                ctx.moveTo(x + rr, y)
                ctx.lineTo(x + w - rr, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + rr)
                ctx.lineTo(x + w, y + h - rr)
                ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h)
                ctx.lineTo(x + rr, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - rr)
                ctx.lineTo(x, y + rr)
                ctx.quadraticCurveTo(x, y, x + rr, y)
                ctx.closePath()
            }

            function drawCloud(x, y, scale) {
                const fill = ctx.createLinearGradient(x, y - scale * 0.32, x, y + scale * 0.42)
                fill.addColorStop(0, root.css(root.cloudColor, 1.0))
                fill.addColorStop(1, "rgba(150,167,198,1.0)")
                ctx.fillStyle = fill
                ctx.beginPath()
                ctx.arc(x - scale * 0.30, y + scale * 0.04, scale * 0.28, Math.PI * 0.78, Math.PI * 1.92)
                ctx.arc(x - scale * 0.04, y - scale * 0.16, scale * 0.34, Math.PI * 1.10, Math.PI * 1.94)
                ctx.arc(x + scale * 0.30, y + scale * 0.00, scale * 0.30, Math.PI * 1.22, Math.PI * 2.15)
                ctx.lineTo(x + scale * 0.48, y + scale * 0.30)
                ctx.lineTo(x - scale * 0.50, y + scale * 0.30)
                ctx.closePath()
                ctx.fill()
            }

            function drawSunFace() {
                const r = side * 0.30
                ctx.strokeStyle = root.css(root.primaryColor, 0.72)
                ctx.lineWidth = Math.max(3, side * 0.035)
                ctx.lineCap = "round"
                for (let i = 0; i < 12; ++i) {
                    const a = i * Math.PI * 2 / 12
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(a) * r * 1.18, cy + Math.sin(a) * r * 1.18)
                    ctx.lineTo(cx + Math.cos(a) * r * 1.48, cy + Math.sin(a) * r * 1.48)
                    ctx.stroke()
                }

                const face = ctx.createRadialGradient(cx - r * 0.22, cy - r * 0.25, r * 0.1, cx, cy, r)
                face.addColorStop(0, "rgba(255,248,168,1.0)")
                face.addColorStop(0.62, root.css(root.faceColor, 1.0))
                face.addColorStop(1, "rgba(244,165,43,1.0)")
                ctx.fillStyle = face
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.fill()

                ctx.fillStyle = root.css(root.darkColor, 0.96)
                roundedRect(cx - r * 0.66, cy - r * 0.24, r * 0.52, r * 0.30, r * 0.08)
                ctx.fill()
                roundedRect(cx + r * 0.14, cy - r * 0.24, r * 0.52, r * 0.30, r * 0.08)
                ctx.fill()

                ctx.strokeStyle = root.css(root.darkColor, 0.96)
                ctx.lineWidth = Math.max(2, side * 0.025)
                ctx.beginPath()
                ctx.moveTo(cx - r * 0.14, cy - r * 0.09)
                ctx.lineTo(cx + r * 0.14, cy - r * 0.09)
                ctx.stroke()

                ctx.strokeStyle = root.css(root.darkColor, 0.82)
                ctx.lineWidth = Math.max(2, side * 0.020)
                ctx.beginPath()
                ctx.arc(cx, cy + r * 0.18, r * 0.36, Math.PI * 0.15, Math.PI * 0.85)
                ctx.stroke()
            }

            function drawRainDrops(x, y, scale, count) {
                ctx.strokeStyle = root.css(root.secondaryColor, 0.92)
                ctx.lineWidth = Math.max(2, side * 0.030)
                ctx.lineCap = "round"
                for (let i = 0; i < count; ++i) {
                    const dx = x + (i - (count - 1) / 2) * scale * 0.26
                    ctx.beginPath()
                    ctx.moveTo(dx + scale * 0.04, y)
                    ctx.lineTo(dx - scale * 0.04, y + scale * 0.24)
                    ctx.stroke()
                }
            }

            if (kind === "clear") {
                drawSunFace()
            } else if (kind === "storm") {
                drawCloud(cx, cy - side * 0.08, side * 0.70)
                ctx.fillStyle = root.css(root.primaryColor, 1.0)
                ctx.beginPath()
                ctx.moveTo(cx - side * 0.02, cy + side * 0.12)
                ctx.lineTo(cx - side * 0.18, cy + side * 0.50)
                ctx.lineTo(cx + side * 0.05, cy + side * 0.36)
                ctx.lineTo(cx - side * 0.02, cy + side * 0.68)
                ctx.lineTo(cx + side * 0.24, cy + side * 0.22)
                ctx.closePath()
                ctx.fill()
            } else if (kind === "rain") {
                drawCloud(cx, cy - side * 0.08, side * 0.72)
                drawRainDrops(cx, cy + side * 0.24, side * 0.68, 4)
            } else if (kind === "snow") {
                drawCloud(cx, cy - side * 0.08, side * 0.72)
                ctx.fillStyle = root.css(root.secondaryColor, 0.95)
                for (let i = 0; i < 4; ++i) {
                    ctx.beginPath()
                    ctx.arc(cx + (i - 1.5) * side * 0.14, cy + side * 0.30 + (i % 2) * side * 0.08, side * 0.025, 0, Math.PI * 2)
                    ctx.fill()
                }
            } else if (kind === "fog") {
                drawCloud(cx, cy - side * 0.14, side * 0.66)
                ctx.strokeStyle = root.css(root.secondaryColor, 0.62)
                ctx.lineWidth = Math.max(2, side * 0.026)
                ctx.lineCap = "round"
                for (let i = 0; i < 3; ++i) {
                    ctx.beginPath()
                    ctx.moveTo(cx - side * 0.32, cy + side * (0.20 + i * 0.13))
                    ctx.lineTo(cx + side * 0.32, cy + side * (0.20 + i * 0.13))
                    ctx.stroke()
                }
            } else {
                drawSunFace()
                ctx.globalAlpha = 0.88
                drawCloud(cx + side * 0.10, cy + side * 0.10, side * 0.55)
                ctx.globalAlpha = 1.0
            }
        }
    }
}
