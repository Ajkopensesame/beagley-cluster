import QtQuick 2.15

import BeagleY 1.0
import "BomCatalog.js" as BomCatalog

Item {
    id: root

    property var theme
    property real lat: -27.4698
    property real lng: 153.0251
    property string effectLevel: "low"
    property bool active: true
    property bool stressScene: false
    property real phase: 0.0
    property var nowPlayingService: null

    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool effectsOff: effectLevel === "off"
    readonly property string displayFont: theme && theme.fontDisplay ? theme.fontDisplay : "Oxanium"
    readonly property string monoFont: theme && theme.fontMono ? theme.fontMono : "Oxanium"
    readonly property bool embeddedSafeMode: Qt.platform.os === "linux"
    readonly property bool linuxBomRadarInlineSupported: false
    readonly property int podSize: Math.floor(Math.min(142, Math.max(118, height * 0.185)))
    readonly property int cornerInset: 0
    readonly property real safeLat: coordValid(lat, -90, 90) ? Number(lat) : -27.4698
    readonly property real safeLng: coordValid(lng, -180, 180) ? Number(lng) : 153.0251
    readonly property real displayTempC: isFinite(Number(airTempC))
        ? Number(airTempC)
        : (24.0 + 3.5 * (0.5 + 0.5 * Math.sin(phase * 0.18)))
    readonly property real displayFeelsC: isFinite(Number(feelsLikeC))
        ? Number(feelsLikeC)
        : displayTempC + 0.8
    readonly property bool musicAvailable: !!(nowPlayingService && nowPlayingService.available)
    readonly property bool musicPlaying: !!(nowPlayingService && nowPlayingService.playing)
    readonly property string musicTitle: nowPlayingService && nowPlayingService.title
        ? String(nowPlayingService.title)
        : ""
    readonly property string musicArtist: nowPlayingService && nowPlayingService.artist
        ? String(nowPlayingService.artist)
        : ""
    readonly property string musicAlbum: nowPlayingService && nowPlayingService.album
        ? String(nowPlayingService.album)
        : ""
    readonly property string musicStatus: nowPlayingService && nowPlayingService.status
        ? String(nowPlayingService.status)
        : "OFFLINE"
    readonly property string musicDetail: nowPlayingService && nowPlayingService.statusDetail
        ? String(nowPlayingService.statusDetail)
        : "Spotify not connected"
    readonly property int weatherRefreshIntervalMs: expandedMode === "temp"
        ? (lowEffectMode ? 12 * 60 * 1000 : 8 * 60 * 1000)
        : 30 * 60 * 1000
    readonly property int radarRefreshIntervalMs: expandedMode === "radar"
        ? (lowEffectMode ? 7 * 60 * 1000 : 5 * 60 * 1000)
        : 25 * 60 * 1000

    property real airTempC: NaN
    property real feelsLikeC: NaN
    property int humidityPct: -1
    property real windKph: NaN
    property real precipitationMm: NaN
    property real pressureHpa: NaN
    property string weatherSummary: ""
    property string weatherWindDir: ""
    property string weatherTime: ""
    property string weatherUpdatedText: ""
    property string weatherStationName: ""
    property string weatherStationProduct: ""
    property real weatherStationDistanceKm: NaN
    property string weatherStatus: "SYNC"
    property string radarStatus: "SYNC"
    property string locationName: ""
    property real locationAnchorLat: NaN
    property real locationAnchorLng: NaN
    property string radarImageSource: ""
    property string radarFrameTime: ""
    property string radarSiteName: ""
    property string radarProduct: ""
    property real radarSiteDistanceKm: NaN
    property int radarRetryCount: 0
    property string expandedMode: ""

    signal mapMenuRequested()

    opacity: active ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function coordValid(value, minValue, maxValue) {
        const number = Number(value)
        return isFinite(number) && number >= minValue && number <= maxValue
    }

    function cacheBucket(intervalMs) {
        return Math.floor((new Date()).getTime() / intervalMs)
    }

    function cleanText(value) {
        return value === undefined || value === null ? "" : String(value).trim()
    }

    function firstNonEmpty(values) {
        for (var i = 0; i < values.length; ++i) {
            const text = cleanText(values[i])
            if (text.length > 0)
                return text
        }
        return ""
    }

    function uppercaseLabel(value) {
        const text = cleanText(value)
        return text.length > 0 ? text.toUpperCase() : ""
    }

    function formatTemp(value) {
        const number = Number(value)
        if (!isFinite(number))
            return "--"
        return Math.round(number).toString()
    }

    function formatWind(value) {
        const number = Number(value)
        if (!isFinite(number))
            return "--"
        return Math.round(number).toString()
    }

    function formatRain(value) {
        const number = Number(value)
        if (!isFinite(number))
            return "0.0"
        return number.toFixed(number >= 10 ? 0 : 1)
    }

    function formatPressure(value) {
        const number = Number(value)
        if (!isFinite(number))
            return "--"
        return number.toFixed(1)
    }

    function formatDistanceKm(value) {
        const number = Number(value)
        if (!isFinite(number))
            return "-- KM"
        if (number < 10)
            return number.toFixed(1) + " KM"
        return Math.round(number).toString() + " KM"
    }

    function musicPrimaryLine() {
        if (musicTitle.length > 0)
            return musicTitle
        if (musicAvailable)
            return musicStatus
        return "SPOTIFY"
    }

    function musicSecondaryLine() {
        if (musicArtist.length > 0)
            return musicArtist
        return musicAvailable ? "LOCAL PLAYER" : "NOT CONNECTED"
    }

    function weatherCompactLabel() {
        if (locationName.length > 0)
            return locationName
        return weatherStatus === "LIVE" ? "WEATHER" : weatherStatus
    }

    function radarCompactLabel() {
        if (locationName.length > 0)
            return locationName
        if (radarSiteName.length > 0)
            return radarSiteName.split(" ")[0].toUpperCase()
        if (radarStatus === "LIVE" || radarStatus === "SITE")
            return "RADAR"
        return radarStatus
    }

    function weatherSourceLabel() {
        if (weatherStationName.length === 0)
            return weatherStatus
        return weatherStationName + "  " + formatDistanceKm(weatherStationDistanceKm)
    }

    function radarSourceLabel() {
        if (radarSiteName.length === 0)
            return radarStatus
        return radarSiteName + "  " + formatDistanceKm(radarSiteDistanceKm)
    }

    function weatherLabel() {
        const summary = cleanText(weatherSummary)
        if (summary.length > 0)
            return summary.toUpperCase()
        return weatherStatus === "LIVE" ? "OBSERVED" : weatherStatus
    }

    function parseBomDate(value) {
        const text = cleanText(value)
        if (text.length < 12)
            return null
        const year = Number(text.slice(0, 4))
        const month = Number(text.slice(4, 6)) - 1
        const day = Number(text.slice(6, 8))
        const hour = Number(text.slice(8, 10))
        const minute = Number(text.slice(10, 12))
        const second = text.length >= 14 ? Number(text.slice(12, 14)) : 0
        const date = new Date(year, month, day, hour, minute, second)
        if (isNaN(date.getTime()))
            return null
        return date
    }

    function formatBomClock(value) {
        const date = parseBomDate(value)
        return date ? Qt.formatTime(date, "HH:mm") : "--:--"
    }

    function formatBomStamp(value) {
        const date = parseBomDate(value)
        return date ? Qt.formatDateTime(date, "ddd HH:mm").toUpperCase() : "--"
    }

    function distanceKm(latA, lngA, latB, lngB) {
        const phi1 = Number(latA) * Math.PI / 180.0
        const phi2 = Number(latB) * Math.PI / 180.0
        const deltaPhi = (Number(latB) - Number(latA)) * Math.PI / 180.0
        const deltaLambda = (Number(lngB) - Number(lngA)) * Math.PI / 180.0
        const sinPhi = Math.sin(deltaPhi / 2.0)
        const sinLambda = Math.sin(deltaLambda / 2.0)
        const a = sinPhi * sinPhi
            + Math.cos(phi1) * Math.cos(phi2) * sinLambda * sinLambda
        const c = 2.0 * Math.atan2(Math.sqrt(a), Math.sqrt(1.0 - a))
        return 6371.0 * c
    }

    function sameLocationAnchor(latValue, lngValue) {
        if (locationName.length === 0)
            return false
        if (!isFinite(Number(locationAnchorLat)) || !isFinite(Number(locationAnchorLng)))
            return false
        return distanceKm(latValue, lngValue, Number(locationAnchorLat), Number(locationAnchorLng)) < 5.0
    }

    function photonReverseUrl(latValue, lngValue) {
        return "https://photon.komoot.io/reverse?lat="
            + Number(latValue).toFixed(5)
            + "&lon="
            + Number(lngValue).toFixed(5)
    }

    function nominatimReverseUrl(latValue, lngValue) {
        return "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat="
            + Number(latValue).toFixed(5)
            + "&lon="
            + Number(lngValue).toFixed(5)
            + "&zoom=10"
    }

    function parsePhotonLocation(payload) {
        const features = payload && payload.features ? payload.features : []
        if (!features || features.length === 0)
            return ""
        const properties = features[0] && features[0].properties ? features[0].properties : ({})
        return uppercaseLabel(firstNonEmpty([
            properties.city,
            properties.town,
            properties.village,
            properties.suburb,
            properties.district,
            properties.county,
            properties.state
        ]))
    }

    function parseNominatimLocation(payload) {
        const address = payload && payload.address ? payload.address : ({})
        return uppercaseLabel(firstNonEmpty([
            address.city,
            address.town,
            address.village,
            address.suburb,
            address.city_district,
            address.county,
            address.state,
            payload.name
        ]))
    }

    function applyLocationName(value, latValue, lngValue) {
        const label = uppercaseLabel(value)
        if (label.length === 0)
            return false
        locationName = label
        locationAnchorLat = Number(latValue)
        locationAnchorLng = Number(lngValue)
        return true
    }

    function requestLocationFallback(latValue, lngValue) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status < 200 || xhr.status >= 300)
                return

            try {
                applyLocationName(parseNominatimLocation(JSON.parse(xhr.responseText)), latValue, lngValue)
            } catch (err) {
                console.warn("[WeatherCorners] fallback location parse failed:", err)
            }
        }
        xhr.open("GET", nominatimReverseUrl(latValue, lngValue), true)
        xhr.send()
    }

    function refreshLocationName() {
        if (!active || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180))
            return

        const latValue = Number(safeLat)
        const lngValue = Number(safeLng)
        if (sameLocationAnchor(latValue, lngValue))
            return

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                requestLocationFallback(latValue, lngValue)
                return
            }

            try {
                if (!applyLocationName(parsePhotonLocation(JSON.parse(xhr.responseText)), latValue, lngValue))
                    requestLocationFallback(latValue, lngValue)
            } catch (err) {
                console.warn("[WeatherCorners] location parse failed:", err)
                requestLocationFallback(latValue, lngValue)
            }
        }
        xhr.open("GET", photonReverseUrl(latValue, lngValue), true)
        xhr.send()
    }

    function stationScore(entry) {
        var score = distanceKm(safeLat, safeLng, Number(entry.lat), Number(entry.lng))
        const name = cleanText(entry.name).toUpperCase()
        if (name.indexOf("PORTABLE") === 0)
            score += 18
        if (name.indexOf("PCS") >= 0)
            score += 12
        if (name.indexOf("DEFENCE") >= 0)
            score += 6
        return score
    }

    function nearestWeatherCandidates(limit) {
        const ranked = []
        const stations = BomCatalog.observationStations || []
        for (var i = 0; i < stations.length; ++i) {
            const entry = stations[i]
            if (!coordValid(entry.lat, -90, 90) || !coordValid(entry.lng, -180, 180))
                continue
            ranked.push({
                product: entry.product,
                jsonId: entry.jsonId,
                name: entry.name,
                lat: Number(entry.lat),
                lng: Number(entry.lng),
                distanceKm: distanceKm(safeLat, safeLng, Number(entry.lat), Number(entry.lng)),
                score: stationScore(entry)
            })
        }
        ranked.sort(function(a, b) {
            return a.score - b.score
        })
        return ranked.slice(0, Math.max(1, limit))
    }

    function nearestRadarSite() {
        const sites = BomCatalog.radarSites || []
        var best = null
        for (var i = 0; i < sites.length; ++i) {
            const site = sites[i]
            if (!coordValid(site.lat, -90, 90) || !coordValid(site.lng, -180, 180))
                continue
            const distance = distanceKm(safeLat, safeLng, Number(site.lat), Number(site.lng))
            if (!best || distance < best.distanceKm) {
                best = {
                    name: site.name,
                    product: site.product,
                    lat: Number(site.lat),
                    lng: Number(site.lng),
                    distanceKm: distance
                }
            }
        }
        return best
    }

    function bomStationUrl(candidate) {
        const path = "/fwo/"
            + encodeURIComponent(candidate.product)
            + "/"
            + encodeURIComponent(candidate.jsonId)
            + ".json"
        const query = "beagley=" + cacheBucket(weatherRefreshIntervalMs)
        return "https://www.bom.gov.au" + path + "?" + query
    }

    function bomRadarUrl(site) {
        if (Qt.platform.os === "linux" && !linuxBomRadarInlineSupported)
            return ""
        const path = "/radar/"
            + encodeURIComponent(site.product)
            + ".gif"
        const query = "beagley=" + cacheBucket(radarRefreshIntervalMs)
        return "https://www.bom.gov.au" + path + "?" + query
    }

    function applyWeatherRow(candidate, payload, row) {
        const header = payload && payload.observations && payload.observations.header
            && payload.observations.header.length > 0
            ? payload.observations.header[0]
            : ({})
        const rawName = cleanText(row.name).length > 0 ? cleanText(row.name)
            : (cleanText(header.name).length > 0 ? cleanText(header.name) : cleanText(candidate.name))
        const rawWeather = cleanText(row.weather)
        const rawCloud = cleanText(row.cloud)
        var summary = rawWeather.length > 0 && rawWeather !== "-" ? rawWeather : ""
        if (summary.length === 0 && rawCloud.length > 0 && rawCloud !== "-")
            summary = rawCloud

        airTempC = Number(row.air_temp)
        feelsLikeC = Number(row.apparent_t)
        humidityPct = Math.round(Number(row.rel_hum))
        windKph = Number(row.wind_spd_kmh)
        precipitationMm = Number(row.rain_trace)
        pressureHpa = Number(row.press)
        weatherWindDir = cleanText(row.wind_dir).toUpperCase()
        weatherSummary = summary.length > 0 ? summary.toUpperCase() : "OBSERVED"
        weatherTime = formatBomClock(row.local_date_time_full || row.aifstime_utc)
        weatherUpdatedText = formatBomStamp(row.local_date_time_full || row.aifstime_utc)
        weatherStationName = rawName.toUpperCase()
        weatherStationProduct = cleanText(candidate.product)
        weatherStationDistanceKm = Number(candidate.distanceKm)
        weatherStatus = "LIVE"
    }

    function requestWeatherCandidate(candidates, index) {
        if (index >= candidates.length) {
            weatherStatus = "OFFLINE"
            return
        }

        const candidate = candidates[index]
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                requestWeatherCandidate(candidates, index + 1)
                return
            }

            try {
                const payload = JSON.parse(xhr.responseText)
                const data = payload && payload.observations && payload.observations.data
                    ? payload.observations.data
                    : []
                if (!data || data.length === 0) {
                    requestWeatherCandidate(candidates, index + 1)
                    return
                }

                const row = data[0]
                if (!isFinite(Number(row.air_temp))) {
                    requestWeatherCandidate(candidates, index + 1)
                    return
                }

                applyWeatherRow(candidate, payload, row)
            } catch (err) {
                console.warn("[WeatherCorners] BOM weather parse failed:", err)
                requestWeatherCandidate(candidates, index + 1)
            }
        }
        xhr.open("GET", bomStationUrl(candidate), true)
        xhr.send()
    }

    function refreshWeather() {
        if (!active || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180))
            return

        const candidates = nearestWeatherCandidates(8)
        if (candidates.length === 0) {
            weatherStatus = "NO DATA"
            return
        }

        weatherStatus = "SYNC"
        requestWeatherCandidate(candidates, 0)
    }

    function refreshRadar() {
        if (!active || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180))
            return

        const site = nearestRadarSite()
        if (!site) {
            radarStatus = "NO RADAR"
            radarImageSource = ""
            radarSiteName = ""
            radarProduct = ""
            radarSiteDistanceKm = NaN
            return
        }

        radarSiteName = cleanText(site.name).toUpperCase()
        radarProduct = cleanText(site.product)
        radarSiteDistanceKm = Number(site.distanceKm)
        radarFrameTime = Qt.formatTime(new Date(), "HH:mm")
        radarRetryCount = 0
        radarImageSource = bomRadarUrl(site)
        radarStatus = root.embeddedSafeMode
            ? "SITE"
            : (radarImageSource.length > 0 ? "LIVE" : "UNAVAILABLE")
    }

    Timer {
        interval: root.weatherRefreshIntervalMs
        repeat: true
        running: root.active
        triggeredOnStart: false
        onTriggered: root.refreshWeather()
    }

    Timer {
        interval: root.radarRefreshIntervalMs
        repeat: true
        running: root.active
        triggeredOnStart: false
        onTriggered: root.refreshRadar()
    }

    Timer {
        id: startupRefreshTimer
        interval: 6500
        repeat: false
        running: false
        onTriggered: {
            root.refreshLocationName()
            root.refreshWeather()
            root.refreshRadar()
        }
    }

    Timer {
        id: radarRetryTimer
        interval: 1500
        repeat: false
        onTriggered: {
            if (!root.active || root.radarRetryCount >= 3)
                return
            root.radarRetryCount += 1
            root.refreshRadar()
        }
    }

    Timer {
        id: coordinateDebounce
        interval: root.lowEffectMode ? 7000 : 4500
        repeat: false
        onTriggered: {
            if (!root.active)
                return
            root.refreshLocationName()
            root.refreshWeather()
            root.refreshRadar()
        }
    }

    onSafeLatChanged: if (root.active) coordinateDebounce.restart()
    onSafeLngChanged: if (root.active) coordinateDebounce.restart()
    onExpandedModeChanged: {
        if (!root.active)
            return
        if (root.expandedMode === "temp" || root.expandedMode === "radar") {
            root.refreshLocationName()
            root.refreshWeather()
            root.refreshRadar()
        }
    }

    Item {
        id: tempPanel
        width: root.podSize
        height: root.podSize
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root.cornerInset
        anchors.topMargin: root.cornerInset

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            border.width: 1
            border.color: "#3C325E"
        }

        Column {
            anchors.centerIn: parent
            spacing: 1

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3

                Text {
                    text: root.formatTemp(root.displayTempC)
                    color: "#F9FBFF"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(root.podSize * 0.44)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                    lineHeight: 0.82
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00B0"
                    color: "#C568FF"
                    font.family: root.displayFont
                    font.pixelSize: Math.floor(root.podSize * 0.20)
                    font.weight: Font.Bold
                    font.letterSpacing: 0
                }
            }

            Text {
                width: root.podSize * 0.72
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.weatherStatus === "LIVE" ? root.weatherCompactLabel() : root.weatherStatus
                color: root.weatherStatus === "LIVE" ? "#58FFE1" : "#FFD36B"
                font.family: root.monoFont
                font.pixelSize: 11
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expandedMode = root.expandedMode === "temp" ? "" : "temp"
        }
    }

    Item {
        id: radarPanel
        width: root.podSize
        height: root.podSize
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: root.cornerInset
        anchors.topMargin: root.cornerInset

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            border.width: 1
            border.color: "#3C325E"
        }

        Loader {
            anchors.fill: parent
            active: !root.embeddedSafeMode

            sourceComponent: Component {
                Item {
                    Rectangle {
                        id: radarPreviewMask
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: width / 2
                        color: "#05060A"
                        clip: true
                    }

                    Image {
                        id: radarPreviewImage
                        anchors.fill: radarPreviewMask
                        source: root.radarImageSource
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        opacity: status === Image.Ready ? 0.90 : 0.0

                        onStatusChanged: {
                            if (status === Image.Error && root.radarImageSource.length > 0) {
                                root.radarStatus = "OFFLINE"
                                radarRetryTimer.restart()
                            } else if (status === Image.Ready && root.radarSiteName.length > 0) {
                                root.radarRetryCount = 0
                                root.radarStatus = "LIVE"
                            }
                        }
                    }

                    Item {
                        anchors.fill: radarPreviewMask
                        visible: radarPreviewImage.status !== Image.Ready

                        Repeater {
                            model: 5

                            Rectangle {
                                width: root.podSize * (0.22 + index * 0.05)
                                height: width
                                radius: width / 2
                                x: radarPreviewMask.width * (0.12 + (index % 3) * 0.20)
                                y: radarPreviewMask.height * (0.22 + (index % 2) * 0.20)
                                color: index % 3 === 0 ? "#52FFE1" : (index % 3 === 1 ? "#C568FF" : "#7AA2FF")
                                opacity: 0.14 + 0.04 * (index % 2)
                            }
                        }
                    }

                    Rectangle {
                        anchors.left: radarPreviewMask.left
                        anchors.right: radarPreviewMask.right
                        anchors.top: radarPreviewMask.top
                        height: 38
                        radius: height / 2
                        color: "#000000C8"
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 2
            visible: root.embeddedSafeMode

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "RADAR"
                color: "#58FFE1"
                font.family: root.monoFont
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0
            }

            Text {
                width: root.podSize * 0.72
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.radarCompactLabel()
                color: "#F7FBFF"
                font.family: root.displayFont
                font.pixelSize: 20
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.radarFrameTime.length > 0 ? root.radarFrameTime : root.radarStatus
                color: "#9DB4FF"
                font.family: root.monoFont
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0
            }
        }

        Column {
            width: parent.width * 0.68
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 9
            spacing: 0

            Text {
                width: parent.width
                text: "RADAR"
                color: "#58FFE1"
                font.family: root.monoFont
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                text: root.radarStatus === "LIVE" ? root.radarFrameTime : root.radarStatus
                color: root.radarStatus === "LIVE" ? "#F7FBFF" : "#FFD36B"
                font.family: root.monoFont
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expandedMode = root.expandedMode === "radar" ? "" : "radar"
        }
    }

    Item {
        id: musicPanel
        width: root.podSize
        height: root.podSize
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.cornerInset
        anchors.bottomMargin: root.cornerInset

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            border.width: 1
            border.color: root.musicPlaying ? "#58FFE1" : "#3C325E"
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 17
            spacing: 3

            Repeater {
                model: [
                    { "h": 11, "c": "#58FFE1" },
                    { "h": 17, "c": "#C568FF" },
                    { "h": 13, "c": "#7AA2FF" }
                ]

                Rectangle {
                    width: 4
                    height: modelData.h
                    radius: 2
                    anchors.bottom: parent.bottom
                    color: modelData.c
                    opacity: root.musicPlaying ? 0.95 : 0.34
                }
            }
        }

        Column {
            width: parent.width * 0.76
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 14
            spacing: 2

            Text {
                width: parent.width
                text: root.musicPrimaryLine()
                color: root.musicAvailable ? "#F7FBFF" : "#9DB4FF"
                font.family: root.displayFont
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                width: parent.width
                text: root.musicSecondaryLine()
                color: root.musicPlaying ? "#58FFE1" : "#C568FF"
                font.family: root.monoFont
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expandedMode = root.expandedMode === "music" ? "" : "music"
        }
    }

    Item {
        id: mapPanel
        width: root.podSize
        height: root.podSize
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.cornerInset
        anchors.bottomMargin: root.cornerInset

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            border.width: 1
            border.color: "#3C325E"
        }

        Loader {
            anchors.fill: parent
            active: !root.embeddedSafeMode

            sourceComponent: Component {
                Canvas {
                    id: mapGlyph
                    width: parent.width * 0.56
                    height: parent.height * 0.54
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -7
                    renderTarget: Canvas.FramebufferObject
                    antialiasing: true
                    smooth: true

                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const route = ctx.createLinearGradient(0, 0, width, height)
                        route.addColorStop(0.0, "#58FFE1")
                        route.addColorStop(0.55, "#9DB4FF")
                        route.addColorStop(1.0, "#C568FF")

                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.strokeStyle = route
                        ctx.lineWidth = Math.max(4, width * 0.07)
                        ctx.beginPath()
                        ctx.moveTo(width * 0.16, height * 0.78)
                        ctx.bezierCurveTo(width * 0.24, height * 0.54, width * 0.44, height * 0.62, width * 0.54, height * 0.44)
                        ctx.bezierCurveTo(width * 0.64, height * 0.27, width * 0.74, height * 0.30, width * 0.82, height * 0.18)
                        ctx.stroke()

                        ctx.fillStyle = "#58FFE1"
                        ctx.beginPath()
                        ctx.arc(width * 0.18, height * 0.78, width * 0.09, 0, Math.PI * 2)
                        ctx.fill()

                        ctx.fillStyle = "#F7FBFF"
                        ctx.beginPath()
                        ctx.moveTo(width * 0.74, height * 0.10)
                        ctx.bezierCurveTo(width * 0.64, height * 0.10, width * 0.57, height * 0.18, width * 0.57, height * 0.28)
                        ctx.bezierCurveTo(width * 0.57, height * 0.40, width * 0.68, height * 0.50, width * 0.74, height * 0.64)
                        ctx.bezierCurveTo(width * 0.80, height * 0.50, width * 0.91, height * 0.40, width * 0.91, height * 0.28)
                        ctx.bezierCurveTo(width * 0.91, height * 0.18, width * 0.84, height * 0.10, width * 0.74, height * 0.10)
                        ctx.fill()

                        ctx.fillStyle = "#05060A"
                        ctx.beginPath()
                        ctx.arc(width * 0.74, height * 0.28, width * 0.08, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.embeddedSafeMode

            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -6
                spacing: 6

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: "#58FFE1"
                    }

                    Rectangle {
                        width: 28
                        height: 4
                        radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#9DB4FF"
                        rotation: -18
                    }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        color: "#C568FF"
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 21
            text: "MAP"
            color: "#F7FBFF"
            font.family: root.monoFont
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.expandedMode = ""
                root.mapMenuRequested()
            }
        }
    }

    Item {
        id: detailLayer
        anchors.fill: parent
        z: 500
        visible: root.expandedMode !== ""
        opacity: visible ? 1 : 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.expandedMode = ""
        }

        Rectangle {
            id: detailCard
            width: Math.floor(Math.min(452, Math.max(332, parent.width * 0.35)))
            height: root.expandedMode === "radar"
                ? Math.floor(Math.min(390, Math.max(292, parent.height * 0.52)))
                : Math.floor(Math.min(360, Math.max(272, parent.height * 0.46)))
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            radius: 8
            color: root.expandedMode === "music" ? "#010208" : "#04050CF0"
            border.width: 1
            border.color: root.expandedMode === "music" ? "#58FFE1" : "#5C4B90"

            MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = true
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 14
                anchors.topMargin: 10
                text: "X"
                color: "#9DB4FF"
                font.family: root.monoFont
                font.pixelSize: 14
                font.weight: Font.Bold

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    onClicked: root.expandedMode = ""
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 20
                visible: root.expandedMode === "music"

                Column {
                    anchors.fill: parent
                    spacing: 14

                    Text {
                        width: parent.width
                        text: "NOW PLAYING"
                        color: "#58FFE1"
                        font.family: root.monoFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Rectangle {
                        width: parent.width
                        height: parent.height - 30
                        radius: 8
                        color: "#070913"
                        border.width: 1
                        border.color: root.musicPlaying ? "#58FFE1" : "#3C325E"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 14

                            Rectangle {
                                width: 96
                                height: 96
                                radius: 48
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: "#05060A"
                                border.width: 1
                                border.color: root.musicPlaying ? "#58FFE1" : "#5C4B90"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Repeater {
                                        model: [
                                            { "h": 30, "c": "#58FFE1" },
                                            { "h": 48, "c": "#C568FF" },
                                            { "h": 36, "c": "#7AA2FF" }
                                        ]

                                        Rectangle {
                                            width: 8
                                            height: modelData.h
                                            radius: 4
                                            anchors.bottom: parent.bottom
                                            color: modelData.c
                                            opacity: root.musicPlaying ? 0.95 : 0.36
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                radius: 8
                                color: "#0A0D18"
                                border.width: 1
                                border.color: "#22283D"
                                implicitHeight: titleColumn.implicitHeight + 22

                                Column {
                                    id: titleColumn
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    spacing: 8

                                    Text {
                                        width: parent.width
                                        text: root.musicTitle.length > 0 ? root.musicTitle : root.musicStatus
                                        color: "#F7FBFF"
                                        font.family: root.displayFont
                                        font.pixelSize: 24
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                    }

                                    Text {
                                        width: parent.width
                                        text: root.musicArtist.length > 0 ? root.musicArtist : root.musicDetail
                                        color: "#58FFE1"
                                        font.family: root.monoFont
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                    }

                                    Text {
                                        width: parent.width
                                        text: root.musicAlbum.length > 0 ? root.musicAlbum : "SPOTIFY"
                                        color: "#C568FF"
                                        font.family: root.monoFont
                                        font.pixelSize: 12
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 20
                visible: root.expandedMode === "temp"

                Column {
                    anchors.fill: parent
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "CURRENT BOM"
                        color: "#58FFE1"
                        font.family: root.monoFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        width: parent.width
                        visible: root.locationName.length > 0
                        text: root.locationName
                        color: "#F7FBFF"
                        font.family: root.displayFont
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.weatherSourceLabel()
                        color: "#9DB4FF"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10

                        Text {
                            text: root.formatTemp(root.displayTempC)
                            color: "#F9FBFF"
                            font.family: root.displayFont
                            font.pixelSize: 86
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            lineHeight: 0.82
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: "\u00B0C"
                                color: "#C568FF"
                                font.family: root.displayFont
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }

                            Text {
                                text: root.weatherTime
                                color: "#9DB4FF"
                                font.family: root.monoFont
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.weatherLabel()
                        color: "#F7FBFF"
                        font.family: root.monoFont
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        columnSpacing: 38
                        rowSpacing: 8

                        Text {
                            text: "FEELS " + root.formatTemp(root.displayFeelsC) + "\u00B0"
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "HUM " + (root.humidityPct >= 0 ? root.humidityPct : "--") + "%"
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "WIND " + (root.weatherWindDir.length > 0 ? root.weatherWindDir + " " : "") + root.formatWind(root.windKph) + " KM/H"
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "PRESS " + root.formatPressure(root.pressureHpa) + " HPA"
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "RAIN " + root.formatRain(root.precipitationMm) + " MM"
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }

                        Text {
                            text: "UPDATED " + root.weatherUpdatedText
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 18
                visible: root.expandedMode === "radar"

                Column {
                    anchors.fill: parent
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "BOM RADAR"
                        color: "#58FFE1"
                        font.family: root.monoFont
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        width: parent.width
                        visible: root.locationName.length > 0
                        text: root.locationName
                        color: "#F7FBFF"
                        font.family: root.displayFont
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.radarSourceLabel()
                        color: "#9DB4FF"
                        font.family: root.monoFont
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.radarStatus === "LIVE"
                            ? "CURRENT FRAME " + root.radarFrameTime
                            : root.radarStatus
                        color: root.radarStatus === "LIVE" ? "#F7FBFF" : "#FFD36B"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Loader {
                        width: parent.width
                        height: parent.height - 74
                        active: !root.embeddedSafeMode

                        sourceComponent: Component {
                            Rectangle {
                                id: detailRadarViewport
                                width: parent.width
                                height: parent.height - 74
                                radius: 8
                                color: "#000000"
                                border.width: 1
                                border.color: "#2E2A43"
                                clip: true

                                Image {
                                    id: detailRadarImage
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    source: root.expandedMode === "radar" ? root.radarImageSource : ""
                                    asynchronous: true
                                    cache: true
                                    fillMode: Image.PreserveAspectCrop
                                    opacity: status === Image.Ready ? 0.92 : 0.0
                                    smooth: true
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: "#080913"
                                    opacity: detailRadarImage.status === Image.Ready ? 0.18 : 0.90
                                }

                                Item {
                                    anchors.fill: parent
                                    visible: detailRadarImage.status !== Image.Ready

                                    Repeater {
                                        model: 7

                                        Rectangle {
                                            width: 52 + index * 9
                                            height: width
                                            radius: width / 2
                                            x: detailRadarViewport.width * (0.10 + (index % 4) * 0.18)
                                            y: detailRadarViewport.height * (0.16 + (index % 3) * 0.20)
                                            color: index % 3 === 0 ? "#52FFE1" : (index % 3 === 1 ? "#C568FF" : "#6E7BFF")
                                            opacity: 0.12 + 0.05 * (index % 2)
                                        }
                                    }
                                }

                                Canvas {
                                    anchors.fill: parent
                                    renderTarget: Canvas.FramebufferObject
                                    antialiasing: true
                                    smooth: true

                                    Component.onCompleted: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.fillStyle = "rgba(0,0,0,0.16)"
                                        ctx.fillRect(0, 0, width, height)

                                        ctx.strokeStyle = "rgba(82,255,225,0.16)"
                                        ctx.lineWidth = 1
                                        for (var ring = 1; ring <= 4; ++ring) {
                                            ctx.beginPath()
                                            ctx.arc(width / 2, height / 2, Math.min(width, height) * ring / 9, 0, Math.PI * 2)
                                            ctx.stroke()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: parent.height - 74
                        radius: 8
                        color: "#05060A"
                        border.width: 1
                        border.color: "#2E2A43"
                        visible: root.embeddedSafeMode

                        Column {
                            anchors.centerIn: parent
                            spacing: 12

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "RADAR IMAGE"
                                color: "#58FFE1"
                                font.family: root.monoFont
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.radarSiteName.length > 0 ? root.radarSiteName : "NO SITE"
                                color: "#F7FBFF"
                                font.family: root.displayFont
                                font.pixelSize: 22
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.radarFrameTime.length > 0
                                    ? "UPDATED " + root.radarFrameTime
                                    : root.radarStatus
                                color: "#9DB4FF"
                                font.family: root.monoFont
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "INLINE IMAGE DISABLED ON DEVICE"
                                color: "#C568FF"
                                font.family: root.monoFont
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0
                            }
                        }
                    }
                }
            }
        }
    }

    onActiveChanged: {
        if (!active) {
            expandedMode = ""
            startupRefreshTimer.stop()
        } else {
            startupRefreshTimer.restart()
        }
    }

    Component.onCompleted: {
        if (root.active)
            startupRefreshTimer.start()
    }
}
