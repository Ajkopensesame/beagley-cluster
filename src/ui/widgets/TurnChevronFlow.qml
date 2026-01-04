import QtQuick 2.15

Item {
    id: root

    // ===== API =====
    property bool active: false
    property string side: "left"      // "left" or "right"
    property int chevrons: 12

    // Full sweep duration in ms (1 second is classic)
    property int sweepMs: 1000

    // ===== Geometry =====
    property real gap: 2
    property real chevronWidth: 16

    // Height nesting (more noticeable)
    property real chevronHeight: 26
    // ===== Flow / glow tuning =====
    property real tailLen: 12
    property real gamma: 1.35

    // Always-visible chain (so it animates THROUGH chevrons)
    property real idleAlpha: 0.10      // faint when inactive
    property real baseAlpha: 0.06      // faint baseline when active (keeps all chevrons visible)
    property real aheadAlpha: 0.03     // faint ahead-of-head (prevents "hard off")

    property real chevronHeightOuter: 48

    // Stroke nesting
    property real thickness: 7
    property real thicknessOuter: 14
    property real thicknessPulseBoost: 1.5

    property color onColor: "#00E676"

    // ===== Tail / head shaping =====
    // Smaller tailDecay => longer tail (more arc-like)
    property real tailDecay: 0.16
    // Smaller headDecay => softer head (more arc-like)
    property real headDecay: 0.55
    // Keep 0 to avoid “faint always-on” when off
    property real tailFloor: 0.0

    // ===== Animated sweep position =====
    property real pos: 0.0

    NumberAnimation on pos {
        running: root.active
        loops: Animation.Infinite
        from: 0.0
        to: Math.max(1.0, root.chevrons * 1.0)   // wrap-friendly
        duration: Math.max(1, root.sweepMs)
        easing.type: Easing.InOutSine
    }

    onActiveChanged: {
        if (!active) pos = 0.0
        canvas.requestPaint()
    }

    // ---- helpers ----
    function outwardRank(visualIndex) {
        if (root.side === "left") return (root.chevrons - 1 - visualIndex)
        return visualIndex
    }

    function alphaFor(index) {
        // Indicator OFF → nothing visible
        if (!root.active) return 0.0

        var n = Math.max(1, root.chevrons)

        // Head position (wrap-safe)
        var head = root.pos % n

        // Logical inside→outside index
        var li = root.outwardRank(index)

        // Distance behind head (wrap-aware)
        var d = head - li
        if (d < 0) d += n   // 0..n

        // Distance ahead of head
        var ahead = li - head
        if (ahead < 0) ahead += n

        // Long tail behind the head
        var tailSpan = Math.max(1.0, root.tailLen)
        var tail = Math.exp(-(d / tailSpan) * root.tailDecay)

        // Soft head highlight (arc-like)
        var headFactor = Math.exp(-d * root.headDecay)

        // Faint forward bleed to prevent hard cutoff
        var forward = Math.exp(-(ahead / tailSpan) * 1.6) * 0.06

        var a = Math.max(tail * headFactor, forward)

        // Gamma shaping for analog feel
        a = Math.pow(a, root.gamma)

        return Math.max(0.0, Math.min(1.0, a))
    }

    // Size follows content (prevents clipping)
    implicitWidth: rowWidth
    width: implicitWidth
    property real rowWidth: root.chevrons * root.chevronWidth + (root.chevrons - 1) * root.gap
    height: Math.max(root.chevronHeight, root.chevronHeightOuter) + 8

    Canvas {
        id: canvas
        anchors.centerIn: parent
        width: root.rowWidth
        height: Math.max(root.chevronHeight, root.chevronHeightOuter)

        // Prefer stable AA
        renderTarget: Canvas.FramebufferObject
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var n = Math.max(1, root.chevrons)
            var baseH = root.chevronHeight
            var outerH = root.chevronHeightOuter

            // Center vertically
            var H = canvas.height
            var yCenter = H / 2

            // Color
            // QML Canvas uses rgba strings; build once
            function rgba(alpha) {
                // onColor is QColor; access r/g/b as 0..1
                var r = Math.round(root.onColor.r * 255)
                var g = Math.round(root.onColor.g * 255)
                var b = Math.round(root.onColor.b * 255)
                return "rgba(" + r + "," + g + "," + b + "," + alpha + ")"
            }

            for (var i = 0; i < n; i++) {
                var rnk = root.outwardRank(i)
                var t = (n <= 1) ? 0.0 : (rnk / (n - 1))

                var a = root.alphaFor(i)
                if (a <= 0.0001) continue

                var h = baseH + t * (outerH - baseH)
                var w = root.chevronWidth

                var x0 = i * (root.chevronWidth + root.gap)
                var y0 = yCenter - (h / 2)

                // Stroke width grows outward and pulses slightly with alpha
                var baseStroke = root.thickness + t * (root.thicknessOuter - root.thickness)
                var stroke = baseStroke + (a * root.thicknessPulseBoost)

                ctx.lineWidth = stroke
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.strokeStyle = rgba(a)

                // Chevron geometry:
                // left side: points left  ( \ / )
                // right side: points right ( / \ )
                ctx.beginPath()
                if (root.side === "left") {
                    ctx.moveTo(x0 + w, y0)
                    ctx.lineTo(x0 + w/2, y0 + h/2)
                    ctx.lineTo(x0 + w, y0 + h)
                } else {
                    ctx.moveTo(x0, y0)
                    ctx.lineTo(x0 + w/2, y0 + h/2)
                    ctx.lineTo(x0, y0 + h)
                }
                ctx.stroke()
            }
        }

        // repaint on animation tick
        Connections {
            target: root
            function onPosChanged() { canvas.requestPaint() }
        }
    }

    // Ensure first paint
    Component.onCompleted: canvas.requestPaint()
}
