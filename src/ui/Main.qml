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
    // Background (demo flair — gated by BEAGLEY_DEMO_SKIN)
    // ===============================
    MatrixRain {
        anchors.fill: parent
        visible: BEAGLEY_DEMO_SKIN
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
    // Center — map (optional WebEngine) or placeholder
    // BEAGLEY_NO_MAP is always true when built with WITH_WEBENGINE=OFF.
    // MapCenterWeb.qml is only in the QML module when WITH_WEBENGINE=ON,
    // so use a string Loader URL (no static type / QtWebEngine import).
    // ===============================
    Loader {
        anchors.fill: centerPanel
        source: BEAGLEY_NO_MAP
               ? Qt.resolvedUrl("widgets/MapCenter.qml")
               : Qt.resolvedUrl("widgets/MapCenterWeb.qml")
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
    // Debug HUD (demo flair — gated by BEAGLEY_DEMO_SKIN)
    // ===============================
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        visible: BEAGLEY_DEMO_SKIN
        color: "#80FFFFFF"
        font.pixelSize: 16
        text: linkOk ? ("speed: " + Math.round(hub.speedKph || 0)) : "speed: (STALE)"
    }

    // ===============================
    // Link fail-safe affordance (product skin; never invent values)
    // Gauges already zero + VIC/turns gated when !linkOk.
    // ===============================
    Text {
        id: linkStatusBanner
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 14
        visible: !linkOk
        z: 200
        color: appTheme.danger
        font.pixelSize: 18
        font.bold: true
        font.letterSpacing: 3
        opacity: 0.95
        text: {
            if (!hub)
                return "NO LINK"
            if (!hub.connected)
                return "DISCONNECTED"
            if (hub.linkStale)
                return "STALE"
            return "NO LINK"
        }
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
