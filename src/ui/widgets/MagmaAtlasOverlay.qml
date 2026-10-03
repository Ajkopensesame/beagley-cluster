import QtQuick 2.15

// Atlas magma as Image sibling of DialChrome (PowerVR: Image inside DialChrome/QSG arc tree does not composite).
Item {
    id: root
    property real progress: 0.0
    property real gaugeSide: Math.min(width, height)

    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))
    readonly property int frameIndex: Math.max(0, Math.min(20, Math.round(clampedProgress * 20)))
    readonly property string framePath: "../assets/skin-v2/progress/lava-p"
        + (frameIndex < 10 ? "0" : "") + frameIndex + ".png"

    visible: clampedProgress > 0.002

    Image {
        anchors.centerIn: parent
        width: root.gaugeSide
        height: root.gaugeSide
        source: Qt.resolvedUrl(root.framePath)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: true
        smooth: true
        mipmap: false
        opacity: status === Image.Ready ? 1.0 : 0.0
    }
}
