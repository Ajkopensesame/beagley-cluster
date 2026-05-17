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
    property url mapUrl: ""
    property string status: "SYNC"
    property string frameLabel: ""

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool live: root.status === "LIVE"
    readonly property bool frameReady: root.live && String(root.frameUrl).length > 0
    readonly property int radarFaceInset: Math.round(frame.side * 0.135)

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live

        Item {
            id: radarFace
            anchors.fill: parent
            anchors.margins: root.radarFaceInset

            RadarFrameItem {
                id: radarPreview
                anchors.fill: parent
                anchors.margins: 0
                source: root.frameReady ? root.frameUrl : ""
                mapSource: root.frameReady ? root.mapUrl : ""
                circular: true
                backgroundVisible: true
                guidesVisible: true
                visible: ready
                opacity: 1.0
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(2, Math.round(frame.side * 0.014))
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
            visible: !radarPreview.ready

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
