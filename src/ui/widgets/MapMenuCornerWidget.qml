import QtQuick 2.15

Item {
    id: root

    property var theme
    property string corner: "bottomRight"
    property string effectLevel: "high"
    property real bleedFraction: 0.18
    property string icon: "menu"
    property string label: "MENU"
    property color accentColor: "#58FFE1"

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: true

        Column {
            width: Math.round(frame.side * 0.58)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(frame.side * 0.02)
            spacing: 5

            OemIcon {
                width: Math.round(frame.side * 0.38)
                height: root.icon === "menu" ? Math.round(frame.side * 0.30) : width
                anchors.horizontalCenter: parent.horizontalCenter
                icon: root.icon
                color: "#F7FBFF"
                accentColor: root.accentColor
                strokeWidth: Math.max(5, frame.side * 0.052)
            }

            Text {
                width: parent.width
                text: root.label
                color: "#F7FBFF"
                font.family: root.monoFont
                font.pixelSize: Math.max(10, Math.floor(frame.side * 0.078))
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
