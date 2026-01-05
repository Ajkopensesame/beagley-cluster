import QtQuick 2.15
import "icons"

Item {
    id: root
    width: 96
    height: 96

    property string warningKey: ""
    property color color: "red"

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.warningKey) {
            case "brake": return brakeIcon
            default: return null
            }
        }
    }

    Component {
        id: brakeIcon
        BrakeIcon { color: root.color }
    }
}
