#include "NavigationService.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QProcessEnvironment>
#include <QStandardPaths>
#include <QUrlQuery>
#include <QtMath>

#include "../system/WiFiSetupService.h"

namespace {
constexpr int kDefaultRouteRefreshSec = 30;
constexpr int kOverviewDurationMs = 1200;
constexpr int kRerouteVoiceDelayMs = 2000;
constexpr int kRerouteMinDistanceMs = 4000;

QString defaultNavCacheDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/navigation");
}

QString formatDistance(double meters)
{
    if (!qIsFinite(meters) || meters <= 0.0) {
        return QStringLiteral("--");
    }
    if (meters >= 1000.0) {
        return QStringLiteral("%1 km").arg(QString::number(meters / 1000.0, 'f', meters < 10000.0 ? 1 : 0));
    }
    return QStringLiteral("%1 m").arg(qRound(meters));
}

QString formatDuration(double seconds)
{
    if (!qIsFinite(seconds) || seconds <= 0.0) {
        return QStringLiteral("--");
    }
    const int mins = qRound(seconds / 60.0);
    if (mins < 60) {
        return QStringLiteral("%1 min").arg(mins);
    }
    const int hours = mins / 60;
    const int rem = mins % 60;
    return rem == 0
        ? QStringLiteral("%1 h").arg(hours)
        : QStringLiteral("%1 h %2 min").arg(hours).arg(rem);
}

double clampValue(double value, double minValue, double maxValue)
{
    return qMax(minValue, qMin(maxValue, value));
}

double segmentProjection(double px, double py, double ax, double ay, double bx, double by, double *distanceOut)
{
    const double dx = bx - ax;
    const double dy = by - ay;
    const double len2 = dx * dx + dy * dy;
    double t = 0.0;
    if (len2 > 0.0) {
        t = ((px - ax) * dx + (py - ay) * dy) / len2;
        t = clampValue(t, 0.0, 1.0);
    }
    const double projX = ax + t * dx;
    const double projY = ay + t * dy;
    if (distanceOut) {
        const double ex = px - projX;
        const double ey = py - projY;
        *distanceOut = qSqrt(ex * ex + ey * ey);
    }
    return t;
}

bool envEnabled(const char *name, bool fallback)
{
    if (!qEnvironmentVariableIsSet(name)) {
        return fallback;
    }
    const QString value = QString::fromUtf8(qgetenv(name)).trimmed().toLower();
    if (value.isEmpty()) {
        return fallback;
    }
    return value != QLatin1String("0")
        && value != QLatin1String("false")
        && value != QLatin1String("off")
        && value != QLatin1String("no");
}
} // namespace

NavigationService::NavigationService(VehicleStateClient *vehicleState, WiFiSetupService *wifiSetup, QObject *parent)
    : QObject(parent)
    , m_vehicleState(vehicleState)
    , m_wifiSetup(wifiSetup)
    , m_ttsEngine(qEnvironmentVariableIsSet("BEAGLEY_TTS_ENGINE")
            ? QString::fromUtf8(qgetenv("BEAGLEY_TTS_ENGINE")).trimmed()
            : QStringLiteral("piper"))
    , m_ttsVoice(qEnvironmentVariableIsSet("BEAGLEY_TTS_VOICE")
            ? QString::fromUtf8(qgetenv("BEAGLEY_TTS_VOICE")).trimmed()
            : QString())
    , m_playerCommand(playerExecutable())
    , m_navCacheDir(qEnvironmentVariableIsSet("BEAGLEY_NAV_CACHE_DIR")
            ? QString::fromUtf8(qgetenv("BEAGLEY_NAV_CACHE_DIR")).trimmed()
            : defaultNavCacheDir())
{
    m_routeRefreshTimer.setInterval((qEnvironmentVariableIsSet("BEAGLEY_NAV_ROUTE_REFRESH_SEC")
            ? qEnvironmentVariableIntValue("BEAGLEY_NAV_ROUTE_REFRESH_SEC")
            : kDefaultRouteRefreshSec) * 1000);
    connect(&m_routeRefreshTimer, &QTimer::timeout, this, &NavigationService::maybeRefreshRoute);
    m_routeRefreshTimer.start();

    m_overviewTimer.setSingleShot(true);
    m_overviewTimer.setInterval(kOverviewDurationMs);
    connect(&m_overviewTimer, &QTimer::timeout, this, [this]() {
        m_overviewActive = false;
        updateGuidance();
    });

    m_rerouteVoiceTimer.setSingleShot(true);
    m_rerouteVoiceTimer.setInterval(kRerouteVoiceDelayMs);
    connect(&m_rerouteVoiceTimer, &QTimer::timeout, this, [this]() {
        if (m_rerouting) {
            speakPrompt(QStringLiteral("Rerouting"), QStringLiteral("reroute-delay"));
        }
    });

    if (m_vehicleState) {
        const auto updateSlot = [this]() { updateFromVehicle(); };
        connect(m_vehicleState, &VehicleStateClient::speedKphChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsLatChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsLngChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsBearingChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsAccuracyMChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsTimestampMsChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsFixValidChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsSourceChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsSatellitesChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::gpsHeadingReliableChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::linkStaleChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::bbbStaleChanged, this, updateSlot);
        connect(m_vehicleState, &VehicleStateClient::connectedChanged, this, &NavigationService::updateConnectivityStatus);
        connect(m_vehicleState, &VehicleStateClient::vehicleStateSeenChanged, this, &NavigationService::updateConnectivityStatus);
        connect(m_vehicleState, &VehicleStateClient::gpsFixValidChanged, this, &NavigationService::updateConnectivityStatus);
        connect(m_vehicleState, &VehicleStateClient::gpsPoseValidChanged, this, &NavigationService::updateConnectivityStatus);
    }

    if (m_wifiSetup) {
        connect(m_wifiSetup, &WiFiSetupService::connectionChanged, this, &NavigationService::updateConnectivityStatus);
        connect(m_wifiSetup, &WiFiSetupService::internetReachableChanged, this, &NavigationService::updateConnectivityStatus);
    }

    ensureTtsReady();
    loadCache();
    loadRecents();
    const QString renderProfile = QString::fromUtf8(qgetenv("BEAGLEY_RENDER_PROFILE")).trimmed().toLower();
    m_emitLegacyMapPayload = envEnabled("BEAGLEY_MAP_PAYLOAD_LEGACY", renderProfile != QLatin1String("embedded"));
    qInfo() << "[NavigationService] legacy mapPayload bridge =" << m_emitLegacyMapPayload;
    updateConnectivityStatus();
    updateFromVehicle();
}

void NavigationService::search(const QString &query)
{
    const QString trimmed = query.trimmed();
    m_lastSearchQuery = trimmed;
    if (trimmed.size() < 2) {
        setSearchResults({});
        if (m_state == QLatin1String("searching")) {
            setState(QStringLiteral("idle"));
        }
        return;
    }

    updateConnectivityStatus();
    if (!providersAllowed()) {
        qWarning() << "[NavigationService] search blocked: hotspot path unavailable";
        setProviderStatus(QStringLiteral("offline"));
        setNetworkStatus(QStringLiteral("connecting_hotspot"));
        setSearchResults({});
        setState(m_activeRoute.isEmpty() ? QStringLiteral("idle") : QStringLiteral("active"));
        return;
    }

    setState(QStringLiteral("searching"));
    setNetworkStatus(QStringLiteral("searching"));
    QNetworkRequest request = m_provider.buildSearchRequest(trimmed);
    QNetworkReply *reply = m_provider.searchUsesPost()
        ? m_network.post(request, QByteArray())
        : m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[NavigationService] primary search failed" << reply->url() << reply->errorString();
            if (m_wifiSetup) {
                m_wifiSetup->refreshStatus();
            }
            setProviderStatus(QStringLiteral("search_degraded"));
            const Pose pose = currentPose();
            runFallbackSearch(m_lastSearchQuery, pose);
            return;
        }

        const Pose pose = currentPose();
        QList<SearchResultData> parsed = m_provider.parseSearchResponse(reply->readAll(), pose.lat, pose.lng);
        if (parsed.isEmpty()) {
            qWarning() << "[NavigationService] primary search returned no results, falling back" << reply->url();
            if (m_wifiSetup) {
                m_wifiSetup->refreshStatus();
            }
            setProviderStatus(QStringLiteral("search_degraded"));
            runFallbackSearch(m_lastSearchQuery, pose);
            return;
        }
        QVariantList results;
        for (const SearchResultData &result : parsed) {
            results.append(QVariantMap{
                {QStringLiteral("id"), result.id},
                {QStringLiteral("label"), result.label},
                {QStringLiteral("primary"), result.primary},
                {QStringLiteral("secondary"), result.secondary},
                {QStringLiteral("lat"), result.lat},
                {QStringLiteral("lng"), result.lng},
                {QStringLiteral("distanceMeters"), result.distanceMeters},
            });
        }
        setSearchResults(results);
        setState(m_activeRoute.isEmpty() ? QStringLiteral("idle") : QStringLiteral("active"));
        setNetworkStatus(QStringLiteral("online"));
        setProviderStatus(QStringLiteral("online"));
    });
}

void NavigationService::selectSearchResult(const QString &id)
{
    const QVariantMap result = searchResultAt(id);
    if (result.isEmpty()) {
        return;
    }
    setDestination(result.value(QStringLiteral("lat")).toDouble(),
        result.value(QStringLiteral("lng")).toDouble(),
        result.value(QStringLiteral("label")).toString());
}

void NavigationService::setDestination(double lat, double lng, const QString &label)
{
    m_destination = destinationToVariant(lat, lng, label);
    if (m_destination.isEmpty()) {
        return;
    }

    QVariantList nextRecents;
    for (const QVariant &item : m_recents) {
        const QVariantMap map = item.toMap();
        const bool duplicate = metersBetween(
            map.value(QStringLiteral("lat")).toDouble(),
            map.value(QStringLiteral("lng")).toDouble(),
            lat,
            lng) < 15.0;
        if (!duplicate) {
            nextRecents.append(item);
        }
    }
    nextRecents.prepend(m_destination);
    while (nextRecents.size() > 5) {
        nextRecents.removeLast();
    }
    setRecents(nextRecents);
    saveRecents();

    requestRoute(false);
}

void NavigationService::clearRoute()
{
    m_destination.clear();
    m_routeManeuvers.clear();
    m_routeProfile.clear();
    m_lastAdvancePromptId.clear();
    m_lastFinalPromptId.clear();
    m_currentManeuverIndex = -1;
    m_offRouteHits = 0;
    m_regressionSinceMs = 0;
    m_lastProgressMeters = 0.0;
    m_currentProgressMeters = 0.0;
    m_currentLateralMeters = 0.0;
    m_rerouting = false;
    m_rerouteVoiceTimer.stop();
    m_overviewActive = false;
    m_overviewTimer.stop();
    setActiveRoute({});
    setNextManeuver({});
    setFollowingManeuver({});
    setBanner({});
    setEta(QString());
    setRemainingDistanceMeters(0.0);
    setRemainingDurationSeconds(0.0);
    setTrafficDelaySeconds(0.0);
    setState(gpsReady() ? QStringLiteral("idle") : QStringLiteral("no_gps"));
    updateMapPayload();
    persistCache();
}

void NavigationService::setFollowEnabled(bool enabled)
{
    if (m_followEnabled == enabled) {
        return;
    }
    if (enabled && !gpsReady()) {
        qInfo() << "[NavigationService] follow enable ignored: BBB GPS not ready";
        updateMapPayload();
        return;
    }
    m_followEnabled = enabled;
    if (!enabled) {
        setFollowMode(QStringLiteral("free_pan"));
    } else {
        updateGuidance();
    }
}

void NavigationService::setMuted(bool muted)
{
    if (m_muted == muted) {
        return;
    }
    m_muted = muted;
    emit mutedChanged();
    ensureTtsReady();
}

void NavigationService::recenter()
{
    if (!gpsReady()) {
        qInfo() << "[NavigationService] recenter ignored: BBB GPS not ready";
        updateMapPayload();
        return;
    }
    m_followEnabled = true;
    m_overviewActive = true;
    m_overviewTimer.start();
    setFollowMode(QStringLiteral("overview"));
    updateGuidance();
}

void NavigationService::setState(const QString &state)
{
    if (m_state == state) {
        return;
    }
    m_state = state;
    emit navigationStateChanged();
    updateMapPayload();
}

void NavigationService::setFollowMode(const QString &followMode)
{
    if (m_followMode == followMode) {
        return;
    }
    m_followMode = followMode;
    emit navigationStateChanged();
    updateMapPayload();
}

void NavigationService::setSearchResults(const QVariantList &results)
{
    if (m_searchResults == results) {
        return;
    }
    m_searchResults = results;
    emit searchResultsChanged();
}

void NavigationService::setRecents(const QVariantList &recents)
{
    if (m_recents == recents) {
        return;
    }
    m_recents = recents;
    emit recentsChanged();
}

void NavigationService::setActiveRoute(const QVariantMap &route)
{
    if (m_activeRoute == route) {
        return;
    }
    m_activeRoute = route;
    emit routeChanged();
    updateMapPayload();
}

void NavigationService::setNextManeuver(const QVariantMap &maneuver)
{
    if (m_nextManeuver == maneuver) {
        return;
    }
    m_nextManeuver = maneuver;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setFollowingManeuver(const QVariantMap &maneuver)
{
    if (m_followingManeuver == maneuver) {
        return;
    }
    m_followingManeuver = maneuver;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setBanner(const QVariantMap &banner)
{
    if (m_banner == banner) {
        return;
    }
    m_banner = banner;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setEta(const QString &eta)
{
    if (m_eta == eta) {
        return;
    }
    m_eta = eta;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setRemainingDistanceMeters(double meters)
{
    if (qFuzzyCompare(m_remainingDistanceMeters, meters)) {
        return;
    }
    m_remainingDistanceMeters = meters;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setRemainingDurationSeconds(double seconds)
{
    if (qFuzzyCompare(m_remainingDurationSeconds, seconds)) {
        return;
    }
    m_remainingDurationSeconds = seconds;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setTrafficDelaySeconds(double seconds)
{
    if (qFuzzyCompare(m_trafficDelaySeconds, seconds)) {
        return;
    }
    m_trafficDelaySeconds = seconds;
    emit guidanceChanged();
    updateMapPayload();
}

void NavigationService::setNetworkStatus(const QString &status)
{
    if (m_networkStatus == status) {
        return;
    }
    m_networkStatus = status;
    emit networkStatusChanged();
    updateMapPayload();
}

void NavigationService::setProviderStatus(const QString &status)
{
    if (m_providerStatus == status) {
        return;
    }
    m_providerStatus = status;
    emit networkStatusChanged();
    updateMapPayload();
}

void NavigationService::setBbbLinkOk(bool ok)
{
    if (m_bbbLinkOk == ok) {
        return;
    }
    m_bbbLinkOk = ok;
    qInfo() << "[NavigationService] bbbLinkOk =" << m_bbbLinkOk;
    emit networkStatusChanged();
    updateMapPayload();
}

void NavigationService::setInternetOk(bool ok)
{
    if (m_internetOk == ok) {
        return;
    }
    m_internetOk = ok;
    qInfo() << "[NavigationService] internetOk =" << m_internetOk;
    emit networkStatusChanged();
    updateMapPayload();
}

void NavigationService::setTtsStatus(const QString &status)
{
    const QString effective = m_muted ? QStringLiteral("muted") : status;
    if (m_ttsStatus == effective) {
        return;
    }
    m_ttsStatus = effective;
    emit ttsStatusChanged();
}

void NavigationService::setMapPayload(const QVariantMap &payload)
{
    if (m_mapPayload == payload) {
        return;
    }
    m_mapPayload = payload;
    emit mapPayloadChanged();
}

void NavigationService::setMapVehiclePose(const QVariantMap &payload)
{
    if (m_mapVehiclePose == payload) {
        return;
    }
    m_mapVehiclePose = payload;
    emit mapVehiclePoseChanged();
}

void NavigationService::setMapCameraHints(const QVariantMap &payload)
{
    if (m_mapCameraHints == payload) {
        return;
    }
    m_mapCameraHints = payload;
    emit mapCameraHintsChanged();
}

void NavigationService::setMapRouteOverlay(const QVariantMap &payload)
{
    if (m_mapRouteOverlay == payload) {
        return;
    }
    m_mapRouteOverlay = payload;
    emit mapRouteOverlayChanged();
}

void NavigationService::setMapGuidanceBanner(const QVariantMap &payload)
{
    if (m_mapGuidanceBanner == payload) {
        return;
    }
    m_mapGuidanceBanner = payload;
    emit mapGuidanceBannerChanged();
}

void NavigationService::setMapConnectivity(const QVariantMap &payload)
{
    if (m_mapConnectivity == payload) {
        return;
    }
    m_mapConnectivity = payload;
    emit mapConnectivityChanged();
}

void NavigationService::updateConnectivityStatus()
{
    const bool bbbOk = m_vehicleState
        && m_vehicleState->connected()
        && !m_vehicleState->linkStale()
        && !m_vehicleState->bbbStale()
        && m_vehicleState->vehicleStateSeen();
    setBbbLinkOk(bbbOk);

    const bool hotspotReady = hotspotPathReady();
    const bool internetProbeOk = m_wifiSetup ? m_wifiSetup->internetReachable() : true;
    setInternetOk(internetProbeOk);

    if (!gpsReady()) {
        setNetworkStatus(QStringLiteral("gps_weak"));
    } else if (!hotspotReady) {
        setNetworkStatus(QStringLiteral("connecting_hotspot"));
    } else if (!internetProbeOk) {
        setNetworkStatus(m_activeRoute.isEmpty()
            ? QStringLiteral("degraded")
            : QStringLiteral("offline_cached"));
    } else if (m_networkStatus == QLatin1String("gps_weak")
               || m_networkStatus == QLatin1String("connecting_hotspot")
               || m_networkStatus == QLatin1String("offline_cached")
               || m_networkStatus == QLatin1String("degraded")) {
        setNetworkStatus(QStringLiteral("online"));
    }

    if (!hotspotReady) {
        setProviderStatus(QStringLiteral("offline"));
    } else if (internetProbeOk && m_providerStatus == QLatin1String("offline")) {
        setProviderStatus(QStringLiteral("online"));
    }
}

void NavigationService::requestRoute(bool reroute)
{
    if (m_destination.isEmpty()) {
        return;
    }
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    updateConnectivityStatus();
    if (!gpsReady()) {
        if (nowMs - m_lastGpsBlockedLogMs >= 5000) {
            qWarning() << "[NavigationService] route blocked: BBB GPS not ready";
            m_lastGpsBlockedLogMs = nowMs;
        }
        setBanner({
            {QStringLiteral("eyebrow"), QStringLiteral("GPS weak")},
            {QStringLiteral("primary"), QStringLiteral("Waiting for BBB GPS fix")},
            {QStringLiteral("secondary"), QStringLiteral("Destination saved. Route will build when GPS becomes valid.")},
        });
        setState(QStringLiteral("no_gps"));
        updateMapPayload();
        return;
    }
    if (!providersAllowed()) {
        if (m_lastRouteRequestMs > 0 && (nowMs - m_lastRouteRequestMs) < 10000) {
            return;
        }
        m_lastRouteRequestMs = nowMs;
        qWarning() << "[NavigationService] route blocked: hotspot path unavailable";
        setProviderStatus(QStringLiteral("offline"));
        setNetworkStatus(QStringLiteral("connecting_hotspot"));
        updateMapPayload();
        return;
    }
    beginRouteRequest(reroute);
}

void NavigationService::beginRouteRequest(bool reroute)
{
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    updateConnectivityStatus();
    if (!gpsReady()) {
        if (nowMs - m_lastGpsBlockedLogMs >= 5000) {
            qWarning() << "[NavigationService] route blocked: BBB GPS not ready";
            m_lastGpsBlockedLogMs = nowMs;
        }
        setBanner({
            {QStringLiteral("eyebrow"), QStringLiteral("GPS weak")},
            {QStringLiteral("primary"), QStringLiteral("Waiting for BBB GPS fix")},
            {QStringLiteral("secondary"), QStringLiteral("Current route stays visible until GPS recovers.")},
        });
        setState(QStringLiteral("no_gps"));
        updateMapPayload();
        return;
    }
    if (!providersAllowed()) {
        if (m_lastRouteRequestMs > 0 && (nowMs - m_lastRouteRequestMs) < 10000) {
            return;
        }
        m_lastRouteRequestMs = nowMs;
        setProviderStatus(QStringLiteral("offline"));
        setNetworkStatus(QStringLiteral("connecting_hotspot"));
        updateMapPayload();
        return;
    }

    const Pose pose = currentPose();
    if (!qIsFinite(pose.lat) || !qIsFinite(pose.lng)) {
        setState(QStringLiteral("no_gps"));
        return;
    }

    setState(reroute ? QStringLiteral("rerouting") : QStringLiteral("routing"));
    setNetworkStatus(QStringLiteral("routing"));
    m_rerouting = reroute;
    if (reroute) {
        emit rerouteStarted();
        m_rerouteVoiceTimer.start();
    }

    QNetworkRequest request = m_provider.buildRouteRequest(
        pose.lat,
        pose.lng,
        m_destination.value(QStringLiteral("lat")).toDouble(),
        m_destination.value(QStringLiteral("lng")).toDouble());
    QNetworkReply *reply = m_provider.routeUsesPost()
        ? m_network.post(request, m_provider.buildRouteBody(
            pose.lat,
            pose.lng,
            m_destination.value(QStringLiteral("lat")).toDouble(),
            m_destination.value(QStringLiteral("lng")).toDouble()))
        : m_network.get(request);
    m_lastRouteRequestMs = QDateTime::currentMSecsSinceEpoch();
    connect(reply, &QNetworkReply::finished, this, [this, reply, reroute]() {
        reply->deleteLater();
        m_rerouteVoiceTimer.stop();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[NavigationService] route request failed" << reply->url() << reply->errorString();
            if (m_wifiSetup) {
                m_wifiSetup->refreshStatus();
            }
            const bool providerPathOk = providersAllowed();
            setProviderStatus(providerPathOk ? QStringLiteral("route_degraded") : QStringLiteral("offline"));
            setNetworkStatus(providerPathOk ? QStringLiteral("degraded") : QStringLiteral("offline_cached"));
            setState(m_activeRoute.isEmpty() ? QStringLiteral("degraded") : QStringLiteral("active"));
            m_rerouting = false;
            emit rerouteFailed();
            updateGuidance();
            return;
        }

        const RouteData data = m_provider.parseRouteResponse(reply->readAll(), m_destination);
        if (data.geometry.size() < 2) {
            qWarning() << "[NavigationService] route response invalid" << reply->url();
            if (m_wifiSetup) {
                m_wifiSetup->refreshStatus();
            }
            setProviderStatus(QStringLiteral("route_degraded"));
            setNetworkStatus(providersAllowed() ? QStringLiteral("degraded") : QStringLiteral("offline_cached"));
            setState(m_activeRoute.isEmpty() ? QStringLiteral("degraded") : QStringLiteral("active"));
            m_rerouting = false;
            emit rerouteFailed();
            updateGuidance();
            return;
        }

        const bool hadRoute = !m_activeRoute.isEmpty();
        QVariantMap route = {
            {QStringLiteral("geometry"), QVariantMap{
                {QStringLiteral("type"), QStringLiteral("LineString")},
                {QStringLiteral("coordinates"), data.geometry},
            }},
            {QStringLiteral("distanceMeters"), data.distanceMeters},
            {QStringLiteral("durationSeconds"), data.durationSeconds},
            {QStringLiteral("destination"), data.destination},
        };
        setActiveRoute(route);
        m_routeProfile = buildRouteProfile(data.geometry);
        m_routeManeuvers = data.maneuvers;
        for (RouteManeuverData &maneuver : m_routeManeuvers) {
            maneuver.progressMeters = snapToRoute(maneuver.lat, maneuver.lng).progressMeters;
        }
        std::sort(m_routeManeuvers.begin(), m_routeManeuvers.end(), [](const RouteManeuverData &left, const RouteManeuverData &right) {
            return left.progressMeters < right.progressMeters;
        });
        m_lastAdvancePromptId.clear();
        m_lastFinalPromptId.clear();
        m_currentManeuverIndex = -1;
        m_overviewActive = reroute || !hadRoute;
        if (m_overviewActive) {
            m_overviewTimer.start();
        } else {
            m_overviewTimer.stop();
        }
        m_rerouting = false;
        setNetworkStatus(QStringLiteral("online"));
        setProviderStatus(QStringLiteral("online"));
        setState(QStringLiteral("active"));
        route.insert(QStringLiteral("maneuverCount"), m_routeManeuvers.size());
        m_lastProgressMeters = 0.0;
        m_offRouteHits = 0;
        m_regressionSinceMs = 0;
        persistCache();
        emit routeRecalculated();
        updateGuidance();
        if (reroute) {
            speakPrompt(QStringLiteral("Route updated"), QStringLiteral("reroute-ready"));
        }
    });
}

void NavigationService::updateFromVehicle()
{
    updateConnectivityStatus();
    const bool gpsNowReady = gpsReady();
    const Pose pose = livePose();
    if (gpsNowReady && qIsFinite(pose.lat) && qIsFinite(pose.lng)) {
        m_lastValidPose = pose;
        m_hasLastValidPose = true;
    }

    if (gpsNowReady != m_lastGpsReadyState) {
        if (gpsNowReady) {
            qInfo() << "[NavigationService] BBB GPS ready"
                    << "source=" << (m_vehicleState ? m_vehicleState->gpsSource() : QString())
                    << "lat=" << pose.lat
                    << "lng=" << pose.lng
                    << "accuracyM=" << (m_vehicleState ? m_vehicleState->gpsAccuracyM() : 0.0)
                    << "satellites=" << (m_vehicleState ? m_vehicleState->gpsSatellites() : 0);
        } else {
            qWarning() << "[NavigationService] BBB GPS degraded"
                       << "source=" << (m_vehicleState ? m_vehicleState->gpsSource() : QString())
                       << "connected=" << (m_vehicleState ? m_vehicleState->connected() : false)
                       << "linkStale=" << (m_vehicleState ? m_vehicleState->linkStale() : true)
                       << "bbbStale=" << (m_vehicleState ? m_vehicleState->bbbStale() : true)
                       << "fixValid=" << (m_vehicleState ? m_vehicleState->gpsFixValid() : false)
                       << "poseValid=" << (m_vehicleState ? m_vehicleState->gpsPoseValid() : false)
                       << "timestampMs=" << (m_vehicleState ? m_vehicleState->gpsTimestampMs() : 0);
        }
        m_lastGpsReadyState = gpsNowReady;
    }

    if (!gpsNowReady) {
        if (!m_activeRoute.isEmpty()) {
            setBanner({
                {QStringLiteral("eyebrow"), QStringLiteral("GPS weak")},
                {QStringLiteral("primary"), QStringLiteral("Holding last known BBB pose")},
                {QStringLiteral("secondary"), QStringLiteral("Current route stays visible until GPS recovers.")},
            });
        } else {
            setBanner({
                {QStringLiteral("eyebrow"), QStringLiteral("GPS weak")},
                {QStringLiteral("primary"), QStringLiteral("Waiting for BBB GPS fix")},
                {QStringLiteral("secondary"), QStringLiteral("Maps and routing stay blocked until the fix is valid.")},
            });
        }
        setState(m_activeRoute.isEmpty() ? QStringLiteral("no_gps") : QStringLiteral("degraded"));
        updateMapPayload();
        return;
    }

    if (m_networkStatus == QLatin1String("gps_weak")) {
        setNetworkStatus(QStringLiteral("online"));
    }

    updateGuidance();
}

void NavigationService::updateGuidance()
{
    const Pose pose = currentPose();
    const bool liveGpsReady = gpsReady();
    const bool hasRoute = !m_activeRoute.isEmpty() && !m_routeProfile.isEmpty();

    if (!hasRoute) {
        const QString primary = m_destination.isEmpty()
            ? QString()
            : m_destination.value(QStringLiteral("primary")).toString();
        if (m_destination.isEmpty()) {
            setBanner({});
        } else {
            setBanner({
                {QStringLiteral("eyebrow"), QStringLiteral("Navigation")},
                {QStringLiteral("primary"), primary.isEmpty() ? m_destination.value(QStringLiteral("label")).toString() : primary},
                {QStringLiteral("secondary"), m_destination.value(QStringLiteral("secondary")).toString()},
            });
        }
        setNextManeuver({});
        setFollowingManeuver({});
        setRemainingDistanceMeters(0.0);
        setRemainingDurationSeconds(0.0);
        setEta(QString());
        setFollowMode(m_followEnabled ? QStringLiteral("auto") : QStringLiteral("free_pan"));
        updateMapPayload();
        return;
    }

    const SnapResult snap = snapToRoute(pose.lat, pose.lng);
    m_currentProgressMeters = snap.progressMeters;
    m_currentLateralMeters = snap.lateralMeters;
    const double totalDistance = m_activeRoute.value(QStringLiteral("distanceMeters")).toDouble();
    const double totalDuration = m_activeRoute.value(QStringLiteral("durationSeconds")).toDouble();
    const double remainingDistance = qMax(0.0, totalDistance - snap.progressMeters);
    const double remainingDuration = totalDistance > 0.0
        ? qMax(0.0, totalDuration * (remainingDistance / totalDistance))
        : 0.0;

    setRemainingDistanceMeters(remainingDistance);
    setRemainingDurationSeconds(remainingDuration);
    setEta(QDateTime::currentDateTime().addSecs(qRound64(remainingDuration)).toString(QStringLiteral("h:mm ap")).toLower());

    int nextIndex = -1;
    for (int index = 0; index < m_routeManeuvers.size(); ++index) {
        if (m_routeManeuvers.at(index).progressMeters >= snap.progressMeters + 5.0) {
            nextIndex = index;
            break;
        }
    }
    if (nextIndex < 0 && !m_routeManeuvers.isEmpty()) {
        nextIndex = m_routeManeuvers.size() - 1;
    }
    m_currentManeuverIndex = nextIndex;

    if (nextIndex >= 0) {
        const RouteManeuverData &current = m_routeManeuvers.at(nextIndex);
        const double distanceToManeuver = qMax(0.0, current.progressMeters - snap.progressMeters);
        setNextManeuver(maneuverToVariant(current, remainingDistance));
        if (nextIndex + 1 < m_routeManeuvers.size()) {
            const RouteManeuverData &following = m_routeManeuvers.at(nextIndex + 1);
            setFollowingManeuver(maneuverToVariant(following, qMax(0.0, remainingDistance - current.distanceMeters)));
        } else {
            setFollowingManeuver({});
        }

        QString secondary = QStringLiteral("%1 to maneuver | %2 remaining | ETA %3")
            .arg(formatDistance(distanceToManeuver),
                 formatDistance(remainingDistance),
                 m_eta.isEmpty() ? QStringLiteral("--") : m_eta);
        if (m_trafficDelaySeconds > 0.0) {
            secondary += QStringLiteral(" | +%1 min traffic").arg(qRound(m_trafficDelaySeconds / 60.0));
        } else if (m_networkStatus != QLatin1String("online")) {
            secondary += QStringLiteral(" | %1").arg(m_networkStatus.replace(QLatin1Char('_'), QLatin1Char(' ')));
        }

        setBanner({
            {QStringLiteral("eyebrow"), m_followEnabled ? QStringLiteral("Guidance") : QStringLiteral("Map unlocked")},
            {QStringLiteral("primary"), current.instruction},
            {QStringLiteral("secondary"), secondary},
            {QStringLiteral("road"), current.road},
            {QStringLiteral("distanceMeters"), distanceToManeuver},
        });

        if (!m_followEnabled) {
            setFollowMode(QStringLiteral("free_pan"));
        } else if (m_overviewActive) {
            setFollowMode(QStringLiteral("overview"));
        } else if (distanceToManeuver > 1200.0) {
            setFollowMode(QStringLiteral("long_leg_relax"));
        } else if (distanceToManeuver <= finalPromptDistance(pose.speedKph)) {
            setFollowMode(QStringLiteral("turn"));
        } else if (distanceToManeuver <= qMax(120.0, pose.speedKph * 6.0)) {
            setFollowMode(QStringLiteral("approach"));
        } else {
            setFollowMode(QStringLiteral("auto"));
        }

        maybeTriggerPrompts();
    } else {
        setNextManeuver({});
        setFollowingManeuver({});
        setBanner({
            {QStringLiteral("eyebrow"), QStringLiteral("Arrival")},
            {QStringLiteral("primary"), QStringLiteral("Arrive at destination")},
            {QStringLiteral("secondary"), formatDistance(remainingDistance)},
        });
    }

    if (snap.lateralMeters > 35.0) {
        ++m_offRouteHits;
    } else {
        m_offRouteHits = 0;
    }

    if (snap.progressMeters + 10.0 < m_lastProgressMeters && pose.speedKph > 15.0) {
        if (m_regressionSinceMs == 0) {
            m_regressionSinceMs = QDateTime::currentMSecsSinceEpoch();
        }
    } else {
        m_regressionSinceMs = 0;
    }

    if (liveGpsReady && !m_rerouting && !m_destination.isEmpty()) {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        const bool progressRegressed = m_regressionSinceMs > 0 && (now - m_regressionSinceMs) >= kRerouteMinDistanceMs;
        if (m_offRouteHits >= 2 || progressRegressed) {
            requestRoute(true);
            return;
        }
    }

    m_lastProgressMeters = qMax(m_lastProgressMeters, snap.progressMeters);
    updateMapPayload();
}

void NavigationService::updateMapPayload()
{
    const Pose pose = currentPose();
    const bool ready = gpsReady();
    const bool usingLastKnown = !ready && m_hasLastValidPose;
    const QVariantMap vehiclePose = {
        {QStringLiteral("lat"), pose.lat},
        {QStringLiteral("lng"), pose.lng},
        {QStringLiteral("bearing"), pose.bearing},
        {QStringLiteral("speedKph"), pose.speedKph},
        {QStringLiteral("gpsReady"), ready},
        {QStringLiteral("gpsFixValid"), m_vehicleState ? m_vehicleState->gpsFixValid() : false},
        {QStringLiteral("gpsSource"), m_vehicleState ? m_vehicleState->gpsSource() : QString()},
        {QStringLiteral("accuracyM"), m_vehicleState ? m_vehicleState->gpsAccuracyM() : 0.0},
        {QStringLiteral("satellites"), m_vehicleState ? m_vehicleState->gpsSatellites() : 0},
        {QStringLiteral("headingReliable"), gpsReliableHeading()},
        {QStringLiteral("usingLastKnown"), usingLastKnown},
    };
    const QVariantMap cameraHints = buildCameraHints();
    const QVariantMap routeOverlay = {
        {QStringLiteral("state"), m_state},
        {QStringLiteral("followMode"), m_followMode},
        {QStringLiteral("followEnabled"), m_followEnabled},
        {QStringLiteral("destination"), m_destination},
        {QStringLiteral("route"), m_activeRoute},
        {QStringLiteral("progress"), QVariantMap{
            {QStringLiteral("distanceMeters"), m_currentProgressMeters},
            {QStringLiteral("lateralMeters"), m_currentLateralMeters},
            {QStringLiteral("remainingDistanceMeters"), m_remainingDistanceMeters},
            {QStringLiteral("remainingDurationSeconds"), m_remainingDurationSeconds},
        }},
        {QStringLiteral("nextManeuver"), m_nextManeuver},
        {QStringLiteral("followingManeuver"), m_followingManeuver},
    };
    const QVariantMap guidanceBanner = {
        {QStringLiteral("banner"), m_banner},
        {QStringLiteral("remainingDistanceMeters"), m_remainingDistanceMeters},
        {QStringLiteral("remainingDurationSeconds"), m_remainingDurationSeconds},
        {QStringLiteral("eta"), m_eta},
        {QStringLiteral("trafficDelaySeconds"), m_trafficDelaySeconds},
        {QStringLiteral("networkStatus"), m_networkStatus},
        {QStringLiteral("providerStatus"), m_providerStatus},
        {QStringLiteral("followMode"), m_followMode},
    };
    const QVariantMap connectivity = {
        {QStringLiteral("bbbLinkOk"), m_bbbLinkOk},
        {QStringLiteral("internetOk"), m_internetOk},
        {QStringLiteral("hotspotConnected"), m_wifiSetup ? m_wifiSetup->connected() : m_internetOk},
        {QStringLiteral("hotspotHasIpLease"), m_wifiSetup ? m_wifiSetup->hasIpLease() : m_internetOk},
        {QStringLiteral("gpsReady"), ready},
        {QStringLiteral("gpsFixValid"), m_vehicleState ? m_vehicleState->gpsFixValid() : false},
        {QStringLiteral("gpsPoseValid"), m_vehicleState ? m_vehicleState->gpsPoseValid() : false},
        {QStringLiteral("gpsEverValid"), m_vehicleState ? m_vehicleState->gpsEverValid() : m_hasLastValidPose},
        {QStringLiteral("gpsUsingLastKnown"), usingLastKnown},
    };

    setMapVehiclePose(vehiclePose);
    setMapCameraHints(cameraHints);
    setMapRouteOverlay(routeOverlay);
    setMapGuidanceBanner(guidanceBanner);
    setMapConnectivity(connectivity);

    if (m_emitLegacyMapPayload) {
        QVariantMap payload = {
            {QStringLiteral("state"), m_state},
            {QStringLiteral("followMode"), m_followMode},
            {QStringLiteral("followEnabled"), m_followEnabled},
            {QStringLiteral("vehiclePose"), vehiclePose},
            {QStringLiteral("destination"), m_destination},
            {QStringLiteral("route"), m_activeRoute},
            {QStringLiteral("progress"), routeOverlay.value(QStringLiteral("progress")).toMap()},
            {QStringLiteral("nextManeuver"), m_nextManeuver},
            {QStringLiteral("followingManeuver"), m_followingManeuver},
            {QStringLiteral("banner"), m_banner},
            {QStringLiteral("remainingDistanceMeters"), m_remainingDistanceMeters},
            {QStringLiteral("remainingDurationSeconds"), m_remainingDurationSeconds},
            {QStringLiteral("eta"), m_eta},
            {QStringLiteral("trafficDelaySeconds"), m_trafficDelaySeconds},
            {QStringLiteral("networkStatus"), m_networkStatus},
            {QStringLiteral("providerStatus"), m_providerStatus},
            {QStringLiteral("connectivity"), connectivity},
            {QStringLiteral("ttsStatus"), m_ttsStatus},
            {QStringLiteral("camera"), cameraHints},
        };
        setMapPayload(payload);
    }
}

void NavigationService::runFallbackSearch(const QString &query, const Pose &pose)
{
    const QString trimmed = query.trimmed();
    if (trimmed.size() < 2) {
        setSearchResults({});
        setState(m_activeRoute.isEmpty() ? QStringLiteral("idle") : QStringLiteral("active"));
        return;
    }

    QNetworkRequest request = m_provider.buildFallbackSearchRequest(trimmed);
    QNetworkReply *reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, pose]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[NavigationService] fallback search failed" << reply->url() << reply->errorString();
            const bool providerPathOk = providersAllowed();
            setProviderStatus(providerPathOk ? QStringLiteral("search_degraded") : QStringLiteral("offline"));
            setNetworkStatus(providerPathOk ? QStringLiteral("degraded") : QStringLiteral("connecting_hotspot"));
            setSearchResults({});
            setState(m_activeRoute.isEmpty() ? QStringLiteral("idle") : QStringLiteral("degraded"));
            return;
        }

        QList<SearchResultData> parsed = m_provider.parseSearchResponse(reply->readAll(), pose.lat, pose.lng);
        QVariantList results;
        for (const SearchResultData &result : parsed) {
            results.append(QVariantMap{
                {QStringLiteral("id"), result.id},
                {QStringLiteral("label"), result.label},
                {QStringLiteral("primary"), result.primary},
                {QStringLiteral("secondary"), result.secondary},
                {QStringLiteral("lat"), result.lat},
                {QStringLiteral("lng"), result.lng},
                {QStringLiteral("distanceMeters"), result.distanceMeters},
            });
        }
        setSearchResults(results);
        setState(m_activeRoute.isEmpty() ? QStringLiteral("idle") : QStringLiteral("active"));
        setNetworkStatus(QStringLiteral("online"));
    });
}

void NavigationService::maybeTriggerPrompts()
{
    if (m_muted || m_currentManeuverIndex < 0 || m_currentManeuverIndex >= m_routeManeuvers.size()) {
        return;
    }

    const Pose pose = currentPose();
    const RouteManeuverData &maneuver = m_routeManeuvers.at(m_currentManeuverIndex);
    const double distanceMeters = qMax(0.0, maneuver.progressMeters - m_currentProgressMeters);
    const double speedMps = qMax(1.0, pose.speedKph / 3.6);
    const double secondsToManeuver = distanceMeters / speedMps;
    const QString advanceId = maneuver.id + QStringLiteral("-advance");
    const QString finalId = maneuver.id + QStringLiteral("-final");

    if (m_lastAdvancePromptId != advanceId
        && (distanceMeters <= advancePromptDistance(pose.speedKph) || secondsToManeuver <= advancePromptSeconds(pose.speedKph))) {
        m_lastAdvancePromptId = advanceId;
        speakPrompt(buildAdvancePrompt(maneuver, distanceMeters), advanceId);
    }

    if (m_lastFinalPromptId != finalId
        && distanceMeters <= finalPromptDistance(pose.speedKph)
        && secondsToManeuver <= finalPromptSeconds(pose.speedKph)) {
        m_lastFinalPromptId = finalId;
        speakPrompt(buildFinalPrompt(maneuver), finalId, true);
    }
}

void NavigationService::maybeRefreshRoute()
{
    if (m_activeRoute.isEmpty() || m_destination.isEmpty() || m_rerouting) {
        return;
    }
    if (!gpsReady()) {
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        if (nowMs - m_lastGpsBlockedLogMs >= 5000) {
            qInfo() << "[NavigationService] reroute suppressed: BBB GPS weak or stale";
            m_lastGpsBlockedLogMs = nowMs;
        }
        return;
    }
    if (QDateTime::currentMSecsSinceEpoch() - m_lastRouteRequestMs < 10000) {
        return;
    }
    beginRouteRequest(false);
}

void NavigationService::persistCache() const
{
    QDir().mkpath(m_navCacheDir);
    QFile file(m_navCacheDir + QStringLiteral("/active_route.json"));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }

    QVariantList maneuvers;
    for (const RouteManeuverData &maneuver : m_routeManeuvers) {
        maneuvers.append(QVariantMap{
            {QStringLiteral("id"), maneuver.id},
            {QStringLiteral("type"), maneuver.type},
            {QStringLiteral("modifier"), maneuver.modifier},
            {QStringLiteral("instruction"), maneuver.instruction},
            {QStringLiteral("road"), maneuver.road},
            {QStringLiteral("lat"), maneuver.lat},
            {QStringLiteral("lng"), maneuver.lng},
            {QStringLiteral("distanceMeters"), maneuver.distanceMeters},
            {QStringLiteral("durationSeconds"), maneuver.durationSeconds},
            {QStringLiteral("progressMeters"), maneuver.progressMeters},
            {QStringLiteral("exit"), maneuver.exit},
        });
    }

    const QVariantMap root = {
        {QStringLiteral("destination"), m_destination},
        {QStringLiteral("route"), m_activeRoute},
        {QStringLiteral("maneuvers"), maneuvers},
    };
    file.write(QJsonDocument::fromVariant(root).toJson(QJsonDocument::Compact));
}

void NavigationService::loadCache()
{
    QFile file(cacheDirectory() + QStringLiteral("/active_route.json"));
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    const QVariantMap root = doc.object().toVariantMap();
    const QVariantMap route = root.value(QStringLiteral("route")).toMap();
    if (route.isEmpty()) {
        return;
    }

    m_destination = root.value(QStringLiteral("destination")).toMap();
    setActiveRoute(route);
    m_routeProfile = buildRouteProfile(route.value(QStringLiteral("geometry")).toMap().value(QStringLiteral("coordinates")).toList());

    const QVariantList maneuvers = root.value(QStringLiteral("maneuvers")).toList();
    m_routeManeuvers.clear();
    for (const QVariant &item : maneuvers) {
        const QVariantMap map = item.toMap();
        RouteManeuverData maneuver;
        maneuver.id = map.value(QStringLiteral("id")).toString();
        maneuver.type = map.value(QStringLiteral("type")).toString();
        maneuver.modifier = map.value(QStringLiteral("modifier")).toString();
        maneuver.instruction = map.value(QStringLiteral("instruction")).toString();
        maneuver.road = map.value(QStringLiteral("road")).toString();
        maneuver.lat = map.value(QStringLiteral("lat")).toDouble();
        maneuver.lng = map.value(QStringLiteral("lng")).toDouble();
        maneuver.distanceMeters = map.value(QStringLiteral("distanceMeters")).toDouble();
        maneuver.durationSeconds = map.value(QStringLiteral("durationSeconds")).toDouble();
        maneuver.progressMeters = map.value(QStringLiteral("progressMeters")).toDouble();
        maneuver.exit = map.value(QStringLiteral("exit")).toInt();
        m_routeManeuvers.append(maneuver);
    }
}

void NavigationService::loadRecents()
{
    QFile file(cacheDirectory() + QStringLiteral("/recents.json"));
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    setRecents(doc.array().toVariantList());
}

void NavigationService::saveRecents() const
{
    QDir().mkpath(m_navCacheDir);
    QFile file(m_navCacheDir + QStringLiteral("/recents.json"));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument::fromVariant(m_recents).toJson(QJsonDocument::Compact));
}

QString NavigationService::cacheDirectory() const
{
    if (!m_navCacheDir.isEmpty()) {
        return m_navCacheDir;
    }
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/navigation");
}

NavigationService::Pose NavigationService::livePose() const
{
    Pose pose;
    if (m_vehicleState) {
        pose.lat = m_vehicleState->gpsLat();
        pose.lng = m_vehicleState->gpsLng();
        pose.bearing = m_vehicleState->gpsBearing();
        pose.speedKph = m_vehicleState->speedKph();
    }
    return pose;
}

NavigationService::Pose NavigationService::currentPose() const
{
    const Pose pose = livePose();
    if (gpsReady()) {
        return pose;
    }
    if (m_hasLastValidPose) {
        Pose frozen = m_lastValidPose;
        frozen.speedKph = pose.speedKph;
        return frozen;
    }
    return pose;
}

bool NavigationService::hotspotPathReady() const
{
    if (!m_wifiSetup) {
        return true;
    }
    return m_wifiSetup->connected() && m_wifiSetup->hasIpLease();
}

bool NavigationService::providersAllowed() const
{
    return hotspotPathReady();
}

bool NavigationService::gpsReady() const
{
    if (!m_vehicleState) {
        return false;
    }
    if (!m_vehicleState->vehicleStateSeen() || !m_vehicleState->gpsPoseValid()) {
        return false;
    }
    if (m_vehicleState->linkStale() || m_vehicleState->bbbStale()) {
        return false;
    }
    if (!m_vehicleState->gpsFixValid()) {
        return false;
    }
    return qIsFinite(m_vehicleState->gpsLat()) && qIsFinite(m_vehicleState->gpsLng());
}

bool NavigationService::gpsReliableHeading() const
{
    if (!m_vehicleState) {
        return false;
    }
    if (m_vehicleState->gpsHeadingReliable()) {
        return true;
    }
    return m_vehicleState->speedKph() > 15.0;
}

QVariantMap NavigationService::searchResultAt(const QString &id) const
{
    for (const QVariant &item : m_searchResults) {
        const QVariantMap map = item.toMap();
        if (map.value(QStringLiteral("id")).toString() == id) {
            return map;
        }
    }
    return {};
}

QList<NavigationService::RouteProfilePoint> NavigationService::buildRouteProfile(const QVariantList &geometry) const
{
    QList<RouteProfilePoint> out;
    double cumulative = 0.0;
    for (int index = 0; index < geometry.size(); ++index) {
        const QVariantList point = geometry.at(index).toList();
        if (point.size() < 2) {
            continue;
        }
        RouteProfilePoint item;
        item.lng = point.at(0).toDouble();
        item.lat = point.at(1).toDouble();
        if (!out.isEmpty()) {
            cumulative += metersBetween(out.last().lat, out.last().lng, item.lat, item.lng);
        }
        item.meters = cumulative;
        out.append(item);
    }
    return out;
}

double NavigationService::metersBetween(double aLat, double aLng, double bLat, double bLng) const
{
    static constexpr double kEarthRadius = 6371000.0;
    const double dLat = qDegreesToRadians(bLat - aLat);
    const double dLng = qDegreesToRadians(bLng - aLng);
    const double lat1 = qDegreesToRadians(aLat);
    const double lat2 = qDegreesToRadians(bLat);
    const double sinLat = qSin(dLat / 2.0);
    const double sinLng = qSin(dLng / 2.0);
    const double h = sinLat * sinLat + qCos(lat1) * qCos(lat2) * sinLng * sinLng;
    return 2.0 * kEarthRadius * qAsin(qSqrt(qBound(0.0, h, 1.0)));
}

double NavigationService::headingBetween(double aLat, double aLng, double bLat, double bLng) const
{
    const double lat1 = qDegreesToRadians(aLat);
    const double lat2 = qDegreesToRadians(bLat);
    const double dLng = qDegreesToRadians(bLng - aLng);
    const double y = qSin(dLng) * qCos(lat2);
    const double x = qCos(lat1) * qSin(lat2) - qSin(lat1) * qCos(lat2) * qCos(dLng);
    double bearing = qRadiansToDegrees(qAtan2(y, x));
    while (bearing < 0.0) {
        bearing += 360.0;
    }
    while (bearing >= 360.0) {
        bearing -= 360.0;
    }
    return bearing;
}

NavigationService::SnapResult NavigationService::snapToRoute(double lat, double lng) const
{
    SnapResult best;
    if (m_routeProfile.size() < 2) {
        return best;
    }

    const double latScale = 111320.0;
    const double lngScale = qCos(qDegreesToRadians(lat)) * 111320.0;
    const double px = lng * lngScale;
    const double py = lat * latScale;
    double bestDistance = std::numeric_limits<double>::max();
    double bestProgress = 0.0;

    for (int index = 1; index < m_routeProfile.size(); ++index) {
        const RouteProfilePoint &prev = m_routeProfile.at(index - 1);
        const RouteProfilePoint &next = m_routeProfile.at(index);
        const double ax = prev.lng * lngScale;
        const double ay = prev.lat * latScale;
        const double bx = next.lng * lngScale;
        const double by = next.lat * latScale;
        double segmentDistance = 0.0;
        const double t = segmentProjection(px, py, ax, ay, bx, by, &segmentDistance);
        if (segmentDistance < bestDistance) {
            bestDistance = segmentDistance;
            bestProgress = prev.meters + (next.meters - prev.meters) * t;
        }
    }

    best.progressMeters = bestProgress;
    best.lateralMeters = bestDistance;
    return best;
}

QVariantMap NavigationService::maneuverToVariant(const RouteManeuverData &maneuver, double remainingAfterMeters) const
{
    return {
        {QStringLiteral("id"), maneuver.id},
        {QStringLiteral("type"), maneuver.type},
        {QStringLiteral("classification"), classifyManeuver(maneuver)},
        {QStringLiteral("modifier"), maneuver.modifier},
        {QStringLiteral("instruction"), maneuver.instruction},
        {QStringLiteral("road"), maneuver.road},
        {QStringLiteral("lat"), maneuver.lat},
        {QStringLiteral("lng"), maneuver.lng},
        {QStringLiteral("distanceMeters"), maneuver.distanceMeters},
        {QStringLiteral("durationSeconds"), maneuver.durationSeconds},
        {QStringLiteral("progressMeters"), maneuver.progressMeters},
        {QStringLiteral("remainingAfterMeters"), remainingAfterMeters},
        {QStringLiteral("exit"), maneuver.exit},
    };
}

QVariantMap NavigationService::destinationToVariant(double lat, double lng, const QString &label) const
{
    if (!qIsFinite(lat) || !qIsFinite(lng)) {
        return {};
    }

    const QString trimmed = label.trimmed();
    QString primary = trimmed;
    QString secondary;
    const QStringList parts = trimmed.split(QLatin1Char(','));
    if (parts.size() > 1) {
        primary = parts.mid(0, 2).join(QStringLiteral(", ")).trimmed();
        secondary = parts.mid(2).join(QStringLiteral(", ")).trimmed();
    }

    return {
        {QStringLiteral("id"), QStringLiteral("destination-%1").arg(QDateTime::currentMSecsSinceEpoch())},
        {QStringLiteral("label"), trimmed},
        {QStringLiteral("primary"), primary},
        {QStringLiteral("secondary"), secondary},
        {QStringLiteral("lat"), lat},
        {QStringLiteral("lng"), lng},
    };
}

QString NavigationService::classifyManeuver(const RouteManeuverData &maneuver) const
{
    const QString type = maneuver.type.toLower();
    if (type == QLatin1String("arrive")) {
        return QStringLiteral("arrival");
    }
    if (type == QLatin1String("roundabout") || type == QLatin1String("rotary")) {
        return QStringLiteral("roundabout");
    }
    if (type == QLatin1String("on ramp") || type == QLatin1String("off ramp")) {
        return QStringLiteral("ramp");
    }
    if (type == QLatin1String("fork")) {
        return QStringLiteral("fork");
    }
    if (type == QLatin1String("merge")) {
        return QStringLiteral("major_turn");
    }
    if (type == QLatin1String("turn")) {
        return maneuver.distanceMeters >= 120.0 ? QStringLiteral("major_turn") : QStringLiteral("minor_turn");
    }
    return QStringLiteral("continue");
}

QString NavigationService::buildAdvancePrompt(const RouteManeuverData &maneuver, double distanceMeters) const
{
    if (classifyManeuver(maneuver) == QLatin1String("roundabout") && maneuver.exit > 0) {
        return QStringLiteral("In %1, at the roundabout take exit %2")
            .arg(formatDistance(distanceMeters))
            .arg(maneuver.exit);
    }
    return QStringLiteral("In %1, %2").arg(formatDistance(distanceMeters), maneuver.instruction.toLower());
}

QString NavigationService::buildFinalPrompt(const RouteManeuverData &maneuver) const
{
    if (classifyManeuver(maneuver) == QLatin1String("roundabout") && maneuver.exit > 0) {
        return QStringLiteral("At the roundabout, take exit %1").arg(maneuver.exit);
    }
    return maneuver.instruction;
}

double NavigationService::advancePromptDistance(double speedKph) const
{
    if (speedKph > 95.0) {
        return 800.0;
    }
    if (speedKph >= 75.0) {
        return 450.0;
    }
    if (speedKph >= 45.0) {
        return 250.0;
    }
    return 120.0;
}

double NavigationService::finalPromptDistance(double speedKph) const
{
    if (speedKph > 95.0) {
        return 140.0;
    }
    if (speedKph >= 75.0) {
        return 90.0;
    }
    if (speedKph >= 45.0) {
        return 60.0;
    }
    return 35.0;
}

double NavigationService::advancePromptSeconds(double speedKph) const
{
    if (speedKph > 95.0) {
        return 20.0;
    }
    if (speedKph >= 75.0) {
        return 15.0;
    }
    if (speedKph >= 45.0) {
        return 12.0;
    }
    return 10.0;
}

double NavigationService::finalPromptSeconds(double speedKph) const
{
    if (speedKph > 95.0) {
        return 6.0;
    }
    if (speedKph >= 75.0) {
        return 5.0;
    }
    if (speedKph >= 45.0) {
        return 4.0;
    }
    return 3.0;
}

QVariantMap NavigationService::buildCameraHints() const
{
    const Pose pose = currentPose();
    double baseZoom = 17.2;
    if (pose.speedKph >= 100.0) {
        baseZoom = 14.4;
    } else if (pose.speedKph >= 70.0) {
        baseZoom = 15.1;
    } else if (pose.speedKph >= 40.0) {
        baseZoom = 15.8;
    } else if (pose.speedKph >= 20.0) {
        baseZoom = 16.5;
    }

    double pitch = pose.speedKph >= 80.0 ? 60.0 : (pose.speedKph >= 40.0 ? 56.0 : 50.0);
    double lookAhead = clampValue(70.0 + pose.speedKph * 4.5, 80.0, 340.0);

    if (m_followMode == QLatin1String("approach")) {
        baseZoom += 0.6;
        pitch = clampValue(pitch - 8.0, 46.0, 50.0);
        lookAhead = clampValue(lookAhead * 0.45, 40.0, 120.0);
    } else if (m_followMode == QLatin1String("turn")) {
        baseZoom += 1.0;
        pitch = clampValue(pitch - 12.0, 42.0, 46.0);
        lookAhead = clampValue(lookAhead * 0.30, 30.0, 90.0);
    } else if (m_followMode == QLatin1String("long_leg_relax")) {
        baseZoom -= 0.7;
        pitch = qMax(pitch, 58.0);
        lookAhead = clampValue(lookAhead * 1.18, 120.0, 420.0);
    }

    return {
        {QStringLiteral("mode"), m_followMode},
        {QStringLiteral("zoom"), baseZoom},
        {QStringLiteral("pitch"), pitch},
        {QStringLiteral("lookAheadMeters"), lookAhead},
        {QStringLiteral("overview"), m_overviewActive},
        {QStringLiteral("fitDurationMs"), kOverviewDurationMs},
    };
}

void NavigationService::speakPrompt(const QString &text, const QString &promptId, bool highPriority)
{
    if (m_muted || text.trimmed().isEmpty()) {
        return;
    }

    emit voicePromptReady(text, promptId);
    Q_UNUSED(highPriority)

    ensureTtsReady();
    if (m_ttsStatus != QLatin1String("ready")) {
        return;
    }

    const QString wavPath = promptCachePath(text);
    if (!QFile::exists(wavPath)) {
        QProcess generator;
        QStringList generatorArgs;
        if (!m_ttsVoice.isEmpty()) {
            generatorArgs << QStringLiteral("--model") << m_ttsVoice;
        }
        generatorArgs << QStringLiteral("--output_file") << wavPath;
        generator.start(m_ttsEngine, generatorArgs);
        if (!generator.waitForStarted(1000)) {
            setTtsStatus(QStringLiteral("degraded"));
            return;
        }
        generator.write(text.toUtf8());
        generator.closeWriteChannel();
        generator.waitForFinished(15000);
        if (generator.exitStatus() != QProcess::NormalExit || generator.exitCode() != 0) {
            setTtsStatus(QStringLiteral("degraded"));
            return;
        }
    }

    if (m_playerCommand.isEmpty()) {
        setTtsStatus(QStringLiteral("degraded"));
        return;
    }
    QProcess::startDetached(m_playerCommand, {wavPath});
    m_lastPromptMs = QDateTime::currentMSecsSinceEpoch();
}

void NavigationService::ensureTtsReady()
{
    if (m_muted) {
        setTtsStatus(QStringLiteral("muted"));
        return;
    }
    if (m_ttsEngine.isEmpty()) {
        setTtsStatus(QStringLiteral("disabled"));
        return;
    }
    if (QStandardPaths::findExecutable(m_ttsEngine).isEmpty()) {
        setTtsStatus(QStringLiteral("degraded"));
        return;
    }
    if (m_ttsEngine == QLatin1String("piper") && m_ttsVoice.isEmpty()) {
        setTtsStatus(QStringLiteral("degraded"));
        return;
    }
    if (playerExecutable().isEmpty()) {
        setTtsStatus(QStringLiteral("degraded"));
        return;
    }
    setTtsStatus(QStringLiteral("ready"));
}

QString NavigationService::promptCachePath(const QString &text) const
{
    const QByteArray digest = QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha1).toHex();
    QDir().mkpath(m_navCacheDir + QStringLiteral("/tts"));
    return m_navCacheDir + QStringLiteral("/tts/") + QString::fromLatin1(digest) + QStringLiteral(".wav");
}

QString NavigationService::playerExecutable() const
{
    const QString paplay = QStandardPaths::findExecutable(QStringLiteral("paplay"));
    if (!paplay.isEmpty()) {
        return paplay;
    }
    const QString aplay = QStandardPaths::findExecutable(QStringLiteral("aplay"));
    if (!aplay.isEmpty()) {
        return aplay;
    }
    return QString();
}
