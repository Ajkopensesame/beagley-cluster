#include "RadarImageService.h"

#include <QCryptographicHash>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QImageReader>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QStandardPaths>
#include <QStringList>
#include <QTimeZone>
#include <QUrl>

#include <algorithm>
#include <cmath>

namespace {
constexpr auto kTimelineUrl = "http://api.rainviewer.com/public/weather-maps.json";
constexpr auto kDefaultTileHost = "https://tilecache.rainviewer.com";
constexpr int kTileZoom = 7;
constexpr int kTileSize = 256;
constexpr int kOutputWidth = 768;
constexpr int kOutputHeight = 512;
constexpr int kTileDrawSize = 256;
constexpr int kTileRadius = 1;
constexpr int kTileSpan = (kTileRadius * 2) + 1;
constexpr int kRefreshIntervalMs = 60 * 1000;
constexpr int kAnimationFrameIntervalMs = 850;
constexpr int kNetworkTimeoutMs = 15000;
constexpr int kTileColorScheme = 2;
constexpr auto kTileOptions = "1_1";
constexpr int kPastFramesWithNowcast = 1;
constexpr int kPastFramesFallback = 1;
constexpr int kNowcastFrames = 0;
constexpr auto kRadarFrameCachePrefix = "radar-map-v3-radar";
constexpr auto kRadarUnderlayCachePrefix = "radar-map-v3-map";
constexpr auto kDarkRadarFrameCachePrefix = "radar-map-v2-radar";
constexpr auto kCombinedRadarMapCachePrefix = "radar-map-v1";
constexpr auto kLegacyRadarCachePrefix = "radar-basic-v2";

bool coordValid(double value, double minValue, double maxValue)
{
    return std::isfinite(value) && value >= minValue && value <= maxValue;
}

double clampLatitude(double latitude)
{
    return qBound(-85.05112878, latitude, 85.05112878);
}

int wrapTileX(int x, int tilesPerAxis)
{
    if (tilesPerAxis <= 0) {
        return 0;
    }
    const int wrapped = x % tilesPerAxis;
    return wrapped < 0 ? wrapped + tilesPerAxis : wrapped;
}

double webMercatorTileX(double lng, int zoom)
{
    const double tilesPerAxis = double(1 << zoom);
    return (lng + 180.0) / 360.0 * tilesPerAxis;
}

double webMercatorTileY(double lat, int zoom)
{
    const double clamped = clampLatitude(lat);
    const double sinLat = std::sin(clamped * M_PI / 180.0);
    const double tilesPerAxis = double(1 << zoom);
    return (0.5 - std::log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * M_PI)) * tilesPerAxis;
}

QString normalizedHost(QString host)
{
    host = host.trimmed();
    if (host.isEmpty()) {
        host = QString::fromLatin1(kDefaultTileHost);
    }
    while (host.endsWith(QLatin1Char('/'))) {
        host.chop(1);
    }
    if (host == QLatin1String("https://tilecache.rainviewer.com")) {
        return QStringLiteral("http://tilecache.rainviewer.com");
    }
    return host;
}

QString normalizedPath(QString path)
{
    path = path.trimmed();
    if (!path.startsWith(QLatin1Char('/'))) {
        path.prepend(QLatin1Char('/'));
    }
    return path;
}

qint64 jsonEpochSeconds(const QJsonValue &value)
{
    if (value.isDouble()) {
        return static_cast<qint64>(value.toDouble());
    }
    if (value.isString()) {
        bool ok = false;
        const qint64 parsed = value.toString().toLongLong(&ok);
        return ok ? parsed : 0;
    }
    return 0;
}

} // namespace

RadarImageService::RadarImageService(const QByteArray &userAgent, QObject *parent)
    : QObject(parent)
    , m_userAgent(userAgent.isEmpty() ? QByteArrayLiteral("BeagleyCluster/1.0") : userAgent)
{
#ifdef Q_OS_LINUX
    m_cacheDirectory = QStringLiteral("/var/volatile/beagley-cluster/radar");
#else
    m_cacheDirectory = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/radar");
#endif
    if (m_cacheDirectory.trimmed().isEmpty()) {
        m_cacheDirectory = QStringLiteral("/tmp/beagley-radar");
    }
    if (!QDir().mkpath(m_cacheDirectory)) {
        m_cacheDirectory = QStringLiteral("/tmp/beagley-radar");
        QDir().mkpath(m_cacheDirectory);
    }
    qInfo().noquote() << "[RadarImage] cache directory" << m_cacheDirectory;

    auto *diskCache = new QNetworkDiskCache(&m_network);
    const QString httpCacheDirectory = QDir(m_cacheDirectory).filePath(QStringLiteral("http-cache"));
    QDir().mkpath(httpCacheDirectory);
    diskCache->setCacheDirectory(httpCacheDirectory);
    diskCache->setMaximumCacheSize(96 * 1024 * 1024);
    m_network.setCache(diskCache);

    m_refreshTimer.setInterval(kRefreshIntervalMs);
    m_refreshTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_refreshTimer, &QTimer::timeout, this, &RadarImageService::refresh);

    m_animationTimer.setInterval(kAnimationFrameIntervalMs);
    m_animationTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_animationTimer, &QTimer::timeout, this, &RadarImageService::advanceAnimationFrame);
}

void RadarImageService::setPosition(double lat, double lng, bool valid)
{
    const bool normalizedValid = valid && coordValid(lat, -90.0, 90.0) && coordValid(lng, -180.0, 180.0);
    const bool moved = !qFuzzyCompare(m_lat, lat) || !qFuzzyCompare(m_lng, lng);
    if (m_positionValid == normalizedValid && (!normalizedValid || !moved)) {
        return;
    }

    m_lat = lat;
    m_lng = lng;
    m_positionValid = normalizedValid;

    if (!m_positionValid) {
        m_refreshTimer.stop();
        m_animationTimer.stop();
        m_frame = RadarFrame();
        m_currentFrame = RadarFrame();
        m_currentCenter = CenterTile();
        m_buildFrames.clear();
        m_animationFrames.clear();
        m_buildFrameIndex = -1;
        m_animationIndex = -1;
        m_cachedBootstrap = false;
        m_lastTimelineRequestMsecs = 0;
        m_lastCompositeKey.clear();
        m_currentTimelineKey.clear();
        setReady(false);
        setImageUrl(QUrl());
        setMapUrl(QUrl());
        setFrameTime(QString());
        setFrameLabel(QString());
        emit frameCountChanged();
        emit frameIndexChanged();
        setStatus(QStringLiteral("GPS WAIT"));
        return;
    }

    if (!m_refreshTimer.isActive()) {
        m_refreshTimer.start();
    }
    if (!m_ready) {
        tryPublishLatestCachedFrame(QStringLiteral("STALE"));
    }
    refresh();
}

void RadarImageService::refresh()
{
    if (!m_positionValid) {
        setReady(false);
        setStatus(QStringLiteral("GPS WAIT"));
        return;
    }
    if (m_inFlight) {
        return;
    }
    const qint64 nowMsecs = QDateTime::currentMSecsSinceEpoch();
    if (m_ready
        && !m_cachedBootstrap
        && m_lastTimelineRequestMsecs > 0
        && nowMsecs - m_lastTimelineRequestMsecs < kRefreshIntervalMs) {
        setStatus(QStringLiteral("LIVE"));
        return;
    }
    requestTimeline();
}

void RadarImageService::requestTimeline()
{
    m_inFlight = true;
    m_lastTimelineRequestMsecs = QDateTime::currentMSecsSinceEpoch();
    setStatus(m_ready ? QStringLiteral("LIVE") : QStringLiteral("SYNC"));

    const int sequence = ++m_sequence;
    QNetworkReply *reply = get(QUrl(QString::fromLatin1(kTimelineUrl)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, sequence]() {
        handleTimelineReply(reply, sequence);
    });
}

void RadarImageService::handleTimelineReply(QNetworkReply *reply, int sequence)
{
    if (sequence != m_sequence) {
        reply->deleteLater();
        return;
    }

    QList<RadarFrame> frames;
    if (reply->error() == QNetworkReply::NoError) {
        frames = parseRadarFrames(reply->readAll());
    } else {
        qWarning().noquote() << "[RadarImage] timeline fetch failed:" << reply->errorString();
    }
    reply->deleteLater();

    if (frames.isEmpty()) {
        m_inFlight = false;
        if (m_ready && m_imageUrl.isLocalFile() && QFileInfo::exists(m_imageUrl.toLocalFile())) {
            setStatus(QStringLiteral("STALE"));
            return;
        }
        if (tryPublishLatestCachedFrame(QStringLiteral("STALE"))) {
            return;
        }
        setReady(false);
        setStatus(QStringLiteral("OFFLINE"));
        return;
    }

    startTimelineFetch(frames);
}

void RadarImageService::startTimelineFetch(const QList<RadarFrame> &frames)
{
    const CenterTile center = centerTile();
    if (!center.valid) {
        m_inFlight = false;
        setReady(false);
        setStatus(QStringLiteral("NO TILE"));
        return;
    }

    const QString key = [&frames, &center, this]() {
        QStringList parts;
        parts.reserve(frames.size());
        for (const RadarFrame &frame : frames) {
            parts.append(compositeKey(frame, center));
        }
        return parts.join(QLatin1Char('|'));
    }();
    if (m_ready
        && key == m_lastCompositeKey
        && m_imageUrl.isLocalFile()
        && QFileInfo::exists(m_imageUrl.toLocalFile())) {
        m_inFlight = false;
        if (m_animationFrames.size() > 1 && !m_animationTimer.isActive()) {
            m_animationTimer.start();
        }
        setStatus(QStringLiteral("LIVE"));
        return;
    }

    m_currentCenter = center;
    m_buildFrames.clear();
    m_buildFrames.reserve(frames.size());
    for (const RadarFrame &frame : frames) {
        ComposedFrame composed;
        composed.frame = frame;
        const QString path = compositePath(frame, center);
        if (QFileInfo::exists(path)) {
            composed.imageUrl = QUrl::fromLocalFile(path);
            const QString mapPath = mapCompositePath(frame, center);
            if (QFileInfo::exists(mapPath)) {
                composed.mapUrl = QUrl::fromLocalFile(mapPath);
            }
            composed.ready = true;
        }
        m_buildFrames.append(composed);
    }
    m_buildFrameIndex = -1;
    m_currentTimelineKey = key;
    fetchNextTimelineFrame();
}

void RadarImageService::fetchNextTimelineFrame()
{
    for (int i = 0; i < m_buildFrames.size(); ++i) {
        if (!m_buildFrames.at(i).ready) {
            m_buildFrameIndex = i;
            startTileFetch(m_buildFrames.at(i).frame);
            return;
        }
    }
    publishTimelineFrames();
}

void RadarImageService::startTileFetch(const RadarFrame &frame)
{
    const CenterTile center = m_currentCenter.valid ? m_currentCenter : centerTile();
    if (!center.valid) {
        m_inFlight = false;
        setReady(false);
        setStatus(QStringLiteral("NO TILE"));
        return;
    }

    m_currentFrame = frame;
    m_currentTiles.clear();
    m_pendingTiles = 0;

    const int sequence = ++m_sequence;
    const int tilesPerAxis = 1 << kTileZoom;
    for (int dy = -kTileRadius; dy <= kTileRadius; ++dy) {
        for (int dx = -kTileRadius; dx <= kTileRadius; ++dx) {
            const int col = wrapTileX(center.col + dx, tilesPerAxis);
            const int row = center.row + dy;
            if (row < 0 || row >= tilesPerAxis) {
                continue;
            }
            const int tileKey = (dy + kTileRadius) * kTileSpan + (dx + kTileRadius);
            RadarTile tile;
            tile.dx = dx;
            tile.dy = dy;
            m_currentTiles.insert(tileKey, tile);

            ++m_pendingTiles;
            QNetworkReply *mapReply = get(mapTileUrl(row, col));
            connect(mapReply, &QNetworkReply::finished, this, [this, mapReply, sequence, dx, dy]() {
                handleMapTileReply(mapReply, sequence, dx, dy);
            });

            ++m_pendingTiles;
            QNetworkReply *radarReply = get(tileUrl(m_currentFrame, row, col));
            connect(radarReply, &QNetworkReply::finished, this, [this, radarReply, sequence, dx, dy]() {
                handleTileReply(radarReply, sequence, dx, dy);
            });
        }
    }

    if (m_pendingTiles == 0) {
        m_inFlight = false;
        setReady(false);
        setStatus(QStringLiteral("NO TILE"));
    }
}

void RadarImageService::handleTileReply(QNetworkReply *reply, int sequence, int dx, int dy)
{
    if (sequence != m_sequence) {
        reply->deleteLater();
        return;
    }

    const int tileKey = (dy + kTileRadius) * kTileSpan + (dx + kTileRadius);
    RadarTile tile = m_currentTiles.value(tileKey);
    tile.dx = dx;
    tile.dy = dy;
    if (reply->error() == QNetworkReply::NoError) {
        QImage image;
        const bool ok = image.loadFromData(reply->readAll());
        tile.radarOk = ok;
        tile.radarImage = image;
    } else {
        qWarning().noquote() << "[RadarImage] radar tile fetch failed:" << reply->errorString();
    }
    reply->deleteLater();

    m_currentTiles.insert(tileKey, tile);
    --m_pendingTiles;
    if (m_pendingTiles <= 0) {
        finishTileFetch(sequence);
    }
}

void RadarImageService::handleMapTileReply(QNetworkReply *reply, int sequence, int dx, int dy)
{
    if (sequence != m_sequence) {
        reply->deleteLater();
        return;
    }

    const int tileKey = (dy + kTileRadius) * kTileSpan + (dx + kTileRadius);
    RadarTile tile = m_currentTiles.value(tileKey);
    tile.dx = dx;
    tile.dy = dy;
    if (reply->error() == QNetworkReply::NoError) {
        QImage image;
        const bool ok = image.loadFromData(reply->readAll());
        tile.mapOk = ok;
        tile.mapImage = image;
    } else {
        qWarning().noquote() << "[RadarImage] map tile fetch failed:" << reply->errorString();
    }
    reply->deleteLater();

    m_currentTiles.insert(tileKey, tile);
    --m_pendingTiles;
    if (m_pendingTiles <= 0) {
        finishTileFetch(sequence);
    }
}

void RadarImageService::finishTileFetch(int sequence)
{
    if (sequence != m_sequence) {
        return;
    }

    QList<RadarTile> tiles = m_currentTiles.values();
    bool anyRadarOk = false;
    for (const RadarTile &tile : tiles) {
        anyRadarOk = anyRadarOk || tile.radarOk;
    }

    if (!anyRadarOk) {
        qWarning().noquote() << "[RadarImage] all radar tile fetches failed";
        if (m_ready && m_imageUrl.isLocalFile() && QFileInfo::exists(m_imageUrl.toLocalFile())) {
            m_inFlight = false;
            setStatus(QStringLiteral("STALE"));
            return;
        }
        if (tryPublishLatestCachedFrame(QStringLiteral("STALE"))) {
            m_inFlight = false;
            return;
        }
        m_inFlight = false;
        setReady(false);
        setStatus(QStringLiteral("OFFLINE"));
        return;
    }

    if (composeRadarImage(tiles, m_currentCenter.valid ? m_currentCenter : centerTile(), m_currentFrame)) {
        if (m_buildFrameIndex >= 0 && m_buildFrameIndex < m_buildFrames.size()) {
            m_buildFrames[m_buildFrameIndex].imageUrl = QUrl::fromLocalFile(compositePath(m_currentFrame, m_currentCenter));
            m_buildFrames[m_buildFrameIndex].mapUrl = QUrl::fromLocalFile(mapCompositePath(m_currentFrame, m_currentCenter));
            m_buildFrames[m_buildFrameIndex].ready = true;
        }
        fetchNextTimelineFrame();
        return;
    }

    qWarning().noquote() << "[RadarImage] failed to compose radar image";
    m_inFlight = false;
    if (m_ready && m_imageUrl.isLocalFile() && QFileInfo::exists(m_imageUrl.toLocalFile())) {
        setStatus(QStringLiteral("STALE"));
    } else {
        setReady(false);
        setStatus(QStringLiteral("OFFLINE"));
    }
}

bool RadarImageService::composeRadarImage(const QList<RadarTile> &tiles,
                                          const CenterTile &center,
                                          const RadarFrame &frame)
{
    if (!center.valid || !frame.valid) {
        return false;
    }

    QImage mapOutput(QSize(kOutputWidth, kOutputHeight), QImage::Format_ARGB32_Premultiplied);
    mapOutput.fill(QColor(229, 232, 229));

    QPainter painter(&mapOutput);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setCompositionMode(QPainter::CompositionMode_SourceOver);

    const double centerTileLeft = kOutputWidth / 2.0 - center.fracX * kTileDrawSize;
    const double centerTileTop = kOutputHeight / 2.0 - center.fracY * kTileDrawSize;
    for (const RadarTile &tile : tiles) {
        if (!tile.mapOk || tile.mapImage.isNull()) {
            continue;
        }
        const QRectF target(centerTileLeft + tile.dx * kTileDrawSize,
                            centerTileTop + tile.dy * kTileDrawSize,
                            kTileDrawSize,
                            kTileDrawSize);
        painter.drawImage(target, tile.mapImage);
    }
    painter.fillRect(mapOutput.rect(), QColor(2, 4, 10, 16));
    painter.end();

    QImage radarOutput(QSize(kOutputWidth, kOutputHeight), QImage::Format_ARGB32_Premultiplied);
    radarOutput.fill(Qt::transparent);

    QPainter radarPainter(&radarOutput);
    radarPainter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    radarPainter.setCompositionMode(QPainter::CompositionMode_SourceOver);
    for (const RadarTile &tile : tiles) {
        if (!tile.radarOk || tile.radarImage.isNull()) {
            continue;
        }
        const QRectF target(centerTileLeft + tile.dx * kTileDrawSize,
                            centerTileTop + tile.dy * kTileDrawSize,
                            kTileDrawSize,
                            kTileDrawSize);
        radarPainter.drawImage(target, tile.radarImage);
    }
    radarPainter.end();

    const QString filePath = compositePath(frame, center);
    if (!radarOutput.save(filePath, "PNG")) {
        qWarning().noquote() << "[RadarImage] failed to write" << filePath;
        return false;
    }
    const QString mapPath = mapCompositePath(frame, center);
    if (!mapOutput.save(mapPath, "PNG")) {
        qWarning().noquote() << "[RadarImage] failed to write" << mapPath;
        return false;
    }

    qInfo().noquote() << "[RadarImage] composed" << filePath
                      << "mapPath" << mapPath
                      << "frame" << frame.path
                      << "time" << formatFrameTime(frame.epochSeconds)
                      << "label" << formatFrameLabel(frame)
                      << "tile" << center.row << center.col
                      << "layers" << tiles.size()
                      << "map" << std::any_of(tiles.cbegin(), tiles.cend(), [](const RadarTile &tile) {
                             return tile.mapOk;
                         });
    return true;
}

void RadarImageService::publishTimelineFrames()
{
    QList<ComposedFrame> frames;
    frames.reserve(m_buildFrames.size());
    for (const ComposedFrame &frame : m_buildFrames) {
        if (frame.ready && frame.imageUrl.isLocalFile() && QFileInfo::exists(frame.imageUrl.toLocalFile())) {
            frames.append(frame);
        }
    }

    m_inFlight = false;
    if (frames.isEmpty()) {
        if (m_ready && m_imageUrl.isLocalFile() && QFileInfo::exists(m_imageUrl.toLocalFile())) {
            setStatus(QStringLiteral("STALE"));
            return;
        }
        setReady(false);
        setStatus(QStringLiteral("OFFLINE"));
        return;
    }

    const int previousCount = m_animationFrames.size();
    m_animationFrames = frames;
    if (previousCount != m_animationFrames.size()) {
        emit frameCountChanged();
    }

    m_frame = m_animationFrames.last().frame;
    m_cachedBootstrap = false;
    m_lastCompositeKey = m_currentTimelineKey;
    if (m_animationIndex < 0 || m_animationIndex >= m_animationFrames.size()) {
        m_animationIndex = -1;
    }
    setReady(true);
    setStatus(QStringLiteral("LIVE"));
    advanceAnimationFrame();
    if (m_animationFrames.size() > 1 && !m_animationTimer.isActive()) {
        m_animationTimer.start();
    } else if (m_animationFrames.size() <= 1) {
        m_animationTimer.stop();
    }
    qInfo().noquote() << "[RadarImage] timeline ready"
                      << "frames" << m_animationFrames.size()
                      << "current" << formatFrameTime(m_frame.epochSeconds);
}

void RadarImageService::advanceAnimationFrame()
{
    if (m_animationFrames.isEmpty()) {
        m_animationTimer.stop();
        setReady(false);
        setMapUrl(QUrl());
        return;
    }

    const int nextIndex = (m_animationIndex + 1) % m_animationFrames.size();
    if (m_animationIndex != nextIndex) {
        m_animationIndex = nextIndex;
        emit frameIndexChanged();
    }

    const ComposedFrame &frame = m_animationFrames.at(m_animationIndex);
    setImageUrl(frame.imageUrl);
    setMapUrl(frame.mapUrl);
    setFrameTime(formatFrameTime(frame.frame.epochSeconds));
    setFrameLabel(formatFrameLabel(frame.frame));
    setReady(true);
    if (m_status != QLatin1String("LIVE")) {
        setStatus(QStringLiteral("LIVE"));
    }
}

RadarImageService::CenterTile RadarImageService::centerTile() const
{
    CenterTile center;
    if (!m_positionValid) {
        return center;
    }

    const int tilesPerAxis = 1 << kTileZoom;
    const double x = webMercatorTileX(m_lng, kTileZoom);
    const double y = webMercatorTileY(m_lat, kTileZoom);
    const int colFloor = static_cast<int>(std::floor(x));
    center.col = wrapTileX(colFloor, tilesPerAxis);
    center.row = static_cast<int>(std::floor(y));
    center.fracX = x - std::floor(x);
    center.fracY = y - std::floor(y);
    center.valid = center.row >= 0 && center.row < tilesPerAxis;
    return center;
}

QUrl RadarImageService::mapTileUrl(int row, int col) const
{
    const int tilesPerAxis = 1 << kTileZoom;
    const QString urlText = QStringLiteral("https://a.basemaps.cartocdn.com/light_nolabels/%1/%2/%3.png")
        .arg(QString::number(kTileZoom),
             QString::number(wrapTileX(col, tilesPerAxis)),
             QString::number(row));
    return QUrl(urlText);
}

QUrl RadarImageService::tileUrl(const RadarFrame &frame, int row, int col) const
{
    const int tilesPerAxis = 1 << kTileZoom;
    const QString urlText = QStringLiteral("%1%2/256/%3/%4/%5/%6/%7.png")
        .arg(normalizedHost(frame.host),
             normalizedPath(frame.path),
             QString::number(kTileZoom),
             QString::number(wrapTileX(col, tilesPerAxis)),
             QString::number(row),
             QString::number(kTileColorScheme),
             QString::fromLatin1(kTileOptions));
    return QUrl(urlText);
}

QNetworkReply *RadarImageService::get(const QUrl &url)
{
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", m_userAgent);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
    request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, true);
    request.setTransferTimeout(kNetworkTimeoutMs);
    return m_network.get(request);
}

QString RadarImageService::compositeKey(const RadarFrame &frame, const CenterTile &center) const
{
    return QStringLiteral("%1:%2:%3").arg(frame.path).arg(center.row).arg(center.col);
}

QString RadarImageService::compositePath(const RadarFrame &frame, const CenterTile &center) const
{
    const QByteArray key = QStringLiteral("%1:%2:%3:%4:%5")
        .arg(QString::number(kTileZoom),
             QString::number(center.row),
             QString::number(center.col),
             frame.path,
             QString::number(frame.epochSeconds))
        .append(QLatin1String(":radar-map-v3"))
        .toUtf8();
    const QString digest = QString::fromLatin1(
        QCryptographicHash::hash(key, QCryptographicHash::Sha1).toHex().left(16));
    return QDir(m_cacheDirectory).filePath(QStringLiteral("%1-%2.png")
                                               .arg(QString::fromLatin1(kRadarFrameCachePrefix), digest));
}

QString RadarImageService::mapCompositePath(const RadarFrame &frame, const CenterTile &center) const
{
    const QString radarPath = compositePath(frame, center);
    return mapCompositePathForRadarPath(radarPath);
}

QString RadarImageService::mapCompositePathForRadarPath(const QString &radarPath) const
{
    const QFileInfo info(radarPath);
    const QString fileName = info.fileName();
    if (!fileName.startsWith(QLatin1String(kRadarFrameCachePrefix))) {
        return QString();
    }
    const QString suffix = fileName.mid(QString::fromLatin1(kRadarFrameCachePrefix).size());
    return QDir(m_cacheDirectory).filePath(QString::fromLatin1(kRadarUnderlayCachePrefix) + suffix);
}

bool RadarImageService::tryPublishLatestCachedFrame(const QString &status)
{
    QDir dir(m_cacheDirectory);
    const QFileInfoList candidates = dir.entryInfoList({
                                                           QStringLiteral("%1-*.png")
                                                               .arg(QString::fromLatin1(kRadarFrameCachePrefix)),
                                                           QStringLiteral("%1-*.png")
                                                               .arg(QString::fromLatin1(kDarkRadarFrameCachePrefix)),
                                                           QStringLiteral("%1-*.png")
                                                               .arg(QString::fromLatin1(kCombinedRadarMapCachePrefix)),
                                                           QStringLiteral("%1-*.png")
                                                               .arg(QString::fromLatin1(kLegacyRadarCachePrefix)),
                                                       },
                                                       QDir::Files | QDir::Readable,
                                                       QDir::Time);
    for (const QFileInfo &info : candidates) {
        if (info.size() <= 0) {
            continue;
        }

        QImageReader reader(info.absoluteFilePath());
        if (!reader.canRead() || !reader.size().isValid()) {
            continue;
        }

        const int previousCount = m_animationFrames.size();
        m_animationFrames.clear();
        if (previousCount != 0) {
            emit frameCountChanged();
        }
        m_animationIndex = -1;
        emit frameIndexChanged();
        m_cachedBootstrap = true;
        setImageUrl(QUrl::fromLocalFile(info.absoluteFilePath()));
        const QString mapPath = mapCompositePathForRadarPath(info.absoluteFilePath());
        setMapUrl(!mapPath.isEmpty() && QFileInfo::exists(mapPath) ? QUrl::fromLocalFile(mapPath) : QUrl());
        setFrameTime(info.lastModified().toLocalTime().toString(QStringLiteral("HH:mm")));
        setFrameLabel(QStringLiteral("CACHE"));
        setReady(true);
        setStatus(status);
        qInfo().noquote() << "[RadarImage] cached bootstrap" << info.absoluteFilePath()
                          << reader.size().width() << "x" << reader.size().height();
        return true;
    }
    return false;
}

QList<RadarImageService::RadarFrame> RadarImageService::parseRadarFrames(const QByteArray &payload) const
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(payload, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qWarning().noquote() << "[RadarImage] timeline parse failed:" << error.errorString();
        return {};
    }

    const QJsonObject root = document.object();
    const QJsonObject radar = root.value(QStringLiteral("radar")).toObject();
    const QJsonArray past = radar.value(QStringLiteral("past")).toArray();
    if (past.isEmpty()) {
        qWarning().noquote() << "[RadarImage] timeline has no past radar frames";
        return {};
    }

    const QString host = root.value(QStringLiteral("host")).toString(QString::fromLatin1(kDefaultTileHost));
    const auto readFrame = [&host](const QJsonObject &object, bool nowcast) {
        RadarFrame frame;
        frame.host = host;
        frame.path = object.value(QStringLiteral("path")).toString();
        frame.epochSeconds = jsonEpochSeconds(object.value(QStringLiteral("time")));
        frame.nowcast = nowcast;
        frame.valid = !frame.path.trimmed().isEmpty() && frame.epochSeconds > 0;
        return frame;
    };

    QList<RadarFrame> pastFrames;
    pastFrames.reserve(past.size());
    for (const QJsonValue &value : past) {
        const RadarFrame frame = readFrame(value.toObject(), false);
        if (frame.valid) {
            pastFrames.append(frame);
        }
    }
    if (pastFrames.isEmpty()) {
        qWarning().noquote() << "[RadarImage] timeline has no valid past radar frames";
        return {};
    }

    QList<RadarFrame> nowcastFrames;
    const QJsonArray nowcast = radar.value(QStringLiteral("nowcast")).toArray();
    nowcastFrames.reserve(nowcast.size());
    for (const QJsonValue &value : nowcast) {
        const RadarFrame frame = readFrame(value.toObject(), true);
        if (frame.valid) {
            nowcastFrames.append(frame);
        }
    }

    const qint64 latestPastEpoch = pastFrames.last().epochSeconds;
    QList<RadarFrame> selected;
    const int pastFrameCount = nowcastFrames.isEmpty()
        ? qMin(kPastFramesFallback, pastFrames.size())
        : qMin(kPastFramesWithNowcast, pastFrames.size());
    const int firstPastIndex = qMax(0, pastFrames.size() - pastFrameCount);
    for (int i = firstPastIndex; i < pastFrames.size(); ++i) {
        RadarFrame frame = pastFrames.at(i);
        frame.offsetMinutes = int(std::llround(double(frame.epochSeconds - latestPastEpoch) / 60.0));
        selected.append(frame);
    }

    for (int i = 0; i < qMin(kNowcastFrames, nowcastFrames.size()); ++i) {
        RadarFrame frame = nowcastFrames.at(i);
        frame.offsetMinutes = int(std::llround(double(frame.epochSeconds - latestPastEpoch) / 60.0));
        bool duplicate = false;
        for (const RadarFrame &existing : selected) {
            if (existing.path == frame.path || existing.epochSeconds == frame.epochSeconds) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) {
            selected.append(frame);
        }
    }

    qInfo().noquote() << "[RadarImage] timeline selected"
                      << selected.size()
                      << "past" << pastFrames.size()
                      << "nowcast" << nowcastFrames.size();
    return selected;
}

QString RadarImageService::formatFrameTime(qint64 epochSeconds) const
{
    if (epochSeconds <= 0) {
        return QStringLiteral("--:--");
    }
    const QDateTime date = QDateTime::fromSecsSinceEpoch(epochSeconds, QTimeZone::UTC);
    if (!date.isValid()) {
        return QStringLiteral("--:--");
    }
    return date.toLocalTime().toString(QStringLiteral("HH:mm"));
}

QString RadarImageService::formatFrameLabel(const RadarFrame &frame) const
{
    if (!frame.valid) {
        return QString();
    }
    if (frame.offsetMinutes == 0) {
        return QStringLiteral("NOW");
    }
    if (frame.offsetMinutes > 0) {
        return QStringLiteral("+%1 MIN").arg(frame.offsetMinutes);
    }
    return QStringLiteral("%1 MIN").arg(frame.offsetMinutes);
}

void RadarImageService::setStatus(const QString &status)
{
    if (m_status == status) {
        return;
    }
    m_status = status;
    emit statusChanged();
}

void RadarImageService::setReady(bool ready)
{
    if (m_ready == ready) {
        return;
    }
    m_ready = ready;
    emit readyChanged();
}

void RadarImageService::setFrameTime(const QString &frameTime)
{
    if (m_frameTime == frameTime) {
        return;
    }
    m_frameTime = frameTime;
    emit frameTimeChanged();
}

void RadarImageService::setFrameLabel(const QString &frameLabel)
{
    if (m_frameLabel == frameLabel) {
        return;
    }
    m_frameLabel = frameLabel;
    emit frameLabelChanged();
}

void RadarImageService::setImageUrl(const QUrl &url)
{
    if (m_imageUrl == url) {
        return;
    }
    m_imageUrl = url;
    emit imageChanged();
}

void RadarImageService::setMapUrl(const QUrl &url)
{
    if (m_mapUrl == url) {
        return;
    }
    m_mapUrl = url;
    emit mapChanged();
}
