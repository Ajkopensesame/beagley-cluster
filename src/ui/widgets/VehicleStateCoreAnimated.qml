import QtQuick 2.15

Item {
    id: root
    width: 240
    height: 240

    // Inputs
    property string drivetrainMode: "2wd"   // "2wd" | "4wd"
    property bool transferLock: false
    property bool hasWarning: false
    property string warningText: "CHECK ENGINE"

    readonly property bool is4wd: drivetrainMode === "4wd"

    // Animated properties
    property real frontOpacity: 0.22
    property real shaftOpacity: 0.0
    property real lockOpacity: 0.0
    property real frontThickness: 6

    // lock "draw" simulation (0..1)
    property real lockProgress: 0.0

    Behavior on frontOpacity    { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on shaftOpacity    { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on lockOpacity     { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on frontThickness  { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    function refresh() {
        if (hasWarning) {
            frontOpacity = 0.0
            shaftOpacity = 0.0
            lockOpacity = 0.0
            frontThickness = 6
            return
        }

        if (is4wd) {
            frontOpacity = 1.0
            shaftOpacity = 1.0
            frontThickness = 10
        } else {
            frontOpacity = 0.22
            shaftOpacity = 0.0
            frontThickness = 6
        }

        lockOpacity = (transferLock && is4wd) ? 1.0 : 0.0
    }

    onDrivetrainModeChanged: refresh()
    onHasWarningChanged: refresh()
    onTransferLockChanged: refresh()
    Component.onCompleted: refresh()

    // =====================
    // DRIVETRAIN VISUAL
    // =====================
    Item {
        id: drivetrainVisual
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        opacity: hasWarning ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // Subtle pulse when locked (very OEM)
        SequentialAnimation on scale {
            running: transferLock && is4wd && !hasWarning
            loops: Animation.Infinite
            NumberAnimation { to: 1.025; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.00; duration: 700; easing.type: Easing.InOutSine }
        }

        // Label
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.08
            text: transferLock && is4wd ? "4WD • LOCK" : (is4wd ? "4WD" : "2WD")
            color: "white"
            font.pixelSize: 18
            font.bold: true
            opacity: 0.9
        }

        // Rear axle (always "driven" in this abstraction)
        Rectangle {
            id: rearAxle
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.72
            width: parent.width * 0.62
            height: 10
            radius: height / 2
            color: "white"
            opacity: 1.0
        }

        // Rear wheels (small hints)
        Repeater {
            model: 2
            Rectangle {
                width: 18; height: 18; radius: 9
                y: rearAxle.y + rearAxle.height/2 - height/2
                x: (index === 0)
                    ? (rearAxle.x - 8)
                    : (rearAxle.x + rearAxle.width - width + 8)
                color: "transparent"
                border.color: "white"
                border.width: 3
                opacity: 0.9
            }
        }

        // Front axle (animated)
        Rectangle {
            id: frontAxle
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.44
            width: parent.width * 0.46
            height: root.frontThickness
            radius: height / 2
            color: "white"
            opacity: root.frontOpacity
        }

        // Front wheels (hints)
        Repeater {
            model: 2
            Rectangle {
                width: 16; height: 16; radius: 8
                y: frontAxle.y + frontAxle.height/2 - height/2
                x: (index === 0)
                    ? (frontAxle.x - 6)
                    : (frontAxle.x + frontAxle.width - width + 6)
                color: "transparent"
                border.color: "white"
                border.width: 3
                opacity: root.frontOpacity
            }
        }

        // Driveshaft spine (only in 4WD)
        Rectangle {
            id: spine
            width: 8
            radius: 4
            color: "white"
            opacity: root.shaftOpacity
            x: parent.width/2 - width/2
            y: frontAxle.y + frontAxle.height
            height: (rearAxle.y - (frontAxle.y + frontAxle.height))
        }

        // Center diff lock "ring" (uses 4 small segments that appear sequentially)
        // This fakes a "draw" without Shapes.
        Item {
            id: lock
            width: 54; height: 54
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.56 - height/2
            opacity: root.lockOpacity

            // animate progress when turning lock on/off
            onOpacityChanged: {
                if (opacity === 1) lockDraw.restart()
                else root.lockProgress = 0
            }

            SequentialAnimation {
                id: lockDraw
                running: false
                ScriptAction { script: root.lockProgress = 0 }
                NumberAnimation { target: root; property: "lockProgress"; to: 1.0; duration: 220; easing.type: Easing.OutCubic }
            }

            // 4 segments (top/right/bottom/left). Each appears at a threshold.
            Rectangle { // top
                anchors.horizontalCenter: parent.horizontalCenter
                y: 0
                width: parent.width * 0.70
                height: 8
                radius: 4
                color: "white"
                opacity: root.lockProgress >= 0.25 ? 1 : 0
            }
            Rectangle { // right
                anchors.right: parent.right
                x: parent.width - 8
                y: parent.height * 0.15
                width: 8
                height: parent.height * 0.70
                radius: 4
                color: "white"
                opacity: root.lockProgress >= 0.50 ? 1 : 0
            }
            Rectangle { // bottom
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 8
                width: parent.width * 0.70
                height: 8
                radius: 4
                color: "white"
                opacity: root.lockProgress >= 0.75 ? 1 : 0
            }
            Rectangle { // left
                x: 0
                y: parent.height * 0.15
                width: 8
                height: parent.height * 0.70
                radius: 4
                color: "white"
                opacity: root.lockProgress >= 1.0 ? 1 : 0
            }

            // inner dot
            Rectangle {
                anchors.centerIn: parent
                width: 14; height: 14; radius: 7
                color: "white"
                opacity: root.lockOpacity
            }
        }
    }

    // =====================
    // WARNING OVERRIDE
    // =====================
    Rectangle {
        id: warningCard
        anchors.centerIn: parent
        width: parent.width * 0.86
        height: parent.height * 0.38
        radius: 18
        color: "transparent"
        border.color: "white"
        border.width: 3
        opacity: hasWarning ? 1 : 0
        scale: hasWarning ? 1 : 0.98

        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: warningText
            color: "white"
            font.pixelSize: 22
            font.bold: true
        }

        // One-shot attention pulse when warning appears
        SequentialAnimation {
            id: warnPulse
            running: false
            NumberAnimation { target: warningCard; property: "scale"; to: 1.06; duration: 120 }
            NumberAnimation { target: warningCard; property: "scale"; to: 1.00; duration: 160 }
        }
        onOpacityChanged: if (opacity === 1) warnPulse.start()
    }
}
