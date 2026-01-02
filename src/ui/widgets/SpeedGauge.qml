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

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)

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
        }
    }
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

    // Centre number
    Text {
        anchors.centerIn: parent
        text: root.speedInt
        font.pixelSize: 120
    font.family: "Menlo"
        font.letterSpacing: 1
        color: root.gaugeColor
        opacity: 1.0

        SequentialAnimation on opacity {
            running: root.speedInt >= 116
            loops: Animation.Infinite
            NumberAnimation { to: 0.15; duration: 90 }
            NumberAnimation { to: 1.0; duration: 90 }
        }

        onTextChanged: {
            if (root.speedInt < 116) opacity = 1.0;
        }
    }

    // Repaint if the theme flips day/night
    Connections {
        target: theme
        function onIsNightChanged() {
            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
        }
    }
}
