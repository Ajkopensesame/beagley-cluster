import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    // API consistency (not used for tinting)
    property color color: "#FF3B3B"

    readonly property real s: Math.min(width, height)

    Image {
        anchors.centerIn: parent
        width: root.s
        height: root.s
        source: Qt.resolvedUrl("../../../../assets/vic/svg/gearshift-shift-svgrepo-com.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        antialiasing: true
        asynchronous: true
        cache: false
    }
}
