import QtQuick 2.15
import "vic/icons" as VicIcons

Item {
    id: root

    // Diameter of the VIC content we are wrapping (px)
    property real vicDiameter: 260

    // Small air-gap between VIC and halo ring (px)
    property real gapPx: 10


    // Shrinks the halo diameter without changing ring thickness (px)
    // Positive numbers make the halo smaller.
    property real trimPx: 0
    // Ring thickness (px) — set thicker by default
    property real ringThickness: 20

    // Input state (from vehicle_state later)
    property bool active: false

    // How long to remain visible after active drops false (ms)
    property int holdMs: 1400

    // Heartbeat pulse
    property bool heartbeat: true

    // Base brightness
    property real glowOpacity: 0.80
    readonly property color neonCyan: "#73F6FF"
    readonly property color neonViolet: "#9B5CFF"
    readonly property color neonPearl: "#EAD7FF"
    readonly property color panelInk: "#060C18"
    // Gap size at the top of the halo where the high-beam icon sits.
    property real topBreakDeg: 44

    readonly property real haloDiameter: Math.max(0, vicDiameter - trimPx) + (gapPx * 2) + (ringThickness * 2)
    readonly property real _outerR: Math.min(width, height) / 2 - 1
    readonly property real _iconPlateSize: Math.max(22, ringThickness * 2.15)
    readonly property real _iconCenterY: (height / 2) - _outerR + (ringThickness * 0.55)
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"

    width: haloDiameter
    height: haloDiameter

    // Internal latched visibility so it "hangs" on after a blip
    property bool _latched: false

    // Display state: active OR latched
    readonly property bool _shown: active || _latched

    // Fade in/out (but don't instantly drop)
    opacity: _shown ? 1.0 : 0.0
    visible: opacity > 0.001
    layer.enabled: visible && !root.embeddedSafeMode
    layer.smooth: !root.embeddedSafeMode

    Behavior on opacity { NumberAnimation { duration: 180 } }

    // Heartbeat pulse: subtle scale + slight alpha modulation
    transform: Scale {
        id: hbScale
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: 1.0
        yScale: 1.0
    }

    SequentialAnimation {
        id: heartbeatAnim
        running: root.heartbeat && root._shown
        loops: Animation.Infinite

        // "lub"
        ParallelAnimation {
            NumberAnimation { target: hbScale; property: "xScale"; to: 1.03; duration: 90 }
            NumberAnimation { target: hbScale; property: "yScale"; to: 1.03; duration: 90 }
            NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: 90 }
        }

        // quick relax
        ParallelAnimation {
            NumberAnimation { target: hbScale; property: "xScale"; to: 1.00; duration: 110 }
            NumberAnimation { target: hbScale; property: "yScale"; to: 1.00; duration: 110 }
            NumberAnimation { target: root; property: "opacity"; to: 0.92; duration: 110 }
        }

        PauseAnimation { duration: 170 }

        // "dub"
        ParallelAnimation {
            NumberAnimation { target: hbScale; property: "xScale"; to: 1.02; duration: 90 }
            NumberAnimation { target: hbScale; property: "yScale"; to: 1.02; duration: 90 }
            NumberAnimation { target: root; property: "opacity"; to: 0.98; duration: 90 }
        }

        // relax again
        ParallelAnimation {
            NumberAnimation { target: hbScale; property: "xScale"; to: 1.00; duration: 130 }
            NumberAnimation { target: hbScale; property: "yScale"; to: 1.00; duration: 130 }
            NumberAnimation { target: root; property: "opacity"; to: 0.90; duration: 130 }
        }

        // gap between beats
        PauseAnimation { duration: 420 }
    }

    // Latch behavior: when active goes true, latch ON immediately.
    // When active goes false, stay latched for holdMs then release.
    Timer {
        id: holdTimer
        interval: root.holdMs
        repeat: false
        onTriggered: root._latched = false
    }

    onActiveChanged: {
        if (active) {
            _latched = true
            holdTimer.stop()
        } else {
            if (_latched) {
                holdTimer.stop()
                holdTimer.start()
            }
        }
    }

    Canvas {
        id: ringCanvas
        anchors.fill: parent
        antialiasing: true
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var outerR = Math.min(width, height) / 2 - 1
            var midR = outerR - ringThickness * 0.5
            var gapRad = Math.max(0.12, root.topBreakDeg * Math.PI / 180)
            var start = -Math.PI / 2 + (gapRad / 2)
            var end = start + (Math.PI * 2 - gapRad)

            function withAlpha(color, alpha) {
                return Qt.rgba(color.r, color.g, color.b, alpha)
            }

            function arc(radius, widthPx, color, alpha, from, to) {
                ctx.beginPath()
                ctx.arc(cx, cy, radius, from, to, false)
                ctx.strokeStyle = withAlpha(color, alpha)
                ctx.lineWidth = widthPx
                ctx.lineCap = "round"
                ctx.stroke()
            }

            arc(midR, ringThickness * 1.85, root.neonCyan, root.glowOpacity * 0.18, start, end)
            arc(midR, ringThickness * 1.26, root.neonViolet, root.glowOpacity * 0.24, start, end)
            arc(midR, ringThickness * 0.78, root.neonCyan, root.glowOpacity * 0.88, start, end)
            arc(midR - ringThickness * 0.16, Math.max(1, ringThickness * 0.18), root.neonPearl, 0.74, start + 0.18, end - 0.24)

            var capSpan = Math.min(0.55, (end - start) * 0.14)
            arc(midR, ringThickness * 0.92, root.neonPearl, 0.52, start, start + capSpan)
            arc(midR, ringThickness * 0.92, root.neonPearl, 0.42, end - capSpan, end)
        }
    }

    onTopBreakDegChanged: ringCanvas.requestPaint()
    onRingThicknessChanged: ringCanvas.requestPaint()
    onGlowOpacityChanged: ringCanvas.requestPaint()

    Rectangle {
        id: iconPlate
        width: root._iconPlateSize
        height: width
        radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: root._iconCenterY - (height / 2)
        color: Qt.rgba(root.panelInk.r, root.panelInk.g, root.panelInk.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(root.neonCyan.r, root.neonCyan.g, root.neonCyan.b, 0.70)
    }

    VicIcons.HighBeamIcon {
        anchors.centerIn: iconPlate
        width: iconPlate.width * 0.76
        height: width
        color: Qt.rgba(root.neonCyan.r, root.neonCyan.g, root.neonCyan.b, 0.98)
    }
}
