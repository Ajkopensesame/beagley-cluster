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

    readonly property string fontUi: cOr("monospace", theme ? theme.fontMono : undefined)

    readonly property real s: Math.min(width, height)
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real haloRadius: s * 0.42
    readonly property real haloThickness: Math.max(4, s * 0.024)
    readonly property real haloInner: haloRadius - haloThickness - s * 0.036
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

    function warningTitle(key) {
        switch (key) {
        case "brake": return "BRAKE"
        case "charge": return "CHARGE"
        case "check": return "CHECK"
        case "at": return "A/T"
        case "fuel": return "LOW"
        case "oil": return "OIL"
        case "door": return "DOOR"
        default: return ""
        }
    }

    function warningSubtitle(key) {
        switch (key) {
        case "brake": return "SYSTEM"
        case "charge": return "VOLTAGE"
        case "check": return "ENGINE"
        case "at": return "TRANS"
        case "fuel": return "FUEL"
        case "oil": return "PRESSURE"
        case "door": return "OPEN"
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
        antialiasing: true
        renderTarget: Canvas.FramebufferObject
        property real pulse: 0.0

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const r = root.haloRadius
            const inner = root.haloInner
            const stroke = root.haloThickness
            const base = root.activeColor
            const glowAlpha = root.hasWarning ? 0.34 : 0.20

            if (root.simplified) {
                ctx.save()
                ctx.beginPath()
                ctx.arc(root.cx, root.cy, r, -Math.PI * 0.82, Math.PI * 1.18, false)
                ctx.strokeStyle = Qt.rgba(base.r, base.g, base.b, 0.82 + halo.pulse * 0.06)
                ctx.lineWidth = stroke
                ctx.lineCap = "round"
                ctx.stroke()
                ctx.restore()
                return
            }

            ctx.save()
            ctx.beginPath()
            ctx.arc(root.cx, root.cy, r, 0, Math.PI * 2, false)
            ctx.strokeStyle = Qt.rgba(base.r, base.g, base.b, glowAlpha + halo.pulse * 0.08)
            ctx.lineWidth = stroke + 8 + halo.pulse * 3
            ctx.lineCap = "round"
            ctx.stroke()
            ctx.restore()

            ctx.save()
            const grad = ctx.createLinearGradient(root.cx - r, root.cy - r, root.cx + r, root.cy + r)
            grad.addColorStop(0.0, Qt.rgba(root.tLow.r, root.tLow.g, root.tLow.b, 0.95))
            grad.addColorStop(0.55, Qt.rgba(base.r, base.g, base.b, 0.98))
            grad.addColorStop(1.0, Qt.rgba(root.tHigh.r, root.tHigh.g, root.tHigh.b, 0.92))
            ctx.beginPath()
            ctx.arc(root.cx, root.cy, r, -Math.PI * 0.82, Math.PI * 1.18, false)
            ctx.strokeStyle = grad
            ctx.lineWidth = stroke
            ctx.lineCap = "round"
            ctx.stroke()
            ctx.restore()

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
        width: root.haloInner * 2 * 0.98
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0.00; color: Qt.rgba(12 / 255, 18 / 255, 30 / 255, 0.98) }
                GradientStop { position: 0.55; color: Qt.rgba(8 / 255, 13 / 255, 21 / 255, 0.94) }
                GradientStop { position: 1.00; color: Qt.rgba(2 / 255, 4 / 255, 9 / 255, 0.98) }
            }
            border.width: 1
            border.color: Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, root.hasWarning ? 0.20 : 0.12)
        }

        Canvas {
            anchors.fill: parent
            visible: !root.simplified
            opacity: 0.32
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
                    width: 112
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
                    font.pixelSize: 20
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
            Behavior on opacity { NumberAnimation { duration: root.fast } }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 22
                text: root.warningTitle(root.currentWarningKey)
                color: root.activeColor
                font.family: root.fontUi
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 4
            }

            VicWarningIcon {
                id: warnIcon
                anchors.centerIn: parent
                width: 84
                height: 84
                warningKey: root.currentWarningKey
                color: root.activeColor
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                text: root.warningSubtitle(root.currentWarningKey)
                color: root.activeColor
                font.family: root.fontUi
                font.pixelSize: 20
                font.bold: true
                font.letterSpacing: 4
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 8

                Repeater {
                    model: root.warningCount
                    Rectangle {
                        width: index === root.warningIndex ? 20 : 8
                        height: 4
                        radius: 2
                        color: index === root.warningIndex
                            ? root.activeColor
                            : Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 0.22)
                    }
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
