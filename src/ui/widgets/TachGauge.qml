import QtQuick 2.15

Item {
    id: root
    width: 420
    height: 420

    // Pass the theme object in from Main.qml
    property var theme
    property string effectLevel: "high"
    property bool matrixRainEnabled: true
    property real matrixRainSharedPhase: NaN

    // Public API
    property real rpm: 0

    // Fuel (0..100) for center mini-gauge
    property real fuelPct: 100
    property real lowFuelPct: 12

    // Smoothed fuel
    property real displayFuel: 100
    property real fuelResponse: 10.0
    property real fuelMaxStepPerFrame: 6.0

    // Smoothed RPM
    property real displayRpm: 0

    // Limits
    property int maxScale: 8
    property int maxRpm: maxScale * 1000
    property int redlineStart: 5000

    // Smoothing
    property real response: 12.0
    property real maxStepPerFrame: 350.0

    // Depth controls
    property real rimDepth: 1.0

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    // ---- BBB vehicle truth source ----
    // NOTE: `vehicleState` is expected to be a context property provided by C++ (VehicleStateClient).
    // If it is missing, QML should fail loudly rather than invent data.
    property var vehicleState
    property bool stressScene: false
    property real stressPhase: 0.0

    // Defensive helper
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
    function mixColors(c1, c2, t, a) {
        return Qt.rgba(
            lerp(c1.r, c2.r, t),
            lerp(c1.g, c2.g, t),
            lerp(c1.b, c2.b, t),
            a
        );
    }
    function fuelActiveColor(level) {
        const l = clamp(level, 0, 1);
        const purple = theme?.pearlLow ?? Qt.color("#C7B7FF");
        const yellow = Qt.color("#FFD54A");
        const red = theme?.danger ?? Qt.color("#FF3B3B");

        if (l >= 0.25) return purple;

        const quarterTint = mixColors(purple, yellow, 0.35, 1.0);
        const t = 1.0 - (l / 0.25);
        return mixColors(quarterTint, red, t, 1.0);
    }
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property bool embeddedHighEffectBudgetMode: embeddedSafeMode && effectLevel === "high"
    readonly property bool cheapAuxArcMode: true
    readonly property bool auxArcAnimationEnabled: !cheapAuxArcMode && !embeddedSafeMode && !lowEffectMode
    readonly property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")
    readonly property real auxArcCanvasScale: embeddedHighEffectBudgetMode
        ? 1.0
        : ((lowEffectMode && !embeddedSafeMode) ? 0.44 : 1.0)
    readonly property real auxArcStrokeTune: auxArcCanvasScale < 1.0 ? auxArcCanvasScale : 1.0
    readonly property real sideArcHeadRadius: lowEffectMode ? 10.5 : (embeddedHighEffectBudgetMode ? 12.0 : 15.5)
    readonly property real rpmRepaintThreshold: lowEffectMode ? 35.0 : (embeddedHighEffectBudgetMode ? 260.0 : 1e-4)
    readonly property real fuelRepaintThreshold: lowEffectMode ? 0.30 : (embeddedHighEffectBudgetMode ? 2.0 : 1e-4)
    property real lastPaintedRpm: 0
    property real lastPaintedFuel: 100

    function requestGaugeStaticPaint() {
        dialChrome.requestStaticPaint();
    }
    function requestRpmPaint() {
        const force = arguments.length > 0 && arguments[0] === true;
        dialChrome.requestDynamicPaint(force);
        root.lastPaintedRpm = root.displayRpm;
    }
    function requestFuelPaint() {
        fuelArcCanvas.requestPaint();
        root.lastPaintedFuel = root.displayFuel;
    }
    function requestGaugeDynamicPaint() {
        const force = arguments.length > 0 && arguments[0] === true;
        requestRpmPaint(force);
        requestFuelPaint();
    }
    function kickSmoother() {
        if (!smoothingTimer.running) smoothingTimer.start();
    }

    readonly property real progress: clamp(displayRpm / maxRpm, 0, 1)
    readonly property int rpmInt: Math.round(displayRpm)

    readonly property int fuelInt: Math.round(displayFuel)
    readonly property bool lowFuel: (displayFuel <= lowFuelPct)
    readonly property bool highRpm: displayRpm >= redlineStart
    readonly property bool tachHeadScared: displayRpm > 3500
    readonly property bool fuelHeadScared: displayFuel <= 15

    // Keep the dial geometry stable so the speed and tach arcs stay optically matched.
    readonly property real faceScale: 1.0
    readonly property real faceYOffset: 0
    readonly property real rainFaceRadius: width * 0.496
    property real flashLevel: 0.0
    property real fuelLavaPhase: 0.0

    function fallbackRpmColor(v) {
        return (v >= redlineStart) ? "#FF3B3B" : "#5E35B1";
    }

    readonly property color gaugeColor: (theme && theme.rpmColor)
        ? theme.rpmColor(displayRpm, redlineStart, maxRpm)
        : fallbackRpmColor(displayRpm)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.72 : 0.42;
    }

    // ---- Link health gating (never lie silently) ----
    readonly property bool linkOk: !!vehicleState
                               && vehicleState.connected
                               && !vehicleState.linkStale
                               && !vehicleState.bbbStale

    readonly property bool displayHighBeam: root.stressScene
        ? Math.sin(root.stressPhase * 0.72) > 0.20
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.highBeam
    readonly property bool displayWarnDoor: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnDoor
    readonly property bool displayWarnCharge: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnCharge
    readonly property bool displayWarnBrake: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnBrake
    readonly property bool displayWarnOil: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnOil
    readonly property bool displayWarnCheckEngine: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnCheckEngine
    readonly property bool displayWarnAT: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnAT
    readonly property bool displayWarnFuelLow: root.stressScene
        ? true
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.warnFuelLow
    readonly property string displayDrivetrainMode: root.stressScene
        ? (Math.sin(root.stressPhase * 0.22) > 0.45 ? "4wd" : "2wd")
        : (root.linkOk && !!root.vehicleState ? root.vehicleState.drivetrainMode : "2wd")
    readonly property bool displayTransferLock: root.stressScene
        ? Math.sin(root.stressPhase * 0.18 + 1.1) > 0.78
        : root.linkOk && !!root.vehicleState && !!root.vehicleState.transferLock

    // ===== Smooth RPM =====
    Timer {
        id: smoothingTimer
        interval: root.lowEffectMode ? 50 : 16
        running: false
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const prevRpm = root.displayRpm;
            const prevFuel = root.displayFuel;
            const target = clamp(root.rpm, 0, root.maxRpm);
            const diff = target - root.displayRpm;

            let step = diff * (1 - Math.exp(-root.response * dt));
            step = clamp(step, -root.maxStepPerFrame, root.maxStepPerFrame);

            root.displayRpm += step;

            // ---- Smooth fuel ----
            const fuelTarget = clamp(root.fuelPct, 0, 100);
            const fuelDiff = fuelTarget - root.displayFuel;

            let fuelStep = fuelDiff * (1 - Math.exp(-root.fuelResponse * dt));
            fuelStep = clamp(fuelStep, -root.fuelMaxStepPerFrame, root.fuelMaxStepPerFrame);

            root.displayFuel += fuelStep;

            const rpmSettled = Math.abs(target - root.displayRpm) < 0.2;
            const fuelSettled = Math.abs(fuelTarget - root.displayFuel) < 0.02;
            const rpmChanged = Math.abs(root.displayRpm - prevRpm) > 1e-4;
            const fuelChanged = Math.abs(root.displayFuel - prevFuel) > 1e-4;
            const rpmNeedsRepaint = Math.abs(root.displayRpm - root.lastPaintedRpm) >= root.rpmRepaintThreshold;
            const fuelNeedsRepaint = Math.abs(root.displayFuel - root.lastPaintedFuel) >= root.fuelRepaintThreshold;
            const rpmSettledFlush = rpmSettled && Math.abs(root.displayRpm - root.lastPaintedRpm) > 1e-4;
            const fuelSettledFlush = fuelSettled && Math.abs(root.displayFuel - root.lastPaintedFuel) > 1e-4;

            if (rpmChanged && (rpmNeedsRepaint || rpmSettledFlush)) requestRpmPaint();
            if (fuelChanged && (fuelNeedsRepaint || fuelSettledFlush)) requestFuelPaint();
            if (rpmSettled && fuelSettled) running = false;
        }
    }

    Timer {
        interval: root.lowEffectMode ? 120 : (root.embeddedHighEffectBudgetMode ? 300 : 42)
        running: root.effectLevel !== "off" && root.auxArcAnimationEnabled
        repeat: true
        onTriggered: {
            root.fuelLavaPhase += interval / 1000.0
            fuelArcCanvas.requestPaint()
        }
    }

    onRpmChanged: kickSmoother()
    onFuelPctChanged: kickSmoother()
    onMaxRpmChanged: kickSmoother()
    onHighRpmChanged: requestGaugeDynamicPaint(true)
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
        displayRpm = clamp(rpm, 0, maxRpm)
        displayFuel = clamp(fuelPct, 0, 100)
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint(true)
        kickSmoother()
    }

    SequentialAnimation {
        id: redlinePulse
        running: root.highRpm
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "flashLevel"; from: 0.10; to: 1.0; duration: 150; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "flashLevel"; from: 1.0; to: 0.16; duration: 190; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 80 }
        onStopped: root.flashLevel = 0.0
    }

    // ===== Gauge face (breathing layer) =====
    Item {
        id: face
        anchors.fill: parent
        transformOrigin: Item.Center
        scale: root.faceScale
        y: root.faceYOffset
        z: 20

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
            gaugeColor: root.gaugeColor
            chromeColor: root.chromeColor
            progress: root.progress
            scaredHead: root.tachHeadScared
            maxValue: root.maxRpm
            startAngleDeg: root.startAngleDeg
            sweepAngleDeg: root.sweepAngleDeg
            minorStep: 500
            majorStep: 1000
            labelStep: 1000
            labelStart: 1000
            labelDivisor: 1000
        }

        // ---- Fuel arc (cheap static band, opposite tach) ----
        Item {
            id: fuelArcLayer
            anchors.fill: parent
            z: 44

            readonly property real rawStartDeg: (root.startAngleDeg + root.sweepAngleDeg) % 360
            readonly property real rawSweepDeg: 360 - root.sweepAngleDeg
            readonly property real padDeg: 12
            readonly property real startDeg: rawStartDeg + padDeg
            readonly property real sweepDeg: Math.max(0, rawSweepDeg - padDeg * 2)
            readonly property real fuelNorm: clamp(root.displayFuel / 100.0, 0, 1)
            readonly property real fillStartNorm: 1.0 - fuelNorm
            readonly property real radius: width * 0.36
            readonly property real labelRadius: radius + 18
            readonly property color baseDark: root.theme?.pearlHigh ?? root.gaugeColor
            readonly property color fuelColor: root.fuelActiveColor(fuelNorm)
            readonly property color fuelBright: root.blendToward(fuelColor, Qt.color("#FFFFFF"), 0.20, 1.0)
            readonly property real sweepRad: sweepDeg * Math.PI / 180
            readonly property real headAngleRad: angleRad(startDeg) + sweepRad * fillStartNorm
            readonly property bool headVisible: fuelNorm > 0.002
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
                id: fuelArcCanvas
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
                    const startRad = fuelArcLayer.angleRad(fuelArcLayer.startDeg)
                    const sweepRad = fuelArcLayer.sweepDeg * Math.PI / 180
                    const tailT = 1.0
                    const headT = fuelArcLayer.fillStartNorm
                    const fuel = fuelArcLayer.fuelColor
                    const bright = fuelArcLayer.fuelBright

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
                    ctx.strokeStyle = rgba(fuelArcLayer.baseDark, root.lowEffectMode ? 0.10 : 0.08)
                    ctx.lineWidth = root.lowEffectMode ? (10 * root.auxArcCanvasScale) : (22 * root.auxArcStrokeTune)
                    ctx.lineCap = "round"
                    ctx.arc(cx, cy, r, startRad, startRad + sweepRad)
                    ctx.stroke()
                    ctx.restore()

                    if (root.cheapAuxArcMode) {
                        if (fuelArcLayer.fuelNorm > 0.002) {
                            const activeStart = startRad + sweepRad * headT
                            const activeEnd = startRad + sweepRad * tailT

                            ctx.save()
                            ctx.beginPath()
                            ctx.strokeStyle = rgba(fuel, root.lowEffectMode ? 0.76 : 0.82)
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
                            performanceMetrics.recordPaint("tachGauge.fuelArc")
                        return
                    }

                    if (fuelArcLayer.fuelNorm > 0.002) {
                        const tailWidth = root.lowEffectMode ? (3.5 * root.auxArcCanvasScale) : (5.5 * root.auxArcStrokeTune)
                        const headWidth = root.lowEffectMode ? (10 * root.auxArcCanvasScale) : (22 * root.auxArcStrokeTune)
                        const phase = root.fuelLavaPhase

                        if (root.lowEffectMode) {
                            ctx.save()
                            buildBandPath(tailT, headT, tailWidth, headWidth)
                            const fill = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r)
                            fill.addColorStop(0.00, rgba(neonLime, 0.64))
                            fill.addColorStop(0.42, rgba(neonCyan, 0.74))
                            fill.addColorStop(0.76, rgba(bright, 0.66))
                            fill.addColorStop(1.00, rgba(neonOrange, 0.56))
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
                            fill.addColorStop(0.00, rgba(neonLime, 0.48))
                            fill.addColorStop(0.24, rgba(neonCyan, 0.64))
                            fill.addColorStop(0.54, rgba(neonPink, 0.72))
                            fill.addColorStop(0.78, rgba(bright, 0.62))
                            fill.addColorStop(1.00, rgba(neonOrange, 0.52))
                            ctx.fillStyle = fill
                            ctx.fillRect(0, 0, width, height)

                            const blobCount = root.embeddedHighEffectBudgetMode ? 2 : 5
                            for (let i = 0; i < blobCount; i++) {
                                const blobColor = [neonLime, neonCyan, neonPink, neonOrange, neonYellow][i % 5]
                                const u = (phase * (0.10 + i * 0.014) + i * 0.21) % 1.0
                                const t = tailT + (headT - tailT) * u
                                const wobble = Math.sin(phase * (1.0 + i * 0.2) + i * 1.9)
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
                        performanceMetrics.recordPaint("tachGauge.fuelArc")
                }
            }

            GaugeArcHead {
                z: 48
                visible: fuelArcLayer.headVisible
                lowEffectMode: root.lowEffectMode
                scared: root.fuelHeadScared
                headRadius: root.sideArcHeadRadius
                x: fuelArcLayer.headCenterX - width / 2
                y: fuelArcLayer.headCenterY - height / 2
            }

            Text {
                width: 24
                height: 20
                x: fuelArcLayer.pointX(fuelArcLayer.startDeg, fuelArcLayer.labelRadius, width)
                y: fuelArcLayer.pointY(fuelArcLayer.startDeg, fuelArcLayer.labelRadius, height)
                text: "F"
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
                x: fuelArcLayer.pointX(fuelArcLayer.startDeg + fuelArcLayer.sweepDeg,
                                        fuelArcLayer.labelRadius,
                                        width)
                y: fuelArcLayer.pointY(fuelArcLayer.startDeg + fuelArcLayer.sweepDeg,
                                        fuelArcLayer.labelRadius,
                                        height)
                text: "E"
                color: root.theme?.text ?? "white"
                opacity: root.theme?.isNight ? 0.90 : 0.75
                font.family: root.theme?.fontMono ?? "monospace"
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // ---- Rim (optional) ----
        Canvas {
            id: rimCanvas
            visible: false
            anchors.fill: parent
        }
    }

    Canvas {
        id: redlineFlash
        anchors.fill: parent
        z: 52
        visible: root.highRpm
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

    VehicleInfoCenter {
        id: vicCenter
        anchors.centerIn: parent

        readonly property real factor: 0.50
        readonly property real side: Math.max(0, Math.min(parent.width, parent.height) * factor)
        width: side
        height: side
        z: 150
        visible: true
        simplified: root.lowEffectMode
        pulseEnabled: !root.lowEffectMode

        warnDoor: root.displayWarnDoor
        warnCharge: root.displayWarnCharge
        warnBrake: root.displayWarnBrake
        warnOil: root.displayWarnOil
        warnCheckEngine: root.displayWarnCheckEngine
        warnAT: root.displayWarnAT
        warnFuelLow: root.displayWarnFuelLow

        drivetrainMode: root.displayDrivetrainMode
        transferLock: root.displayTransferLock
    }

    HighBeamHalo {
        anchors.centerIn: vicCenter
        z: 140
        vicDiameter: vicCenter.width
        ringThickness: 16
        gapPx: 3
        holdMs: 1100
        heartbeat: root.effectLevel !== "off"
        active: root.displayHighBeam
    }
}
