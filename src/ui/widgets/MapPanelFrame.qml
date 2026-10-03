import QtQuick 2.15

// Soft frame for the centre map panel (MainV3 "mapPanel"). Sits ABOVE the map content, inside the
// panel's own clip, and hides the hard rectangular edges of whatever the map renders (light demo
// fallback, missing tiles, dark style):
//   * left/right feather: opaque fence colour -> transparent linear gradients (no layer, no shader)
//   * four small corner patches in the fence colour that round the clipped rectangle
// Everything is plain Rectangle/Gradient geometry plus four tiny Canvas items that paint ONCE (and
// again only on resize/colour change). No offscreen layers, mask effects or shaders (GLSL).
Item {
    id: frame

    // Colour of whatever is behind the panel (the canopy backdrop) so the fence is invisible against it.
    property color fenceColor: "#09111A"
    property int cornerRadius: 22
    property int featherWidth: 56
    // Peak opacity of the feather at the very edge of the panel (1.0 = fully hides the map edge).
    property real featherOpacity: 1.0
    // Feather the top/bottom edges as well (rails sit on those edges; keep short).
    property int verticalFeatherHeight: 18

    readonly property color fenceClear: Qt.rgba(fenceColor.r, fenceColor.g, fenceColor.b, 0.0)
    readonly property color fenceSolid: Qt.rgba(fenceColor.r, fenceColor.g, fenceColor.b, featherOpacity)

    onFenceColorChanged: corners.repaint()
    onCornerRadiusChanged: corners.repaint()

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: frame.featherWidth
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: frame.fenceSolid }
            GradientStop { position: 1.0; color: frame.fenceClear }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: frame.featherWidth
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: frame.fenceClear }
            GradientStop { position: 1.0; color: frame.fenceSolid }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: frame.verticalFeatherHeight
        gradient: Gradient {
            GradientStop { position: 0.0; color: frame.fenceSolid }
            GradientStop { position: 1.0; color: frame.fenceClear }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: frame.verticalFeatherHeight
        gradient: Gradient {
            GradientStop { position: 0.0; color: frame.fenceClear }
            GradientStop { position: 1.0; color: frame.fenceSolid }
        }
    }

    // Rounded corners: fence-coloured square with a quarter-circle punched out (painted once).
    Item {
        id: corners
        anchors.fill: parent

        function repaint() {
            tl.requestPaint(); tr.requestPaint(); bl.requestPaint(); br.requestPaint()
        }

        // corner: 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right
        function paintCorner(canvas, corner) {
            const ctx = canvas.getContext("2d")
            const r = frame.cornerRadius
            ctx.clearRect(0, 0, r, r)
            ctx.fillStyle = frame.fenceColor
            ctx.fillRect(0, 0, r, r)
            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            const cx = (corner === 0 || corner === 2) ? r : 0
            const cy = (corner === 0 || corner === 1) ? r : 0
            ctx.moveTo(cx, cy)
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.closePath()
            ctx.fill()
            ctx.globalCompositeOperation = "source-over"
        }

        Canvas {
            id: tl
            anchors.left: parent.left
            anchors.top: parent.top
            width: frame.cornerRadius
            height: frame.cornerRadius
            onPaint: corners.paintCorner(tl, 0)
        }
        Canvas {
            id: tr
            anchors.right: parent.right
            anchors.top: parent.top
            width: frame.cornerRadius
            height: frame.cornerRadius
            onPaint: corners.paintCorner(tr, 1)
        }
        Canvas {
            id: bl
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: frame.cornerRadius
            height: frame.cornerRadius
            onPaint: corners.paintCorner(bl, 2)
        }
        Canvas {
            id: br
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: frame.cornerRadius
            height: frame.cornerRadius
            onPaint: corners.paintCorner(br, 3)
        }
    }
}
