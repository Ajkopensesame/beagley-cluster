#pragma once

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

signals:
    void nowPlayingChanged();

private:
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
    QTimer m_refreshTimer;
    QTimer m_timeoutTimer;
    bool m_available = false;
    bool m_playing = false;
    QString m_source = QStringLiteral("Spotify");
    QString m_title;
    QString m_artist;
    QString m_album;
    QString m_status = QStringLiteral("OFFLINE");
    QString m_statusDetail = QStringLiteral("Spotify not connected");
};
