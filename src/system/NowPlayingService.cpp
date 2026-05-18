#include "NowPlayingService.h"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QProcessEnvironment>
#include <QTimer>
#include <QtGlobal>
#include <QUrlQuery>

namespace {

constexpr auto kSpotifyApiBase = "https://api.spotify.com/v1";
constexpr auto kSpotifyTokenUrl = "https://accounts.spotify.com/api/token";

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

bool envHasSpotifyCredentials()
{
    return !QString::fromUtf8(qgetenv("BEAGLEY_SPOTIFY_ACCESS_TOKEN")).trimmed().isEmpty()
        || !QString::fromUtf8(qgetenv("BEAGLEY_SPOTIFY_REFRESH_TOKEN")).trimmed().isEmpty();
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
    return envHasSpotifyCredentials() ? NowPlayingService::Backend::SpotifyWeb
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

    QTimer::singleShot(500, this, &NowPlayingService::refresh);
}

NowPlayingService::~NowPlayingService()
{
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
        runSpotifyAction(m_playing ? SpotifyAction::Pause : SpotifyAction::Play);
        return;
    }
    runControlCommand(QStringLiteral("play-pause"));
}

void NowPlayingService::next()
{
    if (spotifyBackendActive()) {
        runSpotifyAction(SpotifyAction::Next);
        return;
    }
    runControlCommand(QStringLiteral("next"));
}

void NowPlayingService::previous()
{
    if (spotifyBackendActive()) {
        runSpotifyAction(SpotifyAction::Previous);
        return;
    }
    runControlCommand(QStringLiteral("previous"));
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
    QNetworkRequest request(spotifyUrl(QStringLiteral("/me/player"), query));
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
    if (m_networkReply) {
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
    case SpotifyAction::None:
    case SpotifyAction::RefreshPlayback:
        return;
    }

    QUrlQuery query;
    if (!m_spotifyDeviceId.isEmpty()) {
        query.addQueryItem(QStringLiteral("device_id"), m_spotifyDeviceId);
    }
    QNetworkRequest request(spotifyUrl(path, query));
    request.setRawHeader("Authorization", "Bearer " + m_spotifyAccessToken.toUtf8());
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("User-Agent", "BeagleyCluster/1.0");
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));

    QNetworkReply *reply = nullptr;
    if (action == SpotifyAction::Play || action == SpotifyAction::Pause) {
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
        setNowPlaying(false,
                      false,
                      sourceLabel(),
                      QString(),
                      QString(),
                      QString(),
                      QStringLiteral("OFFLINE"),
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
    const QJsonObject device = root.value(QStringLiteral("device")).toObject();
    const QString deviceName = device.value(QStringLiteral("name")).toString().trimmed();
    const bool deviceActive = device.value(QStringLiteral("is_active")).toBool(false)
        || !deviceName.isEmpty();
    const bool deviceRestricted = device.value(QStringLiteral("is_restricted")).toBool(false);

    const QJsonObject item = root.value(QStringLiteral("item")).toObject();
    const QString itemType = item.value(QStringLiteral("type"))
                                 .toString(root.value(QStringLiteral("currently_playing_type")).toString());
    const QString title = item.value(QStringLiteral("name")).toString().trimmed();
    QString artist;
    QString album;
    if (itemType == QLatin1String("track")) {
        artist = spotifyArtists(item.value(QStringLiteral("artists")).toArray());
        album = item.value(QStringLiteral("album")).toObject().value(QStringLiteral("name")).toString().trimmed();
    } else if (itemType == QLatin1String("episode")) {
        const QJsonObject show = item.value(QStringLiteral("show")).toObject();
        artist = show.value(QStringLiteral("publisher")).toString().trimmed();
        album = show.value(QStringLiteral("name")).toString().trimmed();
    }

    const bool playing = root.value(QStringLiteral("is_playing")).toBool(false);
    const bool available = !title.isEmpty() || deviceActive;
    const QString status = playing
        ? QStringLiteral("PLAYING")
        : (!title.isEmpty() ? QStringLiteral("PAUSED")
                            : (deviceActive ? QStringLiteral("READY") : QStringLiteral("OFFLINE")));
    const QString detail = deviceRestricted
        ? QStringLiteral("Spotify device restricted")
        : (!deviceName.isEmpty() ? deviceName : QStringLiteral("Spotify Web API"));

    setNowPlaying(available,
                  playing,
                  sourceLabel(),
                  title,
                  artist,
                  album,
                  status,
                  detail);
}

void NowPlayingService::handleSpotifyTokenReply(QNetworkReply *reply)
{
    const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const QByteArray payload = reply->readAll();
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
    const int expiresIn = qMax(300, root.value(QStringLiteral("expires_in")).toInt(3600));
    m_spotifyAccessTokenExpiresAt = QDateTime::currentDateTimeUtc().addSecs(expiresIn);
    const QString refreshToken = root.value(QStringLiteral("refresh_token")).toString().trimmed();
    if (!refreshToken.isEmpty()) {
        m_spotifyRefreshToken = refreshToken;
    }

    const SpotifyAction pendingAction = m_pendingSpotifyAction;
    m_pendingSpotifyAction = SpotifyAction::None;
    if (pendingAction == SpotifyAction::None || pendingAction == SpotifyAction::RefreshPlayback) {
        refreshSpotifyPlayback(true);
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

    QTimer::singleShot(800, this, &NowPlayingService::refresh);
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
    if (m_available == available
        && m_playing == playing
        && m_source == source
        && m_title == title
        && m_artist == artist
        && m_album == album
        && m_status == status
        && m_statusDetail == statusDetail) {
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
    emit nowPlayingChanged();
}
