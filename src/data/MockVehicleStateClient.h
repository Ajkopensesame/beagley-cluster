#pragma once

#include "VehicleStateSource.h"

#include <QTimer>
#include <QStringList>

// Desktop / no-hub stand-in with the same QML property surface as the live client
// (selected with BEAGLEY_VEHICLE_BACKEND=mock). Simulates the contract fields only
// (speed/rpm/fuel/coolant/gear/overdrive, indicators, warnings); GPS and
// drivetrain stay at their defaults, so navigation sees "no GPS fix".
class MockVehicleStateClient : public VehicleStateSource
{
    Q_OBJECT

public:
    explicit MockVehicleStateClient(QObject *parent = nullptr);

private slots:
    void onSimTick();
    void onTargetTick();
    void onFuelTick();
    void onCoolantTick();
    void onGearTick();
    void onFlagTick();

private:
    QTimer m_simTimer;
    QTimer m_targetTimer;
    QTimer m_fuelTimer;
    QTimer m_coolantTimer;
    QTimer m_gearTimer;
    QTimer m_flagTimer;

    QStringList m_gears;
    int m_gearIdx = 0;

    // Mock keeps its own continuous state: the shared setters apply change
    // epsilons (see VehicleStateSource.cpp), so reading back the published
    // value would stall slow ramps (fuel/coolant steps are below epsilon).
    qreal m_speed = 0;
    qreal m_fuel = 100;
    qreal m_coolant = 70;

    qreal m_targetSpeedKph = 0;
    qreal m_accelKphPerSec = 45;
    qreal m_decelKphPerSec = 75;
    int m_maxSpeedKph = 180;

    bool m_coolantHeating = true;
};
