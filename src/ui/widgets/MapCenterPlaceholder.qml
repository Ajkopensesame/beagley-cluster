import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    property real lat: 0
    property real lng: 0
    property real bearing: 0

    property string title: "MAP"
    property string subtitle: "placeholder"

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#101418"
        border.color: "#2a333c"
        border.width: 2
    }

    // Bearing arrow (proof of pose updates)
    Item {
        width: 46; height: 46
        anchors.centerIn: parent

        Rectangle {
            width: 6; height: 28; radius: 3
            anchors.centerIn: parent
            color: "#ff5555"
            transform: Rotation { origin.x: 3; origin.y: 14; angle: root.bearing }
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 6

        Text { text: title.toUpperCase(); color: "#9fb2c1"; font.pixelSize: 18 }
        Text { text: subtitle; color: "#d8e2ea"; font.pixelSize: 14 }
        Text { text: "lat: " + lat.toFixed(6) + "  lng: " + lng.toFixed(6); color: "#d8e2ea"; font.pixelSize: 14 }
    }
}
