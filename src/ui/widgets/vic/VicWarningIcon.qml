import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    // canonical keys: "brake"|"charge"|"check"|"fuel"|"door"|"at"|"oil"
    property string warningKey: ""
    property color color: "red"

    OemTellTaleIcon {
        anchors.fill: parent
        icon: root.warningKey
        color: root.color
        accentColor: root.color
    }
}
