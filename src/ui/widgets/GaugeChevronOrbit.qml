import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property bool active: false
    property string side: "left"
    property int chevrons: 7
    property int cycleMs: 1900

    property real centerX: width / 2
    property real centerY: height / 2
    property real orbitRadius: Math.min(width, height) * 0.47
    property real startAngleDeg: -90
    property real travelSweepDeg: 180

    property real chevronSize: 22
    property real strokeWidth: 4.5
    property real strokeBoost: 2.0
    property real tailSpacingPhase: 0.115
    property real tailGamma: 1.20
    property real gravityExponent: 1.85
    property real topHoldPhase: 0.08
    property color onColor: "#52FFE1"
    property bool simplified: false
    property real phaseOverride: NaN

    property real headPhase: 0.0

    function wrap01(v) {
        var wrapped = v % 1.0
        return wrapped < 0 ? wrapped + 1.0 : wrapped
    }

    function clamp01(v) {
        return Math.max(0.0, Math.min(1.0, v))
    }

    function directionSign() {
        return root.side === "left" ? -1.0 : 1.0
    }

    function cyclePhase() {
        var external = Number(root.phaseOverride)
        return clamp01(isFinite(external) ? external : root.headPhase)
    }

    function fallClock() {
        var hold = clamp01(root.topHoldPhase)
        var p = cyclePhase()
        if (p <= hold)
            return 0.0
        return clamp01((p - hold) / Math.max(0.001, 1.0 - hold))
    }

    function fallDistance() {
        return Math.pow(fallClock(), Math.max(1.0, root.gravityExponent))
    }

    function phaseForIndex(index) {
        return clamp01(fallDistance() - index * root.tailSpacingPhase)
    }

    function releaseForIndex(index) {
        if (index <= 0)
            return 1.0

        var distancePastRelease = fallDistance() - index * root.tailSpacingPhase
        return clamp01(distancePastRelease / 0.045)
    }

    function angleDegForPhase(phase) {
        return root.startAngleDeg + root.directionSign() * root.travelSweepDeg * clamp01(phase)
    }

    function tangentDegForAngle(angleDeg) {
        return angleDeg + (root.directionSign() > 0 ? 90.0 : -90.0)
    }

    function alphaForIndex(index) {
        if (!root.active)
            return 0.0

        var release = releaseForIndex(index)
        if (release <= 0.0)
            return 0.0

        var tailT = root.chevrons <= 1 ? 0.0 : index / (root.chevrons - 1.0)
        var trailAlpha = Math.pow(1.0 - tailT * 0.32, root.tailGamma)
        return clamp01(trailAlpha * release)
    }

    NumberAnimation on headPhase {
        running: root.active && !isFinite(Number(root.phaseOverride))
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: Math.max(1, root.cycleMs)
        easing.type: Easing.Linear
    }

    onActiveChanged: if (active) headPhase = 0.0

    Repeater {
        model: root.chevrons

        delegate: Item {
            id: chevron

            readonly property real chevronAlpha: root.alphaForIndex(index)
            readonly property real phase: root.phaseForIndex(index)
            readonly property real angleDeg: root.angleDegForPhase(phase)
            readonly property real angleRad: angleDeg * Math.PI / 180.0
            readonly property real tailT: root.chevrons <= 1 ? 0.0 : index / (root.chevrons - 1.0)
            readonly property real sizeScale: 1.02 - tailT * 0.10
            readonly property real lineWidth: root.strokeWidth + (1.0 - tailT) * root.strokeBoost * 0.42
            readonly property real centerPosX: root.centerX + Math.cos(angleRad) * root.orbitRadius
            readonly property real centerPosY: root.centerY + Math.sin(angleRad) * root.orbitRadius

            visible: root.active && chevronAlpha > 0.01
            opacity: chevronAlpha
            width: root.chevronSize * 1.72
            height: root.chevronSize * 1.26
            x: centerPosX - width / 2
            y: centerPosY - height / 2
            rotation: root.tangentDegForAngle(angleDeg)
            scale: sizeScale
            antialiasing: true

            Shape {
                anchors.fill: parent
                antialiasing: true
                visible: !root.simplified
                scale: 1.22
                opacity: 0.20 + chevron.chevronAlpha * 0.36

                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillColor: Qt.rgba(root.onColor.r, root.onColor.g, root.onColor.b, 0.38)
                    startX: width * 0.16
                    startY: height * 0.10

                    PathLine { x: width * 0.42; y: height * 0.10 }
                    PathLine { x: width * 0.86; y: height * 0.50 }
                    PathLine { x: width * 0.42; y: height * 0.90 }
                    PathLine { x: width * 0.16; y: height * 0.90 }
                    PathLine { x: width * 0.54; y: height * 0.50 }
                    PathLine { x: width * 0.16; y: height * 0.10 }
                }
            }

            Shape {
                anchors.fill: parent
                antialiasing: true

                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.10 + chevron.chevronAlpha * 0.24)
                    strokeWidth: Math.max(0.8, chevron.lineWidth * 0.16)
                    fillColor: Qt.rgba(root.onColor.r, root.onColor.g, root.onColor.b, 0.34 + chevron.chevronAlpha * 0.62)
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: width * 0.18
                    startY: height * 0.14

                    PathLine { x: width * 0.41; y: height * 0.14 }
                    PathLine { x: width * 0.82; y: height * 0.50 }
                    PathLine { x: width * 0.41; y: height * 0.86 }
                    PathLine { x: width * 0.18; y: height * 0.86 }
                    PathLine { x: width * 0.56; y: height * 0.50 }
                    PathLine { x: width * 0.18; y: height * 0.14 }
                }
            }
        }
    }
}
