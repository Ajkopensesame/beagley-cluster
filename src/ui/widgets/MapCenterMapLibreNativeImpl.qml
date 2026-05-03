import QtQuick 2.15
import QtLocation 6.5
import QtPositioning 6.5

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
    readonly property string resolvedStyleUrl: styleUrl.length > 0
        ? styleUrl
        : "https://tiles.openfreemap.org/styles/liberty"

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
    readonly property int nativeZoomAnimationMs: {
        const hinted = Number(resolvedCameraBucket.zoomAnimationMs)
        if (isFinite(hinted))
            return Math.max(120, Math.min(1800, Math.round(hinted)))
        return embeddedMapThrottle ? 760 : 420
    }
    readonly property real vehicleAnchorY: guidanceCameraActive ? 0.84 : 0.5
    readonly property var routeFeatureCollection: routeGeoJson(nativeRoutePath)

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

    function routeGeoJson(path) {
        var coordinates = []
        for (var i = 0; i < path.length; ++i) {
            const point = path[i] || ({})
            const latValue = Number(point.lat)
            const lngValue = Number(point.lng)
            if (isFinite(latValue) && isFinite(lngValue))
                coordinates.push([lngValue, latValue])
        }

        return {
            type: "FeatureCollection",
            features: coordinates.length >= 2 ? [{
                type: "Feature",
                properties: {},
                geometry: {
                    type: "LineString",
                    coordinates: coordinates
                }
            }] : []
        }
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
    onResolvedRoutePathChanged: nativeRoutePath = resolvedRoutePath
    onResolvedStyleUrlChanged: {
        nativeStyleUrl = resolvedStyleUrl
        mapViewReloadTimer.restart()
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
    }

    Timer {
        id: embeddedViewSyncTimer
        interval: 180
        running: root.embeddedMapThrottle
        repeat: true
        onTriggered: root.syncNativeView(false)
    }

    Timer {
        id: mapViewReloadTimer
        interval: 30
        repeat: false
        onTriggered: {
            mapViewLoader.active = false
            mapViewRestartTimer.restart()
        }
    }

    Timer {
        id: mapViewRestartTimer
        interval: 30
        repeat: false
        onTriggered: mapViewLoader.active = true
    }

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
    }

    Loader {
        id: mapViewLoader
        anchors.fill: parent
        active: true
        sourceComponent: mapLibreViewComponent
    }

    Component {
        id: mapLibreViewComponent

        MapView {
            id: mapView
            anchors.fill: parent

            map.plugin: Plugin {
                id: mapPlugin
                name: "maplibre"

                PluginParameter {
                    name: "maplibre.map.styles"
                    value: root.nativeStyleUrl
                }
            }

            map.center: QtPositioning.coordinate(root.nativeCenterLat, root.nativeCenterLng)
            map.zoomLevel: root.nativeZoom
            map.bearing: root.nativeMapBearing

            MapLibre.style: Style {
                SourceParameter {
                    id: routeSourceParam
                    styleId: "beagley-route"
                    type: "geojson"
                    property var data: root.routeFeatureCollection
                }

                LayerParameter {
                    id: routeLineParam
                    styleId: "beagley-route-line"
                    type: "line"
                    property string source: "beagley-route"
                    layout: {
                        "line-cap": "round",
                        "line-join": "round"
                    }
                    paint: {
                        "line-color": "#4CD9FF",
                        "line-width": 5.0,
                        "line-opacity": 0.92
                    }
                }
            }
        }
    }

    Item {
        id: vehicleMarker
        width: 44
        height: 52
        visible: root.nativeVehicleVisible
        x: Math.round(parent.width * 0.5 - width * 0.5)
        y: Math.round(parent.height * root.vehicleAnchorY - height * 0.54)
        rotation: root.nativeVehicleBearing
        transformOrigin: Item.Center

        Canvas {
            anchors.fill: parent
            antialiasing: true

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                ctx.save()
                ctx.translate(width / 2, height / 2)

                const glow = ctx.createRadialGradient(0, 4, 4, 0, 4, 30)
                glow.addColorStop(0.0, "rgba(255, 222, 74, 0.56)")
                glow.addColorStop(1.0, "rgba(255, 222, 74, 0.00)")
                ctx.fillStyle = glow
                ctx.beginPath()
                ctx.arc(0, 4, 30, 0, Math.PI * 2)
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(0, -22)
                ctx.lineTo(15, 18)
                ctx.quadraticCurveTo(0, 10, -15, 18)
                ctx.closePath()
                ctx.fillStyle = "#FFE45C"
                ctx.shadowColor = "rgba(38, 231, 255, 0.65)"
                ctx.shadowBlur = 14
                ctx.fill()
                ctx.lineWidth = 2
                ctx.strokeStyle = "#06212C"
                ctx.shadowBlur = 0
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(0, 6, 4, 0, Math.PI * 2)
                ctx.fillStyle = "#06212C"
                ctx.fill()

                ctx.restore()
            }
        }
    }
}
