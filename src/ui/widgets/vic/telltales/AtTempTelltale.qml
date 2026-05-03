import QtQuick 2.15

Item {
    id: root
    width: 96
    height: 96

    property color color: "#FF8A00"
    property color cutoutColor: "#050A12"
    property real strokeWidth: 0

    readonly property string cogPath: "M12,15.5A3.5,3.5 0 0,1 8.5,12A3.5,3.5 0 0,1 12,8.5A3.5,3.5 0 0,1 15.5,12A3.5,3.5 0 0,1 12,15.5M19.43,12.97C19.47,12.65 19.5,12.33 19.5,12C19.5,11.67 19.47,11.34 19.42,11.03L21.54,9.37C21.73,9.22 21.78,8.95 21.66,8.73L19.66,5.27C19.54,5.05 19.29,4.96 19.06,5.05L16.56,6.05C16.04,5.65 15.5,5.32 14.87,5.07L14.5,2.42C14.46,2.18 14.25,2 14,2H10C9.75,2 9.54,2.18 9.5,2.42L9.13,5.07C8.5,5.32 7.96,5.66 7.44,6.05L4.94,5.05C4.71,4.96 4.46,5.05 4.34,5.27L2.34,8.73C2.21,8.95 2.27,9.22 2.46,9.37L4.58,11.03C4.53,11.34 4.5,11.67 4.5,12C4.5,12.33 4.53,12.65 4.57,12.97L2.45,14.63C2.26,14.78 2.21,15.05 2.33,15.27L4.33,18.73C4.45,18.95 4.7,19.04 4.93,18.95L7.43,17.95C7.95,18.35 8.49,18.68 9.12,18.93L9.49,21.58C9.54,21.82 9.75,22 10,22H14C14.25,22 14.46,21.82 14.5,21.58L14.87,18.93C15.5,18.68 16.04,18.34 16.56,17.95L19.06,18.95C19.29,19.04 19.54,18.95 19.66,18.73L21.66,15.27C21.78,15.05 21.73,14.78 21.54,14.63L19.43,12.97Z"
    readonly property string thermometerPath: "M17 13V7H19V13H17M17 17V15H19V17H17M13 13V5C13 3.3 11.7 2 10 2S7 3.3 7 5V13C4.8 14.7 4.3 17.8 6 20S10.8 22.7 13 21 15.7 16.2 14 14C13.7 13.6 13.4 13.3 13 13M10 4C10.6 4 11 4.4 11 5V8H9V5C9 4.4 9.4 4 10 4Z"
    readonly property color gearColor: Qt.rgba(color.r, color.g, color.b, 0.62)
    readonly property color badgeColor: Qt.rgba(cutoutColor.r, cutoutColor.g, cutoutColor.b, 0.86)

    MdiPathIcon {
        x: parent.width * 0.02
        y: parent.height * 0.10
        width: parent.width * 0.76
        height: parent.height * 0.76
        color: root.gearColor
        inset: width * 0.04
        path: root.cogPath
    }

    Rectangle {
        x: parent.width * 0.43
        y: parent.height * 0.03
        width: parent.width * 0.54
        height: parent.height * 0.76
        radius: width * 0.22
        color: root.badgeColor
        border.width: Math.max(1, parent.width * 0.025)
        border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.38)
    }

    MdiPathIcon {
        x: root.width * 0.44
        y: root.height * 0.02
        width: root.width * 0.54
        height: root.height * 0.78
        color: root.color
        inset: width * 0.02
        path: root.thermometerPath
    }
}
