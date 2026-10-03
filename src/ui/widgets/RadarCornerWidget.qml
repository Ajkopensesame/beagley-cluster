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
    // Slice 6 must-fix: when feature is off, calm OFF glyph (not empty/NO RADAR dead pod)
    property bool featureEnabled: true

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool live: root.featureEnabled && root.status === "LIVE"
    readonly property bool offMode: !root.featureEnabled || root.status === "OFF"
    readonly property url previewUrl: String(root.mapUrl).length > 0 ? root.mapUrl : root.frameUrl
    readonly property bool frameReady: root.live && String(root.previewUrl).length > 0

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live
        accentColor: root.offMode ? "#2A3344" : "#58FFE1"
        secondaryAccentColor: root.offMode ? "#1A2030" : "#9DB4FF"

        Item {
            id: radarFace
            anchors.fill: parent
            anchors.margins: frame.faceInset
            visible: !root.offMode

            RadarFrameItem {
                id: radarPreview
                anchors.fill: parent
                source: root.frameReady ? root.frameUrl : ""
                mapSource: root.frameReady ? root.previewUrl : ""
                circular: true
                backgroundVisible: true
                guidesVisible: false
                visible: ready
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

        // Waiting / OFF face: calm glyph (muted when feature off; no amber dead-pod look)
        Column {
            anchors.centerIn: parent
            width: Math.round(frame.side * 0.50)
            spacing: root.offMode ? Math.max(2, Math.round(frame.side * 0.02)) : 0
            visible: root.offMode || !radarPreview.ready

            WidgetLocal.RadarGlyph {
                width: parent.width * (root.offMode ? 0.86 : 1.0)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                active: root.live
                primaryColor: root.offMode
                    ? Qt.rgba(0.72, 0.78, 0.88, 0.42)
                    : (active ? "#F7FBFF" : Qt.rgba(0.96, 0.98, 1.0, 0.70))
                accentColor: root.offMode
                    ? Qt.rgba(0.62, 0.72, 0.82, 0.38)
                    : (active ? "#58FFE1" : Qt.rgba(1.0, 0.82, 0.42, 0.88))
            }

            Text {
                width: parent.width
                visible: root.offMode
                text: "OFF"
                color: Qt.rgba(0.72, 0.78, 0.88, 0.55)
                font.family: root.monoFont
                font.pixelSize: Math.max(10, Math.floor(frame.side * 0.078))
                font.weight: Font.DemiBold
                font.letterSpacing: 1.1
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.featureEnabled
        onClicked: root.clicked()
    }
}
