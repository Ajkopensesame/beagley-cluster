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
    readonly property bool weatherPositionReady: controller ? controller.weatherPositionReady : false
    readonly property bool radarServiceAvailable: controller ? controller.radarServiceAvailable : false

    function formatDistanceKm(value) {
        return controller ? controller.formatDistanceKm(value) : "-- KM"
    }

    function radarSourceLabel() {
        return controller ? controller.radarSourceLabel() : radarStatus
    }

    function radarFrameDisplayLabel() {
        return controller ? controller.radarFrameDisplayLabel() : radarStatus
    }

    function radarUnavailableTitle() {
        if (!weatherPositionReady)
            return "WAITING FOR GPS"
        if (!radarServiceAvailable)
            return "RADAR SERVICE OFFLINE"
        if (radarStatus === "LIVE")
            return "RADAR FRAME LOADING"
        return radarStatus.length > 0 ? radarStatus : "RADAR SYNC"
    }

    function radarUnavailableDetail() {
        if (!weatherPositionReady)
            return "Live GPS has not reached the weather/radar path yet."
        if (!radarServiceAvailable)
            return "Radar renderer is not available in this build."
        if (radarStatus === "OFFLINE")
            return "No radar tiles were received. Check BeagleY internet first."
        if (radarStatus === "NO GPS")
            return "No valid GPS coordinate is available for radar."
        if (radarStatus === "SYNC")
            return "Waiting for the first real radar frame."
        return "No real radar frame is ready yet."
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
                source: panel.visible && panel.radarFrameReady ? panel.radarFrameUrl : ""
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

            Column {
                width: Math.min(parent.width - 42, 360)
                anchors.centerIn: parent
                spacing: 10
                visible: !radarPreview.ready

                Text {
                    width: parent.width
                    text: panel.radarUnavailableTitle()
                    color: "#FFD36B"
                    font.family: panel.displayFont
                    font.pixelSize: 27
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: panel.radarUnavailableDetail()
                    color: "#F7FBFF"
                    font.family: panel.monoFont
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
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
                text: radarPreview.ready ? "RADAR MAP" : "RADAR STATUS"
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
