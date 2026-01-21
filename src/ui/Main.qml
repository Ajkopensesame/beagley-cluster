import QtQuick 2.15
import QtQuick.Window 2.15

import "./theme" as Theme
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
    // BBB truth source (C++ context property must be named: vehicleState)
    // ===============================
    // IMPORTANT:
    // We alias it to `hub` to avoid binding loops when components also have a `vehicleState` property.
    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale

    Component.onCompleted: {
        root.showNormal()
        root.raise()
        root.requestActivate()

        if (Qt.application && Qt.application.palette) {
            appTheme.updateFromSystem(Qt.application.palette)
        }
    }

    // Keep: system palette can change (night mode etc.)
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
    // Left gauge (Speed)
    // ===============================
    SpeedGauge {
        id: gauge
        anchors.centerIn: leftPanel
        theme: appTheme

        // Pass BBB truth object (alias avoids binding loop)
        vehicleState: hub

        // Drive values from BBB truth with stale-safe fallback
        speed:    linkOk ? (hub.speedKph || 0) : 0
        coolantC: linkOk ? (hub.coolantC || 0) : 0

        width: Math.min(leftPanel.width * 0.92, leftPanel.height * 0.92)
        height: width
    }

        // ===============================
    // Center — MapCenter (NO WebEngine)
    // ===============================
    W.MapCenter {
        anchors.fill: centerPanel

        // Stable core modes: placeholder/snapshot/video
        mode: "placeholder"

        // Snapshot mode (later from BBB)
        snapshotUrl: ""

        // GPS (safe if fields not present yet)
        lat: linkOk && hub.gpsLat !== undefined ? hub.gpsLat : 0
        lng: linkOk && hub.gpsLng !== undefined ? hub.gpsLng : 0
        bearing: linkOk && hub.gpsBearing !== undefined ? hub.gpsBearing : 0

        // Camera-ready (off until later)
        videoEnabled: false
        videoUrl: ""
    }
    // ===============================
    // Right gauge (Tach)
    // ===============================
    TachGauge {
        id: tach
        anchors.centerIn: rightPanel
        theme: appTheme

        // Pass BBB truth for VIC + warnings
        vehicleState: hub

        rpm:     linkOk ? (hub.rpm || 0) : 0
        fuelPct: linkOk ? (hub.fuelPct || 0) : 0

        width: Math.min(rightPanel.width * 0.92, rightPanel.height * 0.92)
        height: width
    }

    // ===============================
    // Debug (truth-only)
    // ===============================
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        color: "#80FFFFFF"
        font.pixelSize: 16
        text: linkOk ? ("speed: " + Math.round(hub.speedKph || 0)) : "speed: (STALE)"
    }

    // ===============================
    // Turn indicators (truth-only + stale gating)
    // ===============================
    W.TurnChevronFlow {
        id: leftTurnFlow
        chevrons: 12
        parent: gauge
        anchors.top: parent.top
        anchors.topMargin: -28
        anchors.right: parent.right
        anchors.rightMargin: 18

        active: linkOk && !!hub.leftIndicator
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

        active: linkOk && !!hub.rightIndicator
        side: "right"
        thickness: 6
    }
}
