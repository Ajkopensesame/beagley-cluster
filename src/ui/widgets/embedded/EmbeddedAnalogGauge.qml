import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property real value: 0
    property real maxValue: 100
    property real dangerStart: maxValue * 1.1
    property real minorStep: 10
    property real majorStep: 20
    property real labelStep: majorStep
    property real labelDivisor: 1
    property string valueText: ""
    property string unitText: ""
    property string labelText: ""
    property string fontFamily: "sans-serif"
    property color accentColor: "#4CD9FF"
    property color dangerColor: "#E34848"
    property color trackColor: "#24435A"
    property color faceColor: "#071019"
    property color textColor: "white"
    property color mutedTextColor: "#7BA5C9"
    property int valueFontSize: 92
    property int unitFontSize: 22
    property int labelFontSize: 15
    property bool animate: true

    readonly property real startAngle: 144
    readonly property real sweepAngle: 252
    readonly property real clampedValue: clamp(value, 0, maxValue)
    readonly property real progress: clamp(displayValue / Math.max(1e-6, maxValue), 0, 1)
    readonly property real needleAngle: -126 + (sweepAngle * progress)
    readonly property color activeColor: displayValue >= dangerStart ? dangerColor : accentColor
    property real displayValue: 0

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, Number(v) || 0))
    }

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function labelFor(v) {
        return String(Math.round(v / Math.max(1e-6, labelDivisor)))
    }

    function primaryValueText() {
        return valueText.length > 0 ? valueText : String(Math.round(displayValue))
    }

    onClampedValueChanged: displayValue = clampedValue
    onAccentColorChanged: tickCanvas.requestPaint()
    onDangerColorChanged: tickCanvas.requestPaint()
    onTrackColorChanged: tickCanvas.requestPaint()
    onFaceColorChanged: tickCanvas.requestPaint()
    onMinorStepChanged: tickCanvas.requestPaint()
    onMajorStepChanged: tickCanvas.requestPaint()
    onLabelStepChanged: tickCanvas.requestPaint()
    onLabelDivisorChanged: tickCanvas.requestPaint()
    onFontFamilyChanged: tickCanvas.requestPaint()
    onWidthChanged: tickCanvas.requestPaint()
    onHeightChanged: tickCanvas.requestPaint()

    Component.onCompleted: {
        displayValue = clampedValue
        tickCanvas.requestPaint()
    }

    Behavior on displayValue {
        enabled: root.animate
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Canvas {
        id: tickCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        antialiasing: true
        smooth: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const side = Math.min(width, height)
            const cx = width / 2
            const cy = height / 2
            const radius = side * 0.43
            const startRad = root.startAngle * Math.PI / 180.0
            const sweepRad = root.sweepAngle * Math.PI / 180.0

            ctx.save()

            const face = ctx.createRadialGradient(cx, cy, side * 0.10, cx, cy, side * 0.48)
            face.addColorStop(0.0, root.withAlpha(root.faceColor, 0.92))
            face.addColorStop(0.70, root.withAlpha(root.faceColor, 0.98))
            face.addColorStop(1.0, "rgba(0,0,0,0.78)")
            ctx.fillStyle = face
            ctx.beginPath()
            ctx.arc(cx, cy, side * 0.485, 0, Math.PI * 2)
            ctx.fill()

            ctx.lineCap = "round"
            ctx.strokeStyle = "rgba(255,255,255,0.08)"
            ctx.lineWidth = Math.max(2, side * 0.006)
            ctx.beginPath()
            ctx.arc(cx, cy, side * 0.475, 0, Math.PI * 2)
            ctx.stroke()

            ctx.strokeStyle = root.withAlpha(root.trackColor, 0.72)
            for (let v = 0; v <= root.maxValue + 1e-6; v += root.minorStep) {
                const t = root.clamp(v / root.maxValue, 0, 1)
                const angle = startRad + sweepRad * t
                const isMajor = Math.abs(v % root.majorStep) < 1e-6
                const length = side * (isMajor ? 0.070 : 0.040)
                const inner = radius - length

                ctx.globalAlpha = isMajor ? 0.82 : 0.42
                ctx.lineWidth = Math.max(2, side * (isMajor ? 0.010 : 0.005))
                ctx.beginPath()
                ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
                ctx.lineTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius)
                ctx.stroke()
            }

            ctx.globalAlpha = 1.0
            ctx.fillStyle = root.withAlpha(root.mutedTextColor, 0.94)
            ctx.font = "700 " + root.labelFontSize + "px \"" + root.fontFamily + "\""
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"

            const labelRadius = radius - side * 0.115
            for (let label = 0; label <= root.maxValue + 1e-6; label += root.labelStep) {
                const lt = root.clamp(label / root.maxValue, 0, 1)
                const la = startRad + sweepRad * lt
                ctx.fillText(
                    root.labelFor(label),
                    cx + Math.cos(la) * labelRadius,
                    cy + Math.sin(la) * labelRadius
                )
            }

            ctx.restore()
        }
    }

    Shape {
        anchors.fill: parent

        ShapePath {
            strokeWidth: Math.max(16, Math.min(root.width, root.height) * 0.062)
            strokeColor: root.withAlpha(root.trackColor, 0.20)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) * 0.365
                radiusY: Math.min(root.width, root.height) * 0.365
                startAngle: root.startAngle
                sweepAngle: root.sweepAngle
            }
        }

        ShapePath {
            strokeWidth: Math.max(12, Math.min(root.width, root.height) * 0.045)
            strokeColor: root.withAlpha(root.activeColor, 0.22)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) * 0.365
                radiusY: Math.min(root.width, root.height) * 0.365
                startAngle: root.startAngle
                sweepAngle: root.sweepAngle * root.progress
            }
        }

        ShapePath {
            strokeWidth: Math.max(5, Math.min(root.width, root.height) * 0.016)
            strokeColor: root.activeColor
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) * 0.365
                radiusY: Math.min(root.width, root.height) * 0.365
                startAngle: root.startAngle
                sweepAngle: root.sweepAngle * root.progress
            }
        }
    }

    Item {
        id: needlePivot
        anchors.centerIn: parent
        width: 1
        height: 1
        rotation: root.needleAngle

        Rectangle {
            x: -Math.min(root.width, root.height) * 0.055
            y: -height / 2
            width: Math.min(root.width, root.height) * 0.335
            height: Math.max(5, Math.min(root.width, root.height) * 0.018)
            radius: height / 2
            color: root.activeColor
            opacity: 0.96
            antialiasing: true
        }

        Rectangle {
            x: Math.min(root.width, root.height) * 0.18
            y: -height / 2
            width: Math.min(root.width, root.height) * 0.08
            height: Math.max(2, Math.min(root.width, root.height) * 0.006)
            radius: height / 2
            color: "white"
            opacity: 0.36
            antialiasing: true
        }

        Behavior on rotation {
            enabled: root.animate
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        width: Math.min(parent.width, parent.height) * 0.108
        height: width
        radius: width / 2
        anchors.centerIn: parent
        color: "#06101A"
        border.width: Math.max(2, width * 0.11)
        border.color: root.activeColor
        antialiasing: true
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.min(parent.width, parent.height) * 0.052
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: root.valueFontSize
            font.weight: Font.Black
            text: root.primaryValueText()
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.mutedTextColor
            font.family: root.fontFamily
            font.pixelSize: root.unitFontSize
            font.bold: true
            text: root.unitText
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.withAlpha(root.activeColor, 0.92)
            font.family: root.fontFamily
            font.pixelSize: root.labelFontSize
            font.bold: true
            text: root.labelText
            visible: text.length > 0
        }
    }
}
