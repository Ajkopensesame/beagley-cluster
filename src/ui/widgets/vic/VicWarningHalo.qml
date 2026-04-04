import QtQuick 2.15

Item {
    id: root

    // Keep API consistent across VIC pieces
    property var theme: null
    property bool isWarning: false

    // Optional: let VIC drive pulse intensity later
    property real pulse: 0.0

    // Placeholder sizing (real halo will be drawn later)
    width: 240
    height: 240

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: isWarning ? "#FF3B3B" : "#5E35B1"
        opacity: 0.30
    }
}
