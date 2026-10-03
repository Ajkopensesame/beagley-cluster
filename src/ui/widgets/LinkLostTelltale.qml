import QtQuick 2.15

// Persistent LINK LOST telltale (vehicle-data link down / stale / hub-reported stale).
//
// Shown for as long as `active` is true. It is deliberately NOT a toast: no timeout,
// no dismiss, no animation that ever drops below ~70% opacity. Parents must place it
// at a z above every other overlay of the window (see MainV3 / MainEmbedded).
// Policy lives in VehicleStateSource::linkLost; this item only draws it.
Item {
    id: root

    property bool active: false
    property bool pulse: true
    property string fontFamily: "Oxanium"

    readonly property color amber: "#FFB03B"

    visible: active
    width: 340
    height: 66
    z: 20000

    // 0..1 breathing phase; only runs while visible and pulsing.
    property real phase
    SequentialAnimation on phase {
        running: root.active && root.pulse
        loops: Animation.Infinite
        NumberAnimation { from: 1.0; to: 0.0; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.0; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "#F0300808"
        border.width: 3
        border.color: root.amber
        opacity: root.pulse ? (0.72 + 0.28 * root.phase) : 1.0

        Row {
            anchors.centerIn: parent
            spacing: 14

            Rectangle {
                width: 40
                height: 40
                radius: 20
                anchors.verticalCenter: parent.verticalCenter
                color: root.amber

                Text {
                    anchors.centerIn: parent
                    text: "!"
                    color: "#2A0A00"
                    font.family: root.fontFamily
                    font.pixelSize: 30
                    font.bold: true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "LINK LOST"
                color: root.amber
                font.family: root.fontFamily
                font.pixelSize: 38
                font.bold: true
                font.letterSpacing: 2
                style: Text.Outline
                styleColor: "#E0000000"
            }
        }
    }
}
