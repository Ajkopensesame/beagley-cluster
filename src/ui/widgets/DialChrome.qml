import QtQuick 2.15
import BeagleY 1.0

Item {
    id: root

    property var theme
    property string effectLevel: "high"
    property string detailMode: "safe"
    property color gaugeColor: "white"
    property color chromeColor: gaugeColor
    property real progress: 0.0
    property real lavaPhase: 0.0
    property bool scaredHead: false
    property bool showArcHead: true
    // Slice 6: lava/matrix accent over NativeGaugeInstrument — no ticks/labels/track
    property bool accentOverlayMode: false
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
    readonly property bool embeddedHighEffectBudgetMode: embeddedSafeMode && effectLevel === "high"
    readonly property bool richDetailMode: detailMode === "rich"
    // Slice 6: lava is primary night accent. On Linux/BeagleY use embedded high-budget path
    // instead of permanently disabling lava via embeddedSafeMode.
    readonly property bool lavaAnimationEnabled: effectLevel === "high" && !lowEffectMode
        && (richDetailMode || accentOverlayMode || embeddedHighEffectBudgetMode)
        && (!embeddedSafeMode || embeddedHighEffectBudgetMode || accentOverlayMode)
    readonly property bool staticArcMode: !lavaAnimationEnabled
    // Embedded/drive: scene-graph magma only — never ~10Hz Canvas crust.
    // Desktop show keeps Canvas organic path when not embedded.
    readonly property bool sgMagmaMode: (lavaAnimationEnabled || accentOverlayMode) && embeddedSafeMode
    readonly property bool canvasMagmaMode: (lavaAnimationEnabled || accentOverlayMode) && !embeddedSafeMode
    readonly property real lowEffectArcScale: 0.36
    readonly property real lowEffectArcTune: lowEffectArcScale / 0.42
    // Embedded lava-lite: near-full canvas so arcs stay readable at arm's length;
    // cost cut comes from slower paint + one band, not half-res blur.
    readonly property real dynamicArcCanvasScale: embeddedHighEffectBudgetMode
        ? 1.0
        : ((root.lowEffectMode && !root.embeddedSafeMode) ? root.lowEffectArcScale : 1.0)
    readonly property real dynamicArcTune: dynamicArcCanvasScale < 1.0 ? dynamicArcCanvasScale : 1.0
    readonly property real progressRepaintThreshold: embeddedSafeMode
        ? 0.0
        : (lowEffectMode
        ? 0.004
        : (embeddedHighEffectBudgetMode ? 0.012 : 0.0))
    readonly property real sweepRad: root.sweepAngleDeg * Math.PI / 180
    readonly property real clampedProgress: root.clamp(root.progress, 0, 1)
    readonly property real arcRadiusOnScreen: width * root.arcRadiusFactor
    readonly property real headAngleRad: ((root.startAngleDeg - 90) * Math.PI / 180) + root.sweepRad * root.clampedProgress
    readonly property real headScreenRadius: root.lowEffectMode
        ? ((7.0 * root.lowEffectArcTune) / root.lowEffectArcScale)
        : 11.5
    readonly property bool headVisible: root.clampedProgress > 0.002
    property real lastPaintedProgress: -1.0
    property real paintedProgress: 0.0

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
        const force = arguments.length > 0 && arguments[0] === true;
        root.paintedProgress = root.clampedProgress;
        // SG magma: progress binds GaugeArcItem directly — no Canvas paints.
        if (root.sgMagmaMode) {
            root.lastPaintedProgress = root.clampedProgress;
            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordCounter("gauge.sgMagma")
            return;
        }
        if (!force
                && root.progressRepaintThreshold > 0
                && root.lastPaintedProgress >= 0
                && Math.abs(root.clampedProgress - root.lastPaintedProgress) < root.progressRepaintThreshold) {
            return;
        }
        root.lastPaintedProgress = root.clampedProgress;
        if (root.canvasMagmaMode)
            arcCanvas.requestPaint();
        if (typeof performanceMetrics !== "undefined" && performanceMetrics)
            performanceMetrics.recordCounter("gauge.nativeDialArc")
    }

    onThemeChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    // Native arcs bind color directly; progress changes drive geometry updates.
    onChromeColorChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    onProgressChanged: requestDynamicPaint()
    onMaxValueChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    onStartAngleDegChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    onSweepAngleDegChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    onMinorStepChanged: requestStaticPaint()
    onMajorStepChanged: requestStaticPaint()
    onLabelStepChanged: requestStaticPaint()
    onLabelStartChanged: requestStaticPaint()
    onLabelDivisorChanged: requestStaticPaint()
    onWidthChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }
    onHeightChanged: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }

    Component.onCompleted: {
        requestStaticPaint()
        requestDynamicPaint(true)
    }

    Timer {
        // SG magma: ~4Hz property crawl only (no Canvas). Desktop Canvas: ~30Hz.
        // Needle lag stays on MainV3 33ms clock — never hijack it for particles.
        interval: root.sgMagmaMode ? 250 : (root.lowEffectMode ? 120 : 33)
        running: root.effectLevel !== "off" && root.lavaAnimationEnabled
            && (root.sgMagmaMode || root.canvasMagmaMode)
        repeat: true
        onTriggered: {
            root.lavaPhase += interval / 1000.0
            if (root.canvasMagmaMode)
                root.requestDynamicPaint(true)
        }
    }

    Canvas {
        id: ticksCanvas
        anchors.fill: parent
        z: 10
        visible: !root.accentOverlayMode
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
        visible: !root.accentOverlayMode
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

    GaugeArcItem {
        anchors.fill: parent
        z: 20
        visible: !root.accentOverlayMode
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: 1.0
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.lowEffectMode ? 13 : 18
        color: root.colorWithAlpha(root.chromeColor, root.lowEffectMode ? 0.08 : 0.07)
        segments: root.lowEffectMode ? 32 : 48
        roundedCaps: false
    }

    GaugeArcItem {
        anchors.fill: parent
        z: 21
        visible: !root.accentOverlayMode
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: 1.0
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.lowEffectMode ? 5.5 : 7.0
        color: root.colorWithAlpha(root.chromeColor, root.lowEffectMode ? 0.26 : 0.30)
        segments: root.lowEffectMode ? 32 : 48
        roundedCaps: false
    }

    GaugeArcItem {
        anchors.fill: parent
        z: 22
        visible: !root.accentOverlayMode
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: 1.0
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.lowEffectMode ? 1.7 : 2.2
        color: root.colorWithAlpha(root.blendToward(root.chromeColor, Qt.color("#FFFFFF"), 0.28, 0.98), root.lowEffectMode ? 0.10 : 0.12)
        segments: root.lowEffectMode ? 24 : 36
        roundedCaps: false
    }

    GaugeArcItem {
        anchors.fill: parent
        z: 23
        visible: !root.accentOverlayMode && !root.lavaAnimationEnabled && root.paintedProgress > 0.002
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.paintedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.lowEffectMode ? 7.5 : 10.5
        color: root.colorWithAlpha(root.gaugeColor, root.lowEffectMode ? 0.78 : 0.84)
        segments: root.lowEffectMode ? 32 : 48
        roundedCaps: false
    }

    GaugeArcItem {
        anchors.fill: parent
        z: 24
        visible: false
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.paintedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.lowEffectMode ? 2.0 : 2.8
        color: root.colorWithAlpha(root.blendToward(root.gaugeColor, Qt.color("#FFFFFF"), 0.34, 0.98), root.lowEffectMode ? 0.22 : 0.26)
        segments: root.lowEffectMode ? 20 : 32
        roundedCaps: false
    }

    // ---- Scene-graph magma (embedded/drive): no Canvas crust ----
    // Stacked GaugeArcItem = orange body + amber mid + hot yellow core/tip.
    readonly property color _lavaOrange: (theme && theme.lavaOrange) ? theme.lavaOrange : Qt.color("#FF7A14")
    readonly property color _lavaAmber: (theme && theme.lavaAmber) ? theme.lavaAmber : Qt.color("#FFC028")
    readonly property color _lavaHot: (theme && theme.lavaHot) ? theme.lavaHot : Qt.color("#FFF2A8")
    readonly property color _lavaTrack: (theme && theme.lavaTrack) ? theme.lavaTrack : Qt.color("#2A2240")
    readonly property color _lavaRemainder: (theme && theme.lavaRemainder) ? theme.lavaRemainder : Qt.color("#1C1528")
    readonly property real _sgTipStart: root.clampedProgress > 0.002
        ? Math.max(0.0, root.clampedProgress - 0.10)
        : 0.0
    readonly property real _sgCoreStart: root.clampedProgress > 0.002
        ? Math.max(0.0, root.clampedProgress - 0.28)
        : 0.0
    // Slow crust gaps driven by lavaPhase (property-only; no Canvas)
    readonly property real _sgCrackU0: (lavaPhase * 0.07) % 1.0
    readonly property real _sgCrackU1: (_sgCrackU0 + 0.37) % 1.0

    GaugeArcItem {
        anchors.fill: parent
        z: 18
        visible: root.sgMagmaMode
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: 1.0
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 24 : 18
        color: root.colorWithAlpha(root._lavaTrack, 0.36)
        segments: 40
        roundedCaps: true
    }
    GaugeArcItem {
        anchors.fill: parent
        z: 18
        visible: root.sgMagmaMode
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: 1.0
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 8 : 6
        color: root.colorWithAlpha(root._lavaRemainder, 0.22)
        segments: 40
        roundedCaps: true
    }
    // Orange magma body
    GaugeArcItem {
        anchors.fill: parent
        z: 19
        visible: root.sgMagmaMode && root.clampedProgress > 0.002
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.clampedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 22 : 16
        color: root.colorWithAlpha(root._lavaOrange, 0.94)
        segments: 48
        roundedCaps: true
    }
    // Amber mid ribbon
    GaugeArcItem {
        anchors.fill: parent
        z: 19
        visible: root.sgMagmaMode && root.clampedProgress > 0.002
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.clampedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 12 : 9
        color: root.colorWithAlpha(root._lavaAmber, 0.78)
        segments: 48
        roundedCaps: true
    }
    // Hot yellow core (forward half)
    GaugeArcItem {
        anchors.fill: parent
        z: 20
        visible: root.sgMagmaMode && root.clampedProgress > 0.002
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: root._sgCoreStart
        endProgress: root.clampedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 8 : 6
        color: root.colorWithAlpha(root._lavaHot, 0.88)
        segments: 36
        roundedCaps: true
    }
    // Hotter yellow tip / head punch
    GaugeArcItem {
        anchors.fill: parent
        z: 21
        visible: root.sgMagmaMode && root.clampedProgress > 0.002
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: root._sgTipStart
        endProgress: root.clampedProgress
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 14 : 11
        color: root.colorWithAlpha(Qt.color("#FFF8D0"), 0.96)
        segments: 24
        roundedCaps: true
    }
    // Dark crust cracks (2 windows crawl with phase — SG only)
    GaugeArcItem {
        anchors.fill: parent
        z: 20
        visible: root.sgMagmaMode && root.clampedProgress > 0.08
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: Math.min(root.clampedProgress, root._sgCrackU0 * root.clampedProgress)
        endProgress: Math.min(root.clampedProgress, root._sgCrackU0 * root.clampedProgress + 0.055)
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 18 : 13
        color: root.colorWithAlpha(Qt.color("#0C0400"), 0.72)
        segments: 16
        roundedCaps: true
    }
    GaugeArcItem {
        anchors.fill: parent
        z: 20
        visible: root.sgMagmaMode && root.clampedProgress > 0.08
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: Math.min(root.clampedProgress, root._sgCrackU1 * root.clampedProgress)
        endProgress: Math.min(root.clampedProgress, root._sgCrackU1 * root.clampedProgress + 0.04)
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 10 : 7
        color: root.colorWithAlpha(Qt.color("#1A0800"), 0.55)
        segments: 16
        roundedCaps: true
    }
    // Ember flecks in cracks (amber punch through dark)
    GaugeArcItem {
        anchors.fill: parent
        z: 20
        visible: root.sgMagmaMode && root.clampedProgress > 0.08
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: Math.min(root.clampedProgress, root._sgCrackU0 * root.clampedProgress + 0.012)
        endProgress: Math.min(root.clampedProgress, root._sgCrackU0 * root.clampedProgress + 0.035)
        radiusFactor: root.arcRadiusFactor
        strokeWidth: root.embeddedHighEffectBudgetMode ? 5 : 4
        color: root.colorWithAlpha(root._lavaHot, 0.90)
        segments: 12
        roundedCaps: true
    }

    Canvas {
        id: arcCanvas
        anchors.centerIn: parent
        width: parent.width * root.dynamicArcCanvasScale
        height: parent.height * root.dynamicArcCanvasScale
        z: 20
        visible: root.canvasMagmaMode
        scale: root.dynamicArcCanvasScale < 1.0 ? (1.0 / root.dynamicArcCanvasScale) : 1.0
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
            const track = root.chromeColor;
            const bright = root.blendToward(base, Qt.color("#FFFFFF"), 0.34, 0.98);
            const trackBright = root.blendToward(track, Qt.color("#FFFFFF"), 0.28, 0.98);
            const phase = root.lavaPhase;

            function rgba(color, alpha) {
                return "rgba("
                    + Math.round(color.r * 255) + ","
                    + Math.round(color.g * 255) + ","
                    + Math.round(color.b * 255) + ","
                    + alpha + ")";
            }

            if (root.staticArcMode) {
                ctx.save();
                ctx.lineCap = "round";

                ctx.beginPath();
                ctx.strokeStyle = rgba(track, root.lowEffectMode ? 0.08 : 0.07);
                ctx.lineWidth = root.lowEffectMode ? (13 * root.lowEffectArcTune) : (18 * root.dynamicArcTune);
                ctx.arc(cx, cy, r, startRad, fullEndRad);
                ctx.stroke();

                ctx.beginPath();
                ctx.strokeStyle = rgba(track, root.lowEffectMode ? 0.26 : 0.30);
                ctx.lineWidth = root.lowEffectMode ? (5.5 * root.lowEffectArcTune) : (7.0 * root.dynamicArcTune);
                ctx.arc(cx, cy, r, startRad, fullEndRad);
                ctx.stroke();

                ctx.beginPath();
                ctx.strokeStyle = rgba(trackBright, root.lowEffectMode ? 0.10 : 0.12);
                ctx.lineWidth = root.lowEffectMode ? (1.7 * root.lowEffectArcTune) : (2.2 * root.dynamicArcTune);
                ctx.arc(cx, cy, r, startRad, fullEndRad);
                ctx.stroke();

                if (progress > 0.002) {
                    ctx.beginPath();
                    ctx.strokeStyle = rgba(base, root.lowEffectMode ? 0.78 : 0.84);
                    ctx.lineWidth = root.lowEffectMode ? (7.5 * root.lowEffectArcTune) : (10.5 * root.dynamicArcTune);
                    ctx.arc(cx, cy, r, startRad, endRad);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.strokeStyle = rgba(bright, root.lowEffectMode ? 0.22 : 0.26);
                    ctx.lineWidth = root.lowEffectMode ? (2.0 * root.lowEffectArcTune) : (2.8 * root.dynamicArcTune);
                    ctx.arc(cx, cy, r, startRad, endRad);
                    ctx.stroke();
                }

                ctx.restore();
                root.lastPaintedProgress = progress;

                if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                    performanceMetrics.recordPaint("gauge.dialArc")
                return;
            }

            // Skin v2 molten lava: hot yellow→orange core; magenta hairline tail only
            const lavaAmber = (root.theme && root.theme.lavaAmber) ? root.theme.lavaAmber : Qt.color("#FFC028");
            const lavaOrange = (root.theme && root.theme.lavaOrange) ? root.theme.lavaOrange : Qt.color("#FF7A14");
            const lavaMagenta = (root.theme && root.theme.lavaMagenta) ? root.theme.lavaMagenta : Qt.color("#C41848");
            const lavaHot = (root.theme && root.theme.lavaHot) ? root.theme.lavaHot : Qt.color("#FFF2A8");
            const lavaRemainder = (root.theme && root.theme.lavaRemainder) ? root.theme.lavaRemainder : Qt.color("#1C1528");
            const lavaTrack = (root.theme && root.theme.lavaTrack) ? root.theme.lavaTrack : Qt.color("#2A2240");
            const neonCyan = lavaAmber;
            const neonLime = lavaOrange;
            const neonPink = lavaMagenta;
            const neonOrange = lavaOrange;
            const neonYellow = lavaHot;

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
                const embeddedLite = root.embeddedHighEffectBudgetMode || root.accentOverlayMode;
                const showExtras = root.richDetailMode && !root.lowEffectMode && !root.embeddedHighEffectBudgetMode;

                // Embedded / accent: Image-canvas safe path — NO clip/tapered fill
                if (embeddedLite) {
                    // Base molten = GaugeArcItem. Texture = filled quads/circles only
                    // (Canvas.Image strokeArc has been unreliable on BeagleY).
                    const halfW = Math.max(12, Math.max(tailWidth, headWidth * 0.62) * 0.58);
                    function fillArcQuad(a0, a1, half, color, alpha) {
                        const steps = 5;
                        ctx.beginPath();
                        for (let s = 0; s <= steps; s++) {
                            const a = a0 + (a1 - a0) * (s / steps);
                            const p = point(a, r + half);
                            if (s === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
                        }
                        for (let s = steps; s >= 0; s--) {
                            const a = a0 + (a1 - a0) * (s / steps);
                            const p = point(a, r - half);
                            ctx.lineTo(p.x, p.y);
                        }
                        ctx.closePath();
                        ctx.fillStyle = rgba(color, alpha);
                        ctx.fill();
                    }
                    const gaps = 8;
                    for (let i = 0; i < gaps; i++) {
                        const u0 = (i / gaps + phase * 0.02) % 1.0;
                        const a0 = fromRad + sweep * u0;
                        const a1 = fromRad + sweep * Math.min(1.0, u0 + 0.075);
                        fillArcQuad(a0, a1, halfW, Qt.color("#0C0400"), 0.94);
                    }
                    for (let i = 0; i < gaps; i++) {
                        const u0 = ((i + 0.42) / gaps + phase * 0.02) % 1.0;
                        const a0 = fromRad + sweep * u0;
                        const a1 = fromRad + sweep * Math.min(1.0, u0 + 0.04);
                        fillArcQuad(a0, a1, halfW * 0.45, (i % 2) ? lavaHot : lavaAmber, 0.90);
                    }
                    for (let b = 0; b < 8; b++) {
                        const u = ((b + 0.3) / 8 + phase * 0.045) % 1.0;
                        const pt = point(fromRad + sweep * u, r);
                        const rad = (7.5 + (b % 3) * 2.5) * root.dynamicArcTune;
                        ctx.beginPath();
                        ctx.fillStyle = rgba(Qt.color("#1A0800"), 0.75);
                        ctx.arc(pt.x, pt.y, rad * 1.45, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.beginPath();
                        ctx.fillStyle = rgba(lavaOrange, 0.96);
                        ctx.arc(pt.x, pt.y, rad * 1.05, 0, Math.PI * 2);
                        ctx.fill();
                        ctx.beginPath();
                        ctx.fillStyle = rgba(lavaHot, 0.98);
                        ctx.arc(pt.x, pt.y, rad * 0.55, 0, Math.PI * 2);
                        ctx.fill();
                    }
                    return;
                }

                ctx.save();
                if (!buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale)) {
                    ctx.restore();
                    return;
                }
                ctx.clip();
                ctx.fillStyle = rgba(Qt.color("#241006"), 0.85);
                ctx.fillRect(0, 0, width, height);
                const fill = ctx.createLinearGradient(cx - r, cy + r, cx + r, cy - r);
                fill.addColorStop(0.00, rgba(lavaOrange, 0.62));
                fill.addColorStop(0.16, rgba(lavaOrange, 0.90));
                fill.addColorStop(0.44, rgba(lavaAmber, 0.98));
                fill.addColorStop(0.74, rgba(lavaHot, 0.96));
                fill.addColorStop(1.00, rgba(brightColor, 0.82));
                ctx.fillStyle = fill;
                ctx.fillRect(0, 0, width, height);
                if (showExtras && sweep > 0.04) {
                    const tailEnd = fromRad + Math.min(sweep * 0.05, 0.08);
                    ctx.beginPath();
                    ctx.strokeStyle = rgba(lavaMagenta, 0.22);
                    ctx.lineWidth = Math.max(1.2, 2.0 * root.dynamicArcTune);
                    ctx.lineCap = "round";
                    ctx.arc(cx, cy, r, fromRad, tailEnd);
                    ctx.stroke();
                }
                for (let i = 0; i < blobCount; i++) {
                    const blobColor = [lavaHot, lavaAmber, lavaOrange, lavaHot, lavaAmber][i % 5];
                    const u = (phase * (0.11 + i * 0.015) + i * 0.19) % 1.0;
                    const angle = fromRad + sweep * u;
                    const wobble = Math.sin(phase * (1.1 + i * 0.2) + i * 1.7);
                    drawBlob(angle, wobble * 2.1, (9.0 + i * 1.35) * root.dynamicArcTune, blobColor, 0.54, 1.55, phase + i);
                }
                for (let c = 0; c < 12; c++) {
                    const u0 = (c * 0.109 + phase * 0.028) % 1.0;
                    const a0 = fromRad + sweep * u0;
                    const a1 = fromRad + sweep * Math.min(1.0, u0 + 0.05);
                    const off = ((c % 2) === 0 ? 1.0 : -1.0) * (1.4 + (c % 4) * 0.85) * root.dynamicArcTune;
                    const p0 = point(a0, r + off);
                    const p1 = point(a1, r + off * 0.55);
                    ctx.beginPath();
                    ctx.strokeStyle = rgba(Qt.color("#140600"), 0.48);
                    ctx.lineWidth = Math.max(1.4, 1.6 * root.dynamicArcTune);
                    ctx.lineCap = "round";
                    ctx.moveTo(p0.x, p0.y);
                    ctx.lineTo(p1.x, p1.y);
                    ctx.stroke();
                }
                ctx.restore();
                ctx.save();
                buildTaperedPath(fromRad, toRad, tailWidth, headWidth, segments, capScale);
                ctx.fillStyle = rgba(lavaHot, 0.18);
                ctx.fill();
                ctx.restore();
            }

            // Quiet dark track under molten progress — no pink remainder glow
            ctx.beginPath();
            ctx.strokeStyle = rgba(lavaTrack, root.embeddedHighEffectBudgetMode ? 0.34 : 0.28);
            ctx.lineCap = "round";
            ctx.lineWidth = root.lowEffectMode
                ? (16 * root.lowEffectArcTune)
                : ((root.embeddedHighEffectBudgetMode ? 24 : 32) * root.dynamicArcTune);
            ctx.arc(cx, cy, r, startRad, fullEndRad);
            ctx.stroke();
            ctx.beginPath();
            ctx.strokeStyle = rgba(lavaRemainder, root.embeddedHighEffectBudgetMode ? 0.22 : 0.18);
            ctx.lineWidth = root.lowEffectMode
                ? (6 * root.lowEffectArcTune)
                : ((root.embeddedHighEffectBudgetMode ? 8 : 10) * root.dynamicArcTune);
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
                    // One animated family per gauge. Embedded: thicker + brighter for glance.
                    // Thick molten ribbon (concept): drive uses fewer blobs, show uses organic blobs
                    drawLavaBand(startRad, endRad,
                                 (root.embeddedHighEffectBudgetMode ? 13.0 : 8.0) * root.dynamicArcTune,
                                 (root.embeddedHighEffectBudgetMode ? 36.0 : 28.0) * root.dynamicArcTune,
                                 base, bright,
                                 root.embeddedHighEffectBudgetMode ? 32 : 128,
                                 0.50,
                                 root.embeddedHighEffectBudgetMode ? 3 : 6);
                }
            } else if (!root.lowEffectMode) {
                // Idle ambient crawl on same cheap path (visible at 0 progress).
                const ambSweep = sweepRad * (root.embeddedHighEffectBudgetMode ? 0.22 : 0.16);
                const ambTravel = Math.max(0.0, sweepRad - ambSweep);
                const ambU = (phase * 0.065) % 1.0;
                const ambFrom = startRad + ambTravel * ambU;
                const ambTo = ambFrom + ambSweep;
                drawLavaBand(ambFrom, ambTo,
                             (root.embeddedHighEffectBudgetMode ? 6.5 : 3.2) * root.dynamicArcTune,
                             (root.embeddedHighEffectBudgetMode ? 18.0 : 11.0) * root.dynamicArcTune,
                             base, bright,
                             root.embeddedHighEffectBudgetMode ? 20 : 64,
                             0.42,
                             1);
                // Soft track shimmer so the ring never looks fully dead
                ctx.beginPath();
                ctx.strokeStyle = rgba(lavaAmber, (root.embeddedHighEffectBudgetMode ? 0.20 : 0.12)
                    + 0.08 * (0.5 + 0.5 * Math.sin(phase * 0.9)));
                ctx.lineCap = "round";
                ctx.lineWidth = (root.embeddedHighEffectBudgetMode ? 5.5 : 4.0) * root.dynamicArcTune;
                ctx.arc(cx, cy, r, startRad, fullEndRad);
                ctx.stroke();
            }

            root.lastPaintedProgress = progress;

            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordPaint("gauge.dialArc")
        }
    }

    GaugeArcHead {
        id: arcHead
        z: 24
        visible: (root.lavaAnimationEnabled || root.accentOverlayMode) && root.showArcHead && root.headVisible
        lowEffectMode: root.lowEffectMode
        scared: root.scaredHead
        headRadius: root.sgMagmaMode ? (root.headScreenRadius * 1.15) : root.headScreenRadius
        x: (root.width / 2) + Math.cos(root.headAngleRad) * root.arcRadiusOnScreen - (width / 2)
        y: (root.height / 2) + Math.sin(root.headAngleRad) * root.arcRadiusOnScreen - (height / 2)
    }
}
