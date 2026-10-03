// Unit test for the link-lost fail-safe policy in VehicleStateSource:
//   * linkLost = !connected || linkStale || bbbStale || !vehicleStateSeen
//   * warn*Latched mirror the live warnings while healthy and freeze at the last
//     healthy value once the link is lost (a warning that was on stays on).
// Core-only (no QML / network); same plain-main style as the other tests here.

#include "data/VehicleStateSource.h"

#include <QCoreApplication>

#include <iostream>

namespace {

int g_failures = 0;

void expectTrue(bool condition, const char *message)
{
    if (condition) {
        return;
    }
    std::cerr << "FAIL: " << message << "\n";
    ++g_failures;
}

// Exposes the protected setters the real client / mock use.
class TestSource : public VehicleStateSource
{
public:
    using VehicleStateSource::setBbbStale;
    using VehicleStateSource::setConnected;
    using VehicleStateSource::setLinkStale;
    using VehicleStateSource::setVehicleStateSeen;
    using VehicleStateSource::setWarnAT;
    using VehicleStateSource::setWarnBrake;
    using VehicleStateSource::setWarnCharge;
    using VehicleStateSource::setWarnCheckEngine;
    using VehicleStateSource::setWarnDoor;
    using VehicleStateSource::setWarnFuelLow;
    using VehicleStateSource::setWarnOil;

    void healthy()
    {
        setConnected(true);
        setLinkStale(false);
        setBbbStale(false);
        setVehicleStateSeen(true);
    }

    // Mirrors VehicleStateClient::onTextMessageReceived ordering: warnings first,
    // `_health.stale` last, all inside one event-loop turn.
    void applyFrame(bool brake, bool oil, bool door, bool hubStale)
    {
        setVehicleStateSeen(true);
        setWarnBrake(brake);
        setWarnOil(oil);
        setWarnDoor(door);
        setBbbStale(hubStale);
    }
};

void drain()
{
    // Deferred latch sync runs from the event loop.
    QCoreApplication::processEvents();
}

void testLinkLostPredicate()
{
    TestSource s;
    expectTrue(s.linkLost(), "fresh source starts link-lost");

    s.healthy();
    expectTrue(!s.linkLost(), "connected + fresh + hub ok + frame seen -> not lost");

    s.setLinkStale(true);
    expectTrue(s.linkLost(), "linkStale -> lost");
    s.setLinkStale(false);
    expectTrue(!s.linkLost(), "linkStale cleared -> recovered");

    s.setBbbStale(true);
    expectTrue(s.linkLost(), "hub-reported stale (_health.stale) -> lost");
    s.setBbbStale(false);

    s.setConnected(false);
    expectTrue(s.linkLost(), "socket disconnected -> lost");
    s.setConnected(true);
    expectTrue(!s.linkLost(), "reconnected -> recovered");

    TestSource unseen;
    unseen.setConnected(true);
    unseen.setLinkStale(false);
    unseen.setBbbStale(false);
    expectTrue(unseen.linkLost(), "no vehicle_state frame seen yet -> lost");
}

void testLinkLostSignal()
{
    TestSource s;
    int emitted = 0;
    QObject::connect(&s, &VehicleStateSource::linkLostChanged, [&emitted]() { ++emitted; });
    s.healthy(); // lost -> not lost, exactly one change
    expectTrue(emitted == 1, "linkLostChanged emitted once on recovery");
    s.setLinkStale(true);
    s.setBbbStale(true); // still lost: no extra signal
    expectTrue(emitted == 2, "linkLostChanged emitted once on loss, not per cause");
}

void testWarningsFollowLiveWhileHealthy()
{
    TestSource s;
    s.healthy();
    s.setWarnBrake(true);
    drain();
    expectTrue(s.warnBrakeLatched(), "latched follows live ON while healthy");
    s.setWarnBrake(false);
    drain();
    expectTrue(!s.warnBrakeLatched(), "latched follows live OFF while healthy");
}

void testActiveWarningsLatchAcrossLoss()
{
    TestSource s;
    s.healthy();
    s.applyFrame(/*brake*/ true, /*oil*/ false, /*door*/ true, /*hubStale*/ false);
    drain();
    expectTrue(s.warnBrakeLatched() && s.warnDoorLatched() && !s.warnOilLatched(),
               "healthy frame latched");

    // Hub-stale frame: hub publishes zeroed warnings AND _health.stale=true.
    s.applyFrame(false, false, false, /*hubStale*/ true);
    drain();
    expectTrue(s.linkLost(), "hub-stale frame -> lost");
    expectTrue(!s.warnBrake() && !s.warnDoor(), "live warnings were zeroed by the hub");
    expectTrue(s.warnBrakeLatched() && s.warnDoorLatched(),
               "active warnings stay latched ON across hub-stale zeroed frame");
    expectTrue(!s.warnOilLatched(), "warning that was off stays off (no invented warnings)");

    // Link-level loss (watchdog) keeps them too.
    s.setLinkStale(true);
    drain();
    expectTrue(s.warnBrakeLatched() && s.warnDoorLatched(), "latched survives linkStale");

    // A live warning changing while lost must not alter the latched set.
    s.setWarnOil(true);
    drain();
    expectTrue(!s.warnOilLatched(), "live change while lost is ignored by the latch");
}

void testRecoveryReleasesLatch()
{
    TestSource s;
    s.healthy();
    s.applyFrame(true, false, false, false);
    drain();
    s.applyFrame(false, false, false, true); // lost
    drain();
    expectTrue(s.warnBrakeLatched(), "latched while lost");

    s.setLinkStale(false);
    s.applyFrame(false, false, false, /*hubStale*/ false); // healthy frame, brake now off
    drain();
    expectTrue(!s.linkLost(), "recovered");
    expectTrue(!s.warnBrakeLatched(), "after recovery latched follows live again (brake cleared)");
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);

    testLinkLostPredicate();
    testLinkLostSignal();
    testWarningsFollowLiveWhileHealthy();
    testActiveWarningsLatchAcrossLoss();
    testRecoveryReleasesLatch();

    if (g_failures != 0) {
        std::cerr << g_failures << " failure(s)\n";
        return 1;
    }
    std::cout << "vehicle_state_link_lost_test: all passed\n";
    return 0;
}
