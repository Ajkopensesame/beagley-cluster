import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "red"

    // From your SVG: viewBox="0 0 295.238 295.238"
    readonly property real vb: 295.238

    // Stroke tuned for VIC sizes
    readonly property real sw: Math.max(3, width * 0.055)

    Shape {
        anchors.fill: parent
        antialiasing: true

        // Scale whole SVG into this icon box
        transform: Scale {
            xScale: root.width / root.vb
            yScale: root.height / root.vb
        }

        // ---- SVG path #1 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: "M257.143,157.143h-14.286v-28.571H220.49l-28.571-19.048h-30.014V80.952H200v-9.524H85.714v9.524h38.095v28.571H93.476l-33.333,28.571h-26.81v28.571H9.524V123.81H0v119.048h9.524v-38.095h23.81v38.095h27.305l33.333,19.048h53.648v-9.524H96.505l-29.838-17.048v-90.286l30.333-26h92.033l25.252,16.833v16.5h9.524v-14.286h9.524v114.286h-9.524v9.524h19.048v-23.81h14.286v9.524h38.095V142.857h-38.095V157.143z M33.334,195.238H9.524V176.19h23.81V195.238z M57.143,233.333H42.857v-85.714h14.286V233.333z M152.381,109.523h-19.048V80.952h19.048V109.523z M257.143,228.571h-14.286v-61.905h14.286V228.571z M266.667,152.381h19.048v85.714h-19.048V152.381z" }
        }

        // ---- SVG path #2 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: "M192.448,176.19h-35.576l23.81-33.333h-45.533L106.576,200h29.962l-12.833,44.933L192.448,176.19z M121.99,190.476l19.048-38.095h21.133l-23.81,33.333h31.09l-26.495,26.495l6.214-21.733H121.99z" }
        }

        // ---- rects/polygons converted to PathSvg ----
        // rect x=38.095 y=28.571 w=28.571 h=9.524
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M38.095 28.571 H66.666 V38.095 H38.095 Z" }
        }

        // rect x=0 y=28.571 w=28.571 h=9.524
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M0 28.571 H28.571 V38.095 H0 Z" }
        }

        // rect x=28.571 y=38.095 w=9.524 h=28.571
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M28.571 38.095 H38.095 V66.666 H28.571 Z" }
        }

        // rect x=28.571 y=0 w=9.524 h=28.571
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M28.571 0 H38.095 V28.571 H28.571 Z" }
        }

        // polygon (big one near top right)
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M276.191 71.429 L276.191 52.381 L266.667 52.381 L266.667 71.429 L276.19 71.429 L276.19 80.952 L266.667 80.952 L266.667 71.429 L247.619 71.429 L247.619 80.953 L266.667 80.953 L266.667 100 L276.191 100 L276.191 80.953 L295.238 80.953 L295.238 71.429 Z" }
        }

        // rect x=190.476 y=252.381 w=23.81 h=9.524
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M190.476 252.381 H214.286 V261.905 H190.476 Z" }
        }

        // polygon (bottom middle plus)
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M180.953 252.381 L190.476 252.381 L190.476 228.571 L180.952 228.571 L180.952 252.381 L157.143 252.381 L157.143 261.905 L180.952 261.905 L180.952 285.715 L190.476 285.715 L190.476 261.905 L180.953 261.905 Z" }
        }

        // polygon (bottom right cluster)
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M285.714 266.667 L276.19 266.667 L276.19 276.19 L266.667 276.19 L266.667 285.714 L276.19 285.714 L276.19 295.238 L285.714 295.238 L285.714 285.714 L276.191 285.714 L276.191 276.191 L285.714 276.191 L285.714 285.714 L295.238 285.714 L295.238 276.19 L285.714 276.19 Z" }
        }
    }
}
