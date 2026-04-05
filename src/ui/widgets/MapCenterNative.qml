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
    property bool interactionEnabled: true

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
    readonly property bool vehicleVisibleResolved: {
        if (!vehiclePoseValid)
            return false
        if (resolvedVehicleBucket.gpsReady === undefined && resolvedVehicleBucket.usingLastKnown === undefined)
            return true
        return !!resolvedVehicleBucket.gpsReady || !!resolvedVehicleBucket.usingLastKnown
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

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
    }

    NativeRasterMapItem {
        id: nativeMap
        anchors.fill: parent
        centerLat: root.resolvedLat
        centerLng: root.resolvedLng
        zoom: root.resolvedZoom
        vehicleBearing: root.resolvedBearing
        vehicleVisible: root.vehicleVisibleResolved
        routePath: root.resolvedRoutePath
        userAgent: "BeagleyCluster/1.0 (native-online)"
        metrics: (typeof performanceMetrics !== "undefined") ? performanceMetrics : null
    }
}
