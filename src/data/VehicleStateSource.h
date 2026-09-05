#pragma once

#include <QObject>
#include <QString>

// Shared QML-facing vehicle_state surface.
// VehicleStateClient (live WebSocket) and MockVehicleStateClient inherit this
// so QML can bind the same property names on the `vehicleState` context object.
class VehicleStateSource : public QObject
{
    Q_OBJECT

    // Link health
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool linkStale READ linkStale NOTIFY linkStaleChanged)
    Q_PROPERTY(int  rxAgeMs READ rxAgeMs NOTIFY rxAgeMsChanged)

    // Indicators (truth from BBB / mock)
    Q_PROPERTY(bool leftIndicator READ leftIndicator NOTIFY leftIndicatorChanged)
    Q_PROPERTY(bool rightIndicator READ rightIndicator NOTIFY rightIndicatorChanged)
    Q_PROPERTY(bool highBeam READ highBeam NOTIFY highBeamChanged)

    // Warnings (truth from BBB / mock)
    Q_PROPERTY(bool warnBrake READ warnBrake NOTIFY warnBrakeChanged)
    Q_PROPERTY(bool warnOil READ warnOil NOTIFY warnOilChanged)
    Q_PROPERTY(bool warnCharge READ warnCharge NOTIFY warnChargeChanged)
    Q_PROPERTY(bool warnDoor READ warnDoor NOTIFY warnDoorChanged)
    Q_PROPERTY(bool warnCheckEngine READ warnCheckEngine NOTIFY warnCheckEngineChanged)
    Q_PROPERTY(bool warnAT READ warnAT NOTIFY warnATChanged)
    Q_PROPERTY(bool warnFuelLow READ warnFuelLow NOTIFY warnFuelLowChanged)

    // BBB-declared stale (separate from linkStale)
    Q_PROPERTY(bool bbbStale READ bbbStale NOTIFY bbbStaleChanged)

    // Gauges / drivetrain (Phase 1 vehicle_state contract)
    Q_PROPERTY(qreal speedKph READ speedKph NOTIFY speedKphChanged)
    Q_PROPERTY(qreal rpm READ rpm NOTIFY rpmChanged)
    Q_PROPERTY(qreal fuelPct READ fuelPct NOTIFY fuelPctChanged)
    Q_PROPERTY(qreal coolantC READ coolantC NOTIFY coolantCChanged)
    Q_PROPERTY(QString gear READ gear NOTIFY gearChanged)
    Q_PROPERTY(bool overdrive READ overdrive NOTIFY overdriveChanged)

public:
    explicit VehicleStateSource(QObject *parent = nullptr);
    ~VehicleStateSource() override = default;

    bool connected() const { return m_connected; }
    bool linkStale() const { return m_linkStale; }
    int  rxAgeMs() const { return m_rxAgeMs; }

    bool leftIndicator() const { return m_leftIndicator; }
    bool rightIndicator() const { return m_rightIndicator; }
    bool highBeam() const { return m_highBeam; }

    bool warnBrake() const { return m_warnBrake; }
    bool warnOil() const { return m_warnOil; }
    bool warnCharge() const { return m_warnCharge; }
    bool warnDoor() const { return m_warnDoor; }
    bool warnCheckEngine() const { return m_warnCheckEngine; }
    bool warnAT() const { return m_warnAT; }
    bool warnFuelLow() const { return m_warnFuelLow; }

    bool bbbStale() const { return m_bbbStale; }

    qreal speedKph() const { return m_speedKph; }
    qreal rpm() const { return m_rpm; }
    qreal fuelPct() const { return m_fuelPct; }
    qreal coolantC() const { return m_coolantC; }
    QString gear() const { return m_gear; }
    bool overdrive() const { return m_overdrive; }

signals:
    void connectedChanged();
    void linkStaleChanged();
    void rxAgeMsChanged();

    void leftIndicatorChanged();
    void rightIndicatorChanged();
    void highBeamChanged();

    void warnBrakeChanged();
    void warnOilChanged();
    void warnChargeChanged();
    void warnDoorChanged();
    void warnCheckEngineChanged();
    void warnATChanged();
    void warnFuelLowChanged();

    void bbbStaleChanged();

    void speedKphChanged();
    void rpmChanged();
    void fuelPctChanged();
    void coolantCChanged();
    void gearChanged();
    void overdriveChanged();

protected:
    void setConnected(bool v);
    void setLinkStale(bool v);
    void setRxAgeMs(int v);

    void setLeftIndicator(bool v);
    void setRightIndicator(bool v);
    void setHighBeam(bool v);

    void setWarnBrake(bool v);
    void setWarnOil(bool v);
    void setWarnCharge(bool v);
    void setWarnDoor(bool v);
    void setWarnCheckEngine(bool v);
    void setWarnAT(bool v);
    void setWarnFuelLow(bool v);

    void setBbbStale(bool v);

    void setSpeedKph(qreal v);
    void setRpm(qreal v);
    void setFuelPct(qreal v);
    void setCoolantC(qreal v);
    void setGear(const QString &v);
    void setOverdrive(bool v);

private:
    bool m_connected = false;
    bool m_linkStale = true;
    int  m_rxAgeMs = 0;

    bool m_leftIndicator = false;
    bool m_rightIndicator = false;
    bool m_highBeam = false;

    bool m_warnBrake = false;
    bool m_warnOil = false;
    bool m_warnCharge = false;
    bool m_warnDoor = false;
    bool m_warnCheckEngine = false;
    bool m_warnAT = false;
    bool m_warnFuelLow = false;

    bool m_bbbStale = true;

    qreal m_speedKph = 0;
    qreal m_rpm = 0;
    qreal m_fuelPct = 0;
    qreal m_coolantC = 0;
    QString m_gear = QStringLiteral("P");
    bool m_overdrive = false;
};
