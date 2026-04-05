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
    readonly property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")

    function requestGaugeStaticPaint() {
        dialChrome.requestStaticPaint();
    }
    function requestGaugeDynamicPaint() {
        dialChrome.requestDynamicPaint();
        rimCanvas.requestPaint();
        fuelArcCanvas.requestPaint();
    }
    function kickSmoother() {
        if (!smoothingTimer.running) smoothingTimer.start();
    }

    readonly property real progress: clamp(displayRpm / maxRpm, 0, 1)
    readonly property int rpmInt: Math.round(displayRpm)

    readonly property int fuelInt: Math.round(displayFuel)
    readonly property bool lowFuel: (displayFuel <= lowFuelPct)
    readonly property bool highRpm: displayRpm >= redlineStart

    // Keep the dial geometry stable so the speed and tach arcs stay optically matched.
    readonly property real faceScale: 1.0
    readonly property real faceYOffset: 0
    readonly property real rainFaceRadius: width * 0.438
    property real flashLevel: 0.0

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

    // ===== Smooth RPM =====
    Timer {
        id: smoothingTimer
        interval: 16
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
            const changed = Math.abs(root.displayRpm - prevRpm) > 1e-4
                         || Math.abs(root.displayFuel - prevFuel) > 1e-4;

            if (changed) requestGaugeDynamicPaint();
            if (rpmSettled && fuelSettled) running = false;
        }
    }

    onRpmChanged: kickSmoother()
    onFuelPctChanged: kickSmoother()
    onMaxRpmChanged: kickSmoother()
    onGaugeColorChanged: requestGaugeDynamicPaint()
    onHighRpmChanged: requestGaugeDynamicPaint()
    onThemeChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
    }
    onWidthChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
    }
    onHeightChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
    }
    onLowEffectModeChanged: {
        requestGaugeDynamicPaint()
        kickSmoother()
    }

    Component.onCompleted: {
        displayRpm = clamp(rpm, 0, maxRpm)
        displayFuel = clamp(fuelPct, 0, 100)
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
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

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                const cx = width / 2;
                const cy = height / 2;
                ctx.fillStyle = "#07080E";
                ctx.beginPath();
                ctx.arc(cx, cy, root.rainFaceRadius, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        MatrixRain {
            anchors.fill: parent
            z: 2
            visible: root.matrixRainEnabled && !root.lowEffectMode
            circularMask: true
            maskRadius: root.rainFaceRadius
            effectEnabled: visible
            effectLevel: root.effectLevel
            sharedPhase: root.matrixRainSharedPhase
            rainColor: root.blendToward(
                root.gaugeColor,
                root.theme?.pearlLow ?? Qt.color("#C7B7FF"),
                0.72,
                0.96
            )
            fps: 12
            speedMultiplier: 0.20
            density: 0.30
            glowSpeed: 0.72
            glowFloor: 0.28
            driftScale: 0.90
            charChangeChance: 0.026
            fontPx: 12
            fadeAlpha: 0.024
            tailLength: 48
            headAlpha: 0.92
            tailMinAlpha: 0.12
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
            maxValue: root.maxRpm
            startAngleDeg: root.startAngleDeg
            sweepAngleDeg: root.sweepAngleDeg
            minorStep: 500
            majorStep: 1000
            labelStep: 1000
            labelStart: 1000
            labelDivisor: 1000
        }

        // ---- Fuel arc (FILLED band, opposite tach) ----
        Canvas {
            id: fuelArcCanvas
            anchors.centerIn: parent
            width: parent.width * (root.lowEffectMode ? 0.42 : 1.0)
            height: parent.height * (root.lowEffectMode ? 0.42 : 1.0)
            z: 44
            scale: root.lowEffectMode ? (1.0 / 0.42) : 1.0
            renderTarget: Canvas.FramebufferObject

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const cx = width / 2;
                const cy = height / 2;

                const rawStartDeg = (root.startAngleDeg + root.sweepAngleDeg) % 360;
                const rawSweepDeg = 360 - root.sweepAngleDeg;

                const padDeg = 12;
                const startDeg = rawStartDeg + padDeg;
                const sweepDeg = Math.max(0, rawSweepDeg - padDeg * 2);

                const startRad = (startDeg - 90) * Math.PI / 180;
                const sweepRad = sweepDeg * Math.PI / 180;

                const fuel = clamp(root.displayFuel / 100.0, 0, 1);

                const rOut = width * 0.36;
                const thickStart = 24;
                const thickEnd   = 4;
                const segments   = root.lowEffectMode ? 12 : 90;

                const dark  = (theme?.pearlHigh ?? root.gaugeColor);
                const light = (theme?.pearlLow  ?? "#B79CFF");

                ctx.save();

                function drawTrack(tFrom, tTo, color, alpha, widthScale) {
                    for (let i = 0; i < segments; i++) {
                        const u0 = i / segments;
                        const u1 = (i + 1) / segments;

                        if (u0 >= tTo) break;

                        const v0 = Math.max(u0, tFrom);
                        const v1 = Math.min(u1, tTo);
                        if (v1 <= v0) continue;

                        const th  = thickStart + (thickEnd - thickStart) * v1;
                        const rr = rOut - th / 2;
                        ctx.beginPath();
                        ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, alpha);
                        ctx.lineCap = "round";
                        ctx.lineWidth = Math.max(2, th * widthScale);
                        ctx.arc(cx, cy, rr, startRad + sweepRad * v0, startRad + sweepRad * v1, false);
                        ctx.stroke();
                    }
                }

                const fuelColor = root.fuelActiveColor(fuel);

                const fuelStart = 1.0 - fuel;
                if (root.lowEffectMode) {
                    drawTrack(0.0, 1.0, dark, 0.10, 0.40);
                    drawTrack(fuelStart, 1.0, root.blendToward(fuelColor, Qt.color("#FFFFFF"), 0.12, 1.0), 0.88, 0.18);
                } else {
                    drawTrack(0.0, 1.0, dark, 0.08, 1.05);
                    drawTrack(0.0, 1.0, dark, 0.14, 0.60);
                    drawTrack(fuelStart, 1.0, fuelColor, 0.22, 0.74);
                    drawTrack(fuelStart, 1.0, fuelColor, 0.34, 0.42);
                    drawTrack(fuelStart, 1.0, root.blendToward(fuelColor, Qt.color("#FFFFFF"), 0.20, 1.0), 0.90, 0.18);
                }

                function capAt(t, color) {
                    const th = thickStart + (thickEnd - thickStart) * t;
                    const rr = rOut - th / 2;
                    const ang = startRad + sweepRad * t;
                    const x = cx + Math.cos(ang) * rr;
                    const y = cy + Math.sin(ang) * rr;

                    ctx.fillStyle = color;
                    ctx.beginPath();
                    ctx.arc(x, y, Math.max(2, th * 0.18), 0, Math.PI * 2);
                    ctx.fill();
                }

                if (fuelStart > 0.0 && fuelStart < 1.0) {
                    capAt(fuelStart, root.blendToward(fuelColor, Qt.color("#FFFFFF"), 0.12, 1.0));
                }

                // F / E labels
                const labelR = rOut + 18;
                const angF = startRad;
                const angE = startRad + sweepRad;

                ctx.globalAlpha = theme?.isNight ? 0.90 : 0.75;
                ctx.fillStyle = theme?.text ?? "white";
                ctx.font = "700 16px monospace";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                ctx.fillText("F", cx + Math.cos(angF) * labelR, cy + Math.sin(angF) * labelR);
                ctx.fillText("E", cx + Math.cos(angE) * labelR, cy + Math.sin(angE) * labelR);

                ctx.restore();

                if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                    performanceMetrics.recordPaint("tachGauge.fuelArc")
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

    // ==============================
    // VIC: BBB-truth only (no mock)
    // ==============================
    VehicleInfoCenter {
        id: vicCenter
        anchors.centerIn: parent

        // Size + layering preserved from your original block
        readonly property real factor: 0.50
        readonly property real side: Math.max(0, Math.min(parent.width, parent.height) * factor)
        width: side
        height: side
        z: 150
        visible: true
        simplified: root.lowEffectMode
        pulseEnabled: !root.lowEffectMode

        // Bind warnings to BBB truth with stale gating.
        // If link is stale, show nothing rather than inventing warnings.
        warnDoor:   root.linkOk && !!root.vehicleState && root.vehicleState.warnDoor
        warnCharge: root.linkOk && !!root.vehicleState && root.vehicleState.warnCharge
        warnBrake:  root.linkOk && !!root.vehicleState && root.vehicleState.warnBrake
        warnOil:    root.linkOk && !!root.vehicleState && root.vehicleState.warnOil

        // Not implemented on BBB yet in this step; keep false.
        warnCheckEngine: root.linkOk && !!root.vehicleState && root.vehicleState.warnCheckEngine
        warnAT:          root.linkOk && !!root.vehicleState && root.vehicleState.warnAT
        warnFuelLow:     root.linkOk && !!root.vehicleState && root.vehicleState.warnFuelLow

        drivetrainMode: root.linkOk && !!root.vehicleState
            ? root.vehicleState.drivetrainMode
            : "2wd"
        transferLock: root.linkOk && !!root.vehicleState
            ? root.vehicleState.transferLock
            : false
    }

    HighBeamHalo {
        id: highBeamHalo
        anchors.centerIn: vicCenter
        z: 140
        visible: !root.lowEffectMode
        vicDiameter: vicCenter.width
        ringThickness: 16
        gapPx: 3
        holdMs: 1100
        heartbeat: !root.lowEffectMode
        active: root.linkOk && !!root.vehicleState && !!root.vehicleState.highBeam
    }

    Rectangle {
        visible: root.lowEffectMode && root.linkOk && !!root.vehicleState && !!root.vehicleState.highBeam
        z: 160
        width: 90
        height: 36
        radius: 14
        anchors.horizontalCenter: vicCenter.horizontalCenter
        anchors.top: vicCenter.top
        anchors.topMargin: 18
        color: "#102033E8"
        border.width: 1
        border.color: "#63C9FF"

        Text {
            anchors.centerIn: parent
            text: "HIGH"
            color: "#63C9FF"
            font.family: root.theme?.fontMono ?? "monospace"
            font.pixelSize: 16
            font.bold: true
            letterSpacing: 2
        }
    }
}
