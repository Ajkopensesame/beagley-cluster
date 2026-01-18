#include "VehicleStateClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QDebug>

static const int STALE_TIMEOUT_MS = 1000;
static const int WATCHDOG_TICK_MS = 200;
static const int MAX_BACKOFF_MS   = 5000;

VehicleStateClient::VehicleStateClient(QObject *parent)
    : QObject(parent)
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
    const QString type = obj.value("type").toString();
    if (type != QStringLiteral("vehicle_state"))
        return;

    const QJsonObject indicators = obj.value("indicators").toObject();
    const QJsonObject warnings   = obj.value("warnings").toObject();
    const QJsonObject health     = obj.value("_health").toObject();

    // Consider this a "good" frame
    m_lastGoodRxMs = QDateTime::currentMSecsSinceEpoch();

    setLeftIndicator(indicators.value("left").toBool(false));
    setRightIndicator(indicators.value("right").toBool(false));
    setHighBeam(indicators.value("high_beam").toBool(false));

    setWarnBrake(warnings.value("brake").toBool(false));
    setWarnOil(warnings.value("oil").toBool(false));
    setWarnCharge(warnings.value("charge").toBool(false));
    setWarnDoor(warnings.value("door").toBool(false));

    setBbbStale(health.value("stale").toBool(true));

    // Link stale is determined by watchdog timing; watchdog will clear it
    // once age is within threshold.
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

void VehicleStateClient::setConnected(bool v)
{
    if (m_connected == v) return;
    m_connected = v;
    emit connectedChanged();
}

void VehicleStateClient::setLinkStale(bool v)
{
    if (m_linkStale == v) return;
    m_linkStale = v;
    emit linkStaleChanged();
}

void VehicleStateClient::setRxAgeMs(int v)
{
    if (m_rxAgeMs == v) return;
    m_rxAgeMs = v;
    emit rxAgeMsChanged();
}

void VehicleStateClient::setLeftIndicator(bool v)
{
    if (m_leftIndicator == v) return;
    m_leftIndicator = v;
    emit leftIndicatorChanged();
}

void VehicleStateClient::setRightIndicator(bool v)
{
    if (m_rightIndicator == v) return;
    m_rightIndicator = v;
    emit rightIndicatorChanged();
}

void VehicleStateClient::setHighBeam(bool v)
{
    if (m_highBeam == v) return;
    m_highBeam = v;
    emit highBeamChanged();
}

void VehicleStateClient::setWarnBrake(bool v)
{
    if (m_warnBrake == v) return;
    m_warnBrake = v;
    emit warnBrakeChanged();
}

void VehicleStateClient::setWarnOil(bool v)
{
    if (m_warnOil == v) return;
    m_warnOil = v;
    emit warnOilChanged();
}

void VehicleStateClient::setWarnCharge(bool v)
{
    if (m_warnCharge == v) return;
    m_warnCharge = v;
    emit warnChargeChanged();
}

void VehicleStateClient::setWarnDoor(bool v)
{
    if (m_warnDoor == v) return;
    m_warnDoor = v;
    emit warnDoorChanged();
}

void VehicleStateClient::setBbbStale(bool v)
{
    if (m_bbbStale == v) return;
    m_bbbStale = v;
    emit bbbStaleChanged();
}
