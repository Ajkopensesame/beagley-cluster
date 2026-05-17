import QtQuick 2.15

Item {
    id: root

    // ===== PRND21 helpers (local, safe) =====
    function normGear(g) {
        if (g === undefined || g === null) return "";
        return String(g).trim().toUpperCase();
    }

    function gearColorFor(g) {
        var t = root.theme; // may be undefined; handle safely
        var gg = normGear(g);

        // Theme fallbacks
        var pearlLow  = t ? t.pearlLow  : "#C7B7FF";
        var pearlHigh = t ? t.pearlHigh : "#5E35B1";
        var danger    = t ? t.danger    : "#FF3B3B";
        var textCol   = t ? t.text      : "white";

        if (gg === "R") return danger;             // Reverse: red (and flashing via opacity)
        if (gg === "N") return pearlLow;           // Neutral: light purple
        if (gg === "P") return pearlLow;           // Park: light purple
        if (gg === "D") return pearlLow;           // Drive: light purple
        if (gg === "2") return pearlLow;           // 2: light purple
        if (gg === "1") return pearlLow;           // 1: light purple
        if (gg === "L") return pearlLow;           // Low: light purple

        return textCol;
    }

    // =======================================
    width: 420
    height: 420

    // Theme from Main.qml
    property var theme
    property string effectLevel: "high"
    property string detailMode: "safe"
    property bool demoReadouts: false
    property bool matrixRainEnabled: true
    property real matrixRainSharedPhase: NaN
    property bool showArcHeads: true

    property var vehicleState
    property bool stressScene: false
    property real stressPhase: 0.0
    property bool simulationActive: false
    property real simulationPhase: 0.0
    // Public API
    property real speed: 0
    property real maxSpeed: 180

    // --- Coolant public API (°C) ---
    // For now this is a static default until we wire it from VehicleState in the next step.
    property real coolantC: 70

    // Tuning for coolant mapping (°C)
    property real coolantColdC: 40      // bottom-left "C"
    property real coolantHotC: 110      // top-right "H"

    // Smoothed value
    property real displaySpeed: 0

    // Smoothed coolant
    property real displayCoolantC: 70
    property real coolantResponse: 8.0
    property real coolantMaxStepPerFrame: 3.5

    // Tuning
    property real response: 10.0
    property real maxStepPerFrame: 10.0

    // Depth
    property real rimDepth: 1.0
    property bool overSpeed: speedInt >= 116

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
    function lerp(a, b, t) { return a + (b - a) * t; }
    function colorWithAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function blendToward(c, target, t, a) {
        return Qt.rgba(
            lerp(c.r, target.r, t),
            lerp(c.g, target.g, t),
            lerp(c.b, target.b, t),
            a
        );
    }
    function firstFinite(values) {
        for (var i = 0; i < values.length; i++) {
            var n = Number(values[i]);
            if (isFinite(n)) return n;
        }
        return NaN;
    }
    function liveOdometerKmValue() {
        if (!root.vehicleState) return NaN;

        var km = firstFinite([
            root.vehicleState.odometerKm,
            root.vehicleState.odoKm,
            root.vehicleState.mileageKm,
            root.vehicleState.totalKm,
            root.vehicleState.odometer
        ]);
        if (isFinite(km)) return km;

        var meters = firstFinite([
            root.vehicleState.odometerMeters,
            root.vehicleState.odoMeters,
            root.vehicleState.mileageMeters
        ]);
        return isFinite(meters) ? meters / 1000.0 : NaN;
    }
    function formatOdometerKm(v) {
        var s = String(Math.max(0, Math.round(Number(v) || 0)));
        var out = "";
        var count = 0;
        for (var i = s.length - 1; i >= 0; i--) {
            out = s.charAt(i) + out;
            count++;
            if (i > 0 && count % 3 === 0)
                out = " " + out;
        }
        return out;
    }
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property bool embeddedHighEffectBudgetMode: embeddedSafeMode && effectLevel === "high"
    readonly property bool richDetailMode: detailMode === "rich"
    readonly property bool cheapAuxArcMode: !richDetailMode
    readonly property bool auxArcAnimationEnabled: !cheapAuxArcMode && !embeddedSafeMode && !lowEffectMode
    readonly property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    readonly property real auxArcCanvasScale: embeddedHighEffectBudgetMode
        ? 1.0
        : ((lowEffectMode && !embeddedSafeMode) ? 0.44 : 1.0)
    readonly property real auxArcStrokeTune: auxArcCanvasScale < 1.0 ? auxArcCanvasScale : 1.0
    readonly property real sideArcHeadRadius: lowEffectMode ? 10.5 : (embeddedHighEffectBudgetMode ? 12.0 : 15.5)
    readonly property real speedRepaintThreshold: lowEffectMode ? 0.60 : (embeddedHighEffectBudgetMode ? 2.8 : 1e-4)
    readonly property real coolantRepaintThreshold: lowEffectMode ? 0.30 : (embeddedHighEffectBudgetMode ? 2.0 : 1e-4)
    property real lastPaintedSpeed: 0
    property real lastPaintedCoolantC: 70

    function requestGaugeStaticPaint() {
        dialChrome.requestStaticPaint();
    }
    function requestSpeedPaint() {
        const force = arguments.length > 0 && arguments[0] === true;
        dialChrome.requestDynamicPaint(force);
        root.lastPaintedSpeed = root.displaySpeed;
    }
    function requestCoolantPaint() {
        coolantArcCanvas.requestPaint();
        root.lastPaintedCoolantC = root.displayCoolantC;
    }
    function requestGaugeDynamicPaint() {
        const force = arguments.length > 0 && arguments[0] === true;
        requestSpeedPaint(force);
        requestCoolantPaint();
    }
    function kickSmoother() {
        if (!smoothingTimer.running) smoothingTimer.start();
    }

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)
    readonly property bool highSpeed: overSpeed
    readonly property bool speedHeadScared: displaySpeed > 115
    readonly property bool coolantHeadScared: displayCoolantC >= 100
    readonly property var stressGearSequence: ["P", "R", "N", "D", "2", "1", "L"]
    readonly property string displayGear: root.simulationActive
        ? stressGearSequence[Math.floor(root.simulationPhase / 0.9) % stressGearSequence.length]
        : (root.stressScene
        ? stressGearSequence[Math.floor(root.stressPhase / 1.05) % stressGearSequence.length]
        : (root.demoReadouts ? "D" : ((root.vehicleState && root.vehicleState.gear !== undefined) ? root.vehicleState.gear : "P")))
    readonly property bool displayOverdrive: root.simulationActive
        ? ((Math.floor(root.simulationPhase / 1.4) % 2) === 0)
        : (root.stressScene
        ? Math.sin(root.stressPhase * 0.95) > 0.0
        : (root.demoReadouts ? true : !!(root.vehicleState && root.vehicleState.overdrive === true)))
    readonly property real liveOdometerKm: liveOdometerKmValue()
    readonly property real displayOdometerKm: root.simulationActive
        ? 284613 + Math.floor(root.simulationPhase * 12)
        : (root.stressScene
        ? 284613 + Math.floor(root.stressPhase * 2.4)
        : (root.demoReadouts ? 284613 : liveOdometerKm))
    readonly property string odometerText: isFinite(displayOdometerKm)
        ? formatOdometerKm(displayOdometerKm)
        : "------"
    property real flashLevel: 0.0
    property real coolantLavaPhase: 0.0

    // Coolant normalized 0..1 (C -> H)
    readonly property real coolantNorm: clamp(
        (displayCoolantC - coolantColdC) / Math.max(1e-6, (coolantHotC - coolantColdC)),
        0, 1
    )
    readonly property real coolantVisualNorm: displayCoolantC < coolantColdC ? 0.14 : coolantNorm

    // Keep the dial geometry stable so the speed and tach arcs stay optically matched.
    readonly property real faceScale: 1.0
    readonly property real faceYOffset: 0
    readonly property real rainFaceRadius: width * 0.496

    function fallbackSpeedColor(v) {
        if (v <= 50)  return "#C7B7FF";
        if (v <= 115) return "#5E35B1";
        return "#FF3B3B";
    }

    readonly property color gaugeColor: (theme && theme.speedColor)
        ? theme.speedColor(displaySpeed)
        : fallbackSpeedColor(displaySpeed)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.72 : 0.42;
    }

    function coolantActiveColor(tempC) {
        const t = Number(tempC) || 0;
        const purple = theme?.pearlLow ?? Qt.color("#C7B7FF");
        const blue = Qt.color("#63C9FF");
        const red = theme?.danger ?? Qt.color("#FF3B3B");

        if (t < 40) return blue;
        if (t >= 100) return red;
        return purple;
    }

    // Smooth animation
    Timer {
        id: smoothingTimer
        interval: root.lowEffectMode ? 50 : 16
        running: false
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const prevSpeed = root.displaySpeed;
            const prevCoolant = root.displayCoolantC;

            // ---- Smooth speed ----
            const target = clamp(root.speed, 0, root.maxSpeed);
            const diff = target - root.displaySpeed;

            let step = diff * (1 - Math.exp(-root.response * dt));
            step = clamp(step, -root.maxStepPerFrame, root.maxStepPerFrame);
            root.displaySpeed += step;

            // ---- Smooth coolant ----
            const cTarget = root.coolantC;
            const cDiff = cTarget - root.displayCoolantC;

            let cStep = cDiff * (1 - Math.exp(-root.coolantResponse * dt));
            cStep = clamp(cStep, -root.coolantMaxStepPerFrame, root.coolantMaxStepPerFrame);
            root.displayCoolantC += cStep;

            const speedSettled = Math.abs(target - root.displaySpeed) < 0.02;
            const coolantSettled = Math.abs(cTarget - root.displayCoolantC) < 0.02;
            const speedChanged = Math.abs(root.displaySpeed - prevSpeed) > 1e-4;
            const coolantChanged = Math.abs(root.displayCoolantC - prevCoolant) > 1e-4;
            const speedNeedsRepaint = Math.abs(root.displaySpeed - root.lastPaintedSpeed) >= root.speedRepaintThreshold;
            const coolantNeedsRepaint = Math.abs(root.displayCoolantC - root.lastPaintedCoolantC) >= root.coolantRepaintThreshold;
            const speedSettledFlush = speedSettled && Math.abs(root.displaySpeed - root.lastPaintedSpeed) > 1e-4;
            const coolantSettledFlush = coolantSettled && Math.abs(root.displayCoolantC - root.lastPaintedCoolantC) > 1e-4;

            if (speedChanged && (speedNeedsRepaint || speedSettledFlush)) requestSpeedPaint();
            if (coolantChanged && (coolantNeedsRepaint || coolantSettledFlush)) requestCoolantPaint();
            if (speedSettled && coolantSettled) running = false;
        }
    }

    Timer {
        interval: root.lowEffectMode ? 120 : (root.embeddedHighEffectBudgetMode ? 300 : 42)
        running: root.effectLevel !== "off" && root.auxArcAnimationEnabled
        repeat: true
        onTriggered: {
            root.coolantLavaPhase += interval / 1000.0
            coolantArcCanvas.requestPaint()
        }
    }

    onSpeedChanged: kickSmoother()
    onCoolantCChanged: kickSmoother()
    onMaxSpeedChanged: kickSmoother()
    onThemeChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint(true)
    }
    onWidthChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint(true)
    }
    onHeightChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint(true)
    }
    onLowEffectModeChanged: {
        requestGaugeDynamicPaint(true)
        kickSmoother()
    }

    Component.onCompleted: {
        displaySpeed = clamp(speed, 0, maxSpeed)
        displayCoolantC = coolantC
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint(true)
        kickSmoother()
    }

    SequentialAnimation {
        id: redlinePulse
        running: root.highSpeed
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "flashLevel"; from: 0.10; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "flashLevel"; from: 1.0; to: 0.16; duration: 190; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 80 }
        onStopped: root.flashLevel = 0.0
    }

    // ===== Gauge face =====
    Item {
        anchors.fill: parent
        z: 30
        scale: root.faceScale
        y: root.faceYOffset

        Canvas {
            id: rainFaceBg
            anchors.fill: parent
            z: 1
            renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
            antialiasing: !root.lowEffectMode
            smooth: !root.lowEffectMode

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cx = width / 2
                const cy = height / 2
                const r = root.rainFaceRadius
                const pearl = root.theme?.pearlLow ?? Qt.color("#C7B7FF")
                const deep = root.theme?.pearlHigh ?? Qt.color("#5E35B1")

                function rgba(c, alpha) {
                    return "rgba("
                        + Math.round(c.r * 255) + ","
                        + Math.round(c.g * 255) + ","
                        + Math.round(c.b * 255) + ","
                        + alpha + ")"
                }

                const face = ctx.createRadialGradient(cx, cy, r * 0.08, cx, cy, r)
                face.addColorStop(0.00, "rgba(4,5,10,1.00)")
                face.addColorStop(0.58, "rgba(4,5,11,0.99)")
                face.addColorStop(0.86, "rgba(2,3,8,1.00)")
                face.addColorStop(0.96, rgba(pearl, 0.035))
                face.addColorStop(1.00, "rgba(0,0,0,1.00)")

                ctx.fillStyle = face
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.fill()

                ctx.beginPath()
                ctx.strokeStyle = rgba(pearl, 0.16)
                ctx.lineWidth = Math.max(2, width * 0.004)
                ctx.arc(cx, cy, r - ctx.lineWidth, 0, Math.PI * 2)
                ctx.stroke()
            }
        }

        MatrixRain {
            anchors.fill: parent
            z: 2
            visible: root.matrixRainEnabled && root.effectLevel !== "off"
            circularMask: true
            maskRadius: root.rainFaceRadius
            effectEnabled: visible
            effectLevel: root.effectLevel
            sharedPhase: root.matrixRainSharedPhase
            rainColor: root.blendToward(
                root.gaugeColor,
                root.theme?.pearlLow ?? Qt.color("#C7B7FF"),
                0.42,
                0.98
            )
            glowColor: root.blendToward(
                root.theme?.pearlLow ?? Qt.color("#C7B7FF"),
                Qt.color("#FFFFFF"),
                0.34,
                0.96
            )
            fps: root.embeddedSafeMode ? 2.0 : (root.lowEffectMode ? 7 : 12)
            speedMultiplier: root.embeddedSafeMode ? 0.18 : (root.lowEffectMode ? 0.11 : 0.20)
            density: root.embeddedSafeMode ? 0.76 : (root.lowEffectMode ? 0.15 : 0.30)
            glowSpeed: root.embeddedSafeMode ? 0.82 : (root.lowEffectMode ? 0.58 : 0.72)
            glowFloor: root.embeddedSafeMode ? 0.18 : (root.lowEffectMode ? 0.22 : 0.28)
            glowBlur: root.embeddedSafeMode ? 6.5 : 7.0
            driftScale: root.embeddedSafeMode ? 0.86 : 0.90
            charChangeChance: root.embeddedSafeMode ? 0.014 : (root.lowEffectMode ? 0.032 : 0.026)
            fontPx: root.embeddedSafeMode ? 14 : (root.lowEffectMode ? 18 : 12)
            fadeAlpha: root.embeddedSafeMode ? 0.030 : (root.lowEffectMode ? 0.075 : 0.024)
            tailLength: root.embeddedSafeMode ? 34 : (root.lowEffectMode ? 12 : 48)
            headAlpha: root.embeddedSafeMode ? 0.90 : (root.lowEffectMode ? 0.74 : 0.92)
            tailMinAlpha: root.embeddedSafeMode ? 0.070 : (root.lowEffectMode ? 0.025 : 0.12)
        }

        DialChrome {
            id: dialChrome
            anchors.fill: parent
            z: 20
            theme: root.theme
            effectLevel: root.effectLevel
            detailMode: root.detailMode
            gaugeColor: root.gaugeColor
            chromeColor: root.chromeColor
            progress: root.progress
            scaredHead: root.speedHeadScared
            showArcHead: root.showArcHeads
            maxValue: root.maxSpeed
            startAngleDeg: root.startAngleDeg
            sweepAngleDeg: root.sweepAngleDeg
            minorStep: 10
            majorStep: 20
            labelStep: 20
            labelStart: 20
            labelDivisor: 1
        }

        // ---- Coolant arc (cheap static band, opposite speed sweep) ----
        Item {
            id: coolantArcLayer
            anchors.fill: parent
            z: 44

            readonly property real rawStartDeg: (root.startAngleDeg + root.sweepAngleDeg) % 360
            readonly property real rawSweepDeg: 360 - root.sweepAngleDeg
            readonly property real padDeg: 12
            readonly property real startDeg: rawStartDeg + padDeg
            readonly property real sweepDeg: Math.max(0, rawSweepDeg - padDeg * 2)
            readonly property real fillStartNorm: 1.0 - root.coolantVisualNorm
            readonly property real radius: width * 0.36
            readonly property real labelRadius: radius + 18
            readonly property color baseDark: root.theme?.pearlHigh ?? root.gaugeColor
            readonly property color coolantColor: root.coolantActiveColor(root.displayCoolantC)
            readonly property color coolantBright: root.blendToward(coolantColor, Qt.color("#FFFFFF"), 0.20, 1.0)
            readonly property real sweepRad: sweepDeg * Math.PI / 180
            readonly property real headAngleRad: angleRad(startDeg) + sweepRad * fillStartNorm
            readonly property bool headVisible: root.coolantVisualNorm > 0.002
            readonly property real headCenterX: width / 2 + Math.cos(headAngleRad) * radius
            readonly property real headCenterY: height / 2 + Math.sin(headAngleRad) * radius

            function angleRad(deg) {
                return (deg - 90) * Math.PI / 180
            }

            function pointX(deg, radius, itemWidth) {
                return width / 2 + Math.cos(angleRad(deg)) * radius - itemWidth / 2
            }

            function pointY(deg, radius, itemHeight) {
                return height / 2 + Math.sin(angleRad(deg)) * radius - itemHeight / 2
            }

            Canvas {
                id: coolantArcCanvas
                anchors.centerIn: parent
                width: parent.width * root.auxArcCanvasScale
                height: parent.height * root.auxArcCanvasScale
                scale: root.auxArcCanvasScale < 1.0 ? (1.0 / root.auxArcCanvasScale) : 1.0
                renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
                antialiasing: !root.lowEffectMode
                smooth: !root.lowEffectMode

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const cx = width / 2
                    const cy = height / 2
                    const r = width * 0.36
                    const startRad = coolantArcLayer.angleRad(coolantArcLayer.startDeg)
                    const sweepRad = coolantArcLayer.sweepDeg * Math.PI / 180
                    const tailT = 1.0
                    const headT = coolantArcLayer.fillStartNorm
                    const coolant = coolantArcLayer.coolantColor
                    const bright = coolantArcLayer.coolantBright

                    function rgba(color, alpha) {
                        return "rgba("
                            + Math.round(color.r * 255) + ","
                            + Math.round(color.g * 255) + ","
                            + Math.round(color.b * 255) + ","
                            + alpha + ")"
                    }

                    const neonCyan = Qt.color("#73F6FF")
                    const neonLime = Qt.color("#9B5CFF")
                    const neonPink = Qt.color("#FF4DFF")
                    const neonOrange = Qt.color("#6E35FF")
                    const neonYellow = Qt.color("#EAD7FF")
                    const coldMode = root.displayCoolantC < root.coolantColdC
                    const hotMode = root.displayCoolantC >= 100
                    const lava0 = coldMode ? Qt.color("#63C9FF") : (hotMode ? Qt.color("#FF3B3B") : neonCyan)
                    const lava1 = coldMode ? Qt.color("#C9F7FF") : (hotMode ? Qt.color("#FF4D6D") : neonPink)
                    const lava2 = coldMode ? Qt.color("#73F6FF") : (hotMode ? Qt.color("#FF7A4A") : neonLime)
                    const lava3 = coldMode ? Qt.color("#E7FCFF") : (hotMode ? Qt.color("#FFD1CF") : neonYellow)

                    function pointForT(t, radialOffset) {
                        const a = startRad + sweepRad * t
                        return {
                            x: cx + Math.cos(a) * (r + radialOffset),
                            y: cy + Math.sin(a) * (r + radialOffset),
                            a: a
                        }
                    }

                    function buildBandPath(fromT, toT, tailWidth, headWidth) {
                        const outer = []
                        const inner = []
                        const steps = Math.max(10, Math.ceil(Math.abs(toT - fromT) * (root.embeddedHighEffectBudgetMode ? 24 : 56)))
                        for (let i = 0; i <= steps; i++) {
                            const u = i / steps
                            const eased = 1 - Math.pow(1 - u, 1.45)
                            const t = fromT + (toT - fromT) * u
                            const w = tailWidth + (headWidth - tailWidth) * eased
                            outer.push(pointForT(t, w / 2))
                            inner.push(pointForT(t, -w / 2))
                        }

                        ctx.beginPath()
                        ctx.moveTo(outer[0].x, outer[0].y)
                        for (let i = 1; i < outer.length; i++) ctx.lineTo(outer[i].x, outer[i].y)
                        for (let i = inner.length - 1; i >= 0; i--) ctx.lineTo(inner[i].x, inner[i].y)
                        ctx.closePath()

                        const tail = pointForT(fromT, 0)
                        const head = pointForT(toT, 0)
                        ctx.moveTo(tail.x + tailWidth * 0.45, tail.y)
                        ctx.arc(tail.x, tail.y, Math.max(2, tailWidth * 0.48), 0, Math.PI * 2)
                        ctx.moveTo(head.x + headWidth * 0.52, head.y)
                        ctx.arc(head.x, head.y, Math.max(3, headWidth * 0.52), 0, Math.PI * 2)
                    }

                    function drawBlob(t, radialOffset, radius, color, alpha, stretch, phase) {
                        const p = pointForT(t, radialOffset)
                        const grad = ctx.createRadialGradient(0, 0, radius * 0.12, 0, 0, radius)
                        grad.addColorStop(0.00, rgba(root.blendToward(color, Qt.color("#FFFFFF"), 0.42, 1.0), alpha))
                        grad.addColorStop(0.62, rgba(color, alpha * 0.40))
                        grad.addColorStop(1.00, rgba(color, 0.0))

                        ctx.save()
                        ctx.translate(p.x, p.y)
                        ctx.rotate(p.a + Math.PI / 2 + Math.sin(phase) * 0.20)
                        ctx.scale(stretch, 0.62)
                        ctx.fillStyle = grad
                        ctx.beginPath()
                        ctx.arc(0, 0, radius, 0, Math.PI * 2)
                        ctx.fill()
                        ctx.restore()
                    }

                    ctx.save()
                    ctx.beginPath()
                    ctx.strokeStyle = rgba(coolantArcLayer.baseDark, root.lowEffectMode ? 0.10 : 0.08)
                    ctx.lineWidth = root.lowEffectMode ? (10 * root.auxArcCanvasScale) : (22 * root.auxArcStrokeTune)
                    ctx.lineCap = "round"
                    ctx.arc(cx, cy, r, startRad, startRad + sweepRad)
                    ctx.stroke()
                    ctx.restore()

                    if (root.cheapAuxArcMode) {
                        if (root.coolantVisualNorm > 0.002) {
                            const activeStart = startRad + sweepRad * headT
                            const activeEnd = startRad + sweepRad * tailT

                            ctx.save()
                            ctx.beginPath()
                            ctx.strokeStyle = rgba(coolant, root.lowEffectMode ? 0.76 : 0.82)
                            ctx.lineWidth = root.lowEffectMode ? (7 * root.auxArcCanvasScale) : (12 * root.auxArcStrokeTune)
                            ctx.lineCap = "round"
                            ctx.arc(cx, cy, r, activeStart, activeEnd)
                            ctx.stroke()
                            ctx.restore()

                            ctx.save()
                            ctx.beginPath()
                            ctx.strokeStyle = rgba(bright, root.lowEffectMode ? 0.22 : 0.26)
                            ctx.lineWidth = root.lowEffectMode ? (2.0 * root.auxArcCanvasScale) : (2.8 * root.auxArcStrokeTune)
                            ctx.lineCap = "round"
                            ctx.arc(cx, cy, r, activeStart, activeEnd)
                            ctx.stroke()
                            ctx.restore()
                        }

                        if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                            performanceMetrics.recordPaint("speedGauge.coolantArc")
                        return
                    }

                    if (root.coolantVisualNorm > 0.002) {
                        const tailWidth = root.lowEffectMode ? (3.5 * root.auxArcCanvasScale) : (5.5 * root.auxArcStrokeTune)
                        const headWidth = root.lowEffectMode ? (10 * root.auxArcCanvasScale) : (22 * root.auxArcStrokeTune)
                        const phase = root.coolantLavaPhase

                        if (root.lowEffectMode) {
                            ctx.save()
                            buildBandPath(tailT, headT, tailWidth, headWidth)
                            const fill = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r)
                            fill.addColorStop(0.00, rgba(lava0, 0.70))
                            fill.addColorStop(0.42, rgba(lava2, 0.80))
                            fill.addColorStop(0.76, rgba(bright, 0.68))
                            fill.addColorStop(1.00, rgba(lava3, 0.58))
                            ctx.fillStyle = fill
                            ctx.fill()
                            ctx.restore()

                            ctx.save()
                            buildBandPath(tailT, headT,
                                          1.6 * root.auxArcCanvasScale,
                                          4.8 * root.auxArcCanvasScale)
                            ctx.fillStyle = rgba(neonYellow, 0.22)
                            ctx.fill()
                            ctx.restore()
                        } else {
                            ctx.save()
                            buildBandPath(tailT, headT, tailWidth, headWidth)
                            ctx.clip()

                            const fill = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r)
                            fill.addColorStop(0.00, rgba(lava0, 0.54))
                            fill.addColorStop(0.24, rgba(lava1, 0.66))
                            fill.addColorStop(0.54, rgba(lava2, 0.76))
                            fill.addColorStop(0.78, rgba(bright, 0.64))
                            fill.addColorStop(1.00, rgba(lava3, 0.52))
                            ctx.fillStyle = fill
                            ctx.fillRect(0, 0, width, height)

                            const blobCount = root.embeddedHighEffectBudgetMode ? 2 : 5
                            for (let i = 0; i < blobCount; i++) {
                                const blobColor = [lava0, lava1, lava2, bright, lava3][i % 5]
                                const u = (phase * (0.11 + i * 0.015) + i * 0.23) % 1.0
                                const t = tailT + (headT - tailT) * u
                                const wobble = Math.sin(phase * (1.1 + i * 0.2) + i * 1.7)
                                const blobR = (root.embeddedHighEffectBudgetMode ? (7 + i * 1.1) : (11 + i * 1.7)) * root.auxArcStrokeTune
                                drawBlob(t, wobble * 2.4, blobR, blobColor, 0.56, 1.55, phase + i)
                            }
                            ctx.restore()

                            ctx.save()
                            buildBandPath(tailT, headT, tailWidth, headWidth)
                            ctx.fillStyle = rgba(neonYellow, 0.18)
                            ctx.fill()
                            ctx.restore()
                        }

                    }

                    if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                        performanceMetrics.recordPaint("speedGauge.coolantArc")
                }
            }

            GaugeArcHead {
                z: 48
                visible: root.showArcHeads && coolantArcLayer.headVisible
                lowEffectMode: root.lowEffectMode
                scared: root.coolantHeadScared
                headRadius: root.sideArcHeadRadius
                x: coolantArcLayer.headCenterX - width / 2
                y: coolantArcLayer.headCenterY - height / 2
            }

            Text {
                width: 24
                height: 20
                x: coolantArcLayer.pointX(coolantArcLayer.startDeg, coolantArcLayer.labelRadius, width)
                y: coolantArcLayer.pointY(coolantArcLayer.startDeg, coolantArcLayer.labelRadius, height)
                text: "H"
                color: root.theme?.text ?? "white"
                opacity: root.theme?.isNight ? 0.90 : 0.75
                font.family: root.theme?.fontMono ?? "monospace"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                width: 24
                height: 20
                x: coolantArcLayer.pointX(coolantArcLayer.startDeg + coolantArcLayer.sweepDeg,
                                           coolantArcLayer.labelRadius,
                                           width)
                y: coolantArcLayer.pointY(coolantArcLayer.startDeg + coolantArcLayer.sweepDeg,
                                           coolantArcLayer.labelRadius,
                                           height)
                text: "C"
                color: root.theme?.text ?? "white"
                opacity: root.theme?.isNight ? 0.90 : 0.75
                font.family: root.theme?.fontMono ?? "monospace"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Canvas {
        id: redlineFlash
        anchors.fill: parent
        z: 52
        visible: root.highSpeed
        opacity: root.flashLevel

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const rOuter = width * 0.46;
            const rInner = width * 0.24;

            const g = ctx.createRadialGradient(cx, cy, rInner, cx, cy, rOuter);
            g.addColorStop(0.0, "rgba(255,59,59,0.00)");
            g.addColorStop(0.58, "rgba(255,59,59,0.05)");
            g.addColorStop(0.82, "rgba(255,59,59,0.18)");
            g.addColorStop(1.0, "rgba(255,59,59,0.30)");

            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter, 0, Math.PI * 2);
            ctx.arc(cx, cy, rInner, 0, Math.PI * 2, true);
            ctx.fill("evenodd");
        }
    }

    // O/D indicator (Overdrive)
    
Item {
        id: odBadge
        z: 62
        readonly property bool active: root.displayOverdrive
        readonly property color odColor: (root.theme && root.theme.amber) ? root.theme.amber : "#FFC107"
        readonly property color odDimColor: Qt.rgba(odColor.r, odColor.g, odColor.b, 0.28)
        visible: active

        anchors.bottom: speedValueText.top
        anchors.bottomMargin: 12
        anchors.horizontalCenter: speedValueText.horizontalCenter

        // Size tuned to match PRND vibe but still "in your face"
        width: 170
        height: 60

        // Glass body
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: odBadge.active ? "#140A22" : "#100D16"
            border.width: 2
            border.color: odBadge.active ? odBadge.odColor : odBadge.odDimColor
            opacity: odBadge.active ? 0.94 : 0.46
        }

        // Outer glow (soft)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 14
            border.color: Qt.rgba(odBadge.odColor.r, odBadge.odColor.g, odBadge.odColor.b, odBadge.active ? 0.17 : 0.10)
            opacity: odBadge.active ? 1.0 : 0.20
        }

        // Inner highlight line (depth)
        Rectangle {
            x: 10
            y: 10
            width: parent.width - 20
            height: parent.height - 20
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: "#12FFFFFF"
        }

        // Text (crisp, intentional)
        Text {
            anchors.centerIn: parent
            text: "O/D"
            font.family: (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace"
            font.pixelSize: 36
            font.weight: Font.Bold
            font.letterSpacing: 4
            color: odBadge.odColor
            opacity: odBadge.active ? 1.0 : 0.30
        }

        // Micro-pulse so it feels alive (subtle)
        SequentialAnimation on scale {
            running: odBadge.active
            loops: Animation.Infinite
            NumberAnimation { from: 1.00; to: 1.04; duration: 420; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.04; to: 1.00; duration: 420; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 260 }
        }
    }
// Centre speed
    Text {
    id: speedValueText
        anchors.centerIn: parent
        z: 60
        text: root.speedInt
        font.pixelSize: 120
        font.family: (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace"
        font.letterSpacing: 1
        color: root.gaugeColor
    }


    // Gear indicator under speed
    Item {
        id: gearReadout
        z: 61
        anchors.top: speedValueText.bottom
        anchors.topMargin: 4
        anchors.horizontalCenter: speedValueText.horizontalCenter
        width: 96
        height: 58

        Text {
            id: gearText
            anchors.centerIn: parent

            text: root.displayGear

            font.pixelSize: 54
            font.family: (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace"
            font.weight: Font.Black
            font.letterSpacing: 2

            color: gearColorFor(text)
            style: Text.Outline
            styleColor: "#F0000000"
            opacity: 1.0

            SequentialAnimation on opacity {
                running: normGear(gearText.text) === "R"
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.20; duration: 220 }
                NumberAnimation { from: 0.20; to: 1.0; duration: 220 }
            }
        }
    }

    Item {
        id: odometerReadout
        z: 61
        anchors.top: gearReadout.bottom
        anchors.topMargin: -4
        anchors.horizontalCenter: gearReadout.horizontalCenter
        width: 230
        height: 46

        Column {
            anchors.centerIn: parent
            spacing: -2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.odometerText
                font.family: (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace"
                font.pixelSize: 22
                font.weight: Font.Bold
                font.letterSpacing: 0
                color: root.theme?.pearlLow ?? "#C7B7FF"
                horizontalAlignment: Text.AlignHCenter
                style: Text.Outline
                styleColor: "#F0000000"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "KM"
                font.family: (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace"
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0
                color: Qt.rgba(root.chromeColor.r, root.chromeColor.g, root.chromeColor.b, 0.62)
                horizontalAlignment: Text.AlignHCenter
                style: Text.Outline
                styleColor: "#D0000000"
            }
        }
    }

}
