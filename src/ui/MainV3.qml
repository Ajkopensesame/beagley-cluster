import QtQuick 2.15
import QtQuick.Window 2.15

import "./theme" as Theme
import "widgets" as W

Window {
    id: root

    width: 1920
    height: 720
    minimumWidth: 1920
    minimumHeight: 720
    maximumWidth: 1920
    maximumHeight: 720

    visibility: Window.Windowed
    flags: Qt.Window | Qt.CustomizeWindowHint | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    visible: true

    Theme.PurplePearlTheme { id: appTheme }
    color: "#02060B"
    readonly property real defaultMapLat: -27.4698
    readonly property real defaultMapLng: 153.0251
    readonly property string renderProfile: (typeof BEAGLEY_RENDER_PROFILE !== "undefined" && BEAGLEY_RENDER_PROFILE)
        ? String(BEAGLEY_RENDER_PROFILE)
        : "desktop"
    readonly property string effectLevel: (typeof BEAGLEY_EFFECT_LEVEL !== "undefined" && BEAGLEY_EFFECT_LEVEL)
        ? String(BEAGLEY_EFFECT_LEVEL)
        : "high"
    readonly property string mapRenderer: (typeof BEAGLEY_MAP_RENDERER !== "undefined" && BEAGLEY_MAP_RENDERER)
        ? String(BEAGLEY_MAP_RENDERER)
        : "native"
    readonly property bool lowEffectMode: effectLevel === "low" || effectLevel === "off"
    readonly property bool effectsOff: effectLevel === "off"
    readonly property bool stressScene: (typeof BEAGLEY_STRESS_SCENE !== "undefined" && BEAGLEY_STRESS_SCENE) ? true : false
    property real sharedEffectPhase: 0.0
    property real stressPhase: 0.0

    readonly property var hub: vehicleState
    readonly property bool linkOk: hub && hub.connected && !hub.linkStale
    readonly property bool truthOk: linkOk && !hub.bbbStale
    readonly property bool hotspotConnected: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.connected)
    readonly property bool hotspotIpLease: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.hasIpLease)
    readonly property bool internetOk: !!((typeof wifiSetup !== "undefined") && wifiSetup && wifiSetup.internetReachable)
    readonly property string hotspotState: (typeof wifiSetup !== "undefined") && wifiSetup ? String(wifiSetup.networkState || "waiting_for_hotspot") : "waiting_for_hotspot"
    readonly property bool gpsFixOk: !!(hub && hub.gpsFixValid)
    readonly property bool gpsEverValid: !!(hub && hub.gpsEverValid)
    readonly property bool liveMapPoseValid: !!(hub
        && hub.vehicleStateSeen
        && hub.gpsPoseValid
        && hub.gpsFixValid
        && !hub.linkStale
        && !hub.bbbStale
        && isFinite(Number(hub.gpsLat))
        && isFinite(Number(hub.gpsLng)))
    readonly property string gpsSourceText: hub && hub.gpsSource ? String(hub.gpsSource).toUpperCase() : "UNKNOWN"
    readonly property var navConnectivity: navigation ? (navigation.mapConnectivity || ({})) : ({})
    readonly property var navVehiclePose: navigation ? (navigation.mapVehiclePose || ({})) : ({})
    readonly property var navBanner: navigation && navigation.mapGuidanceBanner
        ? (navigation.mapGuidanceBanner.banner || ({}))
        : ({})
    readonly property bool hasActiveRoute: navigation && navigation.activeRoute && Object.keys(navigation.activeRoute).length > 0
    readonly property bool followUnlocked: navigation && navigation.followMode === "free_pan"
    readonly property bool gpsHoldingPose: !!navConnectivity.gpsUsingLastKnown
    readonly property string gearText: truthOk && hub && hub.gear ? hub.gear : "-"
    readonly property real speedValue: truthOk && hub ? (hub.speedKph || 0) : 0
    readonly property real rpmValue: truthOk && hub ? (hub.rpm || 0) : 0
    readonly property real fuelValue: truthOk && hub ? (hub.fuelPct || 0) : 0
    readonly property real coolantValue: truthOk && hub ? (hub.coolantC || 0) : 0
    readonly property real displaySpeedValue: stressScene ? (58 + 42 * Math.sin(stressPhase * 0.9)) : speedValue
    readonly property real displayRpmValue: stressScene ? (2400 + 1650 * (0.5 + 0.5 * Math.sin(stressPhase * 1.15 + 0.4))) : rpmValue
    readonly property real displayFuelValue: stressScene ? (48 + 14 * Math.sin(stressPhase * 0.12)) : fuelValue
    readonly property real displayCoolantValue: stressScene ? (81 + 7 * Math.sin(stressPhase * 0.18 + 1.6)) : coolantValue
    readonly property real displayMapLat: stressScene
        ? (root.defaultMapLat + 0.0028 * Math.sin(stressPhase * 0.12))
        : (liveMapPoseValid
        ? Number(hub.gpsLat)
        : (isFinite(Number(navVehiclePose.lat))
        ? Number(navVehiclePose.lat)
        : (isFinite(Number(hub && hub.gpsLat)) ? Number(hub.gpsLat) : root.defaultMapLat)))
    readonly property real displayMapLng: stressScene
        ? (root.defaultMapLng + 0.0046 * Math.cos(stressPhase * 0.12))
        : (liveMapPoseValid
        ? Number(hub.gpsLng)
        : (isFinite(Number(navVehiclePose.lng))
        ? Number(navVehiclePose.lng)
        : (isFinite(Number(hub && hub.gpsLng)) ? Number(hub.gpsLng) : root.defaultMapLng)))
    readonly property real displayMapBearing: stressScene
        ? ((stressPhase * 26) % 360)
        : (liveMapPoseValid
        ? Number(hub.gpsBearing)
        : (isFinite(Number(navVehiclePose.bearing))
        ? Number(navVehiclePose.bearing)
        : (isFinite(Number(hub && hub.gpsBearing)) ? Number(hub.gpsBearing) : 0)))
    readonly property real displayMapSpeed: stressScene
        ? Math.max(8, displaySpeedValue)
        : (liveMapPoseValid && isFinite(Number(hub && hub.gpsSpeedKph)) && Number(hub.gpsSpeedKph) > 0
        ? Number(hub.gpsSpeedKph)
        : (isFinite(Number(navVehiclePose.speedKph)) ? Number(navVehiclePose.speedKph) : speedValue))
    readonly property bool fallbackRouteOriginEnabled: false
    readonly property real fallbackRouteOriginLat: NaN
    readonly property real fallbackRouteOriginLng: NaN
    readonly property string fallbackRouteOriginLabel: ""
    property string pendingSuggestionQuery: ""
    property var keyboardRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["SPACE", ".", ",", "-", "BACKSPACE", "CLEAR"]
    ]
    property bool mapMenuOpen: false
    property bool navControlsOpen: false
    property bool searchKeyboardOpen: false

    readonly property int activeWarnings: {
        if (!truthOk || !hub) return 0
        var n = 0
        if (hub.warnBrake) n++
        if (hub.warnOil) n++
        if (hub.warnCharge) n++
        if (hub.warnDoor) n++
        if (hub.warnCheckEngine) n++
        if (hub.warnAT) n++
        if (hub.warnFuelLow) n++
        return n
    }

    function warningSummary() {
        if (!truthOk || !hub) return "NO LIVE VEHICLE DATA"
        var parts = []
        if (hub.warnBrake) parts.push("BRAKE")
        if (hub.warnOil) parts.push("OIL")
        if (hub.warnCharge) parts.push("CHARGE")
        if (hub.warnDoor) parts.push("DOOR")
        if (hub.warnCheckEngine) parts.push("CHECK ENGINE")
        if (hub.warnAT) parts.push("A/T")
        if (hub.warnFuelLow) parts.push("LOW FUEL")
        return parts.length > 0 ? parts.join("  •  ") : "SYSTEMS NOMINAL"
    }

    function statusText() {
        if (!hub || !hub.connected) return "LINK DOWN"
        if (hub.linkStale) return "LINK STALE"
        if (hub.bbbStale) return "BBB STALE"
        return "LIVE"
    }

    function radians(value) {
        return value * Math.PI / 180.0
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
        return 2.0 * earthRadius * Math.asin(Math.sqrt(h))
    }

    function suggestionOrigin() {
        return {
            lat: isFinite(Number(navVehiclePose.lat)) ? Number(navVehiclePose.lat) : NaN,
            lng: isFinite(Number(navVehiclePose.lng)) ? Number(navVehiclePose.lng) : NaN
        }
    }

    function routeSearchQuery(query) {
        const trimmed = String(query || "").trim()
        if (trimmed.length === 0)
            return
        if (navigation.searchResults.length > 0) {
            navigation.selectSearchResult(navigation.searchResults[0].id)
            navigation.setFollowEnabled(true)
            root.mapMenuOpen = false
            root.searchKeyboardOpen = false
            return
        }
        navigation.search(trimmed)
    }

    function applyKeyboardKey(key, target) {
        if (!target)
            return
        if (key === "SPACE") {
            target.insert(target.cursorPosition, " ")
            return
        }
        if (key === "BACKSPACE") {
            if (target.selectionStart !== target.selectionEnd) {
                target.remove(target.selectionStart, target.selectionEnd)
            } else if (target.cursorPosition > 0) {
                target.remove(target.cursorPosition - 1, target.cursorPosition)
            }
            return
        }
        if (key === "CLEAR") {
            target.text = ""
            return
        }
        target.insert(target.cursorPosition, key)
    }

    function fetchSearchSuggestions(query) {
        const trimmed = String(query || "").trim()
        pendingSuggestionQuery = trimmed
        if (trimmed.length < 2) {
            navigation.search("")
            return
        }
        navigation.search(trimmed)
    }

    function formatDistanceMeters(meters) {
        const value = Number(meters)
        if (!isFinite(value) || value <= 0)
            return "--"
        if (value >= 10000)
            return Math.round(value / 1000) + " km"
        if (value >= 1000)
            return (value / 1000).toFixed(1) + " km"
        return Math.round(value) + " m"
    }

    function formatDurationSeconds(seconds) {
        const value = Number(seconds)
        if (!isFinite(value) || value <= 0)
            return "--"
        const totalMinutes = Math.max(1, Math.round(value / 60))
        if (totalMinutes >= 60) {
            const hours = Math.floor(totalMinutes / 60)
            const minutes = totalMinutes % 60
            return hours + "h " + (minutes > 0 ? minutes + "m" : "")
        }
        return totalMinutes + " min"
    }

    function hotspotBadgeText() {
        if (hotspotState === "online")
            return "HOTSPOT ONLINE"
        if (hotspotState === "no_internet")
            return "HOTSPOT NO NET"
        if (hotspotState === "associated_no_ip")
            return "HOTSPOT DHCP"
        if (hotspotState === "no_config")
            return "HOTSPOT SETUP"
        return "HOTSPOT JOINING"
    }

    function gpsBadgeText() {
        if (gpsFixOk)
            return "GPS FIX"
        if (gpsHoldingPose)
            return "GPS HOLD"
        if (navigation.bbbLinkOk)
            return "GPS WEAK"
        return "GPS WAIT"
    }

    Component.onCompleted: {
        root.showNormal()
        root.raise()
        root.requestActivate()
    }

    Timer {
        id: effectClock
        interval: root.lowEffectMode ? 140 : 90
        running: !root.effectsOff
        repeat: true
        onTriggered: root.sharedEffectPhase += interval / 1000.0
    }

    Timer {
        id: stressClock
        interval: 50
        running: root.stressScene
        repeat: true
        onTriggered: root.stressPhase += interval / 1000.0
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.00; color: "#04070C" }
            GradientStop { position: 0.35; color: "#07111D" }
            GradientStop { position: 0.70; color: "#06131A" }
            GradientStop { position: 1.00; color: "#02060A" }
        }
    }

    Canvas {
        anchors.fill: parent
        opacity: 0.36
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const grad = ctx.createLinearGradient(0, 0, width, height)
            grad.addColorStop(0.0, "rgba(0,255,220,0.05)")
            grad.addColorStop(0.45, "rgba(0,136,255,0.03)")
            grad.addColorStop(1.0, "rgba(255,255,255,0.01)")
            ctx.fillStyle = grad
            ctx.fillRect(0, 0, width, height)

            ctx.strokeStyle = "rgba(120,200,255,0.08)"
            ctx.lineWidth = 1
            for (var x = -height; x < width + height; x += 54) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x - height * 0.26, height)
                ctx.stroke()
            }
        }
    }

    Item {
        id: canopy
        anchors.fill: parent
        anchors.margins: 18

        Rectangle {
            anchors.fill: parent
            radius: 34
            color: "#09111A"
            border.width: 1
            border.color: "#21435B"
        }

        Canvas {
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                const glow = ctx.createLinearGradient(0, 0, width, 0)
                glow.addColorStop(0.0, "rgba(41,209,255,0.11)")
                glow.addColorStop(0.2, "rgba(41,209,255,0.02)")
                glow.addColorStop(0.5, "rgba(0,0,0,0)")
                glow.addColorStop(0.8, "rgba(41,209,255,0.02)")
                glow.addColorStop(1.0, "rgba(41,209,255,0.11)")
                ctx.fillStyle = glow
                ctx.fillRect(0, 0, width, height)

                ctx.strokeStyle = "rgba(115,225,255,0.16)"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(width * 0.18, 110)
                ctx.lineTo(width * 0.34, 84)
                ctx.lineTo(width * 0.66, 84)
                ctx.lineTo(width * 0.82, 110)
                ctx.stroke()

                ctx.strokeStyle = "rgba(115,225,255,0.10)"
                ctx.beginPath()
                ctx.moveTo(width * 0.16, height - 108)
                ctx.lineTo(width * 0.36, height - 88)
                ctx.lineTo(width * 0.64, height - 88)
                ctx.lineTo(width * 0.84, height - 108)
                ctx.stroke()
            }
        }

        W.MapCenter {
            id: navField
            anchors.fill: parent
            mode: (typeof BEAGLEY_NO_MAP !== "undefined" && BEAGLEY_NO_MAP)
                ? "placeholder"
                : (root.mapRenderer === "web" ? "web" : "snapshot")
            interactionEnabled: !((typeof BEAGLEY_EMBEDDED_DISPLAY !== "undefined" && BEAGLEY_EMBEDDED_DISPLAY) || false)
            lat: root.displayMapLat
            lng: root.displayMapLng
            bearing: root.displayMapBearing
            speedKph: root.displayMapSpeed
            fixedOriginEnabled: fallbackRouteOriginEnabled
            fixedOriginLat: fallbackRouteOriginLat
            fixedOriginLng: fallbackRouteOriginLng
            fixedOriginLabel: fallbackRouteOriginLabel
            navigationState: (root.mapRenderer === "web") ? navigation.mapPayload : ({})
            mapVehiclePose: navigation.mapVehiclePose
            mapCameraHints: navigation.mapCameraHints
            mapRouteOverlay: navigation.mapRouteOverlay
            mapGuidanceBanner: navigation.mapGuidanceBanner
            mapConnectivity: navigation.mapConnectivity
            snapshotRefreshMs: 0
            videoEnabled: false
            videoUrl: ""
        }

        Item {
            id: leftSideMass
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: false
        }

        Item {
            id: rightSideMass
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            visible: false
        }

        Item {
            id: cornerMask
            anchors.fill: parent
            readonly property int cornerRadius: 34

            Canvas {
                anchors.left: parent.left
                anchors.top: parent.top
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(width, height)
                    ctx.arc(width, height, width, Math.PI, Math.PI * 1.5)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.right: parent.right
                anchors.top: parent.top
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(0, height)
                    ctx.arc(0, height, width, Math.PI * 1.5, Math.PI * 2.0)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(width, 0)
                    ctx.arc(width, 0, width, Math.PI * 0.5, Math.PI)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }

            Canvas {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: cornerMask.cornerRadius
                height: cornerMask.cornerRadius
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = root.color
                    ctx.fillRect(0, 0, width, height)
                    ctx.globalCompositeOperation = "destination-out"
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.arc(0, 0, width, 0, Math.PI * 0.5)
                    ctx.closePath()
                    ctx.fill()
                    ctx.globalCompositeOperation = "source-over"
                }
            }
        }

        Item {
            id: leftGaugeShell
            width: 760
            height: 760
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: -56

            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const cx = width / 2
                    const cy = height / 2
                    const innerR = width * 0.414
                    const outerR = width * 0.50
                    const fade = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
                    fade.addColorStop(0.00, "rgba(0,0,0,0.98)")
                    fade.addColorStop(0.62, "rgba(0,0,0,0.98)")
                    fade.addColorStop(0.82, "rgba(0,0,0,0.42)")
                    fade.addColorStop(0.93, "rgba(0,0,0,0.10)")
                    fade.addColorStop(1.00, "rgba(0,0,0,0.00)")

                    ctx.fillStyle = fade
                    ctx.beginPath()
                    ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
                    ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)
                    ctx.fill("evenodd")
                }
            }

            Item {
                id: speedPod
                anchors.centerIn: parent
                width: 628
                height: 628

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const cx = width / 2
                        const cy = height / 2
                        const outerR = width * 0.50
                        const innerR = width * 0.43

                        const barrel = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
                        barrel.addColorStop(0.00, "rgba(3,4,6,0.94)")
                        barrel.addColorStop(0.58, "rgba(2,3,4,0.98)")
                        barrel.addColorStop(1.00, "rgba(0,0,0,1.00)")

                        ctx.fillStyle = barrel
                        ctx.beginPath()
                        ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
                        ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)
                        ctx.fill("evenodd")
                    }
                }

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const cx = width / 2
                        const cy = height / 2
                        const r = width * 0.465

                        ctx.beginPath()
                        ctx.strokeStyle = "rgba(0,0,0,0.72)"
                        ctx.lineWidth = 18
                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                        ctx.stroke()

                        const rim = ctx.createLinearGradient(0, 0, width, height)
                        rim.addColorStop(0.00, "rgba(255,255,255,0.16)")
                        rim.addColorStop(0.18, "rgba(160,220,255,0.06)")
                        rim.addColorStop(0.55, "rgba(0,0,0,0.04)")
                        rim.addColorStop(1.00, "rgba(0,0,0,0.18)")

                        ctx.beginPath()
                        ctx.strokeStyle = rim
                        ctx.lineWidth = 6
                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.strokeStyle = "rgba(255,255,255,0.08)"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.arc(cx, cy, r - 7, Math.PI * 0.86, Math.PI * 1.56)
                        ctx.stroke()
                    }
                }
            }

            W.SpeedGauge {
                id: speedGauge
                anchors.centerIn: parent
                width: 640
                height: 670
                theme: appTheme
                vehicleState: hub
                maxSpeed: 140
                speed: displaySpeedValue
                coolantC: displayCoolantValue
                effectLevel: root.effectLevel
                matrixRainEnabled: !root.lowEffectMode
                matrixRainSharedPhase: root.sharedEffectPhase
            }

            W.GaugeChevronOrbit {
                parent: speedGauge
                anchors.fill: parent
                z: 84
                active: truthOk && !!hub.leftIndicator
                side: "left"
                simplified: root.lowEffectMode
                chevrons: root.lowEffectMode ? 6 : 11
                cycleMs: 1280
                orbitRadius: parent.width * 0.485
                chevronSize: parent.width * 0.030
                strokeWidth: 4.8
                strokeBoost: 2.4
                tailSpacingPhase: 0.026
                gravityBiasDeg: 44
                onColor: "#52FFE1"
            }
        }

        Item {
            id: rightGaugeShell
            width: 760
            height: 760
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: -56

            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const cx = width / 2
                    const cy = height / 2
                    const innerR = width * 0.414
                    const outerR = width * 0.50
                    const fade = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
                    fade.addColorStop(0.00, "rgba(0,0,0,0.98)")
                    fade.addColorStop(0.62, "rgba(0,0,0,0.98)")
                    fade.addColorStop(0.82, "rgba(0,0,0,0.42)")
                    fade.addColorStop(0.93, "rgba(0,0,0,0.10)")
                    fade.addColorStop(1.00, "rgba(0,0,0,0.00)")

                    ctx.fillStyle = fade
                    ctx.beginPath()
                    ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
                    ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)
                    ctx.fill("evenodd")
                }
            }

            Item {
                id: tachPod
                anchors.centerIn: parent
                width: 628
                height: 628

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const cx = width / 2
                        const cy = height / 2
                        const outerR = width * 0.50
                        const innerR = width * 0.43

                        const barrel = ctx.createRadialGradient(cx, cy, innerR, cx, cy, outerR)
                        barrel.addColorStop(0.00, "rgba(3,4,6,0.94)")
                        barrel.addColorStop(0.58, "rgba(2,3,4,0.98)")
                        barrel.addColorStop(1.00, "rgba(0,0,0,1.00)")

                        ctx.fillStyle = barrel
                        ctx.beginPath()
                        ctx.arc(cx, cy, outerR, 0, Math.PI * 2)
                        ctx.arc(cx, cy, innerR, 0, Math.PI * 2, true)
                        ctx.fill("evenodd")
                    }
                }

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const cx = width / 2
                        const cy = height / 2
                        const r = width * 0.465

                        ctx.beginPath()
                        ctx.strokeStyle = "rgba(0,0,0,0.72)"
                        ctx.lineWidth = 18
                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                        ctx.stroke()

                        const rim = ctx.createLinearGradient(0, 0, width, height)
                        rim.addColorStop(0.00, "rgba(255,255,255,0.16)")
                        rim.addColorStop(0.18, "rgba(160,220,255,0.06)")
                        rim.addColorStop(0.55, "rgba(0,0,0,0.04)")
                        rim.addColorStop(1.00, "rgba(0,0,0,0.18)")

                        ctx.beginPath()
                        ctx.strokeStyle = rim
                        ctx.lineWidth = 6
                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                        ctx.stroke()

                        ctx.beginPath()
                        ctx.strokeStyle = "rgba(255,255,255,0.08)"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.arc(cx, cy, r - 7, Math.PI * 0.86, Math.PI * 1.56)
                        ctx.stroke()
                    }
                }
            }

            W.TachGauge {
                id: tachGauge
                anchors.centerIn: parent
                width: 640
                height: 670
                theme: appTheme
                vehicleState: hub
                rpm: displayRpmValue
                fuelPct: displayFuelValue
                effectLevel: root.effectLevel
                matrixRainEnabled: !root.lowEffectMode
                matrixRainSharedPhase: root.sharedEffectPhase
            }

            W.GaugeChevronOrbit {
                parent: tachGauge
                anchors.fill: parent
                z: 84
                active: truthOk && !!hub.rightIndicator
                side: "right"
                simplified: root.lowEffectMode
                chevrons: root.lowEffectMode ? 6 : 11
                cycleMs: 1280
                orbitRadius: parent.width * 0.485
                chevronSize: parent.width * 0.030
                strokeWidth: 4.8
                strokeBoost: 2.4
                tailSpacingPhase: 0.026
                gravityBiasDeg: 44
                onColor: "#52FFE1"
            }
        }

        Item {
            id: mapUiLayer
            anchors.fill: parent
            z: 3000

            Rectangle {
                id: idlePrompt
                visible: !root.mapMenuOpen && !root.navControlsOpen && !root.hasActiveRoute && gpsFixOk
                width: Math.floor(parent.width / 3) - 72
                height: 56
                radius: 18
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 18
                color: "#09141BE8"
                border.width: 1
                border.color: "#35698A"

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Rectangle {
                        width: parent.width
                        height: parent.height
                        radius: 14
                        anchors.verticalCenter: parent.verticalCenter
                        color: "#102230"
                        border.width: 1
                        border.color: "#4F7FA0"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Where to?"
                                color: "#F7FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 21
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 140
                                text: "Search"
                                color: "#8ED6FF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.6
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.mapMenuOpen = true
                                root.searchKeyboardOpen = false
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: tripRail
                visible: !root.mapMenuOpen
                width: Math.floor(parent.width / 3)
                height: root.hasActiveRoute ? 108 : 68
                radius: 24
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                color: "#08121AE6"
                border.width: 1
                border.color: followUnlocked ? "#86D5FF" : "#2A5F8F"

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 10
                        visible: root.hasActiveRoute

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 30
                            radius: 11
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#2A5F8F"

                            Text {
                                anchors.centerIn: parent
                                text: "ETA " + (navigation.eta || "--")
                                color: "#F2FAFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                            }
                        }

                        Rectangle {
                            width: (parent.width - 10) / 2
                            height: 30
                            radius: 11
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#2A5F8F"

                            Text {
                                anchors.centerIn: parent
                                text: root.formatDistanceMeters(navigation.remainingDistanceMeters)
                                    + " • "
                                    + root.formatDurationSeconds(navigation.remainingDurationSeconds)
                                color: "#F2FAFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 0.6
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: "#102230"
                            border.width: 1
                            border.color: "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: "SEARCH"
                                color: "#F4FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.mapMenuOpen = true
                                    root.searchKeyboardOpen = false
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: "#114261"
                            border.width: 1
                            border.color: "#84D8FF"

                            Text {
                                anchors.centerIn: parent
                                text: followUnlocked ? "RECENTER" : "FOLLOW"
                                color: "#F5FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    navigation.recenter()
                                    navField.setFollowEnabled(true)
                                    root.navControlsOpen = false
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: navigation.muted ? "#4D2A2A" : "#102230"
                            border.width: 1
                            border.color: navigation.muted ? "#D79A9A" : "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: navigation.muted ? "UNMUTE" : "MUTE"
                                color: "#F5FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: navigation.setMuted(!navigation.muted)
                            }
                        }

                        Rectangle {
                            width: (parent.width - 24) / 4
                            height: 36
                            radius: 14
                            color: root.navControlsOpen ? "#17394D" : "#102230"
                            border.width: 1
                            border.color: root.navControlsOpen ? "#86D5FF" : "#35627F"

                            Text {
                                anchors.centerIn: parent
                                text: "MORE"
                                color: "#F4FBFF"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                font.letterSpacing: 1.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.navControlsOpen = !root.navControlsOpen
                            }
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: root.navControlsOpen || root.mapMenuOpen
                color: root.mapMenuOpen ? "#9601070D" : "#6201060C"

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.navControlsOpen = false
                        if (root.mapMenuOpen) {
                            root.mapMenuOpen = false
                            root.searchKeyboardOpen = false
                        }
                    }
                }
            }

            Rectangle {
                id: navControlsSheet
                visible: root.navControlsOpen
                width: Math.floor(parent.width / 3)
                height: Math.min(parent.height - 78, navControlsColumn.implicitHeight + 36)
                radius: 26
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: tripRail.top
                anchors.bottomMargin: 12
                color: "#0A121BEA"
                border.width: 1
                border.color: "#35698A"

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: navControlsColumn
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    Row {
                        width: parent.width

                        Text {
                            text: "Navigation"
                            color: "#F5FBFF"
                            font.family: appTheme.fontDisplay
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }

                        Item { width: Math.max(0, parent.width - 170); height: 1 }

                        Rectangle {
                            width: 42
                            height: 42
                            radius: 14
                            color: "#0B1720"
                            border.width: 1
                            border.color: "#456A7D"

                            Text {
                                anchors.centerIn: parent
                                text: "X"
                                color: "#EAF5FB"
                                font.family: appTheme.fontMono
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.navControlsOpen = false
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 64
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: "#23465A"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "Provider"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: String(navigation.providerStatus || "unknown").toUpperCase().replace("_", " ")
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 64
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: "#23465A"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "Hotspot"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: hotspotState === "online"
                                    ? "ONLINE"
                                    : (hotspotState === "no_internet"
                                        ? "NO INTERNET"
                                        : (hotspotState === "associated_no_ip"
                                            ? "WAITING IP"
                                            : (hotspotState === "no_config" ? "SETUP NEEDED" : "JOINING")))
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Rectangle {
                        visible: navigation.bbbLinkOk || gpsEverValid || hub.gpsAccuracyM > 0 || hub.gpsSatellites > 0
                        width: parent.width
                        height: visible ? 82 : 0
                        radius: 18
                        color: "#08121A"
                        border.width: 1
                        border.color: gpsFixOk ? "#2E8B67" : "#8A5D35"

                        Column {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 4

                            Text {
                                text: "BBB GPS"
                                color: "#84AFC4"
                                font.family: appTheme.fontMono
                                font.pixelSize: 13
                            }

                            Text {
                                text: gpsFixOk
                                    ? ("FIX  " + Math.max(0, hub.gpsSatellites) + " SAT")
                                    : (navigation.bbbLinkOk ? "NO FIX" : "WAITING")
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }

                            Text {
                                visible: hub.gpsAccuracyM > 0 || gpsEverValid
                                text: hub.gpsAccuracyM > 0
                                    ? ("±" + Math.round(hub.gpsAccuracyM) + " m")
                                    : (gpsEverValid ? "Holding last known BBB pose" : "Waiting for first valid fix")
                                color: "#8FB4C8"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                            }

                            Text {
                                text: "SRC " + gpsSourceText
                                color: gpsSourceText === "HARDWARE" ? "#89F1B8" : "#8FB4C8"
                                font.family: appTheme.fontMono
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 56
                        radius: 18
                        color: "#0B1720"
                        border.width: 1
                        border.color: hotspotState === "online" ? "#3B5665" : "#456A7D"
                        visible: hotspotState !== "online"

                        Text {
                            anchors.centerIn: parent
                            text: "SET UP WI-FI"
                            color: "#F5FBFF"
                            font.family: appTheme.fontMono
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (typeof wifiSetup !== "undefined")
                                    wifiSetup.showPrompt()
                                root.navControlsOpen = false
                            }
                        }
                    }
                }
            }

            Item {
                id: mapMenu
                visible: root.mapMenuOpen
                anchors.fill: parent

                Rectangle {
                    width: Math.floor(canopy.width / 3)
                    height: Math.min(parent.height - 44, mapMenuColumn.implicitHeight + 44)
                    radius: 28
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#0A121BDD"
                    border.width: 1
                    border.color: "#35698A"

                    MouseArea {
                        anchors.fill: parent
                    }

                    Column {
                        id: mapMenuColumn
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 10

                        Row {
                            width: parent.width
                            spacing: 12

                            Text {
                                width: Math.max(0, parent.width - 64)
                                text: "Where to?"
                                color: "#F5FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                verticalAlignment: Text.AlignVCenter
                            }

                            Rectangle {
                                width: 52
                                height: 52
                                radius: 16
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#456A7D"

                                Text {
                                    anchors.centerIn: parent
                                    text: "X"
                                    color: "#EAF5FB"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 16
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.mapMenuOpen = false
                                        root.searchKeyboardOpen = false
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 68
                            radius: 20
                            color: "#060B11"
                            border.width: 1
                            border.color: searchInput.activeFocus ? "#82C9F2" : "#2E5975"

                            TextInput {
                                id: searchInput
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                verticalAlignment: Text.AlignVCenter
                                color: "#F7FBFF"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 26
                                selectByMouse: true
                                clip: true
                                focus: root.mapMenuOpen && root.searchKeyboardOpen
                                onAccepted: routeButton.trigger()
                                onTextChanged: suggestionDebounce.restart()
                                onActiveFocusChanged: if (activeFocus) suggestionDebounce.restart()
                            }

                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 20
                                verticalAlignment: Text.AlignVCenter
                                text: "Search destination"
                                visible: searchInput.text.length === 0 && !searchInput.activeFocus
                                color: "#7092A7"
                                font.family: appTheme.fontDisplay
                                font.pixelSize: 26
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.searchKeyboardOpen = true
                                    searchInput.forceActiveFocus()
                                }
                            }
                        }

                        Timer {
                            id: suggestionDebounce
                            interval: 250
                            repeat: false
                            onTriggered: root.fetchSearchSuggestions(searchInput.text)
                        }

                        Rectangle {
                            width: parent.width
                            height: 240
                            radius: 20
                            color: "#071019"
                            border.width: 1
                            border.color: "#214C67"
                            clip: true

                            Column {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 6

                                Text {
                                    text: navigation.state === "searching"
                                        ? "Searching…"
                                        : (navigation.searchResults.length > 0
                                            ? "Results"
                                            : (searchInput.text.length >= 2 ? "No matches" : "Tap the field to search"))
                                    color: navigation.state === "searching" ? "#9FE7FF" : "#9FBFD2"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 14
                                }

                                ListView {
                                    width: parent.width
                                    height: parent.height - 30
                                    model: navigation.searchResults
                                    boundsBehavior: Flickable.StopAtBounds
                                    clip: true
                                    interactive: count > 4
                                    spacing: 8

                                    delegate: Rectangle {
                                        readonly property var itemData: modelData
                                        width: ListView.view ? ListView.view.width : 0
                                        height: 44
                                        radius: 12
                                        color: suggestionMouse.containsMouse ? "#143346" : "#0C1822"
                                        border.width: 1
                                        border.color: suggestionMouse.containsMouse ? "#86D5FF" : "#203D50"

                                        Column {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 6
                                            anchors.bottomMargin: 6
                                            spacing: 2

                                            Text {
                                                text: itemData.primary || itemData.label
                                                color: "#F5FBFF"
                                                font.family: appTheme.fontDisplay
                                                font.pixelSize: 18
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }

                                            Text {
                                                text: itemData.secondary || itemData.label
                                                color: "#8FB4C8"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                                width: parent.width
                                            }
                                        }

                                        MouseArea {
                                            id: suggestionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                searchInput.text = itemData.label || itemData.primary
                                                searchInput.cursorPosition = searchInput.text.length
                                                navigation.selectSearchResult(itemData.id)
                                                navigation.setFollowEnabled(true)
                                                navField.setFollowEnabled(true)
                                                root.mapMenuOpen = false
                                                root.searchKeyboardOpen = false
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: root.searchKeyboardOpen
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: root.keyboardRows

                                delegate: Row {
                                    property var keyRow: modelData
                                    spacing: 8
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Repeater {
                                        model: keyRow

                                        delegate: Rectangle {
                                            readonly property string keyValue: modelData
                                            width: keyValue === "SPACE" ? 220 : (keyValue === "BACKSPACE" || keyValue === "CLEAR" ? 100 : 50)
                                            height: 38
                                            radius: 14
                                            color: keyMouse.pressed ? "#2A7FAF" : "#102230"
                                            border.width: 1
                                            border.color: keyMouse.pressed ? "#B2EBFF" : "#35627F"

                                            Text {
                                                anchors.centerIn: parent
                                                text: keyValue === "BACKSPACE" ? "BKSP" : keyValue
                                                color: "#F4FBFF"
                                                font.family: appTheme.fontMono
                                                font.pixelSize: 15
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 1
                                            }

                                            MouseArea {
                                                id: keyMouse
                                                anchors.fill: parent
                                                onClicked: {
                                                    root.applyKeyboardKey(parent.keyValue, searchInput)
                                                    searchInput.forceActiveFocus()
                                                    suggestionDebounce.restart()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            spacing: 10
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                id: routeButton
                                width: 128
                                height: 54
                                radius: 18
                                color: "#1F6A97"
                                border.width: 1
                                border.color: "#82C9F2"

                                function trigger() {
                                    root.routeSearchQuery(searchInput.text)
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "ROUTE"
                                    color: "#F7FBFF"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: routeButton.trigger()
                                }
                            }

                            Rectangle {
                                width: 104
                                height: 54
                                radius: 18
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: "CLEAR"
                                    color: "#E6F1F8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        searchInput.text = ""
                                        navigation.search("")
                                        navigation.clearRoute()
                                        root.searchKeyboardOpen = false
                                    }
                                }
                            }

                            Rectangle {
                                width: 104
                                height: 54
                                radius: 18
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.searchKeyboardOpen ? "HIDE" : "KEYS"
                                    color: "#E6F1F8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.searchKeyboardOpen = !root.searchKeyboardOpen
                                }
                            }

                            Rectangle {
                                width: 128
                                height: 54
                                radius: 18
                                color: "#0B1720"
                                border.width: 1
                                border.color: "#476679"

                                Text {
                                    anchors.centerIn: parent
                                    text: "CLOSE"
                                    color: "#E6F1F8"
                                    font.family: appTheme.fontMono
                                    font.pixelSize: 17
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.8
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.mapMenuOpen = false
                                        root.searchKeyboardOpen = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    W.WiFiSetupOverlay {
        id: wifiOverlay
        anchors.fill: parent
        wifi: (typeof wifiSetup !== "undefined") ? wifiSetup : null
        theme: appTheme
    }
}
