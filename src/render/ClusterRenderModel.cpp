#include "ClusterRenderModel.h"

#include "../data/VehicleStateClient.h"
#include "../navigation/NavigationService.h"

#include <QDateTime>
#include <QPointF>
#include <QStringList>
#include <QProcessEnvironment>
#include <QtMath>

namespace {
constexpr double kDefaultLat = -27.4698;
constexpr double kDefaultLng = 153.0251;
constexpr double kTileSizePx = 256.0;

bool embeddedRenderProfile()
{
    static const bool embedded = qEnvironmentVariable("BEAGLEY_RENDER_PROFILE") == QLatin1String("embedded");
    return embedded;
}

int renderTickIntervalMs()
{
    return embeddedRenderProfile() ? 80 : 16;
}

double mapPixelStep()
{
    return embeddedRenderProfile() ? 6.0 : 0.75;
}

double mapBearingStepDeg()
{
    return embeddedRenderProfile() ? 2.5 : 0.75;
}

double mapZoomStep()
{
    return embeddedRenderProfile() ? 0.20 : 0.05;
}

double clampLatitude(double latitude)
{
    return qBound(-85.05112878, latitude, 85.05112878);
}

QPointF projectToWorld(double lat, double lng, double zoomLevel)
{
    const double latClamped = clampLatitude(lat);
    const double sinLat = qSin(qDegreesToRadians(latClamped));
    const double scale = kTileSizePx * qPow(2.0, zoomLevel);
    const double x = (lng + 180.0) / 360.0 * scale;
    const double y = (0.5 - qLn((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * M_PI)) * scale;
    return QPointF(x, y);
}

double angleDeltaDegrees(double current, double target)
{
    double delta = std::fmod(target - current, 360.0);
    if (delta > 180.0) {
        delta -= 360.0;
    } else if (delta < -180.0) {
        delta += 360.0;
    }
    return delta;
}

double normalizedZoomForSpeed(double speedKph)
{
    if (!qIsFinite(speedKph)) {
        return 14.0;
    }
    if (speedKph >= 110.0) {
        return 13.4;
    }
    if (speedKph >= 80.0) {
        return 13.8;
    }
    if (speedKph >= 45.0) {
        return 14.4;
    }
    if (speedKph >= 15.0) {
        return 15.0;
    }
    return 15.5;
}

double moveTowards(double current, double target, double factor)
{
    return current + ((target - current) * factor);
}

QString formatDistanceMeters(double meters)
{
    if (!qIsFinite(meters) || meters <= 0.0) {
        return QStringLiteral("--");
    }
    if (meters >= 1000.0) {
        return QStringLiteral("%1 km").arg(QString::number(meters / 1000.0, 'f', meters < 10000.0 ? 1 : 0));
    }
    return QStringLiteral("%1 m").arg(qRound(meters));
}
} // namespace

ClusterRenderModel::ClusterRenderModel(VehicleStateClient *vehicleState,
                                       NavigationService *navigation,
                                       QObject *parent)
    : QObject(parent)
    , m_vehicleState(vehicleState)
    , m_navigation(navigation)
{
    m_mapLat = kDefaultLat;
    m_mapLng = kDefaultLng;

    if (m_vehicleState) {
        const auto refreshStatus = [this]() { syncStatus(); };
        const auto refreshAnalogs = [this]() { syncStatus(); };
        connect(m_vehicleState, &VehicleStateClient::connectedChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::linkStaleChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::vehicleStateSeenChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::bbbStaleChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::gpsFixValidChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::gpsPoseValidChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::speedKphChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::rpmChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::fuelPctChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::coolantCChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::gearChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::drivetrainModeChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::overdriveChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::leftIndicatorChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::rightIndicatorChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::highBeamChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::warnBrakeChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnOilChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnChargeChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnDoorChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnCheckEngineChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnATChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::warnFuelLowChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::diagnosticChanged, this, refreshStatus);
        connect(m_vehicleState, &VehicleStateClient::gpsLatChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::gpsLngChanged, this, refreshAnalogs);
        connect(m_vehicleState, &VehicleStateClient::gpsBearingChanged, this, refreshAnalogs);
    }

    if (m_navigation) {
        connect(m_navigation, &NavigationService::mapRouteOverlayChanged, this, &ClusterRenderModel::syncRoutePath);
        connect(m_navigation, &NavigationService::mapVehiclePoseChanged, this, &ClusterRenderModel::syncGuidance);
        connect(m_navigation, &NavigationService::mapGuidanceBannerChanged, this, &ClusterRenderModel::syncGuidance);
        connect(m_navigation, &NavigationService::mapConnectivityChanged, this, &ClusterRenderModel::syncStatus);
        connect(m_navigation, &NavigationService::routeChanged, this, &ClusterRenderModel::syncRoutePath);
        connect(m_navigation, &NavigationService::guidanceChanged, this, &ClusterRenderModel::syncGuidance);
        connect(m_navigation, &NavigationService::networkStatusChanged, this, &ClusterRenderModel::syncStatus);
    }

    m_tickTimer.setInterval(renderTickIntervalMs());
    connect(&m_tickTimer, &QTimer::timeout, this, &ClusterRenderModel::tick);
    m_tickTimer.start();

    syncStatus();
    syncGuidance();
    syncRoutePath();
}

void ClusterRenderModel::syncStatus()
{
    bool linkOk = false;
    bool truthOk = false;
    bool gpsOk = false;
    bool diagnosticActive = false;
    QString diagnosticSeverity;
    int activeWarnings = 0;
    QStringList warnings;

    if (m_vehicleState) {
        linkOk = m_vehicleState->connected() && !m_vehicleState->linkStale();
        truthOk = linkOk && !m_vehicleState->bbbStale() && m_vehicleState->vehicleStateSeen();
        gpsOk = truthOk && m_vehicleState->gpsFixValid() && m_vehicleState->gpsPoseValid();
        if (m_vehicleState->warnBrake()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("BRAKE"));
        }
        if (m_vehicleState->warnOil()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("OIL"));
        }
        if (m_vehicleState->warnCharge()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("CHARGE"));
        }
        if (m_vehicleState->warnDoor()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("DOOR"));
        }
        if (m_vehicleState->warnCheckEngine()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("CHECK"));
        }
        if (m_vehicleState->warnAT()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("A/T"));
        }
        if (m_vehicleState->warnFuelLow()) {
            ++activeWarnings;
            warnings.append(QStringLiteral("LOW FUEL"));
        }
        diagnosticSeverity = m_vehicleState->diagnosticSeverity();
        diagnosticActive = truthOk && !m_vehicleState->diagnosticOk();
        if (diagnosticActive) {
            ++activeWarnings;
            const QString summary = m_vehicleState->diagnosticSummary().trimmed();
            if (warnings.isEmpty() && !summary.isEmpty()) {
                warnings.append(summary.toUpper());
            } else {
                warnings.append(diagnosticSeverity == QLatin1String("error")
                                    ? QStringLiteral("DIAG ERROR")
                                    : QStringLiteral("DIAG WARN"));
            }
        }
    }

    bool internetOk = m_navigation ? m_navigation->internetOk() : false;
    const QString statusText = !linkOk
        ? QStringLiteral("LINK DOWN")
        : (!truthOk
               ? QStringLiteral("BBB STALE")
               : (diagnosticActive
                      ? (diagnosticSeverity == QLatin1String("error")
                             ? QStringLiteral("DIAG ERROR")
                             : QStringLiteral("DIAG WARN"))
                      : (gpsOk ? QStringLiteral("LIVE") : QStringLiteral("GPS WEAK"))));
    const QString networkText = m_navigation
        ? m_navigation->networkStatus().replace(QLatin1Char('_'), QLatin1Char(' ')).toUpper()
        : QStringLiteral("OFFLINE");
    const QString warningSummary = warnings.isEmpty()
        ? QStringLiteral("SYSTEMS NOMINAL")
        : warnings.join(QStringLiteral("  |  "));

    bool changed = false;
    if (m_linkOk != linkOk) {
        m_linkOk = linkOk;
        changed = true;
    }
    if (m_truthOk != truthOk) {
        m_truthOk = truthOk;
        changed = true;
    }
    if (m_internetOk != internetOk) {
        m_internetOk = internetOk;
        changed = true;
    }
    if (m_gpsOk != gpsOk) {
        m_gpsOk = gpsOk;
        changed = true;
    }
    if (m_activeWarnings != activeWarnings) {
        m_activeWarnings = activeWarnings;
        changed = true;
    }
    if (m_statusText != statusText) {
        m_statusText = statusText;
        changed = true;
    }
    if (m_networkText != networkText) {
        m_networkText = networkText;
        changed = true;
    }
    if (m_warningSummary != warningSummary) {
        m_warningSummary = warningSummary;
        changed = true;
    }

    if (m_vehicleState) {
        m_targetSpeedKph = truthOk ? m_vehicleState->speedKph() : 0.0;
        m_targetRpm = truthOk ? double(m_vehicleState->rpm()) : 0.0;
        m_targetFuelPct = truthOk ? m_vehicleState->fuelPct() : 0.0;
        m_targetCoolantC = truthOk ? m_vehicleState->coolantC() : 0.0;

        const QString gear = truthOk ? m_vehicleState->gear() : QStringLiteral("-");
        const QString drivetrain = truthOk ? m_vehicleState->drivetrainMode().toUpper() : QStringLiteral("--");
        if (m_gear != gear || m_drivetrainMode != drivetrain
            || m_overdrive != (truthOk && m_vehicleState->overdrive())
            || m_leftIndicator != (truthOk && m_vehicleState->leftIndicator())
            || m_rightIndicator != (truthOk && m_vehicleState->rightIndicator())
            || m_highBeam != (truthOk && m_vehicleState->highBeam())) {
            m_gear = gear;
            m_drivetrainMode = drivetrain;
            m_overdrive = truthOk && m_vehicleState->overdrive();
            m_leftIndicator = truthOk && m_vehicleState->leftIndicator();
            m_rightIndicator = truthOk && m_vehicleState->rightIndicator();
            m_highBeam = truthOk && m_vehicleState->highBeam();
            emit analogChanged();
        }
    }

    if (changed) {
        emit statusChanged();
    }
}

void ClusterRenderModel::syncGuidance()
{
    QString nextInstruction;
    QString guidanceDetail;
    QString etaText;

    if (m_navigation) {
        const QVariantMap banner = m_navigation->mapGuidanceBanner().value(QStringLiteral("banner")).toMap();
        nextInstruction = banner.value(QStringLiteral("primary")).toString();
        const double remainingDistance = m_navigation->remainingDistanceMeters();
        const QString eta = m_navigation->eta();
        guidanceDetail = QStringLiteral("%1  |  ETA %2")
            .arg(formatDistanceMeters(remainingDistance),
                 eta.isEmpty() ? QStringLiteral("--") : eta.toUpper());
        etaText = eta.toUpper();
    }

    bool changed = false;
    if (m_nextInstruction != nextInstruction) {
        m_nextInstruction = nextInstruction;
        changed = true;
    }
    if (m_guidanceDetail != guidanceDetail) {
        m_guidanceDetail = guidanceDetail;
        changed = true;
    }
    if (m_etaText != etaText) {
        m_etaText = etaText;
        changed = true;
    }
    if (changed) {
        emit guidanceChanged();
    }
}

void ClusterRenderModel::syncRoutePath()
{
    QVariantList path;
    if (m_navigation) {
        const QVariantMap routeOverlay = m_navigation->mapRouteOverlay();
        const QVariantMap route = routeOverlay.value(QStringLiteral("route")).toMap();
        const QVariantMap geometry = route.value(QStringLiteral("geometry")).toMap();
        const QVariantList coordinates = geometry.value(QStringLiteral("coordinates")).toList();
        for (const QVariant &entry : coordinates) {
            const QVariantList point = entry.toList();
            if (point.size() < 2) {
                continue;
            }
            path.append(QVariantMap{
                {QStringLiteral("lng"), point.at(0).toDouble()},
                {QStringLiteral("lat"), point.at(1).toDouble()},
            });
        }
    }
    if (m_routePath != path) {
        m_routePath = path;
        emit mapChanged();
    }
}

void ClusterRenderModel::tick()
{
    bool analogChangedNow = false;
    bool mapChangedNow = false;

    const double nextSpeed = moveTowards(m_speedKph, m_targetSpeedKph, 0.22);
    const double nextRpm = moveTowards(double(m_rpm), m_targetRpm, 0.25);
    const double nextFuel = moveTowards(m_fuelPct, m_targetFuelPct, 0.08);
    const double nextCoolant = moveTowards(m_coolantC, m_targetCoolantC, 0.08);

    if (qAbs(nextSpeed - m_speedKph) >= 0.05) {
        m_speedKph = nextSpeed;
        analogChangedNow = true;
    }
    if (qAbs(nextRpm - double(m_rpm)) >= 1.0) {
        m_rpm = qRound(nextRpm);
        analogChangedNow = true;
    }
    if (qAbs(nextFuel - m_fuelPct) >= 0.02) {
        m_fuelPct = nextFuel;
        analogChangedNow = true;
    }
    if (qAbs(nextCoolant - m_coolantC) >= 0.02) {
        m_coolantC = nextCoolant;
        analogChangedNow = true;
    }

    double targetLat = m_mapLat;
    double targetLng = m_mapLng;
    double targetBearing = m_mapBearing;
    double targetZoom = normalizedZoomForSpeed(m_targetSpeedKph);

    if (m_vehicleState && m_truthOk && m_vehicleState->gpsPoseValid()) {
        targetLat = m_vehicleState->gpsLat();
        targetLng = m_vehicleState->gpsLng();
        targetBearing = m_vehicleState->gpsBearing();
    } else if (m_navigation) {
        const QVariantMap pose = m_navigation->mapVehiclePose();
        targetLat = pose.value(QStringLiteral("lat"), kDefaultLat).toDouble();
        targetLng = pose.value(QStringLiteral("lng"), kDefaultLng).toDouble();
        targetBearing = pose.value(QStringLiteral("bearing"), 0.0).toDouble();
    }

    const double nextLat = moveTowards(m_mapLat, targetLat, 0.12);
    const double nextLng = moveTowards(m_mapLng, targetLng, 0.12);
    const double nextBearing = moveTowards(m_mapBearing, targetBearing, 0.18);
    const double nextZoomValue = moveTowards(m_mapZoom, targetZoom, 0.08);
    const QPointF currentWorld = projectToWorld(m_mapLat, m_mapLng, nextZoomValue);
    const QPointF nextWorld = projectToWorld(nextLat, nextLng, nextZoomValue);
    const QPointF worldDelta = nextWorld - currentWorld;

    if ((worldDelta.x() * worldDelta.x()) + (worldDelta.y() * worldDelta.y())
        >= (mapPixelStep() * mapPixelStep())) {
        m_mapLat = nextLat;
        m_mapLng = nextLng;
        mapChangedNow = true;
    }
    if (qAbs(angleDeltaDegrees(m_mapBearing, nextBearing)) >= mapBearingStepDeg()) {
        m_mapBearing = nextBearing;
        mapChangedNow = true;
    }
    if (qAbs(nextZoomValue - m_mapZoom) >= mapZoomStep()) {
        m_mapZoom = nextZoomValue;
        mapChangedNow = true;
    }

    if (analogChangedNow) {
        emit analogChanged();
    }
    if (mapChangedNow) {
        emit mapChanged();
    }
}
