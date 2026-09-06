import QtQuick 2.15
import QtGraphicalEffects 1.15
import BeagleY 1.0

// Concept-baked molten band: atlas Image + arc OpacityMask (GPU).
// Drive: single atlas composite (no Canvas). Show: same + optional bloom underlay.
Item {
    id: root

    property real progress: 0.0
    property real startAngleDeg: 225
    property real sweepAngleDeg: 210
    property real radiusFactor: 0.405
    // Band thickness as fraction of min(width,height) — matches atlas bake
    property real strokeWidthFactor: 0.053
    property bool richMode: false
    property real lavaPhase: 0.0
    property url annulusSource: Qt.resolvedUrl("../assets/skin-v2/lava-annulus.png")

    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))
    readonly property real strokePx: Math.max(10, Math.min(width, height) * strokeWidthFactor)
    readonly property bool showBand: clampedProgress > 0.002

    // Soft under-bloom (cheap SG) so atlas does not sit flat
    GaugeArcItem {
        anchors.fill: parent
        z: 0
        visible: root.showBand
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.clampedProgress
        radiusFactor: root.radiusFactor
        strokeWidth: root.strokePx * (root.richMode ? 1.35 : 1.15)
        color: Qt.rgba(1.0, 0.35, 0.06, root.richMode ? 0.34 : 0.22)
        segments: root.richMode ? 40 : 28
        roundedCaps: true
    }

    // Magenta lip near tail (concept red→orange start)
    GaugeArcItem {
        anchors.fill: parent
        z: 0
        visible: root.showBand && root.clampedProgress > 0.04
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: Math.min(root.clampedProgress, Math.max(0.06, root.clampedProgress * 0.42))
        radiusFactor: root.radiusFactor + 0.006
        strokeWidth: root.strokePx * 0.85
        color: Qt.rgba(0.72, 0.08, 0.22, root.richMode ? 0.28 : 0.18)
        segments: 24
        roundedCaps: true
    }

    Item {
        id: atlasSource
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        Image {
            anchors.fill: parent
            source: root.annulusSource
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }
    }

    Item {
        id: progressMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true

        GaugeArcItem {
            anchors.fill: parent
            startAngleDeg: root.startAngleDeg
            sweepAngleDeg: root.sweepAngleDeg
            startProgress: 0.0
            endProgress: root.clampedProgress
            radiusFactor: root.radiusFactor
            strokeWidth: root.strokePx
            color: "#FFFFFFFF"
            segments: root.richMode ? 56 : 40
            roundedCaps: true
        }
    }

    OpacityMask {
        anchors.fill: parent
        z: 2
        visible: root.showBand
        source: atlasSource
        maskSource: progressMask
        cached: !root.richMode
    }

    // Hot tip punch from atlas hot end (thin SG overlay — keeps leading edge alive)
    GaugeArcItem {
        anchors.fill: parent
        z: 3
        visible: root.showBand && root.clampedProgress > 0.01
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: Math.max(0.0, root.clampedProgress - (root.richMode ? 0.10 : 0.12))
        endProgress: root.clampedProgress
        radiusFactor: root.radiusFactor
        strokeWidth: root.strokePx * 0.72
        color: Qt.rgba(1.0, 0.97, 0.78, root.richMode ? 0.72 : 0.55)
        segments: 20
        roundedCaps: true
    }
}
