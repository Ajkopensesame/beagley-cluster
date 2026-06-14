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
    readonly property int radarInset: Math.max(6, Math.round(side * 0.040))
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

        RadarFrameItem {
            id: radarPreview
            width: 0
            height: 0
            source: root.frameReady ? root.frameUrl : ""
            mapSource: root.frameReady ? root.mapUrl : ""
            circular: false
            backgroundVisible: false
            guidesVisible: false
            visible: false
        }

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
            clip: false

            Rectangle {
                anchors.fill: parent
                radius: root.radarFaceRadius
                color: "#050B10"
            }

            Item {
                anchors.fill: parent
                anchors.margins: root.radarBorderWidth + 2
                opacity: root.live ? 1.0 : 0.58

                Repeater {
                    model: [0.36, 0.58, 0.80]

                    Rectangle {
                        width: Math.round(radarFace.width * modelData)
                        height: width
                        radius: width / 2
                        anchors.centerIn: parent
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.rgba(0.36, 1.0, 0.88, index === 2 ? 0.17 : 0.105)
                    }
                }

                Rectangle {
                    width: 1
                    height: Math.round(parent.height * 0.76)
                    anchors.centerIn: parent
                    color: Qt.rgba(0.36, 1.0, 0.88, 0.16)
                }

                Rectangle {
                    width: Math.round(parent.width * 0.76)
                    height: 1
                    anchors.centerIn: parent
                    color: Qt.rgba(0.36, 1.0, 0.88, 0.14)
                }

                Rectangle {
                    width: Math.max(2, Math.round(parent.width * 0.030))
                    height: width
                    radius: width / 2
                    anchors.centerIn: parent
                    color: Qt.rgba(0.90, 0.98, 1.0, 0.94)
                }
            }

            Repeater {
                model: radarPreview.ready ? radarPreview.samples : []

                Rectangle {
                    readonly property real blipScale: modelData.scale ? modelData.scale : 1.0
                    readonly property int blipSize: Math.max(3, Math.round(root.side * 0.019 * blipScale))

                    width: blipSize
                    height: blipSize
                    radius: blipSize / 2
                    x: root.radarInset + Math.round((radarFace.width - root.radarInset * 2) * modelData.x - width / 2)
                    y: root.radarInset + Math.round((radarFace.height - root.radarInset * 2) * modelData.y - height / 2)
                    color: modelData.color ? modelData.color : "#72D8FF"
                    border.width: 1
                    border.color: Qt.rgba(0.96, 1.0, 1.0, 0.50)
                    visible: root.frameReady
                }
            }

            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: Math.round(root.side * 0.040)
                anchors.topMargin: Math.round(root.side * 0.032)
                text: "RADAR"
                color: root.live ? Qt.rgba(0.36, 1.0, 0.88, 0.72) : Qt.rgba(1.0, 0.83, 0.42, 0.72)
                font.family: root.monoFont
                font.pixelSize: Math.max(7, Math.floor(root.side * 0.045))
                font.weight: Font.Bold
                font.letterSpacing: 0
                renderType: Text.QtRendering
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
