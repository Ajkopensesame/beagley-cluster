#include "VehicleStateSource.h"

VehicleStateSource::VehicleStateSource(QObject *parent)
    : QObject(parent)
{
}

void VehicleStateSource::setConnected(bool v)
{
    if (m_connected == v) return;
    m_connected = v;
    emit connectedChanged();
}

void VehicleStateSource::setLinkStale(bool v)
{
    if (m_linkStale == v) return;
    m_linkStale = v;
    emit linkStaleChanged();
}

void VehicleStateSource::setRxAgeMs(int v)
{
    if (m_rxAgeMs == v) return;
    m_rxAgeMs = v;
    emit rxAgeMsChanged();
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
}

void VehicleStateSource::setWarnOil(bool v)
{
    if (m_warnOil == v) return;
    m_warnOil = v;
    emit warnOilChanged();
}

void VehicleStateSource::setWarnCharge(bool v)
{
    if (m_warnCharge == v) return;
    m_warnCharge = v;
    emit warnChargeChanged();
}

void VehicleStateSource::setWarnDoor(bool v)
{
    if (m_warnDoor == v) return;
    m_warnDoor = v;
    emit warnDoorChanged();
}

void VehicleStateSource::setWarnCheckEngine(bool v)
{
    if (m_warnCheckEngine == v) return;
    m_warnCheckEngine = v;
    emit warnCheckEngineChanged();
}

void VehicleStateSource::setWarnAT(bool v)
{
    if (m_warnAT == v) return;
    m_warnAT = v;
    emit warnATChanged();
}

void VehicleStateSource::setWarnFuelLow(bool v)
{
    if (m_warnFuelLow == v) return;
    m_warnFuelLow = v;
    emit warnFuelLowChanged();
}

void VehicleStateSource::setBbbStale(bool v)
{
    if (m_bbbStale == v) return;
    m_bbbStale = v;
    emit bbbStaleChanged();
}

void VehicleStateSource::setSpeedKph(qreal v)
{
    if (m_speedKph == v) return;
    m_speedKph = v;
    emit speedKphChanged();
}

void VehicleStateSource::setRpm(qreal v)
{
    if (m_rpm == v) return;
    m_rpm = v;
    emit rpmChanged();
}

void VehicleStateSource::setFuelPct(qreal v)
{
    if (m_fuelPct == v) return;
    m_fuelPct = v;
    emit fuelPctChanged();
}

void VehicleStateSource::setCoolantC(qreal v)
{
    if (m_coolantC == v) return;
    m_coolantC = v;
    emit coolantCChanged();
}

void VehicleStateSource::setGear(const QString &v)
{
    if (m_gear == v) return;
    m_gear = v;
    emit gearChanged();
}

void VehicleStateSource::setOverdrive(bool v)
{
    if (m_overdrive == v) return;
    m_overdrive = v;
    emit overdriveChanged();
}
