import QtQuick 2.15

Item {
    id: root

    property var theme
    property string effectLevel: "high"
    property color gaugeColor: "white"
    property color chromeColor: gaugeColor
    property real progress: 0.0
    property real lavaPhase: 0.0
    property bool scaredHead: false
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
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property real lowEffectArcScale: 0.36
    readonly property real lowEffectArcTune: lowEffectArcScale / 0.42
    readonly property real sweepRad: root.sweepAngleDeg * Math.PI / 180
    readonly property real clampedProgress: root.clamp(root.progress, 0, 1)
    readonly property real arcRadiusOnScreen: width * root.arcRadiusFactor
    readonly property real headAngleRad: ((root.startAngleDeg - 90) * Math.PI / 180) + root.sweepRad * root.clampedProgress
    readonly property real headScreenRadius: root.lowEffectMode
        ? ((7.0 * root.lowEffectArcTune) / root.lowEffectArcScale)
        : 11.5
    readonly property bool headVisible: root.clampedProgress > 0.002

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

    Timer {
        interval: root.lowEffectMode ? 120 : 33
        running: root.effectLevel !== "off" && !root.lowEffectMode
        repeat: true
        onTriggered: {
            root.lavaPhase += interval / 1000.0
            arcCanvas.requestPaint()
        }
    }

    Canvas {
        id: ticksCanvas
        anchors.fill: parent
        z: 10
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject

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
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject

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
        width: parent.width * ((root.lowEffectMode && !root.embeddedSafeMode) ? root.lowEffectArcScale : 1.0)
        height: parent.height * ((root.lowEffectMode && !root.embeddedSafeMode) ? root.lowEffectArcScale : 1.0)
        z: 20
        scale: (root.lowEffectMode && !root.embeddedSafeMode) ? (1.0 / root.lowEffectArcScale) : 1.0
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
        antialiasing: !root.lowEffectMode && !root.embeddedSafeMode
        smooth: !root.lowEffectMode && !root.embeddedSafeMode

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const cx = width / 2;
            const cy = height / 2;
            const r = width * root.arcRadiusFactor;
            const startRad = (root.startAngleDeg - 90) * Math.PI / 180;
            const sweepRad = root.sweepRad;
            const progress = root.clampedProgress;
            const activeSweepRad = sweepRad * progress;
            const endRad = startRad + activeSweepRad;
            const fullEndRad = startRad + sweepRad;
            const base = root.gaugeColor;
            const bright = root.blendToward(base, Qt.color("#FFFFFF"), 0.34, 0.98);
            const phase = root.lavaPhase;

            function rgba(color, alpha) {
                return "rgba("
                    + Math.round(color.r * 255) + ","
                    + Math.round(color.g * 255) + ","
                    + Math.round(color.b * 255) + ","
                    + alpha + ")";
            }

            const neonCyan = Qt.color("#73F6FF");
            const neonLime = Qt.color("#9B5CFF");
            const neonPink = Qt.color("#FF4DFF");
            const neonOrange = Qt.color("#6E35FF");
            const neonYellow = Qt.color("#EAD7FF");

            function point(angle, radius) {
                return {
                    x: cx + Math.cos(angle) * radius,
                    y: cy + Math.sin(angle) * radius
                };
            }

            function buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale) {
                const sweep = toRad - fromRad;
                if (sweep <= 0.0001) return false;

                const outer = [];
                const inner = [];
                const steps = Math.max(10, Math.ceil(Math.abs(sweep) / (Math.PI / Math.max(24, segments))));
                for (let i = 0; i <= steps; i++) {
                    const t = i / steps;
                    const eased = 1 - Math.pow(1 - t, 1.35);
                    const angle = fromRad + sweep * t;
                    const widthAt = tailWidth + (headWidth - tailWidth) * eased;
                    outer.push(point(angle, r + widthAt / 2));
                    inner.push(point(angle, r - widthAt / 2));
                }

                ctx.beginPath();
                ctx.moveTo(outer[0].x, outer[0].y);
                for (let i = 1; i < outer.length; i++) {
                    ctx.lineTo(outer[i].x, outer[i].y);
                }
                for (let i = inner.length - 1; i >= 0; i--) {
                    ctx.lineTo(inner[i].x, inner[i].y);
                }
                ctx.closePath();

                const tail = point(fromRad, r);
                const head = point(toRad, r);
                const tailCap = Math.max(1.5, tailWidth * capScale);
                const headCap = Math.max(2, headWidth * capScale);
                ctx.moveTo(tail.x + tailCap, tail.y);
                ctx.arc(tail.x, tail.y, tailCap, 0, Math.PI * 2);
                ctx.moveTo(head.x + headCap, head.y);
                ctx.arc(head.x, head.y, headCap, 0, Math.PI * 2);
                return true;
            }

            function drawTaperedBand(fromRad, toRad, tailWidth, headWidth, color, alpha, segments, capScale) {
                ctx.save();
                if (!buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale)) {
                    ctx.restore();
                    return;
                }
                ctx.fillStyle = rgba(color, alpha);
                ctx.fill();
                ctx.restore();
            }

            function drawBlob(angle, radialOffset, radius, color, alpha, stretch, wobblePhase) {
                const p = point(angle, r + radialOffset);
                const grad = ctx.createRadialGradient(0, 0, radius * 0.10, 0, 0, radius);
                grad.addColorStop(0.00, rgba(root.blendToward(color, Qt.color("#FFFFFF"), 0.44, 1.0), alpha));
                grad.addColorStop(0.56, rgba(color, alpha * 0.46));
                grad.addColorStop(1.00, rgba(color, 0.0));

                ctx.save();
                ctx.translate(p.x, p.y);
                ctx.rotate(angle + Math.PI / 2 + Math.sin(wobblePhase) * 0.22);
                ctx.scale(stretch, 0.58);
                ctx.fillStyle = grad;
                ctx.beginPath();
                ctx.arc(0, 0, radius, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
            }

            function drawLavaBand(fromRad, toRad, tailWidth, headWidth, color, brightColor, segments, capScale, blobCount) {
                const sweep = toRad - fromRad;
                if (sweep <= 0.0001) return;

                ctx.save();
                if (!buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale)) {
                    ctx.restore();
                    return;
                }
                ctx.clip();

                const fill = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r);
                fill.addColorStop(0.00, rgba(neonCyan, root.lowEffectMode ? 0.54 : 0.46));
                fill.addColorStop(0.24, rgba(neonPink, root.lowEffectMode ? 0.72 : 0.62));
                fill.addColorStop(0.54, rgba(neonLime, root.lowEffectMode ? 0.88 : 0.76));
                fill.addColorStop(0.78, rgba(brightColor, root.lowEffectMode ? 0.76 : 0.64));
                fill.addColorStop(1.00, rgba(neonOrange, root.lowEffectMode ? 0.62 : 0.52));
                ctx.fillStyle = fill;
                ctx.fillRect(0, 0, width, height);

                for (let i = 0; i < blobCount; i++) {
                    const blobColor = [neonCyan, neonPink, neonLime, neonOrange, neonYellow][i % 5];
                    const u = (phase * (0.11 + i * 0.015) + i * 0.23) % 1.0;
                    const angle = fromRad + sweep * u;
                    const wobble = Math.sin(phase * (1.1 + i * 0.2) + i * 1.7);
                    const blobRadius = (root.lowEffectMode ? 5.0 : 9.0) + i * (root.lowEffectMode ? 1.0 : 1.35);
                    drawBlob(
                        angle,
                        wobble * (root.lowEffectMode ? 1.1 : 2.1),
                        blobRadius,
                        blobColor,
                        root.lowEffectMode ? 0.64 : 0.54,
                        1.55,
                        phase + i
                    );
                }
                ctx.restore();

                ctx.save();
                buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale);
                ctx.fillStyle = rgba(neonYellow, root.lowEffectMode ? 0.28 : 0.18);
                ctx.fill();
                ctx.restore();
            }

            ctx.beginPath();
            ctx.strokeStyle = rgba(base, 0.06);
            ctx.lineCap = "round";
            ctx.lineWidth = root.lowEffectMode ? (16 * root.lowEffectArcTune) : 30;
            ctx.arc(cx, cy, r, startRad, fullEndRad);
            ctx.stroke();

            if (progress > 0.002) {
                if (root.lowEffectMode) {
                    drawTaperedBand(startRad, endRad,
                                    3.5 * root.lowEffectArcTune,
                                    10.0 * root.lowEffectArcTune,
                                    base, 0.72, 28, 0.48);
                    drawTaperedBand(startRad, endRad,
                                    1.6 * root.lowEffectArcTune,
                                    4.6 * root.lowEffectArcTune,
                                    bright, 0.26, 16, 0.22);
                } else {
                    drawLavaBand(startRad, endRad, 5.5, 22, base, bright, 128, 0.50, 4);
                }
            }

            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordPaint("gauge.dialArc")
        }
    }

    GaugeArcHead {
        id: arcHead
        z: 24
        visible: root.headVisible
        lowEffectMode: root.lowEffectMode
        scared: root.scaredHead
        headRadius: root.headScreenRadius
        x: (root.width / 2) + Math.cos(root.headAngleRad) * root.arcRadiusOnScreen - (width / 2)
        y: (root.height / 2) + Math.sin(root.headAngleRad) * root.arcRadiusOnScreen - (height / 2)
    }
}
