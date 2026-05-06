import QtQuick 2.15
import BeagleY 1.0

Item {
    id: panel

    property var controller: null

    readonly property string displayFont: controller && controller.displayFont ? controller.displayFont : "Oxanium"
    readonly property string monoFont: controller && controller.monoFont ? controller.monoFont : "Oxanium"
    readonly property string radarStatus: controller && controller.radarStatus ? controller.radarStatus : "SYNC"
    readonly property string radarSiteName: controller && controller.radarSiteName ? controller.radarSiteName : ""
    readonly property string radarProduct: controller && controller.radarProduct ? controller.radarProduct : ""
    readonly property real radarSiteDistanceKm: controller ? controller.radarSiteDistanceKm : NaN
    readonly property url radarFrameUrl: controller ? controller.radarFrameUrl : ""
    readonly property bool detailRadarReady: controller ? controller.detailRadarReady : false
    readonly property bool radarFrameReady: detailRadarReady && String(radarFrameUrl).length > 0

    function formatDistanceKm(value) {
        return controller ? controller.formatDistanceKm(value) : "-- KM"
    }

    function radarSourceLabel() {
        return controller ? controller.radarSourceLabel() : radarStatus
    }

    function radarFrameDisplayLabel() {
        return controller ? controller.radarFrameDisplayLabel() : radarStatus
    }

    Rectangle {
        id: radarHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44
        color: "#070B12"
        border.width: 1
        border.color: "#245866"

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 6
            color: panel.radarStatus === "LIVE" ? "#58FFE1" : "#FFD36B"
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.46
            text: "GPS RADAR"
            color: "#F7FBFF"
            font.family: panel.monoFont
            font.pixelSize: 19
            font.weight: Font.Bold
            font.letterSpacing: 0
            elide: Text.ElideRight
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.44
            text: (panel.radarStatus === "LIVE" ? "LIVE  " : panel.radarStatus + "  ")
                + panel.radarFrameDisplayLabel()
            color: panel.radarStatus === "LIVE" ? "#58FFE1" : "#FFD36B"
            font.family: panel.monoFont
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 0
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    Rectangle {
        id: radarScope
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: radarHeader.bottom
        anchors.topMargin: 10
        anchors.bottom: radarTimeline.top
        anchors.bottomMargin: 10
        color: "#030B11"
        border.width: 1
        border.color: panel.radarStatus === "LIVE" ? "#2B7B88" : "#564C2C"
        clip: false

        Rectangle {
            id: radarMetaBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 30
            color: "#06131B"
            border.width: 1
            border.color: "#183B47"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.50
                text: panel.radarSiteName.length > 0 ? panel.radarSiteName : "GPS AREA"
                color: "#F7FBFF"
                font.family: panel.monoFont
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                text: panel.radarProduct.length > 0
                    ? panel.radarProduct
                    : panel.formatDistanceKm(panel.radarSiteDistanceKm)
                color: "#9DB4FF"
                font.family: panel.monoFont
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Item {
            id: radarMapBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: radarMetaBar.bottom
            anchors.bottom: radarReturnsBar.top
            clip: false

            RadarFrameItem {
                id: radarPreview
                anchors.fill: parent
                source: panel.radarFrameReady ? panel.radarFrameUrl : ""
                circular: false
                backgroundVisible: true
                guidesVisible: false
                visible: radarPreview.ready
                opacity: 0.98
            }

            Rectangle {
                anchors.fill: parent
                color: "#030B11"
                visible: !radarPreview.ready
            }

            Repeater {
                model: [
                    { "x": 0.13, "y": 0.62, "w": 0.05, "h": 0.025, "c": "#25D7FF" },
                    { "x": 0.19, "y": 0.65, "w": 0.065, "h": 0.030, "c": "#25D7FF" },
                    { "x": 0.27, "y": 0.69, "w": 0.080, "h": 0.035, "c": "#25D7FF" },
                    { "x": 0.36, "y": 0.73, "w": 0.086, "h": 0.040, "c": "#25D7FF" },
                    { "x": 0.46, "y": 0.78, "w": 0.092, "h": 0.045, "c": "#25D7FF" },
                    { "x": 0.32, "y": 0.60, "w": 0.052, "h": 0.026, "c": "#FFD75A" },
                    { "x": 0.43, "y": 0.66, "w": 0.058, "h": 0.026, "c": "#FFD75A" },
                    { "x": 0.56, "y": 0.72, "w": 0.046, "h": 0.024, "c": "#FF7045" },
                    { "x": 0.15, "y": 0.42, "w": 0.028, "h": 0.020, "c": "#FFD75A" },
                    { "x": 0.73, "y": 0.28, "w": 0.032, "h": 0.020, "c": "#26E38F" },
                    { "x": 0.70, "y": 0.45, "w": 0.018, "h": 0.012, "c": "#F7FBFF" }
                ]

                Rectangle {
                    x: Math.round(radarMapBody.width * modelData.x)
                    y: Math.round(radarMapBody.height * modelData.y)
                    width: Math.max(8, Math.round(radarMapBody.width * modelData.w))
                    height: Math.max(5, Math.round(radarMapBody.height * modelData.h))
                    visible: !radarPreview.ready
                    color: modelData.c
                    border.width: 1
                    border.color: "#02060B"
                }
            }
        }

        Rectangle {
            id: radarReturnsBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 36
            color: "#050A12"
            border.width: 1
            border.color: "#172E3B"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                text: radarPreview.ready ? "RADAR MAP" : "RADAR RETURNS"
                color: "#58FFE1"
                font.family: panel.monoFont
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0
                elide: Text.ElideRight
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.48
                text: panel.radarSourceLabel()
                color: "#F7FBFF"
                font.family: panel.monoFont
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }

    Row {
        id: radarTimeline
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: radarData.top
        anchors.bottomMargin: 10
        height: 30
        spacing: 6

        Repeater {
            model: ["-30", "-20", "-10", "NOW", "+10", "+20"]

            Rectangle {
                width: (radarTimeline.width - 30) / 6
                height: radarTimeline.height
                color: modelData === "NOW" ? "#123D45" : "#071019"
                border.width: 1
                border.color: modelData === "NOW" ? "#58FFE1" : "#1E3B48"

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: modelData === "NOW" ? "#F7FBFF" : "#9DB4FF"
                    font.family: panel.monoFont
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                }
            }
        }
    }

    Row {
        id: radarData
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 58
        spacing: 10

        Repeater {
            model: [
                { "k": "FRAME", "v": panel.radarFrameDisplayLabel(), "s": "time" },
                { "k": "SOURCE", "v": panel.radarSiteName.length > 0 ? panel.radarSiteName : "GPS", "s": panel.formatDistanceKm(panel.radarSiteDistanceKm) },
                { "k": "STATUS", "v": panel.radarStatus === "LIVE" ? "LIVE NOW" : panel.radarStatus, "s": panel.radarProduct.length > 0 ? panel.radarProduct : panel.radarSourceLabel() }
            ]

            Rectangle {
                width: (radarData.width - 20) / 3
                height: radarData.height
                color: "#0B111B"
                border.width: 1
                border.color: "#243949"

                Column {
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 1

                    Text {
                        width: parent.width
                        text: modelData.k
                        color: "#9DB4FF"
                        font.family: panel.monoFont
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: modelData.v
                        color: "#F7FBFF"
                        font.family: panel.monoFont
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: modelData.s
                        color: "#58FFE1"
                        font.family: panel.monoFont
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
