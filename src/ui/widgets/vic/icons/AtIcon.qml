import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    property color color: "#FF3B3B"

    Text {
        anchors.centerIn: parent
        text: "A/T"
        color: root.color
        font.family: "monospace"
        font.bold: true
        font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.34)
        font.letterSpacing: 1
    }
}
