import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    property real lat: 0
    property real lng: 0
    property real bearing: 0
    property real zoom: NaN
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
    property string tileUrlTemplate: ""
    property string styleUrl: ""
    property bool interactionEnabled: true

    readonly property bool mapLibreNativeAvailable: (typeof BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE
    readonly property bool nativeImplFailed: mapLibreLoader.status === Loader.Error
    readonly property bool usingRasterFallback: !mapLibreNativeAvailable || nativeImplFailed

    function currentItem() {
        return mapLibreLoader.item || fallbackLoader.item
    }

    function searchAddress(query) {
        const item = currentItem()
        if (item && item.searchAddress)
            item.searchAddress(query)
    }

    function clearRoute() {
        const item = currentItem()
        if (item && item.clearRoute)
            item.clearRoute()
    }

    function setFollowEnabled(enabled) {
        const item = currentItem()
        if (item && item.setFollowEnabled)
            item.setFollowEnabled(enabled)
    }

    Component.onCompleted: {
        if (!root.mapLibreNativeAvailable)
            console.warn("[MapCenterMapLibreNative] MapLibre Native is not built into this binary; using native raster fallback")
    }

    Loader {
        id: mapLibreLoader
        anchors.fill: parent
        active: root.mapLibreNativeAvailable
        source: "MapCenterMapLibreNativeImpl.qml"

        onLoaded: {
            if (!item)
                return
            item.lat = Qt.binding(function() { return root.lat })
            item.lng = Qt.binding(function() { return root.lng })
            item.bearing = Qt.binding(function() { return root.bearing })
            item.zoom = Qt.binding(function() { return root.zoom })
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
            item.styleUrl = Qt.binding(function() { return root.styleUrl })
            item.interactionEnabled = Qt.binding(function() { return root.interactionEnabled })
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("[MapCenterMapLibreNative] native implementation failed to load; using native raster fallback")
        }
    }

    Loader {
        id: fallbackLoader
        anchors.fill: parent
        active: root.usingRasterFallback
        sourceComponent: rasterFallbackComponent
    }

    Component {
        id: rasterFallbackComponent

        MapCenterNative {
            anchors.fill: parent
            lat: root.lat
            lng: root.lng
            bearing: root.bearing
            zoom: root.zoom
            speedKph: root.speedKph
            fixedOriginEnabled: root.fixedOriginEnabled
            fixedOriginLat: root.fixedOriginLat
            fixedOriginLng: root.fixedOriginLng
            fixedOriginLabel: root.fixedOriginLabel
            navigationState: root.navigationState
            mapVehiclePose: root.mapVehiclePose
            mapCameraHints: root.mapCameraHints
            mapRouteOverlay: root.mapRouteOverlay
            mapGuidanceBanner: root.mapGuidanceBanner
            mapConnectivity: root.mapConnectivity
            tileUrlTemplate: root.tileUrlTemplate
            interactionEnabled: root.interactionEnabled
        }
    }
}
