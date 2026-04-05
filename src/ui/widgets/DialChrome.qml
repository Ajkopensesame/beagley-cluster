import QtQuick 2.15

Item {
    id: root

    property var theme
    property string effectLevel: "high"
    property color gaugeColor: "white"
    property color chromeColor: gaugeColor
    property real progress: 0.0
    property real maxValue: 100
    property real startAngleDeg: 225
    property real sweepAngleDeg: 210
    property real minorStep: 10
    property real majorStep: 20
    property real labelStep: 20
    property real labelStart: 20
    property real labelDivisor: 1

    property real tickOuterFactor: 0.425
    property real arcRadiusFactor: 0.405
    property real minorTickLength: 12
    property real majorTickLength: 26
    property real minorTickWidth: 3
    property real majorTickWidth: 5
    property real labelInset: 58
    property int labelFontSize: 20
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    function colorWithAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function blendToward(c, target, t, a) {
        return Qt.rgba(
            lerp(c.r, target.r, t),
            lerp(c.g, target.g, t),
            lerp(c.b, target.b, t),
            a
        );
    }

    function tickAlpha(major) {
        if (theme && theme.tickAlpha) return theme.tickAlpha(major);
        return major ? 0.72 : 0.42;
    }

    function labelForValue(v) {
        return String(Math.round(v / Math.max(1e-6, labelDivisor)));
    }

    function requestStaticPaint() {
        ticksCanvas.requestPaint();
        labelCanvas.requestPaint();
    }

    function requestDynamicPaint() {
        arcCanvas.requestPaint();
    }

    onThemeChanged: requestStaticPaint()
    onGaugeColorChanged: requestDynamicPaint()
    onChromeColorChanged: requestStaticPaint()
    onProgressChanged: requestDynamicPaint()
    onMaxValueChanged: {
        requestStaticPaint()
        requestDynamicPaint()
    }
    onStartAngleDegChanged: {
        requestStaticPaint()
        requestDynamicPaint()
    }
    onSweepAngleDegChanged: {
        requestStaticPaint()
        requestDynamicPaint()
    }
    onMinorStepChanged: requestStaticPaint()
    onMajorStepChanged: requestStaticPaint()
    onLabelStepChanged: requestStaticPaint()
    onLabelStartChanged: requestStaticPaint()
    onLabelDivisorChanged: requestStaticPaint()
    onWidthChanged: {
        requestStaticPaint()
        requestDynamicPaint()
    }
    onHeightChanged: {
        requestStaticPaint()
        requestDynamicPaint()
    }

    Component.onCompleted: {
        requestStaticPaint()
        requestDynamicPaint()
    }

    Canvas {
        id: ticksCanvas
        anchors.fill: parent
        z: 10
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const rOuter = width * root.tickOuterFactor;
            const rInnerMinor = rOuter - root.minorTickLength;
            const rInnerMajor = rOuter - root.majorTickLength;

            const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
            const sweepRad = root.sweepAngleDeg * Math.PI / 180;

            for (let v = 0; v <= root.maxValue + 1e-6; v += root.minorStep) {
                const t = v / root.maxValue;
                const a = startRad + sweepRad * t;
                const major = Math.abs(v % root.majorStep) < 1e-6;

                ctx.beginPath();
                ctx.strokeStyle = Qt.rgba(
                    root.chromeColor.r,
                    root.chromeColor.g,
                    root.chromeColor.b,
                    root.tickAlpha(major)
                );
                ctx.lineWidth = major ? root.majorTickWidth : root.minorTickWidth;
                ctx.lineCap = "round";

                const rInner = major ? rInnerMajor : rInnerMinor;
                ctx.moveTo(cx + Math.cos(a) * rInner, cy + Math.sin(a) * rInner);
                ctx.lineTo(cx + Math.cos(a) * rOuter, cy + Math.sin(a) * rOuter);
                ctx.stroke();
            }
        }
    }

    Canvas {
        id: labelCanvas
        anchors.fill: parent
        z: 30
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const rOuter = width * root.tickOuterFactor;
            const rLabel = rOuter - root.labelInset;
            const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
            const sweepRad = root.sweepAngleDeg * Math.PI / 180;
            const fontFamily = (root.theme && root.theme.fontMono) ? root.theme.fontMono : "monospace";

            ctx.save();
            ctx.fillStyle = "white";
            ctx.font = "700 " + root.labelFontSize + "px " + fontFamily;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";

            for (let v = root.labelStart; v <= root.maxValue + 1e-6; v += root.labelStep) {
                const t = v / root.maxValue;
                const a = startRad + sweepRad * t;
                ctx.fillText(
                    root.labelForValue(v),
                    cx + Math.cos(a) * rLabel,
                    cy + Math.sin(a) * rLabel
                );
            }
            ctx.restore();
        }
    }

    Canvas {
        id: arcCanvas
        anchors.centerIn: parent
        width: parent.width * (root.lowEffectMode ? 0.42 : 1.0)
        height: parent.height * (root.lowEffectMode ? 0.42 : 1.0)
        z: 20
        scale: root.lowEffectMode ? (1.0 / 0.42) : 1.0
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const r = width * root.arcRadiusFactor;
            const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
            const endRad = startRad + root.sweepAngleDeg * root.clamp(root.progress, 0, 1) * Math.PI / 180;
            const fullEndRad = startRad + root.sweepAngleDeg * Math.PI / 180;
            const base = root.gaugeColor;
            const bright = root.blendToward(base, Qt.color("#FFFFFF"), 0.34, 0.98);
            const hotEdge = root.blendToward(base, Qt.color("#FFFFFF"), 0.14, 0.74);

            ctx.beginPath();
            ctx.strokeStyle = root.colorWithAlpha(base, 0.06);
            ctx.lineCap = "round";
            ctx.lineWidth = root.lowEffectMode ? 16 : 30;
            ctx.arc(cx, cy, r, startRad, fullEndRad);
            ctx.stroke();

            if (root.lowEffectMode) {
                ctx.beginPath();
                ctx.strokeStyle = root.colorWithAlpha(bright, 0.92);
                ctx.lineCap = "round";
                ctx.lineWidth = 8;
                ctx.arc(cx, cy, r, startRad, endRad);
                ctx.stroke();
            } else {
                ctx.beginPath();
                ctx.strokeStyle = root.colorWithAlpha(base, 0.16);
                ctx.lineCap = "round";
                ctx.lineWidth = 24;
                ctx.arc(cx, cy, r, startRad, endRad);
                ctx.stroke();

                const coreGrad = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r);
                coreGrad.addColorStop(0.0, root.colorWithAlpha(bright, 0.92));
                coreGrad.addColorStop(0.55, root.colorWithAlpha(base, 0.98));
                coreGrad.addColorStop(1.0, root.colorWithAlpha(hotEdge, 0.86));

                ctx.beginPath();
                ctx.strokeStyle = root.colorWithAlpha(base, 0.32);
                ctx.lineCap = "round";
                ctx.lineWidth = 16;
                ctx.arc(cx, cy, r, startRad, endRad);
                ctx.stroke();

                for (let i = 0; i < 64; i++) {
                    const t0 = i / 64;
                    const t1 = (i + 1) / 64;
                    ctx.beginPath();
                    ctx.strokeStyle = coreGrad;
                    ctx.lineCap = "round";
                    ctx.lineWidth = 6 + (18 - 6) * t1;
                    ctx.arc(
                        cx, cy, r,
                        startRad + (endRad - startRad) * t0,
                        startRad + (endRad - startRad) * t1
                    );
                    ctx.stroke();
                }
            }

            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordPaint("gauge.dialArc")
        }
    }
}
