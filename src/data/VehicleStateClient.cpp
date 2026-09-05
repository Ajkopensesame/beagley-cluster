#include "VehicleStateClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QDebug>

static const int STALE_TIMEOUT_MS = 1000;
static const int WATCHDOG_TICK_MS = 200;
static const int MAX_BACKOFF_MS   = 5000;

VehicleStateClient::VehicleStateClient(QObject *parent)
    : VehicleStateSource(parent)
{
    m_url = qEnvironmentVariableIsSet("VEHICLE_HUB_WS_URL")
                ? QString::fromUtf8(qgetenv("VEHICLE_HUB_WS_URL"))
                : QStringLiteral("ws://192.168.0.7:8765");

    connect(&m_ws, &QWebSocket::connected, this, &VehicleStateClient::onConnected);
    connect(&m_ws, &QWebSocket::disconnected, this, &VehicleStateClient::onDisconnected);
    connect(&m_ws, &QWebSocket::textMessageReceived,
            this, &VehicleStateClient::onTextMessageReceived);

    m_watchdog.setInterval(WATCHDOG_TICK_MS);
    connect(&m_watchdog, &QTimer::timeout, this, &VehicleStateClient::checkStale);
    m_watchdog.start();

    m_reconnect.setSingleShot(true);
    connect(&m_reconnect, &QTimer::timeout, this, &VehicleStateClient::connectNow);

    connectNow();
}

void VehicleStateClient::connectNow()
{
    if (m_ws.state() == QAbstractSocket::ConnectedState ||
        m_ws.state() == QAbstractSocket::ConnectingState) {
        return;
    }

    qDebug() << "[VehicleStateClient] connecting to" << m_url;
    m_ws.open(QUrl(m_url));
}

void VehicleStateClient::scheduleReconnect()
{
    if (m_reconnect.isActive())
        return;

    const int delay = m_backoffMs;
    m_backoffMs = qMin(m_backoffMs * 2, MAX_BACKOFF_MS);

    qDebug() << "[VehicleStateClient] reconnect in" << delay << "ms";
    m_reconnect.start(delay);
}

void VehicleStateClient::onConnected()
{
    setConnected(true);
    m_backoffMs = 250;
}

void VehicleStateClient::onDisconnected()
{
    setConnected(false);
    setLinkStale(true);
    scheduleReconnect();
}

void VehicleStateClient::onTextMessageReceived(const QString &msg)
{
    const QJsonDocument doc = QJsonDocument::fromJson(msg.toUtf8());
    if (!doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("type")).toString() != QStringLiteral("vehicle_state"))
        return;

    // Ignore unknown fields. Never derive gauges from analog.*.
    const QJsonValue indicatorsVal = obj.value(QStringLiteral("indicators"));
    const QJsonValue warningsVal   = obj.value(QStringLiteral("warnings"));
    const QJsonValue healthVal     = obj.value(QStringLiteral("_health"));

    if (indicatorsVal.isObject()) {
        const QJsonObject indicators = indicatorsVal.toObject();
        setLeftIndicator(indicators.value(QStringLiteral("left")).toBool());
        setRightIndicator(indicators.value(QStringLiteral("right")).toBool());
        setHighBeam(indicators.value(QStringLiteral("high_beam")).toBool());
    }

    if (warningsVal.isObject()) {
        const QJsonObject warnings = warningsVal.toObject();
        setWarnBrake(warnings.value(QStringLiteral("brake")).toBool());
        setWarnOil(warnings.value(QStringLiteral("oil")).toBool());
        setWarnCharge(warnings.value(QStringLiteral("charge")).toBool());
        setWarnDoor(warnings.value(QStringLiteral("door")).toBool());
        setWarnCheckEngine(warnings.value(QStringLiteral("check")).toBool());
        setWarnAT(warnings.value(QStringLiteral("at")).toBool());
        setWarnFuelLow(warnings.value(QStringLiteral("fuel_low")).toBool());
    }

    if (healthVal.isObject()) {
        setBbbStale(healthVal.toObject().value(QStringLiteral("stale")).toBool(true));
    }

    if (obj.contains(QStringLiteral("speedKph")))
        setSpeedKph(obj.value(QStringLiteral("speedKph")).toDouble());
    if (obj.contains(QStringLiteral("rpm")))
        setRpm(obj.value(QStringLiteral("rpm")).toDouble());
    if (obj.contains(QStringLiteral("fuelPct")))
        setFuelPct(obj.value(QStringLiteral("fuelPct")).toDouble());
    if (obj.contains(QStringLiteral("coolantC")))
        setCoolantC(obj.value(QStringLiteral("coolantC")).toDouble());
    if (obj.contains(QStringLiteral("gear")))
        setGear(obj.value(QStringLiteral("gear")).toString());
    if (obj.contains(QStringLiteral("overdrive")))
        setOverdrive(obj.value(QStringLiteral("overdrive")).toBool());

    // Good-frame: all gauge keys present plus indicators/warnings/_health objects.
    // Partial frames may still apply indicators/warnings/health, but must not
    // refresh last-good RX (link stale watchdog stays honest).
    const bool goodFrame =
        obj.contains(QStringLiteral("speedKph")) &&
        obj.contains(QStringLiteral("rpm")) &&
        obj.contains(QStringLiteral("fuelPct")) &&
        obj.contains(QStringLiteral("coolantC")) &&
        indicatorsVal.isObject() &&
        warningsVal.isObject() &&
        healthVal.isObject();

    if (goodFrame)
        m_lastGoodRxMs = QDateTime::currentMSecsSinceEpoch();
}

void VehicleStateClient::checkStale()
{
    if (m_lastGoodRxMs == 0) {
        setRxAgeMs(0);
        setLinkStale(true);
        return;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const int age = int(now - m_lastGoodRxMs);
    setRxAgeMs(age);

    const bool staleNow = (age > STALE_TIMEOUT_MS);
    setLinkStale(staleNow);

    // If link is stale, force BBB stale as well (defensive)
    if (staleNow) {
        setBbbStale(true);
    }
}
