import QtQuick 2.15
import QtQuick.Window 2.15
import BeagleY 1.0

Window {
    id: root
    width: 1920
    minimumWidth: 1920
    maximumWidth: 1920
    height: 720
    minimumHeight: 720
    maximumHeight: 720
    visibility: Window.Windowed
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    visible: true
    color: "black"


    Component.onCompleted: {
        // Hard-force windowed preview on macOS
        root.showNormal();
        root.raise();
        root.requestActivate();
    }
    // --- Demo "vehicle" model (speed changes like a real car) ---
    property real speedKph: 0
    property real targetSpeedKph: 0
    property real accelKphPerSec: 45     // how fast speed can rise
    property real decelKphPerSec: 75     // how fast speed can fall (braking)
    property int  maxSpeedKph: 180

    // Pick a new target speed every so often.
    Timer {
        id: targetTimer
        interval: 1600
        running: true
        repeat: true
        onTriggered: {
            // Bias toward sensible speeds; occasionally hit higher values.
            const base = 20 + Math.random() * 90;     // 20..110
            const spike = (Math.random() < 0.12) ? (40 + Math.random() * 60) : 0; // sometimes +40..100
            let next = base + spike;

            // Add occasional full stop
            if (Math.random() < 0.08) next = 0;

            targetSpeedKph = Math.max(0, Math.min(maxSpeedKph, next));
        }
    }

    // Smoothly move speed toward the target using accel/decel limits.
    Timer {
        id: simTimer
        interval: 16 // ~60 FPS
        running: true
        repeat: true
        onTriggered: {
            const dt = interval / 1000.0; // seconds
            const diff = targetSpeedKph - speedKph;

            if (Math.abs(diff) < 0.02) {
                speedKph = targetSpeedKph;
                return;
            }

            const rate = (diff > 0) ? accelKphPerSec : decelKphPerSec;
            const step = rate * dt;

            if (Math.abs(diff) <= step) {
                speedKph = targetSpeedKph;
            } else {
                speedKph += (diff > 0) ? step : -step;
            }
        }
    }

    // --- UI ---

    // --- UI ---
    
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


    MatrixRain {
        anchors.fill: parent

        // Match the gauge color (light purple / dark purple / flashing red logic stays in gauge;
        // we keep rain purple-only by forcing the normal purple)
        rainColor: Qt.rgba(gauge.gaugeColor.r, gauge.gaugeColor.g, gauge.gaugeColor.b, 0.45)

        // Performance + aesthetics tuning
        fps: 10
        speedMultiplier: 0.10   // lower = slower rain
        density: 0.12           // lower = fewer glyphs on screen
        fontPx: 11              // smaller glyphs look more "Matrix"
        fadeAlpha: 0.04         // higher = shorter trails, clearer black
        columns: 0              // 0 = auto (uses screen width)
    }

    TachGauge {
        id: tach
        anchors.centerIn: rightPanel

        // Demo value: derive RPM from speed for now (replace with real rpm later)
        rpm: Math.max(0, Math.min(6500, root.speedKph * 50))

        width: Math.min(rightPanel.width * 0.92, rightPanel.height * 0.92)
        height: width
    }


    // Optional: small debug text so you can see target vs actual.
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 12
        color: "#80FFFFFF"

    Component.onCompleted: {
        // Hard-force windowed preview on macOS
        root.showNormal();
        root.raise();
        root.requestActivate();
    }
        font.pixelSize: 16
        text: "speed: " + Math.round(root.speedKph) + "  target: " + Math.round(root.targetSpeedKph)
    }
    // ===== Left third (Speedo zone) =====
    Item {
        id: leftThird
        width: parent.width / 3
        height: parent.height
        anchors.left: parent.left
        anchors.top: parent.top
    SpeedGauge {
        id: gauge
        anchors.centerIn: leftPanel
        speed: root.speedKph

        // Size within left third (square gauge)
        width: Math.min(leftPanel.width * 0.92, leftPanel.height * 0.92)
        height: width
    }

    }

}
