import QtQuick 2.15
import QtLocation 6.5
import QtPositioning 6.5
import QtQuick.Shapes 1.15

import MapLibre 3.0

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
    property string styleUrl: ""
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
    readonly property real rendererMaxZoom: {
        const configured = (typeof BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM !== "undefined")
            ? Number(BEAGLEY_MAPLIBRE_NATIVE_MAX_ZOOM)
            : 14.0
        return isFinite(configured) ? clamp(configured, 1.0, 22.0) : 14.0
    }
    readonly property real resolvedZoom: isFinite(Number(zoom))
        ? clamp(Number(zoom), 3, rendererMaxZoom)
        : computeZoom()
    readonly property var resolvedRoutePath: buildRoutePath()
    readonly property bool vehiclePoseValid: isFinite(Number(resolvedLat)) && isFinite(Number(resolvedLng))
    readonly property bool vehicleBucketHasPose: hasKeys(resolvedVehicleBucket)
        && isFinite(Number(resolvedVehicleBucket.lat))
        && isFinite(Number(resolvedVehicleBucket.lng))
    readonly property bool externalVehiclePoseValid: !hasKeys(resolvedVehicleBucket)
        && isFinite(Number(lat))
        && isFinite(Number(lng))
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
    readonly property bool vehicleVisibleResolved: vehiclePoseValid
        && !fixedOriginEnabled
        && (vehicleBucketHasPose || externalVehiclePoseValid)
    readonly property string resolvedStyleUrl: styleUrl.length > 0
        ? styleUrl
        : "https://demotiles.maplibre.org/style.json"

    property real nativeCenterLat: resolvedCameraLat
    property real nativeCenterLng: resolvedCameraLng
    property real nativeMapBearing: resolvedMapBearing
    property real nativeVehicleLat: resolvedLat
    property real nativeVehicleLng: resolvedLng
    property real nativeVehicleBearing: resolvedVehicleBearing
    property real nativeZoom: resolvedZoom
    property bool nativeVehicleVisible: vehicleVisibleResolved
    property var nativeRoutePath: resolvedRoutePath
    property string nativeStyleUrl: resolvedStyleUrl
    property int lastLoggedNativeRoutePointCount: -1
    readonly property int nativeZoomAnimationMs: {
        const hinted = Number(resolvedCameraBucket.zoomAnimationMs)
        if (isFinite(hinted))
            return Math.max(120, Math.min(1800, Math.round(hinted)))
        return embeddedMapThrottle ? 760 : 420
    }
    readonly property real vehicleAnchorY: guidanceCameraActive ? 0.84 : 0.5
    readonly property var nativeRouteCoordinates: routeCoordinates(nativeRoutePath)
    readonly property var nativeDestination: destinationPoint(nativeRoutePath)
    readonly property real nativeDestinationLat: Number(nativeDestination.lat)
    readonly property real nativeDestinationLng: Number(nativeDestination.lng)
    readonly property bool nativeRouteVisible: nativeRouteCoordinates.length >= 2
    readonly property bool nativeDestinationVisible: isFinite(nativeDestinationLat) && isFinite(nativeDestinationLng)

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
            return clamp(hintedZoom, 3, rendererMaxZoom)

        var targetZoom = 17.2
        if (resolvedSpeedKph >= 100)
            targetZoom = 14.4
        else if (resolvedSpeedKph >= 70)
            targetZoom = 15.1
        else if (resolvedSpeedKph >= 40)
            targetZoom = 15.8
        else if (resolvedSpeedKph >= 20)
            targetZoom = 16.5
        return clamp(targetZoom, 3, rendererMaxZoom)
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

    function routeCoordinates(path) {
        var coordinates = []
        for (var i = 0; i < path.length; ++i) {
            const point = path[i] || ({})
            const latValue = Number(point.lat)
            const lngValue = Number(point.lng)
            if (isFinite(latValue) && isFinite(lngValue))
                coordinates.push(QtPositioning.coordinate(latValue, lngValue))
        }
        return coordinates
    }

    function destinationPoint(path) {
        const destination = resolvedRouteBucket.destination || ({})
        const destinationLat = Number(destination.lat)
        const destinationLng = Number(destination.lng)
        if (isFinite(destinationLat) && isFinite(destinationLng))
            return {
                lat: destinationLat,
                lng: destinationLng
            }

        if (path.length < 1)
            return ({})

        const fallback = path[path.length - 1] || ({})
        const fallbackLat = Number(fallback.lat)
        const fallbackLng = Number(fallback.lng)
        return isFinite(fallbackLat) && isFinite(fallbackLng)
            ? {
                lat: fallbackLat,
                lng: fallbackLng
            }
            : ({})
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

    function logNativeRoutePointCount() {
        const count = nativeRoutePath.length
        if (count === lastLoggedNativeRoutePointCount)
            return
        lastLoggedNativeRoutePointCount = count
        console.info("[MapCenterMapLibreNative] route points", count)
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
        if (Math.abs(angleDeltaDegrees(Number(nativeVehicleBearing), Number(resolvedVehicleBearing))) >= 3.0)
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
        nativeVehicleBearing = resolvedVehicleBearing
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
    onResolvedRoutePathChanged: {
        nativeRoutePath = resolvedRoutePath
        logNativeRoutePointCount()
    }
    onResolvedStyleUrlChanged: {
        nativeStyleUrl = resolvedStyleUrl
    }

    Behavior on nativeZoom {
        NumberAnimation {
            duration: root.nativeZoomAnimationMs
            easing.type: Easing.InOutCubic
        }
    }

    Component.onCompleted: {
        nativeRoutePath = resolvedRoutePath
        nativeStyleUrl = resolvedStyleUrl
        syncNativeView(true)
        logNativeRoutePointCount()
    }

    Timer {
        id: embeddedViewSyncTimer
        interval: 180
        running: root.embeddedMapThrottle
        repeat: true
        onTriggered: root.syncNativeView(false)
    }

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
    }

    Map {
        id: mapView
        anchors.fill: parent

        plugin: Plugin {
            id: mapPlugin
            name: "maplibre"

            PluginParameter {
                name: "maplibre.map.styles"
                value: root.nativeStyleUrl
            }
            PluginParameter {
                name: "maplibre.client.name"
                value: "BeagleyCluster"
            }
            PluginParameter {
                name: "maplibre.client.version"
                value: "1.0"
            }
        }

        center: QtPositioning.coordinate(root.nativeCenterLat, root.nativeCenterLng)
        zoomLevel: root.nativeZoom
        bearing: root.nativeMapBearing

        function selectFirstMapType() {
            const types = supportedMapTypes
            if (!types || types.length < 1)
                return
            activeMapType = types[0]
            console.info("[MapCenterMapLibreNative] active type",
                         types[0].name,
                         "url",
                         types[0].metadata ? types[0].metadata.url : "")
        }

        Component.onCompleted: {
            selectFirstMapType()
            console.info("[MapCenterMapLibreNative] style",
                         root.nativeStyleUrl,
                         "center",
                         root.nativeCenterLat,
                         root.nativeCenterLng,
                         "zoom",
                         root.nativeZoom)
        }

        MapLibre.style: Style {}

        MapPolyline {
            id: routeCasing
            visible: root.nativeRouteVisible
            path: root.nativeRouteCoordinates
            line.width: 9
            line.color: "#07101B"
            opacity: 0.82
        }

        MapPolyline {
            id: routeLine
            visible: root.nativeRouteVisible
            path: root.nativeRouteCoordinates
            line.width: 5
            line.color: "#25B8FF"
            opacity: 0.96
        }

        MapQuickItem {
            id: destinationMarker
            visible: root.nativeDestinationVisible
            coordinate: QtPositioning.coordinate(root.nativeDestinationLat, root.nativeDestinationLng)
            anchorPoint.x: 14
            anchorPoint.y: 32
            z: 30

            sourceItem: Item {
                width: 28
                height: 34

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 3
                    width: 22
                    height: 22
                    radius: 11
                    color: "#25B8FF"
                    border.color: "#07101B"
                    border.width: 3
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 25
                    width: 6
                    height: 8
                    radius: 3
                    color: "#07101B"
                    opacity: 0.9
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 9
                    width: 8
                    height: 8
                    radius: 4
                    color: "#F7FAFF"
                }
            }
        }
    }

    Connections {
        target: mapView
        ignoreUnknownSignals: true

        function onSupportedMapTypesChanged() {
            mapView.selectFirstMapType()
        }

        function onMapReadyChanged() {
            console.info("[MapCenterMapLibreNative] mapReady", mapView.mapReady)
        }
    }

    Item {
        id: vehicleMarker
        width: 54
        height: 64
        z: 40
        visible: root.nativeVehicleVisible
        x: Math.round(parent.width * 0.5 - width * 0.5)
        y: Math.round(parent.height * root.vehicleAnchorY - height * 0.54)
        rotation: root.nativeVehicleBearing
        transformOrigin: Item.Center
        layer.enabled: true
        layer.smooth: true

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "#FFE45C"
            opacity: 0.18
        }

        Shape {
            id: vehicleShape
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "#FFE45C"
                strokeColor: "#061D29"
                strokeWidth: 2.4
                joinStyle: ShapePath.RoundJoin
                startX: vehicleShape.width * 0.5
                startY: vehicleShape.height * 0.08
                PathLine { x: vehicleShape.width * 0.80; y: vehicleShape.height * 0.78 }
                PathQuad {
                    x: vehicleShape.width * 0.50
                    y: vehicleShape.height * 0.66
                    controlX: vehicleShape.width * 0.62
                    controlY: vehicleShape.height * 0.72
                }
                PathQuad {
                    x: vehicleShape.width * 0.20
                    y: vehicleShape.height * 0.78
                    controlX: vehicleShape.width * 0.38
                    controlY: vehicleShape.height * 0.72
                }
                PathLine { x: vehicleShape.width * 0.5; y: vehicleShape.height * 0.08 }
            }
        }

        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 8
            color: "#061D29"
        }
    }
}
