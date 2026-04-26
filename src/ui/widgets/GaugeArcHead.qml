import QtQuick 2.15

Item {
    id: root

    property bool scared: false
    property bool lowEffectMode: false
    property real headRadius: 11.5
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

    readonly property real padding: Math.max(8, headRadius * 1.05)
    readonly property real canvasExtent: Math.ceil((headRadius + padding) * 2)

    width: canvasExtent
    height: canvasExtent
    visible: headRadius > 0.1

    // Keep the production Linux target visible, but avoid the extra FBO layer on EGLFS/KMS.
    layer.enabled: visible && !embeddedSafeMode
    layer.smooth: true

    function requestHeadPaint() {
        canvas.requestPaint()
    }

    onScaredChanged: requestHeadPaint()
    onHeadRadiusChanged: requestHeadPaint()
    onLowEffectModeChanged: requestHeadPaint()

    Component.onCompleted: requestHeadPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        smooth: true
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const size = root.headRadius
            const cx = width / 2
            const cy = height / 2

            function rgba(color, alpha) {
                return "rgba("
                    + Math.round(color.r * 255) + ","
                    + Math.round(color.g * 255) + ","
                    + Math.round(color.b * 255) + ","
                    + alpha + ")"
            }

            function roundedRect(x, y, w, h, radius) {
                ctx.beginPath()
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + w - radius, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
                ctx.lineTo(x + w, y + h - radius)
                ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
                ctx.lineTo(x + radius, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.closePath()
            }

            function drawSunglassesHead() {
                const face = Qt.color("#FFD54A")
                const outline = Qt.color("#4A2300")
                const lens = Qt.color("#070A0F")
                const shine = Qt.color("#FFFFFF")

                ctx.save()
                ctx.translate(cx, cy)

                ctx.shadowColor = rgba(face, root.lowEffectMode ? 0.28 : 0.34)
                ctx.shadowBlur = size * (root.lowEffectMode ? 0.50 : 0.70)

                const faceGrad = ctx.createRadialGradient(-size * 0.26, -size * 0.34, size * 0.10, 0, 0, size)
                faceGrad.addColorStop(0.00, "rgba(255,255,255,0.78)")
                faceGrad.addColorStop(0.18, "rgba(255,230,102,1.00)")
                faceGrad.addColorStop(1.00, "rgba(244,156,28,1.00)")
                ctx.fillStyle = faceGrad
                ctx.beginPath()
                ctx.arc(0, 0, size, 0, Math.PI * 2)
                ctx.fill()

                ctx.shadowBlur = 0
                ctx.strokeStyle = rgba(outline, 0.44)
                ctx.lineWidth = Math.max(1.2, size * 0.10)
                ctx.stroke()

                ctx.fillStyle = rgba(lens, 0.94)
                roundedRect(-size * 0.72, -size * 0.34, size * 0.58, size * 0.36, size * 0.10)
                ctx.fill()
                roundedRect(size * 0.14, -size * 0.34, size * 0.58, size * 0.36, size * 0.10)
                ctx.fill()

                ctx.strokeStyle = rgba(lens, 0.94)
                ctx.lineWidth = Math.max(1.2, size * 0.11)
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(-size * 0.14, -size * 0.18)
                ctx.lineTo(size * 0.14, -size * 0.18)
                ctx.stroke()

                ctx.strokeStyle = rgba(shine, 0.42)
                ctx.lineWidth = Math.max(0.8, size * 0.055)
                ctx.beginPath()
                ctx.moveTo(-size * 0.60, -size * 0.26)
                ctx.lineTo(-size * 0.38, -size * 0.18)
                ctx.moveTo(size * 0.26, -size * 0.26)
                ctx.lineTo(size * 0.48, -size * 0.18)
                ctx.stroke()

                ctx.strokeStyle = rgba(outline, 0.68)
                ctx.lineWidth = Math.max(1.2, size * 0.12)
                ctx.beginPath()
                ctx.arc(0, size * 0.12, size * 0.43, Math.PI * 0.18, Math.PI * 0.82)
                ctx.stroke()
                ctx.restore()
            }

            function drawScaredHead() {
                const face = Qt.color("#FFD54A")
                const outline = Qt.color("#4A2300")
                const eye = Qt.color("#FFFFFF")
                const dark = Qt.color("#071018")
                const blue = Qt.color("#63C9FF")

                ctx.save()
                ctx.translate(cx, cy)

                ctx.shadowColor = rgba(face, root.lowEffectMode ? 0.28 : 0.34)
                ctx.shadowBlur = size * (root.lowEffectMode ? 0.50 : 0.70)

                const faceGrad = ctx.createRadialGradient(-size * 0.24, -size * 0.32, size * 0.10, 0, 0, size)
                faceGrad.addColorStop(0.00, "rgba(255,255,255,0.78)")
                faceGrad.addColorStop(0.20, "rgba(255,231,102,1.00)")
                faceGrad.addColorStop(1.00, "rgba(244,156,28,1.00)")
                ctx.fillStyle = faceGrad
                ctx.beginPath()
                ctx.arc(0, 0, size, 0, Math.PI * 2)
                ctx.fill()

                ctx.shadowBlur = 0
                ctx.strokeStyle = rgba(outline, 0.44)
                ctx.lineWidth = Math.max(1.2, size * 0.10)
                ctx.stroke()

                ctx.fillStyle = rgba(blue, 0.34)
                ctx.beginPath()
                ctx.arc(0, -size * 0.18, size * 0.78, Math.PI * 1.05, Math.PI * 1.95)
                ctx.fill()

                ctx.strokeStyle = rgba(outline, 0.70)
                ctx.lineWidth = Math.max(1.0, size * 0.08)
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(-size * 0.56, -size * 0.42)
                ctx.lineTo(-size * 0.20, -size * 0.30)
                ctx.moveTo(size * 0.56, -size * 0.42)
                ctx.lineTo(size * 0.20, -size * 0.30)
                ctx.stroke()

                ctx.fillStyle = rgba(eye, 0.98)
                ctx.beginPath()
                ctx.arc(-size * 0.34, -size * 0.14, size * 0.23, 0, Math.PI * 2)
                ctx.arc(size * 0.34, -size * 0.14, size * 0.23, 0, Math.PI * 2)
                ctx.fill()

                ctx.fillStyle = rgba(dark, 0.96)
                ctx.beginPath()
                ctx.arc(-size * 0.34, -size * 0.10, size * 0.095, 0, Math.PI * 2)
                ctx.arc(size * 0.34, -size * 0.10, size * 0.095, 0, Math.PI * 2)
                ctx.fill()

                ctx.save()
                ctx.translate(0, size * 0.36)
                ctx.scale(0.72, 1.0)
                ctx.fillStyle = rgba(dark, 0.94)
                ctx.beginPath()
                ctx.arc(0, 0, size * 0.28, 0, Math.PI * 2)
                ctx.fill()
                ctx.restore()

                ctx.fillStyle = rgba(blue, 0.74)
                ctx.beginPath()
                ctx.moveTo(size * 0.66, -size * 0.12)
                ctx.quadraticCurveTo(size * 0.92, size * 0.18, size * 0.64, size * 0.44)
                ctx.quadraticCurveTo(size * 0.38, size * 0.18, size * 0.66, -size * 0.12)
                ctx.fill()
                ctx.restore()
            }

            if (root.scared)
                drawScaredHead()
            else
                drawSunglassesHead()

            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordPaint("gauge.arcHead")
        }
    }
}
