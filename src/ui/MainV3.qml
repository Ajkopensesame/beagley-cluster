import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.settings

import "./theme" as Theme
import "widgets" as W

Window {
    id: root

    width: 1920
    height: 720
    minimumWidth: 1920
    minimumHeight: 720
    maximumWidth: 1920
    maximumHeight: 720

    visibility: Window.Windowed
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    visible: true

    Theme.PurplePearlTheme { id: appTheme }
    Settings {
        id: clusterUiSettings
        category: "beagley_cluster_ui"
        property string mapTheme: "roads"
    }

    color: "#02060B"
    readonly property var cluster: clusterRenderModel
    readonly property real defaultMapLat: -27.4698
    readonly property real defaultMapLng: 153.0251
    readonly property string renderProfile: (typeof BEAGLEY_RENDER_PROFILE !== "undefined" && BEAGLEY_RENDER_PROFILE)
        ? String(BEAGLEY_RENDER_PROFILE)
        : "desktop"
    readonly property string effectLevel: (typeof BEAGLEY_EFFECT_LEVEL !== "undefined" && BEAGLEY_EFFECT_LEVEL)
        ? String(BEAGLEY_EFFECT_LEVEL)
        : "high"
    readonly property string mapRenderer: (typeof BEAGLEY_MAP_RENDERER !== "undefined" && BEAGLEY_MAP_RENDERER)
        ? String(BEAGLEY_MAP_RENDERER)
        : "native"
    readonly property string defaultMapLibreNativeTrustedStyles: "https://demotiles.maplibre.org/style.json"
    readonly property string mapLibreNativeStyleOverride: (typeof BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_STYLE_URL).trim()
        : ""
    readonly property string mapLibreNativeTrustedStyles: (typeof BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES !== "undefined"
        && BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        ? String(BEAGLEY_MAPLIBRE_NATIVE_TRUSTED_STYLES)
        : defaultMapLibreNativeTrustedStyles
    readonly property real mapLibreNativeMaxZoom: {
        const configured = (typeof BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM !== "undefined")
            ? Number(BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM)
            : 14.0
        return isFinite(configured) ? Math.max(1.0, Math.min(22.0, configured)) : 14.0
    }
    readonly property bool mapLibreNativeRequested: mapRenderer === "maplibre-native"
    readonly property bool mapLibreNativeAllowUntestedStyles: (typeof BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_ALLOW_UNTESTED_STYLES
    readonly property bool mapLibreNativeStyleTrusted: mapLibreStyleTrusted(activeMapStyleUrl)
    readonly property string effectiveMapRenderer: mapLibreNativeRequested && !mapLibreNativeStyleTrusted
        ? "native-online"
        : mapRenderer
    readonly property bool mapLibreNativeActive: effectiveMapRenderer === "maplibre-native"
    readonly property bool mapLibreNativeFullUnderlay: (typeof BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY
    readonly property bool mapLibreSafeCompositor: mapLibreNativeActive && !mapLibreNativeFullUnderlay
    readonly property int mapLibreSafeSideInset: mapLibreSafeCompositor
        ? Math.round(gaugeFaceSize * 0.54)
        : 0
    readonly property int mapLibreSafeVerticalInset: mapLibreSafeCompositor ? 18 : 0
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool effectsOff: effectLevel === "off"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property int menuTextRenderType: embeddedSafeMode ? Text.QtRendering : Text.NativeRendering
    readonly property int menuTextInputRenderType: embeddedSafeMode ? TextInput.QtRendering : TextInput.NativeRendering
    readonly property int menuTextHintingPreference: embeddedSafeMode ? Font.PreferNoHinting : Font.PreferDefaultHinting
    readonly property bool stressScene: (typeof BEAGLEY_STRESS_SCENE !== "undefined" && BEAGLEY_STRESS_SCENE) ? true : false
    readonly property bool embeddedEffectBudgetMode: renderProfile === "embedded" && lowEffectMode
    readonly property bool embeddedHighEffectBudgetMode: renderProfile === "embedded" && effectLevel === "high"
    readonly property bool embeddedDirectMapCamera: renderProfile === "embedded"
    readonly property bool embeddedGaugeMatrixRainMode: renderProfile === "embedded"
    readonly property bool gaugeMatrixRainEnabled: !effectsOff
    readonly property real gaugeMatrixRainSharedPhase: (gaugeMatrixRainEnabled && !embeddedGaugeMatrixRainMode)
        ? sharedEffectPhase
        : NaN
    readonly property bool sharedEffectClockEnabled: !effectsOff && !embeddedEffectBudgetMode
    readonly property bool stressMapMotionEnabled: stressScene && !lowEffectMode && renderProfile !== "embedded"
    readonly property int gaugeShellSize: 840
    readonly property int gaugePodSize: 704
    readonly property int gaugeFaceSize: 724
    readonly property int gaugeEdgeBleed: -48
    property real sharedEffectPhase: 0.0
    property real stressPhase: 0.0

    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale
    readonly property bool truthOk: linkOk && !hub.bbbStale
    readonly property bool hotspotConnected: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.connected)
    readonly property bool hotspotIpLease: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.hasIpLease)
    readonly property bool internetOk: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.internetReachable)
    readonly property string hotspotState: (typeof wifiSetup !== "undefined") && wifiSetup ? String(wifiSetup.networkState || "waiting_for_hotspot") : "waiting_for_hotspot"
    readonly property bool gpsFixOk: !!(hub && hub.gpsFixValid)
    readonly property bool gpsEverValid: !!(hub && hub.gpsEverValid)
    readonly property bool liveMapPoseValid: !!(hub
        && hub.vehicleStateSeen
        && hub.gpsPoseValid
        && hub.gpsFixValid
        && !hub.linkStale
        && !hub.bbbStale
        && isFinite(Number(hub.gpsLat))
        && isFinite(Number(hub.gpsLng)))
    readonly property string gpsSourceText: hub && hub.gpsSource ? String(hub.gpsSource).toUpperCase() : "UNKNOWN"
    readonly property var navConnectivity: navigation ? (navigation.mapConnectivity || ({})) : ({})
    readonly property var navVehiclePose: navigation ? (navigation.mapVehiclePose || ({})) : ({})
    readonly property bool navVehiclePoseFinite: isFinite(Number(navVehiclePose.lat))
        && isFinite(Number(navVehiclePose.lng))
    readonly property bool mapVehicleMarkerVisible: mapLibreNativeActive
        && (liveMapPoseValid || navVehiclePoseFinite)
    readonly property bool mapVehicleMarkerGuidanceAnchor: hasActiveRoute
        && navigation
        && navigation.guidanceStarted
    readonly property var navBanner: navigation && navigation.mapGuidanceBanner
        ? (navigation.mapGuidanceBanner.banner || ({}))
        : ({})
    readonly property bool hasActiveRoute: navigation && navigation.activeRoute && Object.keys(navigation.activeRoute).length > 0
    readonly property bool followUnlocked: navigation && navigation.followMode === "free_pan"
    readonly property bool gpsHoldingPose: !!navConnectivity.gpsUsingLastKnown
    readonly property string gearText: truthOk && hub && hub.gear ? hub.gear : "-"
    readonly property real speedValue: truthOk && hub ? (hub.speedKph || 0) : 0
    readonly property real rpmValue: truthOk && hub ? (hub.rpm || 0) : 0
    readonly property real fuelValue: truthOk && hub ? (hub.fuelPct || 0) : 0
    readonly property real coolantValue: truthOk && hub ? (hub.coolantC || 0) : 0
    readonly property real displaySpeedValue: stressScene ? (78 + 50 * Math.sin(stressPhase * 0.9)) : speedValue
    readonly property real displayRpmValue: stressScene ? (2400 + 1800 * (0.5 + 0.5 * Math.sin(stressPhase * 1.15 + 0.4))) : rpmValue
    readonly property real displayFuelValue: stressScene ? (18 + 11 * Math.sin(stressPhase * 0.30 - 1.2)) : fuelValue
    readonly property real displayCoolantValue: stressScene ? (70 + 42 * Math.sin(stressPhase * 0.42 + 1.3)) : coolantValue
    readonly property int indicatorVisualHoldMs: 1850
    readonly property bool rawLeftIndicator: stressScene
        ? Math.sin(stressPhase * 1.35) > 0.68
        : truthOk && !!hub.leftIndicator
    readonly property bool rawRightIndicator: stressScene
        ? Math.sin(stressPhase * 1.12 + 2.4) > 0.68
        : truthOk && !!hub.rightIndicator
    property bool displayLeftIndicator: false
    property bool displayRightIndicator: false
    readonly property bool indicatorCascadeActive: displayLeftIndicator || displayRightIndicator
    readonly property int indicatorCascadeCycleMs: lowEffectMode ? 2600 : 2200
    property real indicatorCascadePhase: 0.0
    readonly property real displayMapLat: stressMapMotionEnabled
        ? (root.defaultMapLat + 0.0028 * Math.sin(stressPhase * 0.12))
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsLat)
        : (isFinite(Number(navVehiclePose.lat))
        ? Number(navVehiclePose.lat)
        : (isFinite(Number(hub && hub.gpsLat)) ? Number(hub.gpsLat) : root.defaultMapLat)))
        : (cluster && isFinite(Number(cluster.mapLat))
        ? Number(cluster.mapLat)
        : (liveMapPoseValid
        ? Number(hub.gpsLat)
        : (isFinite(Number(navVehiclePose.lat))
        ? Number(navVehiclePose.lat)
        : (isFinite(Number(hub && hub.gpsLat)) ? Number(hub.gpsLat) : root.defaultMapLat)))))
    readonly property real displayMapLng: stressMapMotionEnabled
        ? (root.defaultMapLng + 0.0046 * Math.cos(stressPhase * 0.12))
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsLng)
        : (isFinite(Number(navVehiclePose.lng))
        ? Number(navVehiclePose.lng)
        : (isFinite(Number(hub && hub.gpsLng)) ? Number(hub.gpsLng) : root.defaultMapLng)))
        : (cluster && isFinite(Number(cluster.mapLng))
        ? Number(cluster.mapLng)
        : (liveMapPoseValid
        ? Number(hub.gpsLng)
        : (isFinite(Number(navVehiclePose.lng))
        ? Number(navVehiclePose.lng)
        : (isFinite(Number(hub && hub.gpsLng)) ? Number(hub.gpsLng) : root.defaultMapLng)))))
    readonly property real displayMapBearing: stressMapMotionEnabled
        ? ((stressPhase * 26) % 360)
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsBearing)
        : (isFinite(Number(navVehiclePose.bearing))
        ? Number(navVehiclePose.bearing)
        : (isFinite(Number(hub && hub.gpsBearing)) ? Number(hub.gpsBearing) : 0)))
        : (cluster && isFinite(Number(cluster.mapBearing))
        ? Number(cluster.mapBearing)
        : (liveMapPoseValid
        ? Number(hub.gpsBearing)
        : (isFinite(Number(navVehiclePose.bearing))
        ? Number(navVehiclePose.bearing)
        : (isFinite(Number(hub && hub.gpsBearing)) ? Number(hub.gpsBearing) : 0)))))
    readonly property real displayMapZoom: stressMapMotionEnabled
        ? (15.1 + 0.35 * Math.sin(stressPhase * 0.08))
        : (embeddedDirectMapCamera
        ? embeddedMapZoomForSpeed(displayMapSpeed)
        : (cluster && isFinite(Number(cluster.mapZoom))
        ? Number(cluster.mapZoom)
        : 15.5))
    readonly property real displayMapSpeed: stressScene
        ? Math.max(8, displaySpeedValue)
        : (liveMapPoseValid && isFinite(Number(hub && hub.gpsSpeedKph)) && Number(hub.gpsSpeedKph) > 0
        ? Number(hub.gpsSpeedKph)
        : (isFinite(Number(navVehiclePose.speedKph)) ? Number(navVehiclePose.speedKph) : speedValue))
    readonly property bool fallbackRouteOriginEnabled: false
    readonly property real fallbackRouteOriginLat: NaN
    readonly property real fallbackRouteOriginLng: NaN
    readonly property string fallbackRouteOriginLabel: ""
    property string pendingSuggestionQuery: ""
    property var keyboardRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["SPACE", ".", ",", "-", "BACKSPACE", "CLEAR"]
    ]
    property bool mapMenuOpen: false
    property bool navControlsOpen: false
    property bool searchKeyboardOpen: false
    property string mapMenuStage: "search"
    property var pendingDestination: ({})
    property int selectedRouteIndex: 0
    property bool awaitingRoutePreview: false
    property bool departureCameraCloseInActive: false
    readonly property var effectiveMapCameraHints: buildEffectiveMapCameraHints()
    readonly property var mapThemeOptions: [
        {
            id: "roads",
            label: "Roads",
            detail: "OpenStreetMap",
            tileUrlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            styleUrl: "https://tiles.openfreemap.org/styles/liberty",
            maxZoom: 19,
            swatchA: "#F2EFE9",
            swatchB: "#91B3C5"
        },
        {
            id: "light",
            label: "Light",
            detail: "Positron",
            tileUrlTemplate: "https://a.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
            styleUrl: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json",
            maxZoom: 19,
            swatchA: "#F7F8F3",
            swatchB: "#ADBFD1"
        },
        {
            id: "drive",
            label: "Drive",
            detail: "Voyager",
            tileUrlTemplate: "https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
            styleUrl: "https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json",
            maxZoom: 19,
            swatchA: "#F2F0E8",
            swatchB: "#77A0B8"
        },
        {
            id: "terrain",
            label: "Terrain",
            detail: "Topo",
            tileUrlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
            styleUrl: "https://tiles.openfreemap.org/styles/liberty",
            maxZoom: 17,
            swatchA: "#C4D6A0",
            swatchB: "#8A7A55"
        }
    ]
    readonly property var activeMapThemeOption: mapThemeOption(clusterUiSettings.mapTheme)
    readonly property string activeMapTileUrlTemplate: String(activeMapThemeOption.tileUrlTemplate || "")
    readonly property string activeMapStyleUrl: mapLibreNativeStyleOverride.length > 0
        ? mapLibreNativeStyleOverride
        : String(activeMapThemeOption.styleUrl || "")
    readonly property real activeMapMaxZoom: mapLibreNativeRequested
        ? Math.min(Number(activeMapThemeOption.maxZoom || 19), mapLibreNativeMaxZoom)
        : Number(activeMapThemeOption.maxZoom || 19)
    readonly property bool routeLookupInProgress: navigation
        && (navigation.state === "routing" || navigation.state === "rerouting")
    readonly property int activeWarnings: {
        if (!truthOk || !hub) return 0
        var n = 0
        if (hub.warnBrake) n++
        if (hub.warnOil) n++
        if (hub.warnCharge) n++
        if (hub.warnDoor) n++
        if (hub.warnCheckEngine) n++
        if (hub.warnAT) n++
        if (hub.warnFuelLow) n++
        if (hub.diagnosticOk === false) n++
        return n
    }

    function warningSummary() {
        if (!truthOk || !hub) return "NO LIVE VEHICLE DATA"
        var parts = []
        if (hub.warnBrake) parts.push("BRAKE")
        if (hub.warnOil) parts.push("OIL")
        if (hub.warnCharge) parts.push("CHARGE")
        if (hub.warnDoor) parts.push("DOOR")
        if (hub.warnCheckEngine) parts.push("CHECK ENGINE")
        if (hub.warnAT) parts.push("A/T")
        if (hub.warnFuelLow) parts.push("LOW FUEL")
        if (hub.diagnosticOk === false) {
            if (parts.length === 0 && hub.diagnosticSummary) parts.push(String(hub.diagnosticSummary).toUpperCase())
            else parts.push(hub.diagnosticSeverity === "error" ? "DIAG ERROR" : "DIAG WARN")
        }
        return parts.length > 0 ? parts.join("  •  ") : "SYSTEMS NOMINAL"
    }

    function statusText() {
        if (!hub || !hub.connected) return "LINK DOWN"
        if (hub.linkStale) return "LINK STALE"
        if (hub.bbbStale) return "BBB STALE"
        if (hub.diagnosticOk === false) {
            return hub.diagnosticSeverity === "error" ? "DIAG ERROR" : "DIAG WARN"
        }
        return "LIVE"
    }

    function radians(value) {
        return value * Math.PI / 180.0
    }

    function metersBetween(aLat, aLng, bLat, bLng) {
        const earthRadius = 6371000.0
        const dLat = radians(bLat - aLat)
        const dLng = radians(bLng - aLng)
        const lat1 = radians(aLat)
        const lat2 = radians(bLat)
        const sinLat = Math.sin(dLat / 2.0)
        const sinLng = Math.sin(dLng / 2.0)
        const h = sinLat * sinLat + Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng
        return 2.0 * earthRadius * Math.asin(Math.sqrt(h))
    }

    function embeddedMapZoomForSpeed(speedKph) {
        const speed = Number(speedKph)
        if (!isFinite(speed))
            return Math.min(14.8, root.activeMapMaxZoom)
        if (speed >= 110)
            return Math.min(13.4, root.activeMapMaxZoom)
        if (speed >= 80)
            return Math.min(13.8, root.activeMapMaxZoom)
        if (speed >= 45)
            return Math.min(14.4, root.activeMapMaxZoom)
        if (speed >= 15)
            return Math.min(15.0, root.activeMapMaxZoom)
        return Math.min(15.5, root.activeMapMaxZoom)
    }

    function departureCloseInZoomForSpeed(speedKph) {
        const speed = Number(speedKph)
        if (!isFinite(speed) || speed < 15)
            return 17.8
        if (speed >= 80)
            return 16.2
        if (speed >= 45)
            return 16.7
        return 17.3
    }

    function buildEffectiveMapCameraHints() {
        const source = navigation ? (navigation.mapCameraHints || ({})) : ({})
        var hints = {}
        for (var key in source)
            hints[key] = source[key]

        if (root.departureCameraCloseInActive) {
            const hintedZoom = Number(hints.zoom)
            const baseZoom = isFinite(hintedZoom) ? hintedZoom : root.embeddedMapZoomForSpeed(root.displayMapSpeed)
            const hintedLookAhead = Number(hints.lookAheadMeters)
            const hintedPitch = Number(hints.pitch)
            hints.mode = "departure"
            hints.overview = false
            hints.zoom = Math.min(Math.max(baseZoom, root.departureCloseInZoomForSpeed(root.displayMapSpeed)), root.activeMapMaxZoom)
            hints.lookAheadMeters = Math.min(isFinite(hintedLookAhead) ? hintedLookAhead : 42, 42)
            hints.pitch = Math.min(isFinite(hintedPitch) ? hintedPitch : 48, 48)
            hints.zoomAnimationMs = 1500
            return hints
        }

        const zoomValue = Number(hints.zoom)
        if (isFinite(zoomValue))
            hints.zoom = Math.min(zoomValue, root.activeMapMaxZoom)
        if (!isFinite(Number(hints.zoomAnimationMs)))
            hints.zoomAnimationMs = 760
        return hints
    }

    function mapThemeOption(themeId) {
        const wanted = String(themeId || "roads") === "dark" ? "drive" : String(themeId || "roads")
        for (var i = 0; i < root.mapThemeOptions.length; ++i) {
            const option = root.mapThemeOptions[i]
            if (option.id === wanted)
                return option
        }
        return root.mapThemeOptions[0]
    }

    function selectMapTheme(themeId) {
        const option = root.mapThemeOption(themeId)
        clusterUiSettings.mapTheme = option.id
    }

    function mapLibreStyleTrusted(styleUrl) {
        if (!root.mapLibreNativeRequested)
            return false
        if (root.mapLibreNativeAllowUntestedStyles)
            return true

        const url = String(styleUrl || "").trim().toLowerCase()
        const trusted = String(root.mapLibreNativeTrustedStyles || "")
            .split(/[\s,]+/)
        for (var i = 0; i < trusted.length; ++i) {
            const candidate = String(trusted[i] || "").trim().toLowerCase()
            if (candidate.length > 0 && candidate === url)
                return true
        }
        return false
    }

    function logMapLibreFallbackIfNeeded() {
        if (root.mapLibreNativeAllowUntestedStyles)
            return
        if (root.mapLibreNativeRequested && root.effectiveMapRenderer !== "maplibre-native") {
            console.warn("[MainV3] MapLibre Native requested but style is not allowlisted; using native raster map",
                         root.activeMapStyleUrl)
        }
    }

    function suggestionOrigin() {
        return {
            lat: isFinite(Number(navVehiclePose.lat)) ? Number(navVehiclePose.lat) : NaN,
            lng: isFinite(Number(navVehiclePose.lng)) ? Number(navVehiclePose.lng) : NaN
        }
    }

    function routeSearchQuery(query) {
        const trimmed = String(query || "").trim()
        if (trimmed.length < 2)
            return
        root.mapMenuStage = "search"
        root.searchKeyboardOpen = false
        navigation.search(trimmed)
    }

    function applyKeyboardKey(key, target) {
        if (!target)
            return
        if (key === "SPACE") {
            target.insert(target.cursorPosition, " ")
            return
        }
        if (key === "BACKSPACE") {
            if (target.selectionStart !== target.selectionEnd) {
                target.remove(target.selectionStart, target.selectionEnd)
            } else if (target.cursorPosition > 0) {
                target.remove(target.cursorPosition - 1, target.cursorPosition)
            }
            return
        }
        if (key === "CLEAR") {
            target.text = ""
            return
        }
        target.insert(target.cursorPosition, key)
    }

    function fetchSearchSuggestions(query) {
        const trimmed = String(query || "").trim()
        pendingSuggestionQuery = trimmed
        if (trimmed.length < 2) {
            navigation.search("")
            return
        }
        navigation.search(trimmed)
    }

    function openMapMenu() {
        root.mapMenuOpen = true
        root.searchKeyboardOpen = false
        root.awaitingRoutePreview = false
        if (hasActiveRoute && navigation.activeRoute.destination)
            pendingDestination = navigation.activeRoute.destination
        root.mapMenuStage = (root.availableRouteOptions().length > 0 && hasActiveRoute) ? "routes" : "search"
        root.syncSelectedRouteIndexFromNavigation()
    }

    function chooseMapMenuTab(stage) {
        if (stage === "routes") {
            if (root.availableRouteOptions().length > 0 || root.hasActiveRoute) {
                stage = "routes"
            } else if (root.awaitingRoutePreview || root.routeLookupInProgress || Object.keys(root.pendingDestination).length > 0) {
                stage = "routing"
            } else {
                stage = "search"
            }
        }
        root.mapMenuStage = stage
        root.searchKeyboardOpen = false
        if (stage === "routes")
            root.syncSelectedRouteIndexFromNavigation()
        if (stage === "search" && searchInput && String(searchInput.text || "").trim().length >= 2)
            suggestionDebounce.restart()
    }

    function menuResultsModel() {
        if (root.mapMenuStage !== "search")
            return []
        const query = searchInput ? String(searchInput.text || "").trim() : ""
        return query.length >= 2 ? navigation.searchResults : navigation.recents
    }

    function chooseSearchResult(itemData) {
        if (!itemData)
            return
        const lat = Number(itemData.lat)
        const lng = Number(itemData.lng)
        if (!isFinite(lat) || !isFinite(lng))
            return
        const label = String(itemData.label || itemData.primary || "Destination")
        root.mapMenuStage = "routing"
        root.awaitingRoutePreview = true
        searchInput.text = label
        searchInput.cursorPosition = searchInput.text.length
        pendingDestination = {
            label: label,
            primary: String(itemData.primary || label),
            secondary: String(itemData.secondary || ""),
            lat: lat,
            lng: lng
        }
        selectedRouteIndex = 0
        root.searchKeyboardOpen = false
        navigation.setDestination(lat, lng, label)
    }

    function availableRouteOptions() {
        if (typeof navigation.routeAlternatives !== "undefined"
                && navigation.routeAlternatives
                && navigation.routeAlternatives.length > 0) {
            return navigation.routeAlternatives
        }
        if (hasActiveRoute && navigation.activeRoute && navigation.activeRoute.destination) {
            return [{
                index: 0,
                label: "Route",
                distanceMeters: navigation.activeRoute.distanceMeters,
                durationSeconds: navigation.activeRoute.durationSeconds,
                deltaSeconds: 0,
                maneuverCount: navigation.activeRoute.maneuverCount || 0,
                destination: navigation.activeRoute.destination
            }]
        }
        return []
    }

    function syncSelectedRouteIndexFromNavigation() {
        if (typeof navigation.selectedRouteAlternative !== "undefined"
                && navigation.selectedRouteAlternative >= 0) {
            root.selectedRouteIndex = navigation.selectedRouteAlternative
        } else {
            root.selectedRouteIndex = 0
        }
    }

    function selectRoutePreview(index) {
        const routeIndex = Number(index)
        if (!isFinite(routeIndex) || routeIndex < 0)
            return
        selectedRouteIndex = routeIndex
        if (typeof navigation.selectRouteAlternative === "function")
            navigation.selectRouteAlternative(routeIndex)
        root.mapMenuStage = "routes"
    }

    function startSelectedRoute() {
        if (root.availableRouteOptions().length <= 0 && !root.hasActiveRoute)
            return
        if (typeof navigation.selectRouteAlternative === "function" && root.availableRouteOptions().length > 0)
            navigation.selectRouteAlternative(selectedRouteIndex)
        if (typeof navigation.startGuidance === "function")
            navigation.startGuidance()
        else
            navigation.setFollowEnabled(true)
        navField.setFollowEnabled(true)
        root.departureCameraCloseInActive = true
        departureCameraCloseInTimer.restart()
        root.awaitingRoutePreview = false
        root.mapMenuOpen = false
        root.searchKeyboardOpen = false
    }

    function backToRouteSearch() {
        root.mapMenuStage = "search"
        root.awaitingRoutePreview = false
        root.searchKeyboardOpen = false
        if (String(searchInput.text || "").trim().length >= 2)
            suggestionDebounce.restart()
    }

    function clearMapSearch() {
        pendingDestination = ({})
        selectedRouteIndex = 0
        root.mapMenuStage = "search"
        root.awaitingRoutePreview = false
        root.departureCameraCloseInActive = false
        departureCameraCloseInTimer.stop()
        searchInput.text = ""
        navigation.search("")
        navigation.clearRoute()
        root.searchKeyboardOpen = false
    }

    function formatRouteDelta(deltaSeconds) {
        const value = Number(deltaSeconds)
        if (!isFinite(value) || value < 45)
            return "BEST"
        return "+" + formatDurationSeconds(value)
    }

    function formatDistanceMeters(meters) {
        const value = Number(meters)
        if (!isFinite(value) || value <= 0)
            return "--"
        if (value >= 10000)
            return Math.round(value / 1000) + " km"
        if (value >= 1000)
            return (value / 1000).toFixed(1) + " km"
        return Math.round(value) + " m"
    }

    function formatDurationSeconds(seconds) {
        const value = Number(seconds)
        if (!isFinite(value) || value <= 0)
            return "--"
        const totalMinutes = Math.max(1, Math.round(value / 60))
        if (totalMinutes >= 60) {
            const hours = Math.floor(totalMinutes / 60)
            const minutes = totalMinutes % 60
            return hours + "h " + (minutes > 0 ? minutes + "m" : "")
        }
        return totalMinutes + " min"
    }

    function hotspotBadgeText() {
        if (hotspotState === "online")
            return "HOTSPOT ONLINE"
        if (hotspotState === "no_internet")
            return "HOTSPOT NO NET"
        if (hotspotState === "associated_no_ip")
            return "HOTSPOT DHCP"
        if (hotspotState === "no_config")
            return "HOTSPOT SETUP"
        return "HOTSPOT JOINING"
    }

    function gpsBadgeText() {
        if (gpsFixOk)
            return "GPS FIX"
        if (gpsHoldingPose)
            return "GPS HOLD"
        if (navigation.bbbLinkOk)
            return "GPS WEAK"
        return "GPS WAIT"
    }

    Component.onCompleted: {
        root.showNormal()
        root.raise()
        root.requestActivate()
        updateLeftIndicatorVisual()
        updateRightIndicatorVisual()
        Qt.callLater(logMapLibreFallbackIfNeeded)
    }

    onActiveMapStyleUrlChanged: Qt.callLater(logMapLibreFallbackIfNeeded)
    onMapLibreNativeStyleTrustedChanged: Qt.callLater(logMapLibreFallbackIfNeeded)

    Connections {
        target: navigation

        function onNavigationStateChanged() {
            if (!root.mapMenuOpen)
                return
            if (root.awaitingRoutePreview && root.routeLookupInProgress && Object.keys(root.pendingDestination).length > 0)
                root.mapMenuStage = "routing"
        }

        function onRouteAlternativesChanged() {
            if (root.availableRouteOptions().length <= 0)
                return
            if (Object.keys(root.pendingDestination).length === 0 && navigation.activeRoute.destination)
                root.pendingDestination = navigation.activeRoute.destination
            root.syncSelectedRouteIndexFromNavigation()
            if (root.awaitingRoutePreview || root.mapMenuStage === "routing" || root.mapMenuStage === "routes") {
                root.mapMenuStage = "routes"
                root.awaitingRoutePreview = false
            }
        }

        function onSelectedRouteAlternativeChanged() {
            root.syncSelectedRouteIndexFromNavigation()
        }

        function onRouteChanged() {
            if (root.mapMenuOpen
                    && (root.awaitingRoutePreview || root.mapMenuStage === "routing")
                    && root.hasActiveRoute
                    && Object.keys(root.pendingDestination).length > 0) {
                root.mapMenuStage = "routes"
                root.awaitingRoutePreview = false
            }
        }
    }

    Timer {
        id: departureCameraCloseInTimer
        interval: 2200
        repeat: false
        onTriggered: root.departureCameraCloseInActive = false
    }

    Timer {
        id: effectClock
        interval: root.embeddedHighEffectBudgetMode ? 300 : (root.lowEffectMode ? 140 : 90)
        running: root.sharedEffectClockEnabled
        repeat: true
        onTriggered: root.sharedEffectPhase += interval / 1000.0
    }

    Timer {
        id: stressClock
        interval: 50
        running: root.stressScene
        repeat: true
        onTriggered: root.stressPhase += interval / 1000.0
    }

    function updateLeftIndicatorVisual() {
        if (root.rawLeftIndicator) {
            root.displayLeftIndicator = true
            leftIndicatorHoldTimer.restart()
        } else if (root.displayLeftIndicator) {
            leftIndicatorHoldTimer.restart()
        }
    }

    function updateRightIndicatorVisual() {
        if (root.rawRightIndicator) {
            root.displayRightIndicator = true
            rightIndicatorHoldTimer.restart()
        } else if (root.displayRightIndicator) {
            rightIndicatorHoldTimer.restart()
        }
    }

    Timer {
        id: leftIndicatorHoldTimer
        interval: root.indicatorVisualHoldMs
        repeat: false
        onTriggered: {
            if (root.rawLeftIndicator) {
                restart()
            } else {
                root.displayLeftIndicator = false
            }
        }
    }

    Timer {
        id: rightIndicatorHoldTimer
        interval: root.indicatorVisualHoldMs
        repeat: false
        onTriggered: {
            if (root.rawRightIndicator) {
                restart()
            } else {
                root.displayRightIndicator = false
            }
        }
    }

    onRawLeftIndicatorChanged: updateLeftIndicatorVisual()
    onRawRightIndicatorChanged: updateRightIndicatorVisual()
    onIndicatorCascadeActiveChanged: root.indicatorCascadePhase = 0.0

    NumberAnimation on indicatorCascadePhase {
        running: root.indicatorCascadeActive
        loops: Animation.Infinite
        from: 0.0
        to: 1.0
        duration: root.indicatorCascadeCycleMs
        easing.type: Easing.Linear
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#04070C" }
            GradientStop { position: 0.35; color: "#07111D" }
            GradientStop { position: 0.70; color: "#06131A" }
            GradientStop { position: 1.00; color: "#02060A" }
        }
    }

    Canvas {
        anchors.fill: parent
        visible: !root.lowEffectMode
        opacity: 0.36
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const grad = ctx.createLinearGradient(0, 0, width, height)
            grad.addColorStop(0.0, "rgba(0,255,220,0.05)")
            grad.addColorStop(0.45, "rgba(0,136,255,0.03)")
            grad.addColorStop(1.0, "rgba(255,255,255,0.01)")
            ctx.fillStyle = grad
            ctx.fillRect(0, 0, width, height)

            ctx.strokeStyle = "rgba(120,200,255,0.08)"
            ctx.lineWidth = 1
            for (var x = -height; x < width + height; x += 54) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x - height * 0.26, height)
                ctx.stroke()
            }
        }
    }

    Item {
        id: canopy
        anchors.fill: parent
        anchors.margins: 0

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: "#09111A"
            border.width: 0
            border.color: "#21435B"
        }

        Canvas {
            anchors.fill: parent
            visible: !root.lowEffectMode
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                const glow = ctx.createLinearGradient(0, 0, width, 0)
                glow.addColorStop(0.0, "rgba(41,209,255,0.11)")
                glow.addColorStop(0.2, "rgba(41,209,255,0.02)")
                glow.addColorStop(0.5, "rgba(0,0,0,0)")
                glow.addColorStop(0.8, "rgba(41,209,255,0.02)")
                glow.addColorStop(1.0, "rgba(41,209,255,0.11)")
                ctx.fillStyle = glow
                ctx.fillRect(0, 0, width, height)

                ctx.strokeStyle = "rgba(115,225,255,0.16)"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(width * 0.18, 110)
                ctx.lineTo(width * 0.34, 84)
                ctx.lineTo(width * 0.66, 84)
                ctx.lineTo(width * 0.82, 110)
                ctx.stroke()

                ctx.strokeStyle = "rgba(115,225,255,0.10)"
                ctx.beginPath()
                ctx.moveTo(width * 0.16, height - 108)
                ctx.lineTo(width * 0.36, height - 88)
                ctx.lineTo(width * 0.64, height - 88)
                ctx.lineTo(width * 0.84, height - 108)
                ctx.stroke()
            }
        }

        W.MapCenter {
            id: navField
            anchors.fill: parent
            anchors.leftMargin: root.mapLibreSafeSideInset
            anchors.rightMargin: root.mapLibreSafeSideInset
            anchors.topMargin: root.mapLibreSafeVerticalInset
            anchors.bottomMargin: root.mapLibreSafeVerticalInset
            clip: false
            mode: ((typeof BEAGLEY_NO_MAP !== "undefined" && BEAGLEY_NO_MAP)
                && !(root.effectiveMapRenderer === "native"
                    || root.effectiveMapRenderer === "native-online"
                    || root.effectiveMapRenderer === "maplibre-native"))
                ? "placeholder"
                : ((root.effectiveMapRenderer === "maplibre-native")
                    ? "maplibre-native"
                    : ((root.effectiveMapRenderer === "web"
                    && !(typeof BEAGLEY_FORCE_SNAPSHOT_MAP !== "undefined" && BEAGLEY_FORCE_SNAPSHOT_MAP))
                    ? "web"
                    : ((root.effectiveMapRenderer === "native" || root.effectiveMapRenderer === "native-online")
                        ? "native"
                        : "snapshot")))
            interactionEnabled: !((typeof BEAGLEY_EMBEDDED_DISPLAY !== "undefined" && BEAGLEY_EMBEDDED_DISPLAY) || false)
            lat: root.displayMapLat
            lng: root.displayMapLng
            bearing: root.displayMapBearing
            zoom: NaN
            speedKph: root.displayMapSpeed
            fixedOriginEnabled: fallbackRouteOriginEnabled
            fixedOriginLat: fallbackRouteOriginLat
            fixedOriginLng: fallbackRouteOriginLng
            fixedOriginLabel: fallbackRouteOriginLabel
            navigationState: (root.effectiveMapRenderer === "web") ? navigation.mapPayload : ({})
            mapVehiclePose: navigation.mapVehiclePose
            mapCameraHints: root.effectiveMapCameraHints
            mapRouteOverlay: navigation.mapRouteOverlay
            mapGuidanceBanner: navigation.mapGuidanceBanner
            mapConnectivity: navigation.mapConnectivity
            tileUrlTemplate: root.activeMapTileUrlTemplate
            styleUrl: root.activeMapStyleUrl
            snapshotRefreshMs: 0
            videoEnabled: false
            videoUrl: ""
        }

        Item {
            id: mapLibreCompositorFence
            anchors.fill: parent
            visible: root.mapLibreSafeCompositor
            z: 8

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.mapLibreSafeSideInset
                color: root.color
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.mapLibreSafeSideInset
                color: root.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.mapLibreSafeVerticalInset
                color: root.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.mapLibreSafeVerticalInset
                color: root.color
            }
        }

        W.MapVehicleMarker {
            id: mapVehicleMarker
            width: 54
            height: 64
            z: 180
            visible: root.mapVehicleMarkerVisible
            x: Math.round(parent.width * 0.5 - width * 0.5)
            y: Math.round(parent.height * (root.mapVehicleMarkerGuidanceAnchor ? 0.84 : 0.5) - height * 0.54)
            bearing: root.displayMapBearing
        }

        W.WeatherCorners {
            anchors.fill: parent
            z: 260
            theme: appTheme
            lat: root.displayMapLat
            lng: root.displayMapLng
            livePositionValid: root.liveMapPoseValid
            effectLevel: root.effectLevel
            stressScene: root.stressScene
            phase: root.sharedEffectPhase
            nowPlayingService: (typeof nowPlaying !== "undefined") ? nowPlaying : null
            expandedMode: (typeof BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE !== "undefined")
                ? String(BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE)
                : ""
            active: !root.mapMenuOpen && !root.navControlsOpen

            onMapMenuRequested: {
                root.openMapMenu()
            }
        }

        Item {
            id: leftSideMass
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: false
        }

        Item {
            id: rightSideMass
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: false
        }

        Item {
            id: cornerMask
            anchors.fill: parent
            visible: false
            readonly property int cornerRadius: 34

            Canvas {
                anchors.left: parent.left
                anchors.top: parent.top
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(width, height)
                    ctx.arc(width, height, width, Math.PI, Math.PI * 1.5)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.right: parent.right
                anchors.top: parent.top
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(0, height)
                    ctx.arc(0, height, width, Math.PI * 1.5, Math.PI * 2.0)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(width, 0)
                    ctx.arc(width, 0, width, Math.PI * 0.5, Math.PI)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.arc(0, 0, width, 0, Math.PI * 0.5)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }
        }

        Item {
            id: leftGaugeShell
            width: root.gaugeShellSize
            height: root.gaugeShellSize
            z: 220
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: root.gaugeEdgeBleed

            Rectangle {
                anchors.centerIn: parent
                width: root.gaugeFaceSize + 18
                height: width
                radius: width / 2
                visible: root.mapLibreSafeCompositor
                color: "#010309"
            }

            W.GaugeLensShell {
                anchors.fill: parent
                visible: !root.lowEffectMode
                theme: appTheme
                effectLevel: root.effectLevel
                gaugeColor: appTheme.speedColor(root.displaySpeedValue)
                chromeColor: appTheme.pearlLow
                podSize: root.gaugePodSize
                faceSize: root.gaugeFaceSize
            }

            W.MapLibreGaugeBackplate {
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                z: -1
                visible: root.mapLibreNativeActive
                theme: appTheme
                primaryColor: appTheme.speedColor(root.displaySpeedValue)
                auxColor: root.displayCoolantValue >= 100 ? appTheme.danger : (root.displayCoolantValue < 40 ? "#63C9FF" : appTheme.pearlLow)
                primaryProgress: Math.max(0, Math.min(1, root.displaySpeedValue / 140))
                auxProgress: Math.max(0.14, Math.min(1, (root.displayCoolantValue - 40) / 70))
                maxValue: 140
                minorStep: 10
                majorStep: 20
                labelStep: 20
                labelStart: 20
                labelDivisor: 1
                auxStartLabel: "H"
                auxEndLabel: "C"
            }

            W.SpeedGauge {
                id: speedGauge
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                theme: appTheme
                vehicleState: hub
                maxSpeed: 140
                speed: displaySpeedValue
                coolantC: displayCoolantValue
                effectLevel: root.effectLevel
                stressScene: root.stressScene
                stressPhase: root.stressPhase
                matrixRainEnabled: root.gaugeMatrixRainEnabled
                matrixRainSharedPhase: root.gaugeMatrixRainSharedPhase
            }

            W.GaugeChevronOrbit {
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                anchors.centerIn: parent
                z: 240
                visible: !root.effectsOff
                active: root.displayLeftIndicator
                side: "left"
                simplified: root.lowEffectMode
                chevrons: root.lowEffectMode ? 4 : 7
                cycleMs: root.indicatorCascadeCycleMs
                phaseOverride: root.indicatorCascadePhase
                orbitRadius: width * 0.315
                chevronSize: root.lowEffectMode ? width * 0.038 : width * 0.044
                strokeWidth: root.lowEffectMode ? 4.8 : 5.2
                strokeBoost: 1.8
                tailSpacingPhase: root.lowEffectMode ? 0.12 : 0.08
                onColor: "#52FFE1"
            }
        }

        Item {
            id: rightGaugeShell
            width: root.gaugeShellSize
            height: root.gaugeShellSize
            z: 220
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: root.gaugeEdgeBleed

            Rectangle {
                anchors.centerIn: parent
                width: root.gaugeFaceSize + 18
                height: width
                radius: width / 2
                visible: root.mapLibreSafeCompositor
                color: "#010309"
            }

            W.GaugeLensShell {
                anchors.fill: parent
                visible: !root.lowEffectMode
                theme: appTheme
                effectLevel: root.effectLevel
                gaugeColor: appTheme.rpmColor(root.displayRpmValue)
                chromeColor: appTheme.pearlLow
                podSize: root.gaugePodSize
                faceSize: root.gaugeFaceSize
            }

            W.MapLibreGaugeBackplate {
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                z: -1
                visible: root.mapLibreNativeActive
                theme: appTheme
                primaryColor: appTheme.rpmColor(root.displayRpmValue)
                auxColor: root.displayFuelValue <= 12 ? appTheme.danger : appTheme.pearlLow
                primaryProgress: Math.max(0, Math.min(1, root.displayRpmValue / 8000))
                auxProgress: Math.max(0, Math.min(1, root.displayFuelValue / 100))
                maxValue: 8
                minorStep: 0.5
                majorStep: 1
                labelStep: 1
                labelStart: 1
                labelDivisor: 1
                auxStartLabel: "F"
                auxEndLabel: "E"
            }

            W.TachGauge {
                id: tachGauge
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                theme: appTheme
                vehicleState: hub
                rpm: displayRpmValue
                fuelPct: displayFuelValue
                effectLevel: root.effectLevel
                stressScene: root.stressScene
                stressPhase: root.stressPhase
                matrixRainEnabled: root.gaugeMatrixRainEnabled
                matrixRainSharedPhase: root.gaugeMatrixRainSharedPhase
            }

            W.GaugeChevronOrbit {
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                anchors.centerIn: parent
                z: 240
                visible: !root.effectsOff
                active: root.displayRightIndicator
                side: "right"
                simplified: root.lowEffectMode
                chevrons: root.lowEffectMode ? 4 : 7
                cycleMs: root.indicatorCascadeCycleMs
                phaseOverride: root.indicatorCascadePhase
                orbitRadius: width * 0.315
                chevronSize: root.lowEffectMode ? width * 0.038 : width * 0.044
                strokeWidth: root.lowEffectMode ? 4.8 : 5.2
                strokeBoost: 1.8
                tailSpacingPhase: root.lowEffectMode ? 0.12 : 0.08
                onColor: "#52FFE1"
            }
        }

        Item {
            id: mapUiLayer
            anchors.fill: parent
            z: 3000

            Rectangle {
                id: idlePrompt
                // Keep the live map clear; destination search now lives in the maps sheet.
                visible: false
                width: Math.floor(parent.width / 3) - 72
                height: 56
                radius: 18
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 18
                color: "#09141BE8"
                border.width: 1
                border.color: "#35698A"

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: parent.width
                        height: parent.height
                        radius: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#102230"
                        border.width: 1
                        border.color: "#4F7FA0"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Where to?"
                                color: "#F7FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 21
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 140
                                text: "Search"
                                color: "#8ED6FF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openMapMenu()
                        }
                    }
                }
            }

            Rectangle {
                id: tripRail
                visible: false
                width: Math.floor(parent.width / 3)
                height: 0
                radius: 24
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                color: "#08121AE6"
                border.width: 1
                border.color: followUnlocked ? "#86D5FF" : "#2A5F8F"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 10
                        visible: root.hasActiveRoute

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 30
                            radius: 11
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#2A5F8F"

                            Text {
                                anchors.centerIn: parent
                                text: "ETA " + (navigation.eta || "--")
                                color: "#F2FAFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                        }

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 30
                            radius: 11
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#2A5F8F"

                            Text {
                                anchors.centerIn: parent
                                text: root.formatDistanceMeters(navigation.remainingDistanceMeters)
                                    + " • "
                                    + root.formatDurationSeconds(navigation.remainingDurationSeconds)
                                color: "#F2FAFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: "#102230"
                            border.width: 1
                            border.color: "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: "SEARCH"
                                color: "#F4FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.openMapMenu()
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: "#114261"
                            border.width: 1
                            border.color: "#84D8FF"

                            Text {
                                anchors.centerIn: parent
                                text: followUnlocked ? "RECENTER" : "FOLLOW"
                                color: "#F5FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    navigation.recenter()
                                    navField.setFollowEnabled(true)
                                    root.navControlsOpen = false
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: navigation.muted ? "#4D2A2A" : "#102230"
                            border.width: 1
                            border.color: navigation.muted ? "#D79A9A" : "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: navigation.muted ? "UNMUTE" : "MUTE"
                                color: "#F5FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: navigation.setMuted(!navigation.muted)
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: root.navControlsOpen ? "#17394D" : "#102230"
                            border.width: 1
                            border.color: root.navControlsOpen ? "#86D5FF" : "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: "MORE"
                                color: "#F4FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.navControlsOpen = !root.navControlsOpen
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.navControlsOpen || root.mapMenuOpen
                color: root.navControlsOpen ? "#6201060C" : "transparent"

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.navControlsOpen = false
                        if (root.mapMenuOpen) {
                            root.mapMenuOpen = false
                            root.searchKeyboardOpen = false
                        }
                    }
                }
            }

            Rectangle {
                id: navControlsSheet
                visible: root.navControlsOpen
                width: Math.floor(parent.width / 3)
                height: Math.min(parent.height - 78, navControlsColumn.implicitHeight + 36)
                radius: 26
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: tripRail.top
                anchors.bottomMargin: 12
                color: "#0A121BEA"
                border.width: 1
                border.color: "#35698A"

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: navControlsColumn
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Row {
                        width: parent.width

                        Text {
                            text: "Navigation"
                            color: "#F5FBFF"
                            font.family: appTheme.fontDisplay
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }

                        Item { width: Math.max(0, parent.width - 170); height: 1 }

                        Rectangle {
                            width: 42
                            height: 42
                            radius: 14
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#456A7D"

                            W.OemIcon {
                                anchors.centerIn: parent
                                width: 22
                                height: 22
                                icon: "close"
                                color: "#EAF5FB"
                                accentColor: "#EAF5FB"
                                strokeWidth: 3.8
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.navControlsOpen = false
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 64
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: "#23465A"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "Provider"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: String(navigation.providerStatus || "unknown").toUpperCase().replace("_", " ")
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 64
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: "#23465A"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "Hotspot"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: hotspotState === "online"
                                    ? "ONLINE"
                                    : (hotspotState === "no_internet"
                                        ? "NO INTERNET"
                                        : (hotspotState === "associated_no_ip"
                                            ? "WAITING IP"
                                            : (hotspotState === "no_config" ? "SETUP NEEDED" : "JOINING")))
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        visible: navigation.bbbLinkOk || gpsEverValid || hub.gpsAccuracyM > 0 || hub.gpsSatellites > 0
                        width: parent.width
                        height: visible ? 82 : 0
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: gpsFixOk ? "#2E8B67" : "#8A5D35"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "BBB GPS"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: gpsFixOk
                                    ? ("FIX  " + Math.max(0, hub.gpsSatellites) + " SAT")
                                    : (navigation.bbbLinkOk ? "NO FIX" : "WAITING")
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                visible: hub.gpsAccuracyM > 0 || gpsEverValid
                                text: hub.gpsAccuracyM > 0
                                    ? ("±" + Math.round(hub.gpsAccuracyM) + " m")
                                    : (gpsEverValid ? "Holding last known BBB pose" : "Waiting for first valid fix")
                                color: "#8FB4C8"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                            }

                            Text {
                                text: "SRC " + gpsSourceText
                                color: gpsSourceText === "HARDWARE" ? "#89F1B8" : "#8FB4C8"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 18
                        color: "#0B1720"
                        border.width: 1
                        border.color: hotspotState === "online" ? "#3B5665" : "#456A7D"
                        visible: hotspotState !== "online"

                        Text {
                            anchors.centerIn: parent
                            text: "SET UP WI-FI"
                            color: "#F5FBFF"
                            font.family: appTheme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (typeof wifiSetup !== "undefined")
                                    wifiSetup.showPrompt()
                                root.navControlsOpen = false
                            }
                        }
                    }
                }
            }

            Item {
                id: mapMenu
                visible: root.mapMenuOpen
                anchors.fill: parent

                Rectangle {
                    width: Math.floor(Math.min(760, Math.max(640, parent.width * 0.42)))
                    height: Math.min(parent.height - 56, mapMenuColumn.implicitHeight + 40)
                    radius: 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#0A121B"
                    border.width: 1
                    border.color: "#5FAAD2"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 3
                        color: "#58D9FF"
                        opacity: 0.72
                    }

                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: mapMenuColumn
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 9

                        Row {
                            width: parent.width
                            height: 52
                            spacing: 12

                            Column {
                                width: Math.max(0, parent.width - 64)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: "Maps"
                                    color: "#F5FBFF"
                                    font.family: appTheme.fontDisplay
                                    font.pixelSize: 28
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: root.gpsBadgeText() + "   " + root.hotspotBadgeText()
                                    color: "#8FC6DF"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 48
                                height: 48
                                radius: 12
                                color: closeMouse.pressed ? "#19364B" : "#0C1A25"
                                border.width: 1
                                border.color: closeMouse.containsMouse ? "#86D5FF" : "#42657A"

                                W.OemIcon {
                                    anchors.centerIn: parent
                                    width: 24
                                    height: 24
                                    icon: "close"
                                    color: "#EAF5FB"
                                    accentColor: "#EAF5FB"
                                    strokeWidth: 4.0
                                }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        root.mapMenuOpen = false
                                        root.searchKeyboardOpen = false
                                    }
                                }
                            }
                        }

                        Row {
                            id: mapMenuTabs
                            width: parent.width
                            height: 42
                            spacing: 10
                            readonly property bool routeTabVisible: root.mapMenuStage === "routing"
                                || root.awaitingRoutePreview
                                || root.routeLookupInProgress
                                || root.availableRouteOptions().length > 0
                                || root.hasActiveRoute
                            readonly property int tabCount: routeTabVisible ? 3 : 2
                            readonly property real tabWidth: (width - spacing * (tabCount - 1)) / tabCount

                            Rectangle {
                                width: mapMenuTabs.tabWidth
                                height: parent.height
                                radius: 13
                                color: root.mapMenuStage === "search" ? "#143B52" : "#0B1720"
                                border.width: 1
                                border.color: root.mapMenuStage === "search" ? "#86D5FF" : "#345468"

                                Text {
                                    anchors.centerIn: parent
                                    text: "FIND"
                                    color: root.mapMenuStage === "search" ? "#F7FBFF" : "#A8C8D8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    font.hintingPreference: root.menuTextHintingPreference
                                    renderType: root.menuTextRenderType
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.chooseMapMenuTab("search")
                                }
                            }

                            Rectangle {
                                id: routeTab
                                visible: mapMenuTabs.routeTabVisible
                                width: mapMenuTabs.tabWidth
                                height: parent.height
                                radius: 13
                                color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? "#143B52" : "#0B1720"
                                border.width: 1
                                border.color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? "#86D5FF" : "#345468"

                                Text {
                                    anchors.centerIn: parent
                                    text: "ROUTE"
                                    color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? "#F7FBFF" : "#A8C8D8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    font.hintingPreference: root.menuTextHintingPreference
                                    renderType: root.menuTextRenderType
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.chooseMapMenuTab("routes")
                                }
                            }

                            Rectangle {
                                width: mapMenuTabs.tabWidth
                                height: parent.height
                                radius: 13
                                color: root.mapMenuStage === "settings" ? "#143B52" : "#0B1720"
                                border.width: 1
                                border.color: root.mapMenuStage === "settings" ? "#86D5FF" : "#345468"

                                Text {
                                    anchors.centerIn: parent
                                    text: "SETTINGS"
                                    color: root.mapMenuStage === "settings" ? "#F7FBFF" : "#A8C8D8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    font.hintingPreference: root.menuTextHintingPreference
                                    renderType: root.menuTextRenderType
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.chooseMapMenuTab("settings")
                                }
                            }
                        }

                        Rectangle {
                            visible: root.mapMenuStage === "search"
                            width: parent.width
                            height: 70
                            radius: 16
                            color: searchInput.activeFocus ? "#111E2A" : "#071019"
                            border.width: 1
                            border.color: searchInput.activeFocus ? "#82C9F2" : "#2E5975"

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12

                                Rectangle {
                                    width: 46
                                    height: 46
                                    radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: "#102A3A"
                                    border.width: 1
                                    border.color: "#35698A"

                                    W.OemIcon {
                                        anchors.centerIn: parent
                                        width: 31
                                        height: 31
                                        icon: "route"
                                        color: "#F7FBFF"
                                        accentColor: "#8DE8FF"
                                        strokeWidth: 3.2
                                    }
                                }

                                Item {
                                    width: parent.width - 58
                                    height: parent.height

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        text: "DESTINATION"
                                        color: "#6FA8C2"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.1
                                    }

                                    TextInput {
                                        id: searchInput
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 40
                                        verticalAlignment: Text.AlignVCenter
                                        color: "transparent"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 24
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextInputRenderType
                                        selectByMouse: true
                                        clip: true
                                        cursorVisible: false
                                        selectionColor: "transparent"
                                        selectedTextColor: "transparent"
                                        focus: root.mapMenuOpen && root.searchKeyboardOpen
                                        onAccepted: routeButton.trigger()
                                        onTextChanged: {
                                            if (root.mapMenuStage === "search")
                                                suggestionDebounce.restart()
                                        }
                                        onActiveFocusChanged: {
                                            if (activeFocus && root.mapMenuStage === "search")
                                                suggestionDebounce.restart()
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 40
                                        verticalAlignment: Text.AlignVCenter
                                        text: searchInput.text
                                        visible: searchInput.text.length > 0
                                        textFormat: Text.PlainText
                                        color: "#F7FBFF"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 24
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: 40
                                        verticalAlignment: Text.AlignVCenter
                                        text: "Search destination"
                                        visible: searchInput.text.length === 0 && !searchInput.activeFocus
                                        color: "#7092A7"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 22
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.mapMenuStage = "search"
                                    root.searchKeyboardOpen = true
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }

                        Row {
                            visible: root.mapMenuStage === "search"
                            width: parent.width
                            height: 42
                            spacing: 10

                            Rectangle {
                                width: (parent.width - 10) / 2
                                height: parent.height
                                radius: 13
                                color: "#091722"
                                border.width: 1
                                border.color: root.gpsFixOk ? "#2D8F69" : "#806130"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 9

                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.gpsFixOk ? "#7EF0B0" : "#FFCC5C"
                                    }

                                    Text {
                                        width: parent.width - 19
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.gpsBadgeText()
                                        color: "#EAF5FB"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.0
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Rectangle {
                                width: (parent.width - 10) / 2
                                height: parent.height
                                radius: 13
                                color: "#091722"
                                border.width: 1
                                border.color: root.hotspotState === "online" ? "#2D8F69" : "#456A7D"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 9

                                    Rectangle {
                                        width: 10
                                        height: 10
                                        radius: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root.hotspotState === "online" ? "#7EF0B0" : "#9BC9DF"
                                    }

                                    Text {
                                        width: parent.width - 19
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.hotspotBadgeText()
                                        color: "#EAF5FB"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.0
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Timer {
                            id: suggestionDebounce
                            interval: 250
                            repeat: false
                            onTriggered: root.fetchSearchSuggestions(searchInput.text)
                        }

                        Rectangle {
                            width: parent.width
                            height: root.mapMenuStage === "routes"
                                ? 244
                                : (root.mapMenuStage === "routing"
                                    ? 126
                                    : (root.mapMenuStage === "settings"
                                        ? 372
                                        : (root.searchKeyboardOpen ? 110 : 218)))
                            radius: 16
                            color: "#0A151F"
                            border.width: 1
                            border.color: "#2A5A74"

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: root.mapMenuStage === "routes"
                                        ? "Route ready"
                                        : (root.mapMenuStage === "routing"
                                            ? "Building route"
                                            : (root.mapMenuStage === "settings"
                                                ? "Map settings"
                                                : (searchInput.text.length < 2
                                                    ? (navigation.recents.length > 0 ? "Recent destinations" : "Tap the field to search")
                                                    : (root.menuResultsModel().length > 0 ? "Results" : "No matches"))))
                                    color: (root.routeLookupInProgress || root.mapMenuStage === "routing") ? "#9FE7FF" : "#9FBFD2"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 14
                                    font.hintingPreference: root.menuTextHintingPreference
                                    renderType: root.menuTextRenderType
                                }

                                Item {
                                    id: searchResultsSurface
                                    visible: root.mapMenuStage === "search"
                                    width: parent.width
                                    height: parent.height - 30
                                    readonly property var results: root.menuResultsModel()
                                    readonly property int maxVisibleResults: root.searchKeyboardOpen ? 1 : 3

                                    Column {
                                        id: searchResultsColumn
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        spacing: 8

                                        Repeater {
                                            model: Math.min(searchResultsSurface.results.length,
                                                searchResultsSurface.maxVisibleResults)

                                            delegate: Rectangle {
                                                readonly property var itemData: searchResultsSurface.results[index]
                                                width: searchResultsColumn.width
                                                height: 64
                                                radius: 12
                                                antialiasing: false
                                                color: suggestionMouse.containsMouse ? "#143346" : "#0F1B26"
                                                border.width: 1
                                                border.color: suggestionMouse.containsMouse ? "#86D5FF" : "#24455A"

                                                Column {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: 4

                                                    Text {
                                                        width: parent.width
                                                        text: String(itemData.primary || itemData.label || "")
                                                        textFormat: Text.PlainText
                                                        color: "#F5FBFF"
                                                        font.family: appTheme.fontDisplay
                                                        font.pixelSize: 17
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        text: String(itemData.secondary
                                                            || (isFinite(Number(itemData.distanceMeters))
                                                                ? root.formatDistanceMeters(itemData.distanceMeters)
                                                                : ""))
                                                        textFormat: Text.PlainText
                                                        color: "#8FB4C8"
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: 11
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                        elide: Text.ElideRight
                                                        visible: text.length > 0
                                                    }
                                                }

                                                MouseArea {
                                                    id: suggestionMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onClicked: root.chooseSearchResult(itemData)
                                                }
                                            }
                                        }
                                    }
                                }

                                Column {
                                    visible: root.mapMenuStage === "settings"
                                    width: parent.width
                                    spacing: 10

                                    Row {
                                        width: parent.width
                                        height: 86
                                        spacing: 10

                                        Rectangle {
                                            width: (parent.width - 10) / 2
                                            height: parent.height
                                            radius: 14
                                            color: navigation.muted ? "#21151B" : "#0F202C"
                                            border.width: 1
                                            border.color: navigation.muted ? "#A35D74" : "#2F6A84"

                                            Column {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                Text {
                                                    width: parent.width
                                                    text: "VOICE"
                                                    color: "#7FAFC5"
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.0
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: navigation.muted ? "Muted" : "Prompts on"
                                                    color: "#F5FBFF"
                                                    font.family: appTheme.fontDisplay
                                                    font.pixelSize: 22
                                                    font.weight: Font.DemiBold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: navigation.setMuted(!navigation.muted)
                                            }
                                        }

                                        Rectangle {
                                            width: (parent.width - 10) / 2
                                            height: parent.height
                                            radius: 14
                                            color: followUnlocked ? "#171D2A" : "#0F202C"
                                            border.width: 1
                                            border.color: followUnlocked ? "#7389FF" : "#2F6A84"

                                            Column {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                Text {
                                                    width: parent.width
                                                    text: "CAMERA"
                                                    color: "#7FAFC5"
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.0
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: followUnlocked ? "Free pan" : "Following"
                                                    color: "#F5FBFF"
                                                    font.family: appTheme.fontDisplay
                                                    font.pixelSize: 22
                                                    font.weight: Font.DemiBold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    navigation.recenter()
                                                    navField.setFollowEnabled(true)
                                                }
                                            }
                                        }
                                    }

                                    Row {
                                        width: parent.width
                                        height: 86
                                        spacing: 10

                                        Rectangle {
                                            width: (parent.width - 10) / 2
                                            height: parent.height
                                            radius: 14
                                            color: "#0F202C"
                                            border.width: 1
                                            border.color: root.gpsFixOk ? "#2D8F69" : "#806130"

                                            Column {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                Text {
                                                    width: parent.width
                                                    text: "GPS"
                                                    color: "#7FAFC5"
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.0
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: root.gpsBadgeText()
                                                    color: "#F5FBFF"
                                                    font.family: appTheme.fontDisplay
                                                    font.pixelSize: 22
                                                    font.weight: Font.DemiBold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: (parent.width - 10) / 2
                                            height: parent.height
                                            radius: 14
                                            color: "#0F202C"
                                            border.width: 1
                                            border.color: root.hotspotState === "online" ? "#2D8F69" : "#456A7D"

                                            Column {
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 6

                                                Text {
                                                    width: parent.width
                                                    text: "NETWORK"
                                                    color: "#7FAFC5"
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 1.0
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: root.hotspotBadgeText()
                                                    color: "#F5FBFF"
                                                    font.family: appTheme.fontDisplay
                                                    font.pixelSize: 22
                                                    font.weight: Font.DemiBold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            width: parent.width
                                            text: "MAP STYLE"
                                            color: "#7FAFC5"
                                            font.family: appTheme.fontMono
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                            font.letterSpacing: 1.0
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                        }

                                        Row {
                                            width: parent.width
                                            height: 76
                                            spacing: 8

                                            Repeater {
                                                model: root.mapThemeOptions

                                                delegate: Rectangle {
                                                    readonly property bool selected: String(modelData.id) === String(root.activeMapThemeOption.id)
                                                    width: (parent.width - 24) / 4
                                                    height: parent.height
                                                    radius: 12
                                                    color: selected ? "#143B52" : "#0F202C"
                                                    border.width: 1
                                                    border.color: selected ? "#86D5FF" : "#2F6A84"

                                                    Column {
                                                        anchors.fill: parent
                                                        anchors.margins: 9
                                                        spacing: 5

                                                        Rectangle {
                                                            width: parent.width
                                                            height: 16
                                                            radius: 4
                                                            color: modelData.swatchA
                                                            border.width: 1
                                                            border.color: selected ? "#F7FBFF" : "#355B70"

                                                            Rectangle {
                                                                width: parent.width * 0.44
                                                                height: parent.height
                                                                anchors.right: parent.right
                                                                radius: 4
                                                                color: modelData.swatchB
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: modelData.label
                                                            color: "#F5FBFF"
                                                            font.family: appTheme.fontDisplay
                                                            font.pixelSize: 18
                                                            font.weight: Font.DemiBold
                                                            font.hintingPreference: root.menuTextHintingPreference
                                                            renderType: root.menuTextRenderType
                                                            horizontalAlignment: Text.AlignHCenter
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: modelData.detail
                                                            color: selected ? "#9FE7FF" : "#7FAFC5"
                                                            font.family: appTheme.fontMono
                                                            font.pixelSize: 10
                                                            font.weight: Font.Bold
                                                            font.hintingPreference: root.menuTextHintingPreference
                                                            renderType: root.menuTextRenderType
                                                            horizontalAlignment: Text.AlignHCenter
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        onClicked: root.selectMapTheme(modelData.id)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Column {
                                    visible: root.mapMenuStage === "routing"
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        width: parent.width
                                        text: String(root.pendingDestination.primary || searchInput.text || "Destination")
                                        color: "#F5FBFF"
                                        font.family: appTheme.fontDisplay
                                        font.pixelSize: 24
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: String(root.pendingDestination.secondary || navBanner.primary || "Checking live route options")
                                        color: "#9FBFD2"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 12
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 46
                                        radius: 12
                                        color: "#0E1D29"
                                        border.width: 1
                                        border.color: "#24455A"

                                        Text {
                                            anchors.centerIn: parent
                                            text: navBanner.secondary
                                                ? String(navBanner.secondary)
                                                : "Building live guidance from your current GPS position"
                                            color: "#D9E9F5"
                                            font.family: appTheme.fontMono
                                            font.pixelSize: 12
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                            width: parent.width - 20
                                        }
                                    }
                                }

                                Column {
                                    visible: root.mapMenuStage === "routes"
                                    width: parent.width
                                    spacing: 10

                                    Column {
                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            text: String((navigation.activeRoute.destination && navigation.activeRoute.destination.primary)
                                                || root.pendingDestination.primary
                                                || searchInput.text
                                                || "Destination")
                                            color: "#F5FBFF"
                                            font.family: appTheme.fontDisplay
                                            font.pixelSize: 24
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: String((navigation.activeRoute.destination && navigation.activeRoute.destination.secondary)
                                                || root.pendingDestination.secondary
                                                || "")
                                            color: "#8FB4C8"
                                            font.family: appTheme.fontMono
                                            font.pixelSize: 11
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                            elide: Text.ElideRight
                                            visible: text.length > 0
                                        }
                                    }

                                    Row {
                                        id: routeOptionRow
                                        width: parent.width
                                        spacing: 8
                                        readonly property var routeOptions: root.availableRouteOptions()
                                        readonly property int routeCount: Math.max(1, routeOptions.length)

                                        Repeater {
                                            model: routeOptionRow.routeOptions

                                            delegate: Rectangle {
                                                readonly property var routeOption: modelData
                                                readonly property bool selected: Number(routeOption.index) === root.selectedRouteIndex
                                                width: (routeOptionRow.width - routeOptionRow.spacing * (routeOptionRow.routeCount - 1)) / routeOptionRow.routeCount
                                                height: 102
                                                radius: 14
                                                antialiasing: false
                                                color: selected ? "#1B4C68" : "#10202C"
                                                border.width: 1
                                                border.color: selected ? "#8CE4FF" : "#2B4F64"

                                                Column {
                                                    anchors.fill: parent
                                                    anchors.margins: 10
                                                    spacing: 4

                                                    Text {
                                                        text: String(routeOption.label || "")
                                                        color: selected ? "#F7FBFF" : "#A2CFE3"
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                    }

                                                    Text {
                                                        text: root.formatDurationSeconds(routeOption.durationSeconds)
                                                        color: "#F5FBFF"
                                                        font.family: appTheme.fontDisplay
                                                        font.pixelSize: 24
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                    }

                                                    Text {
                                                        text: root.formatDistanceMeters(routeOption.distanceMeters)
                                                        color: "#9ED0E7"
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: 12
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                    }

                                                    Text {
                                                        text: Number(routeOption.index) === 0
                                                            ? "BEST"
                                                            : root.formatRouteDelta(routeOption.deltaSeconds)
                                                        color: selected ? "#BFF1FF" : "#7EA6BD"
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                    }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: root.selectRoutePreview(routeOption.index)
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 58
                                        radius: 12
                                        color: "#0E1D29"
                                        border.width: 1
                                        border.color: "#24455A"

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 8
                                            anchors.bottomMargin: 8
                                            spacing: 2

                                            Text {
                                                width: parent.width
                                                text: navigation.nextManeuver.instruction
                                                    ? String(navigation.nextManeuver.instruction)
                                                    : "Route preview ready"
                                                color: "#F5FBFF"
                                                font.family: appTheme.fontDisplay
                                                font.pixelSize: 18
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: root.formatDistanceMeters(navigation.remainingDistanceMeters)
                                                    + "  •  "
                                                    + root.formatDurationSeconds(navigation.remainingDurationSeconds)
                                                    + "  •  ETA "
                                                    + (navigation.eta || "--")
                                                color: "#8FB4C8"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 11
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: root.searchKeyboardOpen
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: root.keyboardRows

                                delegate: Row {
                                    property var keyRow: modelData
                                    spacing: 8
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Repeater {
                                        model: keyRow

                                        delegate: Rectangle {
                                            readonly property string keyValue: modelData
                                            width: keyValue === "SPACE" ? 220 : (keyValue === "BACKSPACE" || keyValue === "CLEAR" ? 100 : 50)
                                            height: 34
                                            radius: 11
                                            color: keyMouse.pressed ? "#2A7FAF" : "#0F2230"
                                            border.width: 1
                                            border.color: keyMouse.pressed ? "#B2EBFF" : "#35627F"

                                            Text {
                                                anchors.centerIn: parent
                                                text: keyValue === "BACKSPACE" ? "BKSP" : keyValue
                                                color: "#F4FBFF"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 15
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 1
                                            }

                                            MouseArea {
                                                id: keyMouse
                                                anchors.fill: parent
                                                onClicked: {
                                                    root.mapMenuStage = "search"
                                                    root.applyKeyboardKey(parent.keyValue, searchInput)
                                                    searchInput.forceActiveFocus()
                                                    suggestionDebounce.restart()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 10
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                id: routeButton
                                width: 154
                                height: 50
                                radius: 15
                                readonly property bool blocked: root.mapMenuStage === "routing"
                                    || (root.mapMenuStage === "routes"
                                        && root.availableRouteOptions().length <= 0
                                        && !root.hasActiveRoute)
                                enabled: !blocked
                                opacity: enabled ? 1.0 : 0.72
                                color: blocked ? "#102635" : (root.mapMenuStage === "routes" ? "#1A7E62" : "#1F6A97")
                                border.width: 1
                                border.color: blocked ? "#345A70" : (root.mapMenuStage === "routes" ? "#8DF0D0" : "#82C9F2")

                                function trigger() {
                                    if (root.mapMenuStage === "settings") {
                                        root.mapMenuOpen = false
                                        root.searchKeyboardOpen = false
                                        return
                                    }
                                    if (root.mapMenuStage === "routes") {
                                        root.startSelectedRoute()
                                        return
                                    }
                                    if (root.mapMenuStage === "routing")
                                        return
                                    if (root.mapMenuStage === "search" && !root.routeLookupInProgress)
                                        root.routeSearchQuery(searchInput.text)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.mapMenuStage === "routes"
                                        ? "START"
                                        : (root.mapMenuStage === "settings"
                                            ? "DONE"
                                            : ((root.mapMenuStage === "routing" || root.routeLookupInProgress) ? "LOADING" : "FIND"))
                                    color: "#F7FBFF"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: routeButton.enabled
                                    onClicked: routeButton.trigger()
                                }
                            }

                            Rectangle {
                                width: 132
                                height: 50
                                radius: 15
                                color: root.mapMenuStage === "search" ? "#114261" : "#0B1720"
                                border.width: 1
                                border.color: root.mapMenuStage === "search" ? "#84D8FF" : "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.mapMenuStage === "settings"
                                        ? (root.followUnlocked ? "RECENTER" : "FOLLOW")
                                        : (root.mapMenuStage === "search"
                                            ? (root.followUnlocked ? "RECENTER" : "FOLLOW")
                                            : "BACK")
                                    color: "#F5FBFF"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: (root.mapMenuStage === "search" || root.mapMenuStage === "settings") && root.followUnlocked ? 14 : 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.mapMenuStage === "search" || root.mapMenuStage === "settings") {
                                            navigation.recenter()
                                            navField.setFollowEnabled(true)
                                            if (root.mapMenuStage === "search") {
                                                root.mapMenuOpen = false
                                                root.searchKeyboardOpen = false
                                            }
                                        } else {
                                            root.backToRouteSearch()
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: 112
                                height: 50
                                radius: 15
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.mapMenuStage === "settings"
                                        ? (navigation.muted ? "UNMUTE" : "MUTE")
                                        : (root.mapMenuStage === "search"
                                            ? (root.searchKeyboardOpen ? "HIDE" : "KEYS")
                                            : "CENTER")
                                    color: "#E6F1F8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (root.mapMenuStage === "settings")
                                            navigation.setMuted(!navigation.muted)
                                        else if (root.mapMenuStage === "search")
                                            root.searchKeyboardOpen = !root.searchKeyboardOpen
                                        else
                                            navigation.recenter()
                                    }
                                }
                            }

                            Rectangle {
                                width: 112
                                height: 50
                                radius: 15
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: "CLEAR"
                                    color: "#E6F1F8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.4
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.clearMapSearch()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    W.WiFiSetupOverlay {
        id: wifiOverlay
        anchors.fill: parent
        wifi: (typeof wifiSetup !== "undefined") ? wifiSetup : null
        theme: appTheme
    }
}
