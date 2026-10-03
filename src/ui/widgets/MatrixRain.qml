import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    // ===== Public API (Main.qml expects THESE) =====
    property color rainColor: "#C7B7FF"
    property color glowColor: "#EAD7FF"
    property bool effectEnabled: true
    property string effectLevel: "high"
    property real sharedPhase: NaN

    property real fadeAlpha: 0.025
    property real fps: 10
    property int  columns: 0   // 0 = auto; >0 forces column count

    property real speedMultiplier: 0.10

    property int  fontPx: 13
    property real density: 0.35
    property real glowSpeed: 1.2
    property real glowBlur: 7.0
    property real glowFloor: 0.22
    property real driftScale: 0.18
    property real charChangeChance: 0.035

    property int  tailLength: 26
    property real headAlpha: 0.45
    property real tailMinAlpha: 0.02
    property bool circularMask: false
    property real maskCenterX: width / 2
    property real maskCenterY: height / 2
    property real maskRadius: Math.min(width, height) / 2

    readonly property int colWidth: fontPx + 3
    property var drops: []
    property var activeColumns: []
    property var verseStreams: []
    property var verseOffsets: []
    property real timePhase: 0.0
    readonly property bool effectDisabled: !effectEnabled || effectLevel === "off"
    readonly property bool lowEffectMode: effectLevel === "low"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property bool embeddedHighEffectBudgetMode: embeddedSafeMode && effectLevel === "high"
    readonly property bool useSharedPhase: !isNaN(sharedPhase)
    readonly property real renderScale: 1.0
    readonly property real effectiveDensity: embeddedHighEffectBudgetMode ? Math.min(density, 0.80) : density
    readonly property int effectiveTailLength: embeddedHighEffectBudgetMode ? Math.min(tailLength, 36) : tailLength
    readonly property real effectiveCharChangeChance: embeddedHighEffectBudgetMode ? Math.min(charChangeChance, 0.016) : charChangeChance
    readonly property real effectiveGlowBlur: embeddedHighEffectBudgetMode ? Math.min(glowBlur, 7.0) : glowBlur
    // Embedded high: allow up to 4fps so in-face rain stays readable at a glance
    readonly property real effectiveFps: lowEffectMode
        ? Math.min(fps, embeddedHighEffectBudgetMode ? 3.0 : 8.0)
        : (embeddedHighEffectBudgetMode ? Math.min(fps, 4.0) : fps)
    property var greekGlyphs: [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ｶ", "ｷ", "ｸ", "ｹ", "ｺ",
        "ｻ", "ｼ", "ｽ", "ｾ", "ｿ", "ﾀ", "ﾁ", "ﾂ", "ﾃ", "ﾄ",
        "ﾅ", "ﾆ", "ﾇ", "ﾈ", "ﾉ", "ﾊ", "ﾋ", "ﾌ", "ﾍ", "ﾎ",
        "ﾏ", "ﾐ", "ﾑ", "ﾒ", "ﾓ", "ﾔ", "ﾕ", "ﾖ", "ﾗ", "ﾘ",
        "ﾙ", "ﾚ", "ﾛ", "ﾜ", "ﾝ"
    ]
    property var verses: [
        "ΕΝ ΑΡΧΗ ΗΝ Ο ΛΟΓΟΣ",
        "ΚΑΙ ΦΩΣ ΕΝ ΤΗ ΣΚΟΤΙΑ ΦΑΙΝΕΙ",
        "Ο ΘΕΟΣ ΑΓΑΠΗ ΕΣΤΙΝ",
        "ΕΓΩ ΕΙΜΙ ΤΟ ΦΩΣ ΤΟΥ ΚΟΣΜΟΥ",
        "ΜΗ ΦΟΒΟΥ ΜΟΝΟΝ ΠΙΣΤΕΥΕ",
        "Ο ΚΥΡΙΟΣ ΠΟΙΜΑΙΝΕΙ ΜΕ",
        "ΖΗΤΕΙΤΕ ΚΑΙ ΕΥΡΗΣΕΤΕ",
        "ΜΑΚΑΡΙΟΙ ΟΙ ΕΙΡΗΝΟΠΟΙΟΙ"
    ]

    function columnCount() {
        if (columns > 0)
            return columns
        return Math.max(1, Math.floor(width / colWidth))
    }

    function randGlyph() {
        return greekGlyphs[Math.floor(Math.random() * greekGlyphs.length)]
    }

    function randVerse() {
        return verses[Math.floor(Math.random() * verses.length)]
    }

    function visibleChar(ch) {
        return ch === " " ? "·" : ch
    }

    function assignVerse(index) {
        var verse = randVerse()
        verseStreams[index] = verse
        verseOffsets[index] = Math.floor(Math.random() * Math.max(1, verse.length))
    }

    function glyphFor(index, row) {
        var verse = verseStreams[index]
        if (!verse || verse.length === 0)
            return randGlyph()

        var offset = verseOffsets[index] || 0
        var pos = Math.floor(row + offset)
        var normalized = ((pos % verse.length) + verse.length) % verse.length
        return visibleChar(verse.charAt(normalized))
    }

    function resetDrops() {
        if (root.effectDisabled) {
            drops = []
            activeColumns = []
            verseStreams = []
            verseOffsets = []
            canvas.requestPaint()
            return
        }
        var count = columnCount()
        drops = []
        activeColumns = []
        verseStreams = []
        verseOffsets = []
        for (var i = 0; i < count; i++) {
            drops.push(Math.random() * (height / Math.max(1, fontPx)))
            activeColumns.push(Math.random() < root.effectiveDensity)
            assignVerse(i)
        }
        canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: root.embeddedSafeMode ? Canvas.Image : Canvas.FramebufferObject
        antialiasing: false
        smooth: false
        canvasSize: Qt.size(
            Math.max(1, Math.round(width * root.renderScale)),
            Math.max(1, Math.round(height * root.renderScale))
        )

        onPaint: {
            var ctx = getContext("2d")
            const drawWidth = Math.max(1, canvas.canvasSize.width)
            const drawHeight = Math.max(1, canvas.canvasSize.height)
            ctx.clearRect(0, 0, drawWidth, drawHeight)

            if (root.effectDisabled) {
                return
            }

            ctx.save()

            if (root.circularMask) {
                ctx.save()
                ctx.beginPath()
                ctx.arc(root.maskCenterX * root.renderScale,
                        root.maskCenterY * root.renderScale,
                        root.maskRadius * root.renderScale,
                        0, Math.PI * 2)
                ctx.clip()
            }

            // black background + trails
            ctx.save()
            ctx.globalAlpha = root.fadeAlpha
            ctx.fillStyle = "black"
            ctx.fillRect(0, 0, drawWidth, drawHeight)
            ctx.restore()

            const scaledFont = Math.max(7, Math.round(root.fontPx * root.renderScale))
            const scaledColWidth = Math.max(1, Math.round(root.colWidth * root.renderScale))
            const scaledFontPx = Math.max(1, Math.round(root.fontPx * root.renderScale))
            ctx.font = scaledFont + 'px "Menlo", "Monaco", "Courier New", monospace'
            ctx.textBaseline = "top"
            ctx.shadowBlur = 0

            for (var i = 0; i < root.drops.length; i++) {
                var isActive = !!root.activeColumns[i]
                var phaseSource = root.useSharedPhase ? root.sharedPhase : root.timePhase
                var x = i * scaledColWidth
                if (root.lowEffectMode)
                    x += Math.sin(phaseSource * 1.9 + i * 1.73) * Math.max(1, scaledColWidth * 0.18)
                var headRow = root.drops[i]
                var headStep = Math.floor(headRow)
                var headY = headRow * scaledFontPx
                var pulse = root.glowFloor + (1.0 - root.glowFloor)
                    * (0.5 + 0.5 * Math.sin(phaseSource * root.glowSpeed + i * 0.68))
                if (isActive) {
                    var glyph = root.glyphFor(i, headStep)

                    // head
                    ctx.shadowColor = root.glowColor
                    ctx.shadowBlur = root.effectiveGlowBlur * pulse
                    ctx.globalAlpha = root.headAlpha * pulse
                    ctx.fillStyle = root.rainColor
                    ctx.fillText(glyph, x, headY)

                    // tail (fades)
                    for (var t = 1; t <= root.effectiveTailLength; t++) {
                        var tailY = (headRow - t) * scaledFontPx
                        if (tailY < 0) break

                        var k = t / root.effectiveTailLength
                        var a = (root.headAlpha * (1.0 - k) + root.tailMinAlpha * k) * pulse
                        var tailGlyph = root.glyphFor(i, headStep - t)
                        ctx.globalAlpha = a
                        ctx.shadowBlur = root.effectiveGlowBlur * pulse * (1.0 - k) * 0.55
                        ctx.fillStyle = root.rainColor
                        ctx.fillText(tailGlyph, x, tailY)
                    }
                    ctx.shadowBlur = 0
                }

                var step = root.speedMultiplier * (0.35 + 0.65 * pulse) * root.driftScale
                if (root.lowEffectMode)
                    step = Math.max(step, 0.10 + Math.random() * 0.045)
                root.drops[i] += step

                var churnChance = Math.max(root.effectiveCharChangeChance * pulse, root.lowEffectMode ? 0.030 : 0.0)
                if (isActive && Math.random() < churnChance) {
                    if (Math.random() < 0.18) {
                        root.assignVerse(i)
                    } else {
                        var streamLength = Math.max(1, (root.verseStreams[i] || "").length)
                        root.verseOffsets[i] = ((root.verseOffsets[i] || 0)
                            + 1 + Math.floor(Math.random() * 3)) % streamLength
                    }
                }

                if (root.drops[i] * scaledFontPx > drawHeight + (root.effectiveTailLength * scaledFontPx)) {
                    root.drops[i] = -Math.random() * root.effectiveTailLength
                    root.assignVerse(i)
                    root.activeColumns[i] = Math.random() < root.effectiveDensity
                } else if (!isActive && Math.random() < root.effectiveDensity * (root.lowEffectMode ? 0.045 : 0.015)) {
                    root.drops[i] = -Math.random() * root.effectiveTailLength
                    root.assignVerse(i)
                    root.activeColumns[i] = true
                }
            }

            ctx.globalAlpha = 1.0

            if (root.circularMask)
                ctx.restore()
            ctx.restore()

            if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                performanceMetrics.recordPaint("matrixRain")
        }
    }

    Timer {
        interval: Math.round(1000 / Math.max(0.25, root.effectiveFps))
        running: !root.effectDisabled && !root.useSharedPhase
        repeat: true
        onTriggered: {
            root.timePhase += interval / 1000.0
            canvas.requestPaint()
        }
    }

    onWidthChanged: resetDrops()
    onHeightChanged: resetDrops()
    onDensityChanged: resetDrops()
    onEffectiveDensityChanged: resetDrops()
    onColumnsChanged: resetDrops()
    onFontPxChanged: resetDrops()
    onEffectEnabledChanged: resetDrops()
    onEffectLevelChanged: resetDrops()
    onSharedPhaseChanged: {
        if (root.useSharedPhase && !root.effectDisabled) {
            root.timePhase = root.sharedPhase
            canvas.requestPaint()
        }
    }
    onCircularMaskChanged: canvas.requestPaint()
    onMaskCenterXChanged: canvas.requestPaint()
    onMaskCenterYChanged: canvas.requestPaint()
    onMaskRadiusChanged: canvas.requestPaint()
    Component.onCompleted: resetDrops()
}
