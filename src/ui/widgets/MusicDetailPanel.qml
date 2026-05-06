import QtQuick 2.15

Item {
    id: panel

    property var controller: null

    readonly property string displayFont: controller && controller.displayFont ? controller.displayFont : "Oxanium"
    readonly property string monoFont: controller && controller.monoFont ? controller.monoFont : "Oxanium"
    readonly property int modalRadius: controller ? controller.modalRadius : 0
    readonly property bool embeddedSafePopups: controller ? controller.embeddedSafePopups : true
    readonly property bool musicPlaying: !!(controller && controller.musicPlaying)
    readonly property string musicTitle: controller && controller.musicTitle ? controller.musicTitle : ""
    readonly property string musicArtist: controller && controller.musicArtist ? controller.musicArtist : ""
    readonly property string musicAlbum: controller && controller.musicAlbum ? controller.musicAlbum : ""
    readonly property string musicStatus: controller && controller.musicStatus ? controller.musicStatus : "OFFLINE"
    readonly property string musicDetail: controller && controller.musicDetail ? controller.musicDetail : "Spotify not connected"

    Column {
        anchors.fill: parent
        spacing: 14

        Text {
            width: parent.width
            text: "NOW PLAYING"
            color: "#58FFE1"
            font.family: panel.monoFont
            font.pixelSize: 13
            font.weight: Font.Bold
            font.letterSpacing: 0
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            width: parent.width
            height: parent.height - 30
            radius: panel.modalRadius
            color: "#070913"
            border.width: 1
            border.color: panel.musicPlaying ? "#58FFE1" : "#3C325E"

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Rectangle {
                    width: 96
                    height: 96
                    radius: panel.embeddedSafePopups ? 0 : 48
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#05060A"
                    border.width: 1
                    border.color: panel.musicPlaying ? "#58FFE1" : "#5C4B90"

                    OemIcon {
                        anchors.centerIn: parent
                        width: 62
                        height: 62
                        icon: "audio"
                        active: panel.musicPlaying
                        color: "#F7FBFF"
                        accentColor: "#58FFE1"
                        strokeWidth: 5.0
                    }
                }

                Rectangle {
                    width: parent.width
                    radius: panel.modalRadius
                    color: "#0A0D18"
                    border.width: 1
                    border.color: "#22283D"
                    implicitHeight: titleColumn.implicitHeight + 22

                    Column {
                        id: titleColumn
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 8

                        Text {
                            width: parent.width
                            text: panel.musicTitle.length > 0 ? panel.musicTitle : panel.musicStatus
                            color: "#F7FBFF"
                            font.family: panel.displayFont
                            font.pixelSize: 24
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }

                        Text {
                            width: parent.width
                            text: panel.musicArtist.length > 0 ? panel.musicArtist : panel.musicDetail
                            color: "#58FFE1"
                            font.family: panel.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }

                        Text {
                            width: parent.width
                            text: panel.musicAlbum.length > 0 ? panel.musicAlbum : "SPOTIFY"
                            color: "#C568FF"
                            font.family: panel.monoFont
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                        }
                    }
                }
            }
        }
    }
}
