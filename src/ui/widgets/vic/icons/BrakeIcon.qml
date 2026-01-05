import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    // Injected by VicWarningIcon
    property color color: "red"

    // Tuning knobs (keep it OEM-ish)
    readonly property real s: Math.min(width, height)
    readonly property real strokeW: Math.max(3, s * 0.07)
    readonly property real ringPad: Math.max(8, s * 0.10)

    
    // Exclamation stem
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        // visually centered a touch high, like OEM clusters
        y: root.s * 0.24
        width: Math.max(5, root.s * 0.12)
        height: root.s * 0.40
        radius: width / 2
        color: root.color
        opacity: 0.95
    }

    // Exclamation dot
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.s * 0.69
        width: Math.max(6, root.s * 0.13)
        height: width
        radius: width / 2
        color: root.color
        opacity: 0.95
    }

    // Optional subtle parentheses hint (very light) — OEM-ish "(!)" feel
    // If you want *only* circle + !, set opacity to 0.0.
    Text {
        anchors.centerIn: parent
        text: "("
        color: root.color
        opacity: 0.35
        font.bold: true
        font.pixelSize: Math.round(root.s * 0.68)
        y: -root.s * 0.01
        x: -root.s * 0.20
    }

    Text {
        anchors.centerIn: parent
        text: ")"
        color: root.color
        opacity: 0.35
        font.bold: true
        font.pixelSize: Math.round(root.s * 0.68)
        y: -root.s * 0.01
        x: root.s * 0.20
    }
}
