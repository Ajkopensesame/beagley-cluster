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
    signal pressAndHold()

    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool hasTemp: tempText.length > 0 && tempText !== "--"
    readonly property real side: Math.min(width, height)

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: root.live

        OemIcon {
            id: conditionIcon
            width: Math.round(frame.side * 0.180)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(frame.side * 0.195)
            icon: "weather"
            color: "#F7FBFF"
            accentColor: "#FFD36B"
            strokeWidth: Math.max(2.4, frame.side * 0.026)
            active: root.live
            opacity: root.live ? 0.96 : 0.68
            visible: true
        }

        Item {
            id: tempGroup
            width: Math.round(frame.side * 0.58)
            height: Math.round(frame.side * 0.31)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(frame.side * 0.040)

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.max(1, Math.round(frame.side * 0.010))

                Text {
                    width: Math.round(frame.side * 0.42)
                    text: root.hasTemp ? root.tempText : "--"
                    color: "#F9FBFF"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(frame.side * 0.305)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 18
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    renderType: Text.QtRendering
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00B0"
                    color: root.live ? "#58FFE1" : "#FFD36B"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(frame.side * 0.128)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    renderType: Text.QtRendering
                }
            }
        }

        Rectangle {
            width: Math.round(frame.side * 0.40)
            height: 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: tempGroup.bottom
            anchors.topMargin: Math.round(frame.side * 0.018)
            color: root.live ? Qt.rgba(0.35, 1.0, 0.88, 0.40) : Qt.rgba(1.0, 0.83, 0.42, 0.32)
        }

        Text {
            width: Math.round(frame.side * 0.56)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(frame.side * 0.245)
            text: root.live ? root.locationText : root.conditionText
            color: root.live ? "#58FFE1" : "#FFD36B"
            font.family: root.monoFont
            font.pixelSize: Math.max(9, Math.floor(frame.side * 0.060))
            font.weight: Font.Bold
            font.letterSpacing: 0
            fontSizeMode: Text.Fit
            minimumPixelSize: 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            renderType: Text.QtRendering
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
        onPressAndHold: root.pressAndHold()
    }
}
