import QtQuick 2.15

import BeagleY 1.0
import "." as WidgetLocal
import "BomCatalog.js" as BomCatalog

Item {
    id: root

    property var theme
    property real lat: NaN
    property real lng: NaN
    property bool livePositionValid: false
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
    readonly property bool tallDetailMode: expandedMode === "radar"
    readonly property int podSize: Math.floor(Math.min(164, Math.max(142, height * 0.228)))
    readonly property int cornerBleed: Math.round(podSize * 0.17)
    readonly property int cornerInset: -cornerBleed
    readonly property real podBleedFraction: cornerBleed / podSize
    readonly property int podFaceInset: Math.round(podSize * 0.190)
    readonly property int podContentDiameter: Math.round(podSize * 0.56)
    readonly property int podLabelWidth: Math.round(podSize * 0.58)
    readonly property int podIconSize: Math.round(podSize * 0.31)
    readonly property real stressLat: -27.4698
    readonly property real stressLng: 153.0251
    readonly property bool liveWeatherPositionReady: livePositionValid
        && coordValid(lat, -90, 90)
        && coordValid(lng, -180, 180)
    readonly property bool weatherPositionReady: liveWeatherPositionReady || stressScene
    readonly property real safeLat: liveWeatherPositionReady ? Number(lat) : (stressScene ? stressLat : NaN)
    readonly property real safeLng: liveWeatherPositionReady ? Number(lng) : (stressScene ? stressLng : NaN)
    readonly property real displayTempC: isFinite(Number(airTempC))
        ? Number(airTempC)
        : (stressScene ? (24.0 + 3.5 * (0.5 + 0.5 * Math.sin(phase * 0.18))) : NaN)
    readonly property real displayFeelsC: isFinite(Number(feelsLikeC))
        ? Number(feelsLikeC)
        : (stressScene && isFinite(Number(displayTempC)) ? displayTempC + 0.8 : NaN)
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
        ? 5 * 60 * 1000
        : 8 * 60 * 1000
    readonly property int forecastRefreshIntervalMs: expandedMode === "temp"
        ? 30 * 60 * 1000
        : 2 * 60 * 60 * 1000
    readonly property int radarRefreshIntervalMs: 60 * 1000
    readonly property real radarMapZoom: 7.0

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
    property var forecastRows: []
    property string forecastStatus: "SYNC"
    property string forecastUpdatedText: ""
    property string radarStatus: "SYNC"
    property string locationName: ""
    property real locationAnchorLat: NaN
    property real locationAnchorLng: NaN
    property string radarFrameTime: ""
    property string radarSiteName: ""
    property string radarProduct: ""
    property real radarSiteDistanceKm: NaN
    property string radarFrameLabel: ""
    property string expandedMode: ""

    signal mapMenuRequested()

    readonly property bool radarServiceAvailable: typeof radarImage !== "undefined" && radarImage !== null
    readonly property bool radarServiceReady: radarServiceAvailable && radarImage.ready && String(radarImage.imageUrl).length > 0
    readonly property url radarFrameUrl: radarServiceReady ? radarImage.imageUrl : ""

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
        if (radarStatus === "LIVE")
            return "RADAR"
        return radarStatus.length > 0 ? radarStatus : "SYNC"
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

    function radarFrameDisplayLabel() {
        const label = cleanText(radarFrameLabel)
        const time = cleanText(radarFrameTime)
        if (label.length > 0 && time.length > 0)
            return label + "  " + time
        if (label.length > 0)
            return label
        return time.length > 0 ? time : radarStatus
    }

    function weatherLabel() {
        const summary = cleanText(weatherSummary)
        if (summary.length > 0)
            return summary.toUpperCase()
        return weatherStatus === "LIVE" ? "OBSERVED" : weatherStatus
    }

    function currentConditionLabel() {
        const label = weatherLabel()
        if ((label === "OBSERVED" || label === "LIVE") && forecastRows.length > 0)
            return cleanText(forecastRows[0].label).length > 0 ? forecastRows[0].label : label
        return label
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

    function parseIsoDay(value) {
        const text = cleanText(value)
        if (text.length < 10)
            return null
        const date = new Date(text + "T12:00:00")
        return isNaN(date.getTime()) ? null : date
    }

    function forecastDayLabel(value, index) {
        if (index === 0)
            return "TODAY"
        if (index === 1)
            return "TOMORROW"
        const date = parseIsoDay(value)
        return date ? Qt.formatDate(date, "ddd").toUpperCase() : "--"
    }

    function forecastCompactDayLabel(value, index) {
        if (index === 0)
            return "TODAY"
        if (index === 1)
            return "TMRW"
        const date = parseIsoDay(value)
        return date ? Qt.formatDate(date, "ddd").toUpperCase() : "--"
    }

    function forecastConditionLabel(codeValue) {
        const code = Math.round(Number(codeValue))
        if (!isFinite(code))
            return "FORECAST"
        if (code === 0)
            return "CLEAR"
        if (code === 1)
            return "MOSTLY CLEAR"
        if (code === 2)
            return "PARTLY CLOUDY"
        if (code === 3)
            return "CLOUDY"
        if (code === 45 || code === 48)
            return "FOG"
        if (code >= 51 && code <= 57)
            return "DRIZZLE"
        if (code >= 61 && code <= 67)
            return "RAIN"
        if (code >= 71 && code <= 77)
            return "SNOW"
        if (code >= 80 && code <= 82)
            return "SHOWERS"
        if (code >= 85 && code <= 86)
            return "SNOW SHOWERS"
        if (code >= 95)
            return "STORM"
        return "FORECAST"
    }

    function weatherKind(labelValue) {
        const label = uppercaseLabel(labelValue)
        if (label.indexOf("STORM") >= 0)
            return "storm"
        if (label.indexOf("RAIN") >= 0 || label.indexOf("SHOWER") >= 0 || label.indexOf("DRIZZLE") >= 0)
            return "rain"
        if (label.indexOf("SNOW") >= 0)
            return "snow"
        if (label.indexOf("FOG") >= 0)
            return "fog"
        if (label.indexOf("CLOUD") >= 0)
            return "cloud"
        if (label.indexOf("CLEAR") >= 0 || label.indexOf("SUN") >= 0 || label.indexOf("OBSERVED") >= 0)
            return "clear"
        return "clear"
    }

    function weatherMoodLine(labelValue) {
        const label = uppercaseLabel(labelValue)
        if (label.indexOf("STORM") >= 0)
            return "Stormy"
        if (label.indexOf("RAIN") >= 0 || label.indexOf("SHOWER") >= 0 || label.indexOf("DRIZZLE") >= 0)
            return "Rainy"
        if (label.indexOf("FOG") >= 0)
            return "Foggy"
        if (label.indexOf("CLOUD") >= 0)
            return "Cloudy"
        if (label.indexOf("CLEAR") >= 0 || label.indexOf("SUN") >= 0 || label.indexOf("OBSERVED") >= 0)
            return "Sunny"
        return "Today"
    }

    function weatherMoodSubLine(labelValue) {
        const kind = weatherKind(labelValue)
        if (kind === "storm")
            return "stay inside weather"
        if (kind === "rain")
            return "take an umbrella"
        if (kind === "fog")
            return "low visibility"
        if (kind === "cloud")
            return "soft clouds today"
        return "sunglasses weather"
    }

    function rainShortLine(value) {
        const chance = Number(value)
        if (!isFinite(chance))
            return "--"
        if (chance >= 70)
            return "high"
        if (chance >= 35)
            return "maybe"
        if (chance > 0)
            return "low"
        return "none"
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

    function clearWeatherData(statusText) {
        airTempC = NaN
        feelsLikeC = NaN
        humidityPct = -1
        windKph = NaN
        precipitationMm = NaN
        pressureHpa = NaN
        weatherSummary = ""
        weatherWindDir = ""
        weatherTime = ""
        weatherUpdatedText = ""
        weatherStationName = ""
        weatherStationProduct = ""
        weatherStationDistanceKm = NaN
        weatherStatus = statusText
    }

    function clearForecastData(statusText) {
        forecastRows = []
        forecastUpdatedText = ""
        forecastStatus = statusText
    }

    function clearRadarData(statusText) {
        radarStatus = statusText
        radarFrameTime = ""
        radarFrameLabel = ""
        radarSiteName = ""
        radarProduct = ""
        radarSiteDistanceKm = NaN
        if (radarServiceAvailable)
            radarImage.setPosition(0, 0, false)
    }

    function clearLocationData() {
        locationName = ""
        locationAnchorLat = NaN
        locationAnchorLng = NaN
    }

    function clearLiveWeatherState(statusText) {
        clearLocationData()
        clearWeatherData(statusText)
        clearForecastData(statusText)
        clearRadarData(statusText)
    }

    function coordinateStatusText() {
        return livePositionValid || stressScene ? "SYNC" : "GPS WAIT"
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
        if (!active)
            return

        if (!weatherPositionReady || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180)) {
            clearLocationData()
            return
        }

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

    function forecastUrl(latValue, lngValue) {
        return "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + Number(latValue).toFixed(5)
            + "&longitude=" + Number(lngValue).toFixed(5)
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            + "&timezone=auto"
            + "&forecast_days=7"
            + "&beagley=" + cacheBucket(forecastRefreshIntervalMs)
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

    function applyForecast(payload) {
        const daily = payload && payload.daily ? payload.daily : ({})
        const times = daily.time || []
        const codes = daily.weather_code || []
        const highs = daily.temperature_2m_max || []
        const lows = daily.temperature_2m_min || []
        const rain = daily.precipitation_probability_max || []
        const rows = []
        const count = Math.min(7, times.length)

        for (var i = 0; i < count; ++i) {
            const high = Number(highs[i])
            const low = Number(lows[i])
            if (!isFinite(high) && !isFinite(low))
                continue
            const rainPct = Number(rain[i])
            rows.push({
                date: times[i],
                day: forecastDayLabel(times[i], i),
                label: forecastConditionLabel(codes[i]),
                high: isFinite(high) ? Math.round(high) : null,
                low: isFinite(low) ? Math.round(low) : null,
                rain: isFinite(rainPct) ? Math.round(rainPct) : null
            })
        }

        forecastRows = rows
        forecastUpdatedText = Qt.formatDateTime(new Date(), "ddd HH:mm").toUpperCase()
        forecastStatus = rows.length > 0 ? "LIVE" : "NO DATA"
    }

    function refreshForecast() {
        if (!active)
            return

        if (!weatherPositionReady || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180)) {
            clearForecastData(coordinateStatusText())
            return
        }

        forecastStatus = "SYNC"
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return

            if (xhr.status < 200 || xhr.status >= 300) {
                clearForecastData("OFFLINE")
                return
            }

            try {
                applyForecast(JSON.parse(xhr.responseText))
            } catch (err) {
                console.warn("[WeatherCorners] forecast parse failed:", err)
                clearForecastData("OFFLINE")
            }
        }
        xhr.open("GET", forecastUrl(Number(safeLat), Number(safeLng)), true)
        xhr.send()
    }

    function refreshWeather() {
        if (!active)
            return

        if (!weatherPositionReady || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180)) {
            clearWeatherData(coordinateStatusText())
            return
        }

        const candidates = nearestWeatherCandidates(8)
        if (candidates.length === 0) {
            clearWeatherData("NO DATA")
            weatherStatus = "NO DATA"
            return
        }

        weatherStatus = "SYNC"
        requestWeatherCandidate(candidates, 0)
    }

    function refreshRadar() {
        if (!active)
            return

        if (!weatherPositionReady || !coordValid(safeLat, -90, 90) || !coordValid(safeLng, -180, 180)) {
            clearRadarData(coordinateStatusText())
            return
        }

        const site = nearestRadarSite()
        if (!site) {
            clearRadarData("NO RADAR")
            return
        }

        radarSiteName = cleanText(site.name).toUpperCase()
        radarProduct = cleanText(site.product)
        radarSiteDistanceKm = Number(site.distanceKm)
        if (radarServiceAvailable) {
            radarImage.setPosition(Number(safeLat), Number(safeLng), true)
            radarImage.refresh()
            radarStatus = radarImage.status
            radarFrameTime = radarImage.frameTime
            radarFrameLabel = radarImage.frameLabel
        } else {
            radarStatus = "UNAVAILABLE"
            radarFrameTime = ""
            radarFrameLabel = ""
        }
    }

    function handlePositionChanged() {
        if (!root.active)
            return

        if (!root.weatherPositionReady) {
            root.clearLiveWeatherState(root.coordinateStatusText())
            coordinateDebounce.stop()
            return
        }

        if (!root.sameLocationAnchor(Number(root.safeLat), Number(root.safeLng)))
            root.clearLiveWeatherState("SYNC")
        coordinateDebounce.restart()
    }

    Timer {
        interval: root.weatherRefreshIntervalMs
        repeat: true
        running: root.active
        triggeredOnStart: false
        onTriggered: {
            root.refreshWeather()
        }
    }

    Timer {
        interval: root.forecastRefreshIntervalMs
        repeat: true
        running: root.active
        triggeredOnStart: false
        onTriggered: root.refreshForecast()
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
            root.refreshForecast()
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
            root.refreshForecast()
            root.refreshRadar()
        }
    }

    Connections {
        target: root.radarServiceAvailable ? radarImage : null

        function onImageChanged() {
            root.radarStatus = radarImage.status
            root.radarFrameTime = radarImage.frameTime
            root.radarFrameLabel = radarImage.frameLabel
        }

        function onStatusChanged() {
            root.radarStatus = radarImage.status
        }

        function onFrameTimeChanged() {
            root.radarFrameTime = radarImage.frameTime
        }

        function onFrameLabelChanged() {
            root.radarFrameLabel = radarImage.frameLabel
        }
    }

    onSafeLatChanged: handlePositionChanged()
    onSafeLngChanged: handlePositionChanged()
    onLivePositionValidChanged: handlePositionChanged()
    onExpandedModeChanged: {
        if (!root.active)
            return
        if (root.expandedMode === "temp" || root.expandedMode === "radar") {
            root.refreshLocationName()
            root.refreshWeather()
            root.refreshForecast()
            root.refreshRadar()
        }
    }

    WeatherCornerWidget {
        id: weatherCorner
        width: root.podSize
        height: root.podSize
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: root.cornerInset
        anchors.topMargin: root.cornerInset
        theme: root.theme
        corner: "topLeft"
        effectLevel: root.effectLevel
        bleedFraction: root.podBleedFraction
        live: root.weatherStatus === "LIVE"
        tempText: root.formatTemp(root.displayTempC)
        locationText: root.weatherCompactLabel()
        conditionKind: root.weatherKind(root.currentConditionLabel())
        conditionText: root.weatherStatus
        onClicked: root.expandedMode = root.expandedMode === "temp" ? "" : "temp"
    }

    WidgetLocal.RadarCornerWidget {
        id: radarCorner
        width: root.podSize
        height: root.podSize
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: root.cornerInset
        anchors.topMargin: root.cornerInset
        theme: root.theme
        corner: "topRight"
        effectLevel: root.effectLevel
        bleedFraction: root.podBleedFraction
        frameUrl: root.radarFrameUrl
        status: root.radarStatus
        frameLabel: root.radarFrameDisplayLabel()
        onClicked: root.expandedMode = root.expandedMode === "radar" ? "" : "radar"
    }

    MediaCornerWidget {
        id: mediaCorner
        width: root.podSize
        height: root.podSize
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.cornerInset
        anchors.bottomMargin: root.cornerInset
        theme: root.theme
        corner: "bottomLeft"
        effectLevel: root.effectLevel
        bleedFraction: root.podBleedFraction
        available: root.musicAvailable
        playing: root.musicPlaying
        primaryText: root.musicPrimaryLine()
        secondaryText: root.musicSecondaryLine()
        onClicked: root.expandedMode = root.expandedMode === "music" ? "" : "music"
    }

    MapMenuCornerWidget {
        id: mapMenuCorner
        width: root.podSize
        height: root.podSize
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.cornerInset
        anchors.bottomMargin: root.cornerInset
        theme: root.theme
        corner: "bottomRight"
        effectLevel: root.effectLevel
        bleedFraction: root.podBleedFraction
        onClicked: {
            root.expandedMode = ""
            root.mapMenuRequested()
        }
    }

    Item {
        id: detailLayer
        anchors.fill: parent
        z: 500
        visible: root.expandedMode !== ""
        opacity: visible ? 1 : 0

        Rectangle {
            anchors.fill: parent
            color: root.expandedMode === "temp" || root.expandedMode === "radar"
                ? Qt.rgba(0.0, 0.0, 0.0, 0.0)
                : Qt.rgba(0.0, 0.0, 0.0, root.tallDetailMode ? 0.66 : 0.54)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.expandedMode = ""
        }

        Item {
            id: detailCard
            width: root.expandedMode === "temp"
                ? Math.floor(Math.min(560, Math.max(500, parent.width * 0.30)))
                : root.tallDetailMode
                ? Math.floor(Math.min(620, Math.max(500, parent.width * 0.38)))
                : Math.floor(Math.min(452, Math.max(332, parent.width * 0.35)))
            height: root.expandedMode === "temp"
                ? 430
                : root.tallDetailMode
                ? Math.floor(Math.min(parent.height - 44, Math.max(560, parent.height * 0.92)))
                : Math.floor(Math.min(360, Math.max(272, parent.height * 0.46)))
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            clip: false

            NativePanel {
                anchors.fill: parent
                color: root.expandedMode === "temp"
                    ? "#05060B"
                    : root.expandedMode === "music"
                    ? "#02040B"
                    : "#050812"
                borderColor: root.expandedMode === "temp"
                    ? "#FF7AD9"
                    : root.tallDetailMode
                    ? "#58FFE1"
                    : (root.expandedMode === "music" ? "#58FFE1" : "#5C4B90")
                borderWidth: 1
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse.accepted = true
            }

            Item {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 10
                anchors.topMargin: 8
                width: 32
                height: 32

                OemIcon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    icon: "close"
                    color: "#9DB4FF"
                    accentColor: "#9DB4FF"
                    strokeWidth: 3.2
                }

                MouseArea {
                    anchors.fill: parent
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

                                OemIcon {
                                    anchors.centerIn: parent
                                    width: 62
                                    height: 62
                                    icon: "audio"
                                    active: root.musicPlaying
                                    color: "#F7FBFF"
                                    accentColor: "#58FFE1"
                                    strokeWidth: 5.0
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
                    spacing: 9

                    Row {
                        width: parent.width
                        height: 34
                        spacing: 10

                        Text {
                            width: parent.width * 0.58
                            anchors.verticalCenter: parent.verticalCenter
                            text: "TODAY"
                            color: "#F7FBFF"
                            font.family: root.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width * 0.42 - 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.locationName.length > 0 ? root.locationName : root.weatherStatus
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        width: parent.width
                        height: 156

                        NativePanel {
                            anchors.fill: parent
                            color: "#05070D"
                            borderColor: "#1D4C4A"
                            borderWidth: 1
                        }

                        Row {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 18

                            OemIcon {
                                width: 96
                                height: 96
                                anchors.verticalCenter: parent.verticalCenter
                                icon: "weather"
                                color: "#F7FBFF"
                                accentColor: "#FFD36B"
                                strokeWidth: 6.0
                                active: true
                            }

                            Column {
                                width: parent.width - 134
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Row {
                                    width: parent.width
                                    spacing: 10

                                    Text {
                                        width: 128
                                        text: root.formatTemp(root.displayTempC)
                                        color: "#F9FBFF"
                                        font.family: root.displayFont
                                        font.pixelSize: 82
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        lineHeight: 0.82
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    Column {
                                        width: parent.width - 138
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5

                                        Text {
                                            width: parent.width
                                            text: "\u00B0C"
                                            color: "#58FFE1"
                                            font.family: root.monoFont
                                            font.pixelSize: 18
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: root.weatherMoodLine(root.currentConditionLabel())
                                            color: "#FFD36B"
                                            font.family: root.displayFont
                                            font.pixelSize: 30
                                            font.weight: Font.Bold
                                            font.letterSpacing: 0
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: root.weatherMoodSubLine(root.currentConditionLabel())
                                    color: "#F7FBFF"
                                    font.family: root.displayFont
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    text: root.currentConditionLabel() + "  /  updated " + root.weatherUpdatedText
                                    color: "#9DB4FF"
                                    font.family: root.monoFont
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    Grid {
                        id: metricsGrid
                        width: parent.width
                        columns: 3
                        columnSpacing: 10
                        rowSpacing: 6

                        Repeater {
                            model: [
                                { "k": "FEELS", "v": root.formatTemp(root.displayFeelsC) + "\u00B0", "s": "outside" },
                                { "k": "RAIN", "v": root.formatRain(root.precipitationMm) + " MM", "s": root.rainShortLine(root.precipitationMm) },
                                { "k": "WIND", "v": (root.weatherWindDir.length > 0 ? root.weatherWindDir + " " : "") + root.formatWind(root.windKph), "s": "km/h" }
                            ]

                            Item {
                                width: (metricsGrid.width - 20) / 3
                                height: 54

                                NativePanel {
                                    anchors.fill: parent
                                    color: "#080B13"
                                    borderColor: "#162F35"
                                    borderWidth: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.k
                                        color: "#9DB4FF"
                                        font.family: root.monoFont
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.v
                                        color: "#F7FBFF"
                                        font.family: root.monoFont
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.s
                                        color: "#58FFE1"
                                        font.family: root.monoFont
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 22

                        Text {
                            width: parent.width * 0.54
                            anchors.verticalCenter: parent.verticalCenter
                            text: "7 DAYS"
                            color: "#F7FBFF"
                            font.family: root.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                        }

                        Text {
                            width: parent.width * 0.46
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.forecastStatus === "LIVE" ? root.forecastUpdatedText : root.forecastStatus
                            color: "#9DB4FF"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: forecastStrip
                        width: parent.width
                        height: 78
                        spacing: 6

                        Repeater {
                            model: root.forecastRows

                            Item {
                                width: (forecastStrip.width - forecastStrip.spacing * 6) / 7
                                height: forecastStrip.height

                                NativePanel {
                                    anchors.fill: parent
                                    color: index === 0 ? "#0B0E18" : "#060912"
                                    borderColor: index === 0 ? "#244B4A" : "#13272E"
                                    borderWidth: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: root.forecastCompactDayLabel(modelData.date, index)
                                        color: index === 0 ? "#58FFE1" : "#F7FBFF"
                                        font.family: root.monoFont
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: (modelData.high !== null ? modelData.high : "--") + "/" + (modelData.low !== null ? modelData.low : "--")
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
                                        text: modelData.label
                                        color: "#9DB4FF"
                                        font.family: root.monoFont
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.rain !== null ? modelData.rain + "%" : "--%"
                                        color: "#FFD36B"
                                        font.family: root.monoFont
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.forecastRows.length === 0
                            text: root.forecastStatus
                            color: "#FFD36B"
                            font.family: root.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 20
                visible: root.expandedMode === "radar"

                Column {
                    anchors.fill: parent
                    spacing: 9

                    Row {
                        width: parent.width
                        height: 34
                        spacing: 10

                        Text {
                            width: parent.width * 0.58
                            anchors.verticalCenter: parent.verticalCenter
                            text: "RADAR"
                            color: "#F7FBFF"
                            font.family: root.monoFont
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width * 0.42 - 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.radarStatus === "LIVE" ? root.radarFrameDisplayLabel() : root.radarStatus
                            color: root.radarStatus === "LIVE" ? "#9DB4FF" : "#FFD36B"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            font.letterSpacing: 0
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        width: parent.width
                        height: Math.max(360, parent.height - 122)
                        clip: false

                        NativePanel {
                            anchors.fill: parent
                            color: "#05070D"
                            borderColor: "#1D4C4A"
                            borderWidth: 1
                        }

                        RadarFrameItem {
                            id: detailRadarFrame
                            anchors.fill: parent
                            anchors.margins: 8
                            source: root.expandedMode === "radar" ? root.radarFrameUrl : ""
                            circular: false
                            backgroundVisible: true
                            guidesVisible: true
                            visible: ready
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 8
                            radius: 5
                            color: "#080913"
                            opacity: detailRadarFrame.ready ? 0.0 : 1.0

                            Column {
                                anchors.centerIn: parent
                                spacing: 10
                                visible: !detailRadarFrame.ready

                                WidgetLocal.RadarGlyph {
                                    width: 78
                                    height: 78
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    primaryColor: "#F7FBFF"
                                    accentColor: "#58FFE1"
                                    active: root.radarStatus === "LIVE"
                                }

                                Text {
                                    width: parent.width
                                    text: "RADAR"
                                    color: "#F7FBFF"
                                    font.family: root.displayFont
                                    font.pixelSize: 26
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: Math.min(320, detailRadarFrame.width * 0.70)
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.radarStatus === "LIVE" ? "RADAR LOADING" : root.radarStatus
                                    color: root.radarStatus === "LIVE" ? "#58FFE1" : "#FFD36B"
                                    font.family: root.monoFont
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    font.letterSpacing: 0
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                }
                            }
                        }

                    }

                    Row {
                        width: parent.width
                        height: 54
                        spacing: 10

                        Repeater {
                            model: [
                                { "k": "FRAME", "v": root.radarFrameDisplayLabel(), "s": "time" },
                                { "k": "SOURCE", "v": root.radarSiteName.length > 0 ? root.radarSiteName : "GPS", "s": root.formatDistanceKm(root.radarSiteDistanceKm) },
                                { "k": "STATUS", "v": root.radarStatus === "LIVE" ? "LIVE NOW" : root.radarStatus, "s": root.radarProduct.length > 0 ? root.radarProduct : root.radarSourceLabel() }
                            ]

                            Item {
                                width: (parent.width - 20) / 3
                                height: parent.height

                                NativePanel {
                                    anchors.fill: parent
                                    color: "#080B13"
                                    borderColor: "#162F35"
                                    borderWidth: 1
                                }

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.k
                                        color: "#9DB4FF"
                                        font.family: root.monoFont
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.v
                                        color: "#F7FBFF"
                                        font.family: root.monoFont
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.s
                                        color: "#58FFE1"
                                        font.family: root.monoFont
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
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
