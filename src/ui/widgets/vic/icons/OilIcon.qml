import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "#FF3B3B"   // oil warning red

    // viewBox from SVG: "0 0 32 32"
    readonly property real vbX: 0
    readonly property real vbY: 0
    readonly property real vbW: 32
    readonly property real vbH: 32

    Shape {
        anchors.fill: parent
        antialiasing: true

        transform: [
            Translate { x: -root.vbX; y: -root.vbY },
            Scale { xScale: root.width / root.vbW; yScale: root.height / root.vbH }
        ]

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M 11 9 L 11 11 L 13 11 L 13 13 L 7.5625 13 L 5.84375 10.4375 L 5.53125 10 L 1 10 L 1 15.6875 L 6 17.6875 L 6 25 L 20.53125 25 L 20.8125 24.5625 L 29.5 12 L 31 12 L 31 10 L 27.65625 10 L 27.40625 10.1875 L 21 15 L 21 13 L 15 13 L 15 11 L 17 11 L 17 9 Z M 3 12 L 4.4375 12 L 6 14.34375 L 6 15.5 L 3 14.3125 Z M 25.78125 13.9375 L 19.5 23 L 8 23 L 8 15 L 19 15 L 19 19 L 20.59375 17.8125 Z M 29.5 16 C 29.5 16 28 18.671875 28 19.5 C 28 20.328125 28.671875 21 29.5 21 C 30.328125 21 31 20.328125 31 19.5 C 31 18.671875 29.5 16 29.5 16 Z" }
        }
    }
}
