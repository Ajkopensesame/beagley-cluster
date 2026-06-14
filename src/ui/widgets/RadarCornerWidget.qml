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
    readonly property real side: Math.min(width, height)
    readonly property int radarFaceSize: Math.round(side * 0.66)
    readonly property int radarBorderWidth: Math.max(2, Math.round(side * 0.014))
    readonly property int radarFaceRadius: Math.max(6, Math.round(side * 0.045))
    readonly property string compactLabel: root.live
        ? (root.frameLabel.length > 0 ? root.frameLabel : "RADAR")
        : (root.status.length > 0 ? root.status : "SYNC")

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live
        accentColor: "#58FFE1"
        secondaryAccentColor: "#9DB4FF"

        Item {
            id: radarFace
            width: root.radarFaceSize
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenterOffset: root.corner === "topRight" || root.corner === "bottomRight"
                ? -Math.round(frame.side * 0.050)
                : Math.round(frame.side * 0.050)
            anchors.verticalCenterOffset: root.corner === "topLeft" || root.corner === "topRight"
                ? Math.round(frame.side * 0.060)
                : -Math.round(frame.side * 0.060)
            clip: true

            Rectangle {
                anchors.fill: parent
                radius: root.radarFaceRadius
                color: "#071015"
            }

            RadarFrameItem {
                id: radarPreview
                anchors.fill: parent
                anchors.margins: 0
                source: root.frameReady ? root.frameUrl : ""
                mapSource: root.frameReady ? root.mapUrl : ""
                circular: false
                backgroundVisible: true
                guidesVisible: false
                visible: ready
                opacity: 1.0
            }

            Rectangle {
                anchors.fill: parent
                radius: root.radarFaceRadius
                color: "transparent"
                border.width: root.radarBorderWidth
                border.color: Qt.rgba(0.0, 0.0, 0.0, 0.90)
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: root.radarBorderWidth
                radius: Math.max(2, root.radarFaceRadius - root.radarBorderWidth)
                color: "transparent"
                border.width: 1
                border.color: root.live ? Qt.rgba(0.36, 1.0, 0.88, 0.34) : Qt.rgba(0.95, 0.98, 1.0, 0.16)
            }
        }

        Item {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.corner === "topRight" || root.corner === "bottomRight"
                ? -Math.round(frame.side * 0.050)
                : Math.round(frame.side * 0.050)
            anchors.verticalCenterOffset: root.corner === "topLeft" || root.corner === "topRight"
                ? Math.round(frame.side * 0.060)
                : -Math.round(frame.side * 0.060)
            width: Math.round(root.side * 0.34)
            height: width
            visible: !radarPreview.ready

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(root.side * 0.54)
                height: width
                radius: width / 2
                color: Qt.rgba(0.01, 0.02, 0.04, 0.72)
                border.width: root.radarBorderWidth
                border.color: Qt.rgba(0.0, 0.0, 0.0, 0.86)
            }

            WidgetLocal.RadarGlyph {
                width: parent.width
                height: width
                anchors.centerIn: parent
                active: root.status === "LIVE"
            }
        }

        Text {
            width: Math.round(frame.side * 0.58)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(frame.side * 0.245)
            text: root.compactLabel
            color: root.live ? "#58FFE1" : "#FFD36B"
            font.family: root.monoFont
            font.pixelSize: Math.max(8, Math.floor(frame.side * 0.055))
            font.weight: Font.Bold
            font.letterSpacing: 0
            fontSizeMode: Text.Fit
            minimumPixelSize: 7
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            renderType: Text.QtRendering
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
