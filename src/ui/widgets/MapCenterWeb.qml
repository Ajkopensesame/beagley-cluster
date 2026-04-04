import QtQuick 2.15
import QtWebEngine
import QtCore
import Qt.labs.settings

Item {
    id: root
    anchors.fill: parent

    property real lat: -27.4698
    property real lng: 153.0251
    property real bearing: 0
    property real speedKph: 0
    property bool fixedOriginEnabled: false
    property real fixedOriginLat: NaN
    property real fixedOriginLng: NaN
    property string fixedOriginLabel: ""
    property bool demoMotion: false
    property bool pageReady: false
    property bool followVehicle: true
    property bool interactionEnabled: true
    property var navigationState: ({})
    property var mapVehiclePose: ({})
    property var mapCameraHints: ({})
    property var mapRouteOverlay: ({})
    property var mapGuidanceBanner: ({})
    property var mapConnectivity: ({})
    property string renderMode: "web-vector"
    property string failureReason: ""
    property int errorCount: 0
    property int bridgeMessageCount: 0
    property double bootStartedAtMs: 0
    property bool bootShellMetricLogged: false
    property bool domReady: false
    property bool styleReady: false
    property bool firstFrameReady: false
    property bool interactiveReady: false
    property string lastVehiclePoseJson: ""
    property string lastCameraHintsJson: ""
    property string lastRouteOverlayJson: ""
    property string lastGuidanceBannerJson: ""
    property string lastConnectivityJson: ""
    property string styleUrl: resolvedStyleUrl()

    readonly property bool embeddedDisplay: ((typeof BEAGLEY_EMBEDDED_DISPLAY !== "undefined") && BEAGLEY_EMBEDDED_DISPLAY) || false
    readonly property string bootMode: (typeof BEAGLEY_MAP_BOOT_MODE !== "undefined" && BEAGLEY_MAP_BOOT_MODE)
        ? String(BEAGLEY_MAP_BOOT_MODE)
        : (embeddedDisplay ? "staged" : "direct")
    readonly property string styleMode: (typeof BEAGLEY_MAP_STYLE_MODE !== "undefined" && BEAGLEY_MAP_STYLE_MODE)
        ? String(BEAGLEY_MAP_STYLE_MODE)
        : (embeddedDisplay ? "embedded" : "desktop")
    readonly property bool webEngineSoftware: (typeof BEAGLEY_WEBENGINE_SOFTWARE !== "undefined")
        && !!BEAGLEY_WEBENGINE_SOFTWARE
    readonly property bool stagedBootEnabled: bootMode !== "direct"
    readonly property int loadGuardMs: embeddedDisplay ? 30000 : 8000
    readonly property string pageUrl: "qrc:///web/map/index.html?style="
        + encodeURIComponent(styleUrl)
        + "&embedded=" + (embeddedDisplay ? "1" : "0")
        + "&styleMode=" + encodeURIComponent(styleMode)
        + "&software=" + (webEngineSoftware ? "1" : "0")
    readonly property var resolvedVehicleBucket: hasKeys(mapVehiclePose)
        ? mapVehiclePose
        : ((navigationState && navigationState.vehiclePose) ? navigationState.vehiclePose : ({}))
    readonly property var resolvedCameraBucket: hasKeys(mapCameraHints)
        ? mapCameraHints
        : ((navigationState && navigationState.camera) ? navigationState.camera : ({}))
    readonly property var resolvedRouteBucket: hasKeys(mapRouteOverlay)
        ? mapRouteOverlay
        : navigationState
    readonly property var resolvedGuidanceBucket: hasKeys(mapGuidanceBanner)
        ? mapGuidanceBanner
        : ({
            banner: (navigationState && navigationState.banner) ? navigationState.banner : ({}),
            remainingDistanceMeters: navigationState ? Number(navigationState.remainingDistanceMeters || 0) : 0,
            remainingDurationSeconds: navigationState ? Number(navigationState.remainingDurationSeconds || 0) : 0,
            eta: navigationState ? String(navigationState.eta || "") : "",
            trafficDelaySeconds: navigationState ? Number(navigationState.trafficDelaySeconds || 0) : 0,
            networkStatus: navigationState ? String(navigationState.networkStatus || "offline") : "offline",
            providerStatus: navigationState ? String(navigationState.providerStatus || "offline") : "offline",
            followMode: navigationState ? String(navigationState.followMode || "auto") : "auto"
        })
    readonly property var resolvedConnectivityBucket: hasKeys(mapConnectivity)
        ? mapConnectivity
        : ((navigationState && navigationState.connectivity) ? navigationState.connectivity : ({}))
    readonly property var liveRouteCoordinates: resolvedRouteCoordinates()
    readonly property var liveDestination: resolvedDestination()
    readonly property var cachedCameraState: parseJson(bootCache.cameraJson, ({}))
    readonly property var cachedRouteState: parseJson(bootCache.routeJson, ({}))
    readonly property var cachedDestinationState: parseJson(bootCache.destinationJson, ({}))
    readonly property real shellCameraLat: isFinite(Number(cachedCameraState.centerLat))
        ? Number(cachedCameraState.centerLat)
        : (isFinite(Number(resolvedVehicleBucket.lat)) ? Number(resolvedVehicleBucket.lat) : lat)
    readonly property real shellCameraLng: isFinite(Number(cachedCameraState.centerLng))
        ? Number(cachedCameraState.centerLng)
        : (isFinite(Number(resolvedVehicleBucket.lng)) ? Number(resolvedVehicleBucket.lng) : lng)
    readonly property real shellCameraBearing: isFinite(Number(cachedCameraState.bearing))
        ? Number(cachedCameraState.bearing)
        : (isFinite(Number(resolvedVehicleBucket.bearing)) ? Number(resolvedVehicleBucket.bearing) : bearing)
    readonly property int shellCameraZoom: isFinite(Number(cachedCameraState.zoom))
        ? Math.max(3, Math.min(18, Math.round(Number(cachedCameraState.zoom))))
        : 15
    readonly property var shellRouteCoordinates: liveRouteCoordinates.length > 1
        ? liveRouteCoordinates
        : (cachedRouteState.coordinates || [])
    readonly property var shellDestination: hasKeys(liveDestination)
        ? liveDestination
        : cachedDestinationState
    readonly property bool liveMapVisible: !stagedBootEnabled
        || firstFrameReady
        || (webEngineSoftware && styleReady)

    signal snapshotFallbackRequested(string reason)

    Settings {
        id: bootCache
        category: "map_boot"
        property string cameraJson: ""
        property string routeJson: ""
        property string destinationJson: ""
    }

    WebEngineProfile {
        id: webProfile
        storageName: "beagley-map"
        offTheRecord: false
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        cachePath: StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/web-map"
        persistentStoragePath: StandardPaths.writableLocation(StandardPaths.AppDataLocation) + "/web-map"
        httpUserAgent: "BeagleyCluster/1.0 (QtWebEngine embedded map)"
    }

    function hasKeys(value) {
        return !!value && Object.keys(value).length > 0
    }

    function resolvedStyleUrl() {
        if (typeof BEAGLEY_MAP_STYLE_URL !== "undefined" && BEAGLEY_MAP_STYLE_URL)
            return String(BEAGLEY_MAP_STYLE_URL)
        return styleMode === "embedded"
            ? "qrc:/web/map/styles/embedded-liberty.json"
            : "https://tiles.openfreemap.org/styles/liberty"
    }

    function parseJson(raw, fallbackValue) {
        if (!raw || !String(raw).length)
            return fallbackValue
        try {
            return JSON.parse(raw)
        } catch (err) {
            return fallbackValue
        }
    }

    function encodeJson(value) {
        try {
            return JSON.stringify(value || {})
        } catch (err) {
            console.error("[MapCenterWeb] failed to serialize payload:", err)
            return ""
        }
    }

    function elapsedMs() {
        return bootStartedAtMs > 0 ? Math.max(0, Math.round(Date.now() - bootStartedAtMs)) : 0
    }

    function logMetric(name, value) {
        console.log("[MapBoot] " + name + "=" + value)
    }

    function recordReady(stage, value) {
        if (stage === "page_dom_ready" && !domReady) {
            domReady = true
            logMetric("map_page_dom_ready_ms", value)
        } else if (stage === "style_ready" && !styleReady) {
            styleReady = true
            logMetric("map_style_ready_ms", value)
        } else if (stage === "first_frame_ready" && !firstFrameReady) {
            firstFrameReady = true
            logMetric("map_first_frame_ms", value)
        } else if (stage === "interactive_ready" && !interactiveReady) {
            interactiveReady = true
            logMetric("map_interactive_ms", value)
        }
    }

    function requestSnapshotFallback(reason) {
        if (failureReason === reason)
            return
        failureReason = reason
        console.warn("[MapCenterWeb] snapshot fallback:", reason)
        snapshotFallbackRequested(reason)
    }

    function resetBootState() {
        pageReady = false
        domReady = false
        styleReady = false
        firstFrameReady = false
        interactiveReady = false
        renderMode = "web-vector"
        errorCount = 0
        failureReason = ""
        lastVehiclePoseJson = ""
        lastCameraHintsJson = ""
        lastRouteOverlayJson = ""
        lastGuidanceBannerJson = ""
        lastConnectivityJson = ""
        bootStartedAtMs = Date.now()
        if (!bootShellMetricLogged) {
            bootShellMetricLogged = true
            logMetric("map_boot_shell_ms", 0)
        }
    }

    function queuePoseAndCameraPush() {
        if (!pageReady)
            return
        poseBridgeTimer.restart()
    }

    function pushScript(functionName, payloadJson) {
        if (!pageReady || !payloadJson.length)
            return
        bridgeMessageCount += 1
        web.runJavaScript("if (window." + functionName + ") window." + functionName + "(" + payloadJson + ");")
    }

    function pushVehiclePose() {
        const payloadJson = encodeJson(resolvedVehicleBucket)
        if (!payloadJson.length || payloadJson === lastVehiclePoseJson)
            return
        lastVehiclePoseJson = payloadJson
        pushScript("applyVehiclePose", payloadJson)
    }

    function pushCameraHints() {
        const payloadJson = encodeJson(resolvedCameraBucket)
        if (!payloadJson.length || payloadJson === lastCameraHintsJson)
            return
        lastCameraHintsJson = payloadJson
        pushScript("applyCameraHints", payloadJson)
    }

    function pushRouteOverlay() {
        const payloadJson = encodeJson(resolvedRouteBucket)
        if (!payloadJson.length || payloadJson === lastRouteOverlayJson)
            return
        lastRouteOverlayJson = payloadJson
        pushScript("applyRouteOverlay", payloadJson)
    }

    function pushGuidanceBanner() {
        const payloadJson = encodeJson(resolvedGuidanceBucket)
        if (!payloadJson.length || payloadJson === lastGuidanceBannerJson)
            return
        lastGuidanceBannerJson = payloadJson
        pushScript("applyGuidanceBanner", payloadJson)
    }

    function pushConnectivity() {
        const payloadJson = encodeJson(resolvedConnectivityBucket)
        if (!payloadJson.length || payloadJson === lastConnectivityJson)
            return
        lastConnectivityJson = payloadJson
        pushScript("applyConnectivity", payloadJson)
    }

    function pushPoseAndCamera() {
        pushVehiclePose()
        pushCameraHints()
    }

    function pushAllState() {
        pushRouteOverlay()
        pushGuidanceBanner()
        pushConnectivity()
        pushPoseAndCamera()
        pushFollowState()
    }

    function pushFollowState() {
        if (!pageReady)
            return
        bridgeMessageCount += 1
        web.runJavaScript(
            "if (window.setFollowVehicle) window.setFollowVehicle(" + (followVehicle ? "true" : "false") + ");"
        )
    }

    function clearRoute() {
        if (!pageReady)
            return
        bridgeMessageCount += 1
        web.runJavaScript("if (window.clearNavigationState) window.clearNavigationState();")
    }

    function setFollowEnabled(enabled) {
        followVehicle = !!enabled
        pushFollowState()
    }

    function resolvedRouteCoordinates() {
        const route = resolvedRouteBucket && resolvedRouteBucket.route ? resolvedRouteBucket.route : ({})
        const geometry = route.geometry || ({})
        const coordinates = geometry.coordinates || []
        return Array.isArray(coordinates) ? coordinates : []
    }

    function resolvedDestination() {
        const value = resolvedRouteBucket && resolvedRouteBucket.destination ? resolvedRouteBucket.destination : ({})
        return value || ({})
    }

    function persistBootCameraState(payload) {
        bootCache.cameraJson = JSON.stringify(payload)
    }

    function persistBootRouteState(payload) {
        bootCache.routeJson = JSON.stringify(payload)
    }

    function persistBootDestinationState(payload) {
        bootCache.destinationJson = JSON.stringify(payload)
    }

    Timer {
        id: loadGuard
        interval: root.loadGuardMs
        repeat: false
        onTriggered: {
            if (!root.pageReady) {
                root.requestSnapshotFallback("page_ready_timeout")
                return
            }
            if (!root.firstFrameReady) {
                if (root.webEngineSoftware && root.styleReady) {
                    root.recordReady("first_frame_ready", root.elapsedMs())
                    return
                }
                root.logMetric("map_first_frame_pending_ms", root.elapsedMs())
                loadGuard.restart()
            }
        }
    }

    Timer {
        id: poseBridgeTimer
        interval: root.embeddedDisplay ? (root.webEngineSoftware ? 333 : 200) : 90
        repeat: false
        onTriggered: root.pushPoseAndCamera()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.bridgeMessageCount > 0) {
                console.log("[MapBridge] messages_per_sec=" + root.bridgeMessageCount)
                root.bridgeMessageCount = 0
            }
        }
    }

    MapCenterBootShell {
        id: bootShell
        anchors.fill: parent
        visible: root.stagedBootEnabled
        opacity: root.liveMapVisible ? 0 : 1
        liveLat: isFinite(Number(root.resolvedVehicleBucket.lat)) ? Number(root.resolvedVehicleBucket.lat) : root.lat
        liveLng: isFinite(Number(root.resolvedVehicleBucket.lng)) ? Number(root.resolvedVehicleBucket.lng) : root.lng
        liveBearing: isFinite(Number(root.resolvedVehicleBucket.bearing)) ? Number(root.resolvedVehicleBucket.bearing) : root.bearing
        cameraLat: root.shellCameraLat
        cameraLng: root.shellCameraLng
        cameraBearing: root.shellCameraBearing
        cameraZoom: root.shellCameraZoom
        routeCoordinates: root.shellRouteCoordinates
        destination: root.shellDestination
        statusText: root.failureReason.length > 0
            ? "Using cached map"
            : (root.firstFrameReady ? "Map live" : "Loading live map")
        detailText: root.failureReason.length > 0
            ? "Vector map is still starting"
            : (root.styleReady ? "Finalizing vector scene" : "Preparing vector style")
        degraded: root.failureReason.length > 0

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        url: root.pageUrl
        profile: webProfile
        enabled: root.interactionEnabled
        visible: true
        opacity: root.liveMapVisible ? 1 : 0

        settings.javascriptEnabled: true
        settings.errorPageEnabled: false
        settings.localContentCanAccessRemoteUrls: true
        settings.localContentCanAccessFileUrls: true

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }

        onLoadingChanged: function(req) {
            console.log(
                "[WEB] load status:",
                req.status,
                "url:", req.url,
                "error:", req.errorString,
                "code:", req.errorCode,
                "domain:", req.errorDomain
            )

            if (req.status === WebEngineView.LoadStartedStatus) {
                root.resetBootState()
                loadGuard.restart()
                return
            }

            if (req.status === WebEngineView.LoadSucceededStatus) {
                root.pageReady = true
                loadGuard.restart()
                root.pushAllState()
                return
            }

            if (req.status === WebEngineView.LoadFailedStatus) {
                loadGuard.stop()
                root.pageReady = false
                root.requestSnapshotFallback("page_load_failed:" + req.errorCode + ":" + req.errorString)
            }
        }

        onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceId) {
            console.log("[WEBJS]", level, sourceId + ":" + lineNumber, message)

            const modePrefix = "[BEAGLEY_MAP_MODE] "
            const fatalPrefix = "[BEAGLEY_MAP_FATAL] "
            const fallbackPrefix = "[BEAGLEY_MAP_FALLBACK] "
            const readyPrefix = "[BEAGLEY_MAP_READY] "
            const cachePrefix = "[BEAGLEY_MAP_CACHE] "

            if (message.indexOf(modePrefix) === 0) {
                root.renderMode = message.substring(modePrefix.length).trim()
                return
            }

            if (message.indexOf(readyPrefix) === 0) {
                const parts = message.substring(readyPrefix.length).trim().split(/\s+/)
                const stage = parts.length > 0 ? parts[0] : ""
                const value = parts.length > 1 ? Number(parts[1]) : root.elapsedMs()
                root.recordReady(stage, isFinite(value) ? value : root.elapsedMs())
                return
            }

            if (message.indexOf(cachePrefix) === 0) {
                const payload = root.parseJson(message.substring(cachePrefix.length).trim(), ({}))
                if (payload && root.hasKeys(payload.camera || ({})))
                    root.persistBootCameraState(payload.camera)
                if (payload && root.hasKeys(payload.route || ({})))
                    root.persistBootRouteState(payload.route)
                if (payload && root.hasKeys(payload.destination || ({})))
                    root.persistBootDestinationState(payload.destination)
                return
            }

            if (message.indexOf(fatalPrefix) === 0) {
                root.errorCount += 1
                if (root.errorCount >= 2)
                    root.requestSnapshotFallback(message.substring(fatalPrefix.length).trim())
                return
            }

            if (message.indexOf(fallbackPrefix) === 0) {
                root.requestSnapshotFallback(message.substring(fallbackPrefix.length).trim())
                return
            }

            if (level === WebEngineView.ErrorMessageLevel) {
                root.errorCount += 1
                if (root.errorCount >= 3)
                    root.requestSnapshotFallback("web_console_errors")
            }
        }
    }

    onMapVehiclePoseChanged: queuePoseAndCameraPush()
    onMapCameraHintsChanged: queuePoseAndCameraPush()
    onMapRouteOverlayChanged: pushRouteOverlay()
    onMapGuidanceBannerChanged: pushGuidanceBanner()
    onMapConnectivityChanged: pushConnectivity()
    onFollowVehicleChanged: pushFollowState()
    onPageReadyChanged: if (pageReady) pushAllState()

    Component.onCompleted: {
        resetBootState()
    }
}
