import QtQuick 2.15

Item {
    id: root

    // The halo wraps the VIC. You set vicDiameter to match your VIC widget size.
    property real vicDiameter: 260

    // The gap you requested: "small space between the VIC and halo"
    property real gapPx: 10

    // Halo thickness (ring width)
    property real ringThickness: 14

    // State input
    property bool active: false

    // OEM-ish high beam blue (tunable)
    property color beamColor: "#3DA5FF"

    // Visual intensity
    property real glowOpacity: 0.70

    // Derived geometry
    readonly property real haloDiameter: vicDiameter + (gapPx * 2) + (ringThickness * 2)

    width: haloDiameter
    height: haloDiameter

    // This must never compete with warnings: no pulsing, no “breathing”.
    // Soft fade only so it doesn’t “snap” on/off harshly.
    opacity: active ? 1.0 : 0.0
    visible: opacity > 0.001

    Behavior on opacity {
        NumberAnimation { duration: 120 }
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

            // Draw a ring via even-odd fill.
            ctx.beginPath()
            ctx.arc(cx, cy, outerR, 0, Math.PI * 2, false)
            ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)

            // Glow gradient that fades outward and inward slightly.
            var grad = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
            var c = Qt.colorEqual(beamColor, "transparent") ? Qt.rgba(0.24, 0.65, 1.0, 1.0) : beamColor

            // Convert Qt.rgba if needed: just rely on Qt to handle CSS strings
            // We’ll use a simple alpha ramp:
            grad.addColorStop(0.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))
            grad.addColorStop(0.35, Qt.rgba(0.24, 0.65, 1.0, glowOpacity * 0.55))
            grad.addColorStop(0.70, Qt.rgba(0.24, 0.65, 1.0, glowOpacity))
            grad.addColorStop(1.00, Qt.rgba(0.24, 0.65, 1.0, 0.00))

            ctx.fillStyle = grad
            ctx.fill("evenodd")
        }
    }

    // Repaint when any geometry-affecting property changes
    onVicDiameterChanged: haloCanvas.requestPaint()
    onGapPxChanged: haloCanvas.requestPaint()
    onRingThicknessChanged: haloCanvas.requestPaint()
    onBeamColorChanged: haloCanvas.requestPaint()
    onGlowOpacityChanged: haloCanvas.requestPaint()

    // id alias for repaint calls above
    Canvas { id: haloCanvas; visible: false }
}
