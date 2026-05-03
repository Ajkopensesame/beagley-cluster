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
    readonly property string effectLevel: (typeof BEAGLEY_EFFECT_LEVEL !== "undefined" && BEAGLEY_EFFECT_LEVEL)
        ? String(BEAGLEY_EFFECT_LEVEL)
        : "high"
    readonly property string mapRenderer: (typeof BEAGLEY_MAP_RENDERER !== "undefined" && BEAGLEY_MAP_RENDERER)
        ? String(BEAGLEY_MAP_RENDERER)
        : "native"
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    property real sharedEffectPhase: 0.0

    // ===============================
    // BBB truth source (C++ context property must be named: vehicleState)
    // ===============================
    // IMPORTANT:
    // We alias it to `hub` to avoid binding loops when components also have a `vehicleState` property.
    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale
    readonly property bool truthOk: linkOk && !hub.bbbStale

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

    Timer {
        interval: lowEffectMode ? 140 : 90
        running: effectLevel !== "off"
        repeat: true
        onTriggered: root.sharedEffectPhase += interval / 1000.0
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
        clip: true
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
        effectEnabled: effectLevel !== "off"
        effectLevel: root.effectLevel
        sharedPhase: root.sharedEffectPhase
        rainColor: Qt.rgba(gauge.gaugeColor.r,
                           gauge.gaugeColor.g,
                           gauge.gaugeColor.b,
                           0.45)
        fps: 12
        speedMultiplier: 0.13
        density: 0.22
        fontPx: 10
        fadeAlpha: 0.036
        tailLength: 32
        headAlpha: 0.76
        tailMinAlpha: 0.08
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
        speed:    truthOk ? (hub.speedKph || 0) : 0
        coolantC: truthOk ? (hub.coolantC || 0) : 0
        effectLevel: root.effectLevel
        matrixRainEnabled: !root.lowEffectMode
        matrixRainSharedPhase: root.sharedEffectPhase

        width: Math.min(leftPanel.width * 0.92, leftPanel.height * 0.92)
        height: width
    }

        // ===============================
    // Center — MapCenter
    // ===============================
    W.MapCenter {
        anchors.fill: centerPanel

        mode: ((typeof BEAGLEY_NO_MAP !== "undefined" && BEAGLEY_NO_MAP)
                && root.mapRenderer !== "maplibre-native")
            ? "placeholder"
            : (root.mapRenderer === "maplibre-native"
                ? "maplibre-native"
                : (root.mapRenderer === "web" ? "web" : "snapshot"))

        // Static OSM snapshot (centered by live GPS), cache-busted in MapCenterSnapshot.refresh().
        snapshotUrl: "https://staticmap.openstreetmap.de/staticmap.php?center="
            + (truthOk && hub.gpsLat !== undefined ? hub.gpsLat : -27.4698).toFixed(5)
            + ","
            + (truthOk && hub.gpsLng !== undefined ? hub.gpsLng : 153.0251).toFixed(5)
            + "&zoom=13&size=800x800"
        snapshotRefreshMs: 0

        // GPS (safe if fields not present yet)
        lat: truthOk && hub.gpsLat !== undefined ? hub.gpsLat : -27.4698
        lng: truthOk && hub.gpsLng !== undefined ? hub.gpsLng : 153.0251
        bearing: truthOk && hub.gpsBearing !== undefined ? hub.gpsBearing : 0
        mapVehiclePose: (typeof navigation !== "undefined" && navigation) ? navigation.mapVehiclePose : ({})
        mapCameraHints: (typeof navigation !== "undefined" && navigation) ? navigation.mapCameraHints : ({})
        mapRouteOverlay: (typeof navigation !== "undefined" && navigation) ? navigation.mapRouteOverlay : ({})
        mapGuidanceBanner: (typeof navigation !== "undefined" && navigation) ? navigation.mapGuidanceBanner : ({})
        mapConnectivity: (typeof navigation !== "undefined" && navigation) ? navigation.mapConnectivity : ({})

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

        rpm:     truthOk ? (hub.rpm || 0) : 0
        fuelPct: truthOk ? (hub.fuelPct || 0) : 0
        effectLevel: root.effectLevel
        matrixRainEnabled: !root.lowEffectMode
        matrixRainSharedPhase: root.sharedEffectPhase

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
        text: truthOk ? ("speed: " + Math.round(hub.speedKph || 0))
                      : (linkOk ? "speed: (BBB STALE)" : "speed: (LINK STALE)")
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

        active: truthOk && !!hub.leftIndicator
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

        active: truthOk && !!hub.rightIndicator
        side: "right"
        thickness: 6
    }

    W.WiFiSetupOverlay {
        id: wifiOverlay
        anchors.fill: parent
        wifi: (typeof wifiSetup !== "undefined") ? wifiSetup : null
        theme: appTheme
    }
}
