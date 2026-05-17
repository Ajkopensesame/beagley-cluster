#pragma once

#include <QDateTime>
#include <QHash>
#include <QImage>
#include <QNetworkAccessManager>
#include <QObject>
#include <QList>
#include <QTimer>
#include <QUrl>

class QNetworkReply;

class RadarImageService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QUrl imageUrl READ imageUrl NOTIFY imageChanged)
    Q_PROPERTY(QUrl mapUrl READ mapUrl NOTIFY mapChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString frameTime READ frameTime NOTIFY frameTimeChanged)
    Q_PROPERTY(QString frameLabel READ frameLabel NOTIFY frameLabelChanged)
    Q_PROPERTY(int frameCount READ frameCount NOTIFY frameCountChanged)
    Q_PROPERTY(int frameIndex READ frameIndex NOTIFY frameIndexChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)

public:
    explicit RadarImageService(const QByteArray &userAgent, QObject *parent = nullptr);

    QUrl imageUrl() const { return m_imageUrl; }
    QUrl mapUrl() const { return m_mapUrl; }
    QString status() const { return m_status; }
    QString frameTime() const { return m_frameTime; }
    QString frameLabel() const { return m_frameLabel; }
    int frameCount() const { return m_animationFrames.size(); }
    int frameIndex() const { return m_animationIndex; }
    bool ready() const { return m_ready; }

    Q_INVOKABLE void setPosition(double lat, double lng, bool valid);
    Q_INVOKABLE void refresh();

signals:
    void imageChanged();
    void mapChanged();
    void statusChanged();
    void frameTimeChanged();
    void frameLabelChanged();
    void frameCountChanged();
    void frameIndexChanged();
    void readyChanged();

private:
    struct RadarTile {
        int dx = 0;
        int dy = 0;
        QImage mapImage;
        QImage radarImage;
        bool mapOk = false;
        bool radarOk = false;
    };

    struct CenterTile {
        bool valid = false;
        int col = 0;
        int row = 0;
        double fracX = 0.5;
        double fracY = 0.5;
    };

    struct RadarFrame {
        bool valid = false;
        QString host;
        QString path;
        qint64 epochSeconds = 0;
        int offsetMinutes = 0;
        bool nowcast = false;
    };

    struct ComposedFrame {
        RadarFrame frame;
        QUrl imageUrl;
        QUrl mapUrl;
        bool ready = false;
    };

    void requestTimeline();
    void handleTimelineReply(QNetworkReply *reply, int sequence);
    void startTimelineFetch(const QList<RadarFrame> &frames);
    void fetchNextTimelineFrame();
    void startTileFetch(const RadarFrame &frame);
    void handleTileReply(QNetworkReply *reply, int sequence, int dx, int dy);
    void handleMapTileReply(QNetworkReply *reply, int sequence, int dx, int dy);
    void finishTileFetch(int sequence);
    bool composeRadarImage(const QList<RadarTile> &tiles, const CenterTile &center, const RadarFrame &frame);
    void publishTimelineFrames();
    void advanceAnimationFrame();
    CenterTile centerTile() const;
    QUrl mapTileUrl(int row, int col) const;
    QUrl tileUrl(const RadarFrame &frame, int row, int col) const;
    QNetworkReply *get(const QUrl &url);
    QString compositeKey(const RadarFrame &frame, const CenterTile &center) const;
    QString compositePath(const RadarFrame &frame, const CenterTile &center) const;
    QString mapCompositePath(const RadarFrame &frame, const CenterTile &center) const;
    QString mapCompositePathForRadarPath(const QString &radarPath) const;
    QString latestMapCompositePath() const;
    bool tryPublishLatestCachedFrame(const QString &status);
    QList<RadarFrame> parseRadarFrames(const QByteArray &payload) const;
    QString formatFrameTime(qint64 epochSeconds) const;
    QString formatFrameLabel(const RadarFrame &frame) const;
    void setStatus(const QString &status);
    void setReady(bool ready);
    void setFrameTime(const QString &frameTime);
    void setFrameLabel(const QString &frameLabel);
    void setImageUrl(const QUrl &url);
    void setMapUrl(const QUrl &url);

    QNetworkAccessManager m_network;
    QTimer m_refreshTimer;
    QByteArray m_userAgent;
    QUrl m_imageUrl;
    QUrl m_mapUrl;
    QString m_status = QStringLiteral("SYNC");
    QString m_frameTime;
    QString m_frameLabel;
    QString m_cacheDirectory;
    RadarFrame m_frame;
    RadarFrame m_currentFrame;
    CenterTile m_currentCenter;
    double m_lat = 0.0;
    double m_lng = 0.0;
    bool m_positionValid = false;
    bool m_ready = false;
    bool m_inFlight = false;
    bool m_cachedBootstrap = false;
    int m_sequence = 0;
    int m_pendingTiles = 0;
    qint64 m_lastTimelineRequestMsecs = 0;
    QString m_lastCompositeKey;
    QString m_currentTimelineKey;
    QList<ComposedFrame> m_buildFrames;
    QList<ComposedFrame> m_animationFrames;
    QTimer m_animationTimer;
    int m_buildFrameIndex = -1;
    int m_animationIndex = -1;
    QHash<int, RadarTile> m_currentTiles;
};
