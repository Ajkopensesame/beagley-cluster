#include "VehicleStateClient.h"

#include "VehicleStateFrame.h"

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
static const int INITIAL_BACKOFF_MS = 250;
static const int CONNECT_TIMEOUT_MS = 5000;          // TCP connect + WebSocket upgrade
static const int MAX_HANDSHAKE_BYTES = 16 * 1024;    // HTTP upgrade response size cap
static const int PARSE_LOG_INTERVAL_MS = 5000;       // rate limit for parse-error logs

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

bool readNumberAnyPresent(const QJsonObject &obj,
                          std::initializer_list<const char *> keys,
                          double *out)
{
    for (const char *key : keys) {
        const QJsonValue value = obj.value(QLatin1String(key));
        bool ok = false;
        const double parsed = jsonNumber(value, &ok);
        if (ok) {
            if (out) {
                *out = parsed;
            }
            return true;
        }
    }
    return false;
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
    : VehicleStateSource(parent)
{
    m_url = qEnvironmentVariableIsSet("VEHICLE_HUB_WS_URL")
                ? QString::fromUtf8(qgetenv("VEHICLE_HUB_WS_URL"))
                : QStringLiteral("ws://10.24.0.7:8765");
    const QString replayPath = qEnvironmentVariableIsSet("BEAGLEY_REPLAY_FILE")
        ? QString::fromUtf8(qgetenv("BEAGLEY_REPLAY_FILE")).trimmed()
        : QString();
    m_replayLoop = !qEnvironmentVariableIsSet("BEAGLEY_REPLAY_LOOP")
        || qEnvironmentVariableIntValue("BEAGLEY_REPLAY_LOOP") != 0;

    m_clock.start();

    m_socket.setProxy(QNetworkProxy::NoProxy);
    connect(&m_socket, &QTcpSocket::connected, this, &VehicleStateClient::onSocketConnected);
    connect(&m_socket, &QTcpSocket::disconnected, this, &VehicleStateClient::onDisconnected);
    connect(&m_socket, &QTcpSocket::readyRead, this, &VehicleStateClient::onSocketReadyRead);
    connect(&m_socket, &QTcpSocket::errorOccurred, this, [this](QAbstractSocket::SocketError) {
        qWarning() << "[VehicleStateClient] socket error"
                   << m_socket.errorString()
                   << "state=" << m_socket.state()
                   << "url=" << m_connectUrl;
        if (m_socket.state() == QAbstractSocket::UnconnectedState) {
            m_connectTimeout.stop();
            handleLinkDown();
            scheduleReconnect();
        }
    });
    connect(&m_socket, &QTcpSocket::stateChanged, this, [this](QAbstractSocket::SocketState state) {
        qInfo() << "[VehicleStateClient] state" << state << "url=" << m_connectUrl;
    });

    m_watchdog.setInterval(WATCHDOG_TICK_MS);
    connect(&m_watchdog, &QTimer::timeout, this, &VehicleStateClient::checkStale);
    m_watchdog.start();

    m_connectTimeout.setSingleShot(true);
    m_connectTimeout.setInterval(CONNECT_TIMEOUT_MS);
    connect(&m_connectTimeout, &QTimer::timeout, this, &VehicleStateClient::onConnectTimeout);

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

VehicleStateClient::~VehicleStateClient()
{
    // m_socket is declared before members its signal handlers use (e.g.
    // m_connectUrl), so it would otherwise be destroyed after them and emit
    // stateChanged/disconnected into freed state. Detach and close it first.
    m_watchdog.stop();
    m_reconnect.stop();
    m_connectTimeout.stop();
    m_replayTimer.stop();
    QObject::disconnect(&m_socket, nullptr, this, nullptr);
    m_socket.abort();
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
    m_decoder.reset();
    m_handshakeKey = generateHandshakeKey();

    qDebug() << "[VehicleStateClient] connecting to" << m_connectUrl;
    m_connectTimeout.start();
    m_socket.connectToHost(m_connectUrl.host(), m_connectUrl.port(80));
}

void VehicleStateClient::onConnectTimeout()
{
    if (m_handshakeComplete || m_replayMode) {
        return;
    }
    failConnection(QStringLiteral("connect/handshake timed out after %1 ms").arg(CONNECT_TIMEOUT_MS));
}

// Drop the current connection (protocol violation, timeout) and go through the
// normal link-down + backoff path.
void VehicleStateClient::failConnection(const QString &reason)
{
    qWarning().noquote() << "[VehicleStateClient] dropping connection:" << reason
                         << "url=" << m_connectUrl.toString();
    m_connectTimeout.stop();
    m_socket.abort();
    handleLinkDown();
    scheduleReconnect();
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
    const QByteArray data = m_socket.readAll();
    if (!m_handshakeComplete) {
        m_socketBuffer += data;
        processSocketBuffer();
        return;
    }
    QVector<WebSocketFrameDecoder::Event> events;
    const auto status = m_decoder.feed(data, &events);
    processDecodedEvents(events);
    if (status != WebSocketFrameDecoder::Status::Ok) {
        failConnection(m_decoder.errorString());
    }
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
    processHandshake();
}

void VehicleStateClient::processHandshake()
{
    static const QByteArray separator("\r\n\r\n");
    const int headerEnd = m_socketBuffer.indexOf(separator);
    if (headerEnd < 0) {
        if (m_socketBuffer.size() > MAX_HANDSHAKE_BYTES) {
            failConnection(QStringLiteral("handshake response exceeds %1 bytes").arg(MAX_HANDSHAKE_BYTES));
        }
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

    // Bytes after the HTTP headers already belong to the WebSocket stream.
    if (!m_socketBuffer.isEmpty()) {
        const QByteArray rest = m_socketBuffer;
        m_socketBuffer.clear();
        QVector<WebSocketFrameDecoder::Event> events;
        const auto status = m_decoder.feed(rest, &events);
        processDecodedEvents(events);
        if (status != WebSocketFrameDecoder::Status::Ok) {
            failConnection(m_decoder.errorString());
        }
    }
}

void VehicleStateClient::processDecodedEvents(const QVector<WebSocketFrameDecoder::Event> &events)
{
    for (const WebSocketFrameDecoder::Event &event : events) {
        switch (event.type) {
        case WebSocketFrameDecoder::EventType::Text:
            onTextMessageReceived(QString::fromUtf8(event.payload));
            break;
        case WebSocketFrameDecoder::EventType::Ping:
            sendControlFrame(0xA, event.payload);
            break;
        case WebSocketFrameDecoder::EventType::Close:
            sendControlFrame(0x8, event.payload.left(125));
            m_socket.disconnectFromHost();
            return;
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
    m_connectTimeout.stop();
    setConnected(true);
    m_backoffMs = INITIAL_BACKOFF_MS;
}

void VehicleStateClient::onDisconnected()
{
    qWarning() << "[VehicleStateClient] disconnected" << m_connectUrl;
    m_connectTimeout.stop();
    handleLinkDown();
    scheduleReconnect();
}

// Common "link is down" state reset (disconnect, socket error, forced drop).
// Forgetting the last good frame means a fast reconnect cannot present old data
// as fresh: linkStale stays true until a new good frame arrives.
void VehicleStateClient::handleLinkDown()
{
    m_handshakeComplete = false;
    m_socketBuffer.clear();
    m_decoder.reset();
    m_hasGoodFrame = false;
    setConnected(false);
    setLinkStale(true);
    setBbbStale(true);
    setGpsFixValid(false);
    setGpsPoseValid(false);
    setDiagnosticOk(false);
    setDiagnosticSeverity(QStringLiteral("warning"));
    setDiagnosticStatus(QStringLiteral("link_down"));
    setDiagnosticSummary(QStringLiteral("VEHICLE DATA LINK DOWN"));
    setDiagnosticFindingCount(0);
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
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(msg.toUtf8(), &parseError);
    if (parseError.error != QJsonParseError::NoError) {
        logParseProblem(QStringLiteral("invalid JSON (%1 at offset %2, %3 bytes)")
                            .arg(parseError.errorString()).arg(parseError.offset).arg(msg.size()));
        return;
    }
    if (!doc.isObject()) {
        logParseProblem(QStringLiteral("JSON is not an object (%1 bytes)").arg(msg.size()));
        return;
    }

    const QJsonObject obj = doc.object();
    const QString type = obj.value("type").toString();
    if (type != QStringLiteral("vehicle_state"))
        return;

    const QJsonObject indicators = obj.value("indicators").toObject();
    const QJsonObject warnings   = obj.value("warnings").toObject();
    const QJsonObject health     = obj.value("_health").toObject();
    const QJsonObject diagnostic = obj.value("_diagnostic").toObject();
    const QJsonObject drivetrain = obj.value("drivetrain").toObject();
    const QJsonObject transmission = obj.value("transmission").toObject();
    setGpsSource(obj.value("gpsSource").toString());

    // Phase 1 hub contract (vehicle-hub PROTOCOL.md): a frame is "good" (refreshes
    // lastGoodRx, so linkStale stays false) only if the four gauge keys plus the
    // indicators / warnings / _health objects are all present. Partial frames are
    // still applied below but do not keep the link alive. Replayed JSONL frames
    // (BEAGLEY_REPLAY_FILE) are diagnostic fixtures that predate the contract and
    // omit indicators/warnings, so they are always treated as good.
    const bool goodFrame = m_replayMode || VehicleStateFrame::isGood(obj);
    if (goodFrame) {
        m_lastGoodRxMs = nowMs();
        m_hasGoodFrame = true;
    }
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
    if (obj.contains(QStringLiteral("_diagnostic")) && obj.value(QStringLiteral("_diagnostic")).isObject()) {
        setDiagnosticOk(diagnostic.value("ok").toBool(true));
        setDiagnosticSeverity(diagnostic.value("severity").toString(QStringLiteral("unknown")));
        setDiagnosticStatus(diagnostic.value("status").toString(QStringLiteral("unknown")));
        setDiagnosticSummary(diagnostic.value("summary").toString());
        setDiagnosticFindingCount(qMax(0, diagnostic.value("findingCount").toInt(0)));
    } else {
        const bool upstreamStale = health.value("stale").toBool(true);
        setDiagnosticOk(!upstreamStale);
        setDiagnosticSeverity(upstreamStale ? QStringLiteral("warning") : QStringLiteral("ok"));
        setDiagnosticStatus(upstreamStale ? QStringLiteral("data_stale") : QStringLiteral("nominal"));
        setDiagnosticSummary(upstreamStale ? QStringLiteral("VEHICLE DATA STALE") : QStringLiteral("SYSTEMS NOMINAL"));
        setDiagnosticFindingCount(0);
    }

    // Core analogs (top-level keys)
    // Safe defaults if BBB hasn't sent them yet.
    setSpeedKph(obj.value("speedKph").toDouble(0.0));
    setRpm(qRound(readNumberAny(obj, {"rpm"}, 0.0)));
    setFuelPct(obj.value("fuelPct").toDouble(0.0));
    setCoolantC(obj.value("coolantC").toDouble(0.0));
    const QString gearValue = obj.value("gear").toString(
        drivetrain.value("gear").toString(
            transmission.value("gear").toString(gear())
        )
    );
    setGear(gearValue);
    setOverdrive(readBoolAny(
        transmission,
        {"overdrive", "od"},
        readBoolAny(drivetrain, {"overdrive", "od"},
                    readBoolAny(obj, {"overdrive", "od"}, overdrive()))
    ));
    const QString drivetrainModeValue = obj.value("drivetrainMode").toString(
        drivetrain.value("mode").toString(
            drivetrain.value("drivetrainMode").toString(
                drivetrain.value("drive").toString(drivetrainMode())
            )
        )
    );
    setDrivetrainMode(drivetrainModeValue);
    setTransferLock(readBoolAny(
        drivetrain,
        {"transfer_lock", "transferLock", "lock", "locked"},
        readBoolAny(obj, {"transfer_lock", "transferLock", "lock", "locked"}, transferLock())
    ));

    // GPS supports both top-level keys and nested object:
    // - top-level: gpsLat/gpsLng/gpsBearing or lat/lng/bearing
    // - nested:    gps { lat, lng|lon, bearing|heading|course }
    const QJsonObject gps = obj.value("gps").toObject();
    bool gpsLatValid = false;
    bool gpsLngValid = false;

    double lat = 0.0;
    const bool latPresent = readNumberAnyPresent(gps, {"lat", "latitude"}, &lat)
        || readNumberAnyPresent(obj, {"gpsLat", "lat", "latitude"}, &lat);
    if (latPresent && lat >= -90.0 && lat <= 90.0) {
        gpsLatValid = true;
        setGpsLat(lat);
    }

    double lng = 0.0;
    const bool lngPresent = readNumberAnyPresent(gps, {"lng", "lon", "longitude"}, &lng)
        || readNumberAnyPresent(obj, {"gpsLng", "lng", "lon", "longitude"}, &lng);
    if (lngPresent && lng >= -180.0 && lng <= 180.0) {
        gpsLngValid = true;
        setGpsLng(lng);
    }
    setGpsPoseValid(gpsLatValid && gpsLngValid);

    const double bearing = readNumberAny(
        gps,
        {"bearing", "heading", "course"},
        readNumberAny(obj, {"gpsBearing", "bearing", "heading", "course"}, gpsBearing())
    );
    setGpsBearing(normalizeBearing(bearing));
    setGpsAccuracyM(readNumberAny(
        gps,
        {"accuracyM", "accuracy", "hdop_m"},
        readNumberAny(obj, {"gpsAccuracyM", "accuracyM", "accuracy"}, gpsAccuracyM())
    ));
    setGpsTimestampMs(static_cast<qint64>(readNumberAny(
        gps,
        {"timestampMs", "timestamp", "ts"},
        readNumberAny(obj, {"gpsTimestampMs", "timestampMs", "timestamp", "ts"}, static_cast<double>(gpsTimestampMs()))
    )));
    setGpsFixValid(readBoolAny(
        gps,
        {"fixValid", "fix_valid", "valid"},
        readBoolAny(obj, {"gpsFixValid", "fixValid", "fix_valid", "valid"}, gpsFixValid())
    ));
    setGpsSatellites(qRound(readNumberAny(
        gps,
        {"satellites", "sats"},
        readNumberAny(obj, {"gpsSatellites", "satellites", "sats"}, static_cast<double>(gpsSatellites()))
    )));
    setGpsHeadingReliable(readBoolAny(
        gps,
        {"headingReliable", "heading_reliable"},
        readBoolAny(obj, {"gpsHeadingReliable", "headingReliable", "heading_reliable"}, gpsHeadingReliable())
    ));
    setGpsSpeedKph(readNumberAny(
        gps,
        {"speedKph", "speed", "speed_kph"},
        readNumberAny(obj, {"gpsSpeedKph", "speedKph", "speed", "speed_kph"}, gpsSpeedKph())
    ));

    // Link stale is determined by watchdog timing; watchdog will clear it
    // once age is within threshold.
}

// Rate-limited: a misbehaving hub sending 10 Hz garbage must not flood the journal.
void VehicleStateClient::logParseProblem(const QString &what)
{
    const qint64 now = nowMs();
    if (m_lastParseLogMs >= 0 && now - m_lastParseLogMs < PARSE_LOG_INTERVAL_MS) {
        ++m_suppressedParseLogs;
        return;
    }
    qWarning().noquote() << "[VehicleStateClient] frame ignored:" << what
                         << (m_suppressedParseLogs > 0
                                 ? QStringLiteral("(+%1 similar suppressed)").arg(m_suppressedParseLogs)
                                 : QString());
    m_lastParseLogMs = now;
    m_suppressedParseLogs = 0;
}

void VehicleStateClient::checkStale()
{
    if (!m_hasGoodFrame) {
        setRxAgeMs(0);
        setLinkStale(true);
        setGpsFixValid(false);
        setGpsPoseValid(false);
        if (!connected()) {
            // Keep the more specific "link down" diagnostic set by handleLinkDown().
            return;
        }
        setDiagnosticOk(false);
        setDiagnosticSeverity(QStringLiteral("warning"));
        setDiagnosticStatus(QStringLiteral("link_stale"));
        setDiagnosticSummary(QStringLiteral("VEHICLE DATA LINK STALE"));
        setDiagnosticFindingCount(0);
        return;
    }

    const int age = int(nowMs() - m_lastGoodRxMs);
    setRxAgeMs(age);

    const bool staleNow = (age > STALE_TIMEOUT_MS);
    setLinkStale(staleNow);

    // If link is stale, force BBB stale as well (defensive)
    if (staleNow) {
        setBbbStale(true);
        setGpsFixValid(false);
        setDiagnosticOk(false);
        setDiagnosticSeverity(QStringLiteral("warning"));
        setDiagnosticStatus(QStringLiteral("link_stale"));
        setDiagnosticSummary(QStringLiteral("VEHICLE DATA LINK STALE"));
        setDiagnosticFindingCount(0);
    }
}
