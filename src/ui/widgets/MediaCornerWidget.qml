import QtQuick 2.15

Item {
    id: root

    property var theme
    property string corner: "bottomLeft"
    property string effectLevel: "high"
    property real bleedFraction: 0.18
    property bool available: false
    property bool playing: false
    property string primaryText: "SPOTIFY"
    property string secondaryText: "NOT CONNECTED"

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.available

        Column {
            width: Math.round(frame.side * 0.60)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -Math.round(frame.side * 0.02)
            spacing: 4

            OemIcon {
                width: Math.round(frame.side * 0.32)
                height: width
                anchors.horizontalCenter: parent.horizontalCenter
                icon: "audio"
                active: root.playing
                color: "#F7FBFF"
                accentColor: "#58FFE1"
                strokeWidth: Math.max(3, frame.side * 0.034)
            }

            Text {
                width: parent.width
                text: root.primaryText
                color: root.available ? "#F7FBFF" : "#9DB4FF"
                font.family: root.displayFont
                font.pixelSize: Math.max(12, Math.floor(frame.side * 0.096))
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.secondaryText
                color: root.playing ? "#58FFE1" : "#C568FF"
                font.family: root.monoFont
                font.pixelSize: Math.max(8, Math.floor(frame.side * 0.062))
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
