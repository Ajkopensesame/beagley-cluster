import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    // kept for API consistency (no runtime tint available without Effects)
    property color color: "yellow"

    readonly property real s: Math.min(width, height)

    Image {
        anchors.centerIn: parent
        width: root.s
        height: root.s
        source: Qt.resolvedUrl("../../../../../assets/vic/svg/oil-can-solid-svgrepo-com-red.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        asynchronous: true
        cache: false
    }
}
