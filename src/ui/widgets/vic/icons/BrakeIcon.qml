import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "#FF3B3B"

    // viewBox from SVG: "0 0 234.409 234.409"
    readonly property real vbX: 0
    readonly property real vbY: 0
    readonly property real vbW: 234.409
    readonly property real vbH: 234.409

    Shape {
        anchors.fill: parent
        antialiasing: true

        // Same core method as CheckIcon:
        // translate viewBox origin -> (0,0), then scale into our icon box
        transform: [
            Translate { x: -root.vbX; y: -root.vbY },
            Scale { xScale: root.width / root.vbW; yScale: root.height / root.vbH }
        ]

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M117.204,30.677c-47.711,0-86.527,38.816-86.527,86.528c0,47.711,38.816,86.526,86.527,86.526s86.527-38.815,86.527-86.526
		C203.732,69.494,164.915,30.677,117.204,30.677z M117.204,188.732c-39.44,0-71.527-32.086-71.527-71.526
		c0-39.441,32.087-71.528,71.527-71.528s71.527,32.087,71.527,71.528C188.732,156.645,156.645,188.732,117.204,188.732z" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M44.896,44.897c2.929-2.929,2.929-7.678,0-10.607c-2.93-2.929-7.678-2.929-10.607,0
		c-45.718,45.719-45.718,120.111,0,165.831c1.465,1.465,3.384,2.197,5.304,2.197c1.919,0,3.839-0.732,5.303-2.197
		c2.93-2.929,2.93-7.677,0.001-10.606C5.026,149.643,5.026,84.768,44.896,44.897z" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M200.119,34.29c-2.93-2.929-7.678-2.929-10.607,0c-2.929,2.929-2.929,7.678,0,10.607
		c39.872,39.871,39.872,104.746,0,144.618c-2.929,2.929-2.929,7.678,0,10.606c1.465,1.464,3.385,2.197,5.304,2.197
		c1.919,0,3.839-0.732,5.304-2.197C245.839,154.4,245.839,80.009,200.119,34.29z" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M117.204,140.207c4.143,0,7.5-3.358,7.5-7.5v-63.88c0-4.142-3.357-7.5-7.5-7.5c-4.143,0-7.5,3.358-7.5,7.5v63.88
		C109.704,136.849,113.062,140.207,117.204,140.207z" }
        }
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: root.color
            PathSvg { path: "M 107.875000 156.254000 a 9.329000 9.329000 0 1 0 18.658000 0 a 9.329000 9.329000 0 1 0 -18.658000 0" }
        }
    }
}
