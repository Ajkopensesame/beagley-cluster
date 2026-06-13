#include "NowPlayingService.h"

#include <QByteArray>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QProcessEnvironment>
#include <QTcpSocket>
#include <QTimer>
#include <QtGlobal>
#include <QUrlQuery>
#include <QNetworkInterface>

namespace {

constexpr auto kSpotifyApiBase = "https://api.spotify.com/v1";
constexpr auto kSpotifyTokenUrl = "https://accounts.spotify.com/api/token";
constexpr int kPairingPortDefault = 8787;
constexpr int kPairingTimeoutMs = 15 * 60 * 1000;
constexpr auto kSpotifyScopes = "user-read-currently-playing user-library-read user-library-modify";

int refreshIntervalMs()
{
    bool ok = false;
    const int requested = QString::fromUtf8(qgetenv("BEAGLEY_NOW_PLAYING_REFRESH_MS")).toInt(&ok);
    if (!ok) {
        return 4000;
    }
    if (requested < 2000) {
        return 2000;
    }
    if (requested > 30000) {
        return 30000;
    }
    return requested;
}

QString cleanedLine(const QStringList &lines, int index)
{
    if (index < 0 || index >= lines.size()) {
        return QString();
    }
    return lines.at(index).trimmed();
}

QString configuredPlayerName()
{
    const QString value = QString::fromUtf8(qgetenv("BEAGLEY_NOW_PLAYING_PLAYER")).trimmed();
    return value.isEmpty() ? QStringLiteral("spotify") : value;
}

bool envHasSpotifyConfig()
{
    return !QString::fromUtf8(qgetenv("BEAGLEY_SPOTIFY_ACCESS_TOKEN")).trimmed().isEmpty()
        || !QString::fromUtf8(qgetenv("BEAGLEY_SPOTIFY_REFRESH_TOKEN")).trimmed().isEmpty()
        || !QString::fromUtf8(qgetenv("BEAGLEY_SPOTIFY_CLIENT_ID")).trimmed().isEmpty();
}

NowPlayingService::Backend configuredBackend()
{
    const QString value = QString::fromUtf8(qgetenv("BEAGLEY_NOW_PLAYING_BACKEND")).trimmed().toLower();
    if (value == QLatin1String("spotify")
        || value == QLatin1String("spotify-web")
        || value == QLatin1String("spotify_web")
        || value == QLatin1String("web")) {
        return NowPlayingService::Backend::SpotifyWeb;
    }
    if (value == QLatin1String("playerctl") || value == QLatin1String("local")) {
        return NowPlayingService::Backend::Playerctl;
    }
    return envHasSpotifyConfig() ? NowPlayingService::Backend::SpotifyWeb
                                 : NowPlayingService::Backend::Playerctl;
}

QString configuredSourceLabel(const QString &playerName)
{
    const QString value = QString::fromUtf8(qgetenv("BEAGLEY_NOW_PLAYING_SOURCE_LABEL")).trimmed();
    if (!value.isEmpty()) {
        return value;
    }
    if (playerName.isEmpty() || playerName.compare(QStringLiteral("auto"), Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Media");
    }
    if (playerName.compare(QStringLiteral("spotify"), Qt::CaseInsensitive) == 0) {
        return QStringLiteral("Spotify");
    }

    QString label = playerName;
    label.replace(QLatin1Char('-'), QLatin1Char(' '));
    label.replace(QLatin1Char('_'), QLatin1Char(' '));
    QStringList words = label.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (QString &word : words) {
        if (!word.isEmpty()) {
            word[0] = word.at(0).toUpper();
        }
    }
    return words.isEmpty() ? QStringLiteral("Media") : words.join(QLatin1Char(' '));
}

QString envString(const char *name)
{
    return QString::fromUtf8(qgetenv(name)).trimmed();
}

QString nowPlayingStatePath()
{
    const QString configured = envString("BEAGLEY_NOW_PLAYING_STATE_PATH");
    if (!configured.isEmpty()) {
        return configured;
    }
#if defined(Q_OS_LINUX)
    return QStringLiteral("/run/beagley-nowplaying/state.json");
#else
    return QDir::tempPath() + QStringLiteral("/beagley-nowplaying-state.json");
#endif
}

QString backendName(NowPlayingService::Backend backend)
{
    return backend == NowPlayingService::Backend::SpotifyWeb
        ? QStringLiteral("spotify-web")
        : QStringLiteral("playerctl");
}

QString normalizedState(bool available,
                        bool playing,
                        const QString &status,
                        const QString &detail)
{
    const QString normalizedStatus = status.trimmed().toUpper();
    if (normalizedStatus == QLatin1String("AUTH")) {
        return QStringLiteral("auth_required");
    }
    if (normalizedStatus == QLatin1String("PERMISSION")) {
        return QStringLiteral("permission_required");
    }
    if (available && playing) {
        return QStringLiteral("playing");
    }
    if (available) {
        return QStringLiteral("paused");
    }
    if (normalizedStatus == QLatin1String("IDLE")
        || detail.contains(QStringLiteral("Open Spotify"), Qt::CaseInsensitive)) {
        return QStringLiteral("idle");
    }
    if (normalizedStatus == QLatin1String("OFFLINE")) {
        return QStringLiteral("offline");
    }
    if (!normalizedStatus.isEmpty()) {
        return normalizedStatus.toLower();
    }
    return QStringLiteral("unknown");
}

bool envFlag(const char *name)
{
    const QString value = envString(name).toLower();
    return value == QLatin1String("1")
        || value == QLatin1String("true")
        || value == QLatin1String("yes")
        || value == QLatin1String("on");
}

int envPort(const char *name, int fallback)
{
    bool ok = false;
    const int value = envString(name).toInt(&ok);
    return ok && value > 0 && value < 65536 ? value : fallback;
}

QString localCallbackHost()
{
    const QString configured = envString("BEAGLEY_SPOTIFY_CALLBACK_HOST");
    if (!configured.isEmpty()) {
        return configured;
    }
    const QList<QHostAddress> addresses = QNetworkInterface::allAddresses();
    for (const QHostAddress &address : addresses) {
        if (address.protocol() != QAbstractSocket::IPv4Protocol || address.isLoopback()) {
            continue;
        }
        const QString text = address.toString();
        if (!text.startsWith(QStringLiteral("169.254."))) {
            return text;
        }
    }
    return QStringLiteral("127.0.0.1");
}

QString callbackRedirectUri(int port)
{
    const QString configured = envString("BEAGLEY_SPOTIFY_REDIRECT_URI");
    if (!configured.isEmpty()) {
        return configured;
    }
    return QStringLiteral("http://%1:%2/spotify/callback").arg(localCallbackHost()).arg(port);
}

QString pairingPublicBaseUrl(int port)
{
    const QString configured = envString("BEAGLEY_SPOTIFY_PAIRING_BASE_URL");
    if (!configured.isEmpty()) {
        QString trimmed = configured;
        while (trimmed.endsWith(QLatin1Char('/'))) {
            trimmed.chop(1);
        }
        return trimmed;
    }
    return QStringLiteral("http://%1:%2").arg(localCallbackHost()).arg(port);
}

QString trimmedBaseUrl(const char *name)
{
    QString value = envString(name);
    while (value.endsWith(QLatin1Char('/'))) {
        value.chop(1);
    }
    return value;
}

QUrl brokerApiUrl(const QString &baseUrl, const QString &path)
{
    QString normalizedPath = path;
    if (!normalizedPath.startsWith(QLatin1Char('/'))) {
        normalizedPath.prepend(QLatin1Char('/'));
    }
    return QUrl(baseUrl + normalizedPath);
}

QString base64Url(const QByteArray &bytes)
{
    QString encoded = QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding
                                                         | QByteArray::OmitTrailingEquals));
    return encoded;
}

QByteArray randomBytes(int length)
{
    QByteArray bytes;
    bytes.resize(length);
    for (int i = 0; i < length; ++i) {
        bytes[i] = static_cast<char>(QRandomGenerator::global()->bounded(256));
    }
    return bytes;
}

QString randomPairingCode()
{
    const QString alphabet = QStringLiteral("ABCDEFGHJKLMNPQRSTUVWXYZ23456789");
    QString code;
    code.reserve(6);
    for (int i = 0; i < 6; ++i) {
        code.append(alphabet.at(QRandomGenerator::global()->bounded(alphabet.size())));
    }
    return code;
}

QString spotifyArtists(const QJsonArray &artists)
{
    QStringList names;
    for (const QJsonValue &value : artists) {
        const QString name = value.toObject().value(QStringLiteral("name")).toString().trimmed();
        if (!name.isEmpty()) {
            names << name;
        }
    }
    return names.join(QStringLiteral(", "));
}

QUrl spotifyUrl(const QString &path, const QUrlQuery &query = {})
{
    QUrl url(QString::fromLatin1(kSpotifyApiBase) + path);
    if (!query.isEmpty()) {
        url.setQuery(query);
    }
    return url;
}

QString queryItem(const QString &key, const QString &value)
{
    return QString::fromLatin1(QUrl::toPercentEncoding(key))
        + QLatin1Char('=')
        + QString::fromLatin1(QUrl::toPercentEncoding(value));
}

QString spotifyAuthorizeUrl(const QString &clientId,
                            const QString &scope,
                            const QString &redirectUri,
                            const QString &state,
                            const QString &codeChallenge)
{
    QStringList query;
    query << queryItem(QStringLiteral("response_type"), QStringLiteral("code"))
          << queryItem(QStringLiteral("client_id"), clientId)
          << queryItem(QStringLiteral("scope"), scope)
          << queryItem(QStringLiteral("redirect_uri"), redirectUri)
          << queryItem(QStringLiteral("state"), state)
          << queryItem(QStringLiteral("code_challenge_method"), QStringLiteral("S256"))
          << queryItem(QStringLiteral("code_challenge"), codeChallenge);
    return QStringLiteral("https://accounts.spotify.com/authorize?") + query.join(QLatin1Char('&'));
}

QString requestPath(const QByteArray &request)
{
    const QList<QByteArray> lines = request.split('\n');
    if (lines.isEmpty()) {
        return QString();
    }
    const QList<QByteArray> parts = lines.first().trimmed().split(' ');
    if (parts.size() < 2 || parts.first() != QByteArrayLiteral("GET")) {
        return QString();
    }
    return QString::fromUtf8(parts.at(1));
}

void writeHttp(QTcpSocket *socket, int status, const QByteArray &statusText, const QByteArray &body)
{
    QByteArray response;
    response += "HTTP/1.1 " + QByteArray::number(status) + " " + statusText + "\r\n";
    response += "Connection: close\r\n";
    response += "Content-Type: text/html; charset=utf-8\r\n";
    response += "Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n";
    response += body;
    socket->write(response);
    socket->disconnectFromHost();
}

void redirectHttp(QTcpSocket *socket, const QString &location)
{
    QByteArray response;
    response += "HTTP/1.1 302 Found\r\n";
    response += "Connection: close\r\n";
    response += "Location: " + location.toUtf8() + "\r\n";
    response += "Content-Length: 0\r\n\r\n";
    socket->write(response);
    socket->disconnectFromHost();
}

int gfMultiply(int x, int y)
{
    int z = 0;
    for (int i = 7; i >= 0; --i) {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        if (((y >> i) & 1) != 0) {
            z ^= x;
        }
    }
    return z & 0xFF;
}

QVector<int> reedSolomonGenerator(int degree)
{
    QVector<int> result;
    result << 1;
    int root = 1;
    for (int i = 0; i < degree; ++i) {
        result << 0;
        for (int j = result.size() - 1; j >= 1; --j) {
            result[j] = result[j - 1] ^ gfMultiply(result[j], root);
        }
        result[0] = gfMultiply(result[0], root);
        root = gfMultiply(root, 0x02);
    }
    return result;
}

QVector<int> reedSolomonRemainder(const QVector<int> &data, int degree)
{
    const QVector<int> generator = reedSolomonGenerator(degree);
    QVector<int> result(degree, 0);
    for (int value : data) {
        const int factor = value ^ result.first();
        for (int i = 0; i < degree - 1; ++i) {
            result[i] = result[i + 1] ^ gfMultiply(generator.at(degree - 1 - i), factor);
        }
        result[degree - 1] = gfMultiply(generator.first(), factor);
    }
    return result;
}

void appendBits(QVector<bool> *bits, int value, int count)
{
    for (int i = count - 1; i >= 0; --i) {
        bits->append(((value >> i) & 1) != 0);
    }
}

QStringList qrRowsForShortText(const QString &text)
{
    const QByteArray payload = text.toUtf8();
    constexpr int version = 5;
    constexpr int size = 21 + (version - 1) * 4;
    constexpr int dataCodewords = 108;
    constexpr int eccCodewords = 26;
    if (payload.size() > 106) {
        return {};
    }

    QVector<bool> bits;
    appendBits(&bits, 0x4, 4);
    appendBits(&bits, payload.size(), 8);
    for (uchar byte : payload) {
        appendBits(&bits, byte, 8);
    }
    const int capacityBits = dataCodewords * 8;
    appendBits(&bits, 0, qMin(4, capacityBits - bits.size()));
    while ((bits.size() % 8) != 0) {
        bits.append(false);
    }

    QVector<int> data;
    for (int i = 0; i < bits.size(); i += 8) {
        int value = 0;
        for (int j = 0; j < 8; ++j) {
            value = (value << 1) | (bits.at(i + j) ? 1 : 0);
        }
        data.append(value);
    }
    for (int pad = 0xEC; data.size() < dataCodewords; pad ^= 0xEC ^ 0x11) {
        data.append(pad);
    }
    const QVector<int> ecc = reedSolomonRemainder(data, eccCodewords);
    QVector<int> codewords = data;
    codewords += ecc;

    QVector<QVector<int>> modules(size, QVector<int>(size, -1));
    QVector<QVector<bool>> function(size, QVector<bool>(size, false));
    auto setModule = [&](int x, int y, bool dark, bool isFunction = true) {
        if (x < 0 || y < 0 || x >= size || y >= size) {
            return;
        }
        modules[y][x] = dark ? 1 : 0;
        if (isFunction) {
            function[y][x] = true;
        }
    };
    auto finder = [&](int x, int y) {
        for (int dy = -1; dy <= 7; ++dy) {
            for (int dx = -1; dx <= 7; ++dx) {
                const int xx = x + dx;
                const int yy = y + dy;
                const bool in = dx >= 0 && dx <= 6 && dy >= 0 && dy <= 6;
                const bool dark = in && (dx == 0 || dx == 6 || dy == 0 || dy == 6
                                         || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4));
                setModule(xx, yy, dark);
            }
        }
    };
    finder(0, 0);
    finder(size - 7, 0);
    finder(0, size - 7);

    for (int i = 8; i < size - 8; ++i) {
        setModule(i, 6, (i % 2) == 0);
        setModule(6, i, (i % 2) == 0);
    }

    auto alignment = [&](int cx, int cy) {
        for (int dy = -2; dy <= 2; ++dy) {
            for (int dx = -2; dx <= 2; ++dx) {
                setModule(cx + dx, cy + dy, qMax(qAbs(dx), qAbs(dy)) != 1);
            }
        }
    };
    alignment(30, 30);
    setModule(8, size - 8, true);

    auto reserveFormat = [&]() {
        for (int i = 0; i <= 8; ++i) {
            if (i != 6) {
                function[8][i] = true;
                function[i][8] = true;
            }
        }
        for (int i = 0; i < 8; ++i) {
            function[8][size - 1 - i] = true;
            function[size - 1 - i][8] = true;
        }
    };
    reserveFormat();

    int bitIndex = 0;
    for (int right = size - 1; right >= 1; right -= 2) {
        if (right == 6) {
            right = 5;
        }
        for (int vert = 0; vert < size; ++vert) {
            const int y = (((right + 1) & 2) == 0) ? size - 1 - vert : vert;
            for (int j = 0; j < 2; ++j) {
                const int x = right - j;
                if (function[y][x]) {
                    continue;
                }
                bool dark = false;
                if (bitIndex < codewords.size() * 8) {
                    dark = ((codewords.at(bitIndex >> 3) >> (7 - (bitIndex & 7))) & 1) != 0;
                    ++bitIndex;
                }
                if (((x + y) % 2) == 0) {
                    dark = !dark;
                }
                setModule(x, y, dark, false);
            }
        }
    }

    auto formatBits = []() {
        int data = 0x08; // error correction L, mask 0
        int value = data << 10;
        for (int i = 14; i >= 10; --i) {
            if (((value >> i) & 1) != 0) {
                value ^= 0x537 << (i - 10);
            }
        }
        return ((data << 10) | value) ^ 0x5412;
    };
    const int format = formatBits();
    auto bit = [&](int i) { return ((format >> i) & 1) != 0; };
    for (int i = 0; i <= 5; ++i) setModule(8, i, bit(i));
    setModule(8, 7, bit(6));
    setModule(8, 8, bit(7));
    setModule(7, 8, bit(8));
    for (int i = 9; i < 15; ++i) setModule(14 - i, 8, bit(i));
    for (int i = 0; i < 8; ++i) setModule(size - 1 - i, 8, bit(i));
    for (int i = 8; i < 15; ++i) setModule(8, size - 15 + i, bit(i));

    QStringList rows;
    rows.reserve(size);
    for (int y = 0; y < size; ++y) {
        QString row;
        row.reserve(size);
        for (int x = 0; x < size; ++x) {
            row.append(modules[y][x] == 1 ? QLatin1Char('1') : QLatin1Char('0'));
        }
        rows << row;
    }
    return rows;
}

} // namespace

NowPlayingService::NowPlayingService(QObject *parent)
    : QObject(parent)
    , m_backend(configuredBackend())
    , m_playerName(configuredPlayerName())
    , m_spotifyAccessToken(envString("BEAGLEY_SPOTIFY_ACCESS_TOKEN"))
    , m_spotifyRefreshToken(envString("BEAGLEY_SPOTIFY_REFRESH_TOKEN"))
    , m_spotifyClientId(envString("BEAGLEY_SPOTIFY_CLIENT_ID"))
    , m_spotifyClientSecret(envString("BEAGLEY_SPOTIFY_CLIENT_SECRET"))
    , m_spotifyDeviceId(envString("BEAGLEY_SPOTIFY_DEVICE_ID"))
    , m_spotifyMarket(envString("BEAGLEY_SPOTIFY_MARKET"))
    , m_spotifyBrokerUrl(trimmedBaseUrl("BEAGLEY_SPOTIFY_BROKER_URL"))
    , m_spotifyBrokerToken(envString("BEAGLEY_SPOTIFY_BROKER_TOKEN"))
    , m_statePath(nowPlayingStatePath())
    , m_source(sourceLabel())
{
    if (!m_spotifyAccessToken.isEmpty()) {
        m_spotifyAccessTokenExpiresAt = QDateTime::currentDateTimeUtc().addSecs(50 * 60);
    }

    m_refreshTimer.setInterval(refreshIntervalMs());
    m_refreshTimer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_refreshTimer, &QTimer::timeout, this, &NowPlayingService::refresh);
    m_refreshTimer.start();

    m_timeoutTimer.setSingleShot(true);
    m_timeoutTimer.setInterval(1800);
    connect(&m_timeoutTimer, &QTimer::timeout, this, [this]() {
        if (!m_process) {
            return;
        }
        QProcess *process = m_process;
        process->kill();
        finishProcess(process, true, sourceLabel() + QStringLiteral(" did not respond"));
    });

    m_pairingTimeoutTimer.setSingleShot(true);
    m_pairingTimeoutTimer.setInterval(kPairingTimeoutMs);
    connect(&m_pairingTimeoutTimer, &QTimer::timeout, this, [this]() {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify pairing timed out"));
    });
    m_brokerPairingPollTimer.setInterval(2500);
    m_brokerPairingPollTimer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_brokerPairingPollTimer, &QTimer::timeout, this, &NowPlayingService::pollBrokerSpotifyPairing);
    connect(&m_pairingServer, &QTcpServer::newConnection, this, &NowPlayingService::handlePairingConnection);

    QTimer::singleShot(500, this, &NowPlayingService::refresh);
    if (envFlag("BEAGLEY_SPOTIFY_PAIRING_AUTOSTART")) {
        QTimer::singleShot(900, this, &NowPlayingService::beginSpotifyPairing);
    }
    writeStateSnapshot();
}

NowPlayingService::~NowPlayingService()
{
    stopPairingServer();
    if (m_pairingReply) {
        m_pairingReply->abort();
        m_pairingReply->deleteLater();
        m_pairingReply = nullptr;
    }
    if (m_networkReply) {
        m_networkReply->abort();
        m_networkReply->deleteLater();
        m_networkReply = nullptr;
    }
    if (!m_process) {
        return;
    }
    m_process->kill();
    m_process->deleteLater();
    m_process = nullptr;
}

void NowPlayingService::refresh()
{
    if (spotifyBackendActive()) {
        refreshSpotifyPlayback();
        return;
    }

    refreshPlayerctl();
}

void NowPlayingService::refreshPlayerctl()
{
    if (m_process) {
        return;
    }

    auto *process = new QProcess(this);
    m_process = process;
    process->setProcessChannelMode(QProcess::SeparateChannels);

    connect(process, &QProcess::finished, this, [this, process](int, QProcess::ExitStatus) {
        finishProcess(process, false);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finishProcess(process, true, sourceLabel() + QStringLiteral(" not connected"));
        }
    });

#if defined(Q_OS_MACOS)
    const QString script = QString::fromUtf8(R"APPLESCRIPT(
if application "Spotify" is running then
    tell application "Spotify"
        set currentState to player state as string
        if currentState is "playing" or currentState is "paused" then
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            return currentState & linefeed & trackName & linefeed & trackArtist & linefeed & trackAlbum
        else
            return currentState & linefeed & "" & linefeed & "" & linefeed & ""
        end if
    end tell
else
    return "offline" & linefeed & "" & linefeed & "" & linefeed & ""
end if
)APPLESCRIPT");
    process->start(QStringLiteral("/usr/bin/osascript"), { QStringLiteral("-e"), script });
#else
    QStringList args = playerctlBaseArgs();
    args << QStringLiteral("metadata")
         << QStringLiteral("--format")
         << QStringLiteral("{{status}}\n{{title}}\n{{artist}}\n{{album}}");
    process->start(QStringLiteral("playerctl"), args);
#endif
    m_timeoutTimer.start();
}

QString NowPlayingService::sourceLabel() const
{
#if defined(Q_OS_MACOS)
    return QStringLiteral("Spotify");
#else
    if (m_backend == Backend::SpotifyWeb) {
        return configuredSourceLabel(QStringLiteral("spotify"));
    }
    return configuredSourceLabel(m_playerName);
#endif
}

QStringList NowPlayingService::playerctlBaseArgs() const
{
    const QString trimmed = m_playerName.trimmed();
    if (trimmed.isEmpty() || trimmed.compare(QStringLiteral("auto"), Qt::CaseInsensitive) == 0) {
        return {};
    }
    return { QStringLiteral("-p"), trimmed };
}

void NowPlayingService::playPause()
{
    if (spotifyBackendActive()) {
        refreshSpotifyPlayback();
        return;
    }
    runControlCommand(QStringLiteral("play-pause"));
}

void NowPlayingService::next()
{
    if (spotifyBackendActive()) {
        refreshSpotifyPlayback();
        return;
    }
    runControlCommand(QStringLiteral("next"));
}

void NowPlayingService::previous()
{
    if (spotifyBackendActive()) {
        refreshSpotifyPlayback();
        return;
    }
    runControlCommand(QStringLiteral("previous"));
}

void NowPlayingService::saveCurrentSpotifyTrack()
{
    if (!spotifyBackendActive()) {
        return;
    }
    if (spotifyTrackSavedKnown() && spotifyTrackSaved()) {
        setSpotifySaveState(false,
                            QStringLiteral("SAVED"),
                            QStringLiteral("Already in Liked Songs"),
                            2200);
        return;
    }
    if (m_spotifyCurrentTrackId.isEmpty()) {
        setSpotifySaveState(false,
                            QStringLiteral("NO TRACK"),
                            QStringLiteral("No track to save"),
                            1800);
        return;
    }
    runSpotifyAction(SpotifyAction::SaveCurrentTrack);
}

void NowPlayingService::runControlCommand(const QString &action)
{
    if (action.isEmpty()) {
        return;
    }

#if defined(Q_OS_MACOS)
    QString spotifyCommand;
    if (action == QLatin1String("play-pause")) {
        spotifyCommand = QStringLiteral("playpause");
    } else if (action == QLatin1String("next")) {
        spotifyCommand = QStringLiteral("next track");
    } else if (action == QLatin1String("previous")) {
        spotifyCommand = QStringLiteral("previous track");
    } else {
        return;
    }

    const QString script = QStringLiteral(R"APPLESCRIPT(
if application "Spotify" is running then
    tell application "Spotify" to %1
end if
)APPLESCRIPT").arg(spotifyCommand);
    QProcess::startDetached(QStringLiteral("/usr/bin/osascript"), { QStringLiteral("-e"), script });
#else
    QStringList args = playerctlBaseArgs();
    args << action;
    QProcess::startDetached(QStringLiteral("playerctl"), args);
#endif
    QTimer::singleShot(500, this, &NowPlayingService::refresh);
}

bool NowPlayingService::spotifyBackendActive() const
{
    return m_backend == Backend::SpotifyWeb;
}

bool NowPlayingService::spotifyRefreshConfigured() const
{
    return !m_spotifyRefreshToken.isEmpty() && !m_spotifyClientId.isEmpty();
}

bool NowPlayingService::spotifySaveSupported() const
{
    return spotifyBackendActive() && !m_spotifyCurrentTrackId.isEmpty();
}

bool NowPlayingService::spotifyTrackSaved() const
{
    return m_spotifyTrackSavedKnown
        && m_spotifyTrackSaved
        && !m_spotifySavedStateTrackId.isEmpty()
        && m_spotifySavedStateTrackId == m_spotifyCurrentTrackId;
}

bool NowPlayingService::spotifyTrackSavedKnown() const
{
    return m_spotifyTrackSavedKnown
        && !m_spotifySavedStateTrackId.isEmpty()
        && m_spotifySavedStateTrackId == m_spotifyCurrentTrackId;
}

bool NowPlayingService::spotifyTokenUsable() const
{
    if (m_spotifyAccessToken.isEmpty()) {
        return false;
    }
    if (!m_spotifyAccessTokenExpiresAt.isValid() || !spotifyRefreshConfigured()) {
        return true;
    }
    return QDateTime::currentDateTimeUtc().secsTo(m_spotifyAccessTokenExpiresAt) > 60;
}

void NowPlayingService::setSpotifyAuthRequired(const QString &detail)
{
    setNowPlaying(false,
                  false,
                  sourceLabel(),
                  QString(),
                  QString(),
                  QString(),
                  QStringLiteral("AUTH"),
                  detail);
    autoStartSpotifyRepairPairing();
}

void NowPlayingService::autoStartSpotifyRepairPairing()
{
    if (!spotifyBackendActive()
        || m_spotifyClientId.isEmpty()
        || m_pairingActive
        || m_pairingReply) {
        return;
    }

    QTimer::singleShot(300, this, [this]() {
        if (!m_pairingActive && !m_pairingReply && spotifyBackendActive()) {
            beginSpotifyPairing();
        }
    });
}

void NowPlayingService::refreshSpotifyPlayback(bool retriedAfterTokenRefresh)
{
    if (m_networkReply) {
        return;
    }
    if (!spotifyTokenUsable()) {
        if (spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = SpotifyAction::RefreshPlayback;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login required"));
        }
        return;
    }

    QUrlQuery query;
    query.addQueryItem(QStringLiteral("additional_types"), QStringLiteral("track,episode"));
    if (!m_spotifyMarket.isEmpty()) {
        query.addQueryItem(QStringLiteral("market"), m_spotifyMarket);
    }
    QNetworkRequest request(spotifyUrl(QStringLiteral("/me/player/currently-playing"), query));
    request.setRawHeader("Authorization", "Bearer " + m_spotifyAccessToken.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");

    QNetworkReply *reply = m_network.get(request);
    m_networkReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, retriedAfterTokenRefresh]() {
        if (reply != m_networkReply) {
            reply->deleteLater();
            return;
        }
        m_networkReply = nullptr;
        handleSpotifyPlaybackReply(reply, retriedAfterTokenRefresh);
        reply->deleteLater();
    });
}

void NowPlayingService::refreshSpotifySavedState(bool retriedAfterTokenRefresh)
{
    if (m_networkReply || !spotifyBackendActive()) {
        return;
    }
    const QString trackId = m_spotifyCurrentTrackId;
    if (trackId.isEmpty()) {
        setSpotifyTrackSavedState(false, false);
        return;
    }
    if (!spotifyTokenUsable()) {
        if (spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = SpotifyAction::RefreshSavedState;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login required"));
        }
        return;
    }

    QUrlQuery query;
    query.addQueryItem(QStringLiteral("ids"), trackId);
    QNetworkRequest request(spotifyUrl(QStringLiteral("/me/tracks/contains"), query));
    request.setRawHeader("Authorization", "Bearer " + m_spotifyAccessToken.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");

    QNetworkReply *reply = m_network.get(request);
    m_networkReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, retriedAfterTokenRefresh, trackId]() {
        if (reply != m_networkReply) {
            reply->deleteLater();
            return;
        }
        m_networkReply = nullptr;
        handleSpotifySavedStateReply(reply, retriedAfterTokenRefresh, trackId);
        reply->deleteLater();
    });
}

void NowPlayingService::confirmSpotifySavedTrack(const QString &trackId, int attemptsRemaining)
{
    if (trackId.isEmpty() || trackId != m_spotifyCurrentTrackId) {
        return;
    }
    if (m_networkReply) {
        if (attemptsRemaining > 0) {
            QTimer::singleShot(600, this, [this, trackId, attemptsRemaining]() {
                confirmSpotifySavedTrack(trackId, attemptsRemaining - 1);
            });
        } else {
            setSpotifySaveState(false,
                                QStringLiteral("FAILED"),
                                QStringLiteral("Could not confirm Liked Songs"),
                                3200);
        }
        return;
    }
    refreshSpotifySavedState();
}

void NowPlayingService::refreshSpotifyAccessToken()
{
    if (m_networkReply) {
        return;
    }
    if (!spotifyRefreshConfigured()) {
        setSpotifyAuthRequired(QStringLiteral("Spotify login required"));
        return;
    }

    QNetworkRequest request(QUrl(QString::fromLatin1(kSpotifyTokenUrl)));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");
    if (!m_spotifyClientSecret.isEmpty()) {
        const QByteArray basic = (m_spotifyClientId + QLatin1Char(':') + m_spotifyClientSecret)
                                     .toUtf8()
                                     .toBase64();
        request.setRawHeader("Authorization", "Basic " + basic);
    }

    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    form.addQueryItem(QStringLiteral("refresh_token"), m_spotifyRefreshToken);
    if (m_spotifyClientSecret.isEmpty()) {
        form.addQueryItem(QStringLiteral("client_id"), m_spotifyClientId);
    }

    QNetworkReply *reply = m_network.post(request, form.query(QUrl::FullyEncoded).toUtf8());
    m_networkReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply != m_networkReply) {
            reply->deleteLater();
            return;
        }
        m_networkReply = nullptr;
        handleSpotifyTokenReply(reply);
        reply->deleteLater();
    });
}

void NowPlayingService::runSpotifyAction(SpotifyAction action, bool retriedAfterTokenRefresh)
{
    if (action == SpotifyAction::None || action == SpotifyAction::RefreshPlayback) {
        refreshSpotifyPlayback(retriedAfterTokenRefresh);
        return;
    }
    if (action == SpotifyAction::RefreshSavedState) {
        refreshSpotifySavedState(retriedAfterTokenRefresh);
        return;
    }
    if (m_networkReply) {
        if (action == SpotifyAction::SaveCurrentTrack) {
            setSpotifySaveState(false,
                                QStringLiteral("WAIT"),
                                QStringLiteral("Spotify is updating"),
                                1200);
            QTimer::singleShot(900, this, &NowPlayingService::saveCurrentSpotifyTrack);
        }
        return;
    }
    if (!spotifyTokenUsable()) {
        if (spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = action;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login required"));
        }
        return;
    }

    QString path;
    switch (action) {
    case SpotifyAction::Play:
        path = QStringLiteral("/me/player/play");
        break;
    case SpotifyAction::Pause:
        path = QStringLiteral("/me/player/pause");
        break;
    case SpotifyAction::Next:
        path = QStringLiteral("/me/player/next");
        break;
    case SpotifyAction::Previous:
        path = QStringLiteral("/me/player/previous");
        break;
    case SpotifyAction::SaveCurrentTrack:
        if (m_spotifyCurrentTrackId.isEmpty()) {
            setSpotifySaveState(false,
                                QStringLiteral("NO TRACK"),
                                QStringLiteral("No track to save"),
                                1800);
            return;
        }
        path = QStringLiteral("/me/tracks");
        break;
    case SpotifyAction::None:
    case SpotifyAction::RefreshPlayback:
    case SpotifyAction::RefreshSavedState:
        return;
    }

    QUrlQuery query;
    if (action == SpotifyAction::SaveCurrentTrack) {
        query.addQueryItem(QStringLiteral("ids"), m_spotifyCurrentTrackId);
    } else if (!m_spotifyDeviceId.isEmpty()) {
        query.addQueryItem(QStringLiteral("device_id"), m_spotifyDeviceId);
    }
    QNetworkRequest request(spotifyUrl(path, query));
    request.setRawHeader("Authorization", "Bearer " + m_spotifyAccessToken.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QNetworkReply *reply = nullptr;
    if (action == SpotifyAction::SaveCurrentTrack) {
        setSpotifySaveState(true,
                            QStringLiteral("SAVING"),
                            QStringLiteral("Adding to Liked Songs"));
        reply = m_network.put(request, QByteArray());
    } else if (action == SpotifyAction::Play || action == SpotifyAction::Pause) {
        reply = m_network.put(request, QByteArray());
    } else {
        reply = m_network.post(request, QByteArray());
    }
    m_networkReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply, action, retriedAfterTokenRefresh]() {
        if (reply != m_networkReply) {
            reply->deleteLater();
            return;
        }
        m_networkReply = nullptr;
        handleSpotifyControlReply(reply, action, retriedAfterTokenRefresh);
        reply->deleteLater();
    });
}

void NowPlayingService::handleSpotifyPlaybackReply(QNetworkReply *reply, bool retriedAfterTokenRefresh)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    m_lastPlaybackHttpStatus = statusCode;
    m_lastBackendError = reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();

    if (statusCode == 401) {
        if (!retriedAfterTokenRefresh && spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = SpotifyAction::RefreshPlayback;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login expired"));
        }
        return;
    }
    if (statusCode == 204) {
        if (!m_spotifyCurrentTrackId.isEmpty()) {
            m_spotifyCurrentTrackId.clear();
            setSpotifyTrackSavedState(false, false);
        }
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("IDLE"),
                      QStringLiteral("Open Spotify on your phone"));
        return;
    }
    if (statusCode == 403) {
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("PERMISSION"),
                      QStringLiteral("Spotify permission required"));
        return;
    }
    if (statusCode == 429) {
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("OFFLINE"),
                      QStringLiteral("Spotify rate limited"));
        return;
    }
    if (reply->error() != QNetworkReply::NoError || statusCode != 200) {
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("OFFLINE"),
                      QStringLiteral("Spotify unavailable"));
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    if (!document.isObject()) {
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("OFFLINE"),
                      QStringLiteral("Spotify response invalid"));
        return;
    }

    const QJsonObject root = document.object();
    const QJsonObject item = root.value(QStringLiteral("item")).toObject();
    const QString itemType = item.value(QStringLiteral("type"))
                                 .toString(root.value(QStringLiteral("currently_playing_type")).toString());
    const QString title = item.value(QStringLiteral("name")).toString().trimmed();
    QString artist;
    QString album;
    QString trackId;
    if (itemType == QLatin1String("track")) {
        trackId = item.value(QStringLiteral("id")).toString().trimmed();
        artist = spotifyArtists(item.value(QStringLiteral("artists")).toArray());
        album = item.value(QStringLiteral("album")).toObject().value(QStringLiteral("name")).toString().trimmed();
    } else if (itemType == QLatin1String("episode")) {
        const QJsonObject show = item.value(QStringLiteral("show")).toObject();
        artist = show.value(QStringLiteral("publisher")).toString().trimmed();
        album = show.value(QStringLiteral("name")).toString().trimmed();
    }

    const bool playing = root.value(QStringLiteral("is_playing")).toBool(false);
    const bool available = !title.isEmpty();
    const QString status = playing
        ? QStringLiteral("PLAYING")
        : (!title.isEmpty() ? QStringLiteral("PAUSED")
                            : QStringLiteral("IDLE"));
    const QString detail = title.isEmpty()
        ? QStringLiteral("Open Spotify on your phone")
        : QStringLiteral("Spotify now playing");
    const bool trackChanged = m_spotifyCurrentTrackId != trackId;
    if (trackChanged) {
        m_spotifyCurrentTrackId = trackId;
        setSpotifyTrackSavedState(false, false);
        if (!m_spotifySavePending) {
            setSpotifySaveState(false, QString(), QString());
        }
    }

    setNowPlaying(available,
                  playing,
                  sourceLabel(),
                  title,
                  artist,
                  album,
                  status,
                  detail);
    if (trackChanged) {
        emit nowPlayingChanged();
    }
    if (!trackId.isEmpty() && (trackChanged || !spotifyTrackSavedKnown())) {
        refreshSpotifySavedState();
    }
}

void NowPlayingService::handleSpotifyTokenReply(QNetworkReply *reply)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    m_lastTokenHttpStatus = statusCode;
    if (reply->error() != QNetworkReply::NoError) {
        m_lastBackendError = reply->errorString();
    }
    if (reply->error() != QNetworkReply::NoError || statusCode != 200) {
        m_pendingSpotifyAction = SpotifyAction::None;
        setSpotifyAuthRequired(QStringLiteral("Spotify login expired"));
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    const QJsonObject root = document.object();
    const QString accessToken = root.value(QStringLiteral("access_token")).toString().trimmed();
    if (accessToken.isEmpty()) {
        m_pendingSpotifyAction = SpotifyAction::None;
        setSpotifyAuthRequired(QStringLiteral("Spotify login failed"));
        return;
    }

    m_spotifyAccessToken = accessToken;
    m_lastBackendError.clear();
    const int expiresIn = qMax(300, root.value(QStringLiteral("expires_in")).toInt(3600));
    m_spotifyAccessTokenExpiresAt = QDateTime::currentDateTimeUtc().addSecs(expiresIn);
    const QString refreshToken = root.value(QStringLiteral("refresh_token")).toString().trimmed();
    if (!refreshToken.isEmpty()) {
        m_spotifyRefreshToken = refreshToken;
        QString error;
        if (!persistSpotifyRefreshToken(&error)) {
            m_pendingSpotifyAction = SpotifyAction::None;
            setSpotifyAuthRequired(error.isEmpty() ? QStringLiteral("Spotify save failed") : error);
            return;
        }
    }

    const SpotifyAction pendingAction = m_pendingSpotifyAction;
    m_pendingSpotifyAction = SpotifyAction::None;
    if (pendingAction == SpotifyAction::None || pendingAction == SpotifyAction::RefreshPlayback) {
        refreshSpotifyPlayback(true);
    } else if (pendingAction == SpotifyAction::RefreshSavedState) {
        refreshSpotifySavedState(true);
    } else {
        runSpotifyAction(pendingAction, true);
    }
}

void NowPlayingService::handleSpotifyControlReply(QNetworkReply *reply,
                                                  SpotifyAction action,
                                                  bool retriedAfterTokenRefresh)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (statusCode == 401) {
        if (!retriedAfterTokenRefresh && spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = action;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login expired"));
        }
        return;
    }
    if (statusCode == 403) {
        if (action == SpotifyAction::SaveCurrentTrack) {
            setSpotifySaveState(false,
                                QStringLiteral("REPAIR"),
                                QStringLiteral("Re-pair Spotify for Liked Songs"),
                                4500);
            autoStartSpotifyRepairPairing();
            return;
        }
        setNowPlaying(m_available,
                      m_playing,
                      m_source,
                      m_title,
                      m_artist,
                      m_album,
                      QStringLiteral("PERMISSION"),
                      QStringLiteral("Spotify Premium required"));
        QTimer::singleShot(800, this, &NowPlayingService::refresh);
        return;
    }
    if (statusCode == 404) {
        if (action == SpotifyAction::SaveCurrentTrack) {
            setSpotifySaveState(false,
                                QStringLiteral("NO TRACK"),
                                QStringLiteral("No track to save"),
                                2400);
            return;
        }
        setNowPlaying(m_available,
                      m_playing,
                      m_source,
                      m_title,
                      m_artist,
                      m_album,
                      QStringLiteral("OFFLINE"),
                      QStringLiteral("Open Spotify on your phone"));
        QTimer::singleShot(800, this, &NowPlayingService::refresh);
        return;
    }
    if (statusCode == 429) {
        if (action == SpotifyAction::SaveCurrentTrack) {
            setSpotifySaveState(false,
                                QStringLiteral("RATE LIMIT"),
                                QStringLiteral("Spotify rate limited"),
                                3200);
            return;
        }
        setNowPlaying(m_available,
                      m_playing,
                      m_source,
                      m_title,
                      m_artist,
                      m_album,
                      QStringLiteral("OFFLINE"),
                      QStringLiteral("Spotify rate limited"));
        return;
    }

    if (reply->error() != QNetworkReply::NoError || statusCode < 200 || statusCode >= 300) {
        if (action == SpotifyAction::SaveCurrentTrack) {
            setSpotifySaveState(false,
                                QStringLiteral("FAILED"),
                                QStringLiteral("Could not add song"),
                                3200);
            return;
        }
    }

    if (action == SpotifyAction::SaveCurrentTrack) {
        const QString savedTrackId = m_spotifyCurrentTrackId;
        setSpotifyTrackSavedState(false, false, savedTrackId);
        setSpotifySaveState(true,
                            QStringLiteral("CHECKING"),
                            QStringLiteral("Confirming Liked Songs"));
        QTimer::singleShot(900, this, [this, savedTrackId]() {
            confirmSpotifySavedTrack(savedTrackId);
        });
        return;
    }

    QTimer::singleShot(800, this, &NowPlayingService::refresh);
}

void NowPlayingService::handleSpotifySavedStateReply(QNetworkReply *reply,
                                                     bool retriedAfterTokenRefresh,
                                                     const QString &trackId)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    if (trackId.isEmpty() || trackId != m_spotifyCurrentTrackId) {
        return;
    }

    if (statusCode == 401) {
        if (!retriedAfterTokenRefresh && spotifyRefreshConfigured()) {
            m_pendingSpotifyAction = SpotifyAction::RefreshSavedState;
            refreshSpotifyAccessToken();
        } else {
            setSpotifyAuthRequired(QStringLiteral("Spotify login expired"));
        }
        return;
    }
    if (statusCode == 403) {
        setSpotifyTrackSavedState(false, false, trackId);
        setSpotifySaveState(false,
                            QStringLiteral("REPAIR"),
                            QStringLiteral("Liked Songs permission required"),
                            4500);
        autoStartSpotifyRepairPairing();
        return;
    }
    if (statusCode == 429) {
        setSpotifyTrackSavedState(false, false, trackId);
        setSpotifySaveState(false,
                            QStringLiteral("RATE LIMIT"),
                            QStringLiteral("Spotify rate limited"),
                            3200);
        return;
    }
    if (reply->error() != QNetworkReply::NoError || statusCode != 200) {
        setSpotifyTrackSavedState(false, false, trackId);
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    if (!document.isArray() || document.array().isEmpty()) {
        setSpotifyTrackSavedState(false, false, trackId);
        return;
    }

    const bool saved = document.array().at(0).toBool(false);
    const bool confirmingSave = m_spotifySaveStatus == QLatin1String("CHECKING")
        || m_spotifySaveStatus == QLatin1String("SAVING");

    setSpotifyTrackSavedState(true, saved, trackId);

    if (confirmingSave) {
        if (saved) {
            setSpotifySaveState(false,
                                QStringLiteral("SAVED"),
                                QStringLiteral("Added to Liked Songs"),
                                3000);
        } else {
            setSpotifySaveState(false,
                                QStringLiteral("FAILED"),
                                QStringLiteral("Not in Liked Songs"),
                                3200);
        }
    }
}

bool NowPlayingService::spotifyPairingSupported() const
{
    return spotifyBackendActive();
}

bool NowPlayingService::spotifyBrokerConfigured() const
{
    return !m_spotifyBrokerUrl.isEmpty();
}

void NowPlayingService::beginSpotifyPairing()
{
    if (!spotifyBackendActive()) {
        setSpotifyPairingState(false, QStringLiteral("Spotify backend disabled"));
        return;
    }
    if (m_spotifyClientId.isEmpty()) {
        setSpotifyPairingState(false, QStringLiteral("Spotify app missing"));
        return;
    }

    if (spotifyBrokerConfigured()) {
        beginBrokerSpotifyPairing();
        return;
    }

    stopPairingServer();
    const int requestedPort = envPort("BEAGLEY_SPOTIFY_CALLBACK_PORT", kPairingPortDefault);
    if (!m_pairingServer.listen(QHostAddress::AnyIPv4, static_cast<quint16>(requestedPort))) {
        setSpotifyPairingState(false, QStringLiteral("Spotify pairing unavailable"));
        return;
    }

    const int port = int(m_pairingServer.serverPort());
    m_pairingState = base64Url(randomBytes(18));
    m_pairingCode = randomPairingCode();
    m_pairingCodeVerifier = base64Url(randomBytes(64));
    const QByteArray verifierHash = QCryptographicHash::hash(m_pairingCodeVerifier.toUtf8(),
                                                             QCryptographicHash::Sha256);
    const QString codeChallenge = base64Url(verifierHash);
    m_pairingRedirectUri = callbackRedirectUri(port);

    m_pairingAuthorizeUrl = spotifyAuthorizeUrl(m_spotifyClientId,
                                                QString::fromLatin1(kSpotifyScopes),
                                                m_pairingRedirectUri,
                                                m_pairingState,
                                                codeChallenge);

    const QString baseUrl = pairingPublicBaseUrl(port);
    const QString pairUrl = QStringLiteral("%1/spotify/pair/%2").arg(baseUrl, m_pairingCode);
    setSpotifyPairingState(true,
                           QStringLiteral("Scan or open on phone"),
                           pairUrl,
                           m_pairingCode,
                           qrRowsForShortText(pairUrl));
    m_pairingTimeoutTimer.start();
}

void NowPlayingService::cancelSpotifyPairing()
{
    stopPairingServer();
    setSpotifyPairingState(false, QStringLiteral("Spotify pairing cancelled"));
}

void NowPlayingService::stopPairingServer()
{
    m_pairingTimeoutTimer.stop();
    m_brokerPairingPollTimer.stop();
    m_pairingServer.close();
    while (m_pairingServer.hasPendingConnections()) {
        QTcpSocket *socket = m_pairingServer.nextPendingConnection();
        socket->disconnectFromHost();
        socket->deleteLater();
    }
}

void NowPlayingService::beginBrokerSpotifyPairing()
{
    stopPairingServer();
    if (m_pairingReply) {
        m_pairingReply->abort();
        m_pairingReply->deleteLater();
        m_pairingReply = nullptr;
    }

    QNetworkRequest request(brokerApiUrl(m_spotifyBrokerUrl, QStringLiteral("/api/sessions")));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    if (!m_spotifyBrokerToken.isEmpty()) {
        request.setRawHeader("Authorization", "Bearer " + m_spotifyBrokerToken.toUtf8());
    }

    QJsonObject body;
    body.insert(QStringLiteral("client_id"), m_spotifyClientId);
    body.insert(QStringLiteral("scope"), QString::fromLatin1(kSpotifyScopes));

    setSpotifyPairingState(true, QStringLiteral("Starting Spotify sign-in"));
    m_pairingTimeoutTimer.start();
    m_pairingReply = m_network.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(m_pairingReply, &QNetworkReply::finished, this, [this]() {
        QNetworkReply *reply = m_pairingReply;
        m_pairingReply = nullptr;
        handleBrokerPairingCreateReply(reply);
        reply->deleteLater();
    });
}

void NowPlayingService::handleBrokerPairingCreateReply(QNetworkReply *reply)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    if (reply->error() != QNetworkReply::NoError || statusCode < 200 || statusCode >= 300) {
        stopPairingServer();
        const QString detail = statusCode == 401
            ? QStringLiteral("Spotify broker denied")
            : QStringLiteral("Spotify broker unavailable");
        setSpotifyPairingState(false, detail);
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    const QJsonObject root = document.object();
    const QString pairCode = root.value(QStringLiteral("pair_code"))
                                 .toString(root.value(QStringLiteral("pairCode")).toString())
                                 .trimmed();
    const QString pairUrl = root.value(QStringLiteral("pair_url"))
                                .toString(root.value(QStringLiteral("pairUrl")).toString())
                                .trimmed();
    if (pairCode.isEmpty() || pairUrl.isEmpty()) {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify broker response invalid"));
        return;
    }

    m_pairingCode = pairCode;
    m_pairingUrl = pairUrl;
    setSpotifyPairingState(true,
                           QStringLiteral("Scan Spotify sign-in"),
                           pairUrl,
                           pairCode,
                           qrRowsForShortText(pairUrl));
    m_brokerPairingPollTimer.start();
}

void NowPlayingService::pollBrokerSpotifyPairing()
{
    if (m_pairingReply || !m_pairingActive || m_pairingCode.isEmpty() || !spotifyBrokerConfigured()) {
        return;
    }

    QNetworkRequest request(brokerApiUrl(m_spotifyBrokerUrl,
                                         QStringLiteral("/api/sessions/%1").arg(m_pairingCode)));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");
    if (!m_spotifyBrokerToken.isEmpty()) {
        request.setRawHeader("Authorization", "Bearer " + m_spotifyBrokerToken.toUtf8());
    }

    m_pairingReply = m_network.get(request);
    connect(m_pairingReply, &QNetworkReply::finished, this, [this]() {
        QNetworkReply *reply = m_pairingReply;
        m_pairingReply = nullptr;
        handleBrokerPairingPollReply(reply);
        reply->deleteLater();
    });
}

void NowPlayingService::handleBrokerPairingPollReply(QNetworkReply *reply)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    const QJsonDocument document = QJsonDocument::fromJson(payload);
    const QJsonObject root = document.object();
    const QString status = root.value(QStringLiteral("status")).toString().trimmed().toLower();

    if (statusCode == 202 || status == QLatin1String("pending")) {
        setSpotifyPairingState(true,
                               QStringLiteral("Waiting for approval"),
                               m_pairingUrl,
                               m_pairingCode,
                               m_pairingQrRows);
        return;
    }

    if (statusCode == 401) {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify broker denied"));
        return;
    }

    if (status == QLatin1String("denied")) {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify pairing denied"));
        return;
    }

    if (statusCode == 404 || statusCode == 410) {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify pairing expired"));
        return;
    }

    if (reply->error() != QNetworkReply::NoError || statusCode != 200 || status != QLatin1String("ready")) {
        if (status == QLatin1String("failed")) {
            stopPairingServer();
            setSpotifyPairingState(false, QStringLiteral("Spotify pairing failed"));
        }
        return;
    }

    const QString accessToken = root.value(QStringLiteral("access_token")).toString().trimmed();
    const QString refreshToken = root.value(QStringLiteral("refresh_token")).toString().trimmed();
    const QString clientId = root.value(QStringLiteral("client_id")).toString().trimmed();
    if (accessToken.isEmpty() || refreshToken.isEmpty()) {
        stopPairingServer();
        setSpotifyPairingState(false, QStringLiteral("Spotify token missing"));
        return;
    }

    m_spotifyAccessToken = accessToken;
    m_spotifyRefreshToken = refreshToken;
    if (!clientId.isEmpty()) {
        m_spotifyClientId = clientId;
    }
    const int expiresIn = qMax(300, root.value(QStringLiteral("expires_in")).toInt(3600));
    m_spotifyAccessTokenExpiresAt = QDateTime::currentDateTimeUtc().addSecs(expiresIn);

    QString error;
    if (!persistSpotifyRefreshToken(&error)) {
        stopPairingServer();
        setSpotifyPairingState(false,
                               error.isEmpty() ? QStringLiteral("Spotify save failed") : error);
        return;
    }

    stopPairingServer();
    setSpotifyPairingState(false, QStringLiteral("Spotify paired"));
    refreshSpotifyPlayback();
}

void NowPlayingService::setSpotifyPairingState(bool active,
                                               const QString &status,
                                               const QString &url,
                                               const QString &code,
                                               const QStringList &qrRows)
{
    if (m_pairingActive == active
        && m_pairingStatus == status
        && m_pairingUrl == url
        && m_pairingCode == code
        && m_pairingQrRows == qrRows) {
        return;
    }

    m_pairingActive = active;
    m_pairingStatus = status;
    m_pairingUrl = url;
    m_pairingCode = code;
    m_pairingQrRows = qrRows;
    emit spotifyPairingChanged();
}

void NowPlayingService::setSpotifySaveState(bool pending,
                                            const QString &status,
                                            const QString &detail,
                                            int clearAfterMs)
{
    if (m_spotifySavePending == pending
        && m_spotifySaveStatus == status
        && m_spotifySaveDetail == detail) {
        return;
    }

    m_spotifySavePending = pending;
    m_spotifySaveStatus = status;
    m_spotifySaveDetail = detail;
    writeStateSnapshot();
    emit spotifySaveChanged();

    if (clearAfterMs > 0 && !status.isEmpty()) {
        const QString expectedStatus = status;
        QTimer::singleShot(clearAfterMs, this, [this, expectedStatus]() {
            if (!m_spotifySavePending && m_spotifySaveStatus == expectedStatus) {
                setSpotifySaveState(false, QString(), QString());
            }
        });
    }
}

void NowPlayingService::setSpotifyTrackSavedState(bool known, bool saved, const QString &trackId)
{
    const QString effectiveTrackId = known ? (trackId.isEmpty() ? m_spotifyCurrentTrackId : trackId)
                                           : QString();
    const bool effectiveSaved = known && saved;
    if (m_spotifyTrackSavedKnown == known
        && m_spotifyTrackSaved == effectiveSaved
        && m_spotifySavedStateTrackId == effectiveTrackId) {
        return;
    }

    m_spotifyTrackSavedKnown = known;
    m_spotifyTrackSaved = effectiveSaved;
    m_spotifySavedStateTrackId = effectiveTrackId;
    writeStateSnapshot();
    emit spotifySaveChanged();
}

void NowPlayingService::handlePairingConnection()
{
    while (m_pairingServer.hasPendingConnections()) {
        QTcpSocket *socket = m_pairingServer.nextPendingConnection();
        socket->setParent(this);
        connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
            const QByteArray request = socket->readAll();
            if (request.contains("\r\n\r\n") || request.contains("\n\n")) {
                handlePairingRequest(request, socket);
            }
        });
        connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
    }
}

void NowPlayingService::handlePairingRequest(const QByteArray &request, QTcpSocket *socket)
{
    const QString target = requestPath(request);
    if (target == QStringLiteral("/spotify/pair/") + m_pairingCode) {
        redirectHttp(socket, m_pairingAuthorizeUrl);
        return;
    }

    const QUrl url(QStringLiteral("http://beagley.local") + target);
    if (url.path() == QLatin1String("/spotify/callback")) {
        const QUrlQuery query(url);
        const QString state = query.queryItemValue(QStringLiteral("state"));
        const QString error = query.queryItemValue(QStringLiteral("error"));
        const QString code = query.queryItemValue(QStringLiteral("code"));
        if (state != m_pairingState) {
            writeHttp(socket, 400, QByteArrayLiteral("Bad Request"),
                      QByteArrayLiteral("<html><body>Spotify pairing state mismatch.</body></html>"));
            setSpotifyPairingState(false, QStringLiteral("Spotify pairing mismatch"));
            stopPairingServer();
            return;
        }
        if (!error.isEmpty()) {
            writeHttp(socket, 400, QByteArrayLiteral("Bad Request"),
                      QByteArrayLiteral("<html><body>Spotify pairing denied.</body></html>"));
            setSpotifyPairingState(false, QStringLiteral("Spotify pairing denied"));
            stopPairingServer();
            return;
        }
        if (code.isEmpty()) {
            writeHttp(socket, 400, QByteArrayLiteral("Bad Request"),
                      QByteArrayLiteral("<html><body>Spotify pairing code missing.</body></html>"));
            setSpotifyPairingState(false, QStringLiteral("Spotify pairing failed"));
            stopPairingServer();
            return;
        }

        writeHttp(socket, 200, QByteArrayLiteral("OK"),
                  QByteArrayLiteral("<html><body>Spotify is paired. You can return to the cluster.</body></html>"));
        setSpotifyPairingState(true, QStringLiteral("Saving Spotify login"), m_pairingUrl, m_pairingCode, m_pairingQrRows);
        exchangeSpotifyPairingCode(code);
        return;
    }

    writeHttp(socket, 404, QByteArrayLiteral("Not Found"),
              QByteArrayLiteral("<html><body>Spotify pairing link not found.</body></html>"));
}

void NowPlayingService::exchangeSpotifyPairingCode(const QString &code)
{
    if (m_pairingReply) {
        return;
    }

    QNetworkRequest request(QUrl(QString::fromLatin1(kSpotifyTokenUrl)));
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/x-www-form-urlencoded"));
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");

    QUrlQuery form;
    form.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("authorization_code"));
    form.addQueryItem(QStringLiteral("code"), code);
    form.addQueryItem(QStringLiteral("redirect_uri"), m_pairingRedirectUri);
    form.addQueryItem(QStringLiteral("client_id"), m_spotifyClientId);
    form.addQueryItem(QStringLiteral("code_verifier"), m_pairingCodeVerifier);

    m_pairingReply = m_network.post(request, form.query(QUrl::FullyEncoded).toUtf8());
    connect(m_pairingReply, &QNetworkReply::finished, this, [this]() {
        QNetworkReply *reply = m_pairingReply;
        m_pairingReply = nullptr;
        handleSpotifyPairingTokenReply(reply);
        reply->deleteLater();
    });
}

void NowPlayingService::handleSpotifyPairingTokenReply(QNetworkReply *reply)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
    if (reply->error() != QNetworkReply::NoError || statusCode != 200) {
        setSpotifyPairingState(false, QStringLiteral("Spotify token exchange failed"));
        stopPairingServer();
        return;
    }

    const QJsonDocument document = QJsonDocument::fromJson(payload);
    const QJsonObject root = document.object();
    const QString accessToken = root.value(QStringLiteral("access_token")).toString().trimmed();
    const QString refreshToken = root.value(QStringLiteral("refresh_token")).toString().trimmed();
    if (accessToken.isEmpty() || refreshToken.isEmpty()) {
        setSpotifyPairingState(false, QStringLiteral("Spotify token missing"));
        stopPairingServer();
        return;
    }

    m_spotifyAccessToken = accessToken;
    m_spotifyRefreshToken = refreshToken;
    const int expiresIn = qMax(300, root.value(QStringLiteral("expires_in")).toInt(3600));
    m_spotifyAccessTokenExpiresAt = QDateTime::currentDateTimeUtc().addSecs(expiresIn);

    QString error;
    if (!persistSpotifyRefreshToken(&error)) {
        setSpotifyPairingState(false,
                               error.isEmpty() ? QStringLiteral("Spotify save failed") : error);
        stopPairingServer();
        return;
    }

    stopPairingServer();
    setSpotifyPairingState(false, QStringLiteral("Spotify paired"));
    refreshSpotifyPlayback();
}

bool NowPlayingService::persistSpotifyRefreshToken(QString *errorOut) const
{
    const QString envPath = envString("BEAGLEY_CLUSTER_LOCAL_ENV");
    const QString path = envPath.isEmpty()
        ? QStringLiteral("/etc/default/beagley-cluster.local")
        : envPath;
    QFile file(path);
    QStringList lines;
    if (file.exists()) {
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            if (errorOut) {
                *errorOut = QStringLiteral("Spotify save denied");
            }
            return false;
        }
        const QString content = QString::fromUtf8(file.readAll());
        file.close();
        lines = content.split(QLatin1Char('\n'));
    }

    QStringList kept;
    for (const QString &line : lines) {
        const QString key = line.section(QLatin1Char('='), 0, 0).trimmed();
        if (key == QLatin1String("BEAGLEY_SPOTIFY_REFRESH_TOKEN")
            || key == QLatin1String("BEAGLEY_SPOTIFY_ACCESS_TOKEN")
            || key == QLatin1String("BEAGLEY_SPOTIFY_REDIRECT_URI")
            || key == QLatin1String("BEAGLEY_SPOTIFY_PAIRING_BASE_URL")
            || key == QLatin1String("BEAGLEY_SPOTIFY_CALLBACK_HOST")
            || key == QLatin1String("BEAGLEY_SPOTIFY_CALLBACK_PORT")
            || key == QLatin1String("BEAGLEY_SPOTIFY_PAIRING_AUTOSTART")) {
            continue;
        }
        if (!line.isEmpty()) {
            kept << line;
        }
    }
    kept << QStringLiteral("BEAGLEY_SPOTIFY_REFRESH_TOKEN=%1").arg(m_spotifyRefreshToken);

    QSaveFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (errorOut) {
            *errorOut = QStringLiteral("Spotify save denied");
        }
        return false;
    }
    out.write(kept.join(QLatin1Char('\n')).toUtf8());
    out.write("\n");
    if (!out.commit()) {
        if (errorOut) {
            *errorOut = QStringLiteral("Spotify save failed");
        }
        return false;
    }
    QFile::setPermissions(path, QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return true;
}

void NowPlayingService::finishProcess(QProcess *process, bool commandFailed, const QString &fallbackDetail)
{
    if (!process || process != m_process) {
        return;
    }

    m_timeoutTimer.stop();
    m_process = nullptr;

    const int exitCode = process->exitCode();
    const QString stdOut = QString::fromUtf8(process->readAllStandardOutput()).trimmed();
    const QString stdErr = QString::fromUtf8(process->readAllStandardError()).trimmed();
    process->deleteLater();

    if (commandFailed || exitCode != 0) {
        const QString detail = !fallbackDetail.isEmpty()
            ? fallbackDetail
            : (!stdErr.isEmpty() ? stdErr : sourceLabel() + QStringLiteral(" not available"));
        const QString lowerDetail = detail.toLower();
        const QString status = lowerDetail.contains(QStringLiteral("not authorized"))
                || lowerDetail.contains(QStringLiteral("not authorised"))
            ? QStringLiteral("PERMISSION")
            : QStringLiteral("OFFLINE");
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      status,
                      detail);
        return;
    }

    const QStringList lines = stdOut.split(QLatin1Char('\n'));
    const QString rawStatus = cleanedLine(lines, 0);
    const QString statusLower = rawStatus.toLower();
    const QString title = cleanedLine(lines, 1);
    const QString artist = cleanedLine(lines, 2);
    const QString album = cleanedLine(lines, 3);

    const bool playing = statusLower == QStringLiteral("playing");
    const bool paused = statusLower == QStringLiteral("paused");
    const bool available = playing || paused || !title.isEmpty() || !artist.isEmpty();
    const QString status = playing
        ? QStringLiteral("PLAYING")
        : (paused ? QStringLiteral("PAUSED") : QStringLiteral("OFFLINE"));
    const QString detail = available
        ? sourceLabel() + QStringLiteral(" local player")
        : sourceLabel() + QStringLiteral(" not playing");

    setNowPlaying(available,
                  playing,
                  sourceLabel(),
                  title,
                  artist,
                  album,
                  status,
                  detail);
}

void NowPlayingService::setNowPlaying(bool available,
                                      bool playing,
                                      const QString &source,
                                      const QString &title,
                                      const QString &artist,
                                      const QString &album,
                                      const QString &status,
                                      const QString &statusDetail)
{
    m_lastStateUpdatedAt = QDateTime::currentDateTimeUtc();
    if (m_available == available
        && m_playing == playing
        && m_source == source
        && m_title == title
        && m_artist == artist
        && m_album == album
        && m_status == status
        && m_statusDetail == statusDetail) {
        writeStateSnapshot();
        return;
    }

    m_available = available;
    m_playing = playing;
    m_source = source;
    m_title = title;
    m_artist = artist;
    m_album = album;
    m_status = status;
    m_statusDetail = statusDetail;
    writeStateSnapshot();
    emit nowPlayingChanged();
}

void NowPlayingService::writeStateSnapshot() const
{
    if (m_statePath.isEmpty()) {
        return;
    }

    const QFileInfo stateInfo(m_statePath);
    QDir stateDir(stateInfo.absolutePath());
    if (!stateDir.exists() && !stateDir.mkpath(QStringLiteral("."))) {
        return;
    }

    const QDateTime updatedAt = m_lastStateUpdatedAt.isValid()
        ? m_lastStateUpdatedAt
        : QDateTime::currentDateTimeUtc();

    QJsonObject object;
    object.insert(QStringLiteral("schema_version"), 1);
    object.insert(QStringLiteral("backend"), backendName(m_backend));
    object.insert(QStringLiteral("state"), normalizedState(m_available, m_playing, m_status, m_statusDetail));
    object.insert(QStringLiteral("source"), m_source);
    object.insert(QStringLiteral("available"), m_available);
    object.insert(QStringLiteral("playing"), m_playing);
    object.insert(QStringLiteral("title"), m_title);
    object.insert(QStringLiteral("artist"), m_artist);
    object.insert(QStringLiteral("album"), m_album);
    object.insert(QStringLiteral("track_id"), m_spotifyCurrentTrackId);
    object.insert(QStringLiteral("status"), m_status);
    object.insert(QStringLiteral("detail"), m_statusDetail);
    object.insert(QStringLiteral("playback_http_status"), m_lastPlaybackHttpStatus);
    object.insert(QStringLiteral("token_http_status"), m_lastTokenHttpStatus);
    object.insert(QStringLiteral("spotify_refresh_configured"), spotifyRefreshConfigured());
    object.insert(QStringLiteral("spotify_token_usable"), spotifyTokenUsable());
    object.insert(QStringLiteral("spotify_broker_configured"), spotifyBrokerConfigured());
    object.insert(QStringLiteral("spotify_save_supported"), spotifySaveSupported());
    object.insert(QStringLiteral("spotify_save_pending"), m_spotifySavePending);
    object.insert(QStringLiteral("spotify_track_saved_known"), spotifyTrackSavedKnown());
    object.insert(QStringLiteral("spotify_track_saved"), spotifyTrackSaved());
    object.insert(QStringLiteral("spotify_save_status"), m_spotifySaveStatus);
    object.insert(QStringLiteral("spotify_save_detail"), m_spotifySaveDetail);
    object.insert(QStringLiteral("error"), m_lastBackendError);
    object.insert(QStringLiteral("updated_utc"), updatedAt.toString(Qt::ISODateWithMs));
    object.insert(QStringLiteral("pid"), QString::number(QCoreApplication::applicationPid()));

    QSaveFile file(m_statePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return;
    }
    file.write(QJsonDocument(object).toJson(QJsonDocument::Compact));
    file.write("\n");
    if (file.commit()) {
        QFile::setPermissions(m_statePath,
                              QFileDevice::ReadOwner
                                  | QFileDevice::WriteOwner
                                  | QFileDevice::ReadGroup
                                  | QFileDevice::ReadOther);
    }
}
