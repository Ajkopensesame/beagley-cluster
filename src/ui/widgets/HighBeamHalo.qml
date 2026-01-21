import QtQuick 2.15

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

    readonly property real haloDiameter: Math.max(0, vicDiameter - trimPx) + (gapPx * 2) + (ringThickness * 2)

    width: haloDiameter
    height: haloDiameter

    // Internal latched visibility so it "hangs" on after a blip
    property bool _latched: false

    // Display state: active OR latched
    readonly property bool _shown: active || _latched

    // Fade in/out (but don't instantly drop)
    opacity: _shown ? 1.0 : 0.0
    visible: opacity > 0.001

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
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var outerR = Math.min(width, height) / 2 - 1
            var innerR = outerR - ringThickness

            // Ring via even-odd fill
            ctx.beginPath()
            ctx.arc(cx, cy, outerR, 0, Math.PI * 2, false)
            ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)

            // OEM-ish high beam blue glow
            var grad = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
            grad.addColorStop(0.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))
            grad.addColorStop(0.35, Qt.rgba(0.24, 0.65, 1.0, glowOpacity * 0.55))
            grad.addColorStop(0.70, Qt.rgba(0.24, 0.65, 1.0, glowOpacity))
            grad.addColorStop(1.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))

            ctx.fillStyle = grad
            ctx.fill("evenodd")
        }
    }
}
