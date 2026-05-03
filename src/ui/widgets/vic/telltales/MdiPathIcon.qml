import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root
    width: 96
    height: 96

    // Material Design Icons path data, viewBox 0 0 24 24.
    // Source package: @mdi/js 7.4.47, Apache-2.0.
    property string path: ""
    property color color: "#FF3B3B"
    property real inset: 0
    property real alpha: 1.0

    readonly property real box: Math.max(1, Math.min(width, height) - inset * 2)
    readonly property real pathScale: box / 24

    Shape {
        width: 24
        height: 24
        x: (root.width - root.box) / 2
        y: (root.height - root.box) / 2
        antialiasing: true
        transform: Scale { xScale: root.pathScale; yScale: root.pathScale }

        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.alpha)
            fillRule: ShapePath.WindingFill
            PathSvg { path: root.path }
        }
    }
}
