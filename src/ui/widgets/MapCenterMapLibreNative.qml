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
    property bool tileDarken: false
    property string styleUrl: ""
    property bool interactionEnabled: true

    readonly property bool mapLibreNativeAvailable: (typeof BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE
    readonly property bool allowUntestedStyles: (typeof BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES
    readonly property string trustedStyleUrls: (typeof BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        : ""
    readonly property string appTrustedStyleUrls: "https://tiles.openfreemap.org/styles/positron https://tiles.openfreemap.org/styles/liberty https://tiles.openfreemap.org/styles/dark https://tiles.openfreemap.org/styles/bright https://demotiles.maplibre.org/style.json"
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
        const trusted = (String(root.appTrustedStyleUrls || "") + " " + String(root.trustedStyleUrls || "")).split(/[\s,]+/)
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

    function bindNativeImpl(impl) {
        impl.lat = Qt.binding(function() { return root.lat })
        impl.lng = Qt.binding(function() { return root.lng })
        impl.bearing = Qt.binding(function() { return root.bearing })
        impl.zoom = Qt.binding(function() { return root.zoom })
        impl.speedKph = Qt.binding(function() { return root.speedKph })
        impl.fixedOriginEnabled = Qt.binding(function() { return root.fixedOriginEnabled })
        impl.fixedOriginLat = Qt.binding(function() { return root.fixedOriginLat })
        impl.fixedOriginLng = Qt.binding(function() { return root.fixedOriginLng })
        impl.fixedOriginLabel = Qt.binding(function() { return root.fixedOriginLabel })
        impl.navigationState = Qt.binding(function() { return root.navigationState })
        impl.mapVehiclePose = Qt.binding(function() { return root.mapVehiclePose })
        impl.mapCameraHints = Qt.binding(function() { return root.mapCameraHints })
        impl.mapRouteOverlay = Qt.binding(function() { return root.mapRouteOverlay })
        impl.mapGuidanceBanner = Qt.binding(function() { return root.mapGuidanceBanner })
        impl.mapConnectivity = Qt.binding(function() { return root.mapConnectivity })
        impl.styleUrl = Qt.binding(function() { return root.styleUrl })
        impl.interactionEnabled = Qt.binding(function() { return root.interactionEnabled })
    }


    // The Impl's Qt Location Plugin reads its `maplibre.map.styles` parameter exactly once, when
    // the Map is created. The style therefore has to be an INITIAL property of the Impl
    // (Loader.setSource(url, {styleUrl: ...})): assigning `impl.styleUrl` in `onLoaded` is too
    // late, the plugin has already been created with the Impl's own default style (that is how
    // the board ended up on https://demotiles.maplibre.org/style.json, a blank light-blue
    // world map, after the Loader refactor in the QML smoke-test PR). Style changes are
    // handled by the gate toggle in reloadNativeMap(), which re-creates the Impl.
    Loader {
        id: mapLibreLoader
        anchors.fill: parent
        active: false
        readonly property bool wanted: root.shouldUseMapLibre && root.mapLibreReloadGate

        // Resolved by URL at runtime (not a static `MapCenterMapLibreNativeImpl {}` type):
        // the Impl file is only compiled into the module when WITH_MAPLIBRE_NATIVE=ON, and a
        // static reference made MainV3/Main unloadable ("... is not a type") in every other
        // configuration, including the CI build. A missing/broken Impl now only yields
        // Loader.Error -> raster fallback, as nativeImplFailed intends.
        function sync() {
            if (wanted) {
                console.info("[MapCenterMapLibreNative] creating native map with style", root.styleUrl)
                setSource("MapCenterMapLibreNativeImpl.qml", { "styleUrl": root.styleUrl })
                active = true
            } else {
                active = false
            }
        }
        onWantedChanged: sync()
        Component.onCompleted: sync()

        onStatusChanged: {
            if (status === Loader.Error)
                root.logFallbackReason()
        }
        onLoaded: root.bindNativeImpl(item)
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
            tileDarken: root.tileDarken
            interactionEnabled: root.interactionEnabled
        }
    }
}
