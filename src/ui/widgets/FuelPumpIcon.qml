import QtQuick 2.15

Item {
    id: root
    width: 140
    height: 140

    property var theme
    property real fuelPct: 100     // 0..100
    property real lowFuelPct: 12

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
    readonly property real level: clamp(fuelPct / 100.0, 0, 1)
    readonly property bool lowFuel: fuelPct <= lowFuelPct

    readonly property color outline: theme?.text ?? "white"
    readonly property color fillOn: lowFuel
        ? (theme?.danger ?? "#FF3B3B")
        : (theme?.pearlHigh ?? "#5E35B1")
    readonly property color fillOff: theme?.muted ?? "#404040"

    Canvas {
        id: c
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);

            const w = width, h = height;

            const stroke = Math.max(4, Math.round(w * 0.045));
            ctx.lineWidth = stroke;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";

            // --- Pump silhouette (single closed path) ---
            // We draw a pump body + hose + nozzle as one clipped region.
            // Everything inside this region is the "fuel".
            const bodyX = w * 0.22;
            const bodyY = h * 0.16;
            const bodyW = w * 0.42;
            const bodyH = h * 0.72;
            const r = Math.min(w, h) * 0.08;

            function roundRectPath(x, y, ww, hh, rr) {
                rr = Math.min(rr, ww/2, hh/2);
                ctx.beginPath();
                ctx.moveTo(x + rr, y);
                ctx.arcTo(x + ww, y, x + ww, y + hh, rr);
                ctx.arcTo(x + ww, y + hh, x, y + hh, rr);
                ctx.arcTo(x, y + hh, x, y, rr);
                ctx.arcTo(x, y, x + ww, y, rr);
                ctx.closePath();
            }

            function pumpPath() {
                // Body
                roundRectPath(bodyX, bodyY, bodyW, bodyH, r);

                // Hose + nozzle (added to same path)
                // Hose start (mid-right of body)
                const hx0 = bodyX + bodyW;
                const hy0 = bodyY + bodyH * 0.40;
                const hx1 = w * 0.78;
                const hy1 = h * 0.50;
                const nx  = w * 0.78;
                const ny  = h * 0.72;

                ctx.moveTo(hx0, hy0);
                ctx.bezierCurveTo(w * 0.72, h * 0.44, w * 0.82, h * 0.54, hx1, hy1);
                ctx.lineTo(nx, ny);

                // Small nozzle return to make it a closed-ish region for clipping.
                // (The stroke will define it visually; the clip region stays reasonable.)
                ctx.lineTo(nx - w * 0.06, ny);
                ctx.lineTo(nx - w * 0.06, hy1 + h * 0.02);
                ctx.closePath();
            }

            // ---- Clip to pump silhouette ----
            ctx.save();
            pumpPath();
            ctx.clip();

            // ---- Vertical fill inside clip (BOTTOM -> TOP) ----
            // Full background (empty)
            ctx.fillStyle = root.fillOff;
            ctx.fillRect(0, 0, w, h);

            // Filled portion: starts at bottom and rises with level
            const fillH = h * root.level;
            const fillY = h - fillH;

            ctx.fillStyle = root.fillOn;
            ctx.fillRect(0, fillY, w, fillH);

            ctx.restore();

            // ---- Outline stroke on top ----
            ctx.strokeStyle = root.outline;
            pumpPath();
            ctx.stroke();

            // ---- Optional small "window" outline (looks more like OEM icon) ----
            ctx.strokeStyle = root.outline;
            ctx.lineWidth = Math.max(3, Math.round(w * 0.030));
            const winX = bodyX + bodyW * 0.18;
            const winY = bodyY + bodyH * 0.16;
            const winW = bodyW * 0.64;
            const winH = bodyH * 0.22;
            roundRectPath(winX, winY, winW, winH, r * 0.6);
            ctx.stroke();
        }
    }

    // repaint when values change
    onFuelPctChanged: c.requestPaint()
    onWidthChanged: c.requestPaint()
    onHeightChanged: c.requestPaint()
}
