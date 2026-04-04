import QtQuick 2.15

Item {
    property bool left_indicator: true
    property bool right_indicator: true
    id: root

    // ===== Mock PRND21 gear cycling =====
    property var _gears: ["P","R","N","D","2","1"]
    property int _gearIdx: 0
    property string gear: _gears[_gearIdx]

    Timer {
        id: gearTimer
        interval: 900
        repeat: true
        running: true
        onTriggered: _gearIdx = (_gearIdx + 1) % _gears.length
    }
    // ===================================
    property bool overdrive: true

    visible: false   // non-visual data model

    // -------- Vehicle state (mock) --------
    property real speedKph: 0
    property real rpm: 0
    property real fuelPct: 100

    // Coolant temp (°C) mock
    property real coolantC: 70
    property bool coolantHeating: true

    // -------- Simulation parameters --------
    property real targetSpeedKph: 0
    property real accelKphPerSec: 45
    property real decelKphPerSec: 75
    property int  maxSpeedKph: 180

    // Pick a new target speed periodically
    Timer {
        id: targetTimer
        interval: 1600
        running: true
        repeat: true
        onTriggered: {
            const base = 20 + Math.random() * 90; // 20..110
            const spike = (Math.random() < 0.12) ? (40 + Math.random() * 60) : 0;
            let next = base + spike;

            if (Math.random() < 0.08) next = 0; // occasional stop

            root.targetSpeedKph = Math.max(0, Math.min(root.maxSpeedKph, next));
        }
    }

    // Smooth accel/brake toward target
    Timer {
        id: simTimer
        interval: 16 // ~60fps
        running: true
        repeat: true
        onTriggered: {
            const dt = simTimer.interval / 1000.0;
            const diff = root.targetSpeedKph - root.speedKph;

            const rate = (diff > 0) ? root.accelKphPerSec : root.decelKphPerSec;
            const step = rate * dt;

            if (Math.abs(diff) <= step) {
                root.speedKph = root.targetSpeedKph;
            } else {
                root.speedKph += (diff > 0) ? step : -step;
            }

            root.speedKph = Math.max(0, Math.min(root.maxSpeedKph, root.speedKph));

            // Simple RPM mapping for demo only
            root.rpm = Math.max(0, Math.min(6500, root.speedKph * 50));
        }
    }

    // Fuel simulation: slow drain, refill when empty
    Timer {
        id: fuelTimer
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            root.fuelPct -= 0.08;
            if (root.fuelPct <= 0) root.fuelPct = 100;
        }
    }

    // Coolant simulation: warm up and cool down loop
    Timer {
        id: coolantTimer
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            if (root.coolantHeating) root.coolantC += 0.12;
            else root.coolantC -= 0.10;

            if (root.coolantC >= 110) root.coolantHeating = false;
            if (root.coolantC <= 45)  root.coolantHeating = true;
        }
    }
    }

