import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent

    readonly property bool noMap: (typeof BEAGLEY_NO_MAP !== "undefined") ? BEAGLEY_NO_MAP : false

    Rectangle {
        anchors.fill: parent
        color: "black"
        radius: 18
        clip: true

        Loader {
            anchors.fill: parent
            active: !root.noMap
            source: "MapCenterWeb.qml"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: root.noMap ? 52 : 0
            visible: root.noMap
            color: "#AA000000"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                color: "white"
                font.pixelSize: 14
                text: "Map: disabled"
            }
        }
    }
}
