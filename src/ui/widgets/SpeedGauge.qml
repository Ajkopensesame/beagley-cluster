import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 420
    height: 420

    // Theme from Main.qml
    property var theme

    // Public API
    property real speed: 0
    property real maxSpeed: 180

    // Smoothed value
    property real displaySpeed: 0

    // Tuning
    property real response: 10.0
    property real maxStepPerFrame: 10.0

    // Depth
    property real rimDepth: 1.0
    property bool overSpeed: speedInt >= 116

    readonly property real startAngleDeg: 225
    readonly property real sweepAngleDeg: 210

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)

    // Depth effect
    property real depthK: 1.0
    property real depthTargetSpeed: 120
    readonly property real depthProgress: clamp(displaySpeed / depthTargetSpeed, 0, 1)
    readonly property real depth: depthProgress * depthK

    readonly property real faceScale: 1.0 - 0.08 * depth
    readonly property real faceYOffset: 12 * depth

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
        return major ? 0.55 : 0.32;
    }

    // Smooth animation
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;
            const target = clamp(root.speed, 0, root.maxSpeed);
            const diff = target - root.displaySpeed;

            let step = diff * (1 - Math.exp(-root.response * dt));
            step = clamp(step, -root.maxStepPerFrame, root.maxStepPerFrame);

            root.displaySpeed += step;

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

        // Tick marks
        Canvas {
            id: ticksCanvas
            anchors.fill: parent
            z: 10

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0,0,width,height);

                const cx = width/2;
                const cy = height/2;
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
                        root.gaugeColor.r,
                        root.gaugeColor.g,
                        root.gaugeColor.b,
                        tickAlpha(major)
                    );
                    ctx.lineWidth = major ? 4 : 2.5;
                    ctx.lineCap = "round";

                    const rInner = major ? rInnerMajor : rInnerMinor;
                    ctx.moveTo(cx + Math.cos(a)*rInner, cy + Math.sin(a)*rInner);
                    ctx.lineTo(cx + Math.cos(a)*rOuter, cy + Math.sin(a)*rOuter);
                    ctx.stroke();
                }
            }
        }

        // ===== SPEED NUMBERS (20,40,60...) =====
        Canvas {
            id: labelCanvas
            anchors.fill: parent
            z: 30

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0,0,width,height);

                const cx = width/2;
                const cy = height/2;

                const rOuter = width * 0.42;
                const rLabel = rOuter - 52;

                const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
                const sweepRad = root.sweepAngleDeg * Math.PI / 180;

                ctx.save();
                ctx.fillStyle = "white";
                ctx.font = "700 18px Menlo";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                for (let v = 20; v <= root.maxSpeed; v += 20) {
                    const t = v / root.maxSpeed;
                    const a = startRad + sweepRad * t;
                    ctx.fillText(
                        String(v),
                        cx + Math.cos(a) * rLabel,
                        cy + Math.sin(a) * rLabel
                    );
                }
                ctx.restore();
            }
        }

        // Arc
        Canvas {
            id: arcCanvas
            anchors.fill: parent
            z: 20

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0,0,width,height);

                const cx = width/2;
                const cy = height/2;
                const r = width * 0.40;

                const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
                const endRad = startRad + root.sweepAngleDeg * root.progress * Math.PI / 180;

                for (let i=0;i<60;i++) {
                    const t0=i/60, t1=(i+1)/60;
                    ctx.beginPath();
                    ctx.strokeStyle = root.gaugeColor;
                    ctx.lineCap = "round";
                    ctx.lineWidth = 6 + (26-6)*t1;
                    ctx.arc(cx,cy,r,
                        startRad+(endRad-startRad)*t0,
                        startRad+(endRad-startRad)*t1);
                    ctx.stroke();
                }
            }
        }
    }

    // Centre speed
    Text {
        anchors.centerIn: parent
        z: 60
        text: root.speedInt
        font.pixelSize: 120
        font.family: "Menlo"
        font.letterSpacing: 1
        color: root.gaugeColor
    }
}
