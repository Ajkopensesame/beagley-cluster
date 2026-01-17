import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 420
    height: 420

    // Theme from Main.qml
    property var theme

    // Public API: fuel percent 0..100
    property real fuelPct: 100
    property real lowFuelPct: 12

    // Smoothed value
    property real displayFuel: 100

    // Smoothing tuning
    property real response: 10.0
    property real maxStepPerFrame: 8.0

    // Visual geometry (match speed/tach)
    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real fuelClamped: clamp(displayFuel, 0, 100)
    readonly property real progress: fuelClamped / 100.0
    readonly property int fuelInt: Math.round(fuelClamped)

    readonly property bool lowFuel: fuelClamped <= lowFuelPct

    // Depth effect (match SpeedGauge/TachGauge)
    property real depthK: 1.0
    readonly property real depth: progress * depthK
    readonly property real faceScale: 1.0 - 0.08 * depth
    readonly property real faceYOffset: 12 * depth

    function fallbackFuelColor(pct) {
        // High = pearlHigh, mid = pearlLow, low = danger
        if (pct <= lowFuelPct) return "#FF3B3B";
        if (pct <= 50) return "#C7B7FF";
        return "#5E35B1";
    }

    readonly property color gaugeColor: (theme && theme.fuelColor)
        ? theme.fuelColor(fuelClamped, lowFuelPct)
        : fallbackFuelColor(fuelClamped)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.55 : 0.32;
    }

    // Smooth animation
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const target = clamp(root.fuelPct, 0, 100);
            const diff = target - root.displayFuel;

            let step = diff * (1 - Math.exp(-root.response * dt));
            step = clamp(step, -root.maxStepPerFrame, root.maxStepPerFrame);

            root.displayFuel += step;

            ticksCanvas.requestPaint();
            labelCanvas.requestPaint();
            arcCanvas.requestPaint();
        }
    }

    // ===== Gauge face =====
    Item {
        anchors.fill: parent
        z: 30
        scale: root.faceScale
        y: root.faceYOffset

        // Tick marks (0..100 step 10, major every 20)
        Canvas {
            id: ticksCanvas
            anchors.fill: parent
            z: 10

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

                for (let v = 0; v <= 100; v += 10) {
                    const t = v / 100.0;
                    const a = startRad + sweepRad * t;
                    const major = (v % 20 === 0);

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
                }
            }
        }

        // Labels: E / 1/2 / F
        Canvas {
            id: labelCanvas
            anchors.fill: parent
            z: 30

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const cx = width / 2;
                const cy = height / 2;

                const rOuter = width * 0.42;
                const rLabel = rOuter - 52;

                const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
                const sweepRad = root.sweepAngleDeg * Math.PI / 180;

                function drawAt(t, text) {
                    const a = startRad + sweepRad * t;
                    ctx.fillText(
                        text,
                        cx + Math.cos(a) * rLabel,
                        cy + Math.sin(a) * rLabel
                    );
                }

                ctx.save();
                ctx.fillStyle = "white";
                ctx.font = "700 18px DejaVu Sans Mono";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                drawAt(0.0, "E");
                drawAt(0.5, "1/2");
                drawAt(1.0, "F");

                ctx.restore();
            }
        }

        // Arc (thickening segments)
        Canvas {
            id: arcCanvas
            anchors.fill: parent
            z: 20

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
    }

    // Center value: percent
    Text {
        anchors.centerIn: parent
        z: 60
        text: root.fuelInt + "%"
        font.pixelSize: 86
        font.family: "DejaVu Sans Mono"
        font.letterSpacing: 1
        color: root.gaugeColor
    }
}
