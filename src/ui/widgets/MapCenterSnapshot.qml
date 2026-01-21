import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    property real lat: 0
    property real lng: 0
    property real bearing: 0

    property string snapshotUrl: ""
    property int refreshMs: 1000

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#101418"
        border.color: "#2a333c"
        border.width: 2
        clip: true

        Image {
            id: img
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            smooth: true
            asynchronous: true
            cache: false
            visible: source !== ""
        }

        // Vehicle marker overlay
        Item {
            width: 46; height: 46
            anchors.centerIn: parent

            Rectangle {
                width: 6; height: 28; radius: 3
                anchors.centerIn: parent
                color: "#ff5555"
                transform: Rotation { origin.x: 3; origin.y: 14; angle: root.bearing }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 6

            Text { text: "MAP"; color: "#9fb2c1"; font.pixelSize: 18 }
            Text { text: snapshotUrl === "" ? "source: (none)" : "source: BBB snapshot"; color: "#d8e2ea"; font.pixelSize: 14 }
        }
    }

    function refresh() {
        if (snapshotUrl === "") return
        img.source = snapshotUrl + (snapshotUrl.indexOf("?") === -1 ? "?" : "&") + "t=" + Date.now()
    }

    Timer {
        interval: refreshMs
        running: root.visible && snapshotUrl !== ""
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
    onSnapshotUrlChanged: refresh()
}
