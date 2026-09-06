import QtQuick 2.15

Item {
    id: root

    property var theme
    property color gaugeColor: theme?.pearlLow ?? Qt.color("#D4C4FF")
    property color chromeColor: theme?.rimGlow ?? Qt.color("#D4C4FF")
    property string effectLevel: "high"
    property real podSize: Math.min(width, height) * 0.84
    property real faceSize: podSize
    property bool atlasRimEnabled: true
    property bool atlasFaceEnabled: false

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

            // Deep black bezel lip — thicker curved depth vs flat disc
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.98)"
            ctx.lineWidth = Math.max(14, side * 0.036)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            // Outer metal/glass rim gradient (concept thick beveled lens)
            const rim = ctx.createLinearGradient(cx - rimRadius, cy - rimRadius, cx + rimRadius, cy + rimRadius)
            rim.addColorStop(0.00, "rgba(255,255,255,0.88)")
            rim.addColorStop(0.10, root.css(bright, 0.72))
            rim.addColorStop(0.20, root.css(cyan, 0.16))
            rim.addColorStop(0.38, root.css(rimGlow, 0.42))
            rim.addColorStop(0.55, root.css(lava, 0.08))
            rim.addColorStop(0.72, "rgba(0,0,0,0.90)")
            rim.addColorStop(0.88, root.css(pearlLow, 0.36))
            rim.addColorStop(1.00, root.css(bright, 0.58))
            ctx.beginPath()
            ctx.strokeStyle = rim
            ctx.lineWidth = Math.max(5.0, side * 0.012)
            ctx.arc(cx, cy, rimRadius, 0, Math.PI * 2)
            ctx.stroke()

            // Inner glass recess (deeper lip)
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.96)"
            ctx.lineWidth = Math.max(5.0, side * 0.010)
            ctx.arc(cx, cy, faceOuter - ctx.lineWidth * 0.35, 0, Math.PI * 2)
            ctx.stroke()

            // Specular highlight arc (top-left glass catch) — concept white rim punch
            ctx.beginPath()
            ctx.strokeStyle = "rgba(255,255,255,0.86)"
            ctx.lineWidth = Math.max(3.0, side * 0.0065)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.008, Math.PI * 0.84, Math.PI * 1.54)
            ctx.stroke()

            // Soft white secondary specular (shorter)
            ctx.beginPath()
            ctx.strokeStyle = "rgba(255,255,255,0.35)"
            ctx.lineWidth = Math.max(1.8, side * 0.0035)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.016, Math.PI * 0.92, Math.PI * 1.22)
            ctx.stroke()

            // Soft cyan secondary glint
            ctx.beginPath()
            ctx.strokeStyle = root.css(cyan, 0.14)
            ctx.lineWidth = Math.max(1.5, side * 0.0028)
            ctx.arc(cx, cy, rimRadius - side * 0.014, Math.PI * 0.95, Math.PI * 1.28)
            ctx.stroke()

            // Bottom shadow bite for curved depth
            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.92)"
            ctx.lineWidth = Math.max(3.6, side * 0.0075)
            ctx.lineCap = "round"
            ctx.arc(cx, cy, rimRadius - side * 0.010, Math.PI * 0.05, Math.PI * 0.55)
            ctx.stroke()
        }
    }

    // Concept glass rim atlas (specular ring) — cheap Image overlay
    GaugeAtlasRim {
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        z: 20
        visible: root.atlasRimEnabled && !root.lowEffectMode
        showFacePlate: root.atlasFaceEnabled
        faceOpacity: 0.38
        rimOpacity: root.embeddedSafeMode ? 0.88 : 0.95
    }
}
