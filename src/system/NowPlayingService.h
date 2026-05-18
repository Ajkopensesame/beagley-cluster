#pragma once

#include <QDateTime>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTcpServer>
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
    Q_PROPERTY(bool controlsSupported READ controlsSupported CONSTANT)
    Q_PROPERTY(bool spotifyPairingSupported READ spotifyPairingSupported NOTIFY spotifyPairingChanged)
    Q_PROPERTY(bool spotifyPairingActive READ spotifyPairingActive NOTIFY spotifyPairingChanged)
    Q_PROPERTY(QString spotifyPairingStatus READ spotifyPairingStatus NOTIFY spotifyPairingChanged)
    Q_PROPERTY(QString spotifyPairingUrl READ spotifyPairingUrl NOTIFY spotifyPairingChanged)
    Q_PROPERTY(QString spotifyPairingCode READ spotifyPairingCode NOTIFY spotifyPairingChanged)
    Q_PROPERTY(QStringList spotifyPairingQrRows READ spotifyPairingQrRows NOTIFY spotifyPairingChanged)
    Q_PROPERTY(QString spotifyPairingQrPattern READ spotifyPairingQrPattern NOTIFY spotifyPairingChanged)

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
    bool controlsSupported() const { return m_backend != Backend::SpotifyWeb; }
    bool spotifyPairingSupported() const;
    bool spotifyPairingActive() const { return m_pairingActive; }
    QString spotifyPairingStatus() const { return m_pairingStatus; }
    QString spotifyPairingUrl() const { return m_pairingUrl; }
    QString spotifyPairingCode() const { return m_pairingCode; }
    QStringList spotifyPairingQrRows() const { return m_pairingQrRows; }
    QString spotifyPairingQrPattern() const { return m_pairingQrRows.join(QLatin1Char('\n')); }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void beginSpotifyPairing();
    Q_INVOKABLE void cancelSpotifyPairing();

signals:
    void nowPlayingChanged();
    void spotifyPairingChanged();

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
    void exchangeSpotifyPairingCode(const QString &code);
    void handleSpotifyPairingTokenReply(QNetworkReply *reply);
    void handlePairingConnection();
    void handlePairingRequest(const QByteArray &request, QTcpSocket *socket);
    void stopPairingServer();
    void setSpotifyPairingState(bool active,
                                const QString &status,
                                const QString &url = QString(),
                                const QString &code = QString(),
                                const QStringList &qrRows = QStringList());
    bool persistSpotifyRefreshToken(QString *errorOut = nullptr) const;
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
    QNetworkReply *m_pairingReply = nullptr;
    QTcpServer m_pairingServer;
    QTimer m_refreshTimer;
    QTimer m_timeoutTimer;
    QTimer m_pairingTimeoutTimer;
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
    bool m_pairingActive = false;
    QString m_pairingStatus;
    QString m_pairingUrl;
    QString m_pairingCode;
    QString m_pairingState;
    QString m_pairingCodeVerifier;
    QString m_pairingRedirectUri;
    QString m_pairingAuthorizeUrl;
    QStringList m_pairingQrRows;
    bool m_available = false;
    bool m_playing = false;
    QString m_source;
    QString m_title;
    QString m_artist;
    QString m_album;
    QString m_status = QStringLiteral("OFFLINE");
    QString m_statusDetail = QStringLiteral("Media not connected");
};
