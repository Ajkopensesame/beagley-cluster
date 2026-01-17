import QtQuick 2.15
import QtQuick.Shapes 1.15
import QtGraphicalEffects 1.15

Item {
    id: root
    width: 420
    height: 420

    // INPUT (mock or real later)
    property real speedKph: 0
    property real maxSpeed: 180

    readonly property real norm: Math.min(Math.max(speedKph / maxSpeed, 0), 1)

    // Geometry
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real outerRadius: width / 2 - 16
    readonly property real ringRadius: outerRadius - 14

    readonly property real startAngle: -225
    readonly property real sweepAngle: 270

    // Purple pearl theme
    readonly property color pearlBase: "#120A1D"
    readonly property color pearlBase2: "#1A0F2A"
    readonly property color pearlAccent: "#8F5BFF"
    readonly property color pearlGlow: "#D44BFF"

    // Cavern depth reacts to speed
    readonly property real cavernDepth: Qt.lerp(0.56, 0.38, norm)

    // ================= Cavern =================
    Rectangle {
        anchors.fill: parent
        radius: width / 2

        gradient: RadialGradient {
            centerX: cx
            centerY: cy
            centerRadius: width * cavernDepth
            GradientStop { position: 0.0; color: "#050309" }
            GradientStop { position: 0.6; color: pearlBase }
            GradientStop { position: 1.0; color: pearlBase2 }
        }
    }

    // ================= Base ring =================
    Shape {
        anchors.fill: parent
        ShapePath {
            strokeWidth: 12
            strokeColor: "#2B2633"
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: cx
                centerY: cy
                radiusX: ringRadius
                radiusY: ringRadius
                startAngle: startAngle
                sweepAngle: sweepAngle
            }
        }
    }

    // ================= Progress arc =================
    Shape {
        id: arc
        anchors.fill: parent
        ShapePath {
            strokeWidth: 16
            strokeColor: pearlAccent
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: cx
                centerY: cy
                radiusX: ringRadius
                radiusY: ringRadius
                startAngle: startAngle
                sweepAngle: sweepAngle * norm
            }
        }
    }

    // Glow (restrained)
    Glow {
        anchors.fill: arc
        source: arc
        radius: 14
        samples: 16
        color: Qt.rgba(0.83, 0.60, 1.0, 0.35)
        spread: 0.25
    }

    // ================= Speed text =================
    Text {
        anchors.centerIn: parent
        text: Math.round(speedKph)
        font.pixelSize: 96
        font.family: "Orbitron"
        color: "#F3EEFF"

        layer.enabled: true
        layer.effect: DropShadow {
            radius: 16
            verticalOffset: 8
            color: "#90000000"
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.verticalCenter
        anchors.topMargin: 42
        text: "km/h"
        font.pixelSize: 20
        font.family: "DejaVu Sans Mono"
        color: "#B9B1C7"
    }

    Behavior on speedKph {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
