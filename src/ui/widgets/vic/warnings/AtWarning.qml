import QtQuick 2.15

Item {
    id: root
    property var theme: null
    property bool active: false

    width: 220
    height: 220

    Text {
        anchors.centerIn: parent
        text: "A/T"
        color: "#FF3B3B"
        font.pixelSize: 34
        font.family: "Menlo"
        font.bold: true
        opacity: active ? 1.0 : 0.7
    }
}
