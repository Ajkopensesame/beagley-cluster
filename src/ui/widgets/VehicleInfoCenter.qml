import "./vic"
import "./vic/icons" as Icons
import QtQuick 2.15

Item {
    id: root

    VicWarningColors { id: warningColors }

    width: 240
    height: 240

    property var theme: null
    property bool simplified: false
    property bool pulseEnabled: true

    property string drivetrainMode: "2wd"
    property bool transferLock: false

    property bool warnDoor: false
    property bool warnCharge: false
    property bool warnCheckEngine: false
    property bool warnAT: false
    property bool warnFuelLow: false
    property bool warnBrake: false
    property bool warnOil: false

    readonly property bool hasWarning:
        warnBrake || warnCharge || warnCheckEngine || warnAT || warnFuelLow || warnOil || warnDoor

    readonly property string driveModeKey: {
        const mode = String(drivetrainMode || "2wd").toLowerCase()
        if (transferLock) return "lock"
        if (mode.indexOf("4") !== -1) return "4wd"
        return "2wd"
    }

    property var warningQueue: []
    property int warningIndex: 0
    readonly property int warningCount: warningQueue.length
    readonly property string currentWarningKey:
        warningCount > 0 ? warningQueue[warningIndex % warningCount] : ""

    property int fast: 160
    property int slow: 900

    function cOr(fallback, v) { return (v !== undefined && v !== null) ? v : fallback }
    readonly property color tPanel:  cOr("#0B0714", theme ? theme.panel : undefined)
    readonly property color tText:   cOr("#E6FFFFFF", theme ? theme.text : undefined)
    readonly property color tLow:    cOr("#C7B7FF", theme ? theme.pearlLow : undefined)
    readonly property color tHigh:   cOr("#5E35B1", theme ? theme.pearlHigh : undefined)
    readonly property color tDanger: cOr("#FF3B3B", theme ? theme.danger : undefined)
    readonly property color neonCyan: "#73F6FF"
    readonly property color neonViolet: "#9B5CFF"
    readonly property color neonPink: "#FF4DFF"
    readonly property color neonDeep: "#6E35FF"
    readonly property color neonPearl: "#EAD7FF"

    readonly property string fontUi: cOr("monospace", theme ? theme.fontMono : undefined)

    readonly property real s: Math.min(width, height)
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real haloRadius: s * 0.42
    readonly property real haloThickness: Math.max(5, s * 0.028)
    readonly property real haloInner: haloRadius - haloThickness - s * 0.032
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property color activeColor:
        hasWarning ? warningColors.haloColor(currentWarningKey, tDanger) : tLow
    readonly property color activeColorSoft:
        Qt.rgba(activeColor.r, activeColor.g, activeColor.b, hasWarning ? 0.28 : 0.18)

    function rebuildWarningQueue() {
        var q = []
        if (warnBrake) q.push("brake")
        if (warnCharge) q.push("charge")
        if (warnCheckEngine) q.push("check")
        if (warnAT) q.push("at")
        if (warnFuelLow) q.push("fuel")
        if (warnOil) q.push("oil")
        if (warnDoor) q.push("door")
        warningQueue = q
        if (warningQueue.length === 0 || warningIndex >= warningQueue.length)
            warningIndex = 0
    }

    function warningLabel(key) {
        switch (key) {
        case "brake": return "BRAKE"
        case "charge": return "BATTERY"
        case "check": return "CHECK ENG"
        case "at": return "A/T TEMP"
        case "fuel": return "LOW FUEL"
        case "oil": return "OIL PRESS"
        case "door": return "DOOR"
        default: return ""
        }
    }

    function normalSubtitle(key) {
        switch (key) {
        case "lock": return "LOCK"
        case "4wd": return "4WD"
        default: return "2WD"
        }
    }

    Component.onCompleted: rebuildWarningQueue()
    onWarnBrakeChanged: rebuildWarningQueue()
    onWarnChargeChanged: rebuildWarningQueue()
    onWarnCheckEngineChanged: rebuildWarningQueue()
    onWarnATChanged: rebuildWarningQueue()
    onWarnFuelLowChanged: rebuildWarningQueue()
    onWarnOilChanged: rebuildWarningQueue()
    onWarnDoorChanged: rebuildWarningQueue()
    onHasWarningChanged: halo.requestPaint()
    onCurrentWarningKeyChanged: halo.requestPaint()

    Canvas {
        id: halo
        anchors.fill: parent
        antialiasing: !root.simplified
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
        property real pulse: 0.0

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const r = root.haloRadius
            const stroke = root.haloThickness
            const warningPulse = root.hasWarning && root.pulseEnabled ? halo.pulse : 0.0
            const base = root.hasWarning ? root.activeColor : root.neonViolet
            const mainStart = -Math.PI * 0.86
            const mainEnd = Math.PI * 1.16

            function withAlpha(color, alpha) {
                return Qt.rgba(color.r, color.g, color.b, alpha)
            }

            function drawArc(from, to, widthPx, color, alpha) {
                ctx.save()
                ctx.beginPath()
                ctx.arc(root.cx, root.cy, r, from, to, false)
                ctx.strokeStyle = withAlpha(color, alpha)
                ctx.lineWidth = widthPx
                ctx.lineCap = "round"
                ctx.stroke()
                ctx.restore()
            }

            drawArc(mainStart, mainEnd, stroke * 1.58, root.neonDeep, root.simplified ? 0.22 : 0.28)
            drawArc(mainStart, mainEnd, stroke * 0.84, root.tLow, root.simplified ? 0.34 : 0.38)
            drawArc(mainStart, mainEnd, stroke * 0.50, base, root.simplified ? 0.68 : 0.86)

            if (!root.simplified) {
                drawArc(mainStart - 0.08, mainEnd + 0.08, stroke * 1.95 + warningPulse * 3.0, base, (root.hasWarning ? 0.22 : 0.10) + warningPulse * 0.14)

                const grad = ctx.createLinearGradient(root.cx - r, root.cy - r, root.cx + r, root.cy + r)
                grad.addColorStop(0.0, withAlpha(root.neonCyan, 0.16))
                grad.addColorStop(0.38, withAlpha(base, 0.92))
                grad.addColorStop(0.72, withAlpha(root.neonPink, root.hasWarning ? 0.38 : 0.54))
                grad.addColorStop(1.0, withAlpha(root.neonPearl, 0.30))

                ctx.save()
                ctx.beginPath()
                ctx.arc(root.cx, root.cy, r, mainStart, mainEnd, false)
                ctx.strokeStyle = grad
                ctx.lineWidth = stroke * 0.82
                ctx.lineCap = "round"
                ctx.stroke()
                ctx.restore()

                drawArc(-Math.PI * 0.72, -Math.PI * 0.04, Math.max(1, stroke * 0.18), root.neonPearl, 0.36)
            }

        }
    }

    SequentialAnimation {
        id: warnPulse
        running: root.hasWarning && root.pulseEnabled
        loops: Animation.Infinite
        NumberAnimation { target: halo; property: "pulse"; from: 0.0; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: halo; property: "pulse"; from: 1.0; to: 0.0; duration: 520; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 180 }
        onRunningChanged: halo.requestPaint()
        onStopped: { halo.pulse = 0.0; halo.requestPaint() }
    }

    Item {
        id: center
        anchors.centerIn: parent
        width: root.haloInner * 2 * 1.02
        height: width
        layer.enabled: !root.embeddedSafeMode
        layer.smooth: !root.embeddedSafeMode

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(8 / 255, 10 / 255, 17 / 255, root.hasWarning ? 0.98 : 0.94) }
                GradientStop { position: 0.55; color: Qt.rgba(3 / 255, 5 / 255, 10 / 255, root.hasWarning ? 0.96 : 0.92) }
                GradientStop { position: 1.00; color: Qt.rgba(1 / 255, 2 / 255, 6 / 255, root.hasWarning ? 0.99 : 0.95) }
            }
            border.width: Math.max(2, width * 0.012)
            border.color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, root.hasWarning ? 0.52 : 0.28)
        }

        Canvas {
            anchors.fill: parent
            visible: false
            opacity: 0.0
            renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.08)
                ctx.lineWidth = 1
                for (let y = height * 0.16; y < height * 0.84; y += 10) {
                    ctx.beginPath()
                    ctx.moveTo(width * 0.22, y)
                    ctx.lineTo(width * 0.78, y)
                    ctx.stroke()
                }
            }
        }

        Item {
            id: normalLayer
            anchors.fill: parent
            opacity: root.hasWarning ? 0.0 : 1.0
            layer.enabled: !root.embeddedSafeMode
            layer.smooth: !root.embeddedSafeMode
            Behavior on opacity { NumberAnimation { duration: root.fast } }

            Column {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DRIVE"
                    color: Qt.rgba(root.tText.r, root.tText.g, root.tText.b, 0.78)
                    font.family: root.fontUi
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 4
                    horizontalAlignment: Text.AlignHCenter
                    width: 120
                }

                Icons.DriveStateIcon {
                    id: driveGlyph
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 118
                    height: width
                    color: root.tLow
                    mode: root.driveModeKey === "2wd" ? "2wd" : "4wd"
                    locked: root.driveModeKey === "lock"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.normalSubtitle(root.driveModeKey)
                    color: root.tLow
                    font.family: root.fontUi
                    font.pixelSize: 21
                    font.bold: true
                    font.letterSpacing: 4
                    horizontalAlignment: Text.AlignHCenter
                    width: 120
                }
            }
        }

        Item {
            id: warningLayer
            anchors.fill: parent
            opacity: root.hasWarning ? 1.0 : 0.0
            layer.enabled: !root.embeddedSafeMode
            layer.smooth: !root.embeddedSafeMode
            Behavior on opacity { NumberAnimation { duration: root.fast } }

            Column {
                id: warningStack
                width: parent.width
                anchors.centerIn: parent
                spacing: 7

                OemTellTaleIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(root.s * 0.48, warningLayer.width * 0.70)
                    height: width
                    icon: root.currentWarningKey
                    color: root.activeColor
                    accentColor: root.activeColor
                    cutoutColor: "#020409"
                    strokeWidth: Math.max(5, width * 0.056)
                }

                Text {
                    width: parent.width
                    text: root.warningLabel(root.currentWarningKey)
                    color: root.activeColor
                    font.family: root.fontUi
                    font.pixelSize: 20
                    font.bold: true
                    font.letterSpacing: 2
                    horizontalAlignment: Text.AlignHCenter
                    style: Text.Outline
                    styleColor: "#F0000000"
                }
            }

        }
    }

    Timer {
        id: warnCycle
        interval: 1300
        running: root.hasWarning && root.warningCount > 1
        repeat: true
        onTriggered: warnSwap.restart()
    }

    SequentialAnimation {
        id: warnSwap
        running: false
        NumberAnimation { target: warningLayer; property: "opacity"; to: 0.0; duration: 120; easing.type: Easing.OutQuad }
        ScriptAction {
            script: {
                root.warningIndex = (root.warningIndex + 1) % Math.max(1, root.warningCount)
                halo.requestPaint()
            }
        }
        NumberAnimation { target: warningLayer; property: "opacity"; to: 1.0; duration: 160; easing.type: Easing.OutQuad }
    }
}
