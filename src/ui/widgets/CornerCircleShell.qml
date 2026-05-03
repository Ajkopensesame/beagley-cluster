import QtQuick 2.15

Item {
    id: root

    property color accentColor: "#C7B7FF"
    property color secondaryAccentColor: "#58FFE1"
    property string effectLevel: "high"
    property bool active: true
    property string corner: "topLeft"
    property real bleedFraction: 0.18

    readonly property real faceInset: Math.max(20, Math.min(width, height) * 0.178)
    readonly property real contentInset: Math.max(26, Math.min(width, height) * 0.235)
    readonly property real contentDiameter: Math.max(42, Math.min(width, height) - contentInset * 2)

    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

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

    function isRightCorner() {
        return corner === "topRight" || corner === "bottomRight"
    }

    function isBottomCorner() {
        return corner === "bottomLeft" || corner === "bottomRight"
    }

    function visibleAngle() {
        if (corner === "topRight")
            return Math.PI * 0.75
        if (corner === "bottomLeft")
            return -Math.PI * 0.25
        if (corner === "bottomRight")
            return Math.PI * 1.25
        return Math.PI * 0.25
    }

    onAccentColorChanged: faceCanvas.requestPaint()
    onSecondaryAccentColorChanged: faceCanvas.requestPaint()
    onEffectLevelChanged: faceCanvas.requestPaint()
    onActiveChanged: faceCanvas.requestPaint()
    onCornerChanged: faceCanvas.requestPaint()
    onBleedFractionChanged: faceCanvas.requestPaint()
    Component.onCompleted: faceCanvas.requestPaint()

    Canvas {
        id: faceCanvas
        anchors.fill: parent
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
            const outerR = side * 0.5 - Math.max(1.5, side * 0.012)
            const faceR = outerR - root.faceInset
            const rightCorner = root.isRightCorner()
            const bottomCorner = root.isBottomCorner()
            const clippedX = rightCorner ? width : 0
            const clippedY = bottomCorner ? height : 0
            const visibleX = rightCorner ? 0 : width
            const visibleY = bottomCorner ? 0 : height
            const visibleCenter = root.visibleAngle()
            const shadowCenter = visibleCenter + Math.PI
            const clippedAmount = root.clamp(root.bleedFraction, 0.0, 0.34)
            const visibleSpan = Math.PI * (0.76 + clippedAmount * 0.95)
            const innerSpan = Math.PI * (0.58 + clippedAmount * 0.62)
            const shadowSpan = Math.PI * (0.42 + clippedAmount * 0.86)
            const glassHighlight = root.active ? "rgba(242,247,255,0.24)" : "rgba(190,202,220,0.14)"
            const glassSoft = root.active ? "rgba(160,176,205,0.13)" : "rgba(130,145,166,0.08)"
            const tickColor = root.active ? "rgba(218,226,242,0.18)" : "rgba(170,184,205,0.10)"

            function drawArc(radius, centerAngle, span, style, lineWidth, cap) {
                ctx.beginPath()
                ctx.strokeStyle = style
                ctx.lineWidth = lineWidth
                ctx.lineCap = cap ? cap : "round"
                ctx.arc(cx, cy, radius, centerAngle - span / 2, centerAngle + span / 2)
                ctx.stroke()
            }

            const ring = ctx.createLinearGradient(clippedX, clippedY, visibleX, visibleY)
            ring.addColorStop(0.00, "rgba(0,0,0,1.00)")
            ring.addColorStop(0.16, "rgba(4,5,11,0.98)")
            ring.addColorStop(0.42, "rgba(12,13,18,0.94)")
            ring.addColorStop(0.72, "rgba(24,27,34,0.76)")
            ring.addColorStop(1.00, "rgba(7,8,12,0.98)")
            ctx.fillStyle = ring
            ctx.beginPath()
            ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
            ctx.arc(cx, cy, faceR, 0, Math.PI * 2, true)
            ctx.fill("evenodd")

            const face = ctx.createRadialGradient(cx, cy, faceR * 0.10, cx, cy, faceR)
            face.addColorStop(0.00, "rgba(5,6,11,1.00)")
            face.addColorStop(0.62, "rgba(3,4,9,1.00)")
            face.addColorStop(0.88, "rgba(1,2,5,1.00)")
            face.addColorStop(1.00, "rgba(0,0,0,1.00)")
            ctx.fillStyle = face
            ctx.beginPath()
            ctx.arc(cx, cy, faceR, 0, Math.PI * 2)
            ctx.fill()

            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.94)"
            ctx.lineWidth = Math.max(5, side * 0.040)
            ctx.arc(cx, cy, faceR + ctx.lineWidth * 0.45, 0, Math.PI * 2)
            ctx.stroke()

            const rim = ctx.createLinearGradient(clippedX, clippedY, visibleX, visibleY)
            rim.addColorStop(0.00, "rgba(0,0,0,0.96)")
            rim.addColorStop(0.28, "rgba(34,37,46,0.44)")
            rim.addColorStop(0.62, glassHighlight)
            rim.addColorStop(0.82, "rgba(18,20,27,0.68)")
            rim.addColorStop(1.00, "rgba(0,0,0,0.92)")
            ctx.beginPath()
            ctx.strokeStyle = rim
            ctx.lineWidth = Math.max(4, side * 0.038)
            ctx.arc(cx, cy, outerR - ctx.lineWidth * 0.5, 0, Math.PI * 2)
            ctx.stroke()

            ctx.beginPath()
            ctx.strokeStyle = "rgba(0,0,0,0.86)"
            ctx.lineWidth = Math.max(3, side * 0.024)
            ctx.arc(cx, cy, faceR + ctx.lineWidth * 0.5, 0, Math.PI * 2)
            ctx.stroke()

            drawArc(outerR - side * 0.038,
                    visibleCenter,
                    visibleSpan,
                    glassHighlight,
                    Math.max(2.2, side * 0.018),
                    "round")
            drawArc(faceR + Math.max(7, side * 0.050),
                    visibleCenter,
                    innerSpan,
                    glassSoft,
                    Math.max(1.6, side * 0.012),
                    "round")
            drawArc(outerR - side * 0.042,
                    shadowCenter,
                    shadowSpan,
                    "rgba(0,0,0,0.78)",
                    Math.max(4, side * 0.028),
                    "round")

            if (!root.lowEffectMode) {
                const tickCount = 7
                const span = visibleSpan * 0.86
                const start = visibleCenter - span / 2
                const tickOuter = faceR + Math.max(9, side * 0.060)
                const tickInner = faceR + Math.max(4, side * 0.030)
                ctx.strokeStyle = tickColor
                ctx.lineWidth = Math.max(1.2, side * 0.009)
                ctx.lineCap = "round"
                for (let i = 0; i < tickCount; ++i) {
                    const a = start + (span * i) / (tickCount - 1)
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(a) * tickInner, cy + Math.sin(a) * tickInner)
                    ctx.lineTo(cx + Math.cos(a) * tickOuter, cy + Math.sin(a) * tickOuter)
                    ctx.stroke()
                }
            }
        }
    }
}
