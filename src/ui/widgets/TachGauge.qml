import QtQuick 2.15

Item {
    id: root
    width: 420
    height: 420

    // Pass the theme object in from Main.qml
    property var theme

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

    readonly property real progress: clamp(displayRpm / maxRpm, 0, 1)
    readonly property int rpmInt: Math.round(displayRpm)

    readonly property int fuelInt: Math.round(displayFuel)
    readonly property bool lowFuel: (displayFuel <= lowFuelPct)

    // ===== Depth effect (MATCH SPEEDO) =====
    property real depthK: 1.0
    readonly property real depth: progress * depthK
    readonly property real faceScale: 1.0 - 0.08 * depth
    readonly property real faceYOffset: 12 * depth

    function fallbackRpmColor(v) {
        return (v >= redlineStart) ? "#FF3B3B" : "#5E35B1";
    }

    readonly property color gaugeColor: (theme && theme.rpmColor)
        ? theme.rpmColor(displayRpm, redlineStart, maxRpm)
        : fallbackRpmColor(displayRpm)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.55 : 0.32;
    }

    // ---- Link health gating (never lie silently) ----
    readonly property bool linkOk: !!vehicleState && vehicleState.connected && !vehicleState.linkStale

    // ===== Smooth RPM =====
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
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

            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
            rimCanvas.requestPaint();
            innerShadow.requestPaint();
            fuelArcCanvas.requestPaint();
        }
    }

    // ===== Gauge face (breathing layer) =====
    Item {
        id: face
        anchors.fill: parent
        transformOrigin: Item.Center
        scale: root.faceScale
        y: root.faceYOffset
        z: 20

        // ---- Ticks + numbers ----
        Canvas {
            id: ticksCanvas
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const cx = width / 2;
                const cy = height / 2;
                const rOuter = width * 0.42;
                const rInnerMinor = rOuter - 9;
                const rInnerMajor = rOuter - 18;

                const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
                const sweepRad = root.sweepAngleDeg * Math.PI / 180;

                for (let v = 0; v <= root.maxRpm; v += 500) {
                    const t = v / root.maxRpm;
                    const a = startRad + sweepRad * t;
                    const major = (v % 1000 === 0);

                    ctx.beginPath();
                    ctx.strokeStyle = Qt.rgba(
                        root.gaugeColor.r,
                        root.gaugeColor.g,
                        root.gaugeColor.b,
                        tickAlpha(major)
                    );
                    ctx.lineWidth = major ? 4 : 2.5;
                    ctx.lineCap = "round";

                    const rInner = major ? rInnerMajor : rInnerMinor;
                    ctx.moveTo(cx + Math.cos(a) * rInner, cy + Math.sin(a) * rInner);
                    ctx.lineTo(cx + Math.cos(a) * rOuter, cy + Math.sin(a) * rOuter);
                    ctx.stroke();

                    if (major && v > 0) {
                        const label = Math.round(v / 1000);
                        if (label <= root.maxScale) {
                            const rLabel = rInnerMajor - 20;
                            ctx.save();
                            ctx.fillStyle = theme?.text ?? "white";
                            ctx.globalAlpha = theme?.isNight ? 0.85 : 0.75;
                            ctx.font = '600 18px "DejaVu Sans Mono","Noto Sans Mono",monospace';
                            ctx.textAlign = "center";
                            ctx.textBaseline = "middle";
                            ctx.fillText(
                                String(label),
                                cx + Math.cos(a) * rLabel,
                                cy + Math.sin(a) * rLabel
                            );
                            ctx.restore();
                        }
                    }
                }
            }
        }

        // ---- Arc ----
        Canvas {
            id: arcCanvas
            anchors.fill: parent

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const cx = width / 2;
                const cy = height / 2;
                const r  = width * 0.40;

                const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
                const endRad = startRad + root.sweepAngleDeg * root.progress * Math.PI / 180;

                for (let i = 0; i < 60; i++) {
                    const t0 = i / 60;
                    const t1 = (i + 1) / 60;

                    ctx.beginPath();
                    ctx.strokeStyle = root.gaugeColor;
                    ctx.lineCap = "round";
                    ctx.lineWidth = 6 + (26 - 6) * t1;
                    ctx.arc(
                        cx, cy, r,
                        startRad + (endRad - startRad) * t0,
                        startRad + (endRad - startRad) * t1
                    );
                    ctx.stroke();
                }
            }
        }

        // ---- Fuel arc (FILLED band, opposite tach) ----
        Canvas {
            id: fuelArcCanvas
            anchors.fill: parent
            z: 44

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: root
                function onDisplayFuelChanged() { fuelArcCanvas.requestPaint() }
            }

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
                const empty = 1.0 - fuel;

                const rOut = width * 0.36;
                const thickStart = 26;
                const thickEnd   = 3;
                const segments   = 90;

                const dark  = (theme?.pearlHigh ?? root.gaugeColor);
                const light = (theme?.pearlLow  ?? "#B79CFF");

                ctx.save();
                ctx.globalAlpha = theme?.isNight ? 0.88 : 0.72;

                function drawBand(tFrom, tTo, color) {
                    ctx.fillStyle = color;

                    for (let i = 0; i < segments; i++) {
                        const u0 = i / segments;
                        const u1 = (i + 1) / segments;

                        if (u0 >= tTo) break;

                        const v0 = Math.max(u0, tFrom);
                        const v1 = Math.min(u1, tTo);
                        if (v1 <= v0) continue;

                        const a0 = startRad + sweepRad * v0;
                        const a1 = startRad + sweepRad * v1;

                        const th  = thickStart + (thickEnd - thickStart) * v1;
                        const rIn = rOut - th;

                        ctx.beginPath();
                        ctx.arc(cx, cy, rOut, a0, a1, false);
                        ctx.arc(cx, cy, rIn,  a1, a0, true);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                // Base band (empty/light)
                drawBand(0.0, 1.0, dark);

                // Overlay band (full/dark), anchored at the wide end (F)
                drawBand(0.0, empty, light);

                function capAt(t, color) {
                    const th = thickStart + (thickEnd - thickStart) * t;
                    const rr = rOut - th / 2;
                    const ang = startRad + sweepRad * t;
                    const x = cx + Math.cos(ang) * rr;
                    const y = cy + Math.sin(ang) * rr;

                    ctx.fillStyle = color;
                    ctx.beginPath();
                    ctx.arc(x, y, th / 2, 0, Math.PI * 2);
                    ctx.fill();
                }

                if (empty > 0.0 && empty < 1.0) capAt(empty, dark);

                // F / E labels
                const labelR = rOut + 18;
                const angF = startRad;
                const angE = startRad + sweepRad;

                ctx.globalAlpha = theme?.isNight ? 0.90 : 0.75;
                ctx.fillStyle = theme?.text ?? "white";
                ctx.font = '700 16px "DejaVu Sans Mono","Noto Sans Mono",monospace';
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                ctx.fillText("F", cx + Math.cos(angF) * labelR, cy + Math.sin(angF) * labelR);
                ctx.fillText("E", cx + Math.cos(angE) * labelR, cy + Math.sin(angE) * labelR);

                ctx.restore();
            }
        }

        // ---- Rim (optional) ----
        Canvas {
            id: rimCanvas
            visible: false
            anchors.fill: parent
        }
    }

    // ===== Glass / vignette (non-breathing) =====
    Canvas {
        id: innerShadow
        anchors.fill: parent
        z: 50
        opacity: 0.7

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const rOuter = width * 0.46;
            const rInner = width * 0.20;

            const a = 0.10 + 0.35 * root.depth;
            const g = ctx.createRadialGradient(cx, cy, rInner, cx, cy, rOuter);
            g.addColorStop(0.0, "rgba(0,0,0,0)");
            g.addColorStop(0.8, `rgba(0,0,0,${a})`);
            g.addColorStop(1.0, `rgba(0,0,0,${a * 1.25})`);

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

        // Bind warnings to BBB truth with stale gating.
        // If link is stale, show nothing rather than inventing warnings.
        warnDoor:   root.linkOk && !!root.vehicleState && root.vehicleState.warnDoor
        warnCharge: root.linkOk && !!root.vehicleState && root.vehicleState.warnCharge
        warnBrake:  root.linkOk && !!root.vehicleState && root.vehicleState.warnBrake
        warnOil:    root.linkOk && !!root.vehicleState && root.vehicleState.warnOil

        // Not implemented on BBB yet in this step; keep false.
        warnCheckEngine: false
        warnAT: false
        warnFuelLow: false

        // Drivetrain is currently UI-only in your mock.
        // Keep deterministic defaults until BBB exports real fields.
        drivetrainMode: ""
        transferLock: false
    }
}
