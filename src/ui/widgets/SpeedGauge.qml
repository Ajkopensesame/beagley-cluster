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
        if (gg === "N") return "#FFC107";          // Neutral: amber
        if (gg === "P") return pearlLow;           // Park: light purple
        if (gg === "D") return pearlLow;           // Drive: light purple
        if (gg === "2") return pearlHigh;          // 2: darker purple
        if (gg === "1") return Qt.darker(pearlHigh, 1.35); // 1: darkest purple

        return textCol;
    }
    // =======================================
    width: 420
    height: 420

    // Theme from Main.qml
    property var theme


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

    readonly property real progress: clamp(displaySpeed / maxSpeed, 0, 1)
    readonly property int speedInt: Math.round(displaySpeed)

    // Coolant normalized 0..1 (C -> H)
    readonly property real coolantNorm: clamp(
        (displayCoolantC - coolantColdC) / Math.max(1e-6, (coolantHotC - coolantColdC)),
        0, 1
    )

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

    // Smooth animation
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0;

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

            ticksCanvas.requestPaint();
            labelCanvas.requestPaint();
            arcCanvas.requestPaint();
            coolantArcCanvas.requestPaint();
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
                ctx.font = "700 18px DejaVu Sans Mono";
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

        // Speed arc
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
                const thickStart = 26;   // wide end (H side)
                const thickEnd   = 3;    // point end (C side)
                const segments   = 90;

                ctx.save();

                const eps = 0.0;  // seam-gap disabled (caps are now opaque)
                ctx.globalAlpha = theme?.isNight ? 0.88 : 0.72;

                const baseDark = (theme?.pearlHigh ?? root.gaugeColor);

                function drawBand(tFrom, tTo, colorFnOrColor) {
                    for (let i = 0; i < segments; i++) {
                        const u0 = i / segments;
                        const u1 = (i + 1) / segments;

                        if (u0 >= tTo) break;

                        const v0 = Math.max(u0, tFrom);
                        const v1 = Math.min(u1, tTo);
                        if (v1 <= v0) continue;

                        const th  = thickStart + (thickEnd - thickStart) * v1;
                        const rIn = rOut - th;

                        const a0 = startRad + sweepRad * v0;
                        const a1 = startRad + sweepRad * v1;

                        const col = (typeof colorFnOrColor === "function")
                            ? colorFnOrColor(v1)
                            : colorFnOrColor;

                        ctx.fillStyle = col;

                        ctx.beginPath();
                        ctx.arc(cx, cy, rOut, a0, a1, false);
                        ctx.arc(cx, cy, rIn,  a1, a0, true);
                        ctx.closePath();
                        ctx.fill();
                    }
                }

                // Base band (subtle pearl layer)
                drawBand(0.0, 1.0, baseDark);

                // Fill from C -> H.
                // Arc param: 0 at H, 1 at C. Coolant norm: 0 at C, 1 at H.
                // Therefore filled region is [1 - coolantNorm, 1.0].
                const tStartFill = 1.0 - root.coolantNorm;

                drawBand(tStartFill, 1.0, function(t) {
                    // t=1 (C) -> cold (0), t=0 (H) -> hot (1)
                    const rampT = 1.0 - t;
                    return root.coolantRampColor(rampT);
                });

                // Moving boundary cap
                function capAt(t, color) {
                    const th = thickStart + (thickEnd - thickStart) * t;
                    const rr = rOut - th / 2;
                    const ang = startRad + sweepRad * t;
                    const x = cx + Math.cos(ang) * rr;
                    const y = cy + Math.sin(ang) * rr;

                ctx.save();
                ctx.globalAlpha = 1.0;  // opaque caps to avoid blending
                    ctx.fillStyle = color;
                    ctx.beginPath();
                    ctx.arc(x, y, th/2, 0, Math.PI * 2);
                    ctx.fill();
                ctx.restore();
                }

                if (tStartFill > 0.0 && tStartFill < 1.0) {
                    capAt(tStartFill, root.coolantRampColor(1.0 - tStartFill));
                }


                // Rounded physical endpoint caps (match Tach fuel arc style)
                // t=0.0 is the H end (wide), t=1.0 is the C end (point)
                // Labels pinned to endpoints
                const labelR = rOut + 18;
                const angH = startRad;
                const angC = startRad + sweepRad;

                ctx.globalAlpha = theme?.isNight ? 0.90 : 0.75;
                ctx.fillStyle = theme?.text ?? "white";
                ctx.font = "700 16px DejaVu Sans Mono";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                ctx.fillText("H", cx + Math.cos(angH) * labelR, cy + Math.sin(angH) * labelR);
                ctx.fillText("C", cx + Math.cos(angC) * labelR, cy + Math.sin(angC) * labelR);

                ctx.restore();
            }
        }
    }

    // O/D indicator (Overdrive)
    
Item {
        id: odBadge
        z: 62

        visible: root.vehicleState && root.vehicleState.overdrive === true

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
            color: "#140A22"              // deep purple glass
            border.width: 2
            border.color: "#FFC107"       // amber rim
            opacity: 0.94
        }

        // Outer glow (soft)
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "transparent"
            border.width: 14
            border.color: "#2BFFC107"     // low-alpha amber glow
            opacity: 1.0
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
            font.family: "DejaVu Sans Mono"
            font.pixelSize: 36
            font.weight: Font.Bold
            font.letterSpacing: 4
            color: "#FFC107"
        }

        // Micro-pulse so it feels alive (subtle)
        SequentialAnimation on scale {
            running: odBadge.visible
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
        font.family: "DejaVu Sans Mono"
        font.letterSpacing: 1
        color: root.gaugeColor
    }


    // Gear indicator under speed (PRND21)
    Text {
        id: gearText
        z: 61

        // Pull from vehicleState mock if present; default to P
        text: (root.vehicleState && root.vehicleState.gear !== undefined) ? root.vehicleState.gear : "P"

        anchors.top: speedValueText.bottom
        anchors.topMargin: 8
        anchors.horizontalCenter: speedValueText.horizontalCenter

        font.pixelSize: 56
        font.family: "DejaVu Sans Mono"
        font.weight: Font.Bold
        font.letterSpacing: 4

        color: gearColorFor(text)
        opacity: 1.0

        // Reverse attention flash (ONLY when in R)
        SequentialAnimation on opacity {
            running: normGear(gearText.text) === "R"
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.20; duration: 220 }
            NumberAnimation { from: 0.20; to: 1.0; duration: 220 }
        }
    }

}
