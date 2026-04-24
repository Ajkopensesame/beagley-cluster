#include "NowPlayingService.h"

#include <QByteArray>
#include <QProcessEnvironment>
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

} // namespace

NowPlayingService::NowPlayingService(QObject *parent)
    : QObject(parent)
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
        finishProcess(process, true, QStringLiteral("Spotify query timed out"));
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
            finishProcess(process, true, QStringLiteral("Spotify player command unavailable"));
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
    process->start(QStringLiteral("playerctl"),
                   { QStringLiteral("-p"),
                     QStringLiteral("spotify"),
                     QStringLiteral("metadata"),
                     QStringLiteral("--format"),
                     QStringLiteral("{{status}}\n{{title}}\n{{artist}}\n{{album}}") });
#endif
    m_timeoutTimer.start();
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
            : (!stdErr.isEmpty() ? stdErr : QStringLiteral("Spotify not available"));
        const QString lowerDetail = detail.toLower();
        const QString status = lowerDetail.contains(QStringLiteral("not authorized"))
                || lowerDetail.contains(QStringLiteral("not authorised"))
            ? QStringLiteral("PERMISSION")
            : QStringLiteral("OFFLINE");
        setNowPlaying(false,
                      false,
                      QStringLiteral("Spotify"),
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
        ? QStringLiteral("Spotify local player")
        : QStringLiteral("Spotify not playing");

    setNowPlaying(available,
                  playing,
                  QStringLiteral("Spotify"),
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
