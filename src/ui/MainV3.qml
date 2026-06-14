import QtQuick 2.15
import QtQuick.Window 2.15
import Qt.labs.settings
import BeagleY 1.0

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
        property string mapTheme: "light"
        property bool mapThemeUserSelected: false
        property string themeMode: "auto"
        property string cachedSunriseIso: ""
        property string cachedSunsetIso: ""
        property int cachedSunUtcOffsetSeconds: 36000
        property string cachedSunDate: ""
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
    function boolEnvValue(value) {
        const v = String(value || "").trim().toLowerCase()
        return v === "1" || v === "true" || v === "yes" || v === "on"
    }
    function gaugeDetailValue(value) {
        const v = String(value || "").trim().toLowerCase()
        if (v === "rich" || v === "full" || v === "high")
            return "rich"
        return "safe"
    }
    function simulationTriangle(phaseSeconds, periodSeconds) {
        const period = Math.max(0.001, Number(periodSeconds) || 1.0)
        const phase = ((Number(phaseSeconds) || 0) % period + period) % period
        const unit = phase / period
        return unit < 0.5 ? unit * 2.0 : (1.0 - unit) * 2.0
    }
    readonly property string gaugeDetail: gaugeDetailValue(
        (typeof BEAGLEY_GAUGE_DETAIL !== "undefined" && BEAGLEY_GAUGE_DETAIL)
            ? String(BEAGLEY_GAUGE_DETAIL)
            : "safe"
    )
    readonly property bool gaugeRichDetail: gaugeDetail === "rich"
    readonly property bool gaugeDemo: (typeof BEAGLEY_GAUGE_DEMO !== "undefined")
        ? boolEnvValue(BEAGLEY_GAUGE_DEMO)
        : false
    readonly property bool clusterSimulation: (typeof BEAGLEY_CLUSTER_SIMULATION !== "undefined")
        ? boolEnvValue(BEAGLEY_CLUSTER_SIMULATION)
        : false
    readonly property string gaugeEffectLevel: effectLevel
    readonly property bool gaugeLowEffectMode: gaugeEffectLevel === "low" || gaugeEffectLevel === "off"
    readonly property bool gaugeEffectsOff: gaugeEffectLevel === "off"
    readonly property bool gaugeMatrixRainEnabled: gaugeEffectLevel === "high" && !clusterSimulation
    readonly property int gaugeIndicatorCascadeCycleMs: gaugeLowEffectMode ? 2300 : 2100
    readonly property string mapRenderer: (typeof BEAGLEY_MAP_RENDERER !== "undefined" && BEAGLEY_MAP_RENDERER)
        ? String(BEAGLEY_MAP_RENDERER)
        : "native"
    readonly property string appMapLibreTrustedStyles: "https://tiles.openfreemap.org/styles/positron https://tiles.openfreemap.org/styles/liberty https://tiles.openfreemap.org/styles/dark https://tiles.openfreemap.org/styles/bright https://demotiles.maplibre.org/style.json"
    readonly property string defaultMapLibreNativeTrustedStyles: appMapLibreTrustedStyles
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
    readonly property bool mapLibreNativeStyleOverrideActive: mapLibreNativeStyleOverride.length > 0
        && !clusterUiSettings.mapThemeUserSelected
    readonly property bool mapLibreNativeStyleTrusted: mapLibreStyleTrusted(activeMapStyleUrl)
    readonly property string effectiveMapRenderer: mapLibreNativeRequested
        && (!activeMapThemeUsesMapLibre || !mapLibreNativeStyleTrusted)
        ? "native-online"
        : mapRenderer
    readonly property bool mapLibreNativeActive: effectiveMapRenderer === "maplibre-native"
    readonly property bool mapLibreNativeFullUnderlay: (typeof BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY !== "undefined")
        && BEAGLEY_MAPLIBRE_NATIVE_FULL_UNDERLAY
    readonly property bool mapLibreSafeCompositor: mapLibreNativeActive && !mapLibreNativeFullUnderlay
    readonly property real gaugeFaceBackgroundOpacity: 1.0
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
    property real clusterSimulationPhase: 0.0
    property real clusterSimulationDiscretePhase: 0.0

    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale
    readonly property bool truthOk: linkOk && !hub.bbbStale
    readonly property bool hotspotConnected: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.connected)
    readonly property bool hotspotIpLease: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.hasIpLease)
    readonly property bool internetOk: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.internetReachable)
    readonly property string hotspotState: (typeof wifiSetup !== "undefined") && wifiSetup ? String(wifiSetup.networkState || "waiting_for_hotspot") : "waiting_for_hotspot"
    readonly property string hotspotSsid: (typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.currentSsid ? String(wifiSetup.currentSsid) : ""
    readonly property bool gpsFixOk: !!(hub && hub.gpsFixValid)
    readonly property bool gpsEverValid: !!(hub && hub.gpsEverValid)
    readonly property bool liveMapPoseValid: !!(hub
        && hub.vehicleStateSeen
        && hub.gpsPoseValid
        && hub.gpsFixValid
        && !hub.linkStale
        && isFinite(Number(hub.gpsLat))
        && isFinite(Number(hub.gpsLng)))
    readonly property bool weakGpsPoseValid: !!(hub
        && hub.vehicleStateSeen
        && hub.gpsPoseValid
        && !hub.gpsFixValid
        && !hub.linkStale
        && Number(hub.gpsSatellites) >= 4
        && Number(hub.gpsAccuracyM) > 0
        && Number(hub.gpsAccuracyM) <= 80
        && isFinite(Number(hub.gpsLat))
        && isFinite(Number(hub.gpsLng)))
    readonly property bool gpsSignalSeen: !!(hub
        && hub.vehicleStateSeen
        && !hub.linkStale
        && (Number(hub.gpsSatellites) > 0 || Number(hub.gpsAccuracyM) > 0))
    readonly property string gpsSourceText: hub && hub.gpsSource ? String(hub.gpsSource).toUpperCase() : "UNKNOWN"
    readonly property var navConnectivity: navigation ? (navigation.mapConnectivity || ({})) : ({})
    readonly property var navVehiclePose: navigation ? (navigation.mapVehiclePose || ({})) : ({})
    readonly property bool navVehiclePoseFinite: isFinite(Number(navVehiclePose.lat))
        && isFinite(Number(navVehiclePose.lng))
    readonly property bool retainedGpsPoseValid: !!(navConnectivity.gpsUsingLastKnown && navVehiclePoseFinite)
    readonly property bool weatherPoseValid: liveMapPoseValid || weakGpsPoseValid || retainedGpsPoseValid || navVehiclePoseFinite
    readonly property real weatherPoseLat: (liveMapPoseValid || weakGpsPoseValid)
        ? Number(hub.gpsLat)
        : (navVehiclePoseFinite ? Number(navVehiclePose.lat) : NaN)
    readonly property real weatherPoseLng: (liveMapPoseValid || weakGpsPoseValid)
        ? Number(hub.gpsLng)
        : (navVehiclePoseFinite ? Number(navVehiclePose.lng) : NaN)
    readonly property bool mapVehicleMarkerVisible: mapLibreNativeActive
        && (liveMapPoseValid || weakGpsPoseValid || retainedGpsPoseValid)
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
    readonly property bool gaugeReviewMode: gaugeDemo && !stressScene && !clusterSimulation
    readonly property real gaugeAuxStartDeg: 87
    readonly property real gaugeAuxSweepDeg: 126
    readonly property real displaySpeedValue: clusterSimulation
        ? simulationTriangle(clusterSimulationPhase, 8.0) * 140
        : (stressScene
        ? (78 + 50 * Math.sin(stressPhase * 0.9))
        : (gaugeReviewMode ? 118 : speedValue))
    readonly property real displayRpmValue: clusterSimulation
        ? simulationTriangle(clusterSimulationPhase + 1.0, 7.2) * 8000
        : (stressScene
        ? (2400 + 1800 * (0.5 + 0.5 * Math.sin(stressPhase * 1.15 + 0.4)))
        : (gaugeReviewMode ? 4200 : rpmValue))
    readonly property real displayFuelValue: clusterSimulation
        ? (100 - simulationTriangle(clusterSimulationPhase + 2.0, 9.5) * 100)
        : (stressScene
        ? (18 + 11 * Math.sin(stressPhase * 0.30 - 1.2))
        : (gaugeReviewMode ? 14 : fuelValue))
    readonly property real displayCoolantValue: clusterSimulation
        ? (40 + simulationTriangle(clusterSimulationPhase + 3.0, 10.5) * 70)
        : (stressScene
        ? (70 + 42 * Math.sin(stressPhase * 0.42 + 1.3))
        : (gaugeReviewMode ? 104 : coolantValue))
    readonly property var simulationGearSequence: ["P", "R", "N", "D", "2", "1", "L"]
    readonly property string displayGearValue: clusterSimulation
        ? simulationGearSequence[Math.floor(clusterSimulationDiscretePhase / 1.25) % simulationGearSequence.length]
        : (gaugeReviewMode ? "D" : gearText)
    readonly property bool displayOverdriveValue: clusterSimulation
        ? (Math.floor(clusterSimulationDiscretePhase / 4.0) % 3) === 1
        : (gaugeReviewMode ? false : truthOk && !!(hub && hub.overdrive))
    readonly property bool displayHighBeamValue: clusterSimulation
        ? (Math.floor(clusterSimulationDiscretePhase / 1.4) % 2) === 0
        : (gaugeReviewMode ? true : !!(hub && hub.highBeam))
    readonly property int simulationDriveStep: Math.floor(clusterSimulationDiscretePhase / 2.2) % 3
    readonly property int simulationWarningStep: Math.floor(clusterSimulationDiscretePhase / 1.15) % 10
    readonly property bool displayWarnDoorValue: clusterSimulation
        ? (simulationWarningStep === 4 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnDoor))
    readonly property bool displayWarnChargeValue: clusterSimulation
        ? (simulationWarningStep === 3 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnCharge))
    readonly property bool displayWarnBrakeValue: clusterSimulation
        ? (simulationWarningStep === 1 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnBrake))
    readonly property bool displayWarnOilValue: clusterSimulation
        ? (simulationWarningStep === 2 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnOil))
    readonly property bool displayWarnCheckEngineValue: clusterSimulation
        ? (simulationWarningStep === 5 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnCheckEngine))
    readonly property bool displayWarnATValue: clusterSimulation
        ? (simulationWarningStep === 6 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnAT))
    readonly property bool displayWarnFuelLowValue: clusterSimulation
        ? (simulationWarningStep === 7 || simulationWarningStep === 8)
        : (gaugeReviewMode ? true : truthOk && !!(hub && hub.warnFuelLow))
    readonly property string displayDrivetrainModeValue: clusterSimulation
        ? (simulationDriveStep === 0 ? "2wd" : "4wd")
        : (gaugeReviewMode ? "4wd" : ((hub && hub.drivetrainMode) ? String(hub.drivetrainMode).toLowerCase() : "2wd"))
    readonly property bool displayTransferLockValue: clusterSimulation
        ? simulationDriveStep === 2
        : (gaugeReviewMode ? false : truthOk && !!(hub && hub.transferLock))
    readonly property string displayDriveModeText: clusterSimulation
        ? (simulationDriveStep === 0 ? "2WD" : (simulationDriveStep === 1 ? "4WD" : "LOCK"))
        : (gaugeReviewMode ? "4WD" : ((hub && hub.drivetrainMode) ? String(hub.drivetrainMode).toUpperCase() : "2WD"))
    readonly property string displayOdometerText: clusterSimulation
        ? formatOdometerKm(284613 + Math.floor(clusterSimulationDiscretePhase * 12))
        : "------"
    function formatOdometerKm(value) {
        const text = String(Math.max(0, Math.round(Number(value) || 0)))
        let out = ""
        let count = 0
        for (let i = text.length - 1; i >= 0; --i) {
            out = text.charAt(i) + out
            ++count
            if (i > 0 && count % 3 === 0)
                out = " " + out
        }
        return out
    }
    function formatSpeedValue(value) {
        return String(Math.max(0, Math.round(Number(value) || 0)))
    }
    function formatRpmValue(value) {
        return (Math.max(0, Math.round((Number(value) || 0) / 100)) / 10).toFixed(1)
    }
    function normGear(value) {
        if (value === undefined || value === null)
            return ""
        return String(value).trim().toUpperCase()
    }
    function gearColorFor(value) {
        const gear = normGear(value)
        if (gear === "R")
            return appTheme.danger
        if (gear === "P" || gear === "N" || gear === "D" || gear === "2" || gear === "1" || gear === "L")
            return appTheme.pearlLow
        return appTheme.text
    }
    function gaugeAngleDeg(index, count) {
        return 225 + 210 * (Number(index) / Number(count))
    }
    function gaugePointX(width, angleDeg, radius) {
        return width * 0.5 + Math.cos((angleDeg - 90) * Math.PI / 180) * radius
    }
    function gaugePointY(height, angleDeg, radius) {
        return height * 0.5 + Math.sin((angleDeg - 90) * Math.PI / 180) * radius
    }
    readonly property int indicatorVisualHoldMs: root.gaugeIndicatorCascadeCycleMs + 250
    readonly property int simulationIndicatorStep: Math.floor(clusterSimulationDiscretePhase / 1.8) % 4
    readonly property bool rawLeftIndicator: clusterSimulation
        ? (simulationIndicatorStep === 0 || simulationIndicatorStep === 2)
        : (stressScene
        ? Math.sin(stressPhase * 1.35) > 0.68
        : truthOk && !!hub.leftIndicator)
    readonly property bool rawRightIndicator: clusterSimulation
        ? (simulationIndicatorStep === 1 || simulationIndicatorStep === 2)
        : (stressScene
        ? Math.sin(stressPhase * 1.12 + 2.4) > 0.68
        : truthOk && !!hub.rightIndicator)
    property bool displayLeftIndicator: false
    property bool displayRightIndicator: false
    readonly property bool indicatorCascadeActive: displayLeftIndicator || displayRightIndicator
    readonly property int indicatorCascadeCycleMs: gaugeIndicatorCascadeCycleMs
    property real indicatorCascadePhase: 0.0
    readonly property real displayMapLat: stressMapMotionEnabled
        ? (root.defaultMapLat + 0.0028 * Math.sin(stressPhase * 0.12))
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsLat)
        : (isFinite(Number(navVehiclePose.lat))
        ? Number(navVehiclePose.lat)
        : root.defaultMapLat))
        : (liveMapPoseValid
        ? Number(hub.gpsLat)
        : (cluster && isFinite(Number(cluster.mapLat))
        ? Number(cluster.mapLat)
        : (isFinite(Number(navVehiclePose.lat))
        ? Number(navVehiclePose.lat)
        : root.defaultMapLat))))
    readonly property real displayMapLng: stressMapMotionEnabled
        ? (root.defaultMapLng + 0.0046 * Math.cos(stressPhase * 0.12))
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsLng)
        : (isFinite(Number(navVehiclePose.lng))
        ? Number(navVehiclePose.lng)
        : root.defaultMapLng))
        : (liveMapPoseValid
        ? Number(hub.gpsLng)
        : (cluster && isFinite(Number(cluster.mapLng))
        ? Number(cluster.mapLng)
        : (isFinite(Number(navVehiclePose.lng))
        ? Number(navVehiclePose.lng)
        : root.defaultMapLng))))
    readonly property real displayMapBearing: stressMapMotionEnabled
        ? ((stressPhase * 26) % 360)
        : (embeddedDirectMapCamera
        ? (liveMapPoseValid
        ? Number(hub.gpsBearing)
        : (isFinite(Number(navVehiclePose.bearing))
        ? Number(navVehiclePose.bearing)
        : (isFinite(Number(hub && hub.gpsBearing)) ? Number(hub.gpsBearing) : 0)))
        : (liveMapPoseValid
        ? Number(hub.gpsBearing)
        : (cluster && isFinite(Number(cluster.mapBearing))
        ? Number(cluster.mapBearing)
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
    readonly property var displayMapVehiclePose: (liveMapPoseValid || weakGpsPoseValid)
        ? ({
            lat: Number(hub.gpsLat),
            lng: Number(hub.gpsLng),
            bearing: isFinite(Number(hub.gpsBearing)) ? Number(hub.gpsBearing) : 0,
            speedKph: displayMapSpeed,
            gpsReady: liveMapPoseValid,
            gpsFixValid: !!hub.gpsFixValid,
            gpsSource: hub.gpsSource || "",
            accuracyM: Number(hub.gpsAccuracyM) || 0,
            satellites: Number(hub.gpsSatellites) || 0,
            headingReliable: !!hub.gpsHeadingReliable,
            usingLastKnown: false
        })
        : navVehiclePose
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
    property bool mapMenuSystemMode: false
    property bool navControlsOpen: false
    property bool searchKeyboardOpen: false
    property string mapMenuStage: "search"
    readonly property var nowPlayingService: (typeof nowPlaying !== "undefined") ? nowPlaying : null
    readonly property bool musicAvailable: !!(nowPlayingService && nowPlayingService.available)
    readonly property bool musicPlaying: !!(nowPlayingService && nowPlayingService.playing)
    readonly property string musicTitle: nowPlayingService && nowPlayingService.title
        ? String(nowPlayingService.title)
        : ""
    readonly property string musicArtist: nowPlayingService && nowPlayingService.artist
        ? String(nowPlayingService.artist)
        : ""
    readonly property string musicStatus: nowPlayingService && nowPlayingService.status
        ? String(nowPlayingService.status)
        : "OFFLINE"
    readonly property string musicDetail: nowPlayingService && nowPlayingService.statusDetail
        ? String(nowPlayingService.statusDetail)
        : "Spotify not connected"
    readonly property bool spotifyPairingSupported: !!(nowPlayingService && nowPlayingService.spotifyPairingSupported)
    readonly property bool spotifyPairingActive: !!(nowPlayingService && nowPlayingService.spotifyPairingActive)
    readonly property bool spotifySaveSupported: !!(nowPlayingService && nowPlayingService.spotifySaveSupported)
    readonly property bool spotifySavePending: !!(nowPlayingService && nowPlayingService.spotifySavePending)
    readonly property string spotifySaveStatus: nowPlayingService && nowPlayingService.spotifySaveStatus
        ? String(nowPlayingService.spotifySaveStatus)
        : ""
    readonly property string spotifySaveDetail: nowPlayingService && nowPlayingService.spotifySaveDetail
        ? String(nowPlayingService.spotifySaveDetail)
        : ""
    readonly property bool spotifyRepairRequired: spotifySaveStatus.toUpperCase() === "REPAIR"
    property real autoThemeSunriseMs: NaN
    property real autoThemeSunsetMs: NaN
    property bool autoThemeRequestActive: false
    property int autoThemeClockTick: 0
    property real autoThemeLastRequestLat: NaN
    property real autoThemeLastRequestLng: NaN
    property string autoThemeStatus: "SYNC"
    readonly property string normalizedThemeMode: normalizedChromeThemeMode(clusterUiSettings.themeMode)
    readonly property string resolvedChromeTheme: resolveChromeTheme(normalizedThemeMode,
        autoThemeClockTick,
        autoThemeSunriseMs,
        autoThemeSunsetMs)
    readonly property bool menuDarkChrome: resolvedChromeTheme === "dark"
    readonly property color menuAccentColor: "#1A73E8"
    readonly property color menuPanelColor: menuDarkChrome ? "#101821" : "#F8FAFF"
    readonly property color menuSurfaceColor: menuDarkChrome ? "#111D2B" : "#FFFFFF"
    readonly property color menuSurfaceAltColor: menuDarkChrome ? "#182637" : "#F8FAFF"
    readonly property color menuSurfaceSelectedColor: menuDarkChrome ? "#1E3A5F" : "#E8F0FE"
    readonly property color menuBorderColor: menuDarkChrome ? "#33465C" : "#DADCE0"
    readonly property color menuStrongBorderColor: menuDarkChrome ? "#4B6F95" : "#D8E2EE"
    readonly property color menuTextPrimaryColor: menuDarkChrome ? "#F8FAFC" : "#202124"
    readonly property color menuTextSecondaryColor: menuDarkChrome ? "#A9B8C7" : "#5F6368"
    readonly property color menuTextMutedColor: menuDarkChrome ? "#7D8EA3" : "#80868B"
    readonly property color menuDangerSurfaceColor: menuDarkChrome ? "#3A1822" : "#FFF1F3"
    readonly property color menuDangerBorderColor: menuDarkChrome ? "#87465A" : "#F4A8B8"
    readonly property var chromeThemeOptions: [
        { id: "auto", label: "Auto", detail: "Sunrise" },
        { id: "light", label: "Light", detail: "Day" },
        { id: "dark", label: "Dark", detail: "Night" }
    ]
    readonly property string initialMapMenuStage: (typeof BEAGLEY_INITIAL_MAP_MENU_STAGE !== "undefined"
        && BEAGLEY_INITIAL_MAP_MENU_STAGE)
        ? String(BEAGLEY_INITIAL_MAP_MENU_STAGE).trim().toLowerCase()
        : ""
    readonly property string initialMapSearchQuery: (typeof BEAGLEY_INITIAL_MAP_SEARCH_QUERY !== "undefined"
        && BEAGLEY_INITIAL_MAP_SEARCH_QUERY)
        ? String(BEAGLEY_INITIAL_MAP_SEARCH_QUERY).trim()
        : ""
    readonly property bool initialMapSearchKeyboard: (typeof BEAGLEY_INITIAL_MAP_SEARCH_KEYBOARD !== "undefined")
        ? boolEnvValue(BEAGLEY_INITIAL_MAP_SEARCH_KEYBOARD)
        : false
    property int searchResultOffset: 0
    property var pendingDestination: ({})
    property int selectedRouteIndex: 0
    property bool awaitingRoutePreview: false
    property bool departureCameraCloseInActive: false
    readonly property var effectiveMapCameraHints: buildEffectiveMapCameraHints()
    readonly property var mapThemeOptions: [
        {
            id: "light",
            label: "Minimal",
            detail: "Vector",
            tileUrlTemplate: "https://a.basemaps.cartocdn.com/rastertiles/light_all/{z}/{x}/{y}.png",
            styleUrl: "https://tiles.openfreemap.org/styles/positron",
            mapLibre: true,
            maxZoom: 19,
            swatchA: "#F7F8F3",
            swatchB: "#ADBFD1"
        },
        {
            id: "street",
            label: "Street",
            detail: "Vector",
            tileUrlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            styleUrl: "https://tiles.openfreemap.org/styles/liberty",
            mapLibre: true,
            maxZoom: 19,
            swatchA: "#F2EFE9",
            swatchB: "#91B3C5"
        },
        {
            id: "dark",
            label: "Dark",
            detail: "Vector night",
            tileUrlTemplate: "https://a.basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png",
            styleUrl: "https://tiles.openfreemap.org/styles/dark",
            mapLibre: true,
            maxZoom: 19,
            swatchA: "#172132",
            swatchB: "#406179"
        },
        {
            id: "terrain",
            label: "Terrain",
            detail: "Raster topo",
            tileUrlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
            styleUrl: "",
            mapLibre: false,
            maxZoom: 17,
            swatchA: "#C4D6A0",
            swatchB: "#8A7A55"
        }
    ]
    readonly property var activeMapThemeOption: mapThemeOption(clusterUiSettings.mapTheme)
    readonly property string activeMapTileUrlTemplate: String(activeMapThemeOption.tileUrlTemplate || "")
    readonly property bool activeMapThemeUsesMapLibre: activeMapThemeOption.mapLibre !== false
        && String(activeMapThemeOption.styleUrl || "").length > 0
    readonly property string activeMapStyleUrl: mapLibreNativeStyleOverrideActive
        ? mapLibreNativeStyleOverride
        : (activeMapThemeUsesMapLibre ? String(activeMapThemeOption.styleUrl || "") : "")
    readonly property real activeMapMaxZoom: mapLibreNativeRequested && activeMapThemeUsesMapLibre
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
        const raw = String(themeId || "light")
        const wanted = raw === "roads" || raw === "drive" ? "street" : raw
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
        clusterUiSettings.mapThemeUserSelected = true
    }

    function normalizedChromeThemeMode(value) {
        const mode = String(value || "auto").trim().toLowerCase()
        if (mode === "light" || mode === "dark")
            return mode
        return "auto"
    }

    function selectChromeThemeMode(mode) {
        clusterUiSettings.themeMode = root.normalizedChromeThemeMode(mode)
        root.autoThemeClockTick += 1
        if (clusterUiSettings.themeMode === "auto")
            root.requestAutoThemeSunTimes(false)
    }

    function resolveChromeTheme(mode, tick, sunriseMs, sunsetMs) {
        const normalized = root.normalizedChromeThemeMode(mode)
        if (normalized === "light" || normalized === "dark")
            return normalized

        // Reference tick keeps the binding fresh without forcing continuous work.
        const ignoredTick = tick
        if (ignoredTick < -1)
            return "light"

        const sunrise = Number(sunriseMs)
        const sunset = Number(sunsetMs)
        const now = Date.now()
        if (isFinite(sunrise) && isFinite(sunset) && sunset > sunrise)
            return (now < sunrise || now >= sunset) ? "dark" : "light"

        const fallbackHour = (new Date()).getHours()
        return (fallbackHour < 6 || fallbackHour >= 18) ? "dark" : "light"
    }

    function pad2(value) {
        const n = Math.max(0, Math.floor(Number(value) || 0))
        return n < 10 ? "0" + n : String(n)
    }

    function localDateKey(offsetSeconds) {
        const offset = isFinite(Number(offsetSeconds)) ? Number(offsetSeconds) : 0
        const local = new Date(Date.now() + offset * 1000)
        return local.getUTCFullYear()
            + "-" + root.pad2(local.getUTCMonth() + 1)
            + "-" + root.pad2(local.getUTCDate())
    }

    function parseOpenMeteoLocalIso(isoText, offsetSeconds) {
        const text = String(isoText || "")
        const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?/.exec(text)
        if (!match)
            return NaN

        const offset = isFinite(Number(offsetSeconds)) ? Number(offsetSeconds) : 0
        const utcMs = Date.UTC(Number(match[1]),
            Number(match[2]) - 1,
            Number(match[3]),
            Number(match[4]),
            Number(match[5]),
            match[6] ? Number(match[6]) : 0)
        return utcMs - offset * 1000
    }

    function formatSunTime(isoText) {
        const match = /T(\d{2}):(\d{2})/.exec(String(isoText || ""))
        if (!match)
            return "--:--"
        return match[1] + ":" + match[2]
    }

    function cachedSunTimesValid() {
        return isFinite(Number(root.autoThemeSunriseMs))
            && isFinite(Number(root.autoThemeSunsetMs))
            && Number(root.autoThemeSunsetMs) > Number(root.autoThemeSunriseMs)
    }

    function restoreCachedSunTimes() {
        const offset = Number(clusterUiSettings.cachedSunUtcOffsetSeconds)
        const sunrise = root.parseOpenMeteoLocalIso(clusterUiSettings.cachedSunriseIso, offset)
        const sunset = root.parseOpenMeteoLocalIso(clusterUiSettings.cachedSunsetIso, offset)
        if (isFinite(sunrise) && isFinite(sunset) && sunset > sunrise) {
            root.autoThemeSunriseMs = sunrise
            root.autoThemeSunsetMs = sunset
            root.autoThemeStatus = "CACHED"
        }
    }

    function autoThemeDetailText() {
        if (clusterUiSettings.cachedSunriseIso.length > 0
                && clusterUiSettings.cachedSunsetIso.length > 0) {
            return root.formatSunTime(clusterUiSettings.cachedSunriseIso)
                + " / "
                + root.formatSunTime(clusterUiSettings.cachedSunsetIso)
        }
        if (root.autoThemeStatus === "SYNC")
            return "Syncing"
        return "By daylight"
    }

    function themeOptionDetail(optionId, fallbackDetail) {
        const id = String(optionId || "")
        if (id === "auto")
            return root.autoThemeDetailText()
        return String(fallbackDetail || "")
    }

    function autoThemeUrl(latValue, lngValue) {
        return "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + Number(latValue).toFixed(5)
            + "&longitude=" + Number(lngValue).toFixed(5)
            + "&daily=sunrise,sunset"
            + "&timezone=auto"
            + "&forecast_days=1"
            + "&beagley=" + Math.floor(Date.now() / (6 * 60 * 60 * 1000))
    }

    function applyAutoThemePayload(payload) {
        const daily = payload && payload.daily ? payload.daily : ({})
        const sunriseList = daily.sunrise || []
        const sunsetList = daily.sunset || []
        const sunriseIso = sunriseList.length > 0 ? String(sunriseList[0] || "") : ""
        const sunsetIso = sunsetList.length > 0 ? String(sunsetList[0] || "") : ""
        const offset = isFinite(Number(payload && payload.utc_offset_seconds))
            ? Number(payload.utc_offset_seconds)
            : Number(clusterUiSettings.cachedSunUtcOffsetSeconds)
        const sunrise = root.parseOpenMeteoLocalIso(sunriseIso, offset)
        const sunset = root.parseOpenMeteoLocalIso(sunsetIso, offset)
        if (!isFinite(sunrise) || !isFinite(sunset) || sunset <= sunrise)
            return false

        root.autoThemeSunriseMs = sunrise
        root.autoThemeSunsetMs = sunset
        clusterUiSettings.cachedSunriseIso = sunriseIso
        clusterUiSettings.cachedSunsetIso = sunsetIso
        clusterUiSettings.cachedSunUtcOffsetSeconds = Math.round(offset)
        clusterUiSettings.cachedSunDate = root.localDateKey(offset)
        root.autoThemeStatus = "LIVE"
        root.autoThemeClockTick += 1
        return true
    }

    function requestAutoThemeSunTimes(force) {
        if (root.autoThemeRequestActive)
            return

        const lat = Number(root.displayMapLat)
        const lng = Number(root.displayMapLng)
        if (!isFinite(lat) || !isFinite(lng))
            return

        const offset = Number(clusterUiSettings.cachedSunUtcOffsetSeconds)
        const today = root.localDateKey(offset)
        const moved = !isFinite(root.autoThemeLastRequestLat)
            || Math.abs(lat - root.autoThemeLastRequestLat) > 0.08
            || Math.abs(lng - root.autoThemeLastRequestLng) > 0.08
        if (!force
                && root.cachedSunTimesValid()
                && clusterUiSettings.cachedSunDate === today
                && !moved)
            return

        root.autoThemeRequestActive = true
        root.autoThemeStatus = "SYNC"

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            root.autoThemeRequestActive = false
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const payload = JSON.parse(xhr.responseText)
                    if (root.applyAutoThemePayload(payload)) {
                        root.autoThemeLastRequestLat = lat
                        root.autoThemeLastRequestLng = lng
                        return
                    }
                } catch (err) {
                    console.warn("[MainV3] auto theme sunrise parse failed:", err)
                }
            }
            root.autoThemeStatus = root.cachedSunTimesValid() ? "CACHED" : "OFFLINE"
        }
        xhr.open("GET", root.autoThemeUrl(lat, lng), true)
        xhr.send()
    }

    function mapLibreStyleTrustedByList(styleUrl, trustedList) {
        const url = String(styleUrl || "").trim().toLowerCase()
        if (url.length <= 0)
            return false

        const trusted = String(trustedList || "").split(/[\s,]+/)
        for (var i = 0; i < trusted.length; ++i) {
            const candidate = String(trusted[i] || "").trim().toLowerCase()
            if (candidate.length > 0 && candidate === url)
                return true
        }
        return false
    }

    function mapLibreThemeStyleTrusted(styleUrl) {
        const url = String(styleUrl || "").trim().toLowerCase()
        if (url.length <= 0)
            return false
        for (var i = 0; i < root.mapThemeOptions.length; ++i) {
            const option = root.mapThemeOptions[i]
            const candidate = String(option.styleUrl || "").trim().toLowerCase()
            if (option.mapLibre !== false && candidate.length > 0 && candidate === url)
                return true
        }
        return root.mapLibreStyleTrustedByList(url, root.appMapLibreTrustedStyles)
    }

    function mapLibreStyleTrusted(styleUrl) {
        if (!root.mapLibreNativeRequested)
            return false
        if (root.mapLibreNativeAllowUntestedStyles)
            return true
        if (root.mapLibreThemeStyleTrusted(styleUrl))
            return true

        return root.mapLibreStyleTrustedByList(styleUrl, root.mapLibreNativeTrustedStyles)
    }

    function logMapLibreFallbackIfNeeded() {
        if (root.mapLibreNativeAllowUntestedStyles)
            return
        if (root.mapLibreNativeRequested && !root.activeMapThemeUsesMapLibre) {
            console.info("[MainV3] Map theme uses native raster fallback", root.activeMapThemeOption.id)
            return
        }
        if (root.mapLibreNativeRequested && root.effectiveMapRenderer !== "maplibre-native") {
            console.warn("[MainV3] MapLibre Native requested but style is not allowlisted; using native raster map",
                         root.activeMapStyleUrl)
        }
    }

    function normalizedMapMenuStage(stage) {
        const value = String(stage || "").trim().toLowerCase()
        if (value === "search" || value === "settings" || value === "spotify" || value === "routes" || value === "routing")
            return value
        return ""
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
        root.searchResultOffset = 0
        if (trimmed.length < 2) {
            navigation.search("")
            return
        }
        navigation.search(trimmed)
    }

    function openMapMenu(stage) {
        const requestedStage = root.normalizedMapMenuStage(stage)
        root.mapMenuOpen = true
        root.searchKeyboardOpen = false
        root.awaitingRoutePreview = false
        root.mapMenuSystemMode = requestedStage === "settings" || requestedStage === "spotify"
        if (hasActiveRoute && navigation.activeRoute.destination)
            pendingDestination = navigation.activeRoute.destination
        root.mapMenuStage = requestedStage.length > 0
            ? requestedStage
            : ((root.availableRouteOptions().length > 0 && hasActiveRoute) ? "routes" : "search")
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
        if (stage === "search" || stage === "routes" || stage === "routing")
            root.mapMenuSystemMode = false
        root.searchKeyboardOpen = false
        if (stage === "routes")
            root.syncSelectedRouteIndexFromNavigation()
        if (stage === "search" && searchInput && String(searchInput.text || "").trim().length >= 2)
            suggestionDebounce.restart()
    }

    function mapMenuTitleText() {
        if (root.mapMenuSystemMode)
            return "Menu"
        return "Navigation"
    }

    function mapMenuContentTitleText() {
        if (root.mapMenuStage === "routes")
            return "Route ready"
        if (root.mapMenuStage === "routing")
            return "Building route"
        if (root.mapMenuStage === "settings")
            return root.mapMenuSystemMode ? "System controls" : "Map view"
        if (root.mapMenuStage === "spotify")
            return "Spotify setup"
        return root.menuSearchTitle()
    }

    function musicAuthRequired() {
        return String(root.musicStatus).toUpperCase() === "AUTH"
    }

    function musicNowPlayingLine() {
        if (root.musicTitle.length <= 0)
            return root.musicDetail.length > 0 ? root.musicDetail : "No current track"
        if (root.musicArtist.length > 0)
            return root.musicTitle + " - " + root.musicArtist
        return root.musicTitle
    }

    function spotifySetupStatusLine() {
        if (!root.nowPlayingService)
            return "Spotify service unavailable"
        if (!root.spotifyPairingSupported)
            return "Spotify setup required"
        if (root.spotifyPairingActive && root.nowPlayingService.spotifyPairingStatus.length > 0)
            return root.nowPlayingService.spotifyPairingStatus
        if (root.spotifyRepairRequired)
            return root.spotifySaveDetail.length > 0 ? root.spotifySaveDetail : "Reconnect Spotify for liked songs"
        if (root.spotifySavePending)
            return "Updating liked songs"
        if (root.musicAuthRequired())
            return "Connect Spotify to show what is playing"
        if (root.musicAvailable)
            return root.musicPlaying ? "Now playing" : "Paused"
        return root.musicDetail.length > 0 ? root.musicDetail : "Open Spotify on your phone"
    }

    function spotifyActionLabel() {
        if (!root.spotifyPairingSupported)
            return "SETUP"
        if (root.spotifyPairingActive)
            return "CANCEL"
        if (root.musicAuthRequired())
            return "CONNECT"
        if (root.spotifyRepairRequired)
            return "REPAIR"
        return "REFRESH"
    }

    function triggerSpotifySetup() {
        if (!root.nowPlayingService)
            return
        if (!root.spotifyPairingSupported) {
            root.mapMenuStage = "spotify"
            return
        }
        if (root.spotifyPairingActive) {
            root.nowPlayingService.cancelSpotifyPairing()
            return
        }
        if (root.musicAuthRequired() || root.spotifyRepairRequired) {
            root.mapMenuStage = "spotify"
            root.nowPlayingService.beginSpotifyPairing()
            return
        }
        root.nowPlayingService.refresh()
    }

    function menuNormalizedText(value) {
        return String(value || "")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, " ")
            .trim()
    }

    function menuResultKey(item) {
        if (!item)
            return ""
        const lat = Number(item.lat)
        const lng = Number(item.lng)
        if (isFinite(lat) && isFinite(lng))
            return Math.round(lat * 100000) + "," + Math.round(lng * 100000)
        return root.menuNormalizedText(String(item.label || item.primary || ""))
    }

    function menuResultMatchesQuery(item, query) {
        const normalizedQuery = root.menuNormalizedText(query)
        if (normalizedQuery.length <= 0)
            return true
        const haystack = root.menuNormalizedText(String((item && item.primary) || "")
            + " "
            + String((item && item.label) || "")
            + " "
            + String((item && item.secondary) || ""))
        const tokens = normalizedQuery.split(/\s+/)
        for (var i = 0; i < tokens.length; ++i) {
            if (tokens[i].length > 0 && haystack.indexOf(tokens[i]) < 0)
                return false
        }
        return true
    }

    function decoratedMenuResult(item, recent) {
        var copy = {}
        for (var key in item)
            copy[key] = item[key]
        if (recent) {
            copy.recent = true
            const secondary = String(copy.secondary || "")
            copy.secondary = secondary.length > 0 ? "Recent - " + secondary : "Recent destination"
        }
        return copy
    }

    function mergedMenuResults(query) {
        const trimmed = String(query || "").trim()
        const recents = navigation && navigation.recents ? navigation.recents : []
        const liveResults = navigation && navigation.searchResults ? navigation.searchResults : []
        var merged = []
        var seen = {}

        function appendResult(item, recent) {
            if (!item)
                return
            const key = root.menuResultKey(item)
            if (key.length <= 0 || seen[key])
                return
            seen[key] = true
            merged.push(root.decoratedMenuResult(item, recent))
        }

        if (trimmed.length < 2) {
            for (var r = 0; r < recents.length; ++r)
                appendResult(recents[r], true)
            return merged
        }

        for (var resultIndex = 0; resultIndex < liveResults.length; ++resultIndex)
            appendResult(liveResults[resultIndex], false)
        for (var recentIndex = 0; recentIndex < recents.length; ++recentIndex) {
            if (root.menuResultMatchesQuery(recents[recentIndex], trimmed))
                appendResult(recents[recentIndex], true)
        }
        return merged
    }

    function menuSearchTitle() {
        const query = searchInput ? String(searchInput.text || "").trim() : ""
        if (query.length < 2)
            return navigation.recents.length > 0 ? "Previous destinations" : "Tap the field to search"
        return root.menuResultsModel().length > 0 ? "Closest and previous matches" : "No matches"
    }

    function menuResultsModel() {
        if (root.mapMenuStage !== "search")
            return []
        const query = searchInput ? String(searchInput.text || "").trim() : ""
        return root.mergedMenuResults(query)
    }

    function visibleSearchResultSlots() {
        return 3
    }

    function maxSearchResultOffset() {
        return Math.max(0, root.menuResultsModel().length - root.visibleSearchResultSlots())
    }

    function setSearchResultOffset(value) {
        root.searchResultOffset = Math.max(0, Math.min(root.maxSearchResultOffset(), value))
    }

    function resetSearchResultOffset() {
        root.searchResultOffset = 0
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

    function searchResultSubtitle(item) {
        const secondary = String((item && item.secondary) || "")
        const distance = Number(item && item.distanceMeters)
        const distanceText = isFinite(distance) && distance > 0
            ? root.formatDistanceMeters(distance)
            : ""
        if (distanceText.length > 0 && secondary.length > 0)
            return distanceText + " - " + secondary
        return secondary.length > 0 ? secondary : distanceText
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

    function mapMenuSubtitleText() {
        if (root.mapMenuSystemMode) {
            if (root.mapMenuStage === "spotify")
                return "Scan the code to connect now playing"
            return "System controls and connections"
        }
        const displayMode = root.normalizedThemeMode === "auto"
            ? ("Auto " + (root.menuDarkChrome ? "dark" : "light"))
            : (root.menuDarkChrome ? "Dark" : "Light")
        return displayMode + " display / " + String(root.activeMapThemeOption.label || "Minimal") + " map"
    }

    Component.onCompleted: {
        if (!clusterUiSettings.mapThemeUserSelected && String(clusterUiSettings.mapTheme || "") !== "light")
            clusterUiSettings.mapTheme = "light"
        clusterUiSettings.themeMode = root.normalizedChromeThemeMode(clusterUiSettings.themeMode)
        root.restoreCachedSunTimes()
        root.requestAutoThemeSunTimes(true)
        root.showNormal()
        root.raise()
        root.requestActivate()
        updateLeftIndicatorVisual()
        updateRightIndicatorVisual()
        const bootStage = root.normalizedMapMenuStage(root.initialMapMenuStage)
        if (bootStage.length > 0 || root.initialMapSearchQuery.length > 0) {
            root.mapMenuStage = bootStage.length > 0 ? bootStage : "search"
            root.mapMenuSystemMode = root.mapMenuStage === "settings" || root.mapMenuStage === "spotify"
            root.mapMenuOpen = true
            root.searchKeyboardOpen = root.initialMapSearchKeyboard && root.mapMenuStage === "search"
        }
        if (root.initialMapSearchQuery.length > 0) {
            searchInput.text = root.initialMapSearchQuery
            searchInput.cursorPosition = searchInput.text.length
            root.mapMenuStage = "search"
            root.mapMenuSystemMode = false
            root.searchKeyboardOpen = root.initialMapSearchKeyboard
            Qt.callLater(function() {
                if (root.searchKeyboardOpen)
                    searchInput.forceActiveFocus()
                root.fetchSearchSuggestions(searchInput.text)
            })
        }
        Qt.callLater(logMapLibreFallbackIfNeeded)
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            root.autoThemeClockTick += 1
            root.requestAutoThemeSunTimes(false)
        }
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

        function onSearchResultsChanged() {
            root.resetSearchResultOffset()
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

    NumberAnimation on clusterSimulationPhase {
        id: clusterSimulationClock
        running: root.clusterSimulation
        loops: Animation.Infinite
        from: 0.0
        to: 3600.0
        duration: 3600000
        easing.type: Easing.Linear
    }

    Timer {
        id: clusterSimulationDiscreteClock
        interval: 200
        running: root.clusterSimulation
        repeat: true
        onTriggered: root.clusterSimulationDiscretePhase = root.clusterSimulationPhase
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
            visible: !root.mapMenuOpen
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
            mapVehiclePose: root.displayMapVehiclePose
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
            visible: root.mapVehicleMarkerVisible && !root.mapMenuOpen
            x: Math.round(parent.width * 0.5 - width * 0.5)
            y: Math.round(parent.height * (root.mapVehicleMarkerGuidanceAnchor ? 0.84 : 0.5) - height * 0.54)
            bearing: root.displayMapBearing
        }

        W.WeatherCorners {
            anchors.fill: parent
            z: 260
            theme: appTheme
            lat: root.weatherPoseLat
            lng: root.weatherPoseLng
            livePositionValid: root.weatherPoseValid
            positionLive: root.liveMapPoseValid
            positionWeak: root.weakGpsPoseValid && !root.liveMapPoseValid
            effectLevel: root.effectLevel
            stressScene: root.stressScene
            phase: root.sharedEffectPhase
            nowPlayingService: root.nowPlayingService
            expandedMode: (typeof BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE !== "undefined")
                ? String(BEAGLEY_INITIAL_WEATHER_EXPANDED_MODE)
                : ""
            active: !root.mapMenuOpen && !root.navControlsOpen

            onMapMenuRequested: function(stage) {
                root.openMapMenu(stage)
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
                z: root.mapLibreSafeCompositor ? 110 : 0
                visible: root.mapLibreSafeCompositor
                color: "#010309FE"
            }

            NativeGaugeInstrument {
                id: speedGauge
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                z: root.mapLibreSafeCompositor ? 120 : 20
                kind: "speed"
                value: root.displaySpeedValue
                maxValue: 140
                auxProgress: Math.max(0.14, Math.min(1, (root.displayCoolantValue - 40) / 70))
                primaryColor: appTheme.speedColor(root.displaySpeedValue)
                auxColor: root.displayCoolantValue >= 100 ? appTheme.danger : (root.displayCoolantValue < 40 ? "#63C9FF" : appTheme.pearlLow)
                chromeColor: appTheme.pearlLow
                lowEffectMode: root.gaugeLowEffectMode
                backgroundOpacity: root.gaugeFaceBackgroundOpacity
            }

            Item {
                anchors.fill: speedGauge
                z: root.mapLibreSafeCompositor ? 130 : 30

                Repeater {
                    model: [
                        { "label": "20", "index": 2 },
                        { "label": "40", "index": 4 },
                        { "label": "60", "index": 6 },
                        { "label": "80", "index": 8 },
                        { "label": "100", "index": 10 },
                        { "label": "120", "index": 12 },
                        { "label": "140", "index": 14 }
                    ]

                    delegate: Text {
                        readonly property real labelAngle: root.gaugeAngleDeg(modelData.index, 14)
                        x: root.gaugePointX(parent.width, labelAngle, parent.width * 0.322) - width / 2
                        y: root.gaugePointY(parent.height, labelAngle, parent.height * 0.322) - height / 2
                        text: modelData.label
                        color: appTheme.pearlLow
                        opacity: 0.84
                        font.family: "Oxanium"
                        font.pixelSize: parent.width * 0.0275
                        font.bold: true
                        renderType: root.menuTextRenderType
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Item {
                    id: odBadge
                    z: 62
                    visible: root.displayOverdriveValue
                    anchors.horizontalCenter: speedValueText.horizontalCenter
                    anchors.bottom: speedValueText.top
                    anchors.bottomMargin: parent.height * 0.046
                    width: parent.width * 0.222
                    height: parent.height * 0.078

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "#140A22"
                        border.width: Math.max(1, parent.width * 0.012)
                        border.color: appTheme.amber
                        opacity: 0.94
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"
                        border.width: parent.height * 0.23
                        border.color: Qt.rgba(appTheme.amber.r, appTheme.amber.g, appTheme.amber.b, 0.17)
                    }

                    Rectangle {
                        x: parent.width * 0.06
                        y: parent.height * 0.17
                        width: parent.width * 0.88
                        height: parent.height * 0.66
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: "#12FFFFFF"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "O/D"
                        color: appTheme.amber
                        font.family: "Oxanium"
                        font.pixelSize: parent.height * 0.60
                        font.bold: true
                        font.letterSpacing: 4
                        renderType: root.menuTextRenderType
                    }

                    SequentialAnimation on scale {
                        running: odBadge.visible && !root.gaugeEffectsOff
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.00; to: 1.04; duration: 420; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.04; to: 1.00; duration: 420; easing.type: Easing.InOutQuad }
                        PauseAnimation { duration: 260 }
                    }
                }

                Text {
                    id: speedValueText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -parent.height * 0.030
                    text: root.formatSpeedValue(root.displaySpeedValue)
                    color: appTheme.speedColor(root.displaySpeedValue)
                    font.family: "Oxanium"
                    font.pixelSize: parent.width * 0.158
                    font.bold: true
                    renderType: root.menuTextRenderType
                    horizontalAlignment: Text.AlignHCenter
                    style: Text.Outline
                    styleColor: "#F0000000"
                }

                Item {
                    id: gearReadout
                    z: 61
                    anchors.top: speedValueText.bottom
                    anchors.topMargin: parent.height * 0.024
                    anchors.horizontalCenter: speedValueText.horizontalCenter
                    width: parent.width * 0.144
                    height: parent.height * 0.088

                    Text {
                        id: gearText
                        anchors.centerIn: parent
                        text: root.displayGearValue
                        color: root.gearColorFor(text)
                        font.family: "Oxanium"
                        font.pixelSize: parent.parent.width * 0.075
                        font.bold: true
                        font.letterSpacing: 2
                        renderType: root.menuTextRenderType
                        horizontalAlignment: Text.AlignHCenter
                        style: Text.Outline
                        styleColor: "#F0000000"

                        SequentialAnimation on opacity {
                            running: root.normGear(gearText.text) === "R"
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.20; duration: 220 }
                            NumberAnimation { from: 0.20; to: 1.0; duration: 220 }
                        }
                    }
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: gearReadout.bottom
                    anchors.topMargin: parent.height * 0.010
                    spacing: -1

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.displayOdometerText
                        color: appTheme.pearlLow
                        font.family: "Oxanium"
                        font.pixelSize: speedGauge.width * 0.030
                        font.bold: true
                        renderType: root.menuTextRenderType
                        horizontalAlignment: Text.AlignHCenter
                        style: Text.Outline
                        styleColor: "#F0000000"
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "KM"
                        color: Qt.rgba(appTheme.pearlLow.r, appTheme.pearlLow.g, appTheme.pearlLow.b, 0.62)
                        font.family: "Oxanium"
                        font.pixelSize: speedGauge.width * 0.017
                        font.bold: true
                        renderType: root.menuTextRenderType
                        horizontalAlignment: Text.AlignHCenter
                        style: Text.Outline
                        styleColor: "#D0000000"
                    }
                }

                Text {
                    width: parent.width * 0.042
                    height: parent.height * 0.034
                    x: root.gaugePointX(parent.width, root.gaugeAuxStartDeg + root.gaugeAuxSweepDeg, parent.width * 0.36 + 24) - width / 2
                    y: root.gaugePointY(parent.height, root.gaugeAuxStartDeg + root.gaugeAuxSweepDeg, parent.width * 0.36 + 24) - height / 2
                    text: "C"
                    color: appTheme.pearlLow
                    opacity: 0.86
                    font.family: "Oxanium"
                    font.pixelSize: parent.width * 0.026
                    font.bold: true
                    renderType: root.menuTextRenderType
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    width: parent.width * 0.042
                    height: parent.height * 0.034
                    x: root.gaugePointX(parent.width, root.gaugeAuxStartDeg, parent.width * 0.36 + 24) - width / 2
                    y: root.gaugePointY(parent.height, root.gaugeAuxStartDeg, parent.width * 0.36 + 24) - height / 2
                    text: "H"
                    color: appTheme.pearlLow
                    opacity: 0.86
                    font.family: "Oxanium"
                    font.pixelSize: parent.width * 0.026
                    font.bold: true
                    renderType: root.menuTextRenderType
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            W.GaugeChevronOrbit {
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                anchors.centerIn: parent
                z: 240
                visible: root.displayLeftIndicator || !root.gaugeEffectsOff
                active: root.displayLeftIndicator
                side: "left"
                simplified: root.gaugeLowEffectMode
                chevrons: 6
                cycleMs: root.indicatorCascadeCycleMs
                phaseOverride: root.indicatorCascadePhase
                orbitRadius: width * 0.315
                startAngleDeg: -90
                travelSweepDeg: 360
                chevronSize: root.gaugeLowEffectMode ? width * 0.038 : width * 0.044
                strokeWidth: root.gaugeLowEffectMode ? 4.8 : 5.2
                strokeBoost: 1.8
                tailSpacingPhase: 0.115
                gravityExponent: 1.85
                topHoldPhase: 0.08
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
                z: root.mapLibreSafeCompositor ? 110 : 0
                visible: root.mapLibreSafeCompositor
                color: "#010309FE"
            }

            NativeGaugeInstrument {
                id: tachGauge
                anchors.centerIn: parent
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                z: root.mapLibreSafeCompositor ? 120 : 20
                kind: "tach"
                value: root.displayRpmValue
                maxValue: 8000
                auxProgress: Math.max(0, Math.min(1, root.displayFuelValue / 100))
                primaryColor: appTheme.rpmColor(root.displayRpmValue)
                auxColor: root.displayFuelValue <= 12 ? appTheme.danger : appTheme.pearlLow
                chromeColor: appTheme.pearlLow
                lowEffectMode: root.gaugeLowEffectMode
                backgroundOpacity: root.gaugeFaceBackgroundOpacity
            }

            Item {
                anchors.fill: tachGauge
                z: root.mapLibreSafeCompositor ? 130 : 30

                Repeater {
                    model: [
                        { "label": "1", "index": 2 },
                        { "label": "2", "index": 4 },
                        { "label": "3", "index": 6 },
                        { "label": "4", "index": 8 },
                        { "label": "5", "index": 10 },
                        { "label": "6", "index": 12 },
                        { "label": "7", "index": 14 },
                        { "label": "8", "index": 16 }
                    ]

                    delegate: Text {
                        readonly property real labelAngle: root.gaugeAngleDeg(modelData.index, 16)
                        x: root.gaugePointX(parent.width, labelAngle, parent.width * 0.322) - width / 2
                        y: root.gaugePointY(parent.height, labelAngle, parent.height * 0.322) - height / 2
                        text: modelData.label
                        color: appTheme.pearlLow
                        opacity: 0.84
                        font.family: "Oxanium"
                        font.pixelSize: parent.width * 0.0275
                        font.bold: true
                        renderType: root.menuTextRenderType
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                W.VehicleInfoCenter {
                    id: vicCenter
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.50
                    height: width
                    z: 150
                    theme: appTheme
                    simplified: root.gaugeLowEffectMode
                    pulseEnabled: !root.gaugeLowEffectMode
                    warnDoor: root.displayWarnDoorValue
                    warnCharge: root.displayWarnChargeValue
                    warnBrake: root.displayWarnBrakeValue
                    warnOil: root.displayWarnOilValue
                    warnCheckEngine: root.displayWarnCheckEngineValue
                    warnAT: root.displayWarnATValue
                    warnFuelLow: root.displayWarnFuelLowValue
                    drivetrainMode: root.displayDrivetrainModeValue
                    transferLock: root.displayTransferLockValue
                }

                W.HighBeamHalo {
                    anchors.centerIn: vicCenter
                    z: 140
                    vicDiameter: vicCenter.width
                    ringThickness: 16
                    gapPx: 3
                    heartbeat: true
                    active: root.displayHighBeamValue
                }

                Text {
                    width: parent.width * 0.042
                    height: parent.height * 0.034
                    x: root.gaugePointX(parent.width, root.gaugeAuxStartDeg + root.gaugeAuxSweepDeg, parent.width * 0.36 + 24) - width / 2
                    y: root.gaugePointY(parent.height, root.gaugeAuxStartDeg + root.gaugeAuxSweepDeg, parent.width * 0.36 + 24) - height / 2
                    text: "E"
                    color: appTheme.pearlLow
                    opacity: 0.86
                    font.family: "Oxanium"
                    font.pixelSize: parent.width * 0.026
                    font.bold: true
                    renderType: root.menuTextRenderType
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Text {
                    width: parent.width * 0.042
                    height: parent.height * 0.034
                    x: root.gaugePointX(parent.width, root.gaugeAuxStartDeg, parent.width * 0.36 + 24) - width / 2
                    y: root.gaugePointY(parent.height, root.gaugeAuxStartDeg, parent.width * 0.36 + 24) - height / 2
                    text: "F"
                    color: appTheme.pearlLow
                    opacity: 0.86
                    font.family: "Oxanium"
                    font.pixelSize: parent.width * 0.026
                    font.bold: true
                    renderType: root.menuTextRenderType
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            W.GaugeChevronOrbit {
                width: root.gaugeFaceSize
                height: root.gaugeFaceSize
                anchors.centerIn: parent
                z: 240
                visible: root.displayRightIndicator || !root.gaugeEffectsOff
                active: root.displayRightIndicator
                side: "right"
                simplified: root.gaugeLowEffectMode
                chevrons: 6
                cycleMs: root.indicatorCascadeCycleMs
                phaseOverride: root.indicatorCascadePhase
                orbitRadius: width * 0.315
                startAngleDeg: -90
                travelSweepDeg: 360
                chevronSize: root.gaugeLowEffectMode ? width * 0.038 : width * 0.044
                strokeWidth: root.gaugeLowEffectMode ? 4.8 : 5.2
                strokeBoost: 1.8
                tailSpacingPhase: 0.115
                gravityExponent: 1.85
                topHoldPhase: 0.08
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
                color: root.navControlsOpen
                    ? "#6201060C"
                    : (root.mapMenuOpen
                        ? (root.menuDarkChrome ? "#40000000" : "#33F8FAFF")
                        : "transparent")

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
                                    ? (hotspotSsid.length > 0 ? hotspotSsid : "ONLINE")
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
                                    : (root.weakGpsPoseValid
                                    ? ("POS  " + Math.max(0, hub.gpsSatellites) + " SAT")
                                    : (root.gpsSignalSeen
                                    ? ("ACQ  " + Math.max(0, hub.gpsSatellites) + " SAT")
                                    : (navigation.bbbLinkOk ? "NO FIX" : "WAITING")))
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                visible: hub.gpsAccuracyM > 0 || gpsEverValid || root.gpsSignalSeen
                                text: hub.gpsAccuracyM > 0
                                    ? ("±" + Math.round(hub.gpsAccuracyM) + " m")
                                    : (root.gpsSignalSeen
                                    ? "Reading satellites; waiting for coordinates"
                                    : (gpsEverValid ? "Holding last known BBB pose" : "Waiting for first valid fix"))
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
                        border.color: hotspotState === "online" ? "#2E8B67" : "#456A7D"

                        Text {
                            anchors.centerIn: parent
                            text: hotspotState === "online" ? "WI-FI DETAILS" : "SET UP WI-FI"
                            color: hotspotState === "online" ? "#8AF0B7" : "#F5FBFF"
                            font.family: appTheme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                wifiOverlay.openPrompt()
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
                z: 4000

                Rectangle {
                    width: Math.floor(Math.min(760, Math.max(640, parent.width * 0.42)))
                    height: Math.min(parent.height - 56, mapMenuColumn.implicitHeight + 40)
                    radius: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.menuPanelColor
                    border.width: 1
                    border.color: root.menuStrongBorderColor

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
                                    text: root.mapMenuTitleText()
                                    color: root.menuTextPrimaryColor
                                    font.family: appTheme.fontDisplay
                                    font.pixelSize: 28
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: root.mapMenuSubtitleText()
                                    color: root.menuTextSecondaryColor
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0.4
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: 48
                                height: 48
                                radius: 12
                                color: closeMouse.pressed ? root.menuSurfaceSelectedColor : root.menuSurfaceColor
                                border.width: 1
                                border.color: closeMouse.containsMouse ? root.menuAccentColor : root.menuBorderColor

                                Text {
                                    anchors.centerIn: parent
                                    text: "X"
                                    color: root.menuTextPrimaryColor
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 22
                                    font.weight: Font.Bold
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
                            readonly property bool systemTabs: root.mapMenuSystemMode
                            readonly property bool routeTabVisible: root.mapMenuStage === "routing"
                                || root.awaitingRoutePreview
                                || root.routeLookupInProgress
                                || root.availableRouteOptions().length > 0
                                || root.hasActiveRoute
                            readonly property int tabCount: systemTabs ? 2 : (routeTabVisible ? 3 : 2)
                            readonly property real tabWidth: (width - spacing * (tabCount - 1)) / tabCount

                            Rectangle {
                                visible: !mapMenuTabs.systemTabs
                                width: visible ? mapMenuTabs.tabWidth : 0
                                height: parent.height
                                radius: 21
                                color: root.mapMenuStage === "search" ? root.menuSurfaceSelectedColor : root.menuSurfaceColor
                                border.width: 1
                                border.color: root.mapMenuStage === "search" ? root.menuAccentColor : root.menuBorderColor

                                Text {
                                    anchors.centerIn: parent
                                    text: "Search"
                                    color: root.mapMenuStage === "search" ? root.menuAccentColor : root.menuTextSecondaryColor
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
                                visible: !mapMenuTabs.systemTabs && mapMenuTabs.routeTabVisible
                                width: visible ? mapMenuTabs.tabWidth : 0
                                height: parent.height
                                radius: 21
                                color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? root.menuSurfaceSelectedColor : root.menuSurfaceColor
                                border.width: 1
                                border.color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? root.menuAccentColor : root.menuBorderColor

                                Text {
                                    anchors.centerIn: parent
                                    text: "Route"
                                    color: (root.mapMenuStage === "routes" || root.mapMenuStage === "routing") ? root.menuAccentColor : root.menuTextSecondaryColor
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
                                radius: 21
                                color: root.mapMenuStage === "settings" ? root.menuSurfaceSelectedColor : root.menuSurfaceColor
                                border.width: 1
                                border.color: root.mapMenuStage === "settings" ? root.menuAccentColor : root.menuBorderColor

                                Text {
                                    anchors.centerIn: parent
                                    text: mapMenuTabs.systemTabs ? "Settings" : "Map View"
                                    color: root.mapMenuStage === "settings" ? root.menuAccentColor : root.menuTextSecondaryColor
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

                            Rectangle {
                                visible: mapMenuTabs.systemTabs
                                width: visible ? mapMenuTabs.tabWidth : 0
                                height: parent.height
                                radius: 21
                                color: root.mapMenuStage === "spotify" ? root.menuSurfaceSelectedColor : root.menuSurfaceColor
                                border.width: 1
                                border.color: root.mapMenuStage === "spotify" ? root.menuAccentColor : root.menuBorderColor

                                Text {
                                    anchors.centerIn: parent
                                    text: "Spotify"
                                    color: root.mapMenuStage === "spotify" ? root.menuAccentColor : root.menuTextSecondaryColor
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.0
                                    font.hintingPreference: root.menuTextHintingPreference
                                    renderType: root.menuTextRenderType
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.chooseMapMenuTab("spotify")
                                }
                            }
                        }

                        Rectangle {
                            visible: root.mapMenuStage === "search"
                            width: parent.width
                            height: 68
                            radius: 18
                            color: root.menuSurfaceColor
                            border.width: 1
                            border.color: searchInput.activeFocus ? root.menuAccentColor : root.menuBorderColor

                            MouseArea {
                                anchors.fill: parent
                                z: 0
                                onClicked: {
                                    root.mapMenuStage = "search"
                                    root.searchKeyboardOpen = true
                                    searchInput.forceActiveFocus()
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 12
                                z: 1

                                Rectangle {
                                    width: 44
                                    height: 44
                                    radius: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.menuSurfaceSelectedColor
                                    border.width: 1
                                    border.color: root.menuStrongBorderColor

                                    W.OemIcon {
                                        anchors.centerIn: parent
                                        width: 31
                                        height: 31
                                        icon: "route"
                                        color: root.menuAccentColor
                                        accentColor: "#34A853"
                                        strokeWidth: 3.2
                                    }
                                }

                                Item {
                                    width: Math.max(0, parent.width - 56 - searchKeyboardButton.width - searchFindButton.width - searchClearButton.width - parent.spacing * 4)
                                    height: parent.height

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        text: "Where to?"
                                        color: root.menuTextSecondaryColor
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
                                        color: root.menuTextPrimaryColor
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
                                        color: root.menuTextMutedColor
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 22
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                    }
                                }

                                Rectangle {
                                    id: searchKeyboardButton
                                    width: 64
                                    height: 34
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: searchKeyboardMouse.pressed ? root.menuSurfaceSelectedColor : root.menuSurfaceAltColor
                                    border.width: 1
                                    border.color: root.searchKeyboardOpen ? root.menuAccentColor : root.menuBorderColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.searchKeyboardOpen ? "HIDE" : "KEYS"
                                        color: root.searchKeyboardOpen ? root.menuAccentColor : root.menuTextSecondaryColor
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.8
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                    }

                                    MouseArea {
                                        id: searchKeyboardMouse
                                        anchors.fill: parent
                                        onClicked: {
                                            root.searchKeyboardOpen = !root.searchKeyboardOpen
                                            if (root.searchKeyboardOpen)
                                                searchInput.forceActiveFocus()
                                        }
                                    }
                                }

                                Rectangle {
                                    id: searchFindButton
                                    width: 58
                                    height: 34
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: !root.routeLookupInProgress
                                    opacity: enabled ? 1.0 : 0.54
                                    color: searchFindMouse.pressed ? "#3B8EFF" : root.menuAccentColor
                                    border.width: 1
                                    border.color: root.menuAccentColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.routeLookupInProgress ? "..." : "GO"
                                        color: "#FFFFFF"
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.0
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                    }

                                    MouseArea {
                                        id: searchFindMouse
                                        anchors.fill: parent
                                        enabled: searchFindButton.enabled
                                        onClicked: routeButton.trigger()
                                    }
                                }

                                Rectangle {
                                    id: searchClearButton
                                    width: 48
                                    height: 34
                                    radius: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    enabled: searchInput.text.length > 0
                                    opacity: enabled ? 1.0 : 0.35
                                    color: searchClearMouse.pressed ? root.menuSurfaceSelectedColor : "transparent"
                                    border.width: 1
                                    border.color: enabled ? root.menuBorderColor : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "CLR"
                                        color: searchClearButton.enabled ? root.menuTextSecondaryColor : root.menuTextMutedColor
                                        font.family: appTheme.fontMono
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.7
                                        font.hintingPreference: root.menuTextHintingPreference
                                        renderType: root.menuTextRenderType
                                    }

                                    MouseArea {
                                        id: searchClearMouse
                                        anchors.fill: parent
                                        enabled: searchClearButton.enabled
                                        onClicked: {
                                            root.clearMapSearch()
                                            searchInput.forceActiveFocus()
                                        }
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
                            id: mapMenuContentPanel
                            width: parent.width
                            height: root.mapMenuStage === "routes"
                                ? 244
                                    : (root.mapMenuStage === "routing"
                                        ? 126
                                        : (root.mapMenuStage === "settings"
                                            ? 220
                                            : (root.mapMenuStage === "spotify"
                                                ? 430
                                            : (root.searchKeyboardOpen ? 190 : 258)))
                                        )
                            radius: 22
                            color: root.menuSurfaceColor
                            border.width: 1
                            border.color: root.menuBorderColor

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: root.mapMenuContentTitleText()
                                    color: (root.routeLookupInProgress || root.mapMenuStage === "routing") ? root.menuAccentColor : root.menuTextSecondaryColor
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
                                    readonly property int rowHeight: root.searchKeyboardOpen ? 48 : 64
                                    readonly property int visibleRows: Math.min(root.visibleSearchResultSlots(),
                                        Math.max(0, results.length - root.searchResultOffset))

                                    Column {
                                        id: searchResultsColumn
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        width: parent.width - (searchResultsSurface.results.length > searchResultsSurface.visibleRows ? 16 : 0)
                                        spacing: 6

                                        Repeater {
                                            model: searchResultsSurface.visibleRows

                                            delegate: Rectangle {
                                                readonly property int resultIndex: root.searchResultOffset + index
                                                readonly property var itemData: searchResultsSurface.results[resultIndex]
                                                width: searchResultsColumn.width
                                                height: searchResultsSurface.rowHeight
                                                radius: 12
                                                antialiasing: false
                                                color: suggestionMouse.containsMouse ? root.menuSurfaceSelectedColor : root.menuSurfaceAltColor
                                                border.width: 1
                                                border.color: suggestionMouse.containsMouse ? root.menuAccentColor : root.menuBorderColor

                                                Column {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    spacing: root.searchKeyboardOpen ? 2 : 4

                                                    Text {
                                                        width: parent.width
                                                        text: String(itemData.primary || itemData.label || "")
                                                        textFormat: Text.PlainText
                                                        color: root.menuTextPrimaryColor
                                                        font.family: appTheme.fontDisplay
                                                        font.pixelSize: root.searchKeyboardOpen ? 15 : 17
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        width: parent.width
                                                        text: root.searchResultSubtitle(itemData)
                                                        textFormat: Text.PlainText
                                                        color: root.menuTextSecondaryColor
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: root.searchKeyboardOpen ? 10 : 11
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

                                    Rectangle {
                                        visible: searchResultsSurface.results.length > searchResultsSurface.visibleRows
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 8
                                        radius: 4
                                        color: root.menuBorderColor
                                        opacity: 0.55

                                        Rectangle {
                                            width: parent.width
                                            radius: 4
                                            color: root.menuAccentColor
                                            readonly property int maxOffset: Math.max(1, searchResultsSurface.results.length - searchResultsSurface.visibleRows)
                                            height: Math.max(20, parent.height * searchResultsSurface.visibleRows / Math.max(searchResultsSurface.results.length, 1))
                                            y: Math.min(parent.height - height,
                                                (parent.height - height)
                                                * root.searchResultOffset
                                                / maxOffset)
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                const next = mouse.y > parent.height / 2
                                                    ? root.searchResultOffset + 1
                                                    : root.searchResultOffset - 1
                                                root.setSearchResultOffset(next)
                                            }
                                        }
                                    }
                                }

                                Column {
                                    visible: root.mapMenuStage === "settings"
                                    width: parent.width
                                    spacing: 12

                                    Column {
                                        visible: root.mapMenuSystemMode
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            width: parent.width
                                            text: "Display"
                                            color: root.menuTextSecondaryColor
                                            font.family: appTheme.fontMono
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.2
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                        }

                                        Row {
                                            width: parent.width
                                            height: 64
                                            spacing: 8

                                            Repeater {
                                                model: root.chromeThemeOptions

                                                delegate: Rectangle {
                                                    readonly property bool selected: String(modelData.id) === root.normalizedThemeMode
                                                    width: (parent.width - 16) / 3
                                                    height: parent.height
                                                    radius: 18
                                                    color: selected ? root.menuSurfaceSelectedColor : root.menuSurfaceAltColor
                                                    border.width: 1
                                                    border.color: selected ? root.menuAccentColor : root.menuBorderColor

                                                    Column {
                                                        anchors.fill: parent
                                                        anchors.margins: 12
                                                        spacing: 4

                                                        Row {
                                                            width: parent.width
                                                            height: 14
                                                            spacing: 5

                                                            Rectangle {
                                                                width: (parent.width - 10) / 3
                                                                height: parent.height
                                                                radius: 7
                                                                color: modelData.id === "dark" ? "#111827" : "#FFFFFF"
                                                                border.width: 1
                                                                border.color: root.menuBorderColor
                                                            }

                                                            Rectangle {
                                                                width: (parent.width - 10) / 3
                                                                height: parent.height
                                                                radius: 7
                                                                color: modelData.id === "light" ? "#FFFFFF" : "#1F2937"
                                                                border.width: 1
                                                                border.color: root.menuBorderColor
                                                            }

                                                            Rectangle {
                                                                width: (parent.width - 10) / 3
                                                                height: parent.height
                                                                radius: 7
                                                                color: modelData.id === "auto"
                                                                    ? (root.menuDarkChrome ? "#1F2937" : "#FFFFFF")
                                                                    : (modelData.id === "dark" ? "#1F2937" : "#E8F0FE")
                                                                border.width: 1
                                                                border.color: root.menuBorderColor
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: modelData.label
                                                            color: root.menuTextPrimaryColor
                                                            font.family: appTheme.fontDisplay
                                                            font.pixelSize: 17
                                                            font.weight: Font.DemiBold
                                                            font.hintingPreference: root.menuTextHintingPreference
                                                            renderType: root.menuTextRenderType
                                                            horizontalAlignment: Text.AlignHCenter
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: root.themeOptionDetail(modelData.id, modelData.detail)
                                                            color: selected ? root.menuAccentColor : root.menuTextSecondaryColor
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
                                                        onClicked: root.selectChromeThemeMode(modelData.id)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        visible: !root.mapMenuSystemMode
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            width: parent.width
                                            text: "Map view"
                                            color: root.menuTextSecondaryColor
                                            font.family: appTheme.fontMono
                                            font.pixelSize: 13
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0.2
                                            font.hintingPreference: root.menuTextHintingPreference
                                            renderType: root.menuTextRenderType
                                        }

                                        Row {
                                            width: parent.width
                                            height: 96
                                            spacing: 8

                                            Repeater {
                                                model: root.mapThemeOptions

                                                delegate: Rectangle {
                                                    readonly property bool selected: String(modelData.id) === String(root.activeMapThemeOption.id)
                                                    width: (parent.width - 24) / 4
                                                    height: parent.height
                                                    radius: 18
                                                    color: selected ? root.menuSurfaceSelectedColor : root.menuSurfaceAltColor
                                                    border.width: 1
                                                    border.color: selected ? root.menuAccentColor : root.menuBorderColor

                                                    Column {
                                                        anchors.fill: parent
                                                        anchors.margins: 10
                                                        spacing: 6

                                                        Rectangle {
                                                            width: parent.width
                                                            height: 24
                                                            radius: 8
                                                            color: modelData.swatchA
                                                            border.width: 1
                                                            border.color: selected ? root.menuAccentColor : root.menuBorderColor

                                                            Rectangle {
                                                                width: parent.width * 0.44
                                                                height: parent.height
                                                                anchors.right: parent.right
                                                                radius: 5
                                                                color: modelData.swatchB
                                                            }
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: modelData.label
                                                            color: root.menuTextPrimaryColor
                                                            font.family: appTheme.fontDisplay
                                                            font.pixelSize: 17
                                                            font.weight: Font.DemiBold
                                                            font.hintingPreference: root.menuTextHintingPreference
                                                            renderType: root.menuTextRenderType
                                                            horizontalAlignment: Text.AlignHCenter
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            text: modelData.detail
                                                            color: selected ? root.menuAccentColor : root.menuTextSecondaryColor
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

                                    Row {
                                        visible: root.mapMenuSystemMode
                                        width: parent.width
                                        height: 38
                                        spacing: 8

                                        Rectangle {
                                            width: (parent.width - 8) / 2
                                            height: parent.height
                                            radius: 18
                                            color: root.menuSurfaceAltColor
                                            border.width: 1
                                            border.color: hotspotState === "online" ? "#2E8B67" : root.menuBorderColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: hotspotState === "online" ? "Wi-Fi details" : "Set up Wi-Fi"
                                                color: hotspotState === "online" ? "#8AF0B7" : root.menuTextPrimaryColor
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    wifiOverlay.openPrompt()
                                                    root.mapMenuOpen = false
                                                    root.searchKeyboardOpen = false
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: (parent.width - 8) / 2
                                            height: parent.height
                                            radius: 18
                                            color: navigation.muted ? root.menuDangerSurfaceColor : root.menuSurfaceAltColor
                                            border.width: 1
                                            border.color: navigation.muted ? root.menuDangerBorderColor : root.menuBorderColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: navigation.muted ? "Audio cues off" : "Audio cues on"
                                                color: navigation.muted ? "#D93025" : root.menuTextPrimaryColor
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: navigation.setMuted(!navigation.muted)
                                            }
                                        }
                                    }

                                    Row {
                                        visible: !root.mapMenuSystemMode
                                        width: parent.width
                                        height: 38
                                        spacing: 8

                                        Rectangle {
                                            width: (parent.width - 8) / 2
                                            height: parent.height
                                            radius: 18
                                            color: root.menuSurfaceAltColor
                                            border.width: 1
                                            border.color: followUnlocked ? root.menuAccentColor : root.menuBorderColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: followUnlocked ? "Recenter map" : "Following"
                                                color: followUnlocked ? root.menuAccentColor : root.menuTextPrimaryColor
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    navigation.recenter()
                                                    navField.setFollowEnabled(true)
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: (parent.width - 8) / 2
                                            height: parent.height
                                            radius: 18
                                            color: navigation.muted ? root.menuDangerSurfaceColor : root.menuSurfaceAltColor
                                            border.width: 1
                                            border.color: navigation.muted ? root.menuDangerBorderColor : root.menuBorderColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: navigation.muted ? "Sound off" : "Sound on"
                                                color: navigation.muted ? "#D93025" : root.menuTextPrimaryColor
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 13
                                                font.weight: Font.Bold
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: navigation.setMuted(!navigation.muted)
                                            }
                                        }
                                    }
                                }

                                Column {
                                    visible: root.mapMenuStage === "spotify"
                                    width: parent.width
                                    spacing: 10

                                    Rectangle {
                                        width: parent.width
                                        height: 274
                                        radius: 18
                                        color: root.menuSurfaceAltColor
                                        border.width: 1
                                        border.color: root.menuBorderColor

                                        Row {
                                            anchors.fill: parent
                                            anchors.margins: 18
                                            spacing: 22

                                            Rectangle {
                                                id: spotifyQrBox
                                                width: 238
                                                height: 238
                                                radius: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: "#FFFFFF"
                                                border.width: 0
                                                visible: root.spotifyPairingActive
                                                    && root.nowPlayingService
                                                    && root.nowPlayingService.spotifyPairingQrPattern.length > 0
                                                property string qrPattern: root.nowPlayingService ? String(root.nowPlayingService.spotifyPairingQrPattern) : ""
                                                property var qrRows: qrPattern.length > 0 ? qrPattern.split("\n") : []
                                                property int qrModuleCount: qrRows.length
                                                property int qrModuleSize: qrModuleCount > 0 ? Math.floor((Math.min(width, height) - 28) / qrModuleCount) : 1
                                                property var qrModules: qrPattern.length > 0 ? qrPattern.replace(/\n/g, "").split("") : []

                                                Item {
                                                    anchors.centerIn: parent
                                                    width: spotifyQrBox.qrModuleCount * spotifyQrBox.qrModuleSize
                                                    height: width

                                                    Repeater {
                                                        model: spotifyQrBox.qrModules

                                                        Rectangle {
                                                            x: (index % spotifyQrBox.qrModuleCount) * spotifyQrBox.qrModuleSize
                                                            y: Math.floor(index / spotifyQrBox.qrModuleCount) * spotifyQrBox.qrModuleSize
                                                            width: spotifyQrBox.qrModuleSize
                                                            height: spotifyQrBox.qrModuleSize
                                                            color: modelData === "1" ? "#000000" : "#FFFFFF"
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                width: 238
                                                height: 238
                                                radius: 119
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: root.menuSurfaceColor
                                                border.width: 1
                                                border.color: root.menuBorderColor
                                                visible: !spotifyQrBox.visible

                                                OemIcon {
                                                    anchors.centerIn: parent
                                                    width: 96
                                                    height: 96
                                                    icon: "audio"
                                                    active: root.musicPlaying
                                                    color: root.menuTextPrimaryColor
                                                    accentColor: root.menuAccentColor
                                                    strokeWidth: 5.0
                                                }
                                            }

                                            Column {
                                                width: parent.width - 260
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 10

                                                Text {
                                                    width: parent.width
                                                    text: "Spotify now playing"
                                                    color: root.menuTextPrimaryColor
                                                    font.family: appTheme.fontDisplay
                                                    font.pixelSize: 26
                                                    font.weight: Font.DemiBold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: root.spotifySetupStatusLine()
                                                    color: root.spotifyPairingActive ? "#FFFFFF" : root.menuTextSecondaryColor
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: 13
                                                    font.weight: Font.Bold
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    wrapMode: Text.WordWrap
                                                    maximumLineCount: 2
                                                }

                                                Text {
                                                    width: parent.width
                                                    text: root.nowPlayingService && root.nowPlayingService.spotifyPairingCode.length > 0
                                                        ? root.nowPlayingService.spotifyPairingCode
                                                        : (root.musicAvailable ? root.musicNowPlayingLine() : "SCAN TO CONNECT")
                                                    color: root.musicAvailable ? root.menuAccentColor : root.menuTextPrimaryColor
                                                    font.family: appTheme.fontMono
                                                    font.pixelSize: root.nowPlayingService && root.nowPlayingService.spotifyPairingCode.length > 0 ? 34 : 13
                                                    font.weight: Font.Bold
                                                    font.letterSpacing: 0
                                                    font.hintingPreference: root.menuTextHintingPreference
                                                    renderType: root.menuTextRenderType
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    width: 154
                                                    height: 42
                                                    radius: 14
                                                    enabled: root.spotifyPairingSupported
                                                    opacity: enabled ? 1.0 : 0.56
                                                    color: spotifyPairingMouse.pressed && enabled ? root.menuSurfaceSelectedColor : root.menuAccentColor
                                                    border.width: 1
                                                    border.color: root.menuAccentColor

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: root.spotifyActionLabel()
                                                        color: root.spotifyPairingSupported ? "#FFFFFF" : root.menuTextMutedColor
                                                        font.family: appTheme.fontMono
                                                        font.pixelSize: 13
                                                        font.weight: Font.Bold
                                                        font.letterSpacing: 1.0
                                                        font.hintingPreference: root.menuTextHintingPreference
                                                        renderType: root.menuTextRenderType
                                                    }

                                                    MouseArea {
                                                        id: spotifyPairingMouse
                                                        anchors.fill: parent
                                                        enabled: parent.enabled
                                                        onClicked: root.triggerSpotifySetup()
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: !root.spotifyPairingActive
                                        width: parent.width
                                        height: 96
                                        radius: 16
                                        color: root.menuSurfaceAltColor
                                        border.width: 1
                                        border.color: root.menuBorderColor

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: 12
                                            spacing: 5

                                            Text {
                                                width: parent.width
                                                text: root.musicAvailable ? root.musicNowPlayingLine() : "Nothing playing"
                                                color: root.menuTextPrimaryColor
                                                font.family: appTheme.fontDisplay
                                                font.pixelSize: 20
                                                font.weight: Font.DemiBold
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                text: "The cluster only reads the current track. Playback stays on the phone."
                                                color: root.menuTextSecondaryColor
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 12
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
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
                                            anchors.rightMargin: 116
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

                                        Rectangle {
                                            id: routeStartButton
                                            width: 86
                                            height: 34
                                            radius: 11
                                            anchors.right: parent.right
                                            anchors.rightMargin: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                            enabled: root.availableRouteOptions().length > 0 || root.hasActiveRoute
                                            opacity: enabled ? 1.0 : 0.48
                                            color: routeStartMouse.pressed ? "#3B8EFF" : root.menuAccentColor
                                            border.width: 1
                                            border.color: root.menuAccentColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: "START"
                                                color: "#FFFFFF"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                                font.letterSpacing: 1.0
                                                font.hintingPreference: root.menuTextHintingPreference
                                                renderType: root.menuTextRenderType
                                            }

                                            MouseArea {
                                                id: routeStartMouse
                                                anchors.fill: parent
                                                enabled: routeStartButton.enabled
                                                onClicked: root.startSelectedRoute()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: root.searchKeyboardOpen
                            width: parent.width
                            spacing: 5

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
                                            height: 30
                                            radius: 10
                                            color: keyMouse.pressed ? "#2A7FAF" : "#0F2230"
                                            border.width: 1
                                            border.color: keyMouse.pressed ? "#B2EBFF" : "#35627F"

                                            Text {
                                                anchors.centerIn: parent
                                                text: keyValue === "BACKSPACE" ? "BKSP" : keyValue
                                                color: "#F4FBFF"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 14
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

                        Item {
                            id: routeButton
                            visible: false
                            width: 0
                            height: 0

                            readonly property bool blocked: root.mapMenuStage === "routing"
                                || (root.mapMenuStage === "routes"
                                    && root.availableRouteOptions().length <= 0
                                    && !root.hasActiveRoute)

                            function trigger() {
                                if (root.mapMenuStage === "settings" || root.mapMenuStage === "spotify") {
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
                                if (root.mapMenuStage === "search" && !root.routeLookupInProgress) {
                                    const results = root.menuResultsModel()
                                    if (results.length > 0) {
                                        root.chooseSearchResult(results[0])
                                        return
                                    }
                                    root.routeSearchQuery(searchInput.text)
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
