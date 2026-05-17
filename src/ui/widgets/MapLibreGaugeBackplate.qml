import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property var theme
    property color primaryColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    property color auxColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    property real primaryProgress: 0
    property real auxProgress: 0
    property real maxValue: 140
    property real minorStep: 10
    property real majorStep: 20
    property real labelStep: 20
    property real labelStart: 20
    property real labelDivisor: 1
    property string auxStartLabel: ""
    property string auxEndLabel: ""
    property bool drawFaceBackground: true
    property bool showArcHeads: true
    property bool primaryScared: false
    property bool auxScared: false
    property bool matrixRainVisible: false
    property color matrixRainColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    property real matrixPhase: 0

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210
    readonly property real pathStartAngle: startAngleDeg - 90
    readonly property real arcRadius: width * 0.405
    readonly property real auxStartDeg: (startAngleDeg + sweepAngleDeg + 12) % 360
    readonly property real auxSweepDeg: 360 - sweepAngleDeg - 24
    readonly property real clampedPrimary: clamp(primaryProgress, 0, 1)
    readonly property real clampedAux: clamp(auxProgress, 0, 1)
    readonly property real primaryHeadDeg: startAngleDeg + sweepAngleDeg * clampedPrimary
    readonly property real auxHeadDeg: auxStartDeg + auxSweepDeg * (1.0 - clampedAux)
    readonly property real primaryHeadRadius: Math.max(17, width * 0.027)
    readonly property real auxHeadRadius: Math.max(15, width * 0.024)
    readonly property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    readonly property color textColor: theme?.text ?? Qt.color("#F7FBFF")

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, Number(v) || 0))
    }

    function angleRad(deg) {
        return (deg - 90) * Math.PI / 180.0
    }

    function pointX(deg, radius, itemWidth) {
        return width / 2 + Math.cos(angleRad(deg)) * radius - itemWidth / 2
    }

    function pointY(deg, radius, itemHeight) {
        return height / 2 + Math.sin(angleRad(deg)) * radius - itemHeight / 2
    }

    function labelForValue(value) {
        return String(Math.round(value / Math.max(1e-6, labelDivisor)))
    }

    function matrixGlyph(seed) {
        const glyphs = ["0", "1", "0", "1", "7", "K", "M", "R", "A", "N"]
        return glyphs[Math.abs(seed) % glyphs.length]
    }

    Timer {
        interval: 360
        running: root.matrixRainVisible
        repeat: true
        onTriggered: root.matrixPhase += 1
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.996
        height: width
        radius: width / 2
        visible: root.drawFaceBackground
        color: "#03060D"
        opacity: 0.96
        border.width: Math.max(2, width * 0.004)
        border.color: Qt.rgba(root.chromeColor.r, root.chromeColor.g, root.chromeColor.b, 0.16)
    }

    Item {
        anchors.fill: parent
        z: -1
        visible: root.matrixRainVisible
        opacity: 0.58

        Repeater {
            model: 72

            delegate: Text {
                readonly property int col: index % 9
                readonly property int row: Math.floor(index / 9)
                readonly property real phase: root.matrixPhase * 0.66 + index * 0.71
                readonly property real px: root.width * (0.18 + col * 0.078 + 0.010 * Math.sin(phase))
                readonly property real py: root.height * (0.18 + row * 0.078 + 0.006 * ((root.matrixPhase + col * 2) % 5))
                readonly property real dx: px - root.width / 2
                readonly property real dy: py - root.height / 2
                readonly property real maskR: root.width * 0.31

                visible: dx * dx + dy * dy < maskR * maskR
                x: px
                y: py
                width: 24
                height: 24
                text: root.matrixGlyph(index + Math.floor(root.matrixPhase))
                color: root.matrixRainColor
                opacity: 0.22 + 0.38 * (0.5 + 0.5 * Math.sin(phase))
                font.family: root.theme?.fontMono ?? "monospace"
                font.pixelSize: Math.max(15, root.width * 0.024)
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.chromeColor.r, root.chromeColor.g, root.chromeColor.b, 0.12)
            strokeWidth: Math.max(12, root.width * 0.024)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: root.pathStartAngle
                sweepAngle: root.sweepAngleDeg
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.chromeColor.r, root.chromeColor.g, root.chromeColor.b, 0.32)
            strokeWidth: Math.max(5, root.width * 0.010)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: root.pathStartAngle
                sweepAngle: root.sweepAngleDeg
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.primaryColor.r, root.primaryColor.g, root.primaryColor.b, 0.90)
            strokeWidth: Math.max(8, root.width * 0.015)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: root.pathStartAngle
                sweepAngle: root.sweepAngleDeg * root.clampedPrimary
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(root.auxColor.r, root.auxColor.g, root.auxColor.b, 0.82)
            strokeWidth: Math.max(7, root.width * 0.014)
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width * 0.36
                radiusY: root.width * 0.36
                startAngle: root.auxStartDeg - 90
                sweepAngle: root.auxSweepDeg * root.clampedAux
            }
        }
    }

    Repeater {
        model: Math.floor(root.maxValue / root.minorStep) + 1

        delegate: Rectangle {
            readonly property real value: index * root.minorStep
            readonly property bool major: Math.abs(value % root.majorStep) < 0.001
            readonly property real angle: root.startAngleDeg + root.sweepAngleDeg * (value / root.maxValue)
            width: major ? Math.max(4, root.width * 0.008) : Math.max(2, root.width * 0.004)
            height: major ? Math.max(22, root.width * 0.038) : Math.max(10, root.width * 0.018)
            radius: width / 2
            color: Qt.rgba(root.chromeColor.r, root.chromeColor.g, root.chromeColor.b, major ? 0.72 : 0.42)
            x: root.pointX(angle, root.width * 0.425 - height / 2, width)
            y: root.pointY(angle, root.width * 0.425 - height / 2, height)
            rotation: angle
            transformOrigin: Item.Center
        }
    }

    Repeater {
        model: Math.floor((root.maxValue - root.labelStart) / root.labelStep) + 1

        delegate: Text {
            readonly property real value: root.labelStart + index * root.labelStep
            readonly property real angle: root.startAngleDeg + root.sweepAngleDeg * (value / root.maxValue)
            width: 46
            height: 28
            x: root.pointX(angle, root.width * 0.325, width)
            y: root.pointY(angle, root.width * 0.325, height)
            text: root.labelForValue(value)
            color: root.textColor
            opacity: 0.78
            font.family: root.theme?.fontMono ?? "monospace"
            font.pixelSize: Math.max(14, root.width * 0.028)
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Text {
        width: 30
        height: 24
        x: root.pointX(root.auxStartDeg, root.width * 0.36 + 24, width)
        y: root.pointY(root.auxStartDeg, root.width * 0.36 + 24, height)
        text: root.auxStartLabel
        color: root.textColor
        opacity: 0.78
        font.family: root.theme?.fontMono ?? "monospace"
        font.pixelSize: Math.max(14, root.width * 0.025)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Text {
        width: 30
        height: 24
        x: root.pointX(root.auxStartDeg + root.auxSweepDeg, root.width * 0.36 + 24, width)
        y: root.pointY(root.auxStartDeg + root.auxSweepDeg, root.width * 0.36 + 24, height)
        text: root.auxEndLabel
        color: root.textColor
        opacity: 0.78
        font.family: root.theme?.fontMono ?? "monospace"
        font.pixelSize: Math.max(14, root.width * 0.025)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    GaugeArcHead {
        z: 90
        visible: root.showArcHeads && root.clampedPrimary > 0.002
        lowEffectMode: false
        scared: root.primaryScared
        headRadius: root.primaryHeadRadius
        x: root.pointX(root.primaryHeadDeg, root.arcRadius, width)
        y: root.pointY(root.primaryHeadDeg, root.arcRadius, height)
    }

    GaugeArcHead {
        z: 92
        visible: root.showArcHeads && root.clampedAux > 0.002
        lowEffectMode: false
        scared: root.auxScared
        headRadius: root.auxHeadRadius
        x: root.pointX(root.auxHeadDeg, root.width * 0.36, width)
        y: root.pointY(root.auxHeadDeg, root.width * 0.36, height)
    }
}
