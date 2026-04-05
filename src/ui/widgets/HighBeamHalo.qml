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
    // Gap size at the top of the halo where the high-beam icon sits.
    property real topBreakDeg: 44

    readonly property real haloDiameter: Math.max(0, vicDiameter - trimPx) + (gapPx * 2) + (ringThickness * 2)
    readonly property real _outerR: Math.min(width, height) / 2 - 1
    readonly property real _iconPlateSize: Math.max(22, ringThickness * 2.15)
    readonly property real _iconCenterY: (height / 2) - _outerR + (ringThickness * 0.55)

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
        id: ringCanvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var outerR = Math.min(width, height) / 2 - 1
            var innerR = outerR - ringThickness
            var gapRad = Math.max(0.12, root.topBreakDeg * Math.PI / 180)
            var start = -Math.PI / 2 + (gapRad / 2)
            var end = start + (Math.PI * 2 - gapRad)

            // Annular segment with a top break for the icon.
            ctx.beginPath()
            ctx.arc(cx, cy, outerR, start, end, false)
            ctx.arc(cx, cy, innerR, end, start, true)
            ctx.closePath()

            // OEM-ish high beam blue glow
            var grad = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
            grad.addColorStop(0.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))
            grad.addColorStop(0.35, Qt.rgba(0.24, 0.65, 1.0, glowOpacity * 0.55))
            grad.addColorStop(0.70, Qt.rgba(0.24, 0.65, 1.0, glowOpacity))
            grad.addColorStop(1.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))

            ctx.fillStyle = grad
            ctx.fill()
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
        color: Qt.rgba(0.02, 0.08, 0.14, 0.92)
        border.width: 1
        border.color: Qt.rgba(0.35, 0.78, 1.0, 0.58)
    }

    VicIcons.HighBeamIcon {
        anchors.centerIn: iconPlate
        width: iconPlate.width * 0.76
        height: width
        color: Qt.rgba(0.52, 0.86, 1.0, 0.98)
    }
}
