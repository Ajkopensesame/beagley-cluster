import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    // "placeholder" | "snapshot" | "video"
    property string mode: "placeholder"

    property real lat: 0
    property real lng: 0
    property real bearing: 0

    // Snapshot mode (BBB will serve a periodic map image later)
    property string snapshotUrl: ""
    property int snapshotRefreshMs: 1000

    // Video mode (reserved for later)
    property string videoUrl: ""
    property bool videoEnabled: false

    readonly property string effectiveMode: {
        if (mode === "video") {
            // For now, video is not implemented, but we keep the API.
            return (videoEnabled && videoUrl !== "") ? "video" : "placeholder"
        }
        if (mode === "snapshot") {
            return (snapshotUrl !== "") ? "snapshot" : "placeholder"
        }
        return "placeholder"
    }

    Loader {
        anchors.fill: parent
        active: true
        sourceComponent: effectiveMode === "snapshot"
            ? snapshotComp
            : placeholderComp
    }

    Component {
        id: placeholderComp
        MapCenterPlaceholder {
            anchors.fill: parent
            lat: root.lat
            lng: root.lng
            bearing: root.bearing
            title: (root.mode === "video") ? "CAM" : "MAP"
            subtitle: (root.mode === "video") ? "video not implemented" : "placeholder"
        }
    }

    Component {
        id: snapshotComp
        MapCenterSnapshot {
            anchors.fill: parent
            lat: root.lat
            lng: root.lng
            bearing: root.bearing
            snapshotUrl: root.snapshotUrl
            refreshMs: root.snapshotRefreshMs
        }
    }
}
