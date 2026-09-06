import QtQuick 2.15

// Low-cost in-gauge matrix depth: scrolling Text columns (concept cyan glyphs).
// Prefer this over MatrixRain Canvas on embedded/show budgets.
// Keep glyphs inside an inner rounded disc so magma arcs stay clean.
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
    // Face-only radius so arcs (rim) are not washed with cyan
    property real faceFactor: 0.72

    visible: effectEnabled
    opacity: opacityScale
    // Sit above NativeGauge face; parent MainV3 sets absolute z under DialChrome
    z: 0

    readonly property var glyphs: ["0","1","ｱ","ｶ","ｻ","ﾀ","ﾅ","ﾊ","ﾏ","ﾔ","ﾗ","ﾝ","Φ","λ","7","3"]

    // Rounded clip disc — Qt clips to radius, no OpacityMask/ShaderEffect cost
    Rectangle {
        id: faceDisc
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * root.faceFactor
        height: width
        radius: width / 2
        color: "transparent"
        clip: root.circularMask
        border.width: 0

        Item {
            id: rainLayer
            anchors.fill: parent

            Repeater {
                model: Math.max(4, Math.min(16, root.columns))
                delegate: Item {
                    id: col
                    width: root.fontPx + 2
                    height: faceDisc.height * 2.4
                    x: (index + 0.5) * (faceDisc.width / Math.max(1, root.columns)) - width / 2
                    y: -height * 0.15
                    opacity: (index % 3 === 0) ? 1.0 : 0.55
                    visible: (index / Math.max(1, root.columns)) <= root.density
                        || ((index * 17) % 10) < (root.density * 10)

                    Column {
                        spacing: 1
                        Repeater {
                            model: 22
                            delegate: Text {
                                text: root.glyphs[Math.floor(Math.abs(index * 3 + Math.floor(col.x))) % root.glyphs.length]
                                color: root.rainColor
                                font.pixelSize: root.fontPx
                                font.family: "monospace"
                                opacity: 0.40 + (index % 5) * 0.12
                                style: Text.Normal
                            }
                        }
                    }

                    NumberAnimation on y {
                        from: -col.height * 0.35
                        to: faceDisc.height * 0.65
                        duration: 9000 + (index % 5) * 1400
                        loops: Animation.Infinite
                        running: root.effectEnabled && root.visible
                    }
                }
            }
        }

        // Soft center dim only — keep glyphs readable behind numerals (was #CC opaque)
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.42
            height: width
            radius: width / 2
            color: "#18010108"
            visible: root.circularMask
            z: 5
        }
    }
}
