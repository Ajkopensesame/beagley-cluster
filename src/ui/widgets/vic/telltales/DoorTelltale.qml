import QtQuick 2.15

MdiPathIcon {
    id: root
    property color cutoutColor: "#050A12"
    property real strokeWidth: 0

    color: "#FF3B3B"
    inset: width * 0.10
    path: "M19,14H16V16H19V14M22,21H3V11L11,3H21A1,1 0 0,1 22,4V21M11.83,5L5.83,11H20V5H11.83Z"
}
