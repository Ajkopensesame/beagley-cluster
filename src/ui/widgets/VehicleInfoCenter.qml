import "./vic"
import QtQuick 2.15

Item {
    id: root

    // Warning color helper
    VicWarningColors { id: warningColors }

    width: 240
    height: 240

    // Theme (pass PurplePearlTheme from Main/preview)
    property var theme: null

    // --- Inputs ---
    property string drivetrainMode: "2wd"    // "2wd" | "4wd"
    property bool transferLock: false

    // warnings
    property bool warnDoor: false
    property bool warnCharge: false
    property bool warnCheckEngine: false
    property bool warnAT: false
    property bool warnFuelLow: false
    property bool warnBrake: false   // park brake or brake fluid
    property bool warnOil: false     // oil pressure warning

    // --- Derived ---
    readonly property bool hasWarning:
        warnBrake || warnCharge || warnCheckEngine || warnAT || warnFuelLow || warnOil || warnDoor
    readonly property string driveText: transferLock ? "LOCK" : (drivetrainMode === "4wd" ? "4WD" : "2WD")

    // --- Motion tuning ---

    // ==========================
    // Warning queue + cycling
    // ==========================
    property var warningQueue: []
    property int warningIndex: 0
    readonly property int warningCount: warningQueue.length

    // Display label (what user sees)
    readonly property string currentWarningText:
        (warningCount > 0) ? warningQueue[warningIndex % warningCount] : ""

    // Stable key (what halo colors should follow)
    readonly property string currentWarningKey: {
        // Build the same warning queue locally (no shared scope)
        var q = []
        if (warnBrake)       q.push("BRAKE")
        if (warnCharge)      q.push("CHARGE")
        if (warnCheckEngine) q.push("CHECK")
        if (warnAT)          q.push("A/T")
        if (warnFuelLow)     q.push("FUEL")
        if (warnOil)         q.push("OIL")
        if (warnDoor)        q.push("DOOR")

        if (q.length === 0) return ""

        var i = Math.max(0, Math.min(root.warningIndex, q.length - 1))

        switch (q[i]) {
        case "BRAKE":  return "brake"
        case "CHARGE": return "charge"
        case "CHECK":  return "check"
        case "A/T":    return "at"
        case "FUEL":   return "fuel"
        case "OIL":    return "oil"
        case "DOOR":   return "door"
        default:       return ""
        }
    }

    function rebuildWarningQueue() {
        var q = []
        // Order = priority (edit anytime)
        if (warnBrake)       q.push("BRAKE")
        if (warnCharge)      q.push("CHARGE")
        if (warnCheckEngine) q.push("CHECK")
        if (warnAT)          q.push("A/T")
        if (warnFuelLow)     q.push("FUEL")
        if (warnOil)         q.push("OIL")
        if (warnDoor)        q.push("DOOR")

        warningQueue = q

        if (warningQueue.length === 0) {
            warningIndex = 0
        } else if (warningIndex >= warningQueue.length) {
            warningIndex = 0
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

    // Force halo repaint when the *displayed* warning changes
    onWarningIndexChanged: halo.requestPaint()
    onCurrentWarningTextChanged: halo.requestPaint()
    property int fast: 160
    property int slow: 900

    // --- Theme-safe helpers ---
    function cOr(fallback, v) { return (v !== undefined && v !== null) ? v : fallback }
    readonly property color tBg:     cOr("#000000", theme ? theme.bg : undefined)
    readonly property color tPanel:  cOr("#0B0714", theme ? theme.panel : undefined)
    readonly property color tText:   cOr("#E6FFFFFF", theme ? theme.text : undefined)
    readonly property color tLow:    cOr("#C7B7FF", theme ? theme.pearlLow : undefined)
    readonly property color tHigh:   cOr("#5E35B1", theme ? theme.pearlHigh : undefined)
    readonly property color tDanger: cOr("#FF3B3B", theme ? theme.danger : undefined)

    readonly property string fontDisplay: cOr("Menlo", theme ? theme.fontDisplay : undefined)
    readonly property string fontAccent:  cOr("Menlo", theme ? theme.fontAccent : undefined)
    readonly property string fontMono:    cOr("Menlo", theme ? theme.fontMono : undefined)

    // --- Geometry ---
    readonly property real s: Math.min(width, height)
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // Halo sizing
    readonly property real haloRadius: s * 0.40
        readonly property real haloThickness: Math.max(2, s * 0.018)
    readonly property real haloInner: Math.max(8, haloRadius - haloThickness * 0.9 - s * 0.030)

    // ================
    // HALO (background)
    // ================
    Canvas {
        id: halo
        anchors.fill: parent
        antialiasing: true

        // animate warning pulse via this
        property real pulse: 0.0

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var r = root.haloRadius
            var rIn  = root.haloInner
            var lineW = root.haloThickness
                        
            // Colors
            var low = root.tLow
            var high = root.tHigh
            var danger = root.tDanger            // Pick ring color set
            var isWarn = root.hasWarning

            var low = root.tLow
            var high = root.tHigh
            var danger = root.tDanger

            var baseA
            var baseB

            if (isWarn) {
                var wcol = warningColors.haloColor(root.currentWarningKey, danger)
                baseA = Qt.rgba(wcol.r, wcol.g, wcol.b, 0.95)
                baseB = Qt.rgba(wcol.r * 0.92, wcol.g * 0.92, wcol.b * 0.92, 0.95)
            } else {
                baseA = low
                baseB = high
            }

            // Soft glow
            ctx.save()
            ctx.beginPath()
            ctx.arc(root.cx, root.cy, r, 0, Math.PI * 2, false)
            ctx.strokeStyle = Qt.rgba(baseB.r, baseB.g, baseB.b, isWarn ? 0.22 : 0.18)
            ctx.lineWidth = lineW + (isWarn ? (2 + halo.pulse * 2) : 2)
            ctx.lineCap = "round"
            ctx.stroke()
            ctx.restore()

            // Main halo stroke (gradient sweep)
            ctx.save()
            var grad = ctx.createLinearGradient(root.cx - r, root.cy, root.cx + r, root.cy)
            grad.addColorStop(0.00, Qt.rgba(baseA.r, baseA.g, baseA.b, 0.95))
            grad.addColorStop(0.50, Qt.rgba(baseB.r, baseB.g, baseB.b, 0.95))
            grad.addColorStop(1.00, Qt.rgba(baseA.r, baseA.g, baseA.b, 0.95))

            ctx.beginPath()
            ctx.arc(root.cx, root.cy, r, 0, Math.PI * 2, false)
            ctx.strokeStyle = grad
            ctx.lineWidth = lineW
            ctx.lineCap = "round"
            ctx.stroke()
            ctx.restore()
            // Tiny tick accents around halo (subtle)
            ctx.save()
            ctx.translate(root.cx, root.cy)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, isWarn ? 0.22 : 0.10)
            ctx.lineWidth = 1
            for (var i = 0; i < 12; i++) {
                ctx.save()
                ctx.rotate(i * (Math.PI * 2 / 12.0))
                ctx.beginPath()
                ctx.moveTo(r + 4, 0)
                ctx.lineTo(r + 8, 0)
                ctx.stroke()
                ctx.restore()
            }
            ctx.restore()
        }

        // repaint triggers
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    // Pulse only when warning is active (no cheap blinking)
    SequentialAnimation {
        id: warnPulse
        running: root.hasWarning
        loops: Animation.Infinite
        NumberAnimation { target: halo; property: "pulse"; from: 0.0; to: 1.0; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: halo; property: "pulse"; from: 1.0; to: 0.0; duration: 540; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 220 }
        onRunningChanged: halo.requestPaint()
        onStopped: { halo.pulse = 0.0; halo.requestPaint() }
    }

    // Keep canvas updated on state changes
    onHasWarningChanged: halo.requestPaint()
    onDrivetrainModeChanged: halo.requestPaint()
    onTransferLockChanged: halo.requestPaint()

    // ========================
    // CENTER CONTENT (inside)
    // ========================
    Item {
        id: center
        anchors.centerIn: parent
        width: root.haloInner * 2 * 0.92
        height: width

        // soft panel in center
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: width / 2
            color: root.tPanel
            opacity: root.hasWarning ? 0.14 : 0.18
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, root.hasWarning ? 0.08 : 0.10)
        }

        // NORMAL MODE (drivetrain)
        Item {
            id: normalLayer
            anchors.fill: parent
            opacity: root.hasWarning ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: root.fast } }

            // “mechanical bars” instead of boring text
            Column {
                id: bars
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Repeater {
                    model: (root.drivetrainMode === "4wd") ? 2 : 1
                    Rectangle {
                        width: parent.width * 0.46
                        height: 7
                        radius: 3.5
                        color: root.tHigh
                        opacity: 0.90
                    }
                }

                Rectangle {
                    visible: root.transferLock
                    width: parent.width * 0.30
                    height: 5
                    radius: 2.5
                    color: root.tLow
                    opacity: 0.90
                }
            }

            Text {
                
                id: driveTextLabel
anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: bars.bottom
                anchors.topMargin: 14
                text: root.driveText
                color: Qt.rgba(root.tText.r, root.tText.g, root.tText.b, 0.92)
                font.family: root.fontAccent
                font.pixelSize: 24
                font.bold: true
                font.letterSpacing: 3
            }

            // Lock “breath” (subtle)
            SequentialAnimation on scale {
                running: root.transferLock && !root.hasWarning
                loops: Animation.Infinite
                NumberAnimation { to: 1.03; duration: root.slow; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.00; duration: root.slow; easing.type: Easing.InOutSine }
            }
        }

        // WARNING MODE (dominant)
        Item {
            id: warningLayer
            anchors.fill: parent
            opacity: root.hasWarning ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.fast } }

            // Warning (ICON + small text)

            
Column {
    id: warnText
    anchors.centerIn: parent
    spacing: 8

    // ---- CHECK (top) ----
    Text {
        visible: root.currentWarningKey === "check"
        width: parent.width
        text: "CHECK"
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        font.family: root.fontAccent
        font.pixelSize: 17
        font.bold: true
        font.letterSpacing: 4
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.96
    }

    // ---- AUTO (top) ----
    Text {
        visible: root.currentWarningKey === "at"
        width: parent.width
        text: "AUTO"
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        font.family: root.fontAccent
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 3
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.96
    }

    // ---- ICON ----
    VicWarningIcon {
        id: warnIcon
        warningKey: root.currentWarningKey
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        width: 76
        height: 76
    }

    // ---- ENGINE (bottom) ----
    Text {
        visible: root.currentWarningKey === "check"
        width: parent.width
        text: "ENGINE"
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        font.family: root.fontAccent
        font.pixelSize: 17
        font.bold: true
        font.letterSpacing: 4
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.96
    }

    // ---- TRANS (bottom) ----
    Text {
        visible: root.currentWarningKey === "at"
        width: parent.width
        text: "TRANS"
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        font.family: root.fontAccent
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 3
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.96
    }

    // ---- Generic label (everything else) ----
    Text {
        visible: root.currentWarningKey !== "check"
              && root.currentWarningKey !== "at"
        width: parent.width
        text: root.currentWarningText
        color: warningColors.haloColor(root.currentWarningKey, root.tDanger)
        font.family: root.fontAccent
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 3
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.96
    }
}

            
                // ---- Warning cycling (only when 2+ warnings are active) ----
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
                NumberAnimation { target: warnText; property: "opacity"; to: 0.0; duration: 130; easing.type: Easing.OutQuad }
                ScriptAction {
                    script: {
                        root.warningIndex = (root.warningIndex + 1) % Math.max(1, root.warningCount)
                        halo.requestPaint()
                    }
                }
                NumberAnimation { target: warnText; property: "opacity"; to: 1.0; duration: 170; easing.type: Easing.OutQuad }
            }


        }
    }

    // Small status line (always present, minimal)
    Text {
        visible: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        text: root.hasWarning ? "ATTENTION" : "STATUS"
        color: Qt.rgba(root.tText.r, root.tText.g, root.tText.b, root.hasWarning ? 0.65 : 0.45)
        font.family: root.fontMono
        font.pixelSize: 12
        font.letterSpacing: 3
    }
}
