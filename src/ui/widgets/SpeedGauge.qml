import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 420
    height: 420

    // Pass the theme object in from Main.qml
    property var theme

    // ===== Public API (raw input) =====
    property real speed: 0
    property real maxSpeed: 180

    // ===== Smoothed value (what we render) =====
    property real displaySpeed: 0

    // Tuning (OEM feel)
    property real response: 10.0
    property real maxStepPerFrame: 10.0

    // Depth controls (rim line around gauge)
    property real rimDepth: 1.0      // 0.0..2.0 (try 1.2 to 1.6)
    property bool overSpeed: speedInt >= 116

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)

    
    // ===== Depth effect (more depth as speed rises) =====
    // Global depth intensity multiplier
    property real depthK: 1.0

    property real depthTargetSpeed: 120

    readonly property real depthProgress: clamp(displaySpeed / depthTargetSpeed, 0, 1)
    readonly property real depth: depthProgress * depthK

    // Make the face recess more obvious
    readonly property real faceScale: 1.0 - 0.08 * depth
    readonly property real faceYOffset: 12 * depth


    function fallbackSpeedColor(s) {
        const v = Math.round(s);
        if (v <= 50)  return "#C7B7FF";
        if (v <= 115) return "#5E35B1";
        return "#FF3B3B";
    }

    readonly property color gaugeColor: (theme && theme.speedColor)
        ? theme.speedColor(displaySpeed)
        : fallbackSpeedColor(displaySpeed)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.55 : 0.32;
    }

    // Smooth speed -> displaySpeed
    Timer {
        id: smoothTimer
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const target = clamp(root.speed, 0, root.maxSpeed);
            const diff = target - root.displaySpeed;

            let step = diff * (1 - Math.exp(-root.response * dt));

            const cap = root.maxStepPerFrame;
            if (step > cap) step = cap;
            if (step < -cap) step = -cap;

            root.displaySpeed += step;

            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
            rimCanvas.requestPaint();
        }
    }
    // ===== Gauge face (scaled/sunk for depth) =====
    Item {
        id: face
        z: 30
        anchors.fill: parent
        transformOrigin: Item.Center

        scale: root.faceScale
        y: root.faceYOffset



    // Tick marks
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

            for (let v = 0; v <= root.maxSpeed; v += 10) {
                const t = v / root.maxSpeed;
                const a = startRad + sweepRad * t;
                const major = (v % 20 === 0);

                ctx.beginPath();
                ctx.strokeStyle = Qt.rgba(
                    root.gaugeColor.r, root.gaugeColor.g, root.gaugeColor.b,
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

    // Tapered arc
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
            const endRad = startRad + (root.sweepAngleDeg * root.progress) * Math.PI / 180;

            for (let i = 0; i < 60; i++) {
                const t0 = i / 60;
                const t1 = (i + 1) / 60;

                ctx.beginPath();
                ctx.strokeStyle = root.gaugeColor;
                ctx.lineCap = "round";
                ctx.lineWidth = 6 + (26 - 6) * t1;

                ctx.arc(cx, cy, r,
                        startRad + (endRad - startRad) * t0,
                        startRad + (endRad - startRad) * t1);
                ctx.stroke();
            }
        }
    }

    // ===== "Depth line" around the gauge (rim highlight + shadow) =====
    Canvas {
        id: rimCanvas
        visible: false
        anchors.fill: parent
        opacity: 1.0

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const d = Math.max(0.0, Math.min(2.0, root.rimDepth));
            const cx = width / 2;
            const cy = height / 2;

            // Place this just outside your ticks/arc so it reads like a bezel line.
            const rOuter = width * 0.465;
            const rimW = 6 + 8 * d;

            const aHi = 0.16 + 0.24 * d;   // highlight strength
            const aSh = 0.18 + 0.32 * d;   // shadow strength

            ctx.save();
            ctx.globalCompositeOperation = "source-over";

            // Soft highlight arc (top-left quadrant-ish)
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter - rimW * 0.35, (-140 * Math.PI)/180, (20 * Math.PI)/180);
            ctx.strokeStyle = "rgba(255,255,255," + aHi + ")";
            ctx.lineWidth = rimW;
            ctx.lineCap = "round";
            ctx.stroke();

            // Shadow arc (bottom-right quadrant-ish)
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter - rimW * 0.35, (40 * Math.PI)/180, (220 * Math.PI)/180);
            ctx.strokeStyle = "rgba(0,0,0," + aSh + ")";
            ctx.lineWidth = rimW;
            ctx.lineCap = "round";
            ctx.stroke();

            // Inner rim separator (plane separation)
            ctx.beginPath();
            ctx.arc(cx, cy, width * 0.33, 0, Math.PI * 2);
            ctx.strokeStyle = "rgba(0,0,0," + (0.10 + 0.20 * d) + ")";
            ctx.lineWidth = 2;
            ctx.stroke();

            ctx.restore();
        }
    }

    // Centre number
    Text {
        id: speedText
        z: 50
        anchors.centerIn: parent
        text: root.speedInt
        font.pixelSize: 120
        font.family: "Menlo"
        font.letterSpacing: 1
        color: root.gaugeColor
        opacity:  1.0

        SequentialAnimation on opacity {
            id: flashAnim
            running: root.overSpeed
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: 90 }
            NumberAnimation { to: 1.0; duration: 90 }
        }

    }
    }

    // Ensure we snap back after overspeed stops
    onOverSpeedChanged: {
        if (!overSpeed) speedText.opacity = 1.0;
    }
    // ===== Inner shadow / glass vignette (depth) =====
    Canvas {
        id: innerShadow
        visible: true
        z: 10
        anchors.fill: parent
        opacity: 0.70
        // repaint when the value changes
        Connections {
            target: root
            function onProgressChanged() { innerShadow.requestPaint(); }
        }
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;

            // Shadow ring sits just inside the tick radius
            const rOuter = width * 0.46;
            const rInner = width * 0.08;   // pulls the vignette closer to centre

            // Depth-controlled alpha
            const a = 0.14 + 0.55 * root.depth;  // deeper, more noticeable   // 0.10..0.45
            const a2 = 0.04 + 0.18 * root.depth;  // subtle highlight

            // Inner shadow (dark vignette)
            let g = ctx.createRadialGradient(cx, cy, rInner, cx, cy, rOuter);
            g.addColorStop(0.00, "rgba(0,0,0,0.00)");
            g.addColorStop(0.55, "rgba(0,0,0,0.00)");
            g.addColorStop(0.78, "rgba(0,0,0," + a + ")");
            g.addColorStop(1.00, "rgba(0,0,0," + (a * 1.25) + ")");

            ctx.fillStyle = g;
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter, 0, Math.PI * 2);
            ctx.arc(cx, cy, rInner, 0, Math.PI * 2, true);
            ctx.closePath();
            ctx.fill("evenodd");

            // A very soft inner highlight ring for "glass"
            let h = ctx.createRadialGradient(cx, cy, rInner, cx, cy, rOuter);
            h.addColorStop(0.00, "rgba(255,255,255,0.00)");
            h.addColorStop(0.65, "rgba(255,255,255,0.00)");
            h.addColorStop(0.90, "rgba(255,255,255," + a2 + ")");
            h.addColorStop(1.00, "rgba(255,255,255,0.00)");

            ctx.fillStyle = h;
            ctx.beginPath();
            ctx.arc(cx, cy, rOuter, 0, Math.PI * 2);
            ctx.arc(cx, cy, rInner, 0, Math.PI * 2, true);
            ctx.closePath();
            ctx.fill("evenodd");
        }
    }


    // Repaint if the theme flips day/night
    Connections {
        target: theme
        function onIsNightChanged() {
            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
            rimCanvas.requestPaint();
        }
    }
}
