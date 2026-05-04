import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    property real bearing: 0

    rotation: bearing
    transformOrigin: Item.Center

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        color: "#FFE45C"
        opacity: 0.20
    }

    Shape {
        id: vehicleShape
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "#FFE45C"
            strokeColor: "#061D29"
            strokeWidth: 2.4
            joinStyle: ShapePath.RoundJoin
            startX: vehicleShape.width * 0.5
            startY: vehicleShape.height * 0.08
            PathLine { x: vehicleShape.width * 0.80; y: vehicleShape.height * 0.78 }
            PathQuad {
                x: vehicleShape.width * 0.50
                y: vehicleShape.height * 0.66
                controlX: vehicleShape.width * 0.62
                controlY: vehicleShape.height * 0.72
            }
            PathQuad {
                x: vehicleShape.width * 0.20
                y: vehicleShape.height * 0.78
                controlX: vehicleShape.width * 0.38
                controlY: vehicleShape.height * 0.72
            }
            PathLine { x: vehicleShape.width * 0.5; y: vehicleShape.height * 0.08 }
        }
    }

    Rectangle {
        width: 8
        height: 8
        radius: 4
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 8
        color: "#061D29"
    }
}
