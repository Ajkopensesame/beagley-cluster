import QtQuick 2.15

Item {
    id: root

    property var theme
    property color gaugeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
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
            const rimRadius = faceOuter + side * 0.006
            const pearlLow = root.theme?.pearlLow ?? Qt.color("#C7B7FF")
            const accent = root.mix(root.gaugeColor, root.chromeColor, 0.42, 1.0)
            const bright = root.mix(accent, Qt.color("#FFFFFF"), 0.30, 1.0)
            const cyan = Qt.color("#5FF7FF")

            // Thin black lip only. The gauge widget owns the full black face; this
            // shell should not create a broad grey halo over the map.
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.92)"
            ctx.lineWidth = Math.max(6, side * 0.012)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            const rim = ctx.createLinearGradient(cx - rimRadius, cy - rimRadius, cx + rimRadius, cy + rimRadius)
            rim.addColorStop(0.00, root.css(bright, 0.44))
            rim.addColorStop(0.18, root.css(cyan, 0.13))
            rim.addColorStop(0.48, root.css(accent, 0.08))
            rim.addColorStop(0.78, "rgba(0,0,0,0.64)")
            rim.addColorStop(1.00, root.css(pearlLow, 0.20))
            ctx.beginPath()
            ctx.strokeStyle = rim
            ctx.lineWidth = Math.max(2, side * 0.004)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.82)"
            ctx.lineWidth = Math.max(2, side * 0.004)
            ctx.arc(cx, cy, faceOuter - ctx.lineWidth, 0, Math.PI * 2)
            ctx.stroke()

            ctx.beginPath()
            ctx.strokeStyle = root.css(bright, 0.22)
            ctx.lineWidth = Math.max(1.5, side * 0.0025)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.006, Math.PI * 0.86, Math.PI * 1.42)
            ctx.stroke()

            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.74)"
            ctx.lineWidth = Math.max(2, side * 0.004)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.006, Math.PI * 0.02, Math.PI * 0.52)
            ctx.stroke()
        }
    }
}
