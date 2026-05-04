import QtQuick 2.15

Item {
    id: root

    property var theme
    property string corner: "topLeft"
    property string effectLevel: "high"
    property real bleedFraction: 0.18
    property bool live: false
    property string tempText: "--"
    property string locationText: "GPS WAIT"
    property string conditionKind: "clear"
    property string conditionText: "WEATHER"

    signal clicked()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool hasTemp: tempText.length > 0 && tempText !== "--"

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live

        WeatherMoodIcon {
            width: Math.round(frame.side * 0.34)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(frame.side * 0.18)
            kind: root.conditionKind
            primaryColor: "#FFD36B"
            secondaryColor: "#58FFE1"
            visible: root.live
            opacity: 0.95
        }

        OemIcon {
            width: Math.round(frame.side * 0.32)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(frame.side * 0.19)
            icon: "weather"
            color: "#F7FBFF"
            accentColor: "#FFD36B"
            strokeWidth: Math.max(3, frame.side * 0.035)
            active: false
            visible: !root.live
        }

        Column {
            width: Math.round(frame.side * 0.62)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(frame.side * 0.11)
            spacing: 0

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                Text {
                    text: root.hasTemp ? root.tempText : "--"
                    color: "#F9FBFF"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(frame.side * 0.36)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    lineHeight: 0.82
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00B0"
                    color: root.live ? "#58FFE1" : "#FFD36B"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(frame.side * 0.17)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                }
            }

            Text {
                width: parent.width
                text: root.live ? root.locationText : root.conditionText
                color: root.live ? "#58FFE1" : "#FFD36B"
                font.family: root.monoFont
                font.pixelSize: Math.max(9, Math.floor(frame.side * 0.068))
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
