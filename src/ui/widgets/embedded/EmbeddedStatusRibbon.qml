import QtQuick 2.15

Rectangle {
    id: root

    property var cluster
    property var wifi
    property string fontFamily: "sans-serif"
    signal wifiRequested()

    readonly property bool wifiPresent: !!root.wifi
    readonly property string wifiState: root.wifiPresent ? String(root.wifi.networkState || "waiting_for_hotspot") : "unavailable"
    readonly property bool wifiOnline: root.wifiState === "online"
    readonly property bool wifiLinked: root.wifiPresent && root.wifi.connected && root.wifi.hasIpLease
    readonly property string wifiSsid: root.wifiPresent && root.wifi.currentSsid ? String(root.wifi.currentSsid) : "--"
    readonly property string wifiIp: root.wifiPresent && root.wifi.ipv4Address ? String(root.wifi.ipv4Address).split("/")[0] : ""
    readonly property bool wifiSignalKnown: root.wifiPresent && Number(root.wifi.signalDbm) > -998
    readonly property string wifiMeta: {
        if (!root.wifiPresent) {
            return "SERVICE N/A"
        }
        if (root.wifiIp.length > 0 && root.wifiSignalKnown) {
            return root.wifiIp + "  " + Math.round(Number(root.wifi.signalDbm)) + " dBm"
        }
        if (root.wifiIp.length > 0) {
            return root.wifiIp
        }
        if (root.wifiSignalKnown) {
            return Math.round(Number(root.wifi.signalDbm)) + " dBm"
        }
        return root.wifiState.toUpperCase()
    }

    color: "#0A1220"
    border.color: "#16314C"
    border.width: 1

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Rectangle {
            width: 180
            height: 42
            radius: 18
            color: root.cluster.truthOk ? "#113223" : "#341717"
            border.color: root.cluster.truthOk ? "#2DA56A" : "#B64040"
            border.width: 1

            Text {
                anchors.centerIn: parent
                color: "white"
                font.family: root.fontFamily
                font.pixelSize: 26
                font.bold: true
                text: root.cluster.statusText
            }
        }

        Rectangle {
            width: 240
            height: 42
            radius: 18
            color: "#0D1C2D"
            border.color: "#1B4667"
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#8EC9FF"
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    text: "NETWORK"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 26
                    font.bold: true
                    text: root.cluster.networkText
                }
            }
        }

        Rectangle {
            width: 360
            height: 42
            radius: 18
            color: root.wifiOnline ? "#0F2F23" : (root.wifiLinked ? "#302816" : "#301A1A")
            border.color: root.wifiOnline ? "#2EA66B" : (root.wifiLinked ? "#D39A32" : "#B74444")
            border.width: 1

            Column {
                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: root.wifiOnline ? "#8AF0B7" : "#FFC76B"
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    text: "WIFI  " + root.wifiSsid
                    elide: Text.ElideRight
                    width: 328
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    text: root.wifiMeta
                    elide: Text.ElideRight
                    width: 328
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.wifiRequested()
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
            model: [
                { label: "OD", active: root.cluster.overdrive, activeColor: "#FFB03B" },
                { label: "HI", active: root.cluster.highBeam, activeColor: "#4CD9FF" },
                { label: root.cluster.drivetrainMode, active: true, activeColor: "#D8F4FF" },
                { label: "GEAR " + root.cluster.gear, active: true, activeColor: "#FFFFFF" }
            ]

            delegate: Rectangle {
                width: 110
                height: 42
                radius: 14
                color: modelData.active ? "#112233" : "#0A1018"
                border.color: modelData.active ? modelData.activeColor : "#233646"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    color: modelData.active ? modelData.activeColor : "#6E8397"
                    font.family: root.fontFamily
                    font.pixelSize: 18
                    font.bold: true
                    text: modelData.label
                }
            }
        }
    }
}
