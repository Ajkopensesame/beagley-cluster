#include <QtTest>

#include "data/MockVehicleStateClient.h"

class TstMockVehicleState : public QObject
{
    Q_OBJECT

private slots:
    void startsHealthy()
    {
        MockVehicleStateClient mock;
        VehicleStateSource *base = &mock; // QML only ever sees the base surface
        QVERIFY(base->connected());
        QVERIFY(!base->linkStale());
        QVERIFY(!base->bbbStale());
        QVERIFY(base->vehicleStateSeen());
        QCOMPARE(base->gear(), QStringLiteral("P"));
        QCOMPARE(base->rpm(), 0);
        QCOMPARE(base->speedKph(), 0.0);
        QCOMPARE(base->fuelPct(), 100.0);
        QCOMPARE(base->coolantC(), 70.0);
        QVERIFY(base->diagnosticOk());
    }

    void valuesMoveAndStayInRange()
    {
        MockVehicleStateClient mock;
        QSignalSpy fuel(&mock, &VehicleStateSource::fuelPctChanged);
        QSignalSpy coolant(&mock, &VehicleStateSource::coolantCChanged);
        QSignalSpy gear(&mock, &VehicleStateSource::gearChanged);

        QTRY_VERIFY_WITH_TIMEOUT(fuel.count() >= 1, 4000);
        QTRY_VERIFY_WITH_TIMEOUT(coolant.count() >= 1, 4000);
        QTRY_VERIFY_WITH_TIMEOUT(gear.count() >= 1, 4000);

        // Sample the published values over a while; all must stay in range.
        for (int i = 0; i < 20; ++i) {
            QTest::qWait(50);
            QVERIFY(mock.speedKph() >= 0.0 && mock.speedKph() <= 180.0);
            QVERIFY(mock.rpm() >= 0 && mock.rpm() <= 6500);
            QVERIFY(mock.fuelPct() >= 0.0 && mock.fuelPct() <= 100.0);
            QVERIFY(mock.coolantC() >= 40.0 && mock.coolantC() <= 115.0);
            const QStringList valid = {QStringLiteral("P"), QStringLiteral("R"), QStringLiteral("N"),
                                       QStringLiteral("D"), QStringLiteral("2"), QStringLiteral("1")};
            QVERIFY(valid.contains(mock.gear()));
            QVERIFY(mock.connected());
            QVERIFY(!mock.linkStale());
        }
        // Fuel only ever counts down within a run (until it wraps at empty).
        QVERIFY(mock.fuelPct() < 100.0);
    }

    void publishesThroughBaseClassSignals()
    {
        MockVehicleStateClient mock;
        VehicleStateSource *base = &mock;
        QSignalSpy gear(base, &VehicleStateSource::gearChanged);
        QTRY_VERIFY_WITH_TIMEOUT(gear.count() >= 1, 4000);
        QCOMPARE(base->gear(), mock.gear());
    }
};

QTEST_MAIN(TstMockVehicleState)
#include "tst_mock_vehicle_state.moc"
