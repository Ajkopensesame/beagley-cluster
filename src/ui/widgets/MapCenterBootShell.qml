import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent

    property real liveLat: NaN
    property real liveLng: NaN
    property real liveBearing: 0
    property real cameraLat: NaN
    property real cameraLng: NaN
    property real cameraBearing: 0
    property int cameraZoom: 15
    property var routeCoordinates: []
    property var destination: ({})
    property string statusText: "Loading live map"
    property string detailText: "Preparing vector map"
    property bool degraded: false

    readonly property int tileSize: 256
    readonly property int tileColumns: Math.max(3, Math.ceil(width / tileSize) + 2)
    readonly property int tileRows: Math.max(3, Math.ceil(height / tileSize) + 2)
    readonly property int tileCount: tileColumns * tileRows
    readonly property int tilesPerAxis: Math.max(1, Math.pow(2, cameraZoom))
    readonly property real resolvedCameraLat: isFinite(cameraLat) ? clamp(cameraLat, -85.0511, 85.0511) : -27.4698
    readonly property real resolvedCameraLng: isFinite(cameraLng) ? cameraLng : 153.0251
    readonly property real resolvedWorldX: lngToWorldX(resolvedCameraLng, cameraZoom)
    readonly property real resolvedWorldY: latToWorldY(resolvedCameraLat, cameraZoom)
    readonly property real topLeftWorldX: resolvedWorldX - width / 2
    readonly property real topLeftWorldY: resolvedWorldY - height / 2
    readonly property int firstTileX: Math.floor(topLeftWorldX / tileSize)
    readonly property int firstTileY: Math.floor(topLeftWorldY / tileSize)
    readonly property real resolvedVehicleLat: isFinite(liveLat) ? liveLat : resolvedCameraLat
    readonly property real resolvedVehicleLng: isFinite(liveLng) ? liveLng : resolvedCameraLng

    function clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value))
    }

    function radians(value) {
        return value * Math.PI / 180.0
    }

    function degrees(value) {
        return value * 180.0 / Math.PI
    }

    function latToWorldY(value, zoomLevel) {
        const clamped = clamp(value, -85.0511, 85.0511)
        const sinValue = Math.sin(radians(clamped))
        const normalized = 0.5 - Math.log((1 + sinValue) / (1 - sinValue)) / (4 * Math.PI)
        return normalized * Math.pow(2, zoomLevel) * tileSize
    }

    function lngToWorldX(value, zoomLevel) {
        return ((value + 180.0) / 360.0) * Math.pow(2, zoomLevel) * tileSize
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
            x: lngToWorldX(lngValue, cameraZoom) - topLeftWorldX,
            y: latToWorldY(latValue, cameraZoom) - topLeftWorldY
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#102133"
    }

    Repeater {
        model: root.tileCount

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
            asynchronous: true
            cache: true
            smooth: false
            fillMode: Image.PreserveAspectFit
            visible: validTileY
            source: validTileY ? root.tileUrlFor(root.cameraZoom, root.wrapTileX(rawTileX), rawTileY) : ""
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#101d2dcc" }
            GradientStop { position: 0.3; color: "#00000000" }
            GradientStop { position: 1.0; color: "#0a121ccc" }
        }
    }

    Canvas {
        id: overlay
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            if (root.routeCoordinates && root.routeCoordinates.length > 1) {
                function drawStroke(lineWidth, color) {
                    ctx.beginPath()
                    for (let i = 0; i < root.routeCoordinates.length; ++i) {
                        const point = root.routeCoordinates[i]
                        if (!point || point.length < 2)
                            continue
                        const screen = root.screenPoint(Number(point[1]), Number(point[0]))
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

                drawStroke(14, "rgba(5,10,18,0.34)")
                drawStroke(8, "rgba(61,143,255,0.25)")
                drawStroke(5, "#61c6ff")
            }

            if (root.destination && isFinite(Number(root.destination.lat)) && isFinite(Number(root.destination.lng))) {
                const dest = root.screenPoint(Number(root.destination.lat), Number(root.destination.lng))
                ctx.fillStyle = "#ffb151"
                ctx.strokeStyle = "rgba(255,255,255,0.95)"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.arc(dest.x, dest.y, 8, 0, Math.PI * 2)
                ctx.fill()
                ctx.stroke()
            }

            const vehicle = root.screenPoint(root.resolvedVehicleLat, root.resolvedVehicleLng)
            ctx.save()
            ctx.translate(vehicle.x, vehicle.y)
            ctx.rotate((root.liveBearing || root.cameraBearing || 0) * Math.PI / 180.0)
            ctx.fillStyle = "#3b8cff"
            ctx.strokeStyle = "rgba(255,255,255,0.98)"
            ctx.lineWidth = 2
            ctx.beginPath()
            ctx.moveTo(0, -13)
            ctx.lineTo(9, 10)
            ctx.lineTo(-9, 10)
            ctx.closePath()
            ctx.fill()
            ctx.stroke()
            ctx.restore()
        }
    }

    onLiveLatChanged: overlay.requestPaint()
    onLiveLngChanged: overlay.requestPaint()
    onLiveBearingChanged: overlay.requestPaint()
    onCameraLatChanged: overlay.requestPaint()
    onCameraLngChanged: overlay.requestPaint()
    onCameraBearingChanged: overlay.requestPaint()
    onCameraZoomChanged: overlay.requestPaint()
    onRouteCoordinatesChanged: overlay.requestPaint()
    onDestinationChanged: overlay.requestPaint()

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 14
        width: Math.min(parent.width - 48, 430)
        height: detailText.length > 0 ? 70 : 50
        radius: 18
        color: "#f4ffffff"
        border.width: 1
        border.color: "#c5d5e6"

        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 3

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.statusText
                color: "#10243a"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                visible: root.detailText.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.detailText
                color: root.degraded ? "#8a5d35" : "#35607b"
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        text: "\u00a9 OpenStreetMap"
        color: "#d9e6f2"
        font.pixelSize: 11
    }
}
