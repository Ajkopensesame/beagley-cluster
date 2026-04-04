import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "red"

    // From SVG viewBox="0 0 504.446 504.446"
    readonly property real vbW: 504.446
    readonly property real vbH: 504.446
    readonly property real vb: 504.446

    // Stroke tuned for VIC sizes (adjust if you want thinner/thicker)
    readonly property real sw: Math.max(2, width * 0.045)

    Shape {
        anchors.fill: parent
        antialiasing: true

        // Scale SVG into this icon box
        transform: Scale {
            xScale: root.width / root.vbW
            yScale: root.height / root.vbH
        }

        // ---- SVG path #1 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M251.643,74.961h-0.839c-82.256,0-159.475,28.538-206.479,74.702C14.948,179.879-1,214.292-1,251.223
				c0,96.525,113.311,176.262,252.643,176.262c3.357,0,7.554-2.518,8.393-5.875c33.574-111.633,33.574-229.141,0-340.774
				C258.357,77.479,255,74.961,251.643,74.961z M245.767,411.538c-127.58-2.518-229.98-73.023-229.98-159.475
				c0-31.895,14.269-62.951,41.128-89.81c42.807-43.646,113.311-69.666,188.852-70.505
				C275.984,196.666,275.984,306.62,245.767,411.538z" }
        }

        // ---- SVG path #2 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M495.052,200.862H310.397c-5.036,0-8.393,3.357-8.393,8.393s3.357,8.393,8.393,8.393h184.656
				c5.036,0,8.393-3.357,8.393-8.393S500.088,200.862,495.052,200.862z" }
        }

        // ---- SVG path #3 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M495.052,284.797H310.397c-5.036,0-8.393,3.357-8.393,8.393s3.357,8.393,8.393,8.393h184.656
				c5.036,0,8.393-3.357,8.393-8.393S500.088,284.797,495.052,284.797z" }
        }

        // ---- SVG path #4 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M495.052,368.731H310.397c-5.036,0-8.393,3.357-8.393,8.393c0,5.036,3.357,8.393,8.393,8.393h184.656
				c5.036,0,8.393-3.357,8.393-8.393C503.446,372.089,500.088,368.731,495.052,368.731z" }
        }

        // ---- SVG path #5 ----
        ShapePath {
            strokeColor: root.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M310.397,133.715h184.656c5.036,0,8.393-3.357,8.393-8.393c0-5.036-3.357-8.393-8.393-8.393H310.397
				c-5.036,0-8.393,3.357-8.393,8.393C302.003,130.357,305.361,133.715,310.397,133.715z" }
        }

    }
}
