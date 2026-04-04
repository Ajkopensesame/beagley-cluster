#include "VehicleStateClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QDebug>
#include <QCryptographicHash>
#include <QFile>
#include <QNetworkProxy>
#include <QRandomGenerator>
#include <QTextStream>
#include <cmath>
#include <initializer_list>

static const int STALE_TIMEOUT_MS = 1000;
static const int WATCHDOG_TICK_MS = 200;
static const int MAX_BACKOFF_MS   = 5000;
static const double ANALOG_SPEED_EPSILON_KPH = 0.25;
static const int ANALOG_RPM_EPSILON = 20;
static const double ANALOG_FUEL_EPSILON_PCT = 0.2;
static const double ANALOG_COOLANT_EPSILON_C = 0.5;
static const double GPS_MOVE_EPSILON_M = 2.0;
static const double GPS_BEARING_EPSILON_DEG = 3.0;
static const double GPS_SPEED_EPSILON_KPH = 0.5;

namespace {
bool jsonBool(const QJsonValue &value, bool *okOut = nullptr)
{
    bool ok = false;
    bool out = false;

    if (value.isBool()) {
        out = value.toBool();
        ok = true;
    } else if (value.isDouble()) {
        out = (value.toInt() != 0);
        ok = true;
    } else if (value.isString()) {
        const QString s = value.toString().trimmed().toLower();
        if (s == QLatin1String("true") || s == QLatin1String("1") || s == QLatin1String("yes")) {
            out = true;
            ok = true;
        } else if (s == QLatin1String("false") || s == QLatin1String("0") || s == QLatin1String("no")) {
            out = false;
            ok = true;
        }
    }

    if (okOut) {
        *okOut = ok;
    }
    return out;
}

double jsonNumber(const QJsonValue &value, bool *okOut = nullptr)
{
    bool ok = false;
    double out = 0.0;

    if (value.isDouble()) {
        out = value.toDouble();
        ok = true;
    } else if (value.isString()) {
        out = value.toString().toDouble(&ok);
    }

    if (okOut) {
        *okOut = ok;
    }
    return out;
}

double readNumberAny(const QJsonObject &obj,
                     std::initializer_list<const char *> keys,
                     double fallback)
{
    for (const char *key : keys) {
        const QJsonValue value = obj.value(QLatin1String(key));
        bool ok = false;
        const double parsed = jsonNumber(value, &ok);
        if (ok) {
            return parsed;
        }
    }
    return fallback;
}

bool readBoolAny(const QJsonObject &obj,
                 std::initializer_list<const char *> keys,
                 bool fallback)
{
    for (const char *key : keys) {
        const QJsonValue value = obj.value(QLatin1String(key));
        bool ok = false;
        const bool parsed = jsonBool(value, &ok);
        if (ok) {
            return parsed;
        }
    }
    return fallback;
}

double normalizeBearing(double degrees)
{
    const double wrapped = std::fmod(degrees, 360.0);
    return wrapped < 0.0 ? wrapped + 360.0 : wrapped;
}

bool changedEnough(double previous, double next, double epsilon)
{
    return std::fabs(previous - next) >= epsilon;
}

double coordinateDistanceMeters(double latA, double lngA, double latB, double lngB)
{
    if (!std::isfinite(latA) || !std::isfinite(lngA) || !std::isfinite(latB) || !std::isfinite(lngB)) {
        return std::numeric_limits<double>::infinity();
    }

    const double latScale = 111320.0;
    const double lngScale = std::cos(latA * M_PI / 180.0) * 111320.0;
    const double dLat = (latB - latA) * latScale;
    const double dLng = (lngB - lngA) * lngScale;
    return std::sqrt(dLat * dLat + dLng * dLng);
}

double bearingDelta(double previous, double next)
{
    const double delta = std::fabs(normalizeBearing(next) - normalizeBearing(previous));
    return std::min(delta, 360.0 - delta);
}

QByteArray generateHandshakeKey()
{
    QByteArray nonce(16, Qt::Uninitialized);
    for (int i = 0; i < nonce.size(); ++i) {
        nonce[i] = char(QRandomGenerator::global()->generate() & 0xff);
    }
    return nonce.toBase64();
}

QByteArray expectedAcceptKey(const QByteArray &handshakeKey)
{
    static const QByteArray websocketGuid("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    return QCryptographicHash::hash(handshakeKey + websocketGuid, QCryptographicHash::Sha1).toBase64();
}

QByteArray headerValue(const QByteArray &headers, const QByteArray &name)
{
    const QList<QByteArray> lines = headers.split('\n');
    const QByteArray lowerName = name.toLower();
    for (const QByteArray &rawLine : lines) {
        const QByteArray line = rawLine.trimmed();
        const int separator = line.indexOf(':');
        if (separator <= 0) {
            continue;
        }
        if (line.left(separator).trimmed().toLower() == lowerName) {
            return line.mid(separator + 1).trimmed();
        }
    }
    return QByteArray();
}
} // namespace

VehicleStateClient::VehicleStateClient(QObject *parent)
    : QObject(parent)
{
    m_url = qEnvironmentVariableIsSet("VEHICLE_HUB_WS_URL")
                ? QString::fromUtf8(qgetenv("VEHICLE_HUB_WS_URL"))
                : QStringLiteral("ws://192.168.0.7:8765");
    const QString replayPath = qEnvironmentVariableIsSet("BEAGLEY_REPLAY_FILE")
        ? QString::fromUtf8(qgetenv("BEAGLEY_REPLAY_FILE")).trimmed()
        : QString();
    m_replayLoop = !qEnvironmentVariableIsSet("BEAGLEY_REPLAY_LOOP")
        || qEnvironmentVariableIntValue("BEAGLEY_REPLAY_LOOP") != 0;

    m_socket.setProxy(QNetworkProxy::NoProxy);
    connect(&m_socket, &QTcpSocket::connected, this, &VehicleStateClient::onSocketConnected);
    connect(&m_socket, &QTcpSocket::disconnected, this, &VehicleStateClient::onDisconnected);
    connect(&m_socket, &QTcpSocket::readyRead, this, &VehicleStateClient::onSocketReadyRead);
    connect(&m_socket, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        qWarning() << "[VehicleStateClient] socket error"
                   << m_socket.errorString()
                   << "state=" << m_socket.state()
                   << "url=" << m_connectUrl;
    });
    connect(&m_socket, &QTcpSocket::stateChanged, this, [this](QAbstractSocket::SocketState state) {
        qInfo() << "[VehicleStateClient] state" << state << "url=" << m_connectUrl;
    });

    m_watchdog.setInterval(WATCHDOG_TICK_MS);
    connect(&m_watchdog, &QTimer::timeout, this, &VehicleStateClient::checkStale);
    m_watchdog.start();

    m_reconnect.setSingleShot(true);
    connect(&m_reconnect, &QTimer::timeout, this, &VehicleStateClient::connectNow);

    m_replayTimer.setSingleShot(true);
    connect(&m_replayTimer, &QTimer::timeout, this, &VehicleStateClient::playNextReplayFrame);

    if (!replayPath.isEmpty()) {
        loadReplayFrames(replayPath);
        if (!m_replayFrames.isEmpty()) {
            m_replayMode = true;
            qInfo() << "[VehicleStateClient] replay mode enabled file=" << replayPath
                    << "frames=" << m_replayFrames.size()
                    << "loop=" << m_replayLoop;
            setConnected(true);
            m_replayTimer.start(0);
            return;
        }
    }

    connectNow();
}

void VehicleStateClient::loadReplayFrames(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[VehicleStateClient] replay open failed" << path << file.errorString();
        return;
    }

    QTextStream stream(&file);
    int lineNumber = 0;
    while (!stream.atEnd()) {
        const QString line = stream.readLine().trimmed();
        ++lineNumber;
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(line.toUtf8());
        if (!doc.isObject()) {
            qWarning() << "[VehicleStateClient] replay line ignored: invalid JSON object"
                       << "line=" << lineNumber;
            continue;
        }

        const QJsonObject obj = doc.object();
        int delayMs = 16;
        QJsonObject frameObject = obj;
        if (obj.contains(QStringLiteral("frame")) && obj.value(QStringLiteral("frame")).isObject()) {
            frameObject = obj.value(QStringLiteral("frame")).toObject();
            delayMs = qMax(1, obj.value(QStringLiteral("delayMs")).toInt(delayMs));
        } else if (obj.contains(QStringLiteral("_meta")) && obj.value(QStringLiteral("_meta")).isObject()) {
            const QJsonObject meta = obj.value(QStringLiteral("_meta")).toObject();
            delayMs = qMax(1, meta.value(QStringLiteral("delayMs")).toInt(delayMs));
        }

        if (frameObject.value(QStringLiteral("type")).toString() != QStringLiteral("vehicle_state")) {
            continue;
        }

        m_replayFrames.append(QString::fromUtf8(QJsonDocument(frameObject).toJson(QJsonDocument::Compact)));
        m_replayDelaysMs.append(delayMs);
    }
}

void VehicleStateClient::connectNow()
{
    if (m_replayMode) {
        return;
    }
    if (m_socket.state() == QAbstractSocket::ConnectedState ||
        m_socket.state() == QAbstractSocket::ConnectingState) {
        return;
    }

    m_connectUrl = QUrl(m_url);
    if (m_connectUrl.path().isEmpty()) {
        m_connectUrl.setPath(QStringLiteral("/"));
    }
    m_handshakeComplete = false;
    m_socketBuffer.clear();
    m_fragmentBuffer.clear();
    m_fragmentIsText = false;
    m_handshakeKey = generateHandshakeKey();

    qDebug() << "[VehicleStateClient] connecting to" << m_connectUrl;
    m_socket.connectToHost(m_connectUrl.host(), m_connectUrl.port(80));
}

void VehicleStateClient::scheduleReconnect()
{
    if (m_replayMode) {
        return;
    }
    if (m_reconnect.isActive())
        return;

    const int delay = m_backoffMs;
    m_backoffMs = qMin(m_backoffMs * 2, MAX_BACKOFF_MS);

    qDebug() << "[VehicleStateClient] reconnect in" << delay << "ms";
    m_reconnect.start(delay);
}

void VehicleStateClient::onSocketConnected()
{
    sendHandshakeRequest();
}

void VehicleStateClient::onSocketReadyRead()
{
    m_socketBuffer += m_socket.readAll();
    processSocketBuffer();
}

void VehicleStateClient::sendHandshakeRequest()
{
    QString resource = m_connectUrl.path(QUrl::FullyEncoded);
    if (resource.isEmpty()) {
        resource = QStringLiteral("/");
    }
    if (m_connectUrl.hasQuery()) {
        resource += QStringLiteral("?") + m_connectUrl.query(QUrl::FullyEncoded);
    }

    QByteArray hostHeader = m_connectUrl.host().toUtf8();
    if (m_connectUrl.port(80) != 80) {
        hostHeader += ":" + QByteArray::number(m_connectUrl.port(80));
    }

    QByteArray request;
    request += "GET " + resource.toUtf8() + " HTTP/1.1\r\n";
    request += "Host: " + hostHeader + "\r\n";
    request += "Upgrade: websocket\r\n";
    request += "Connection: Upgrade\r\n";
    request += "Sec-WebSocket-Key: " + m_handshakeKey + "\r\n";
    request += "Sec-WebSocket-Version: 13\r\n";
    request += "\r\n";

    m_socket.write(request);
    m_socket.flush();
}

void VehicleStateClient::processSocketBuffer()
{
    if (!m_handshakeComplete) {
        processHandshake();
    }
    if (m_handshakeComplete) {
        processFrameBuffer();
    }
}

void VehicleStateClient::processHandshake()
{
    static const QByteArray separator("\r\n\r\n");
    const int headerEnd = m_socketBuffer.indexOf(separator);
    if (headerEnd < 0) {
        return;
    }

    const QByteArray responseHeaders = m_socketBuffer.left(headerEnd + separator.size());
    m_socketBuffer.remove(0, headerEnd + separator.size());

    const QList<QByteArray> lines = responseHeaders.split('\n');
    const QByteArray statusLine = lines.isEmpty() ? QByteArray() : lines.first().trimmed();
    const QByteArray acceptHeader = headerValue(responseHeaders, "Sec-WebSocket-Accept");
    const QByteArray upgradeHeader = headerValue(responseHeaders, "Upgrade").toLower();

    if ((!statusLine.startsWith("HTTP/1.1 101") && !statusLine.startsWith("HTTP/1.0 101"))
        || upgradeHeader != QByteArrayLiteral("websocket")
        || acceptHeader != expectedAcceptKey(m_handshakeKey)) {
        qWarning() << "[VehicleStateClient] handshake failed"
                   << statusLine
                   << "upgrade=" << upgradeHeader
                   << "accept=" << acceptHeader
                   << "url=" << m_connectUrl;
        m_socket.disconnectFromHost();
        return;
    }

    m_handshakeComplete = true;
    onConnected();
}

void VehicleStateClient::processFrameBuffer()
{
    while (true) {
        if (m_socketBuffer.size() < 2) {
            return;
        }

        const quint8 byte0 = quint8(m_socketBuffer.at(0));
        const quint8 byte1 = quint8(m_socketBuffer.at(1));
        const bool fin = (byte0 & 0x80) != 0;
        const quint8 opcode = (byte0 & 0x0f);
        const bool masked = (byte1 & 0x80) != 0;

        quint64 payloadLength = quint64(byte1 & 0x7f);
        int offset = 2;

        if (payloadLength == 126) {
            if (m_socketBuffer.size() < offset + 2) {
                return;
            }
            payloadLength =
                (quint64(quint8(m_socketBuffer.at(offset))) << 8) |
                quint64(quint8(m_socketBuffer.at(offset + 1)));
            offset += 2;
        } else if (payloadLength == 127) {
            if (m_socketBuffer.size() < offset + 8) {
                return;
            }
            payloadLength = 0;
            for (int i = 0; i < 8; ++i) {
                payloadLength = (payloadLength << 8) | quint64(quint8(m_socketBuffer.at(offset + i)));
            }
            offset += 8;
        }

        QByteArray maskKey;
        if (masked) {
            if (m_socketBuffer.size() < offset + 4) {
                return;
            }
            maskKey = m_socketBuffer.mid(offset, 4);
            offset += 4;
        }

        if (m_socketBuffer.size() < offset + int(payloadLength)) {
            return;
        }

        QByteArray payload = m_socketBuffer.mid(offset, int(payloadLength));
        m_socketBuffer.remove(0, offset + int(payloadLength));

        if (masked) {
            for (int i = 0; i < payload.size(); ++i) {
                payload[i] = payload.at(i) ^ maskKey.at(i % 4);
            }
        }

        switch (opcode) {
        case 0x0:
            if (m_fragmentIsText) {
                m_fragmentBuffer += payload;
                if (fin) {
                    onTextMessageReceived(QString::fromUtf8(m_fragmentBuffer));
                    m_fragmentBuffer.clear();
                    m_fragmentIsText = false;
                }
            }
            break;
        case 0x1:
            if (fin) {
                onTextMessageReceived(QString::fromUtf8(payload));
            } else {
                m_fragmentBuffer = payload;
                m_fragmentIsText = true;
            }
            break;
        case 0x8:
            sendControlFrame(0x8, payload.left(125));
            m_socket.disconnectFromHost();
            return;
        case 0x9:
            sendControlFrame(0xA, payload);
            break;
        case 0xA:
            break;
        default:
            break;
        }
    }
}

void VehicleStateClient::sendControlFrame(quint8 opcode, const QByteArray &payload)
{
    QByteArray frame;
    frame.append(char(0x80 | (opcode & 0x0f)));

    const quint64 payloadLength = quint64(payload.size());
    if (payloadLength < 126) {
        frame.append(char(0x80 | payloadLength));
    } else if (payloadLength <= 0xffff) {
        frame.append(char(0x80 | 126));
        frame.append(char((payloadLength >> 8) & 0xff));
        frame.append(char(payloadLength & 0xff));
    } else {
        frame.append(char(0x80 | 127));
        for (int i = 7; i >= 0; --i) {
            frame.append(char((payloadLength >> (i * 8)) & 0xff));
        }
    }

    const quint32 mask = QRandomGenerator::global()->generate();
    const char maskBytes[4] = {
        char((mask >> 24) & 0xff),
        char((mask >> 16) & 0xff),
        char((mask >> 8) & 0xff),
        char(mask & 0xff),
    };
    frame.append(maskBytes, 4);

    QByteArray maskedPayload = payload;
    for (int i = 0; i < maskedPayload.size(); ++i) {
        maskedPayload[i] = maskedPayload.at(i) ^ maskBytes[i % 4];
    }
    frame += maskedPayload;
    m_socket.write(frame);
}

void VehicleStateClient::onConnected()
{
    qInfo() << "[VehicleStateClient] connected" << m_connectUrl;
    setConnected(true);
    m_backoffMs = 250;
}

void VehicleStateClient::onDisconnected()
{
    qWarning() << "[VehicleStateClient] disconnected" << m_connectUrl;
    m_handshakeComplete = false;
    m_socketBuffer.clear();
    m_fragmentBuffer.clear();
    m_fragmentIsText = false;
    setConnected(false);
    setLinkStale(true);
    setGpsFixValid(false);
    setGpsPoseValid(false);
    scheduleReconnect();
}

void VehicleStateClient::playNextReplayFrame()
{
    if (!m_replayMode || m_replayFrames.isEmpty()) {
        return;
    }

    if (m_replayIndex >= m_replayFrames.size()) {
        if (!m_replayLoop) {
            qInfo() << "[VehicleStateClient] replay complete";
            return;
        }
        m_replayIndex = 0;
    }

    onTextMessageReceived(m_replayFrames.at(m_replayIndex));
    const int delayMs = m_replayDelaysMs.value(m_replayIndex, 16);
    ++m_replayIndex;
    m_replayTimer.start(delayMs);
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
    const QJsonObject drivetrain = obj.value("drivetrain").toObject();
    const QJsonObject transmission = obj.value("transmission").toObject();
    setGpsSource(obj.value("gpsSource").toString());

    // Consider this a "good" frame
    m_lastGoodRxMs = QDateTime::currentMSecsSinceEpoch();
    setVehicleStateSeen(true);

    setLeftIndicator(readBoolAny(indicators, {"left"}, false));
    setRightIndicator(readBoolAny(indicators, {"right"}, false));
    setHighBeam(readBoolAny(indicators, {"high_beam", "highBeam"}, false));

    setWarnBrake(readBoolAny(warnings, {"brake"}, false));
    setWarnOil(readBoolAny(warnings, {"oil"}, false));
    setWarnCharge(readBoolAny(warnings, {"charge"}, false));
    setWarnDoor(readBoolAny(warnings, {"door"}, false));
    setWarnCheckEngine(readBoolAny(warnings, {"check_engine", "check", "engine"}, false));
    setWarnAT(readBoolAny(warnings, {"at", "a_t", "trans", "transmission"}, false));
    setWarnFuelLow(readBoolAny(warnings, {"fuel_low", "fuelLow", "fuel"}, false));

    setBbbStale(health.value("stale").toBool(true));

    // Core analogs (top-level keys)
    // Safe defaults if BBB hasn't sent them yet.
    setSpeedKph(obj.value("speedKph").toDouble(0.0));
    setRpm(qRound(readNumberAny(obj, {"rpm"}, 0.0)));
    setFuelPct(obj.value("fuelPct").toDouble(0.0));
    setCoolantC(obj.value("coolantC").toDouble(0.0));
    const QString gearValue = obj.value("gear").toString(
        drivetrain.value("gear").toString(
            transmission.value("gear").toString(m_gear)
        )
    );
    setGear(gearValue);
    setOverdrive(readBoolAny(
        transmission,
        {"overdrive", "od"},
        readBoolAny(drivetrain, {"overdrive", "od"},
                    readBoolAny(obj, {"overdrive", "od"}, m_overdrive))
    ));
    const QString drivetrainModeValue = obj.value("drivetrainMode").toString(
        drivetrain.value("mode").toString(
            drivetrain.value("drivetrainMode").toString(
                drivetrain.value("drive").toString(m_drivetrainMode)
            )
        )
    );
    setDrivetrainMode(drivetrainModeValue);
    setTransferLock(readBoolAny(
        drivetrain,
        {"transfer_lock", "transferLock", "lock", "locked"},
        readBoolAny(obj, {"transfer_lock", "transferLock", "lock", "locked"}, m_transferLock)
    ));

    // GPS supports both top-level keys and nested object:
    // - top-level: gpsLat/gpsLng/gpsBearing or lat/lng/bearing
    // - nested:    gps { lat, lng|lon, bearing|heading|course }
    const QJsonObject gps = obj.value("gps").toObject();
    bool gpsLatValid = false;
    bool gpsLngValid = false;

    const double lat = readNumberAny(
        gps,
        {"lat", "latitude"},
        readNumberAny(obj, {"gpsLat", "lat", "latitude"}, m_gpsLat)
    );
    if (lat >= -90.0 && lat <= 90.0) {
        gpsLatValid = true;
        setGpsLat(lat);
    }

    const double lng = readNumberAny(
        gps,
        {"lng", "lon", "longitude"},
        readNumberAny(obj, {"gpsLng", "lng", "lon", "longitude"}, m_gpsLng)
    );
    if (lng >= -180.0 && lng <= 180.0) {
        gpsLngValid = true;
        setGpsLng(lng);
    }
    setGpsPoseValid(gpsLatValid && gpsLngValid);

    const double bearing = readNumberAny(
        gps,
        {"bearing", "heading", "course"},
        readNumberAny(obj, {"gpsBearing", "bearing", "heading", "course"}, m_gpsBearing)
    );
    setGpsBearing(normalizeBearing(bearing));
    setGpsAccuracyM(readNumberAny(
        gps,
        {"accuracyM", "accuracy", "hdop_m"},
        readNumberAny(obj, {"gpsAccuracyM", "accuracyM", "accuracy"}, m_gpsAccuracyM)
    ));
    setGpsTimestampMs(static_cast<qint64>(readNumberAny(
        gps,
        {"timestampMs", "timestamp", "ts"},
        readNumberAny(obj, {"gpsTimestampMs", "timestampMs", "timestamp", "ts"}, static_cast<double>(m_gpsTimestampMs))
    )));
    setGpsFixValid(readBoolAny(
        gps,
        {"fixValid", "fix_valid", "valid"},
        readBoolAny(obj, {"gpsFixValid", "fixValid", "fix_valid", "valid"}, m_gpsFixValid)
    ));
    setGpsSatellites(qRound(readNumberAny(
        gps,
        {"satellites", "sats"},
        readNumberAny(obj, {"gpsSatellites", "satellites", "sats"}, static_cast<double>(m_gpsSatellites))
    )));
    setGpsHeadingReliable(readBoolAny(
        gps,
        {"headingReliable", "heading_reliable"},
        readBoolAny(obj, {"gpsHeadingReliable", "headingReliable", "heading_reliable"}, m_gpsHeadingReliable)
    ));
    setGpsSpeedKph(readNumberAny(
        gps,
        {"speedKph", "speed", "speed_kph"},
        readNumberAny(obj, {"gpsSpeedKph", "speedKph", "speed", "speed_kph"}, m_gpsSpeedKph)
    ));

    // Link stale is determined by watchdog timing; watchdog will clear it
    // once age is within threshold.
}

void VehicleStateClient::checkStale()
{
    if (m_lastGoodRxMs == 0) {
        setRxAgeMs(0);
        setLinkStale(true);
        setGpsFixValid(false);
        setGpsPoseValid(false);
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
        setGpsFixValid(false);
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

void VehicleStateClient::setVehicleStateSeen(bool v)
{
    if (m_vehicleStateSeen == v) return;
    m_vehicleStateSeen = v;
    emit vehicleStateSeenChanged();
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

void VehicleStateClient::setWarnCheckEngine(bool v)
{
    if (m_warnCheckEngine == v) return;
    m_warnCheckEngine = v;
    emit warnCheckEngineChanged();
}

void VehicleStateClient::setWarnAT(bool v)
{
    if (m_warnAT == v) return;
    m_warnAT = v;
    emit warnATChanged();
}

void VehicleStateClient::setWarnFuelLow(bool v)
{
    if (m_warnFuelLow == v) return;
    m_warnFuelLow = v;
    emit warnFuelLowChanged();
}

void VehicleStateClient::setBbbStale(bool v)
{
    if (m_bbbStale == v) return;
    m_bbbStale = v;
    emit bbbStaleChanged();
}

void VehicleStateClient::setSpeedKph(double v)
{
    if (!changedEnough(m_speedKph, v, ANALOG_SPEED_EPSILON_KPH)) return;
    m_speedKph = v;
    emit speedKphChanged();
}

void VehicleStateClient::setRpm(int v)
{
    if (std::abs(m_rpm - v) < ANALOG_RPM_EPSILON) return;
    m_rpm = v;
    emit rpmChanged();
}

void VehicleStateClient::setFuelPct(double v)
{
    if (!changedEnough(m_fuelPct, v, ANALOG_FUEL_EPSILON_PCT)) return;
    m_fuelPct = v;
    emit fuelPctChanged();
}

void VehicleStateClient::setCoolantC(double v)
{
    if (!changedEnough(m_coolantC, v, ANALOG_COOLANT_EPSILON_C)) return;
    m_coolantC = v;
    emit coolantCChanged();
}

void VehicleStateClient::setGear(const QString &v)
{
    const QString trimmed = v.trimmed().toUpper();
    const QString normalized = trimmed.isEmpty() ? QStringLiteral("P") : trimmed;
    if (m_gear == normalized) return;
    m_gear = normalized;
    emit gearChanged();
}

void VehicleStateClient::setOverdrive(bool v)
{
    if (m_overdrive == v) return;
    m_overdrive = v;
    emit overdriveChanged();
}

void VehicleStateClient::setDrivetrainMode(const QString &v)
{
    QString normalized = v.trimmed().toLower();
    if (normalized.isEmpty()) {
        normalized = QStringLiteral("2wd");
    } else if (normalized == QLatin1String("4x4") || normalized == QLatin1String("4h")) {
        normalized = QStringLiteral("4wd");
    } else if (normalized == QLatin1String("2h")) {
        normalized = QStringLiteral("2wd");
    }

    if (m_drivetrainMode == normalized) return;
    m_drivetrainMode = normalized;
    emit drivetrainModeChanged();
}

void VehicleStateClient::setTransferLock(bool v)
{
    if (m_transferLock == v) return;
    m_transferLock = v;
    emit transferLockChanged();
}

void VehicleStateClient::setGpsLat(double v)
{
    if (coordinateDistanceMeters(m_gpsLat, m_gpsLng, v, m_gpsLng) < GPS_MOVE_EPSILON_M) return;
    m_gpsLat = v;
    emit gpsLatChanged();
}

void VehicleStateClient::setGpsLng(double v)
{
    if (coordinateDistanceMeters(m_gpsLat, m_gpsLng, m_gpsLat, v) < GPS_MOVE_EPSILON_M) return;
    m_gpsLng = v;
    emit gpsLngChanged();
}

void VehicleStateClient::setGpsBearing(double v)
{
    if (bearingDelta(m_gpsBearing, v) < GPS_BEARING_EPSILON_DEG) return;
    m_gpsBearing = v;
    emit gpsBearingChanged();
}

void VehicleStateClient::setGpsAccuracyM(double v)
{
    if (qFuzzyCompare(m_gpsAccuracyM + 1.0, v + 1.0)) return;
    m_gpsAccuracyM = v;
    emit gpsAccuracyMChanged();
}

void VehicleStateClient::setGpsTimestampMs(qint64 v)
{
    if (m_gpsTimestampMs == v) return;
    m_gpsTimestampMs = v;
    emit gpsTimestampMsChanged();
}

void VehicleStateClient::setGpsFixValid(bool v)
{
    if (m_gpsFixValid == v) return;
    const bool wasValid = m_gpsFixValid;
    m_gpsFixValid = v;
    if (v && !m_gpsEverValid) {
        m_gpsEverValid = true;
        qInfo() << "[VehicleStateClient] first valid BBB GPS fix"
                << "lat=" << m_gpsLat
                << "lng=" << m_gpsLng
                << "accuracyM=" << m_gpsAccuracyM
                << "satellites=" << m_gpsSatellites;
        emit gpsEverValidChanged();
    } else if (!v && wasValid) {
        qWarning() << "[VehicleStateClient] BBB GPS fix invalid"
                   << "accuracyM=" << m_gpsAccuracyM
                   << "satellites=" << m_gpsSatellites
                   << "timestampMs=" << m_gpsTimestampMs;
    }
    emit gpsFixValidChanged();
}

void VehicleStateClient::setGpsSource(const QString &v)
{
    const QString normalized = v.trimmed();
    if (m_gpsSource == normalized) return;
    m_gpsSource = normalized;
    qInfo() << "[VehicleStateClient] BBB GPS source" << (m_gpsSource.isEmpty() ? QStringLiteral("<unset>") : m_gpsSource)
            << "fixValid=" << m_gpsFixValid
            << "poseValid=" << m_gpsPoseValid;
    emit gpsSourceChanged();
}

void VehicleStateClient::setGpsSatellites(int v)
{
    if (m_gpsSatellites == v) return;
    m_gpsSatellites = v;
    emit gpsSatellitesChanged();
}

void VehicleStateClient::setGpsHeadingReliable(bool v)
{
    if (m_gpsHeadingReliable == v) return;
    m_gpsHeadingReliable = v;
    emit gpsHeadingReliableChanged();
}

void VehicleStateClient::setGpsSpeedKph(double v)
{
    if (!changedEnough(m_gpsSpeedKph, v, GPS_SPEED_EPSILON_KPH)) return;
    m_gpsSpeedKph = v;
    emit gpsSpeedKphChanged();
}

void VehicleStateClient::setGpsPoseValid(bool v)
{
    if (m_gpsPoseValid == v) return;
    m_gpsPoseValid = v;
    if (!v) {
        qWarning() << "[VehicleStateClient] BBB GPS pose invalid"
                   << "source=" << m_gpsSource
                   << "lat=" << m_gpsLat
                   << "lng=" << m_gpsLng
                   << "timestampMs=" << m_gpsTimestampMs;
    }
    emit gpsPoseValidChanged();
}
