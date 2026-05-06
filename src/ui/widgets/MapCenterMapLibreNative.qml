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
    property bool vehicleMarkerEnabled: true

    readonly property bool mapLibreNativeAvailable: (typeof BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE
    readonly property bool allowUntestedStyles: (typeof BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES
    readonly property string trustedStyleUrls: (typeof BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        : "https://demotiles.maplibre.org/style.json"
    readonly property bool styleTrusted: mapLibreStyleTrusted(styleUrl)
    readonly property bool shouldUseMapLibre: mapLibreNativeAvailable && styleTrusted
    readonly property bool nativeImplFailed: mapLibreLoader.status === Loader.Error
    readonly property bool usingRasterFallback: !shouldUseMapLibre || nativeImplFailed
    property bool mapLibreReloadGate: true

    function currentItem() {
        return mapLibreLoader.item || fallbackLoader.item
    }

    function mapLibreStyleTrusted(url) {
        if (root.allowUntestedStyles)
            return true

        const style = String(url || "").trim().toLowerCase()
        const trusted = String(root.trustedStyleUrls || "").split(/[\s,]+/)
        for (var i = 0; i < trusted.length; ++i) {
            const candidate = String(trusted[i] || "").trim().toLowerCase()
            if (candidate.length > 0 && candidate === style)
                return true
        }
        return false
    }

    function logFallbackReason() {
        if (!root.mapLibreNativeAvailable) {
            console.warn("[MapCenterMapLibreNative] MapLibre Native is not built into this binary; using native raster fallback")
        } else if (!root.styleTrusted) {
            console.warn("[MapCenterMapLibreNative] MapLibre style is not allowlisted; using native raster fallback",
                         root.styleUrl)
        } else if (root.nativeImplFailed) {
            console.warn("[MapCenterMapLibreNative] native implementation failed to load; using native raster fallback")
        }
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

    function reloadNativeMap() {
        if (!root.shouldUseMapLibre)
            return
        root.mapLibreReloadGate = false
        Qt.callLater(function() {
            root.mapLibreReloadGate = true
        })
    }

    Component.onCompleted: {
        root.logFallbackReason()
    }

    onStyleTrustedChanged: root.logFallbackReason()
    onNativeImplFailedChanged: root.logFallbackReason()
    onStyleUrlChanged: root.reloadNativeMap()

    Loader {
        id: mapLibreLoader
        anchors.fill: parent
        active: root.shouldUseMapLibre && root.mapLibreReloadGate
        sourceComponent: mapLibreNativeComponent

        onStatusChanged: {
            if (status === Loader.Error)
                root.logFallbackReason()
        }
    }

    Component {
        id: mapLibreNativeComponent

        MapCenterMapLibreNativeImpl {
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
            styleUrl: root.styleUrl
            interactionEnabled: root.interactionEnabled
            vehicleMarkerEnabled: root.vehicleMarkerEnabled
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
