import QtQuick 2.15

Item {
    id: root

    // ===== Public API =====
    property real rpm: 0

    // Tuning / limits
    property int maxRpm: 6500
    property int greenMax: 2500
    property int amberMax: 5000

    // Visual sizing helper
    readonly property real sizePx: Math.min(width, height)

    // Fonts (use your existing qrc root aliases)
    FontLoader { id: oxReg;  source: "qrc:/Oxanium-Regular.ttf" }
    FontLoader { id: oxSemi; source: "qrc:/Oxanium-SemiBold.ttf" }

    // Zone color based on your thresholds:
    // 0–2500 green, 2501–5000 amber, 5000+ red
    function zoneColor(v) {
        if (v <= greenMax) return "#4CAF50";     // green
        if (v <= amberMax) return "#FFC107";     // amber
        return "#FF1744";                        // red
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset && ctx.reset(); // Qt 6 Canvas supports reset in some builds; safe no-op otherwise

            var w = width, h = height;
            ctx.clearRect(0, 0, w, h);

            // Guard against weird sizing
            if (w <= 2 || h <= 2) return;

            // Geometry
            var cx = w * 0.5;
            var cy = h * 0.52;                    // slight vertical bias like automotive clusters
            var r  = Math.min(w, h) * 0.40;       // radius
            var thickness = Math.max(10, r * 0.16);

            // Sweep angles (classic cluster arc)
            // Start ~225°, end ~-45° (i.e., 270° sweep)
            var start = Math.PI * 1.25;           // 225°
            var end   = Math.PI * -0.25;          // -45°
            var sweep = end - start;

            // Normalize value
            var v = root.clamp(root.rpm, 0, root.maxRpm);
            var t = (root.maxRpm > 0) ? (v / root.maxRpm) : 0;
            t = root.clamp(t, 0, 1);

            // Colors
            var bgArc = "rgba(255,255,255,0.12)";
            var valArc = root.zoneColor(v);

            // Background arc
            ctx.save();
            ctx.lineCap = "round";
            ctx.lineWidth = thickness;
            ctx.strokeStyle = bgArc;
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, end, false);
            ctx.stroke();
            ctx.restore();

            // Value arc
            var valEnd = start + (sweep * t);
            ctx.save();
            ctx.lineCap = "round";
            ctx.lineWidth = thickness;
            ctx.strokeStyle = valArc;
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, valEnd, false);
            ctx.stroke();
            ctx.restore();

            // Optional subtle inner ring (matches “premium” look)
            ctx.save();
            ctx.lineWidth = Math.max(2, thickness * 0.18);
            ctx.strokeStyle = "rgba(255,255,255,0.10)";
            ctx.beginPath();
            ctx.arc(cx, cy, r - thickness * 0.70, start, end, false);
            ctx.stroke();
            ctx.restore();

            // Ticks (sparse, clean)
            // Major every 1000 RPM, minor every 500 RPM
            function drawTick(angle, len, alpha) {
                var x1 = cx + Math.cos(angle) * (r - thickness * 0.10);
                var y1 = cy + Math.sin(angle) * (r - thickness * 0.10);
                var x2 = cx + Math.cos(angle) * (r - thickness * 0.10 - len);
                var y2 = cy + Math.sin(angle) * (r - thickness * 0.10 - len);
                ctx.strokeStyle = "rgba(255,255,255," + alpha + ")";
                ctx.beginPath();
                ctx.moveTo(x1, y1);
                ctx.lineTo(x2, y2);
                ctx.stroke();
            }

            ctx.save();
            ctx.lineWidth = Math.max(2, thickness * 0.12);
            var majors = Math.floor(root.maxRpm / 1000);
            for (var i = 0; i <= majors; i++) {
                var rpmMajor = i * 1000;
                var tt = rpmMajor / root.maxRpm;
                var a = start + sweep * tt;

                // Major tick
                drawTick(a, thickness * 0.55, 0.55);

                // Minor tick between majors (500)
                if (i < majors) {
                    var rpmMinor = rpmMajor + 500;
                    var ttm = rpmMinor / root.maxRpm;
                    var am = start + sweep * ttm;
                    drawTick(am, thickness * 0.32, 0.30);
                }
            }
            ctx.restore();

            // Numbers: big RPM value
            ctx.save();
            var rpmText = Math.round(v).toString();
            ctx.fillStyle = valArc;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.font = Math.round(root.sizePx * 0.16) + "px " + (oxSemi.name || "sans-serif");
            ctx.fillText(rpmText, cx, cy + r * 0.10);
            ctx.restore();

            // Label: RPM
            ctx.save();
            ctx.fillStyle = "rgba(255,255,255,0.70)";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.font = Math.round(root.sizePx * 0.06) + "px " + (oxReg.name || "sans-serif");
            ctx.fillText("RPM", cx, cy + r * 0.28);
            ctx.restore();

            // Title: TACH
            ctx.save();
            ctx.fillStyle = "rgba(255,255,255,0.55)";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.font = Math.round(root.sizePx * 0.055) + "px " + (oxReg.name || "sans-serif");
            ctx.fillText("TACH", cx, cy - r * 0.55);
            ctx.restore();
        }
    }

    // Repaint smoothly when rpm changes or size changes
    onRpmChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
