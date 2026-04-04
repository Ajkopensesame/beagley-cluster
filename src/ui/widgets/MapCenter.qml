import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    // "placeholder" | "snapshot"(native) | "video" | "web"(desktop/debug)
    property string mode: "placeholder"
    property bool webFallbackActive: false
    property string webFallbackReason: ""
    property string webRenderMode: "web-vector"
    readonly property string mapRenderMode: effectiveMode === "web"
        ? webRenderMode
        : (effectiveMode === "snapshot" ? "snapshot" : "placeholder")

    property real lat: 0
    property real lng: 0
    property real bearing: 0
    property real speedKph: 0
    property bool fixedOriginEnabled: false
    property real fixedOriginLat: NaN
    property real fixedOriginLng: NaN
    property string fixedOriginLabel: ""
    property var navigationState: ({})
    property var mapVehiclePose: ({})
    property var mapCameraHints: ({})
    property var mapRouteOverlay: ({})
    property var mapGuidanceBanner: ({})
    property var mapConnectivity: ({})
    property bool interactionEnabled: true

    // Snapshot mode (BBB will serve a periodic map image later)
    property string snapshotUrl: ""
    property int snapshotRefreshMs: 1000

    // Video mode (reserved for later)
    property string videoUrl: ""
    property bool videoEnabled: false

    onModeChanged: {
        if (mode !== "web") {
            webFallbackActive = false
            webFallbackReason = ""
            webRenderMode = "web-vector"
        }
    }

    function currentItem() {
        return effectiveMode === "web" ? webLoader.item : contentLoader.item
    }

    function searchAddress(query) {
        const item = currentItem()
        if (item && item.searchAddress) item.searchAddress(query)
    }

    function clearRoute() {
        const item = currentItem()
        if (item && item.clearRoute) item.clearRoute()
    }

    function setFollowEnabled(enabled) {
        const item = currentItem()
        if (item && item.setFollowEnabled) item.setFollowEnabled(enabled)
    }

    readonly property string effectiveMode: {
        if (mode === "web") {
            return webFallbackActive ? "snapshot" : "web"
        }
        if (mode === "video") {
            // For now, video is not implemented, but we keep the API.
            return (videoEnabled && videoUrl !== "") ? "video" : "placeholder"
        }
        if (mode === "snapshot") {
            return "snapshot"
        }
        return "placeholder"
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: effectiveMode !== "web"
        sourceComponent: effectiveMode === "snapshot" ? snapshotComp : placeholderComp
    }

    Loader {
        id: webLoader
        anchors.fill: parent
        active: effectiveMode === "web"
        source: "MapCenterWeb.qml"
        onLoaded: {
            if (!item)
                return
            item.lat = Qt.binding(function() { return root.lat })
            item.lng = Qt.binding(function() { return root.lng })
            item.bearing = Qt.binding(function() { return root.bearing })
            item.speedKph = Qt.binding(function() { return root.speedKph })
            item.fixedOriginEnabled = Qt.binding(function() { return root.fixedOriginEnabled })
            item.fixedOriginLat = Qt.binding(function() { return root.fixedOriginLat })
            item.fixedOriginLng = Qt.binding(function() { return root.fixedOriginLng })
            item.fixedOriginLabel = Qt.binding(function() { return root.fixedOriginLabel })
            item.navigationState = Qt.binding(function() { return root.navigationState })
            item.mapVehiclePose = Qt.binding(function() { return root.mapVehiclePose })
            item.mapCameraHints = Qt.binding(function() { return root.mapCameraHints })
            item.mapRouteOverlay = Qt.binding(function() { return root.mapRouteOverlay })
            item.mapGuidanceBanner = Qt.binding(function() { return root.mapGuidanceBanner })
            item.mapConnectivity = Qt.binding(function() { return root.mapConnectivity })
            item.interactionEnabled = Qt.binding(function() { return root.interactionEnabled })
            item.demoMotion = false
        }
    }

    Connections {
        target: webLoader.item
        ignoreUnknownSignals: true

        function onSnapshotFallbackRequested(reason) {
            console.warn("[MapCenter] snapshot fallback:", reason)
            root.webFallbackReason = reason
            root.webFallbackActive = true
        }

        function onRenderModeChanged() {
            if (webLoader.item && webLoader.item.renderMode)
                root.webRenderMode = webLoader.item.renderMode
        }
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
            speedKph: root.speedKph
            fixedOriginEnabled: root.fixedOriginEnabled
            fixedOriginLat: root.fixedOriginLat
            fixedOriginLng: root.fixedOriginLng
            fixedOriginLabel: root.fixedOriginLabel
            snapshotUrl: root.snapshotUrl
            refreshMs: root.snapshotRefreshMs
            navigationState: root.navigationState
            mapVehiclePose: root.mapVehiclePose
            mapCameraHints: root.mapCameraHints
            mapRouteOverlay: root.mapRouteOverlay
            mapGuidanceBanner: root.mapGuidanceBanner
            mapConnectivity: root.mapConnectivity
        }
    }

}
