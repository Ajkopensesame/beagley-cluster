import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "#FF3B3B"

    // From SVG viewBox="0 0 24 24"
    readonly property real vbX: 0
    readonly property real vbY: 0
    readonly property real vbW: 24
    readonly property real vbH: 24

    // Outline thickness tuned for small icon legibility
    readonly property real sw: width * 0.008

    Shape {
        anchors.fill: parent
        antialiasing: true

        transform: [
            Translate { x: -root.vbX; y: -root.vbY },
            Scale { xScale: root.width / root.vbW; yScale: root.height / root.vbH }
        ]

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M4,20V4A1,1,0,0,1,5,3h6.59a1,1,0,0,1,.7.29l7.42,7.42a1,1,0,0,1,.29.7V20a1,1,0,0,1-1,1H5A1,1,0,0,1,4,20Zm0-9H19.9" }
        }
    }
}
