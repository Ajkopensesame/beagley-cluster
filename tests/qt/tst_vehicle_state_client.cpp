#include <QtTest>

#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryFile>
#include <memory>

#include "TestFrames.h"
#include "data/VehicleStateClient.h"

namespace {

const char kGoodFrame[] =
    R"({"type":"vehicle_state","ts_ms":1,"seq":1,"source":"test",)"
    R"("speedKph":42.0,"rpm":2500,"fuelPct":55.5,"coolantC":88.0,"gear":"d","overdrive":true,)"
    R"("indicators":{"left":true,"right":false,"high_beam":true},)"
    R"("warnings":{"brake":false,"oil":true,"charge":false,"door":false,"check":true,"at":true,"fuel_low":true},)"
    R"("_health":{"stale":false}})";

// Minimal hub: accepts TCP, performs the WebSocket upgrade, sends unmasked frames.
class FakeHub : public QObject
{
public:
    explicit FakeHub(bool respondToHandshake = true)
        : m_respond(respondToHandshake)
    {
        QVERIFY2(m_server.listen(QHostAddress::LocalHost, 0), "listen failed");
        connect(&m_server, &QTcpServer::newConnection, this, [this] {
            QTcpSocket *s = m_server.nextPendingConnection();
            ++m_connections;
            m_client = s;
            m_request.clear();
            m_upgraded = false;
            connect(s, &QTcpSocket::readyRead, this, [this, s] { onReadyRead(s); });
        });
    }

    QString url() const { return QStringLiteral("ws://127.0.0.1:%1").arg(m_server.serverPort()); }
    int connections() const { return m_connections; }
    bool upgraded() const { return m_upgraded; }

    void sendText(const QByteArray &json) { sendRaw(textFrame(json)); }
    void sendRaw(const QByteArray &bytes)
    {
        if (m_client) {
            m_client->write(bytes);
            m_client->flush();
        }
    }
    void dropClient()
    {
        if (m_client)
            m_client->disconnectFromHost();
    }

private:
    void onReadyRead(QTcpSocket *s)
    {
        m_request += s->readAll();
        if (m_upgraded || !m_respond || !m_request.contains("\r\n\r\n"))
            return;
        const QByteArray tag("Sec-WebSocket-Key: ");
        const int at = m_request.indexOf(tag);
        if (at < 0)
            return;
        const int end = m_request.indexOf("\r\n", at);
        const QByteArray key = m_request.mid(at + tag.size(), end - at - tag.size());
        const QByteArray accept = QCryptographicHash::hash(
            key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11", QCryptographicHash::Sha1).toBase64();
        s->write("HTTP/1.1 101 Switching Protocols\r\n"
                 "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                 "Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
        s->flush();
        m_upgraded = true;
    }

    QTcpServer m_server;
    QTcpSocket *m_client = nullptr;
    QByteArray m_request;
    bool m_respond = true;
    bool m_upgraded = false;
    int m_connections = 0;
};

} // namespace

class TstVehicleStateClient : public QObject
{
    Q_OBJECT

private:
    std::unique_ptr<VehicleStateClient> makeClient(const FakeHub &hub)
    {
        qputenv("VEHICLE_HUB_WS_URL", hub.url().toUtf8());
        return std::make_unique<VehicleStateClient>();
    }

private slots:
    void cleanup()
    {
        qunsetenv("VEHICLE_HUB_WS_URL");
        qunsetenv("BEAGLEY_REPLAY_FILE");
        qunsetenv("BEAGLEY_REPLAY_LOOP");
    }

    void goodFrameAppliesValuesAndKeepsLinkAlive()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        QVERIFY(c->linkStale()); // nothing received yet

        hub.sendText(kGoodFrame);
        QTRY_VERIFY_WITH_TIMEOUT(!c->linkStale(), 2000);
        QVERIFY(c->vehicleStateSeen());
        QCOMPARE(c->speedKph(), 42.0);
        QCOMPARE(c->rpm(), 2500);
        QCOMPARE(c->fuelPct(), 55.5);
        QCOMPARE(c->coolantC(), 88.0);
        QCOMPARE(c->gear(), QStringLiteral("D"));
        QVERIFY(c->overdrive());
        QVERIFY(c->leftIndicator());
        QVERIFY(!c->rightIndicator());
        QVERIFY(c->highBeam());
        QVERIFY(c->warnOil());
        QVERIFY(c->warnCheckEngine());
        QVERIFY(c->warnAT());
        QVERIFY(c->warnFuelLow());
        QVERIFY(!c->warnBrake());
        QVERIFY(!c->bbbStale());
    }

    void linkGoesStaleAfterAboutOneSecond()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        hub.sendText(kGoodFrame);
        QTRY_VERIFY_WITH_TIMEOUT(!c->linkStale(), 2000);

        QElapsedTimer since;
        since.start();
        QTRY_VERIFY_WITH_TIMEOUT(c->linkStale(), 3000);
        // 1000 ms threshold, 200 ms watchdog tick (+ scheduling slack).
        QVERIFY2(since.elapsed() >= 700, qPrintable(QString::number(since.elapsed())));
        QVERIFY2(since.elapsed() <= 2500, qPrintable(QString::number(since.elapsed())));
    }

    void continuousGoodFramesKeepLinkFresh()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        for (int i = 0; i < 20; ++i) { // 2 s at 10 Hz
            hub.sendText(kGoodFrame);
            QTest::qWait(100);
        }
        QVERIFY(!c->linkStale());
    }

    void partialFrameIsAppliedButDoesNotRefreshLink()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        // Missing `rpm` (and fuel/coolant): not a good frame.
        hub.sendText(R"({"type":"vehicle_state","speedKph":10,)"
                     R"("indicators":{},"warnings":{"brake":true},"_health":{"stale":false}})");
        QTRY_VERIFY_WITH_TIMEOUT(c->warnBrake(), 2000); // still applied
        QTest::qWait(500);
        QVERIFY(c->linkStale());
    }

    void missingHealthObjectIsNotAGoodFrame()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        hub.sendText(R"({"type":"vehicle_state","speedKph":10,"rpm":1,"fuelPct":1,"coolantC":1,)"
                     R"("indicators":{},"warnings":{}})");
        QTest::qWait(500);
        QVERIFY(c->linkStale());
    }

    void malformedAndNonObjectJsonAreIgnored()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        hub.sendText("{not json");
        hub.sendText("[1,2,3]");
        hub.sendText("42");
        hub.sendText(R"({"type":"hello","service":"vehicle_hub"})");
        QTest::qWait(400);
        QVERIFY(c->connected());
        QVERIFY(c->linkStale());
        QVERIFY(!c->vehicleStateSeen());
        // And the stream still works afterwards.
        hub.sendText(kGoodFrame);
        QTRY_VERIFY_WITH_TIMEOUT(!c->linkStale(), 2000);
    }

    void disconnectResetsFreshness()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        hub.sendText(kGoodFrame);
        QTRY_VERIFY_WITH_TIMEOUT(!c->linkStale(), 2000);

        hub.dropClient();
        QTRY_VERIFY_WITH_TIMEOUT(!c->connected(), 2000);
        QVERIFY(c->linkStale());

        // Fast reconnect (250 ms backoff): connected again, but old data must not
        // look fresh before a new good frame arrives.
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 4000);
        QVERIFY(c->linkStale());
        hub.sendText(kGoodFrame);
        QTRY_VERIFY_WITH_TIMEOUT(!c->linkStale(), 2000);
    }

    void oversizedFrameDropsConnectionAndReconnects()
    {
        FakeHub hub;
        auto c = makeClient(hub);
        QTRY_VERIFY_WITH_TIMEOUT(c->connected(), 3000);
        QSignalSpy spy(c.get(), &VehicleStateSource::connectedChanged);

        QByteArray header;
        header.append(char(0x81));
        header.append(char(127));
        const quint64 n = quint64(WebSocketFrameDecoder::kMaxPayloadBytes) + 1;
        for (int i = 7; i >= 0; --i)
            header.append(char((n >> (8 * i)) & 0xff));
        hub.sendRaw(header);

        QTRY_VERIFY_WITH_TIMEOUT(spy.count() >= 2, 5000); // down, then back up
        QVERIFY(c->connected());
        QVERIFY(c->linkStale());
        QVERIFY(hub.connections() >= 2);
    }

    void handshakeTimeoutAbortsAndRetries()
    {
        FakeHub silent(false); // accepts TCP, never answers the upgrade
        auto c = makeClient(silent);
        QTRY_VERIFY_WITH_TIMEOUT(silent.connections() >= 1, 3000);
        QVERIFY(!c->connected());
        // 5 s timeout + 250 ms backoff, then a second attempt.
        QTRY_VERIFY_WITH_TIMEOUT(silent.connections() >= 2, 9000);
        QVERIFY(!c->connected());
        QVERIFY(c->linkStale());
    }

    void replayFramesAlwaysCountAsGood()
    {
        // A fixture-style frame without indicators/warnings/_health.
        QTemporaryFile file;
        QVERIFY(file.open());
        file.write(R"({"type":"vehicle_state","speedKph":12.0,"rpm":900})" "\n");
        file.flush();
        qputenv("BEAGLEY_REPLAY_FILE", file.fileName().toUtf8());
        qputenv("BEAGLEY_REPLAY_LOOP", "1");

        VehicleStateClient c;
        QVERIFY(c.connected()); // replay mode reports connected
        QTRY_VERIFY_WITH_TIMEOUT(!c.linkStale(), 2000);
        QCOMPARE(c.speedKph(), 12.0);
        QCOMPARE(c.rpm(), 900);
        QTest::qWait(1300); // looped replay keeps refreshing
        QVERIFY(!c.linkStale());
    }
};

QTEST_MAIN(TstVehicleStateClient)
#include "tst_vehicle_state_client.moc"
