import QtQuick 2.15

Item {
    id: panel

    property var controller: null

    readonly property string displayFont: controller && controller.displayFont ? controller.displayFont : "Oxanium"
    readonly property string monoFont: controller && controller.monoFont ? controller.monoFont : "Oxanium"
    readonly property int modalRadius: controller ? controller.modalRadius : 0
    readonly property int modalSmallRadius: controller ? controller.modalSmallRadius : 0
    readonly property string locationName: controller && controller.locationName ? controller.locationName : ""
    readonly property string weatherStatus: controller && controller.weatherStatus ? controller.weatherStatus : "SYNC"
    readonly property string weatherUpdatedText: controller && controller.weatherUpdatedText ? controller.weatherUpdatedText : ""
    readonly property string forecastStatus: controller && controller.forecastStatus ? controller.forecastStatus : "SYNC"
    readonly property string forecastUpdatedText: controller && controller.forecastUpdatedText ? controller.forecastUpdatedText : ""
    readonly property var forecastRows: controller ? controller.forecastRows : []
    readonly property real displayTempC: controller ? controller.displayTempC : NaN
    readonly property real displayFeelsC: controller ? controller.displayFeelsC : NaN
    readonly property real precipitationMm: controller ? controller.precipitationMm : NaN
    readonly property string weatherWindDir: controller && controller.weatherWindDir ? controller.weatherWindDir : ""
    readonly property real windKph: controller ? controller.windKph : NaN

    function currentConditionLabel() {
        return controller ? controller.currentConditionLabel() : panel.weatherStatus
    }

    function formatTemp(value) {
        return controller ? controller.formatTemp(value) : "--"
    }

    function formatRain(value) {
        return controller ? controller.formatRain(value) : "0.0"
    }

    function formatWind(value) {
        return controller ? controller.formatWind(value) : "--"
    }

    function rainShortLine(value) {
        return controller ? controller.rainShortLine(value) : "none"
    }

    function weatherKind(value) {
        return controller ? controller.weatherKind(value) : "clear"
    }

    function weatherMoodLine(value) {
        return controller ? controller.weatherMoodLine(value) : "Weather"
    }

    function weatherMoodSubLine(value) {
        return controller ? controller.weatherMoodSubLine(value) : panel.weatherStatus
    }

    Column {
        anchors.fill: parent
        spacing: 9

        Row {
            width: parent.width
            height: 34
            spacing: 10

            Text {
                width: parent.width * 0.58
                anchors.verticalCenter: parent.verticalCenter
                text: "TODAY"
                color: "#F7FBFF"
                font.family: panel.monoFont
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 0
                elide: Text.ElideRight
            }

            Text {
                width: parent.width * 0.42 - 10
                anchors.verticalCenter: parent.verticalCenter
                text: panel.locationName.length > 0 ? panel.locationName : panel.weatherStatus
                color: "#9DB4FF"
                font.family: panel.monoFont
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Rectangle {
            width: parent.width
            height: 156
            radius: panel.modalRadius
            color: "#0A0D16"
            border.width: 1
            border.color: "#233E4B"

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18

                WeatherMoodIcon {
                    width: 116
                    height: 116
                    anchors.verticalCenter: parent.verticalCenter
                    kind: panel.weatherKind(panel.currentConditionLabel())
                    primaryColor: "#FFD36B"
                    secondaryColor: "#58FFE1"
                }

                Column {
                    width: parent.width - 134
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Row {
                        width: parent.width
                        spacing: 10

                        Text {
                            width: 128
                            text: panel.formatTemp(panel.displayTempC)
                            color: "#F9FBFF"
                            font.family: panel.displayFont
                            font.pixelSize: 82
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            lineHeight: 0.82
                            horizontalAlignment: Text.AlignRight
                        }

                        Column {
                            width: parent.width - 138
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5

                            Text {
                                width: parent.width
                                text: "\u00B0C"
                                color: "#58FFE1"
                                font.family: panel.monoFont
                                font.pixelSize: 18
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: panel.weatherMoodLine(panel.currentConditionLabel())
                                color: "#FFD36B"
                                font.family: panel.displayFont
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: panel.weatherMoodSubLine(panel.currentConditionLabel())
                        color: "#F7FBFF"
                        font.family: panel.displayFont
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: panel.currentConditionLabel() + "  /  updated " + panel.weatherUpdatedText
                        color: "#9DB4FF"
                        font.family: panel.monoFont
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Grid {
            id: metricsGrid
            width: parent.width
            columns: 3
            columnSpacing: 10
            rowSpacing: 6

            Repeater {
                model: [
                    { "k": "FEELS", "v": panel.formatTemp(panel.displayFeelsC) + "\u00B0", "s": "outside" },
                    { "k": "RAIN", "v": panel.formatRain(panel.precipitationMm) + " MM", "s": panel.rainShortLine(panel.precipitationMm) },
                    { "k": "WIND", "v": (panel.weatherWindDir.length > 0 ? panel.weatherWindDir + " " : "") + panel.formatWind(panel.windKph), "s": "km/h" }
                ]

                Rectangle {
                    width: (metricsGrid.width - 20) / 3
                    height: 54
                    radius: panel.modalRadius
                    color: "#0D111C"
                    border.width: 1
                    border.color: "#202C3A"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 7
                        spacing: 1

                        Text {
                            width: parent.width
                            text: modelData.k
                            color: "#9DB4FF"
                            font.family: panel.monoFont
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.v
                            color: "#F7FBFF"
                            font.family: panel.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: modelData.s
                            color: "#58FFE1"
                            font.family: panel.monoFont
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: 22

            Text {
                width: parent.width * 0.54
                anchors.verticalCenter: parent.verticalCenter
                text: "THIS WEEK"
                color: "#F7FBFF"
                font.family: panel.monoFont
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 0
            }

            Text {
                width: parent.width * 0.46
                anchors.verticalCenter: parent.verticalCenter
                text: panel.forecastStatus === "LIVE" ? panel.forecastUpdatedText : panel.forecastStatus
                color: "#9DB4FF"
                font.family: panel.monoFont
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Column {
            id: forecastList
            width: parent.width
            spacing: 0

            Repeater {
                model: panel.forecastRows

                Rectangle {
                    width: forecastList.width
                    height: 43
                    radius: panel.modalSmallRadius
                    color: index === 0 ? "#101725" : "#0B0F1A"
                    border.width: 1
                    border.color: index === 0 ? "#2A4652" : "#1B2734"

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        WeatherMoodIcon {
                            width: 30
                            height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            kind: panel.weatherKind(modelData.label)
                            primaryColor: "#FFD36B"
                            secondaryColor: "#58FFE1"
                        }

                        Text {
                            width: 68
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.day
                            color: index === 0 ? "#58FFE1" : "#F7FBFF"
                            font.family: panel.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            elide: Text.ElideRight
                        }

                        Column {
                            width: parent.width - 224
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                text: modelData.label
                                color: "#F7FBFF"
                                font.family: panel.monoFont
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: panel.rainShortLine(modelData.rain) + " rain"
                                color: "#9DB4FF"
                                font.family: panel.monoFont
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            width: 62
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.high !== null ? modelData.high : "--") + "\u00B0/" + (modelData.low !== null ? modelData.low : "--") + "\u00B0"
                            color: "#F7FBFF"
                            font.family: panel.displayFont
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            width: 40
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.rain !== null ? modelData.rain + "%" : "--%"
                            color: "#FFD36B"
                            font.family: panel.monoFont
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: panel.forecastRows.length === 0
                text: panel.forecastStatus
                color: "#FFD36B"
                font.family: panel.monoFont
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
