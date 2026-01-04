import QtQuick 2.15
import QtQuick.Window 2.15

import "./theme" as Theme
import "mock"
import BeagleY 1.0

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

    // Theme instance (was undefined before)
    Theme.PurplePearlTheme { id: appTheme }

    color: appTheme.bg

    // Mock data (replace with real VehicleState provider later)
    MockVehicleState { id: vehicle }

    Component.onCompleted: {
        // Hard-force windowed preview on macOS
        root.showNormal();
        root.raise();
        root.requestActivate();

        // Best-effort: follow system palette if available
        if (Qt.application && Qt.application.palette) {
            appTheme.updateFromSystem(Qt.application.palette);
        }
    }

    // Lightweight poll to keep theme aligned with system changes.
    // (Qt.application paletteChanged isn't consistently exposed across setups.)
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (Qt.application && Qt.application.palette) {
                appTheme.updateFromSystem(Qt.application.palette);
            }
        }
    }

    // --- Layout panels (3 columns: left / center / right) ---
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

    // Background effect
    MatrixRain {
        anchors.fill: parent
        rainColor: Qt.rgba(gauge.gaugeColor.r, gauge.gaugeColor.g, gauge.gaugeColor.b, 0.45)
        fps: 10
        speedMultiplier: 0.10
        density: 0.12
        fontPx: 11
        fadeAlpha: 0.04
        columns: 0
    }

    // ===== Left (Speed) =====
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


    // ===== Center (Map) =====
    MapCenter {
        id: map
        anchors.fill: centerPanel
    }


    // ===== Right (Tach) =====
    TachGauge {
        id: tach
        anchors.centerIn: rightPanel
        theme: appTheme
        rpm: vehicle.rpm

        fuelPct: vehicle.fuelPct
        width: Math.min(rightPanel.width * 0.92, rightPanel.height * 0.92)
        height: width
    }
    // Debug overlay
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        color: "#80FFFFFF"
        font.pixelSize: 16
        text: "speed: " + Math.round(vehicle.speedKph) + "  target: " + Math.round(vehicle.targetSpeedKph)
    }
}
