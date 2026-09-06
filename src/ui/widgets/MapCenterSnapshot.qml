import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

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
    property string snapshotUrl: ""
    property int refreshMs: 1000
    property bool tilePrimary: (typeof BEAGLEY_MAP_RENDERER !== "undefined")
        ? String(BEAGLEY_MAP_RENDERER) !== "web"
        : true
    readonly property bool lowEffectMode: (typeof BEAGLEY_EFFECT_LEVEL !== "undefined")
        ? String(BEAGLEY_EFFECT_LEVEL).toLowerCase() === "off"
        : false
    readonly property int cameraRefreshIntervalMs: lowEffectMode ? 700 : (root.tilePrimary ? 140 : 80)
    readonly property int rerouteIntervalMs: lowEffectMode ? 800 : 350
    readonly property int previewIntervalMs: lowEffectMode ? 250 : 100

    property bool followEnabled: true
    property bool holdingOverview: false
    property bool previewRunning: false
    property var destination: null
    property var routePoints: []
    property var routeProfile: []
    property real routeDistanceMeters: 0
    property real routeDurationSeconds: 0
    property real previewProgressMeters: 0
    property real previewSpeedKph: 0
    property real previewLat: 0
    property real previewLng: 0
    property real previewBearing: 0
    property string statusText: "Waiting for GPS..."
    property string detailText: "Search destination"
    property color statusColor: "#9fb2c1"
    property string lastGoodSnapshotUrl: ""
    property string pendingSnapshotUrl: ""
    property real pendingSnapshotLat: 0
    property real pendingSnapshotLng: 0
    property int pendingSnapshotZoom: 16
    property real renderCameraLat: -27.4698
    property real renderCameraLng: 153.0251
    property int renderCameraZoom: 16
    property bool snapshotLoadFailed: false
    property string snapshotFailureText: ""
    property real lastCameraRequestLat: NaN
    property real lastCameraRequestLng: NaN
    property real lastCameraRequestBearing: NaN
    property real lastCameraRequestSpeedKph: NaN
    property double lastCameraRefreshAtMs: 0

    readonly property bool hasSplitBuckets: hasObjectKeys(mapVehiclePose)
        || hasObjectKeys(mapCameraHints)
        || hasObjectKeys(mapRouteOverlay)
        || hasObjectKeys(mapGuidanceBanner)
        || hasObjectKeys(mapConnectivity)
    readonly property bool hasLegacyPayload: navigationState
        && (navigationState.vehiclePose !== undefined
            || navigationState.destination !== undefined
            || navigationState.route !== undefined
            || navigationState.connectivity !== undefined)
    readonly property bool useExternalNavigation: hasSplitBuckets || hasLegacyPayload
    readonly property var resolvedRouteOverlay: hasObjectKeys(mapRouteOverlay)
        ? mapRouteOverlay
        : (navigationState || ({}))
    readonly property var resolvedVehicleBucket: hasObjectKeys(mapVehiclePose)
        ? mapVehiclePose
        : ((resolvedRouteOverlay && resolvedRouteOverlay.vehiclePose) ? resolvedRouteOverlay.vehiclePose : ({}))
    readonly property var resolvedCameraBucket: hasObjectKeys(mapCameraHints)
        ? mapCameraHints
        : ((resolvedRouteOverlay && resolvedRouteOverlay.camera) ? resolvedRouteOverlay.camera : ({}))
    readonly property var resolvedGuidanceBucket: hasObjectKeys(mapGuidanceBanner)
        ? mapGuidanceBanner
        : ({
            banner: (resolvedRouteOverlay && resolvedRouteOverlay.banner) ? resolvedRouteOverlay.banner : ({}),
            networkStatus: resolvedRouteOverlay ? String(resolvedRouteOverlay.networkStatus || "") : "",
            providerStatus: resolvedRouteOverlay ? String(resolvedRouteOverlay.providerStatus || "") : ""
        })
    readonly property var resolvedConnectivityBucket: hasObjectKeys(mapConnectivity)
        ? mapConnectivity
        : ((resolvedRouteOverlay && resolvedRouteOverlay.connectivity) ? resolvedRouteOverlay.connectivity : ({}))
    readonly property var externalVehiclePose: useExternalNavigation ? resolvedVehicleBucket : ({})
    readonly property real resolvedVehicleLat: isFinite(lat)
        ? lat
        : (isFinite(Number(externalVehiclePose.lat))
        ? Number(externalVehiclePose.lat)
        : effectiveLat)
    readonly property real resolvedVehicleLng: isFinite(lng)
        ? lng
        : (isFinite(Number(externalVehiclePose.lng))
        ? Number(externalVehiclePose.lng)
        : effectiveLng)
    readonly property real resolvedVehicleBearing: isFinite(bearing)
        ? bearing
        : (isFinite(Number(externalVehiclePose.bearing))
        ? Number(externalVehiclePose.bearing)
        : bearing)
    readonly property real resolvedSpeedKph: isFinite(speedKph) && speedKph > 0
        ? speedKph
        : (isFinite(Number(externalVehiclePose.speedKph))
        ? Number(externalVehiclePose.speedKph)
        : speedKph)

    property real vehicleLat: previewRunning ? previewLat : resolvedVehicleLat
    property real vehicleLng: previewRunning ? previewLng : resolvedVehicleLng
    property real vehicleBearing: previewRunning ? previewBearing : resolvedVehicleBearing
    property real cameraSpeedKph: previewRunning ? clamp(previewSpeedKph, 35, 80) : resolvedSpeedKph
    property real cameraLat: vehicleLat
    property real cameraLng: vehicleLng
    property int cameraZoom: followZoomForSpeed(cameraSpeedKph, previewRunning)

    property int searchToken: 0
    property int routeToken: 0
    property real lastRouteOriginLat: NaN
    property real lastRouteOriginLng: NaN
    property double lastRouteAtMs: 0
    property string lastOverviewKey: ""

    readonly property int tileSize: 256
    readonly property int minZoom: 3
    readonly property int maxZoom: 18
    readonly property real effectiveLat: fixedOriginEnabled && isFinite(fixedOriginLat) ? fixedOriginLat : lat
    readonly property real effectiveLng: fixedOriginEnabled && isFinite(fixedOriginLng) ? fixedOriginLng : lng
    readonly property int tileColumns: Math.max(3, Math.ceil(width / tileSize) + 2)
    readonly property int tileRows: Math.max(3, Math.ceil(height / tileSize) + 2)
    readonly property int tileCount: tileColumns * tileRows
    readonly property int tilesPerAxis: Math.max(1, Math.pow(2, renderCameraZoom))
    readonly property real renderWorldX: lngToWorldX(renderCameraLng, renderCameraZoom)
    readonly property real renderWorldY: latToWorldY(renderCameraLat, renderCameraZoom)
    readonly property real topLeftWorldX: renderWorldX - width / 2
    readonly property real topLeftWorldY: renderWorldY - height / 2
    readonly property int firstTileX: Math.floor(topLeftWorldX / tileSize)
    readonly property int firstTileY: Math.floor(topLeftWorldY / tileSize)

    function hasObjectKeys(value) {
        return !!value && Object.keys(value).length > 0
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function limitedLat(value) {
        return clamp(value, -85.0511, 85.0511)
    }

    function radians(value) {
        return value * Math.PI / 180.0
    }

    function degrees(value) {
        return value * 180.0 / Math.PI
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
        return 2.0 * earthRadius * Math.asin(Math.sqrt(Math.max(0, Math.min(1, h))))
    }

    function headingBetween(aLat, aLng, bLat, bLng) {
        const lat1 = radians(aLat)
        const lat2 = radians(bLat)
        const dLng = radians(bLng - aLng)
        const y = Math.sin(dLng) * Math.cos(lat2)
        const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng)
        return (degrees(Math.atan2(y, x)) + 360.0) % 360.0
    }

    function bearingDelta(a, b) {
        const delta = Math.abs((Number(a) || 0) - (Number(b) || 0)) % 360
        return Math.min(delta, 360 - delta)
    }

    function pointFromBearing(originLat, originLng, bearingDeg, distanceMeters) {
        const earthRadius = 6378137.0
        const angularDistance = distanceMeters / earthRadius
        const bearingRad = radians(bearingDeg || 0)
        const lat1 = radians(originLat)
        const lng1 = radians(originLng)
        const sinLat1 = Math.sin(lat1)
        const cosLat1 = Math.cos(lat1)
        const sinAngular = Math.sin(angularDistance)
        const cosAngular = Math.cos(angularDistance)
        const lat2 = Math.asin(sinLat1 * cosAngular + cosLat1 * sinAngular * Math.cos(bearingRad))
        const lng2 = lng1 + Math.atan2(
            Math.sin(bearingRad) * sinAngular * cosLat1,
            cosAngular - sinLat1 * Math.sin(lat2)
        )
        return {
            lat: degrees(lat2),
            lng: degrees(lng2)
        }
    }

    function lngToWorldX(value, zoomLevel) {
        return ((value + 180.0) / 360.0) * Math.pow(2, zoomLevel) * tileSize
    }

    function latToWorldY(value, zoomLevel) {
        const latClamped = limitedLat(value)
        const sinValue = Math.sin(radians(latClamped))
        const normalizedY = 0.5 - Math.log((1 + sinValue) / (1 - sinValue)) / (4 * Math.PI)
        return normalizedY * Math.pow(2, zoomLevel) * tileSize
    }

    function worldXToLng(value, zoomLevel) {
        return value / (Math.pow(2, zoomLevel) * tileSize) * 360.0 - 180.0
    }

    function worldYToLat(value, zoomLevel) {
        const mercator = Math.PI * (1 - 2 * value / (Math.pow(2, zoomLevel) * tileSize))
        return degrees(Math.atan((Math.exp(mercator) - Math.exp(-mercator)) / 2))
    }

    function wrapTileX(value) {
        const axis = tilesPerAxis
        return ((value % axis) + axis) % axis
    }

    function tileUrlFor(zoomLevel, tileX, tileY) {
        return "https://tile.openstreetmap.org/" + zoomLevel + "/" + tileX + "/" + tileY + ".png"
    }

    function screenPoint(latValue, lngValue) {
        return {
            x: lngToWorldX(lngValue, renderCameraZoom) - topLeftWorldX,
            y: latToWorldY(latValue, renderCameraZoom) - topLeftWorldY
        }
    }

    function effectiveOrigin() {
        return {
            lat: effectiveLat,
            lng: effectiveLng
        }
    }

    function followZoomForSpeed(kph, previewMode) {
        if (previewMode) {
            if (kph >= 70)
                return 17
            if (kph >= 40)
                return 17
            return 18
        }
        if (kph >= 95)
            return 14
        if (kph >= 60)
            return 15
        if (kph >= 28)
            return 16
        return 17
    }

    function lookAheadMeters(kph, previewMode) {
        if (previewMode)
            return clamp(110 + kph * 1.3, 120, 220)
        return clamp(70 + kph * 4.5, 80, 340)
    }

    function fitCameraForRoute() {
        const points = []
        const origin = effectiveOrigin()
        points.push(origin)
        if (destination && isFinite(destination.lat) && isFinite(destination.lng))
            points.push({ lat: destination.lat, lng: destination.lng })
        for (let i = 0; i < routePoints.length; ++i)
            points.push(routePoints[i])

        let minLat = points[0].lat
        let maxLat = points[0].lat
        let minLng = points[0].lng
        let maxLng = points[0].lng

        for (let i = 1; i < points.length; ++i) {
            const point = points[i]
            minLat = Math.min(minLat, point.lat)
            maxLat = Math.max(maxLat, point.lat)
            minLng = Math.min(minLng, point.lng)
            maxLng = Math.max(maxLng, point.lng)
        }

        const availableWidth = Math.max(220, width - 220)
        const availableHeight = Math.max(180, height - 220)
        let bestZoom = minZoom
        for (let z = maxZoom; z >= minZoom; --z) {
            const spanX = Math.abs(lngToWorldX(maxLng, z) - lngToWorldX(minLng, z))
            const spanY = Math.abs(latToWorldY(maxLat, z) - latToWorldY(minLat, z))
            if (spanX <= availableWidth && spanY <= availableHeight) {
                bestZoom = z
                break
            }
        }

        const minX = lngToWorldX(minLng, bestZoom)
        const maxX = lngToWorldX(maxLng, bestZoom)
        const minY = latToWorldY(maxLat, bestZoom)
        const maxY = latToWorldY(minLat, bestZoom)
        const centerX = (minX + maxX) / 2.0
        const centerY = (minY + maxY) / 2.0
        return {
            lat: worldYToLat(centerY, bestZoom),
            lng: worldXToLng(centerX, bestZoom),
            zoom: bestZoom
        }
    }

    function snapshotPixelWidth() {
        return Math.max(320, Math.min(1920, Math.round(width)))
    }

    function snapshotPixelHeight() {
        return Math.max(240, Math.min(1080, Math.round(height)))
    }

    function parseSnapshotCenter(url) {
        const match = /[?&]center=([^&]+)/.exec(String(url || ""))
        if (!match || match.length < 2)
            return null
        const parts = decodeURIComponent(match[1]).split(",")
        if (parts.length < 2)
            return null
        const latValue = Number(parts[0])
        const lngValue = Number(parts[1])
        if (!isFinite(latValue) || !isFinite(lngValue))
            return null
        return {
            lat: latValue,
            lng: lngValue
        }
    }

    function parseSnapshotZoom(url) {
        const match = /[?&]zoom=(\d+)/.exec(String(url || ""))
        if (!match || match.length < 2)
            return NaN
        const zoomValue = Number(match[1])
        return isFinite(zoomValue) ? clamp(Math.round(zoomValue), minZoom, maxZoom) : NaN
    }

    function buildDynamicSnapshotUrl(centerLat, centerLng, zoomLevel) {
        return "https://staticmap.openstreetmap.de/staticmap.php?center="
            + centerLat.toFixed(5)
            + ","
            + centerLng.toFixed(5)
            + "&zoom="
            + clamp(Math.round(zoomLevel), minZoom, maxZoom)
            + "&size="
            + snapshotPixelWidth()
            + "x"
            + snapshotPixelHeight()
            + "&maptype=mapnik"
    }

    function currentSnapshotDescriptor() {
        if (tilePrimary) {
            return {
                url: "",
                lat: cameraLat,
                lng: cameraLng,
                zoom: cameraZoom
            }
        }
        if (snapshotUrl && snapshotUrl.length > 0) {
            const center = parseSnapshotCenter(snapshotUrl)
            const zoomLevel = parseSnapshotZoom(snapshotUrl)
            return {
                url: snapshotUrl,
                lat: center ? center.lat : cameraLat,
                lng: center ? center.lng : cameraLng,
                zoom: isFinite(zoomLevel) ? zoomLevel : cameraZoom
            }
        }
        return {
            url: buildDynamicSnapshotUrl(cameraLat, cameraLng, cameraZoom),
            lat: cameraLat,
            lng: cameraLng,
            zoom: cameraZoom
        }
    }

    function requestSnapshotRefresh(force) {
        if (tilePrimary)
            return
        if (width <= 0 || height <= 0)
            return
        const descriptor = currentSnapshotDescriptor()
        if (!descriptor.url.length)
            return
        if (!force && descriptor.url === pendingSnapshotUrl)
            return
        if (!force && descriptor.url === lastGoodSnapshotUrl)
            return

        pendingSnapshotUrl = descriptor.url
        pendingSnapshotLat = descriptor.lat
        pendingSnapshotLng = descriptor.lng
        pendingSnapshotZoom = descriptor.zoom
        snapshotProbe.source = ""
        snapshotProbe.source = descriptor.url
    }

    function setStatus(primary, secondary, tone) {
        statusText = primary
        detailText = secondary
        if (tone === "danger")
            statusColor = "#ff8c82"
        else if (tone === "warn")
            statusColor = "#ffd083"
        else if (tone === "ok")
            statusColor = "#7ef0be"
        else
            statusColor = "#9fb2c1"
    }

    function formatDistance(meters) {
        if (!isFinite(meters) || meters <= 0)
            return ""
        if (meters >= 1000)
            return (meters / 1000.0).toFixed(meters >= 10000 ? 0 : 1) + " km"
        return Math.round(meters) + " m"
    }

    function formatDuration(seconds) {
        if (!isFinite(seconds) || seconds <= 0)
            return ""
        const mins = Math.round(seconds / 60.0)
        if (mins < 60)
            return mins + " min"
        const hours = Math.floor(mins / 60)
        const remMins = mins % 60
        return hours + " h " + remMins + " min"
    }

    function buildRouteProfile(points) {
        const out = []
        let cumulative = 0
        for (let i = 0; i < points.length; ++i) {
            if (i > 0)
                cumulative += metersBetween(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng)
            out.push({
                lat: points[i].lat,
                lng: points[i].lng,
                meters: cumulative
            })
        }
        return out
    }

    function syncFromNavigationState() {
        if (!useExternalNavigation)
            return

        const payload = resolvedRouteOverlay || {}
        const route = payload.route || {}
        const geometry = route.geometry || {}
        const coords = geometry.coordinates || []
        const nextPoints = []
        for (let i = 0; i < coords.length; ++i) {
            const coord = coords[i]
            if (!coord || coord.length < 2)
                continue
            const pointLat = Number(coord[1])
            const pointLng = Number(coord[0])
            if (!isFinite(pointLat) || !isFinite(pointLng))
                continue
            nextPoints.push({ lat: pointLat, lng: pointLng })
        }

        routePoints = nextPoints
        routeProfile = buildRouteProfile(nextPoints)
        routeDistanceMeters = Number(route.distanceMeters || 0)
        routeDurationSeconds = Number(route.durationSeconds || 0)

        const destinationPayload = payload.destination || {}
        destination = hasObjectKeys(destinationPayload) ? {
            lat: Number(destinationPayload.lat),
            lng: Number(destinationPayload.lng),
            label: destinationPayload.label || "",
            primary: destinationPayload.primary || destinationPayload.label || "Destination",
            secondary: destinationPayload.secondary || ""
        } : null

        followEnabled = payload.followEnabled !== false
        previewRunning = false
        previewProgressMeters = Number((payload.progress || {}).distanceMeters || 0)
        const camera = resolvedCameraBucket || {}
        holdingOverview = !!camera.overview
        const overviewKey = String(route.distanceMeters || 0) + "|" + String(destinationPayload.label || "") + "|" + String(camera.mode || "")

        const guidance = resolvedGuidanceBucket || {}
        const banner = guidance.banner || {}
        const connectivity = resolvedConnectivityBucket || {}
        const providerStatus = String(guidance.providerStatus || payload.providerStatus || "offline")
        const networkStatus = String(guidance.networkStatus || payload.networkStatus || "connecting_hotspot")
        const vehicle = resolvedVehicleBucket || {}

        if (!vehicle.gpsReady) {
            setStatus(
                "GPS weak",
                vehicle.usingLastKnown
                    ? "Using last known position."
                    : "Waiting for GPS fix.",
                "warn"
            )
        } else if (!connectivity.hotspotConnected || !connectivity.hotspotHasIpLease) {
            setStatus("Connecting hotspot", "Waiting for connection.", "warn")
        } else if (!connectivity.internetOk) {
            setStatus("Offline", "Showing cached guidance.", "warn")
        } else if (providerStatus === "search_degraded") {
            setStatus("Search limited", banner.secondary || "Fallback search active.", "warn")
        } else if (providerStatus === "route_degraded" || networkStatus === "degraded") {
            setStatus("Routing limited", banner.secondary || "Using cached guidance.", "warn")
        } else if (networkStatus === "routing") {
            setStatus("Refreshing route", banner.secondary || "Routing with live GPS.", "default")
        } else if (networkStatus === "searching") {
            setStatus("Searching...", banner.secondary || "", "default")
        } else if (banner.primary) {
            setStatus(banner.primary, banner.secondary || "", "ok")
        } else if (destination && routePoints.length > 1) {
            setStatus(formatDistance(routeDistanceMeters), formatDuration(routeDurationSeconds), "ok")
        } else {
            setStatus("GPS live", "Search destination", "default")
        }

        if (holdingOverview && routePoints.length > 1 && overviewKey !== lastOverviewKey) {
            lastOverviewKey = overviewKey
            showRouteOverview()
        } else {
            if (!holdingOverview)
                lastOverviewKey = ""
            refreshCamera()
        }
    }

    function sampleRouteAt(distanceMeters) {
        if (!routeProfile.length) {
            return {
                lat: effectiveLat,
                lng: effectiveLng,
                bearing: bearing
            }
        }

        const clampedDistance = clamp(distanceMeters, 0, routeDistanceMeters)
        for (let i = 1; i < routeProfile.length; ++i) {
            const prev = routeProfile[i - 1]
            const next = routeProfile[i]
            if (clampedDistance <= next.meters) {
                const span = Math.max(0.1, next.meters - prev.meters)
                const t = clamp((clampedDistance - prev.meters) / span, 0, 1)
                return {
                    lat: prev.lat + (next.lat - prev.lat) * t,
                    lng: prev.lng + (next.lng - prev.lng) * t,
                    bearing: headingBetween(prev.lat, prev.lng, next.lat, next.lng)
                }
            }
        }

        const last = routeProfile[routeProfile.length - 1]
        const beforeLast = routeProfile[Math.max(0, routeProfile.length - 2)]
        return {
            lat: last.lat,
            lng: last.lng,
            bearing: headingBetween(beforeLast.lat, beforeLast.lng, last.lat, last.lng)
        }
    }

    function refreshCamera() {
        const nowMs = Date.now()
        if (lowEffectMode && lastCameraRefreshAtMs > 0
                && (nowMs - lastCameraRefreshAtMs) < cameraRefreshIntervalMs) {
            cameraRefreshTimer.restart()
            return
        }
        lastCameraRefreshAtMs = nowMs

        if (holdingOverview && routePoints.length > 1) {
            if (!lastGoodSnapshotUrl.length)
                requestSnapshotRefresh(true)
            routeCanvas.requestPaint()
            return
        }

        if (followEnabled) {
            const zoomLevel = routePoints.length > 1
                ? followZoomForSpeed(cameraSpeedKph, previewRunning)
                : Math.max(16, followZoomForSpeed(cameraSpeedKph, previewRunning))
            const lookAheadPoint = pointFromBearing(vehicleLat, vehicleLng, vehicleBearing, lookAheadMeters(cameraSpeedKph, previewRunning))
            cameraLat = lookAheadPoint.lat
            cameraLng = lookAheadPoint.lng
            cameraZoom = clamp(zoomLevel, minZoom, maxZoom)
        } else if (routePoints.length <= 1) {
            cameraLat = vehicleLat
            cameraLng = vehicleLng
            cameraZoom = clamp(Math.max(16, followZoomForSpeed(cameraSpeedKph, previewRunning)), minZoom, maxZoom)
        }

        if (!lastGoodSnapshotUrl.length)
            requestSnapshotRefresh(true)
        routeCanvas.requestPaint()
        if (typeof performanceMetrics !== "undefined" && performanceMetrics)
            performanceMetrics.recordPaint("map.cameraRefresh")
    }

    function scheduleCameraRefresh(force) {
        if (force) {
            cameraRefreshTimer.restart()
            return
        }

        const poseLat = previewRunning ? previewLat : resolvedVehicleLat
        const poseLng = previewRunning ? previewLng : resolvedVehicleLng
        const poseBearing = previewRunning ? previewBearing : resolvedVehicleBearing
        const poseSpeed = previewRunning ? previewSpeedKph : resolvedSpeedKph

        if (!isFinite(lastCameraRequestLat) || !isFinite(lastCameraRequestLng)) {
            lastCameraRequestLat = poseLat
            lastCameraRequestLng = poseLng
            lastCameraRequestBearing = poseBearing
            lastCameraRequestSpeedKph = poseSpeed
            cameraRefreshTimer.restart()
            return
        }

        const movedMeters = metersBetween(lastCameraRequestLat, lastCameraRequestLng, poseLat, poseLng)
        const bearingMoved = bearingDelta(lastCameraRequestBearing, poseBearing)
        const speedDelta = Math.abs((Number(lastCameraRequestSpeedKph) || 0) - (Number(poseSpeed) || 0))
        if (movedMeters >= 6 || bearingMoved >= 6 || speedDelta >= 4) {
            lastCameraRequestLat = poseLat
            lastCameraRequestLng = poseLng
            lastCameraRequestBearing = poseBearing
            lastCameraRequestSpeedKph = poseSpeed
            cameraRefreshTimer.restart()
        }
    }

    function showRouteOverview() {
        if (routePoints.length <= 1) {
            holdingOverview = false
            refreshCamera()
            return
        }
        const fit = fitCameraForRoute()
        holdingOverview = true
        cameraLat = fit.lat
        cameraLng = fit.lng
        cameraZoom = fit.zoom
        routeCanvas.requestPaint()
        if (followEnabled)
            overviewTimer.restart()
    }

    function stopPreviewPlayback() {
        previewRunning = false
        previewTimer.stop()
    }

    function updatePreviewState() {
        const sample = sampleRouteAt(previewProgressMeters)
        previewLat = sample.lat
        previewLng = sample.lng
        previewBearing = sample.bearing
        const remaining = Math.max(0, routeDistanceMeters - previewProgressMeters)
        const remainingSeconds = previewSpeedKph > 0 ? remaining / (previewSpeedKph / 3.6) : 0
        setStatus(
            "Previewing route at 10x.",
            formatDistance(remaining) + " remaining | " + formatDuration(remainingSeconds),
            "ok"
        )
    }

    function startPreviewPlayback() {
        if (!fixedOriginEnabled || routeProfile.length <= 1)
            return
        previewRunning = true
        previewProgressMeters = 0
        updatePreviewState()
        previewTimer.start()
        refreshCamera()
    }

    function clearRoute() {
        if (useExternalNavigation) {
            syncFromNavigationState()
            return
        }
        ++searchToken
        ++routeToken
        destination = null
        routePoints = []
        routeProfile = []
        routeDistanceMeters = 0
        routeDurationSeconds = 0
        previewProgressMeters = 0
        previewSpeedKph = 0
        lastRouteOriginLat = NaN
        lastRouteOriginLng = NaN
        lastRouteAtMs = 0
        holdingOverview = false
        overviewTimer.stop()
        stopPreviewPlayback()
        setStatus(
            fixedOriginEnabled ? "Fallback origin" : "GPS live",
            "Search destination",
            "default"
        )
        refreshCamera()
    }

    function setFollowEnabled(enabled) {
        followEnabled = !!enabled
        if (followEnabled) {
            holdingOverview = false
            overviewTimer.stop()
            refreshCamera()
        }
    }

    function parsePhotonCandidates(payload) {
        const origin = effectiveOrigin()
        const features = (payload && payload.features) || []
        const ranked = []
        for (let i = 0; i < features.length; ++i) {
            const feature = features[i]
            const props = feature.properties || {}
            const coords = (feature.geometry && feature.geometry.coordinates) || []
            const itemLat = Number(coords[1])
            const itemLng = Number(coords[0])
            if (!isFinite(itemLat) || !isFinite(itemLng))
                continue
            const labelParts = [props.name, props.street, props.city, props.state, props.country].filter(Boolean)
            ranked.push({
                label: labelParts.join(", "),
                primary: props.name || props.street || props.city || "Destination",
                secondary: [props.street, props.city, props.state, props.country].filter(Boolean).join(", "),
                lat: itemLat,
                lng: itemLng,
                distanceMeters: metersBetween(origin.lat, origin.lng, itemLat, itemLng)
            })
        }
        ranked.sort(function(a, b) { return a.distanceMeters - b.distanceMeters })
        return ranked
    }

    function parseNominatimCandidates(items) {
        const origin = effectiveOrigin()
        const ranked = []
        for (let i = 0; i < (items || []).length; ++i) {
            const item = items[i]
            const itemLat = Number(item.lat)
            const itemLng = Number(item.lon)
            if (!isFinite(itemLat) || !isFinite(itemLng))
                continue
            const label = String(item.display_name || "")
            const parts = label.split(",")
            ranked.push({
                label: label,
                primary: parts.slice(0, 2).join(", ").trim() || label,
                secondary: parts.slice(2).join(", ").trim() || "OpenStreetMap result",
                lat: itemLat,
                lng: itemLng,
                distanceMeters: metersBetween(origin.lat, origin.lng, itemLat, itemLng)
            })
        }
        ranked.sort(function(a, b) { return a.distanceMeters - b.distanceMeters })
        return ranked
    }

    function searchAddress(query) {
        if (useExternalNavigation)
            return
        const trimmed = String(query || "").trim()
        if (!trimmed.length) {
            setStatus("Enter destination", "", "warn")
            return
        }

        const token = ++searchToken
        setStatus("Searching...", "", "default")

        const photonXhr = new XMLHttpRequest()
        photonXhr.onreadystatechange = function() {
            if (photonXhr.readyState !== XMLHttpRequest.DONE || token !== searchToken)
                return

            if (photonXhr.status >= 200 && photonXhr.status < 300) {
                try {
                    const photonMatches = parsePhotonCandidates(JSON.parse(photonXhr.responseText))
                    if (photonMatches.length) {
                        destination = photonMatches[0]
                        computeRoute(true)
                        return
                    }
                } catch (err) {
                }
            }

            const nominatimXhr = new XMLHttpRequest()
            nominatimXhr.onreadystatechange = function() {
                if (nominatimXhr.readyState !== XMLHttpRequest.DONE || token !== searchToken)
                    return

                if (nominatimXhr.status < 200 || nominatimXhr.status >= 300) {
                    setStatus("Destination search failed.", "Check internet access for geocoding.", "danger")
                    return
                }

                try {
                    const nominatimMatches = parseNominatimCandidates(JSON.parse(nominatimXhr.responseText))
                    if (!nominatimMatches.length) {
                        setStatus("Destination not found.", "Try a more specific address.", "warn")
                        return
                    }
                    destination = nominatimMatches[0]
                    computeRoute(true)
                } catch (err) {
                    setStatus("Destination search failed.", "Check internet access for geocoding.", "danger")
                }
            }
            nominatimXhr.open("GET", "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=5&q=" + encodeURIComponent(trimmed))
            nominatimXhr.send()
        }
        photonXhr.open("GET", "https://photon.komoot.io/api/?limit=6&q=" + encodeURIComponent(trimmed))
        photonXhr.send()
    }

    function computeRoute(force) {
        if (useExternalNavigation)
            return
        if (!destination || !isFinite(destination.lat) || !isFinite(destination.lng)) {
            setStatus("Waiting for route destination.", "Search for a destination first.", "warn")
            return
        }

        const origin = effectiveOrigin()
        const now = Date.now()
        if (!force && isFinite(lastRouteOriginLat) && isFinite(lastRouteOriginLng)) {
            const moved = metersBetween(origin.lat, origin.lng, lastRouteOriginLat, lastRouteOriginLng)
            if (moved < 30 && (now - lastRouteAtMs) < 5000)
                return
        }

        const token = ++routeToken
        setStatus(
            "Calculating route...",
            fixedOriginEnabled ? "Routing from fallback origin." : "Routing from live GPS.",
            "default"
        )

        const url = "https://router.project-osrm.org/route/v1/driving/"
            + origin.lng + "," + origin.lat + ";"
            + destination.lng + "," + destination.lat
            + "?overview=full&geometries=geojson&steps=true&alternatives=false"

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || token !== routeToken)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                routePoints = []
                routeProfile = []
                routeDistanceMeters = 0
                routeDurationSeconds = 0
                holdingOverview = false
                overviewTimer.stop()
                stopPreviewPlayback()
                setStatus("Route unavailable.", "Check internet access for routing.", "danger")
                refreshCamera()
                return
            }

            try {
                const payload = JSON.parse(xhr.responseText)
                const route = payload.routes && payload.routes.length ? payload.routes[0] : null
                const coords = route && route.geometry ? route.geometry.coordinates : null
                if (!route || !coords || coords.length < 2)
                    throw new Error("no route")

                const points = []
                for (let i = 0; i < coords.length; ++i) {
                    const point = coords[i]
                    points.push({
                        lat: Number(point[1]),
                        lng: Number(point[0])
                    })
                }

                routePoints = points
                routeProfile = buildRouteProfile(points)
                routeDistanceMeters = Number(route.distance) || 0
                routeDurationSeconds = Number(route.duration) || 0
                previewSpeedKph = routeDurationSeconds > 0
                    ? clamp(routeDistanceMeters / routeDurationSeconds * 3.6 * 10.0, 18, 260)
                    : 60
                previewProgressMeters = 0
                stopPreviewPlayback()
                const start = sampleRouteAt(0)
                previewLat = start.lat
                previewLng = start.lng
                previewBearing = start.bearing
                lastRouteOriginLat = origin.lat
                lastRouteOriginLng = origin.lng
                lastRouteAtMs = Date.now()
                setStatus(
                    fixedOriginEnabled ? "Route ready for preview." : "Route ready.",
                    formatDistance(routeDistanceMeters) + " | " + formatDuration(routeDurationSeconds),
                    "ok"
                )
                showRouteOverview()
            } catch (err) {
                routePoints = []
                routeProfile = []
                routeDistanceMeters = 0
                routeDurationSeconds = 0
                holdingOverview = false
                overviewTimer.stop()
                stopPreviewPlayback()
                setStatus("Route unavailable.", "Check internet access for routing.", "danger")
                refreshCamera()
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    onNavigationStateChanged: syncFromNavigationState()
    onMapVehiclePoseChanged: {
        if (useExternalNavigation && !previewRunning)
            scheduleCameraRefresh(false)
    }
    onMapCameraHintsChanged: {
        if (useExternalNavigation)
            refreshCamera()
    }
    onMapRouteOverlayChanged: syncFromNavigationState()
    onMapGuidanceBannerChanged: syncFromNavigationState()
    onMapConnectivityChanged: syncFromNavigationState()
    onLatChanged: {
        scheduleCameraRefresh(false)
        if (!useExternalNavigation && destination && !fixedOriginEnabled)
            rerouteTimer.restart()
    }
    onLngChanged: {
        scheduleCameraRefresh(false)
        if (!useExternalNavigation && destination && !fixedOriginEnabled)
            rerouteTimer.restart()
    }
    onBearingChanged: if (!previewRunning) scheduleCameraRefresh(false)
    onSpeedKphChanged: if (!previewRunning) scheduleCameraRefresh(false)
    onFixedOriginEnabledChanged: {
        if (useExternalNavigation) {
            syncFromNavigationState()
        } else if (destination)
            computeRoute(true)
        else
            clearRoute()
    }
    onFixedOriginLatChanged: {
        if (useExternalNavigation) {
            syncFromNavigationState()
        } else if (fixedOriginEnabled && destination)
            computeRoute(true)
    }
    onFixedOriginLngChanged: {
        if (useExternalNavigation) {
            syncFromNavigationState()
        } else if (fixedOriginEnabled && destination)
            computeRoute(true)
    }
    onWidthChanged: {
        if (holdingOverview && routePoints.length > 1)
            showRouteOverview()
        else
            scheduleCameraRefresh(true)
        requestSnapshotRefresh(true)
    }
    onHeightChanged: {
        if (holdingOverview && routePoints.length > 1)
            showRouteOverview()
        else
            scheduleCameraRefresh(true)
        requestSnapshotRefresh(true)
    }
    onSnapshotUrlChanged: requestSnapshotRefresh(true)

    Component.onCompleted: {
        if (useExternalNavigation)
            syncFromNavigationState()
        else
            clearRoute()
        renderCameraLat = isFinite(cameraLat) ? cameraLat : renderCameraLat
        renderCameraLng = isFinite(cameraLng) ? cameraLng : renderCameraLng
        renderCameraZoom = clamp(cameraZoom, minZoom, maxZoom)
        lastCameraRequestLat = renderCameraLat
        lastCameraRequestLng = renderCameraLng
        lastCameraRequestBearing = resolvedVehicleBearing
        lastCameraRequestSpeedKph = resolvedSpeedKph
        requestSnapshotRefresh(true)
    }

    Timer {
        id: overviewTimer
        interval: 1800
        repeat: false
        onTriggered: {
            holdingOverview = false
            if (fixedOriginEnabled && routeProfile.length > 1 && followEnabled)
                startPreviewPlayback()
            else
                refreshCamera()
        }
    }

    Timer {
        id: cameraRefreshTimer
        interval: Math.max(250, Number(root.cameraRefreshIntervalMs) || 1000)
        repeat: false
        onTriggered: root.refreshCamera()
    }

    Timer {
        id: rerouteTimer
        interval: Math.max(250, Number(root.rerouteIntervalMs) || 5000)
        repeat: false
        onTriggered: root.computeRoute(false)
    }

    Timer {
        id: snapshotRefreshTimer
        interval: Math.max(500, root.refreshMs)
        repeat: true
        running: root.visible && !root.tilePrimary && root.refreshMs > 0
        onTriggered: root.requestSnapshotRefresh(false)
    }

    Timer {
        id: previewTimer
        interval: root.previewIntervalMs
        repeat: true
        onTriggered: {
            if (!previewRunning || routeDistanceMeters <= 0) {
                stop()
                return
            }

            const metersPerSecond = previewSpeedKph / 3.6
            previewProgressMeters = Math.min(routeDistanceMeters, previewProgressMeters + metersPerSecond * (interval / 1000.0))
            updatePreviewState()

            if (previewProgressMeters >= routeDistanceMeters - 1) {
                previewProgressMeters = routeDistanceMeters
                updatePreviewState()
                stopPreviewPlayback()
                setStatus("Destination reached.", destination ? destination.primary : "Preview complete.", "ok")
            }

            refreshCamera()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#101418"
        border.color: "#2a333c"
        border.width: 2
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "#0d1720"
        }

        Image {
            id: snapshotImage
            anchors.fill: parent
            visible: !root.tilePrimary && root.lastGoodSnapshotUrl.length > 0
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            smooth: true
            source: root.lastGoodSnapshotUrl
        }

        Repeater {
            model: root.tileCount
            visible: root.tilePrimary || root.lastGoodSnapshotUrl.length === 0 || root.snapshotLoadFailed

            delegate: Image {
                readonly property int tileColumn: index % root.tileColumns
                readonly property int tileRow: Math.floor(index / root.tileColumns)
                readonly property int rawTileX: root.firstTileX + tileColumn
                readonly property int rawTileY: root.firstTileY + tileRow
                readonly property bool validTileY: rawTileY >= 0 && rawTileY < root.tilesPerAxis
                x: Math.round(rawTileX * root.tileSize - root.topLeftWorldX)
                y: Math.round(rawTileY * root.tileSize - root.topLeftWorldY)
                width: root.tileSize
                height: root.tileSize
                visible: parent.visible && validTileY
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                smooth: false
                source: validTileY ? root.tileUrlFor(root.renderCameraZoom, root.wrapTileX(rawTileX), rawTileY) : ""
            }
        }

        Image {
            id: snapshotProbe
            visible: false
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectCrop
            source: ""

            onStatusChanged: {
                if (source !== root.pendingSnapshotUrl)
                    return

                if (status === Image.Ready) {
                    root.lastGoodSnapshotUrl = source
                    root.renderCameraLat = root.pendingSnapshotLat
                    root.renderCameraLng = root.pendingSnapshotLng
                    root.renderCameraZoom = root.pendingSnapshotZoom
                    root.snapshotLoadFailed = false
                    root.snapshotFailureText = ""
                    routeCanvas.requestPaint()
                } else if (status === Image.Error) {
                    if (!root.lastGoodSnapshotUrl.length) {
                        root.renderCameraLat = root.pendingSnapshotLat
                        root.renderCameraLng = root.pendingSnapshotLng
                        root.renderCameraZoom = root.pendingSnapshotZoom
                    }
                    root.snapshotLoadFailed = true
                    root.snapshotFailureText = root.lastGoodSnapshotUrl.length > 0
                        ? "Map update unavailable"
                        : "Map unavailable"
                }
            }
        }

        Canvas {
            id: routeCanvas
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                if (root.routePoints.length > 1) {
                    function drawStroke(lineWidth, color) {
                        ctx.beginPath()
                        for (let i = 0; i < root.routePoints.length; ++i) {
                            const point = root.routePoints[i]
                            const screen = root.screenPoint(point.lat, point.lng)
                            if (i === 0)
                                ctx.moveTo(screen.x, screen.y)
                            else
                                ctx.lineTo(screen.x, screen.y)
                        }
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.lineWidth = lineWidth
                        ctx.strokeStyle = color
                        ctx.stroke()
                    }

                    drawStroke(16, "rgba(255,255,255,0.30)")
                    drawStroke(10, "rgba(40,88,152,0.28)")
                    drawStroke(6, "#3b8cff")
                }

                if (root.destination && isFinite(root.destination.lat) && isFinite(root.destination.lng)) {
                    const destinationPoint = root.screenPoint(root.destination.lat, root.destination.lng)
                    ctx.fillStyle = "rgba(255,170,72,0.95)"
                    ctx.strokeStyle = "rgba(255,255,255,0.95)"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.arc(destinationPoint.x, destinationPoint.y, 8, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.stroke()
                }

                const vehiclePoint = root.screenPoint(root.vehicleLat, root.vehicleLng)
                ctx.save()
                ctx.translate(vehiclePoint.x, vehiclePoint.y)
                ctx.rotate((root.vehicleBearing || 0) * Math.PI / 180.0)
                ctx.fillStyle = "#3b8cff"
                ctx.strokeStyle = "rgba(255,255,255,0.98)"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(0, -14)
                ctx.lineTo(9, 11)
                ctx.lineTo(-9, 11)
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
                ctx.restore()

                if (typeof performanceMetrics !== "undefined" && performanceMetrics)
                    performanceMetrics.recordPaint("map.routeOverlay")
            }
        }

        Rectangle {
            visible: root.snapshotLoadFailed
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            radius: 14
            color: "#f9f3e6"
            border.width: 1
            border.color: "#d8c7a4"
            height: 30
            width: degradedText.implicitWidth + 20

            Text {
                id: degradedText
                anchors.centerIn: parent
                text: root.snapshotFailureText
                color: "#6a4e1f"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 14
            width: Math.min(parent.width - 44, 460)
            height: root.detailText.length > 0 ? 70 : 50
            radius: 20
            color: "#f4ffffff"
            border.width: 1
            border.color: "#c7d6e6"

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 3

                Text {
                    text: root.statusText
                    color: "#10243a"
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    elide: Text.ElideRight
                }

                Text {
                    visible: root.detailText.length > 0
                    text: root.detailText
                    color: root.statusColor
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    elide: Text.ElideRight
                }
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            radius: 14
            color: "#f5ffffff"
            border.width: 1
            border.color: "#c7d6e6"
            height: 34
            width: followText.implicitWidth + 24

            Text {
                id: followText
                anchors.centerIn: parent
                color: "#24415f"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                text: root.holdingOverview
                    ? "OVERVIEW"
                    : (root.previewRunning ? "PREVIEW" : (root.followEnabled ? "FOLLOW" : "FREE"))
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            text: "\u00a9 OpenStreetMap"
            color: "#6d8297"
            font.pixelSize: 11
        }
    }
}
