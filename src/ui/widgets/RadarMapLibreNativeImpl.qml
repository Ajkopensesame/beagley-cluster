import QtQuick 2.15
import QtLocation 6.5
import QtPositioning 6.5
import MapLibre 3.0

import BeagleY 1.0

Item {
    id: root
    anchors.fill: parent
    clip: true

    property real lat: -27.4698
    property real lng: 153.0251
    property real zoom: 7.0
    property url frameUrl: ""
    property string status: "SYNC"
    property string styleUrl: ""
    property bool interactionEnabled: false
    property bool guidesVisible: true

    readonly property bool live: root.status === "LIVE"
    readonly property bool frameReady: root.live && String(root.frameUrl).length > 0
    readonly property real resolvedLat: coordValid(root.lat, -90, 90) ? Number(root.lat) : -27.4698
    readonly property real resolvedLng: coordValid(root.lng, -180, 180) ? Number(root.lng) : 153.0251
    readonly property real resolvedZoom: isFinite(Number(root.zoom))
        ? Math.max(3.0, Math.min(14.0, Number(root.zoom)))
        : 7.0
    readonly property string resolvedStyleUrl: String(root.styleUrl || "").length > 0
        ? String(root.styleUrl)
        : "https://tiles.openfreemap.org/styles/positron"
    property alias radarReady: radarOverlay.ready

    function coordValid(value, minValue, maxValue) {
        const number = Number(value)
        return isFinite(number) && number >= minValue && number <= maxValue
    }

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
    }

    Map {
        id: mapView
        anchors.fill: parent

        plugin: Plugin {
            id: radarMapPlugin
            name: "maplibre"

            PluginParameter {
                name: "maplibre.map.styles"
                value: root.resolvedStyleUrl
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

        center: QtPositioning.coordinate(root.resolvedLat, root.resolvedLng)
        zoomLevel: root.resolvedZoom
        bearing: 0

        function selectFirstMapType() {
            const types = supportedMapTypes
            if (!types || types.length < 1)
                return
            activeMapType = types[0]
            console.info("[RadarMapNative] active type",
                         types[0].name,
                         "url",
                         types[0].metadata ? types[0].metadata.url : "")
        }

        Component.onCompleted: {
            selectFirstMapType()
            console.info("[RadarMapNative] style",
                         root.resolvedStyleUrl,
                         "center",
                         root.resolvedLat,
                         root.resolvedLng,
                         "zoom",
                         root.resolvedZoom)
        }

        MapLibre.style: Style {}
    }

    Rectangle {
        anchors.fill: parent
        color: "#06111D"
        opacity: 0.10
    }

    RadarFrameItem {
        id: radarOverlay
        anchors.fill: parent
        source: root.frameReady ? root.frameUrl : ""
        mapSource: ""
        circular: false
        backgroundVisible: false
        guidesVisible: root.guidesVisible
        visible: ready
    }

    Connections {
        target: mapView
        ignoreUnknownSignals: true

        function onSupportedMapTypesChanged() {
            mapView.selectFirstMapType()
        }

        function onMapReadyChanged() {
            console.info("[RadarMapNative] mapReady", mapView.mapReady)
        }
    }
}
