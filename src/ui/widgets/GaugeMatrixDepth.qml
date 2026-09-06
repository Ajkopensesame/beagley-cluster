import QtQuick 2.15

// Low-cost in-gauge matrix depth: scrolling Text columns (concept cyan glyphs).
// Prefer this over MatrixRain Canvas on embedded/show budgets.
Item {
    id: root
    anchors.fill: parent
    clip: true

    property color rainColor: "#5FF7FF"
    property bool effectEnabled: true
    property real density: 0.35
    property int columns: 10
    property int fontPx: 11
    property real opacityScale: 0.28
    property bool circularMask: true

    visible: effectEnabled
    opacity: opacityScale

    readonly property var glyphs: ["0","1","ｱ","ｶ","ｻ","ﾀ","ﾅ","ﾊ","ﾏ","ﾔ","ﾗ","ﾝ","Φ","λ"]

    Rectangle {
        id: maskDisc
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.92
        height: width
        radius: width / 2
        color: "transparent"
        visible: false
    }

    Item {
        id: rainLayer
        anchors.fill: parent
        layer.enabled: root.circularMask
        layer.smooth: false

        Repeater {
            model: Math.max(4, Math.min(16, root.columns))
            delegate: Item {
                id: col
                width: root.fontPx + 2
                height: root.height * 2.2
                x: (index + 0.5) * (root.width / Math.max(1, root.columns)) - width / 2
                y: -height * 0.15
                opacity: (index % 3 === 0) ? 0.9 : 0.45
                visible: (index / Math.max(1, root.columns)) <= root.density
                    || ((index * 17) % 10) < (root.density * 10)

                Column {
                    spacing: 2
                    Repeater {
                        model: 18
                        delegate: Text {
                            text: root.glyphs[Math.floor(Math.abs(index * 3 + Math.floor(col.x))) % root.glyphs.length]
                            color: root.rainColor
                            font.pixelSize: root.fontPx
                            font.family: "monospace"
                            opacity: 0.15 + (index % 5) * 0.12
                        }
                    }
                }

                NumberAnimation on y {
                    from: -col.height * 0.35
                    to: root.height * 0.55
                    duration: 9000 + (index % 5) * 1400
                    loops: Animation.Infinite
                    running: root.effectEnabled && root.visible
                }
            }
        }
    }

    // Soft circular veil so glyphs only read as depth behind numerals
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.55
        height: width
        radius: width / 2
        color: "#CC010105"
        visible: root.circularMask
        z: 5
    }
}
