#pragma once

#include <QDateTime>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QProcess>
#include <QTimer>

class NowPlayingService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool available READ available NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString source READ source NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString title READ title NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString album READ album NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString status READ status NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString statusDetail READ statusDetail NOTIFY nowPlayingChanged)

public:
    enum class Backend {
        Playerctl,
        SpotifyWeb
    };

    enum class SpotifyAction {
        None,
        RefreshPlayback,
        Play,
        Pause,
        Next,
        Previous
    };

    explicit NowPlayingService(QObject *parent = nullptr);
    ~NowPlayingService() override;

    bool available() const { return m_available; }
    bool playing() const { return m_playing; }
    QString source() const { return m_source; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString album() const { return m_album; }
    QString status() const { return m_status; }
    QString statusDetail() const { return m_statusDetail; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

signals:
    void nowPlayingChanged();

private:
    QString sourceLabel() const;
    QStringList playerctlBaseArgs() const;
    void runControlCommand(const QString &action);
    void refreshPlayerctl();
    void refreshSpotifyPlayback(bool retriedAfterTokenRefresh = false);
    void refreshSpotifyAccessToken();
    void runSpotifyAction(SpotifyAction action, bool retriedAfterTokenRefresh = false);
    bool spotifyBackendActive() const;
    bool spotifyTokenUsable() const;
    bool spotifyRefreshConfigured() const;
    void handleSpotifyPlaybackReply(QNetworkReply *reply, bool retriedAfterTokenRefresh);
    void handleSpotifyTokenReply(QNetworkReply *reply);
    void handleSpotifyControlReply(QNetworkReply *reply, SpotifyAction action, bool retriedAfterTokenRefresh);
    void setSpotifyAuthRequired(const QString &detail);
    void finishProcess(QProcess *process, bool commandFailed, const QString &fallbackDetail = QString());
    void setNowPlaying(bool available,
                       bool playing,
                       const QString &source,
                       const QString &title,
                       const QString &artist,
                       const QString &album,
                       const QString &status,
                       const QString &statusDetail);

    QProcess *m_process = nullptr;
    QNetworkAccessManager m_network;
    QNetworkReply *m_networkReply = nullptr;
    QTimer m_refreshTimer;
    QTimer m_timeoutTimer;
    Backend m_backend = Backend::Playerctl;
    SpotifyAction m_pendingSpotifyAction = SpotifyAction::None;
    QString m_playerName;
    QString m_spotifyAccessToken;
    QString m_spotifyRefreshToken;
    QString m_spotifyClientId;
    QString m_spotifyClientSecret;
    QString m_spotifyDeviceId;
    QString m_spotifyMarket;
    QDateTime m_spotifyAccessTokenExpiresAt;
    bool m_available = false;
    bool m_playing = false;
    QString m_source;
    QString m_title;
    QString m_artist;
    QString m_album;
    QString m_status = QStringLiteral("OFFLINE");
    QString m_statusDetail = QStringLiteral("Media not connected");
};
