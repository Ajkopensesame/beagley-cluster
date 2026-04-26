import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: root

    width: 1920
    height: 720
    minimumWidth: 1920
    minimumHeight: 720
    maximumWidth: 1920
    maximumHeight: 720
    visible: true
    color: "#000000"
    visibility: Window.Windowed

    readonly property int outerMargin: 18
    readonly property int gap: 12
    readonly property int headerHeight: 52
    readonly property int colorBandHeight: 170
    readonly property int rampBandHeight: 96
    readonly property int motionBandHeight: 270
    readonly property color panelFill: "#050505"
    readonly property color panelStroke: "#D8E2F0"

    Component.onCompleted: {
        root.showFullScreen()
        root.raise()
        root.requestActivate()
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: outerMargin
        color: "transparent"
        border.width: 4
        border.color: "#FFFFFF"
    }

    Rectangle {
        x: width / 2 - 1
        y: outerMargin
        width: 2
        height: parent.height - outerMargin * 2
        color: "#FFFFFF"
        opacity: 0.75
    }

    Rectangle {
        x: outerMargin
        y: height / 2 - 1
        width: parent.width - outerMargin * 2
        height: 2
        color: "#FFFFFF"
        opacity: 0.75
    }

    Column {
        anchors.fill: parent
        anchors.margins: outerMargin + 10
        spacing: gap

        Rectangle {
            width: parent.width
            height: headerHeight
            color: panelFill
            border.width: 2
            border.color: panelStroke

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "BEAGLEY PANEL TEST"
                color: "#FFFFFF"
                font.pixelSize: 30
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "COLOR  |  GEOMETRY  |  MOTION"
                color: "#FFFFFF"
                font.pixelSize: 22
                font.bold: true
            }
        }

        Row {
            width: parent.width
            height: colorBandHeight
            spacing: gap

            Repeater {
                model: [
                    { label: "RED", fill: "#FF0000", fg: "#FFFFFF" },
                    { label: "GREEN", fill: "#00FF00", fg: "#000000" },
                    { label: "BLUE", fill: "#0000FF", fg: "#FFFFFF" },
                    { label: "WHITE", fill: "#FFFFFF", fg: "#000000" },
                    { label: "BLACK", fill: "#000000", fg: "#FFFFFF", border: "#FFFFFF" }
                ]

                Rectangle {
                    width: (parent.width - parent.spacing * 4) / 5
                    height: parent.height
                    color: modelData.fill
                    border.width: 2
                    border.color: modelData.border ? modelData.border : "#C0C0C0"

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: modelData.fg
                        font.pixelSize: 28
                        font.bold: true
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: rampBandHeight
            color: panelFill
            border.width: 2
            border.color: panelStroke

            Row {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                Repeater {
                    model: 16

                    Rectangle {
                        width: (parent.width - parent.spacing * 15) / 16
                        height: parent.height
                        color: Qt.rgba(index / 15, index / 15, index / 15, 1.0)
                        border.width: 1
                        border.color: index < 8 ? "#808080" : "#202020"
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: motionBandHeight
            spacing: gap

            Rectangle {
                width: (parent.width - gap) * 0.54
                height: parent.height
                color: panelFill
                border.width: 2
                border.color: panelStroke

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.72
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 4
                    border.color: "#FFFFFF"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.48
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 4
                    border.color: "#00FFFF"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.24
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 4
                    border.color: "#FF00FF"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.78
                    height: 4
                    color: "#FFFFFF"
                    rotation: 28
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.78
                    height: 4
                    color: "#FFFF00"
                    rotation: -28
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    radius: 12
                    color: "#FF0000"
                    border.width: 2
                    border.color: "#FFFFFF"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    text: "CIRCLES SHOULD BE ROUND. DIAGONALS SHOULD BE CLEAN."
                    color: "#FFFFFF"
                    font.pixelSize: 22
                    font.bold: true
                }
            }

            Rectangle {
                width: (parent.width - gap) * 0.46
                height: parent.height
                color: panelFill
                border.width: 2
                border.color: panelStroke

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 14
                    text: "MOTION"
                    color: "#FFFFFF"
                    font.pixelSize: 28
                    font.bold: true
                }

                Rectangle {
                    id: scanTrack
                    x: 18
                    y: 64
                    width: parent.width - 36
                    height: 70
                    color: "#000000"
                    border.width: 2
                    border.color: "#808080"

                    Rectangle {
                        id: scanBar
                        y: 8
                        width: Math.max(80, scanTrack.width * 0.16)
                        height: scanTrack.height - 16
                        color: "#FFFFFF"
                        border.width: 2
                        border.color: "#00FFFF"

                        NumberAnimation on x {
                            from: 8
                            to: scanTrack.width - scanBar.width - 8
                            duration: 1800
                            loops: Animation.Infinite
                            easing.type: Easing.Linear
                        }
                    }
                }

                Rectangle {
                    id: bounceTrack
                    x: 18
                    y: 156
                    width: parent.width - 36
                    height: parent.height - 174
                    color: "#000000"
                    border.width: 2
                    border.color: "#808080"

                    Rectangle {
                        id: bounceDot
                        width: 34
                        height: 34
                        radius: 17
                        color: "#00FF00"
                        border.width: 2
                        border.color: "#FFFFFF"

                        NumberAnimation on x {
                            from: 10
                            to: bounceTrack.width - bounceDot.width - 10
                            duration: 1600
                            loops: Animation.Infinite
                            easing.type: Easing.InOutQuad
                        }

                        SequentialAnimation on y {
                            loops: Animation.Infinite
                            NumberAnimation { from: 10; to: bounceTrack.height - bounceDot.height - 10; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: bounceTrack.height - bounceDot.height - 10; to: 10; duration: 900; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 78
            color: panelFill
            border.width: 2
            border.color: panelStroke

            Text {
                anchors.centerIn: parent
                text: "IF THESE BLOCKS, LINES, AND MOVING SHAPES ARE STILL CORRUPTED, THE ISSUE IS BELOW THE CLUSTER UI."
                color: "#FFFFFF"
                font.pixelSize: 24
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
