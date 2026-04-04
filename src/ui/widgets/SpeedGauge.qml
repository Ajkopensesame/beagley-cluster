import QtQuick 2.15
import QtQuick.Shapes 1.15

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

        return textCol;
    }

    // =======================================
    width: 420
    height: 420

    // Theme from Main.qml
    property var theme
    property string effectLevel: "high"
    property bool matrixRainEnabled: true
    property real matrixRainSharedPhase: NaN

    property var vehicleState
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
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property color chromeColor: theme?.pearlLow ?? Qt.color("#C7B7FF")

    function requestGaugeStaticPaint() {
        dialChrome.requestStaticPaint();
    }
    function requestGaugeDynamicPaint() {
        dialChrome.requestDynamicPaint();
        coolantArcCanvas.requestPaint();
    }
    function kickSmoother() {
        if (!smoothingTimer.running) smoothingTimer.start();
    }

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)
    readonly property bool highSpeed: overSpeed
    property real flashLevel: 0.0

    // Coolant normalized 0..1 (C -> H)
    readonly property real coolantNorm: clamp(
        (displayCoolantC - coolantColdC) / Math.max(1e-6, (coolantHotC - coolantColdC)),
        0, 1
    )

    // Keep the dial geometry stable so the speed and tach arcs stay optically matched.
    readonly property real faceScale: 1.0
    readonly property real faceYOffset: 0
    readonly property real rainFaceRadius: width * 0.438

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

    // --- Coolant colour ramp (cold->warm->hot) ---
    function coolantRampColor(t) {
        // Palette (fallbacks)
        const cold = "#C7B7FF";  // light purple
        const warm = "#FFD54A";  // yellow
        const hot  = "#FF3B3B";  // red

        // 0..0.65: cold->warm, 0.65..1: warm->hot
        if (t <= 0.65) {
            const u = t / 0.65;
            return Qt.rgba(
                lerp(Qt.color(cold).r, Qt.color(warm).r, u),
                lerp(Qt.color(cold).g, Qt.color(warm).g, u),
                lerp(Qt.color(cold).b, Qt.color(warm).b, u),
                1
            );
        } else {
            const u = (t - 0.65) / 0.35;
            return Qt.rgba(
                lerp(Qt.color(warm).r, Qt.color(hot).r, u),
                lerp(Qt.color(warm).g, Qt.color(hot).g, u),
                lerp(Qt.color(warm).b, Qt.color(hot).b, u),
                1
            );
        }
    }

    function mixColors(c1, c2, t, a) {
        return Qt.rgba(
            lerp(c1.r, c2.r, t),
            lerp(c1.g, c2.g, t),
            lerp(c1.b, c2.b, t),
            a
        );
    }

    function coolantActiveColor(tempC) {
        const t = Number(tempC) || 0;
        const purple = theme?.pearlLow ?? Qt.color("#C7B7FF");
        const blue = Qt.color("#63C9FF");
        const green = Qt.color("#72F7A1");
        const red = theme?.danger ?? Qt.color("#FF3B3B");

        if (t <= 50) return purple;
        if (t <= 75) return mixColors(purple, blue, (t - 50) / 25.0, 1.0);
        if (t <= 90) return mixColors(blue, green, (t - 75) / 15.0, 1.0);
        if (t <= 100) return mixColors(mixColors(purple, green, 0.35, 1.0), green, (t - 90) / 10.0, 1.0);
        if (t <= 110) return mixColors(green, red, (t - 100) / 10.0, 1.0);
        return red;
    }

    // Smooth animation
    Timer {
        id: smoothingTimer
        interval: 16
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
            const changed = Math.abs(root.displaySpeed - prevSpeed) > 1e-4
                         || Math.abs(root.displayCoolantC - prevCoolant) > 1e-4;

            if (changed) requestGaugeDynamicPaint();
            if (speedSettled && coolantSettled) running = false;
        }
    }

    onSpeedChanged: kickSmoother()
    onCoolantCChanged: kickSmoother()
    onMaxSpeedChanged: kickSmoother()
    onGaugeColorChanged: requestGaugeDynamicPaint()
    onThemeChanged: requestGaugeStaticPaint()
    onWidthChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
    }
    onHeightChanged: {
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
    }

    Component.onCompleted: {
        displaySpeed = clamp(speed, 0, maxSpeed)
        displayCoolantC = coolantC
        requestGaugeStaticPaint()
        requestGaugeDynamicPaint()
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
            gaugeColor: root.gaugeColor
            chromeColor: root.chromeColor
            progress: root.progress
            maxValue: root.maxSpeed
            startAngleDeg: root.startAngleDeg
            sweepAngleDeg: root.sweepAngleDeg
            minorStep: 10
            majorStep: 20
            labelStep: 20
            labelStart: 20
            labelDivisor: 1
        }

        // ---- Coolant arc (FILLED band, opposite speed sweep) ----
        Canvas {
            id: coolantArcCanvas
            anchors.fill: parent
            z: 44

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: root
                function onDisplayCoolantCChanged() { coolantArcCanvas.requestPaint() }
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const cx = width / 2;
                const cy = height / 2;

                // Opposite-side arc (same concept as Tach fuel arc)
                const rawStartDeg = (root.startAngleDeg + root.sweepAngleDeg) % 360;
                const rawSweepDeg = 360 - root.sweepAngleDeg;

                const padDeg = 12;
                const startDeg = rawStartDeg + padDeg;
                const sweepDeg = Math.max(0, rawSweepDeg - padDeg * 2);

                // startRad ~ top-right, end ~ bottom-left
                const startRad = (startDeg - 90) * Math.PI / 180;
                const sweepRad = sweepDeg * Math.PI / 180;

                const rOut = width * 0.36;
                const thickStart = 24;   // wide end (H side)
                const thickEnd   = 4;    // point end (C side)
                const segments   = 90;

                ctx.save();

                const baseDark = (theme?.pearlHigh ?? root.gaugeColor);
                const coolantColor = root.coolantActiveColor(root.displayCoolantC);
                function drawTrack(tFrom, tTo, colorFnOrColor, alpha, widthScale) {
                    for (let i = 0; i < segments; i++) {
                        const u0 = i / segments;
                        const u1 = (i + 1) / segments;
                        if (u0 >= tTo) break;

                        const v0 = Math.max(u0, tFrom);
                        const v1 = Math.min(u1, tTo);
                        if (v1 <= v0) continue;

                        const th = thickStart + (thickEnd - thickStart) * ((v0 + v1) * 0.5);
                        const rr = rOut - th / 2;
                        const col = (typeof colorFnOrColor === "function")
                            ? colorFnOrColor((v0 + v1) * 0.5)
                            : colorFnOrColor;

                        ctx.beginPath();
                        ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, alpha);
                        ctx.lineCap = "round";
                        ctx.lineWidth = Math.max(2, th * widthScale);
                        ctx.arc(cx, cy, rr, startRad + sweepRad * v0, startRad + sweepRad * v1, false);
                        ctx.stroke();
                    }
                }

                // Fill from C -> H.
                // Arc param: 0 at H, 1 at C. Coolant norm: 0 at C, 1 at H.
                // Therefore filled region is [1 - coolantNorm, 1.0].
                const tStartFill = 1.0 - root.coolantNorm;
                drawTrack(0.0, 1.0, baseDark, 0.08, 1.05);
                drawTrack(0.0, 1.0, baseDark, 0.14, 0.60);
                drawTrack(tStartFill, 1.0, coolantColor, 0.22, 0.74);
                drawTrack(tStartFill, 1.0, coolantColor, 0.34, 0.42);
                drawTrack(tStartFill, 1.0, root.blendToward(coolantColor, Qt.color("#FFFFFF"), 0.20, 1.0), 0.90, 0.18);

                // Moving boundary cap
                function capAt(t, color) {
                    const th = thickStart + (thickEnd - thickStart) * t;
                    const rr = rOut - th / 2;
                    const ang = startRad + sweepRad * t;
                    const x = cx + Math.cos(ang) * rr;
                    const y = cy + Math.sin(ang) * rr;

                ctx.save();
                    ctx.fillStyle = color;
                    ctx.beginPath();
                    ctx.arc(x, y, Math.max(2, th * 0.18), 0, Math.PI * 2);
                    ctx.fill();
                ctx.restore();
                }

                if (tStartFill > 0.0 && tStartFill < 1.0) {
                    capAt(tStartFill, root.blendToward(coolantColor, Qt.color("#FFFFFF"), 0.12, 1.0));
                }


                // Rounded physical endpoint caps (match Tach fuel arc style)
                // t=0.0 is the H end (wide), t=1.0 is the C end (point)
                // Labels pinned to endpoints
                const labelR = rOut + 18;
                const angH = startRad;
                const angC = startRad + sweepRad;

                ctx.globalAlpha = theme?.isNight ? 0.90 : 0.75;
                ctx.fillStyle = theme?.text ?? "white";
                ctx.font = "700 16px monospace";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                ctx.fillText("H", cx + Math.cos(angH) * labelR, cy + Math.sin(angH) * labelR);
                ctx.fillText("C", cx + Math.cos(angC) * labelR, cy + Math.sin(angC) * labelR);

                ctx.restore();

                if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                    performanceMetrics.recordPaint("speedGauge.coolantArc")
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
        readonly property bool active: !!(root.vehicleState && root.vehicleState.overdrive === true)
        readonly property color odColor: (root.theme && root.theme.amber) ? root.theme.amber : "#FFC107"
        visible: true

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
            border.color: odBadge.odColor
            opacity: odBadge.active ? 0.94 : 0.70
        }

        // Outer glow (soft)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 14
            border.color: Qt.rgba(odBadge.odColor.r, odBadge.odColor.g, odBadge.odColor.b, odBadge.active ? 0.17 : 0.10)
            opacity: odBadge.active ? 1.0 : 0.45
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
            opacity: odBadge.active ? 1.0 : 0.78
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
        anchors.topMargin: 8
        anchors.horizontalCenter: speedValueText.horizontalCenter
        width: 96
        height: 72

        Text {
            id: gearText
            anchors.centerIn: parent

            text: (root.vehicleState && root.vehicleState.gear !== undefined) ? root.vehicleState.gear : "P"

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

}
