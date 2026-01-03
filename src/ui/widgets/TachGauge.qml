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
                            ctx.font = "600 18px Menlo";
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

        // ---- Rim (optional) ----
        Canvas {
            id: rimCanvas
            visible: false
            anchors.fill: parent
        }
    }


    // ===== Center Fuel (debug text) =====
    Column {
        anchors.centerIn: parent
        width: parent.width * 0.32
        z: 45
        spacing: 2

        Text {
            text: "FUEL"
            font.pixelSize: 14
            font.family: "Menlo"
            color: theme?.text ?? "white"
            opacity: theme?.isNight ? 0.80 : 0.65
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }

        Text {
            text: root.fuelInt + "%"
            font.pixelSize: 44
            font.family: "Menlo"
            font.letterSpacing: 1
            color: root.lowFuel ? (theme?.danger ?? "#FF3B3B") : (theme?.pearlHigh ?? root.gaugeColor)
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
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
}
