import QtQuick 2.15
import QtQuick.Window 2.15
import QtWebEngine

import "./theme" as Theme
import "mock"
import BeagleY 1.0
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

    // ===============================
    // Theme
    // ===============================
    Theme.PurplePearlTheme { id: appTheme }
    color: appTheme.bg

    // ===============================
    // Mock vehicle data
    // ===============================
    MockVehicleState { id: vehicle }

    Component.onCompleted: {
        root.showNormal()
        root.raise()
        root.requestActivate()

        if (Qt.application && Qt.application.palette) {
            appTheme.updateFromSystem(Qt.application.palette)
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (Qt.application && Qt.application.palette) {
                appTheme.updateFromSystem(Qt.application.palette)
            }
        }
    }

    // ===============================
    // Layout panels
    // ===============================
    Item {
        id: leftPanel
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: parent.width / 3
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
        width: parent.width / 3
    }

    // ===============================
    // Background
    // ===============================
    MatrixRain {
        anchors.fill: parent
        rainColor: Qt.rgba(gauge.gaugeColor.r,
                           gauge.gaugeColor.g,
                           gauge.gaugeColor.b,
                           0.45)
        fps: 10
        speedMultiplier: 0.10
        density: 0.12
        fontPx: 11
        fadeAlpha: 0.04
        columns: 0
    }

    // ===============================
    // Left gauge
    // ===============================
    SpeedGauge {
        id: gauge
        anchors.centerIn: leftPanel
        theme: appTheme
        vehicleState: vehicle
        speed: vehicle.speedKph
        coolantC: vehicle.coolantC
        width: Math.min(leftPanel.width * 0.92, leftPanel.height * 0.92)
        height: width
    }

    // ===============================
    // Center — WebEngine (Stage M1)
    // ===============================
    MapCenterWeb {
        anchors.fill: centerPanel
    }

    // ===============================
    // Right gauge
    // ===============================
    TachGauge {
        id: tach
        anchors.centerIn: rightPanel
        theme: appTheme
        rpm: vehicle.rpm
        fuelPct: vehicle.fuelPct
        width: Math.min(rightPanel.width * 0.92, rightPanel.height * 0.92)
        height: width
    }

    // ===============================
    // Debug
    // ===============================
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        color: "#80FFFFFF"
        font.pixelSize: 16
        text: "speed: " + Math.round(vehicle.speedKph)
    }

    // ===============================
    // Turn indicators
    // ===============================
    W.TurnChevronFlow {
        id: leftTurnFlow
        chevrons: 12
        parent: gauge
        anchors.top: parent.top
        anchors.topMargin: -28
        anchors.right: parent.right
        anchors.rightMargin: 18
        active: !!vehicle.left_indicator
        side: "left"
        thickness: 6
    }

    W.TurnChevronFlow {
        id: rightTurnFlow
        chevrons: 12
        parent: tach
        anchors.top: parent.top
        anchors.topMargin: -28
        anchors.left: parent.left
        anchors.leftMargin: 18
        active: !!vehicle.right_indicator
        side: "right"
        thickness: 6
    }
}
