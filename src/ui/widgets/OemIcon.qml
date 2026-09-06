import QtQuick 2.15

Item {
    id: root

    width: 64
    height: 64

    property string icon: "menu"
    property color color: "#F7FBFF"
    property color accentColor: "#58FFE1"
    property color mutedColor: Qt.rgba(color.r, color.g, color.b, 0.28)
    property real strokeWidth: Math.max(3, Math.min(width, height) * 0.085)
    property bool active: true

    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

    function requestIconPaint() {
        iconCanvas.requestPaint()
    }

    onIconChanged: requestIconPaint()
    onColorChanged: requestIconPaint()
    onAccentColorChanged: requestIconPaint()
    onMutedColorChanged: requestIconPaint()
    onStrokeWidthChanged: requestIconPaint()
    onActiveChanged: requestIconPaint()

    Canvas {
        id: iconCanvas
        anchors.fill: parent
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
        antialiasing: !root.embeddedSafeMode
        smooth: !root.embeddedSafeMode

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        function css(c, alphaOverride) {
            var alpha = alphaOverride
            if (alpha === undefined || alpha === null)
                alpha = c.a
            return "rgba("
                + Math.round(c.r * 255) + ","
                + Math.round(c.g * 255) + ","
                + Math.round(c.b * 255) + ","
                + Math.max(0, Math.min(1, alpha)) + ")"
        }

        function roundedRectPath(ctx, x, y, w, h, r) {
            r = Math.min(r, w / 2, h / 2)
            ctx.beginPath()
            ctx.moveTo(x + r, y)
            ctx.arcTo(x + w, y, x + w, y + h, r)
            ctx.arcTo(x + w, y + h, x, y + h, r)
            ctx.arcTo(x, y + h, x, y, r)
            ctx.arcTo(x, y, x + w, y, r)
            ctx.closePath()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const w = width
            const h = height
            const s = Math.max(1, Math.min(w, h))
            const ox = (w - s) / 2
            const oy = (h - s) / 2
            const sw = Math.max(2, root.strokeWidth)
            const primary = root.active ? root.color : root.mutedColor
            const accent = root.active ? root.accentColor : root.mutedColor

            function x(v) { return ox + s * v }
            function y(v) { return oy + s * v }
            function line(x1, y1, x2, y2, color, widthScale) {
                ctx.strokeStyle = css(color)
                ctx.lineWidth = sw * (widthScale || 1.0)
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(x1, y1)
                ctx.lineTo(x2, y2)
                ctx.stroke()
            }

            const name = String(root.icon).toLowerCase()

            if (name === "close") {
                line(x(0.28), y(0.28), x(0.72), y(0.72), primary, 1.06)
                line(x(0.72), y(0.28), x(0.28), y(0.72), primary, 1.06)
                return
            }

            if (name === "menu") {
                line(x(0.20), y(0.28), x(0.80), y(0.28), accent, 1.12)
                line(x(0.20), y(0.50), x(0.80), y(0.50), primary, 1.12)
                line(x(0.20), y(0.72), x(0.80), y(0.72), accent, 1.12)
                return
            }

            if (name === "route") {
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.strokeStyle = css(accent)
                ctx.lineWidth = sw
                ctx.beginPath()
                ctx.moveTo(x(0.24), y(0.72))
                ctx.bezierCurveTo(x(0.34), y(0.44), x(0.55), y(0.62), x(0.70), y(0.29))
                ctx.stroke()

                ctx.fillStyle = css(primary)
                ctx.beginPath()
                ctx.arc(x(0.24), y(0.72), sw * 0.95, 0, Math.PI * 2)
                ctx.fill()

                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw * 0.82
                ctx.beginPath()
                ctx.arc(x(0.70), y(0.29), sw * 1.25, 0, Math.PI * 2)
                ctx.stroke()
                return
            }

            if (name === "radar") {
                ctx.strokeStyle = css(primary, 0.90)
                ctx.lineWidth = sw * 0.58
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(x(0.50), y(0.50), s * 0.18, -0.92, 2.72)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(x(0.50), y(0.50), s * 0.32, -0.78, 2.58)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(x(0.50), y(0.50), s * 0.45, -0.64, 2.42)
                ctx.stroke()

                line(x(0.50), y(0.50), x(0.84), y(0.26), accent, 0.86)
                ctx.fillStyle = css(accent)
                ctx.beginPath()
                ctx.arc(x(0.50), y(0.50), sw * 0.82, 0, Math.PI * 2)
                ctx.fill()
                return
            }

            if (name === "weather") {
                ctx.strokeStyle = css(accent)
                ctx.lineWidth = sw * 0.72
                ctx.lineCap = "round"
                for (let i = 0; i < 8; i++) {
                    const a = (Math.PI * 2 / 8) * i
                    const r1 = s * 0.29
                    const r2 = s * 0.39
                    line(x(0.67) + Math.cos(a) * r1, y(0.34) + Math.sin(a) * r1,
                         x(0.67) + Math.cos(a) * r2, y(0.34) + Math.sin(a) * r2,
                         accent, 0.58)
                }
                ctx.beginPath()
                ctx.arc(x(0.67), y(0.34), s * 0.14, 0, Math.PI * 2)
                ctx.stroke()

                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(x(0.21), y(0.67))
                ctx.bezierCurveTo(x(0.20), y(0.53), x(0.33), y(0.45), x(0.44), y(0.52))
                ctx.bezierCurveTo(x(0.50), y(0.38), x(0.69), y(0.43), x(0.71), y(0.58))
                ctx.bezierCurveTo(x(0.83), y(0.58), x(0.84), y(0.73), x(0.70), y(0.73))
                ctx.lineTo(x(0.29), y(0.73))
                ctx.stroke()
                return
            }

            if (name === "audio") {
                const bars = [
                    { x: 0.27, y: 0.42, h: 0.30, c: accent },
                    { x: 0.43, y: 0.27, h: 0.45, c: primary },
                    { x: 0.59, y: 0.36, h: 0.36, c: accent },
                    { x: 0.75, y: 0.49, h: 0.23, c: primary }
                ]
                for (let i = 0; i < bars.length; i++) {
                    const b = bars[i]
                    ctx.fillStyle = css(b.c)
                    roundedRectPath(ctx, x(b.x), y(b.y), s * 0.075, s * b.h, s * 0.038)
                    ctx.fill()
                }
                line(x(0.21), y(0.79), x(0.86), y(0.79), primary, 0.62)
                return
            }

            if (name === "play") {
                ctx.fillStyle = css(accent)
                ctx.beginPath()
                ctx.moveTo(x(0.34), y(0.22))
                ctx.lineTo(x(0.34), y(0.78))
                ctx.lineTo(x(0.78), y(0.50))
                ctx.closePath()
                ctx.fill()
                return
            }

            if (name === "pause") {
                ctx.fillStyle = css(accent)
                roundedRectPath(ctx, x(0.30), y(0.22), s * 0.13, s * 0.56, s * 0.035)
                ctx.fill()
                roundedRectPath(ctx, x(0.57), y(0.22), s * 0.13, s * 0.56, s * 0.035)
                ctx.fill()
                return
            }

            if (name === "next" || name === "previous") {
                const flip = name === "previous"
                ctx.fillStyle = css(accent)
                function px(v) { return flip ? x(1.0 - v) : x(v) }
                ctx.beginPath()
                ctx.moveTo(px(0.24), y(0.24))
                ctx.lineTo(px(0.24), y(0.76))
                ctx.lineTo(px(0.54), y(0.50))
                ctx.closePath()
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(px(0.46), y(0.24))
                ctx.lineTo(px(0.46), y(0.76))
                ctx.lineTo(px(0.76), y(0.50))
                ctx.closePath()
                ctx.fill()
                line(px(0.80), y(0.24), px(0.80), y(0.76), primary, 0.92)
                return
            }

            if (name === "fuel") {
                ctx.lineWidth = sw
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                roundedRectPath(ctx, x(0.20), y(0.16), s * 0.42, s * 0.68, s * 0.06)
                ctx.fillStyle = css(Qt.rgba(primary.r, primary.g, primary.b, 0.28))
                ctx.fill()
                ctx.strokeStyle = css(primary)
                ctx.stroke()
                roundedRectPath(ctx, x(0.28), y(0.26), s * 0.26, s * 0.16, s * 0.03)
                ctx.fillStyle = css(accent)
                ctx.fill()
                ctx.stroke()
                ctx.strokeStyle = css(accent)
                ctx.lineWidth = sw * 1.05
                ctx.beginPath()
                ctx.moveTo(x(0.62), y(0.34))
                ctx.bezierCurveTo(x(0.80), y(0.38), x(0.86), y(0.52), x(0.76), y(0.64))
                ctx.lineTo(x(0.76), y(0.80))
                ctx.lineTo(x(0.68), y(0.80))
                ctx.stroke()
                // foot
                ctx.strokeStyle = css(primary)
                ctx.beginPath()
                ctx.moveTo(x(0.16), y(0.84))
                ctx.lineTo(x(0.66), y(0.84))
                ctx.stroke()
                return
            }

            if (name === "drive") {
                line(x(0.24), y(0.30), x(0.76), y(0.30), primary, 0.78)
                line(x(0.24), y(0.70), x(0.76), y(0.70), primary, 0.78)
                line(x(0.50), y(0.30), x(0.50), y(0.70), accent, 0.78)
                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw * 0.72
                for (let j = 0; j < 4; j++) {
                    const px = j % 2 === 0 ? 0.19 : 0.71
                    const py = j < 2 ? 0.22 : 0.62
                    ctx.beginPath()
                    ctx.arc(x(px + 0.05), y(py + 0.08), s * 0.075, 0, Math.PI * 2)
                    ctx.stroke()
                }
                return
            }

            if (name === "thermo" || name === "thermometer" || name === "temp") {
                const cx = x(0.50)
                const stemTop = y(0.12)
                const stemBot = y(0.58)
                const stemW = s * 0.16
                const bulbR = s * 0.18
                ctx.lineWidth = sw
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(cx - stemW * 0.5, stemTop)
                ctx.lineTo(cx + stemW * 0.5, stemTop)
                ctx.lineTo(cx + stemW * 0.5, stemBot)
                ctx.lineTo(cx - stemW * 0.5, stemBot)
                ctx.closePath()
                ctx.fillStyle = css(Qt.rgba(primary.r, primary.g, primary.b, 0.22))
                ctx.fill()
                ctx.strokeStyle = css(primary)
                ctx.stroke()
                // mercury
                ctx.fillStyle = css(accent)
                ctx.fillRect(cx - stemW * 0.28, stemTop + (stemBot - stemTop) * 0.35, stemW * 0.56, (stemBot - stemTop) * 0.65)
                // ticks
                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw * 0.55
                for (let ti = 0; ti < 3; ti++) {
                    const ty = stemTop + (stemBot - stemTop) * (0.22 + ti * 0.2)
                    ctx.beginPath()
                    ctx.moveTo(cx + stemW * 0.55, ty)
                    ctx.lineTo(cx + stemW * 1.05, ty)
                    ctx.stroke()
                }
                ctx.beginPath()
                ctx.arc(cx, stemBot + bulbR * 0.55, bulbR, 0, Math.PI * 2)
                ctx.fillStyle = css(accent)
                ctx.fill()
                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw
                ctx.stroke()
                return
            }

            if (name === "warning") {
                ctx.strokeStyle = css(primary)
                ctx.lineWidth = sw
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                ctx.moveTo(x(0.50), y(0.16))
                ctx.lineTo(x(0.85), y(0.80))
                ctx.lineTo(x(0.15), y(0.80))
                ctx.closePath()
                ctx.stroke()
                line(x(0.50), y(0.38), x(0.50), y(0.58), accent, 0.82)
                ctx.fillStyle = css(accent)
                ctx.beginPath()
                ctx.arc(x(0.50), y(0.68), sw * 0.46, 0, Math.PI * 2)
                ctx.fill()
                return
            }

            line(x(0.20), y(0.50), x(0.80), y(0.50), primary, 1.0)
        }
    }
}
