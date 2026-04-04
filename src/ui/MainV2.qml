import QtQuick 2.15
import QtQuick.Window 2.15

import "./theme" as Theme
import "widgets" as W

Window {
    id: root

    width: 1920
    height: 720
    minimumWidth: 1920
    minimumHeight: 720
    maximumWidth: 1920
    maximumHeight: 720

    visibility: Window.Windowed
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    visible: true

    Theme.PurplePearlTheme { id: appTheme }
    color: appTheme.bg
    readonly property string mapRenderer: (typeof BEAGLEY_MAP_RENDERER !== "undefined" && BEAGLEY_MAP_RENDERER)
        ? String(BEAGLEY_MAP_RENDERER)
        : "native"

    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale
    readonly property bool truthOk: linkOk && !hub.bbbStale
    readonly property bool fallbackRouteOriginEnabled: !truthOk
    readonly property real fallbackRouteOriginLat: -27.4698
    readonly property real fallbackRouteOriginLng: 153.0251
    readonly property string fallbackRouteOriginLabel: "Brisbane City QLD"

    readonly property int activeWarnings: {
        if (!truthOk || !hub) return 0
        var n = 0
        if (hub.warnBrake) n++
        if (hub.warnOil) n++
        if (hub.warnCharge) n++
        if (hub.warnDoor) n++
        if (hub.warnCheckEngine) n++
        if (hub.warnAT) n++
        if (hub.warnFuelLow) n++
        return n
    }

    function warningSummary() {
        if (!truthOk || !hub) return "NO LIVE VEHICLE DATA"
        var parts = []
        if (hub.warnBrake) parts.push("BRAKE")
        if (hub.warnOil) parts.push("OIL")
        if (hub.warnCharge) parts.push("CHARGE")
        if (hub.warnDoor) parts.push("DOOR")
        if (hub.warnCheckEngine) parts.push("CHECK")
        if (hub.warnAT) parts.push("A/T")
        if (hub.warnFuelLow) parts.push("FUEL")
        return parts.length > 0 ? parts.join("  •  ") : "ALL SYSTEMS NOMINAL"
    }

    Component.onCompleted: {
        root.showNormal()
        root.raise()
        root.requestActivate()
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#05070B" }
            GradientStop { position: 0.48; color: "#0B1220" }
            GradientStop { position: 1.00; color: "#06080E" }
        }
    }

    Canvas {
        id: backGrid
        anchors.fill: parent
        opacity: 0.32
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "rgba(105,146,196,0.20)"
            ctx.lineWidth = 1
            const pitch = 56
            for (var x = 0; x < width; x += pitch) {
                ctx.beginPath()
                ctx.moveTo(x + 0.5, 0)
                ctx.lineTo(x + 0.5, height)
                ctx.stroke()
            }
            for (var y = 0; y < height; y += pitch) {
                ctx.beginPath()
                ctx.moveTo(0, y + 0.5)
                ctx.lineTo(width, y + 0.5)
                ctx.stroke()
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    Rectangle {
        id: topRibbon
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        height: 82
        radius: 16
        color: "#111A26"
        border.width: 1
        border.color: "#324761"

        Item {
            anchors.fill: parent
            anchors.margins: 16

            Row {
                id: leftStatus
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 28

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    color: truthOk ? "#16D64D" : (linkOk ? "#E3A322" : "#D83333")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#DCEBFF"
                    font.pixelSize: 24
                    font.family: appTheme.fontAccent
                    text: truthOk ? "LIVE DATA" : (linkOk ? "BBB STALE" : "LINK DOWN")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#DCEBFF"
                    font.pixelSize: 22
                    font.family: appTheme.fontMono
                    text: "GEAR " + (truthOk ? (hub.gear || "-") : "-")
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: (truthOk && hub.overdrive) ? "#FFCC4D" : "#7488A5"
                    font.pixelSize: 22
                    font.family: appTheme.fontMono
                    text: "O/D"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: (truthOk && hub.highBeam) ? "#5FD4FF" : "#7488A5"
                    font.pixelSize: 22
                    font.family: appTheme.fontMono
                    text: "HIGH"
                }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                color: "#BFD1E7"
                font.pixelSize: 18
                font.family: appTheme.fontMono
                text: "LAT " + ((truthOk && hub.gpsLat !== undefined) ? hub.gpsLat.toFixed(5) : "--.--")
                    + "   LNG " + ((truthOk && hub.gpsLng !== undefined) ? hub.gpsLng.toFixed(5) : "--.--")
            }
        }
    }

    Item {
        id: stage
        anchors.top: topRibbon.bottom
        anchors.bottom: bottomRibbon.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        anchors.topMargin: 12
        anchors.bottomMargin: 12

        Item {
            id: leftPanel
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * 0.32
        }

        Item {
            id: centerPanel
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: leftPanel.right
            anchors.right: rightPanel.left
        }

        Item {
            id: rightPanel
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: parent.width * 0.32
        }

        Rectangle {
            anchors.fill: leftPanel
            anchors.margins: 10
            radius: 28
            color: "#0D141E"
            border.width: 1
            border.color: "#29405A"
        }

        W.SpeedGauge {
            id: speedGauge
            z: 10
            anchors.centerIn: leftPanel
            width: Math.min(leftPanel.width * 0.94, leftPanel.height * 0.94)
            height: width
            theme: appTheme
            vehicleState: hub
            maxSpeed: 140
            speed: truthOk ? (hub.speedKph || 0) : 0
            coolantC: truthOk ? (hub.coolantC || 0) : 0
        }

        Rectangle {
            id: mapShell
            anchors.fill: centerPanel
            anchors.margins: 10
            radius: 28
            color: "#0A111A"
            border.width: 1
            border.color: "#2C4868"
            clip: true
        }

        W.MapCenter {
            anchors.fill: mapShell
            anchors.margins: 10
            mode: (typeof BEAGLEY_NO_MAP !== "undefined" && BEAGLEY_NO_MAP)
                ? "placeholder"
                : ((root.mapRenderer === "web"
                    && !(typeof BEAGLEY_FORCE_SNAPSHOT_MAP !== "undefined" && BEAGLEY_FORCE_SNAPSHOT_MAP))
                    ? "web"
                    : "snapshot")
            lat: truthOk && hub.gpsLat !== undefined ? hub.gpsLat : -27.4698
            lng: truthOk && hub.gpsLng !== undefined ? hub.gpsLng : 153.0251
            bearing: truthOk && hub.gpsBearing !== undefined ? hub.gpsBearing : 0
            speedKph: truthOk ? (hub.speedKph || 0) : 0
            fixedOriginEnabled: fallbackRouteOriginEnabled
            fixedOriginLat: fallbackRouteOriginLat
            fixedOriginLng: fallbackRouteOriginLng
            fixedOriginLabel: fallbackRouteOriginLabel
            snapshotRefreshMs: 15000
            videoEnabled: false
            videoUrl: ""
        }

        Text {
            anchors.left: mapShell.left
            anchors.top: mapShell.top
            anchors.margins: 18
            color: "#BFD1E7"
            font.pixelSize: 20
            font.family: appTheme.fontAccent
            text: "NAVIGATION"
        }

        Rectangle {
            anchors.right: mapShell.right
            anchors.top: mapShell.top
            anchors.margins: 16
            width: 98
            height: 44
            radius: 22
            color: "#0D1C2D"
            border.width: 1
            border.color: "#2A5F8F"

            Text {
                anchors.centerIn: parent
                color: "#8DD6FF"
                font.pixelSize: 17
                font.family: appTheme.fontMono
                text: Math.round(truthOk && hub.gpsBearing !== undefined ? hub.gpsBearing : 0) + "°"
            }
        }

        Rectangle {
            anchors.fill: rightPanel
            anchors.margins: 10
            radius: 28
            color: "#0D141E"
            border.width: 1
            border.color: "#29405A"
        }

        W.TachGauge {
            id: tachGauge
            z: 10
            anchors.centerIn: rightPanel
            width: Math.min(rightPanel.width * 0.94, rightPanel.height * 0.94)
            height: width
            theme: appTheme
            vehicleState: hub
            rpm: truthOk ? (hub.rpm || 0) : 0
            fuelPct: truthOk ? (hub.fuelPct || 0) : 0
        }

        W.TurnChevronFlow {
            parent: speedGauge
            anchors.top: parent.top
            anchors.topMargin: -28
            anchors.right: parent.right
            anchors.rightMargin: 18
            chevrons: 12
            active: truthOk && !!hub.leftIndicator
            side: "left"
            thickness: 6
        }

        W.TurnChevronFlow {
            parent: tachGauge
            anchors.top: parent.top
            anchors.topMargin: -28
            anchors.left: parent.left
            anchors.leftMargin: 18
            chevrons: 12
            active: truthOk && !!hub.rightIndicator
            side: "right"
            thickness: 6
        }
    }

    Rectangle {
        id: bottomRibbon
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        height: 70
        radius: 16
        color: activeWarnings > 0 ? "#2A1214" : "#101822"
        border.width: 1
        border.color: activeWarnings > 0 ? "#8E2D34" : "#2E475F"

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 18
            color: activeWarnings > 0 ? "#FF8C98" : "#C9D8EA"
            font.pixelSize: 22
            font.family: appTheme.fontMono
            text: warningSummary()
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: 18
            color: "#9CB8D8"
            font.pixelSize: 20
            font.family: appTheme.fontMono
            text: "SPD " + Math.round(truthOk ? (hub.speedKph || 0) : 0)
                + "  RPM " + Math.round(truthOk ? (hub.rpm || 0) : 0)
        }
    }

    W.WiFiSetupOverlay {
        id: wifiOverlay
        anchors.fill: parent
        wifi: (typeof wifiSetup !== "undefined") ? wifiSetup : null
        theme: appTheme
    }
}
