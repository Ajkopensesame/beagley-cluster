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
    readonly property real side: Math.min(width, height)
    readonly property bool menuIcon: root.icon === "menu"
    readonly property color podFaceColor: root.menuIcon ? "#020409" : Qt.rgba(0.01, 0.02, 0.04, 0.86)

    CornerPodFrame {
        id: frame
        anchors.fill: parent
        corner: root.corner
        bleedFraction: root.bleedFraction
        effectLevel: root.effectLevel
        active: true

        Rectangle {
            visible: root.menuIcon
            width: Math.round(frame.side * 0.720)
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: "#020409"
            border.width: Math.max(1, Math.round(frame.side * 0.010))
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
        }

        Rectangle {
            id: actionFace
            width: Math.round(frame.side * (root.menuIcon ? 0.650 : 0.615))
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            color: root.podFaceColor
            border.width: Math.max(3, Math.round(frame.side * 0.018))
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, root.menuIcon ? 0.78 : 0.66)
        }

        Rectangle {
            width: Math.round(frame.side * 0.465)
            height: width
            radius: width / 2
            anchors.centerIn: actionFace
            color: root.menuIcon ? Qt.rgba(0.02, 0.03, 0.07, 0.72) : "transparent"
            border.width: 1
            border.color: Qt.rgba(0.86, 0.90, 0.98, root.menuIcon ? 0.14 : 0.20)
        }

        Rectangle {
            visible: !root.menuIcon
            width: Math.round(frame.side * 0.150)
            height: Math.max(2, Math.round(frame.side * 0.018))
            radius: height / 2
            anchors.horizontalCenter: actionFace.horizontalCenter
            anchors.top: actionFace.top
            anchors.topMargin: Math.round(frame.side * 0.038)
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.90)
        }

        Item {
            id: iconGlyph
            width: Math.round(frame.side * 0.365)
            height: Math.round(frame.side * 0.300)
            anchors.horizontalCenter: actionFace.horizontalCenter
            anchors.verticalCenter: actionFace.verticalCenter
            anchors.verticalCenterOffset: -Math.round(frame.side * 0.058)

            readonly property int glyphStroke: Math.max(4, Math.round(root.side * 0.035))

            Item {
                anchors.fill: parent
                visible: root.menuIcon

                Rectangle {
                    x: parent.width * 0.14
                    y: parent.height * 0.18
                    width: parent.width * 0.72
                    height: iconGlyph.glyphStroke
                    radius: height / 2
                    color: root.accentColor
                }

                Rectangle {
                    x: parent.width * 0.14
                    y: parent.height * 0.47
                    width: parent.width * 0.72
                    height: iconGlyph.glyphStroke
                    radius: height / 2
                    color: "#F7FBFF"
                }

                Rectangle {
                    x: parent.width * 0.14
                    y: parent.height * 0.76
                    width: parent.width * 0.72
                    height: iconGlyph.glyphStroke
                    radius: height / 2
                    color: root.accentColor
                }
            }

            Item {
                anchors.fill: parent
                visible: !root.menuIcon

                Rectangle {
                    x: parent.width * 0.18
                    y: parent.height * 0.62
                    width: parent.width * 0.40
                    height: iconGlyph.glyphStroke
                    radius: height / 2
                    rotation: -24
                    transformOrigin: Item.Left
                    color: root.accentColor
                }

                Rectangle {
                    x: parent.width * 0.48
                    y: parent.height * 0.50
                    width: parent.width * 0.40
                    height: iconGlyph.glyphStroke
                    radius: height / 2
                    rotation: -48
                    transformOrigin: Item.Left
                    color: root.accentColor
                }

                Rectangle {
                    x: parent.width * 0.13
                    y: parent.height * 0.63
                    width: iconGlyph.glyphStroke * 2.25
                    height: width
                    radius: width / 2
                    color: "#F7FBFF"
                }

                Rectangle {
                    x: parent.width * 0.68
                    y: parent.height * 0.12
                    width: iconGlyph.glyphStroke * 2.70
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Math.max(3, iconGlyph.glyphStroke * 0.70)
                    border.color: "#F7FBFF"
                }
            }
        }

        Rectangle {
            id: labelSlot
            width: Math.round(frame.side * 0.445)
            height: Math.round(frame.side * 0.124)
            radius: height / 2
            anchors.horizontalCenter: actionFace.horizontalCenter
            anchors.top: iconGlyph.bottom
            anchors.topMargin: Math.round(frame.side * 0.020)
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.48)

            Text {
                anchors.fill: parent
                text: root.label
                color: "#F7FBFF"
                font.family: root.monoFont
                font.pixelSize: Math.max(9, Math.floor(frame.side * 0.064))
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                renderType: Text.QtRendering
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
