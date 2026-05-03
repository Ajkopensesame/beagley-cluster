import QtQuick 2.15

import BeagleY 1.0

Item {
    id: root
    anchors.fill: parent

    property real lat: -27.4698
    property real lng: 153.0251
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
    property bool interactionEnabled: true
    readonly property bool embeddedMapThrottle: (typeof BEAGLEY_RENDER_PROFILE !== "undefined"
        && String(BEAGLEY_RENDER_PROFILE) === "embedded")

    readonly property var resolvedVehicleBucket: hasKeys(mapVehiclePose)
        ? mapVehiclePose
        : ((navigationState && navigationState.vehiclePose) ? navigationState.vehiclePose : ({}))
    readonly property var resolvedCameraBucket: hasKeys(mapCameraHints)
        ? mapCameraHints
        : ((navigationState && navigationState.camera) ? navigationState.camera : ({}))
    readonly property var resolvedRouteBucket: hasKeys(mapRouteOverlay)
        ? mapRouteOverlay
        : (navigationState || ({}))
    readonly property real resolvedLat: fixedOriginEnabled && isFinite(Number(fixedOriginLat))
        ? Number(fixedOriginLat)
        : firstFinite([resolvedVehicleBucket.lat, lat, -27.4698])
    readonly property real resolvedLng: fixedOriginEnabled && isFinite(Number(fixedOriginLng))
        ? Number(fixedOriginLng)
        : firstFinite([resolvedVehicleBucket.lng, lng, 153.0251])
    readonly property real resolvedBearing: firstFinite([resolvedVehicleBucket.bearing, bearing, 0])
    readonly property real resolvedSpeedKph: Math.max(0, firstFinite([resolvedVehicleBucket.speedKph, speedKph, 0]))
    readonly property real resolvedZoom: isFinite(Number(zoom))
        ? clamp(Number(zoom), 3, 19)
        : computeZoom()
    readonly property var resolvedRoutePath: buildRoutePath()
    readonly property bool vehiclePoseValid: isFinite(Number(resolvedLat)) && isFinite(Number(resolvedLng))
    readonly property bool guidanceCameraActive: !fixedOriginEnabled
        && vehiclePoseValid
        && !!resolvedRouteBucket.guidanceStarted
    readonly property real resolvedMapBearing: guidanceCameraActive ? normalizeBearing(resolvedBearing) : 0
    readonly property real resolvedVehicleBearing: normalizeBearing(resolvedBearing - resolvedMapBearing)
    readonly property real resolvedLookAheadMeters: computeGuidanceLookAheadMeters()
    readonly property var resolvedCameraCenter: guidanceCameraActive
        ? pointFromBearing(resolvedLat, resolvedLng, resolvedBearing, resolvedLookAheadMeters)
        : ({ lat: resolvedLat, lng: resolvedLng })
    readonly property real resolvedCameraLat: {
        const center = resolvedCameraCenter || ({})
        const value = Number(center.lat)
        return isFinite(value) ? value : resolvedLat
    }
    readonly property real resolvedCameraLng: {
        const center = resolvedCameraCenter || ({})
        const value = Number(center.lng)
        return isFinite(value) ? value : resolvedLng
    }
    readonly property bool vehicleVisibleResolved: {
        if (!vehiclePoseValid)
            return false
        if (resolvedVehicleBucket.gpsReady === undefined && resolvedVehicleBucket.usingLastKnown === undefined)
            return true
        return !!resolvedVehicleBucket.gpsReady || !!resolvedVehicleBucket.usingLastKnown
    }

    property real nativeCenterLat: resolvedCameraLat
    property real nativeCenterLng: resolvedCameraLng
    property real nativeMapBearing: resolvedMapBearing
    property real nativeVehicleLat: resolvedLat
    property real nativeVehicleLng: resolvedLng
    property real nativeBearing: resolvedVehicleBearing
    property real nativeZoom: resolvedZoom
    property bool nativeVehicleVisible: vehicleVisibleResolved
    property var nativeRoutePath: resolvedRoutePath
    readonly property string resolvedTileUrlTemplate: tileUrlTemplate.length > 0
        ? tileUrlTemplate
        : "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    readonly property int nativeZoomAnimationMs: {
        const hinted = Number(resolvedCameraBucket.zoomAnimationMs)
        if (isFinite(hinted))
            return Math.max(120, Math.min(1800, Math.round(hinted)))
        return embeddedMapThrottle ? 760 : 420
    }

    function hasKeys(value) {
        return !!value && Object.keys(value).length > 0
    }

    function firstFinite(values) {
        for (var i = 0; i < values.length; ++i) {
            const number = Number(values[i])
            if (isFinite(number))
                return number
        }
        return NaN
    }

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function radians(value) {
        return Number(value) * Math.PI / 180.0
    }

    function degrees(value) {
        return Number(value) * 180.0 / Math.PI
    }

    function normalizeBearing(value) {
        var normalized = Number(value) % 360
        if (normalized < 0)
            normalized += 360
        return normalized
    }

    function pointFromBearing(originLat, originLng, bearingDeg, distanceMeters) {
        const earthRadius = 6378137.0
        const angularDistance = Number(distanceMeters || 0) / earthRadius
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

    function metersPerPixel(latValue, zoomValue) {
        const earthCircumferenceMeters = 40075016.686
        const clampedLat = clamp(Number(latValue), -85.0, 85.0)
        return Math.cos(radians(clampedLat)) * earthCircumferenceMeters
            / (256.0 * Math.pow(2.0, Number(zoomValue)))
    }

    function computeGuidanceLookAheadMeters() {
        if (!guidanceCameraActive)
            return 0

        const hinted = Number(resolvedCameraBucket.lookAheadMeters)
        const targetVehicleY = 0.84
        const anchorOffsetPx = Math.max(0, (targetVehicleY - 0.5) * Math.max(1, height))
        const anchorMeters = anchorOffsetPx * metersPerPixel(resolvedLat, resolvedZoom)
        return clamp(Math.max(isFinite(hinted) ? hinted : 0, anchorMeters), 40, 900)
    }

    function angleDeltaDegrees(current, target) {
        var delta = (target - current) % 360
        if (delta > 180)
            delta -= 360
        else if (delta < -180)
            delta += 360
        return delta
    }

    function computeZoom() {
        const hintedZoom = Number(resolvedCameraBucket.zoom)
        if (isFinite(hintedZoom))
            return clamp(hintedZoom, 3, 19)

        if (resolvedSpeedKph >= 100)
            return 14.4
        if (resolvedSpeedKph >= 70)
            return 15.1
        if (resolvedSpeedKph >= 40)
            return 15.8
        if (resolvedSpeedKph >= 20)
            return 16.5
        return 17.2
    }

    function buildRoutePath() {
        const route = resolvedRouteBucket.route || ({})
        const geometry = route.geometry || ({})
        const coordinates = geometry.coordinates || []
        var path = []
        for (var i = 0; i < coordinates.length; ++i) {
            const point = coordinates[i]
            if (!point || point.length < 2)
                continue
            const lngValue = Number(point[0])
            const latValue = Number(point[1])
            if (!isFinite(latValue) || !isFinite(lngValue))
                continue
            path.push({
                lat: latValue,
                lng: lngValue
            })
        }
        return path
    }

    function searchAddress(query) {
        if (typeof navigation !== "undefined" && navigation && navigation.search)
            navigation.search(query)
    }

    function clearRoute() {
        if (typeof navigation !== "undefined" && navigation && navigation.clearRoute)
            navigation.clearRoute()
    }

    function setFollowEnabled(enabled) {
        if (typeof navigation !== "undefined" && navigation && navigation.setFollowEnabled)
            navigation.setFollowEnabled(enabled)
    }

    function needsEmbeddedViewSync() {
        if (!embeddedMapThrottle)
            return true

        if (!isFinite(Number(nativeCenterLat)) || !isFinite(Number(nativeCenterLng)))
            return true

        if (Math.abs(Number(resolvedCameraLat) - Number(nativeCenterLat)) >= 0.00005)
            return true
        if (Math.abs(Number(resolvedCameraLng) - Number(nativeCenterLng)) >= 0.00005)
            return true
        if (Math.abs(Number(resolvedLat) - Number(nativeVehicleLat)) >= 0.00005)
            return true
        if (Math.abs(Number(resolvedLng) - Number(nativeVehicleLng)) >= 0.00005)
            return true
        if (Math.abs(angleDeltaDegrees(Number(nativeMapBearing), Number(resolvedMapBearing))) >= 3.0)
            return true
        if (Math.abs(angleDeltaDegrees(Number(nativeBearing), Number(resolvedVehicleBearing))) >= 3.0)
            return true
        if (Math.abs(Number(resolvedZoom) - Number(nativeZoom)) >= 0.20)
            return true
        if (nativeVehicleVisible !== vehicleVisibleResolved)
            return true
        return false
    }

    function syncNativeView(force) {
        if (!force && !needsEmbeddedViewSync())
            return
        nativeCenterLat = resolvedCameraLat
        nativeCenterLng = resolvedCameraLng
        nativeMapBearing = resolvedMapBearing
        nativeVehicleLat = resolvedLat
        nativeVehicleLng = resolvedLng
        nativeBearing = resolvedVehicleBearing
        nativeZoom = resolvedZoom
        nativeVehicleVisible = vehicleVisibleResolved
    }

    onResolvedCameraCenterChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onResolvedLatChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onResolvedLngChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onResolvedMapBearingChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onResolvedVehicleBearingChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onResolvedZoomChanged: {
        if (!embeddedMapThrottle)
            syncNativeView(true)
        else
            syncNativeView(false)
    }
    onVehicleVisibleResolvedChanged: {
        if (!embeddedMapThrottle)
            nativeVehicleVisible = vehicleVisibleResolved
        else
            syncNativeView(false)
    }
    onResolvedRoutePathChanged: nativeRoutePath = resolvedRoutePath
    onResolvedTileUrlTemplateChanged: {
        if (!nativeMapLoader.active)
            return
        nativeMapLoader.active = false
        nativeMapReloadTimer.restart()
    }

    Behavior on nativeZoom {
        NumberAnimation {
            duration: root.nativeZoomAnimationMs
            easing.type: Easing.InOutCubic
        }
    }

    Component.onCompleted: {
        nativeRoutePath = resolvedRoutePath
        syncNativeView(true)
    }

    Timer {
        id: embeddedViewSyncTimer
        interval: 180
        running: root.embeddedMapThrottle
        repeat: true
        onTriggered: root.syncNativeView(false)
    }

    Timer {
        id: nativeMapReloadTimer
        interval: 30
        repeat: false
        onTriggered: nativeMapLoader.active = true
    }

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
    }

    Loader {
        id: nativeMapLoader
        anchors.fill: parent
        active: true
        sourceComponent: Component {
            NativeRasterMapItem {
                centerLat: root.nativeCenterLat
                centerLng: root.nativeCenterLng
                mapBearing: root.nativeMapBearing
                zoom: root.nativeZoom
                vehicleLat: root.nativeVehicleLat
                vehicleLng: root.nativeVehicleLng
                vehicleBearing: root.nativeBearing
                vehicleVisible: root.nativeVehicleVisible
                routePath: root.nativeRoutePath
                tileUrlTemplate: root.resolvedTileUrlTemplate
                userAgent: "BeagleyCluster/1.0 (native-online)"
                metrics: (typeof performanceMetrics !== "undefined") ? performanceMetrics : null
            }
        }
    }
}
