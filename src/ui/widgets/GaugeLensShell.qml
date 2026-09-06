import QtQuick 2.15

Item {
    id: root

    property var theme
    property color gaugeColor: theme?.pearlLow ?? Qt.color("#D4C4FF")
    property color chromeColor: theme?.rimGlow ?? Qt.color("#D4C4FF")
    property string effectLevel: "high"
    property real podSize: Math.min(width, height) * 0.84
    property real faceSize: podSize

    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v))
    }

    function lerp(a, b, t) {
        return a + (b - a) * t
    }

    function mix(c1, c2, t, a) {
        return Qt.rgba(
            lerp(c1.r, c2.r, t),
            lerp(c1.g, c2.g, t),
            lerp(c1.b, c2.b, t),
            a
        )
    }

    function css(c, a) {
        return "rgba("
            + Math.round(clamp(c.r, 0, 1) * 255) + ","
            + Math.round(clamp(c.g, 0, 1) * 255) + ","
            + Math.round(clamp(c.b, 0, 1) * 255) + ","
            + clamp(a, 0, 1) + ")"
    }

    onThemeChanged: shellCanvas.requestPaint()
    onGaugeColorChanged: shellCanvas.requestPaint()
    onChromeColorChanged: shellCanvas.requestPaint()
    onEffectLevelChanged: shellCanvas.requestPaint()
    onPodSizeChanged: shellCanvas.requestPaint()
    onFaceSizeChanged: shellCanvas.requestPaint()
    Component.onCompleted: shellCanvas.requestPaint()

    Canvas {
        id: shellCanvas
        anchors.fill: parent
        visible: !root.lowEffectMode
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
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
            const faceOuter = Math.min(root.faceSize, side) * 0.498
            const rimRadius = faceOuter + side * 0.018
            const pearlLow = root.theme?.pearlLow ?? Qt.color("#D4C4FF")
            const rimGlow = root.theme?.rimGlow ?? pearlLow
            const accent = root.mix(root.gaugeColor, root.chromeColor, 0.42, 1.0)
            const bright = root.mix(accent, Qt.color("#FFFFFF"), 0.38, 1.0)
            const cyan = root.theme?.matrixCyan ?? Qt.color("#5FF7FF")
            const lava = root.theme?.lavaOrange ?? Qt.color("#FF7A14")

            // Deep black bezel lip — curved depth vs flat disc
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.96)"
            ctx.lineWidth = Math.max(10, side * 0.028)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            // Outer metal/glass rim gradient
            const rim = ctx.createLinearGradient(cx - rimRadius, cy - rimRadius, cx + rimRadius, cy + rimRadius)
            rim.addColorStop(0.00, root.css(bright, 0.58))
            rim.addColorStop(0.16, root.css(cyan, 0.18))
            rim.addColorStop(0.38, root.css(rimGlow, 0.34))
            rim.addColorStop(0.55, root.css(lava, 0.08))
            rim.addColorStop(0.72, "rgba(0,0,0,0.78)")
            rim.addColorStop(0.90, root.css(pearlLow, 0.28))
            rim.addColorStop(1.00, root.css(bright, 0.40))
            ctx.beginPath()
            ctx.strokeStyle = rim
            ctx.lineWidth = Math.max(3.5, side * 0.008)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            // Inner glass recess
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.88)"
            ctx.lineWidth = Math.max(3, side * 0.006)
            ctx.arc(cx, cy, faceOuter - ctx.lineWidth * 0.35, 0, Math.PI * 2)
            ctx.stroke()

            // Specular highlight arc (top-left glass catch)
            ctx.beginPath()
            ctx.strokeStyle = root.css(bright, 0.42)
            ctx.lineWidth = Math.max(2.0, side * 0.004)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.010, Math.PI * 0.88, Math.PI * 1.48)
            ctx.stroke()

            // Soft cyan secondary glint
            ctx.beginPath()
            ctx.strokeStyle = root.css(cyan, 0.16)
            ctx.lineWidth = Math.max(1.5, side * 0.0028)
            ctx.arc(cx, cy, rimRadius - side * 0.014, Math.PI * 0.95, Math.PI * 1.28)
            ctx.stroke()

            // Bottom shadow bite for curved depth
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.80)"
            ctx.lineWidth = Math.max(2.5, side * 0.005)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.010, Math.PI * 0.05, Math.PI * 0.55)
            ctx.stroke()
        }
    }
}
