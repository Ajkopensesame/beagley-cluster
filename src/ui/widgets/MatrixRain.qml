import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    // ===== Public API (Main.qml expects THESE) =====
    property color rainColor: "#5E35B1"

    property real fadeAlpha: 0.025
    property int  fps: 10
    property int  columns: 0   // 0 = auto; >0 forces column count

    property real speedMultiplier: 0.10

    property int  fontPx: 13
    property real density: 0.35

    property int  tailLength: 26
    property real headAlpha: 0.45
    property real tailMinAlpha: 0.02

    readonly property int colWidth: fontPx + 3
    property var drops: []

    function columnCount() { return Math.max(1, Math.floor(width / colWidth)) }
    function randChar() { return String.fromCharCode(0x30A0 + Math.floor(Math.random() * 96)) }

    function resetDrops() {
        var count = columnCount()
        drops = []
        for (var i = 0; i < count; i++)
            drops.push(Math.random() * (height / Math.max(1, fontPx)))
        canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            var ctx = getContext("2d")

            // black background + trails
            ctx.save()
            ctx.globalAlpha = root.fadeAlpha
            ctx.fillStyle = "black"
            ctx.fillRect(0, 0, width, height)
            ctx.restore()

            ctx.font = root.fontPx + "px monospace"
            ctx.textBaseline = "top"
            ctx.shadowBlur = 0

            for (var i = 0; i < root.drops.length; i++) {
                if (Math.random() > root.density) continue

                var x = i * root.colWidth
                var headRow = root.drops[i]
                var headY = headRow * root.fontPx

                // head
                ctx.globalAlpha = root.headAlpha
                ctx.fillStyle = root.rainColor
                ctx.fillText(randChar(), x, headY)

                // tail (fades)
                for (var t = 1; t <= root.tailLength; t++) {
                    var tailY = (headRow - t) * root.fontPx
                    if (tailY < 0) break

                    var k = t / root.tailLength
                    var a = root.headAlpha * (1.0 - k) + root.tailMinAlpha * k
                    ctx.globalAlpha = a
                    ctx.fillStyle = root.rainColor
                    ctx.fillText(randChar(), x, tailY)
                }

                root.drops[i] += root.speedMultiplier

                if (root.drops[i] * root.fontPx > height + (root.tailLength * root.fontPx)) {
                    if (Math.random() > 0.90) root.drops[i] = 0
                }
            }

            ctx.globalAlpha = 1.0
        }
    }

    Timer {
        interval: Math.round(1000 / Math.max(1, root.fps))
        running: true
        repeat: true
        onTriggered: canvas.requestPaint()
    }

    onWidthChanged: resetDrops()
    onHeightChanged: resetDrops()
    Component.onCompleted: resetDrops()
}
