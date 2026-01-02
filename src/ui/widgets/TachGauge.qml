import QtQuick 2.15

Item {
    id: root
    width: 420
    height: 420

    // Pass the theme object in from Main.qml
    property var theme

    // Public API
    property real rpm: 0

    // Smoothed RPM
    property real displayRpm: 0

    // Limits
    property int maxRpm: 6500
    property int redlineStart: 5000

    // Smoothing
    property real response: 12.0
    property real maxStepPerFrame: 350.0

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real progress: clamp(displayRpm / maxRpm, 0, 1)
    readonly property int rpmInt: Math.round(displayRpm)

    function fallbackRpmColor(v) {
        return (v >= redlineStart) ? "#FF3B3B" : "#5E35B1";
    }

    readonly property color gaugeColor: (theme && theme.rpmColor)
        ? theme.rpmColor(displayRpm, redlineStart)
        : fallbackRpmColor(displayRpm)

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.55 : 0.32;
    }
    // Smooth rpm -> displayRpm
    Timer {
        id: smoothTimer
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const target = clamp(root.rpm, 0, root.maxRpm);
            const diff = target - root.displayRpm;

            let step = diff * (1 - Math.exp(-root.response * dt));

            const cap = root.maxStepPerFrame;
            if (step > cap) step = cap;
            if (step < -cap) step = -cap;

            root.displayRpm += step;

            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
        }
    }

    // Tick marks (tach style)
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

    // Tapered arc (pearl depth)
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

    // Centre number + label
    Item {
        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -6
            text: root.rpmInt
            font.pixelSize: 86
    font.family: "Menlo"
            font.letterSpacing: 1
            color: root.gaugeColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.verticalCenter
            anchors.topMargin: 62
            text: "RPM"
            font.pixelSize: 26
    font.family: "Menlo"
            color: (theme && theme.text) ? theme.text : "white"
            opacity: (theme && theme.isNight !== undefined) ? (theme.isNight ? 0.70 : 0.85) : 0.75
        }
    }

    // Repaint if day/night flips
    Connections {
        target: theme
        function onIsNightChanged() {
            ticksCanvas.requestPaint();
            arcCanvas.requestPaint();
        }
    }
}
