import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property bool active: false
    property string side: "left" // "left" spins CCW, "right" spins CW
    property int chevrons: 10
    property int cycleMs: 1200

    property real centerX: width / 2
    property real centerY: height / 2
    property real orbitRadius: Math.min(width, height) * 0.47
    property real startAngleDeg: -90
    property real gravityBiasDeg: 42

    property real chevronSize: 22
    property real strokeWidth: 4.5
    property real strokeBoost: 2.0
    property real tailSpacingPhase: 0.024
    property real tailGamma: 1.35
    property color onColor: "#52FFE1"
    property bool simplified: false

    property real headPhase: 0.0

    function wrap01(v) {
        var wrapped = v % 1.0
        return wrapped < 0 ? wrapped + 1.0 : wrapped
    }

    function directionSign() {
        return root.side === "left" ? -1.0 : 1.0
    }

    function phaseForIndex(index) {
        return wrap01(root.headPhase - index * root.tailSpacingPhase)
    }

    function angleDegForPhase(phase) {
        var wrapped = wrap01(phase)
        var travelDeg = wrapped * 360.0 - root.gravityBiasDeg * Math.sin(wrapped * Math.PI * 2.0)
        return root.startAngleDeg + directionSign() * travelDeg
    }

    function alphaForIndex(index) {
        if (!root.active)
            return 0.0

        var tailT = (root.chevrons <= 1) ? 0.0 : (index / (root.chevrons - 1.0))
        return Math.pow(Math.max(0.0, 1.0 - tailT), root.tailGamma)
    }

    NumberAnimation on headPhase {
        running: root.active
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
            readonly property real tangentDeg: angleDeg + (root.directionSign() > 0 ? 90 : -90)
            readonly property real sizeScale: 0.84 + chevronAlpha * 0.32
            readonly property real lineWidth: root.strokeWidth + chevronAlpha * root.strokeBoost
            readonly property real centerPosX: root.centerX + Math.cos(angleRad) * root.orbitRadius
            readonly property real centerPosY: root.centerY + Math.sin(angleRad) * root.orbitRadius

            visible: root.active && chevronAlpha > 0.01
            opacity: 0.12 + chevronAlpha * 0.88
            width: root.chevronSize * 1.5
            height: root.chevronSize * 1.5
            x: centerPosX - width / 2
            y: centerPosY - height / 2
            rotation: tangentDeg
            scale: sizeScale
            antialiasing: true
            layer.enabled: true
            layer.smooth: true

            Shape {
                anchors.fill: parent
                antialiasing: true
                visible: !root.simplified
                opacity: chevron.chevronAlpha * 0.26

                ShapePath {
                    strokeColor: root.onColor
                    strokeWidth: chevron.lineWidth + 3.0
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: width * 0.26
                    startY: height * 0.26

                    PathLine { x: width * 0.58; y: height * 0.50 }
                    PathLine { x: width * 0.26; y: height * 0.74 }
                }
            }

            Shape {
                anchors.fill: parent
                antialiasing: true

                ShapePath {
                    strokeColor: Qt.rgba(root.onColor.r, root.onColor.g, root.onColor.b, 0.28 + chevron.chevronAlpha * 0.72)
                    strokeWidth: chevron.lineWidth
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    startX: width * 0.26
                    startY: height * 0.26

                    PathLine { x: width * 0.58; y: height * 0.50 }
                    PathLine { x: width * 0.26; y: height * 0.74 }
                }
            }
        }
    }
}
