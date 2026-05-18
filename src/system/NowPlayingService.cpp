#include "NowPlayingService.h"

#include <QByteArray>
#include <QProcessEnvironment>
#include <QTimer>
#include <QtGlobal>

namespace {

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

} // namespace

NowPlayingService::NowPlayingService(QObject *parent)
    : QObject(parent)
    , m_playerName(configuredPlayerName())
    , m_source(sourceLabel())
{
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
    if (!m_process) {
        return;
    }
    m_process->kill();
    m_process->deleteLater();
    m_process = nullptr;
}

void NowPlayingService::refresh()
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
    runControlCommand(QStringLiteral("play-pause"));
}

void NowPlayingService::next()
{
    runControlCommand(QStringLiteral("next"));
}

void NowPlayingService::previous()
{
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
