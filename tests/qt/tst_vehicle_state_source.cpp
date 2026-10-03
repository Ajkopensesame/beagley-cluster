#include <QtTest>

#include <cmath>

#include "data/VehicleStateSource.h"

// Exposes the protected setters so the shared change-threshold logic can be tested.
class TestSource : public VehicleStateSource
{
public:
    using VehicleStateSource::VehicleStateSource;
    using VehicleStateSource::setBbbStale;
    using VehicleStateSource::setConnected;
    using VehicleStateSource::setCoolantC;
    using VehicleStateSource::setDiagnosticFindingCount;
    using VehicleStateSource::setDiagnosticSeverity;
    using VehicleStateSource::setDiagnosticStatus;
    using VehicleStateSource::setDrivetrainMode;
    using VehicleStateSource::setFuelPct;
    using VehicleStateSource::setGear;
    using VehicleStateSource::setGpsBearing;
    using VehicleStateSource::setGpsFixValid;
    using VehicleStateSource::setGpsLat;
    using VehicleStateSource::setGpsLng;
    using VehicleStateSource::setGpsSpeedKph;
    using VehicleStateSource::setHighBeam;
    using VehicleStateSource::setLeftIndicator;
    using VehicleStateSource::setLinkStale;
    using VehicleStateSource::setRpm;
    using VehicleStateSource::setSpeedKph;
    using VehicleStateSource::setWarnBrake;
    using VehicleStateSource::setWarnCheckEngine;
};

class TstVehicleStateSource : public QObject
{
    Q_OBJECT

private slots:
    void defaults()
    {
        TestSource s;
        QVERIFY(!s.connected());
        QVERIFY(s.linkStale());
        QVERIFY(s.bbbStale());
        QCOMPARE(s.gear(), QStringLiteral("P"));
        QCOMPARE(s.drivetrainMode(), QStringLiteral("2wd"));
        QVERIFY(std::isnan(s.gpsLat()));
        QVERIFY(!s.gpsFixValid());
    }

    void speedThreshold()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::speedKphChanged);
        s.setSpeedKph(100.0);
        QCOMPARE(spy.count(), 1);
        s.setSpeedKph(100.2); // < 0.25 kph
        QCOMPARE(spy.count(), 1);
        QCOMPARE(s.speedKph(), 100.0);
        s.setSpeedKph(100.3); // >= 0.25 kph
        QCOMPARE(spy.count(), 2);
        QCOMPARE(s.speedKph(), 100.3);
    }

    void rpmThreshold()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::rpmChanged);
        s.setRpm(1000);
        QCOMPARE(spy.count(), 1);
        s.setRpm(1019); // < 20 rpm
        QCOMPARE(spy.count(), 1);
        QCOMPARE(s.rpm(), 1000);
        s.setRpm(1020); // >= 20 rpm
        QCOMPARE(spy.count(), 2);
        QCOMPARE(s.rpm(), 1020);
    }

    void fuelThreshold()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::fuelPctChanged);
        s.setFuelPct(50.0);
        QCOMPARE(spy.count(), 1);
        s.setFuelPct(50.1); // < 0.2 %
        QCOMPARE(spy.count(), 1);
        s.setFuelPct(50.3); // >= 0.2 %
        QCOMPARE(spy.count(), 2);
    }

    void coolantThreshold()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::coolantCChanged);
        s.setCoolantC(90.0);
        QCOMPARE(spy.count(), 1);
        s.setCoolantC(90.4); // < 0.5 C
        QCOMPARE(spy.count(), 1);
        s.setCoolantC(90.6); // >= 0.5 C
        QCOMPARE(spy.count(), 2);
    }

    void gearIsNormalised()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::gearChanged);
        s.setGear(QStringLiteral("P")); // already P -> no signal
        QCOMPARE(spy.count(), 0);
        s.setGear(QStringLiteral(" d "));
        QCOMPARE(s.gear(), QStringLiteral("D"));
        QCOMPARE(spy.count(), 1);
        s.setGear(QStringLiteral("")); // empty falls back to P
        QCOMPARE(s.gear(), QStringLiteral("P"));
        QCOMPARE(spy.count(), 2);
    }

    void drivetrainModeAliases()
    {
        TestSource s;
        s.setDrivetrainMode(QStringLiteral("4x4"));
        QCOMPARE(s.drivetrainMode(), QStringLiteral("4wd"));
        s.setDrivetrainMode(QStringLiteral("2H"));
        QCOMPARE(s.drivetrainMode(), QStringLiteral("2wd"));
        s.setDrivetrainMode(QStringLiteral("4H"));
        QCOMPARE(s.drivetrainMode(), QStringLiteral("4wd"));
        s.setDrivetrainMode(QStringLiteral(""));
        QCOMPARE(s.drivetrainMode(), QStringLiteral("2wd"));
    }

    void boolFlagsEmitOnlyOnChange()
    {
        TestSource s;
        QSignalSpy brake(&s, &VehicleStateSource::warnBrakeChanged);
        QSignalSpy left(&s, &VehicleStateSource::leftIndicatorChanged);
        s.setWarnBrake(true);
        s.setWarnBrake(true);
        QCOMPARE(brake.count(), 1);
        QVERIFY(s.warnBrake());
        s.setLeftIndicator(true);
        s.setLeftIndicator(false);
        s.setLeftIndicator(false);
        QCOMPARE(left.count(), 2);
    }

    void linkFlagsEmitOnlyOnChange()
    {
        TestSource s;
        QSignalSpy stale(&s, &VehicleStateSource::linkStaleChanged);
        s.setLinkStale(true); // default already true
        QCOMPARE(stale.count(), 0);
        s.setLinkStale(false);
        QCOMPARE(stale.count(), 1);
        QVERIFY(!s.linkStale());
    }

    void gpsPositionThreshold()
    {
        TestSource s;
        // Longitude first: while either coordinate is NaN every update counts as a move.
        s.setGpsLng(153.0);
        s.setGpsLat(-27.0);
        QSignalSpy lat(&s, &VehicleStateSource::gpsLatChanged);
        s.setGpsLat(-27.0 + 0.00001); // ~1.1 m < 2 m
        QCOMPARE(lat.count(), 0);
        s.setGpsLat(-27.0 + 0.00003); // ~3.3 m >= 2 m
        QCOMPARE(lat.count(), 1);
    }

    void gpsBearingThresholdAndWrap()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::gpsBearingChanged);
        s.setGpsBearing(90.0);
        QCOMPARE(spy.count(), 1);
        s.setGpsBearing(91.0); // < 3 deg
        QCOMPARE(spy.count(), 1);
        s.setGpsBearing(94.0); // >= 3 deg
        QCOMPARE(spy.count(), 2);
        s.setGpsBearing(359.0);
        QCOMPARE(spy.count(), 3);
        s.setGpsBearing(1.0); // 2 deg across the 360 wrap -> ignored
        QCOMPARE(spy.count(), 3);
    }

    void gpsSpeedThreshold()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::gpsSpeedKphChanged);
        s.setGpsSpeedKph(10.0);
        QCOMPARE(spy.count(), 1);
        s.setGpsSpeedKph(10.3); // < 0.5
        QCOMPARE(spy.count(), 1);
        s.setGpsSpeedKph(10.6); // >= 0.5
        QCOMPARE(spy.count(), 2);
    }

    void gpsEverValidLatches()
    {
        TestSource s;
        QSignalSpy ever(&s, &VehicleStateSource::gpsEverValidChanged);
        QSignalSpy fix(&s, &VehicleStateSource::gpsFixValidChanged);
        s.setGpsFixValid(true);
        QVERIFY(s.gpsFixValid());
        QVERIFY(s.gpsEverValid());
        QCOMPARE(ever.count(), 1);
        s.setGpsFixValid(false);
        QVERIFY(!s.gpsFixValid());
        QVERIFY(s.gpsEverValid());
        QCOMPARE(ever.count(), 1);
        QCOMPARE(fix.count(), 2);
    }

    void diagnosticFieldsAreNormalised()
    {
        TestSource s;
        QSignalSpy spy(&s, &VehicleStateSource::diagnosticChanged);
        s.setDiagnosticSeverity(QStringLiteral("  WARNING "));
        QCOMPARE(s.diagnosticSeverity(), QStringLiteral("warning"));
        s.setDiagnosticStatus(QStringLiteral("Link_Down"));
        QCOMPARE(s.diagnosticStatus(), QStringLiteral("link_down"));
        s.setDiagnosticFindingCount(-5);
        QCOMPARE(s.diagnosticFindingCount(), 0);
        QVERIFY(spy.count() >= 2);
    }
};

QTEST_APPLESS_MAIN(TstVehicleStateSource)
#include "tst_vehicle_state_source.moc"
