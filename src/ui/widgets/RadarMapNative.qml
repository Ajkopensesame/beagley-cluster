import QtQuick 2.15

import BeagleY 1.0

Item {
    id: root
    anchors.fill: parent

    property real lat: -27.4698
    property real lng: 153.0251
    property real zoom: 7.0
    property url frameUrl: ""
    property url mapUrl: ""
    property string status: "SYNC"
    property string tileUrlTemplate: ""
    property string styleUrl: ""
    property bool interactionEnabled: false
    property bool guidesVisible: true

    readonly property bool live: root.status === "LIVE"
    readonly property bool frameReady: root.live && String(root.frameUrl).length > 0
    readonly property bool positionValid: coordValid(root.lat, -90, 90) && coordValid(root.lng, -180, 180)
    readonly property string envStyleUrl: (typeof BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL).trim()
        : ""
    readonly property string resolvedStyleUrl: String(root.styleUrl || "").length > 0
        ? String(root.styleUrl)
        : root.envStyleUrl
    readonly property string resolvedTileUrlTemplate: String(root.tileUrlTemplate || "").length > 0
        ? String(root.tileUrlTemplate)
        : "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    readonly property bool mapLibreNativeAvailable: (typeof BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE
    readonly property bool allowUntestedStyles: (typeof BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES
    readonly property string trustedStyleUrls: (typeof BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        : "https://demotiles.maplibre.org/style.json"
    readonly property string appTrustedStyleUrls: "https://tiles.openfreemap.org/styles/positron https://tiles.openfreemap.org/styles/liberty https://tiles.openfreemap.org/styles/dark https://tiles.openfreemap.org/styles/bright https://demotiles.maplibre.org/style.json"
    readonly property bool styleTrusted: mapLibreStyleTrusted(root.resolvedStyleUrl)
    readonly property bool shouldUseMapLibre: root.positionValid
        && root.mapLibreNativeAvailable
        && root.styleTrusted
    readonly property bool nativeImplFailed: mapLibreLoader.status === Loader.Error
    readonly property bool usingRasterFallback: !root.shouldUseMapLibre || root.nativeImplFailed
    readonly property bool radarReady: (mapLibreLoader.item && mapLibreLoader.item.radarReady)
        || (fallbackLoader.item && fallbackLoader.item.radarReady)
    property bool mapLibreReloadGate: true

    function coordValid(value, minValue, maxValue) {
        const number = Number(value)
        return isFinite(number) && number >= minValue && number <= maxValue
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
        if (root.shouldUseMapLibre && !root.nativeImplFailed)
            return
        if (!root.positionValid) {
            console.warn("[RadarMapNative] invalid radar map position; using cached raster radar fallback")
        } else if (!root.mapLibreNativeAvailable) {
            console.warn("[RadarMapNative] MapLibre Native is not built into this binary; using native raster radar fallback")
        } else if (!root.styleTrusted) {
            console.warn("[RadarMapNative] MapLibre style is not allowlisted; using native raster radar fallback",
                         root.resolvedStyleUrl)
        } else if (root.nativeImplFailed) {
            console.warn("[RadarMapNative] MapLibre radar implementation failed to load; using native raster radar fallback")
        }
    }

    function reloadNativeMap() {
        if (!root.shouldUseMapLibre)
            return
        root.mapLibreReloadGate = false
        Qt.callLater(function() {
            root.mapLibreReloadGate = true
        })
    }

    Component.onCompleted: root.logFallbackReason()
    onStyleTrustedChanged: root.logFallbackReason()
    onNativeImplFailedChanged: root.logFallbackReason()
    onResolvedStyleUrlChanged: root.reloadNativeMap()

    Loader {
        id: mapLibreLoader
        anchors.fill: parent
        active: root.shouldUseMapLibre && root.mapLibreReloadGate
        source: active ? "RadarMapLibreNativeImpl.qml" : ""

        onLoaded: {
            if (!item)
                return
            item.lat = Qt.binding(function() { return root.lat })
            item.lng = Qt.binding(function() { return root.lng })
            item.zoom = Qt.binding(function() { return root.zoom })
            item.frameUrl = Qt.binding(function() { return root.frameUrl })
            item.status = Qt.binding(function() { return root.status })
            item.styleUrl = Qt.binding(function() { return root.resolvedStyleUrl })
            item.interactionEnabled = Qt.binding(function() { return root.interactionEnabled })
            item.guidesVisible = Qt.binding(function() { return root.guidesVisible })
        }

        onStatusChanged: {
            if (status === Loader.Error)
                root.logFallbackReason()
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

        Item {
            anchors.fill: parent
            property alias radarReady: fallbackRadarFrame.ready

            Rectangle {
                anchors.fill: parent
                color: "#06111D"
            }

            NativeRasterMapItem {
                anchors.fill: parent
                centerLat: root.positionValid ? root.lat : -27.4698
                centerLng: root.positionValid ? root.lng : 153.0251
                zoom: root.zoom
                mapBearing: 0
                vehicleVisible: false
                tileUrlTemplate: root.resolvedTileUrlTemplate
                visible: root.positionValid
            }

            Image {
                anchors.fill: parent
                source: !root.positionValid && root.frameReady ? root.mapUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: false
                visible: !root.positionValid && root.frameReady && String(root.mapUrl).length > 0
            }

            RadarFrameItem {
                id: fallbackRadarFrame
                anchors.fill: parent
                source: root.frameReady ? root.frameUrl : ""
                mapSource: ""
                circular: false
                backgroundVisible: false
                guidesVisible: root.guidesVisible
                visible: ready
            }
        }
    }
}
