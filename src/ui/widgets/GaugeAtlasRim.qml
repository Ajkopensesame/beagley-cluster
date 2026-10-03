import QtQuick 2.15

// Concept glass rim / specular ring atlas overlay (static Image — cheap).
Item {
    id: root
    property url rimSource: Qt.resolvedUrl("../assets/skin-v2/glass-rim.png")
    property url faceSource: Qt.resolvedUrl("../assets/skin-v2/gauge-face-matrix.png")
    property bool showFacePlate: false
    property real faceOpacity: 0.42
    property real rimOpacity: 0.92

    Image {
        anchors.fill: parent
        visible: root.showFacePlate
        source: root.faceSource
        fillMode: Image.PreserveAspectFit
        opacity: root.faceOpacity
        asynchronous: true
        smooth: true
        z: 0
    }

    Image {
        anchors.fill: parent
        source: root.rimSource
        fillMode: Image.PreserveAspectFit
        opacity: root.rimOpacity
        asynchronous: true
        smooth: true
        mipmap: true
        z: 2
    }
}
