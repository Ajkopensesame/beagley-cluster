#include "VehicleStateSource.h"

#include <QDebug>
#include <QTimer>
#include <cmath>
#include <cstdlib>
#include <algorithm>

static const double ANALOG_SPEED_EPSILON_KPH = 0.25;
static const int ANALOG_RPM_EPSILON = 20;
static const double ANALOG_FUEL_EPSILON_PCT = 0.2;
static const double ANALOG_COOLANT_EPSILON_C = 0.5;
static const double GPS_MOVE_EPSILON_M = 2.0;
static const double GPS_BEARING_EPSILON_DEG = 3.0;
static const double GPS_SPEED_EPSILON_KPH = 0.5;

namespace {
double normalizeBearing(double degrees)
{
    const double wrapped = std::fmod(degrees, 360.0);
    return wrapped < 0.0 ? wrapped + 360.0 : wrapped;
}

bool changedEnough(double previous, double next, double epsilon)
{
    return std::fabs(previous - next) >= epsilon;
}

double coordinateDistanceMeters(double latA, double lngA, double latB, double lngB)
{
    if (!std::isfinite(latA) || !std::isfinite(lngA) || !std::isfinite(latB) || !std::isfinite(lngB)) {
        return std::numeric_limits<double>::infinity();
    }

    const double latScale = 111320.0;
    const double lngScale = std::cos(latA * M_PI / 180.0) * 111320.0;
    const double dLat = (latB - latA) * latScale;
    const double dLng = (lngB - lngA) * lngScale;
    return std::sqrt(dLat * dLat + dLng * dLng);
}

double bearingDelta(double previous, double next)
{
    const double delta = std::fabs(normalizeBearing(next) - normalizeBearing(previous));
    return std::min(delta, 360.0 - delta);
}
} // namespace

VehicleStateSource::VehicleStateSource(QObject *parent)
    : QObject(parent)
{
}

void VehicleStateSource::updateLinkLost()
{
    // Same predicate as MainV3 `truthOk` / ClusterRenderModel `truthOk`, inverted.
    const bool lost = !m_connected || m_linkStale || m_bbbStale || !m_vehicleStateSeen;
    if (m_linkLost == lost) return;
    m_linkLost = lost;
    emit linkLostChanged();
    if (!lost) {
        // Recovered: latched warnings follow the live values again.
        scheduleLatchedSync();
    }
}

void VehicleStateSource::scheduleLatchedSync()
{
    // Deferred by one event-loop turn on purpose. A hub-stale frame carries
    // zeroed warnings AND `_health.stale=true`; the client applies the warnings
    // before it applies the stale flag. Syncing immediately would latch those
    // zeros. By the time this runs the whole frame has been applied, linkLost is
    // true, and syncLatchedWarnings() leaves the previous latched set untouched.
    if (m_latchedSyncQueued) return;
    m_latchedSyncQueued = true;
    QTimer::singleShot(0, this, [this]() {
        m_latchedSyncQueued = false;
        syncLatchedWarnings();
    });
}

void VehicleStateSource::syncLatchedWarnings()
{
    if (m_linkLost) return;
    WarnSet live;
    live.brake = m_warnBrake;
    live.oil = m_warnOil;
    live.charge = m_warnCharge;
    live.door = m_warnDoor;
    live.checkEngine = m_warnCheckEngine;
    live.at = m_warnAT;
    live.fuelLow = m_warnFuelLow;
    if (live == m_latched) return;
    m_latched = live;
    emit warnLatchedChanged();
}

void VehicleStateSource::setConnected(bool v)
{
    if (m_connected == v) return;
    m_connected = v;
    emit connectedChanged();
    updateLinkLost();
}

void VehicleStateSource::setLinkStale(bool v)
{
    if (m_linkStale == v) return;
    m_linkStale = v;
    emit linkStaleChanged();
    updateLinkLost();
}

void VehicleStateSource::setRxAgeMs(int v)
{
    if (m_rxAgeMs == v) return;
    m_rxAgeMs = v;
    emit rxAgeMsChanged();
}

void VehicleStateSource::setVehicleStateSeen(bool v)
{
    if (m_vehicleStateSeen == v) return;
    m_vehicleStateSeen = v;
    emit vehicleStateSeenChanged();
    updateLinkLost();
}

void VehicleStateSource::setLeftIndicator(bool v)
{
    if (m_leftIndicator == v) return;
    m_leftIndicator = v;
    emit leftIndicatorChanged();
}

void VehicleStateSource::setRightIndicator(bool v)
{
    if (m_rightIndicator == v) return;
    m_rightIndicator = v;
    emit rightIndicatorChanged();
}

void VehicleStateSource::setHighBeam(bool v)
{
    if (m_highBeam == v) return;
    m_highBeam = v;
    emit highBeamChanged();
}

void VehicleStateSource::setWarnBrake(bool v)
{
    if (m_warnBrake == v) return;
    m_warnBrake = v;
    emit warnBrakeChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnOil(bool v)
{
    if (m_warnOil == v) return;
    m_warnOil = v;
    emit warnOilChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnCharge(bool v)
{
    if (m_warnCharge == v) return;
    m_warnCharge = v;
    emit warnChargeChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnDoor(bool v)
{
    if (m_warnDoor == v) return;
    m_warnDoor = v;
    emit warnDoorChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnCheckEngine(bool v)
{
    if (m_warnCheckEngine == v) return;
    m_warnCheckEngine = v;
    emit warnCheckEngineChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnAT(bool v)
{
    if (m_warnAT == v) return;
    m_warnAT = v;
    emit warnATChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setWarnFuelLow(bool v)
{
    if (m_warnFuelLow == v) return;
    m_warnFuelLow = v;
    emit warnFuelLowChanged();
    scheduleLatchedSync();
}

void VehicleStateSource::setBbbStale(bool v)
{
    if (m_bbbStale == v) return;
    m_bbbStale = v;
    emit bbbStaleChanged();
    updateLinkLost();
}

void VehicleStateSource::setDiagnosticOk(bool v)
{
    if (m_diagnosticOk == v) return;
    m_diagnosticOk = v;
    emit diagnosticChanged();
}

void VehicleStateSource::setDiagnosticSeverity(const QString &v)
{
    const QString normalized = v.trimmed().toLower();
    if (m_diagnosticSeverity == normalized) return;
    m_diagnosticSeverity = normalized;
    emit diagnosticChanged();
}

void VehicleStateSource::setDiagnosticStatus(const QString &v)
{
    const QString normalized = v.trimmed().toLower();
    if (m_diagnosticStatus == normalized) return;
    m_diagnosticStatus = normalized;
    emit diagnosticChanged();
}

void VehicleStateSource::setDiagnosticSummary(const QString &v)
{
    const QString normalized = v.trimmed();
    if (m_diagnosticSummary == normalized) return;
    m_diagnosticSummary = normalized;
    emit diagnosticChanged();
}

void VehicleStateSource::setDiagnosticFindingCount(int v)
{
    const int normalized = qMax(0, v);
    if (m_diagnosticFindingCount == normalized) return;
    m_diagnosticFindingCount = normalized;
    emit diagnosticChanged();
}

void VehicleStateSource::setSpeedKph(double v)
{
    if (!changedEnough(m_speedKph, v, ANALOG_SPEED_EPSILON_KPH)) return;
    m_speedKph = v;
    emit speedKphChanged();
}

void VehicleStateSource::setRpm(int v)
{
    if (std::abs(m_rpm - v) < ANALOG_RPM_EPSILON) return;
    m_rpm = v;
    emit rpmChanged();
}

void VehicleStateSource::setFuelPct(double v)
{
    if (!changedEnough(m_fuelPct, v, ANALOG_FUEL_EPSILON_PCT)) return;
    m_fuelPct = v;
    emit fuelPctChanged();
}

void VehicleStateSource::setCoolantC(double v)
{
    if (!changedEnough(m_coolantC, v, ANALOG_COOLANT_EPSILON_C)) return;
    m_coolantC = v;
    emit coolantCChanged();
}

void VehicleStateSource::setGear(const QString &v)
{
    const QString trimmed = v.trimmed().toUpper();
    const QString normalized = trimmed.isEmpty() ? QStringLiteral("P") : trimmed;
    if (m_gear == normalized) return;
    m_gear = normalized;
    emit gearChanged();
}

void VehicleStateSource::setOverdrive(bool v)
{
    if (m_overdrive == v) return;
    m_overdrive = v;
    emit overdriveChanged();
}

void VehicleStateSource::setDrivetrainMode(const QString &v)
{
    QString normalized = v.trimmed().toLower();
    if (normalized.isEmpty()) {
        normalized = QStringLiteral("2wd");
    } else if (normalized == QLatin1String("4x4") || normalized == QLatin1String("4h")) {
        normalized = QStringLiteral("4wd");
    } else if (normalized == QLatin1String("2h")) {
        normalized = QStringLiteral("2wd");
    }

    if (m_drivetrainMode == normalized) return;
    m_drivetrainMode = normalized;
    emit drivetrainModeChanged();
}

void VehicleStateSource::setTransferLock(bool v)
{
    if (m_transferLock == v) return;
    m_transferLock = v;
    emit transferLockChanged();
}

void VehicleStateSource::setGpsLat(double v)
{
    if (coordinateDistanceMeters(m_gpsLat, m_gpsLng, v, m_gpsLng) < GPS_MOVE_EPSILON_M) return;
    m_gpsLat = v;
    emit gpsLatChanged();
}

void VehicleStateSource::setGpsLng(double v)
{
    if (coordinateDistanceMeters(m_gpsLat, m_gpsLng, m_gpsLat, v) < GPS_MOVE_EPSILON_M) return;
    m_gpsLng = v;
    emit gpsLngChanged();
}

void VehicleStateSource::setGpsBearing(double v)
{
    if (bearingDelta(m_gpsBearing, v) < GPS_BEARING_EPSILON_DEG) return;
    m_gpsBearing = v;
    emit gpsBearingChanged();
}

void VehicleStateSource::setGpsAccuracyM(double v)
{
    if (qFuzzyCompare(m_gpsAccuracyM + 1.0, v + 1.0)) return;
    m_gpsAccuracyM = v;
    emit gpsAccuracyMChanged();
}

void VehicleStateSource::setGpsTimestampMs(qint64 v)
{
    if (m_gpsTimestampMs == v) return;
    m_gpsTimestampMs = v;
    emit gpsTimestampMsChanged();
}

void VehicleStateSource::setGpsFixValid(bool v)
{
    if (m_gpsFixValid == v) return;
    const bool wasValid = m_gpsFixValid;
    m_gpsFixValid = v;
    if (v && !m_gpsEverValid) {
        m_gpsEverValid = true;
        qInfo() << "[VehicleStateSource] first valid BBB GPS fix"
                << "lat=" << m_gpsLat
                << "lng=" << m_gpsLng
                << "accuracyM=" << m_gpsAccuracyM
                << "satellites=" << m_gpsSatellites;
        emit gpsEverValidChanged();
    } else if (!v && wasValid) {
        qWarning() << "[VehicleStateSource] BBB GPS fix invalid"
                   << "accuracyM=" << m_gpsAccuracyM
                   << "satellites=" << m_gpsSatellites
                   << "timestampMs=" << m_gpsTimestampMs;
    }
    emit gpsFixValidChanged();
}

void VehicleStateSource::setGpsSource(const QString &v)
{
    const QString normalized = v.trimmed();
    if (m_gpsSource == normalized) return;
    m_gpsSource = normalized;
    qInfo() << "[VehicleStateSource] BBB GPS source" << (m_gpsSource.isEmpty() ? QStringLiteral("<unset>") : m_gpsSource)
            << "fixValid=" << m_gpsFixValid
            << "poseValid=" << m_gpsPoseValid;
    emit gpsSourceChanged();
}

void VehicleStateSource::setGpsSatellites(int v)
{
    if (m_gpsSatellites == v) return;
    m_gpsSatellites = v;
    emit gpsSatellitesChanged();
}

void VehicleStateSource::setGpsHeadingReliable(bool v)
{
    if (m_gpsHeadingReliable == v) return;
    m_gpsHeadingReliable = v;
    emit gpsHeadingReliableChanged();
}

void VehicleStateSource::setGpsSpeedKph(double v)
{
    if (!changedEnough(m_gpsSpeedKph, v, GPS_SPEED_EPSILON_KPH)) return;
    m_gpsSpeedKph = v;
    emit gpsSpeedKphChanged();
}

void VehicleStateSource::setGpsPoseValid(bool v)
{
    if (m_gpsPoseValid == v) return;
    m_gpsPoseValid = v;
    if (!v) {
        qWarning() << "[VehicleStateSource] BBB GPS pose invalid"
                   << "source=" << m_gpsSource
                   << "lat=" << m_gpsLat
                   << "lng=" << m_gpsLng
                   << "timestampMs=" << m_gpsTimestampMs;
    }
    emit gpsPoseValidChanged();
}
