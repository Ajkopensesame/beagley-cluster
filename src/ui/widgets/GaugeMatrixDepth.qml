import QtQuick 2.15

// Low-cost in-gauge matrix depth: scrolling Text columns (concept cyan glyphs).
// ASCII-only glyphs (appliance often lacks CJK fonts). No Canvas / ShaderEffect.
Item {
    id: root
    anchors.fill: parent

    property color rainColor: "#5FF7FF"
    property bool effectEnabled: true
    property real density: 0.35
    property int columns: 10
    property int fontPx: 11
    property real opacityScale: 0.28
    property bool circularMask: true
    property real faceFactor: 0.72

    visible: effectEnabled
    opacity: opacityScale

    readonly property var glyphs: ["0","1","7","3","A","F","E","C","8","4","#","+","|",":","*","="]

    // Inner face bounds (no clip — clip+transparent Rectangle was unreliable on EGLFS)
    Item {
        id: face
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * root.faceFactor
        height: width

        Repeater {
            model: Math.max(4, Math.min(16, root.columns))
            delegate: Item {
                id: col
                width: root.fontPx + 2
                height: face.height * 2.2
                x: (index + 0.5) * (face.width / Math.max(1, root.columns)) - width / 2
                y: -height * 0.10
                opacity: (index % 3 === 0) ? 1.0 : 0.62
                visible: (index / Math.max(1, root.columns)) <= root.density
                    || ((index * 17) % 10) < (root.density * 10)

                Column {
                    spacing: 0
                    Repeater {
                        model: 20
                        delegate: Text {
                            text: root.glyphs[(index * 5 + Math.floor(col.x)) % root.glyphs.length]
                            color: root.rainColor
                            font.pixelSize: root.fontPx
                            font.family: "DejaVu Sans Mono"
                            font.bold: true
                            opacity: 0.55 + (index % 4) * 0.12
                        }
                    }
                }

                NumberAnimation on y {
                    from: -col.height * 0.30
                    to: face.height * 0.55
                    duration: 10000 + (index % 5) * 1200
                    loops: Animation.Infinite
                    running: root.effectEnabled && root.visible
                }
            }
        }
    }
}
