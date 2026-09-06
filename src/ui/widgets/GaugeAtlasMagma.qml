import QtQuick 2.15
import BeagleY 1.0

// Soft under-bloom only. Atlas Image is MagmaAtlasOverlay (MainV3 sibling).
Item {
    id: root
    property real progress: 0.0
    property real startAngleDeg: 225
    property real sweepAngleDeg: 210
    property real radiusFactor: 0.405
    property real strokeWidthFactor: 0.078
    property bool richMode: false
    property real lavaPhase: 0.0
    property url annulusSource: Qt.resolvedUrl("../assets/skin-v2/lava-annulus.png")
    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))
    readonly property real strokePx: Math.max(16, Math.min(width, height) * strokeWidthFactor)
    readonly property bool showBand: clampedProgress > 0.002

    GaugeArcItem {
        anchors.fill: parent
        visible: root.showBand
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.clampedProgress
        radiusFactor: root.radiusFactor
        strokeWidth: root.strokePx * 1.20
        color: Qt.rgba(0.90, 0.10, 0.02, root.richMode ? 0.28 : 0.22)
        segments: 32
        roundedCaps: false
    }
}
