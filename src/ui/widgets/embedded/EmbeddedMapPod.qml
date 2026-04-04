import QtQuick 2.15

import BeagleY 1.0

Rectangle {
    id: root

    property var cluster
    property var metrics
    property color panelFill: "#081220"
    property color panelStroke: "#14324A"

    radius: 34
    color: panelFill
    border.color: panelStroke
    border.width: 1

    NativeRasterMapItem {
        id: liveMap
        anchors.fill: parent
        anchors.margins: 16
        clip: true
        centerLat: root.cluster.mapLat
        centerLng: root.cluster.mapLng
        zoom: root.cluster.mapZoom
        vehicleBearing: root.cluster.mapBearing
        vehicleVisible: root.cluster.gpsOk
        routePath: root.cluster.routePath
        userAgent: "BeagleyCluster/1.0 (native-online)"
        metrics: root.metrics
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        height: 92
        radius: 26
        color: "#0A1422CC"
        border.color: "#1B4767"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 4

            Text {
                color: "#7BA5C9"
                font.pixelSize: 15
                text: "GUIDANCE"
            }

            Text {
                color: "white"
                font.pixelSize: 26
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
                text: root.cluster.nextInstruction.length > 0 ? root.cluster.nextInstruction : "Following live route"
            }

            Text {
                color: "#C7DAE8"
                font.pixelSize: 17
                elide: Text.ElideRight
                width: parent.width
                text: root.cluster.guidanceDetail.length > 0 ? root.cluster.guidanceDetail : "Waiting for route guidance"
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 16
        height: 66
        radius: 24
        color: "#09111CCC"
        border.color: "#1B4767"
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "#8EC9FF"
                font.pixelSize: 18
                text: root.cluster.gpsOk ? "GPS LIVE" : "GPS HOLD"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "white"
                font.pixelSize: 18
                text: root.cluster.etaText.length > 0 ? ("ETA " + root.cluster.etaText) : "ETA --"
            }

            Item {
                width: 1
                height: 1
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: "#C7DAE8"
                font.pixelSize: 18
                text: Qt.formatDateTime(new Date(), "hh:mm")
            }
        }
    }
}
