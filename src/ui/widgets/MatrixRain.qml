import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    // ===== Public API (Main.qml expects THESE) =====
    property color rainColor: "#5E35B1"
    property bool effectEnabled: true
    property string effectLevel: "high"
    property real sharedPhase: NaN

    property real fadeAlpha: 0.025
    property int  fps: 10
    property int  columns: 0   // 0 = auto; >0 forces column count

    property real speedMultiplier: 0.10

    property int  fontPx: 13
    property real density: 0.35
    property real glowSpeed: 1.2
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
    readonly property bool useSharedPhase: !isNaN(sharedPhase)
    readonly property real renderScale: lowEffectMode ? 0.45 : 1.0
    property var greekGlyphs: [
        "Α", "Β", "Γ", "Δ", "Ε", "Ζ", "Η", "Θ", "Ι", "Κ", "Λ", "Μ",
        "Ν", "Ξ", "Ο", "Π", "Ρ", "Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω"
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
            activeColumns.push(Math.random() < density)
            assignVerse(i)
        }
        canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        antialiasing: false
        smooth: false
        canvasSize: Qt.size(
            Math.max(1, Math.round(width * root.renderScale)),
            Math.max(1, Math.round(height * root.renderScale))
        )

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            if (root.effectDisabled) {
                return
            }

            const drawWidth = Math.max(1, canvas.canvasSize.width)
            const drawHeight = Math.max(1, canvas.canvasSize.height)
            ctx.save()
            ctx.scale(width / drawWidth, height / drawHeight)

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
                var x = i * scaledColWidth
                var headRow = root.drops[i]
                var headStep = Math.floor(headRow)
                var headY = headRow * scaledFontPx
                var pulse = root.glowFloor + (1.0 - root.glowFloor)
                    * (0.5 + 0.5 * Math.sin((root.useSharedPhase ? root.sharedPhase : root.timePhase) * root.glowSpeed + i * 0.68))
                if (isActive) {
                    var glyph = root.glyphFor(i, headStep)

                    // head
                    ctx.globalAlpha = root.headAlpha * pulse
                    ctx.fillStyle = root.rainColor
                    ctx.fillText(glyph, x, headY)

                    // tail (fades)
                    for (var t = 1; t <= root.tailLength; t++) {
                        var tailY = (headRow - t) * scaledFontPx
                        if (tailY < 0) break

                        var k = t / root.tailLength
                        var a = (root.headAlpha * (1.0 - k) + root.tailMinAlpha * k) * pulse
                        var tailGlyph = root.glyphFor(i, headStep - t)
                        ctx.globalAlpha = a
                        ctx.fillStyle = root.rainColor
                        ctx.fillText(tailGlyph, x, tailY)
                    }
                }

                root.drops[i] += root.speedMultiplier * (0.35 + 0.65 * pulse) * root.driftScale

                if (isActive && Math.random() < root.charChangeChance * pulse) {
                    if (Math.random() < 0.18) {
                        root.assignVerse(i)
                    } else {
                        var streamLength = Math.max(1, (root.verseStreams[i] || "").length)
                        root.verseOffsets[i] = ((root.verseOffsets[i] || 0)
                            + 1 + Math.floor(Math.random() * 3)) % streamLength
                    }
                }

                if (root.drops[i] * scaledFontPx > drawHeight + (root.tailLength * scaledFontPx)) {
                    root.drops[i] = -Math.random() * root.tailLength
                    root.assignVerse(i)
                    root.activeColumns[i] = Math.random() < root.density
                } else if (!isActive && Math.random() < root.density * 0.015) {
                    root.drops[i] = -Math.random() * root.tailLength
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
        interval: Math.round(1000 / Math.max(1, root.lowEffectMode ? Math.min(root.fps, 8) : root.fps))
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
    onColumnsChanged: resetDrops()
    onFontPxChanged: resetDrops()
    onEffectEnabledChanged: resetDrops()
    onEffectLevelChanged: resetDrops()
    onSharedPhaseChanged: {
        if (root.useSharedPhase) {
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
