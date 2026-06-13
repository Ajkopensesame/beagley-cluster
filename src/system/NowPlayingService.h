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
    Q_PROPERTY(bool spotifySaveSupported READ spotifySaveSupported NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool spotifySavePending READ spotifySavePending NOTIFY spotifySaveChanged)
    Q_PROPERTY(bool spotifyTrackSaved READ spotifyTrackSaved NOTIFY spotifySaveChanged)
    Q_PROPERTY(bool spotifyTrackSavedKnown READ spotifyTrackSavedKnown NOTIFY spotifySaveChanged)
    Q_PROPERTY(QString spotifySaveStatus READ spotifySaveStatus NOTIFY spotifySaveChanged)
    Q_PROPERTY(QString spotifySaveDetail READ spotifySaveDetail NOTIFY spotifySaveChanged)

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
        Previous,
        RefreshSavedState,
        SaveCurrentTrack
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
    bool spotifySaveSupported() const;
    bool spotifySavePending() const { return m_spotifySavePending; }
    bool spotifyTrackSaved() const;
    bool spotifyTrackSavedKnown() const;
    QString spotifySaveStatus() const { return m_spotifySaveStatus; }
    QString spotifySaveDetail() const { return m_spotifySaveDetail; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void saveCurrentSpotifyTrack();
    Q_INVOKABLE void beginSpotifyPairing();
    Q_INVOKABLE void cancelSpotifyPairing();

signals:
    void nowPlayingChanged();
    void spotifyPairingChanged();
    void spotifySaveChanged();

private:
    QString sourceLabel() const;
    QStringList playerctlBaseArgs() const;
    void runControlCommand(const QString &action);
    void refreshPlayerctl();
    void refreshSpotifyPlayback(bool retriedAfterTokenRefresh = false);
    void refreshSpotifySavedState(bool retriedAfterTokenRefresh = false);
    void confirmSpotifySavedTrack(const QString &trackId, int attemptsRemaining = 4);
    void refreshSpotifyAccessToken();
    void runSpotifyAction(SpotifyAction action, bool retriedAfterTokenRefresh = false);
    bool spotifyBackendActive() const;
    bool spotifyTokenUsable() const;
    bool spotifyRefreshConfigured() const;
    void handleSpotifyPlaybackReply(QNetworkReply *reply, bool retriedAfterTokenRefresh);
    void handleSpotifyTokenReply(QNetworkReply *reply);
    void handleSpotifyControlReply(QNetworkReply *reply, SpotifyAction action, bool retriedAfterTokenRefresh);
    void handleSpotifySavedStateReply(QNetworkReply *reply,
                                      bool retriedAfterTokenRefresh,
                                      const QString &trackId);
    void exchangeSpotifyPairingCode(const QString &code);
    void handleSpotifyPairingTokenReply(QNetworkReply *reply);
    void beginBrokerSpotifyPairing();
    void pollBrokerSpotifyPairing();
    void handleBrokerPairingCreateReply(QNetworkReply *reply);
    void handleBrokerPairingPollReply(QNetworkReply *reply);
    void handlePairingConnection();
    void handlePairingRequest(const QByteArray &request, QTcpSocket *socket);
    void stopPairingServer();
    bool spotifyBrokerConfigured() const;
    void setSpotifyPairingState(bool active,
                                const QString &status,
                                const QString &url = QString(),
                                const QString &code = QString(),
                                const QStringList &qrRows = QStringList());
    void setSpotifySaveState(bool pending,
                             const QString &status,
                             const QString &detail = QString(),
                             int clearAfterMs = 0);
    void setSpotifyTrackSavedState(bool known, bool saved, const QString &trackId = QString());
    bool persistSpotifyRefreshToken(QString *errorOut = nullptr) const;
    void setSpotifyAuthRequired(const QString &detail);
    void autoStartSpotifyRepairPairing();
    void finishProcess(QProcess *process, bool commandFailed, const QString &fallbackDetail = QString());
    void setNowPlaying(bool available,
                       bool playing,
                       const QString &source,
                       const QString &title,
                       const QString &artist,
                       const QString &album,
                       const QString &status,
                       const QString &statusDetail);
    void writeStateSnapshot() const;

    QProcess *m_process = nullptr;
    QNetworkAccessManager m_network;
    QNetworkReply *m_networkReply = nullptr;
    QNetworkReply *m_pairingReply = nullptr;
    QTcpServer m_pairingServer;
    QTimer m_refreshTimer;
    QTimer m_timeoutTimer;
    QTimer m_pairingTimeoutTimer;
    QTimer m_brokerPairingPollTimer;
    Backend m_backend = Backend::Playerctl;
    SpotifyAction m_pendingSpotifyAction = SpotifyAction::None;
    QString m_playerName;
    QString m_spotifyAccessToken;
    QString m_spotifyRefreshToken;
    QString m_spotifyClientId;
    QString m_spotifyClientSecret;
    QString m_spotifyDeviceId;
    QString m_spotifyMarket;
    QString m_spotifyBrokerUrl;
    QString m_spotifyBrokerToken;
    QString m_spotifyCurrentTrackId;
    bool m_spotifySavePending = false;
    bool m_spotifyTrackSavedKnown = false;
    bool m_spotifyTrackSaved = false;
    QString m_spotifySavedStateTrackId;
    QString m_spotifySaveStatus;
    QString m_spotifySaveDetail;
    QString m_statePath;
    QDateTime m_spotifyAccessTokenExpiresAt;
    QDateTime m_lastStateUpdatedAt;
    int m_lastPlaybackHttpStatus = -1;
    int m_lastTokenHttpStatus = -1;
    QString m_lastBackendError;
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
