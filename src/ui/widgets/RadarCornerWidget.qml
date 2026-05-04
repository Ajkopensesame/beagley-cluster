import QtQuick 2.15
import BeagleY 1.0
import "." as WidgetLocal

Item {
    id: root

    property var theme
    property string corner: "topRight"
    property string effectLevel: "high"
    property real bleedFraction: 0.18
    property url frameUrl: ""
    property string status: "SYNC"
    property string frameLabel: ""

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool live: root.status === "LIVE"
    readonly property bool frameReady: root.live && String(root.frameUrl).length > 0

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live

        Rectangle {
            id: radarFace
            anchors.fill: parent
            anchors.margins: frame.faceInset
            radius: width / 2
            color: "#010307"
            clip: true

            Image {
                id: radarPreview
                anchors.fill: parent
                anchors.margins: -Math.round(parent.width * 0.12)
                source: root.frameReady ? root.frameUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: false
                smooth: true
                visible: status === Image.Ready
                opacity: 0.96
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(3, Math.round(frame.side * 0.024))
                border.color: "#010307"
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: root.live ? Qt.rgba(0.36, 1.0, 0.88, 0.34) : Qt.rgba(0.95, 0.98, 1.0, 0.16)
            }
        }

        Item {
            anchors.centerIn: parent
            width: Math.round(frame.side * 0.46)
            height: width
            visible: !radarPreview.visible

            WidgetLocal.RadarGlyph {
                width: parent.width
                height: width
                anchors.centerIn: parent
                active: root.status === "LIVE"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
