#include "MockVehicleStateClient.h"

#include <QRandomGenerator>
#include <QtMath>

MockVehicleStateClient::MockVehicleStateClient(QObject *parent)
    : VehicleStateSource(parent)
    , m_gears({QStringLiteral("P"), QStringLiteral("R"), QStringLiteral("N"),
               QStringLiteral("D"), QStringLiteral("2"), QStringLiteral("1")})
{
    // Healthy mock link so QML linkOk gating shows simulated gauges/warnings.
    setConnected(true);
    setLinkStale(false);
    setBbbStale(false);
    setRxAgeMs(0);

    setSpeedKph(0);
    setRpm(0);
    setFuelPct(100);
    setCoolantC(70);
    setGear(m_gears.at(m_gearIdx));
    setOverdrive(false);

    m_simTimer.setInterval(16);
    connect(&m_simTimer, &QTimer::timeout, this, &MockVehicleStateClient::onSimTick);
    m_simTimer.start();

    m_targetTimer.setInterval(1600);
    connect(&m_targetTimer, &QTimer::timeout, this, &MockVehicleStateClient::onTargetTick);
    m_targetTimer.start();

    m_fuelTimer.setInterval(250);
    connect(&m_fuelTimer, &QTimer::timeout, this, &MockVehicleStateClient::onFuelTick);
    m_fuelTimer.start();

    m_coolantTimer.setInterval(200);
    connect(&m_coolantTimer, &QTimer::timeout, this, &MockVehicleStateClient::onCoolantTick);
    m_coolantTimer.start();

    m_gearTimer.setInterval(900);
    connect(&m_gearTimer, &QTimer::timeout, this, &MockVehicleStateClient::onGearTick);
    m_gearTimer.start();

    m_flagTimer.setInterval(2200);
    connect(&m_flagTimer, &QTimer::timeout, this, &MockVehicleStateClient::onFlagTick);
    m_flagTimer.start();
}

void MockVehicleStateClient::onSimTick()
{
    const qreal dt = m_simTimer.interval() / 1000.0;
    const qreal diff = m_targetSpeedKph - speedKph();
    const qreal rate = (diff > 0) ? m_accelKphPerSec : m_decelKphPerSec;
    const qreal step = rate * dt;

    qreal next = speedKph();
    if (qAbs(diff) <= step)
        next = m_targetSpeedKph;
    else
        next += (diff > 0) ? step : -step;

    next = qBound(0.0, next, qreal(m_maxSpeedKph));
    setSpeedKph(next);

    // Simple RPM mapping for demo only (same as retired QML mock).
    setRpm(qBound(0.0, next * 50.0, 6500.0));
    setRxAgeMs(0);
}

void MockVehicleStateClient::onTargetTick()
{
    auto *rng = QRandomGenerator::global();
    const qreal base = 20.0 + rng->bounded(90.0); // 20..110
    const qreal spike = (rng->bounded(100) < 12) ? (40.0 + rng->bounded(60.0)) : 0.0;
    qreal next = base + spike;
    if (rng->bounded(100) < 8)
        next = 0;
    m_targetSpeedKph = qBound(0.0, next, qreal(m_maxSpeedKph));
}

void MockVehicleStateClient::onFuelTick()
{
    qreal next = fuelPct() - 0.08;
    if (next <= 0)
        next = 100;
    setFuelPct(next);
}

void MockVehicleStateClient::onCoolantTick()
{
    qreal next = coolantC();
    if (m_coolantHeating)
        next += 0.12;
    else
        next -= 0.10;

    if (next >= 110)
        m_coolantHeating = false;
    if (next <= 45)
        m_coolantHeating = true;

    setCoolantC(next);
}

void MockVehicleStateClient::onGearTick()
{
    m_gearIdx = (m_gearIdx + 1) % m_gears.size();
    const QString g = m_gears.at(m_gearIdx);
    setGear(g);
    setOverdrive(g == QLatin1String("D") || g == QLatin1String("2"));
}

void MockVehicleStateClient::onFlagTick()
{
    auto *rng = QRandomGenerator::global();

    if (rng->bounded(100) < 30)
        setLeftIndicator(!leftIndicator());
    if (rng->bounded(100) < 30)
        setRightIndicator(!rightIndicator());
    if (rng->bounded(100) < 18)
        setHighBeam(!highBeam());

    if (rng->bounded(100) < 12)
        setWarnBrake(!warnBrake());
    if (rng->bounded(100) < 10)
        setWarnOil(!warnOil());
    if (rng->bounded(100) < 10)
        setWarnCharge(!warnCharge());
    if (rng->bounded(100) < 12)
        setWarnDoor(!warnDoor());
    if (rng->bounded(100) < 10)
        setWarnCheckEngine(!warnCheckEngine());
    if (rng->bounded(100) < 10)
        setWarnAT(!warnAT());
    if (rng->bounded(100) < 14)
        setWarnFuelLow(!warnFuelLow());
}
