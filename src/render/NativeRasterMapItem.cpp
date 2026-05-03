#include "NativeRasterMapItem.h"

#include <QDir>
#include <QMatrix4x4>
#include <QMetaObject>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QSGTransformNode>
#include <QStandardPaths>
#include <QUrl>
#include <QPainter>
#include <QVector>

#include <QtMath>

#include <cmath>

namespace {
constexpr int kTileSizePx = 256;
constexpr qreal kRouteCullDistancePx = 3.0;
constexpr qreal kTileRefreshStepPx = 96.0;

double normalizeBearing(double bearing)
{
    double normalized = std::fmod(bearing, 360.0);
    if (normalized < 0.0) {
        normalized += 360.0;
    }
    return normalized;
}

double bearingDeltaDegrees(double current, double target)
{
    double delta = std::fmod(target - current, 360.0);
    if (delta > 180.0) {
        delta -= 360.0;
    } else if (delta < -180.0) {
        delta += 360.0;
    }
    return delta;
}

QPointF rotatePoint(const QPointF &point, double degrees)
{
    const double radians = qDegreesToRadians(degrees);
    const double cosA = qCos(radians);
    const double sinA = qSin(radians);
    return QPointF(point.x() * cosA - point.y() * sinA,
                   point.x() * sinA + point.y() * cosA);
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

class MapSceneRoot final : public QSGNode
{
public:
    MapSceneRoot()
    {
        mapNode = new QSGSimpleTextureNode;
        appendChildNode(mapNode);

        mapTransformNode = new QSGTransformNode;
        appendChildNode(mapTransformNode);

        tileRoot = new QSGNode;
        mapTransformNode->appendChildNode(tileRoot);

        routeNode = new QSGGeometryNode;
        auto *routeGeometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
        routeGeometry->setDrawingMode(QSGGeometry::DrawLineStrip);
        routeGeometry->setLineWidth(5.0f);
        routeNode->setGeometry(routeGeometry);
        routeNode->setFlag(QSGNode::OwnsGeometry);
        auto *routeMaterial = new QSGFlatColorMaterial;
        routeMaterial->setColor(QColor(0x4C, 0xD9, 0xFF, 220));
        routeNode->setMaterial(routeMaterial);
        routeNode->setFlag(QSGNode::OwnsMaterial);
        appendChildNode(routeNode);

        vehicleNode = new QSGGeometryNode;
        auto *vehicleGeometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 3);
        vehicleGeometry->setDrawingMode(QSGGeometry::DrawTriangles);
        vehicleNode->setGeometry(vehicleGeometry);
        vehicleNode->setFlag(QSGNode::OwnsGeometry);
        auto *vehicleMaterial = new QSGFlatColorMaterial;
        vehicleMaterial->setColor(QColor(0xFF, 0xB0, 0x3B));
        vehicleNode->setMaterial(vehicleMaterial);
        vehicleNode->setFlag(QSGNode::OwnsMaterial);
        appendChildNode(vehicleNode);
    }

    QSGSimpleTextureNode *mapNode = nullptr;
    QSGTransformNode *mapTransformNode = nullptr;
    QSGNode *tileRoot = nullptr;
    QHash<QString, QSGSimpleTextureNode *> tileNodes;
    QSGGeometryNode *routeNode = nullptr;
    QSGGeometryNode *vehicleNode = nullptr;
};
} // namespace

NativeRasterMapItem::NativeRasterMapItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    m_cacheDirectory = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
        + QStringLiteral("/native-online-map");
}

NativeRasterMapItem::~NativeRasterMapItem()
{
    qDeleteAll(m_textures);
}

void NativeRasterMapItem::setCenterLat(double value)
{
    if (qFuzzyCompare(m_centerLat, value)) {
        return;
    }
    m_centerLat = value;
    if (m_componentReady) {
        scheduleTileRefresh();
    }
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setCenterLng(double value)
{
    if (qFuzzyCompare(m_centerLng, value)) {
        return;
    }
    m_centerLng = value;
    if (m_componentReady) {
        scheduleTileRefresh();
    }
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setMapBearing(double value)
{
    const double normalized = normalizeBearing(value);
    if (qAbs(bearingDeltaDegrees(m_mapBearing, normalized)) < 0.05) {
        return;
    }
    m_mapBearing = normalized;
    if (m_componentReady) {
        scheduleTileRefresh();
    }
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setZoom(double value)
{
    if (qFuzzyCompare(m_zoom, value)) {
        return;
    }
    m_zoom = qBound(1.0, value, 19.0);
    if (m_componentReady) {
        scheduleTileRefresh();
    }
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setVehicleLat(double value)
{
    if (qFuzzyCompare(m_vehicleLat, value)) {
        return;
    }
    m_vehicleLat = value;
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setVehicleLng(double value)
{
    if (qFuzzyCompare(m_vehicleLng, value)) {
        return;
    }
    m_vehicleLng = value;
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setVehicleBearing(double value)
{
    const double normalized = normalizeBearing(value);
    if (qAbs(bearingDeltaDegrees(m_vehicleBearing, normalized)) < 0.05) {
        return;
    }
    m_vehicleBearing = normalized;
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setVehicleVisible(bool value)
{
    if (m_vehicleVisible == value) {
        return;
    }
    m_vehicleVisible = value;
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setRoutePath(const QVariantList &path)
{
    if (m_routePath == path) {
        return;
    }
    m_routePath = path;
    recordCounter(QStringLiteral("map.routeRebuild"));
    emit routePathChanged();
    update();
}

void NativeRasterMapItem::setTileUrlTemplate(const QString &value)
{
    if (m_tileUrlTemplate == value) {
        return;
    }
    m_tileUrlTemplate = value;
    invalidateTileState();
    emit tileUrlTemplateChanged();
    update();
}

void NativeRasterMapItem::setUserAgent(const QString &value)
{
    if (m_userAgent == value) {
        return;
    }
    m_userAgent = value;
    emit userAgentChanged();
}

void NativeRasterMapItem::setCacheDirectory(const QString &value)
{
    if (m_cacheDirectory == value) {
        return;
    }
    m_cacheDirectory = value;
    if (m_componentReady) {
        ensureNetwork();
        scheduleTileRefresh();
    }
    emit cacheDirectoryChanged();
}

void NativeRasterMapItem::setMetrics(QObject *metricsObject)
{
    if (m_metrics == metricsObject) {
        return;
    }
    m_metrics = metricsObject;
    emit metricsChanged();
}

void NativeRasterMapItem::componentComplete()
{
    QQuickItem::componentComplete();
    m_componentReady = true;
    ensureNetwork();
    scheduleTileRefresh();
    update();
}

void NativeRasterMapItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!m_componentReady || newGeometry.size() == oldGeometry.size()) {
        return;
    }
    scheduleTileRefresh();
    update();
}

void NativeRasterMapItem::updatePolish()
{
    if (!m_componentReady || !m_tileRefreshPending) {
        return;
    }
    m_tileRefreshPending = false;
    updateVisibleTiles();
}

void NativeRasterMapItem::ensureNetwork()
{
    if (m_network) {
        return;
    }

    m_network = new QNetworkAccessManager(this);
    auto *diskCache = new QNetworkDiskCache(m_network);
    QDir().mkpath(m_cacheDirectory);
    diskCache->setCacheDirectory(m_cacheDirectory);
    diskCache->setMaximumCacheSize(512 * 1024 * 1024);
    m_network->setCache(diskCache);
}

QList<NativeRasterMapItem::VisibleTile> NativeRasterMapItem::visibleTiles() const
{
    QList<VisibleTile> tiles;
    const int z = qRound(m_zoom);
    const int tilesPerAxis = 1 << z;
    const QPointF centerWorld = projectToWorld(m_centerLat, m_centerLng, z);
    const QPointF viewportCenter(width() / 2.0, height() / 2.0);

    QVector<QPointF> worldCorners;
    worldCorners.reserve(4);
    const QPointF screenCorners[] = {
        QPointF(0.0, 0.0),
        QPointF(width(), 0.0),
        QPointF(width(), height()),
        QPointF(0.0, height()),
    };
    for (const QPointF &corner : screenCorners) {
        worldCorners.append(centerWorld + rotatePoint(corner - viewportCenter, m_mapBearing));
    }

    double minWorldX = worldCorners.first().x();
    double maxWorldX = minWorldX;
    double minWorldY = worldCorners.first().y();
    double maxWorldY = minWorldY;
    for (const QPointF &corner : worldCorners) {
        minWorldX = qMin(minWorldX, corner.x());
        maxWorldX = qMax(maxWorldX, corner.x());
        minWorldY = qMin(minWorldY, corner.y());
        maxWorldY = qMax(maxWorldY, corner.y());
    }

    const int minTileX = int(std::floor(minWorldX / kTileSizePx)) - 1;
    const int minTileY = int(std::floor(minWorldY / kTileSizePx)) - 1;
    const int maxTileX = int(std::ceil(maxWorldX / kTileSizePx)) + 1;
    const int maxTileY = int(std::ceil(maxWorldY / kTileSizePx)) + 1;

    for (int tileY = minTileY; tileY <= maxTileY; ++tileY) {
        if (tileY < 0 || tileY >= tilesPerAxis) {
            continue;
        }
        for (int tileX = minTileX; tileX <= maxTileX; ++tileX) {
            const int wrappedX = wrapTileX(tileX, tilesPerAxis);
            VisibleTile tile;
            tile.z = z;
            tile.x = wrappedX;
            tile.y = tileY;
            tile.key = tileKey(z, wrappedX, tileY);
            tile.rect = QRectF(tileX * kTileSizePx,
                               tileY * kTileSizePx,
                               kTileSizePx,
                               kTileSizePx);
            tiles.append(tile);
        }
    }

    return tiles;
}

QPointF NativeRasterMapItem::projectToWorld(double lat, double lng, double zoomLevel) const
{
    const double latClamped = clampLatitude(lat);
    const double sinLat = qSin(qDegreesToRadians(latClamped));
    const double scale = kTileSizePx * qPow(2.0, zoomLevel);
    const double x = (lng + 180.0) / 360.0 * scale;
    const double y = (0.5 - qLn((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * M_PI)) * scale;
    return QPointF(x, y);
}

QPointF NativeRasterMapItem::projectToScreen(double lat,
                                             double lng,
                                             double zoomLevel,
                                             const QPointF &centerWorld) const
{
    const QPointF deltaWorld = projectToWorld(lat, lng, zoomLevel) - centerWorld;
    const QPointF deltaScreen = rotatePoint(deltaWorld, -m_mapBearing);
    return QPointF(width() / 2.0, height() / 2.0) + deltaScreen;
}

QString NativeRasterMapItem::tileKey(int z, int x, int y) const
{
    return QStringLiteral("%1/%2/%3").arg(z).arg(x).arg(y);
}

void NativeRasterMapItem::requestTile(int z, int x, int y)
{
    ensureNetwork();
    const QString key = tileKey(z, x, y);

    {
        QMutexLocker locker(&m_tileMutex);
        if (m_tileImages.contains(key) || m_pendingTiles.contains(key)) {
            return;
        }
        m_pendingTiles.insert(key);
    }

    QString urlText = m_tileUrlTemplate;
    urlText.replace(QStringLiteral("{z}"), QString::number(z));
    urlText.replace(QStringLiteral("{x}"), QString::number(x));
    urlText.replace(QStringLiteral("{y}"), QString::number(y));

    QNetworkRequest request{QUrl(urlText)};
    request.setRawHeader("User-Agent", m_userAgent.toUtf8());
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
    request.setAttribute(QNetworkRequest::CacheSaveControlAttribute, true);

    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, key]() {
        reply->deleteLater();

        QImage image;
        if (reply->error() == QNetworkReply::NoError) {
            image.loadFromData(reply->readAll());
        }

        {
            QMutexLocker locker(&m_tileMutex);
            m_pendingTiles.remove(key);
            if (!image.isNull()) {
                m_tileImages.insert(key, image);
                m_dirtyTextures.insert(key);
            }
        }

        if (!image.isNull()) {
            update();
        }
    });
}

void NativeRasterMapItem::updateVisibleTiles()
{
    const int z = qRound(m_zoom);
    const QSize viewSize(qMax(1, int(width())), qMax(1, int(height())));
    const QPointF centerWorld = projectToWorld(m_centerLat, m_centerLng, z);
    const QPointF topLeftWorld = centerWorld;
    const QPointF topLeftDelta = topLeftWorld - m_lastTileRefreshTopLeftWorld;
    const bool cameraMovedEnough = !m_haveTileRefreshState
        || qAbs(topLeftDelta.x()) >= kTileRefreshStepPx
        || qAbs(topLeftDelta.y()) >= kTileRefreshStepPx;
    const bool bearingMovedEnough = !m_haveTileRefreshState
        || qAbs(bearingDeltaDegrees(m_lastTileRefreshBearing, m_mapBearing)) >= 2.0;
    const bool refreshVisibleSet = !m_haveTileRefreshState
        || m_lastTileRefreshSize != viewSize
        || m_lastTileRefreshZoom != z
        || cameraMovedEnough
        || bearingMovedEnough;
    if (!refreshVisibleSet) {
        return;
    }

    m_lastTileRefreshSize = viewSize;
    m_lastTileRefreshTopLeftWorld = topLeftWorld;
    m_lastTileRefreshZoom = z;
    m_lastTileRefreshBearing = m_mapBearing;
    m_haveTileRefreshState = true;

    m_visibleTiles = visibleTiles();
    for (const VisibleTile &tile : m_visibleTiles) {
        requestTile(tile.z, tile.x, tile.y);
    }
    recordCounter(QStringLiteral("map.visibleTileSet"));
}

void NativeRasterMapItem::scheduleTileRefresh()
{
    if (!m_componentReady) {
        return;
    }
    if (!m_tileRefreshPending) {
        m_tileRefreshPending = true;
        polish();
    }
}

void NativeRasterMapItem::invalidateTileState()
{
    m_haveTileRefreshState = false;
    m_haveCompositeState = false;
    if (m_componentReady) {
        scheduleTileRefresh();
    }
}

void NativeRasterMapItem::recordCounter(const QString &bucket, int amount)
{
    if (!m_metrics) {
        return;
    }
    QMetaObject::invokeMethod(m_metrics,
                              "recordCounter",
                              Qt::AutoConnection,
                              Q_ARG(QString, bucket),
                              Q_ARG(int, amount));
}

QSGNode *NativeRasterMapItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    auto *root = oldNode ? static_cast<MapSceneRoot *>(oldNode) : new MapSceneRoot;

    const QList<VisibleTile> tiles = m_visibleTiles;
    QSet<QString> neededTextures;
    for (const VisibleTile &tile : tiles) {
        if (!m_textures.contains(tile.key)) {
            neededTextures.insert(tile.key);
        }
    }

    QHash<QString, QImage> visibleTileImages;
    QHash<QString, QImage> tileImagesToUpload;
    QSet<QString> dirtyTextures;
    {
        QMutexLocker locker(&m_tileMutex);
        dirtyTextures = m_dirtyTextures;
        for (const VisibleTile &tile : tiles) {
            const auto imageIt = m_tileImages.constFind(tile.key);
            if (imageIt != m_tileImages.constEnd() && !imageIt.value().isNull()) {
                visibleTileImages.insert(tile.key, imageIt.value());
            }
        }
        QSet<QString> uploadKeys = dirtyTextures;
        uploadKeys.unite(neededTextures);
        for (const QString &key : uploadKeys) {
            const auto imageIt = m_tileImages.constFind(key);
            if (imageIt != m_tileImages.constEnd() && !imageIt.value().isNull()) {
                tileImagesToUpload.insert(key, imageIt.value());
            }
        }
        m_dirtyTextures.clear();
    }

    const int z = qRound(m_zoom);
    const QPointF centerWorld = projectToWorld(m_centerLat, m_centerLng, z);
    if (window() && width() > 0 && height() > 0) {
        const QString textureMode = QString::fromUtf8(qgetenv("BEAGLEY_NATIVE_MAP_TEXTURE_MODE"))
            .trimmed()
            .toLower();
        const bool useTileNodes = textureMode == QLatin1String("tiles");

        if (!useTileNodes) {
            const auto nodeKeys = root->tileNodes.keys();
            for (const QString &key : nodeKeys) {
                QSGSimpleTextureNode *tileNode = root->tileNodes.take(key);
                root->tileRoot->removeChildNode(tileNode);
                delete tileNode;
            }
            root->mapTransformNode->setMatrix(QMatrix4x4());

            const QSize compositeSize(qMax(1, int(width())), qMax(1, int(height())));
            const QPointF cameraDelta = centerWorld - m_lastCompositeTopLeftWorld;
            const bool cameraMovedEnough = !m_haveCompositeState
                || qAbs(cameraDelta.x()) >= 1.0
                || qAbs(cameraDelta.y()) >= 1.0;
            const bool bearingMovedEnough = !m_haveCompositeState
                || qAbs(bearingDeltaDegrees(m_lastCompositeBearing, m_mapBearing)) >= 0.25;
            const bool rebuildComposite = !m_textures.contains(QStringLiteral("__composite__"))
                || !m_haveCompositeState
                || m_lastCompositeSize != compositeSize
                || m_lastCompositeZoom != z
                || cameraMovedEnough
                || bearingMovedEnough
                || !dirtyTextures.isEmpty();

            if (rebuildComposite) {
                QImage composite(compositeSize, QImage::Format_ARGB32_Premultiplied);
                composite.fill(QColor(0x06, 0x11, 0x1D));

                QPainter painter(&composite);
                painter.setRenderHint(QPainter::SmoothPixmapTransform, false);
                painter.translate(width() / 2.0, height() / 2.0);
                painter.rotate(-m_mapBearing);
                painter.translate(-centerWorld.x(), -centerWorld.y());

                bool drewTile = false;
                for (const VisibleTile &tile : tiles) {
                    const QImage image = visibleTileImages.value(tile.key);
                    if (image.isNull()) {
                        continue;
                    }
                    painter.drawImage(tile.rect, image, image.rect());
                    drewTile = true;
                }
                painter.end();

                QSGTexture *oldTexture = m_textures.take(QStringLiteral("__composite__"));
                delete oldTexture;
                QSGTexture *texture = window()->createTextureFromImage(composite);
                if (texture) {
                    m_textures.insert(QStringLiteral("__composite__"), texture);
                    m_lastCompositeSize = compositeSize;
                    m_lastCompositeTopLeftWorld = centerWorld;
                    m_lastCompositeZoom = z;
                    m_lastCompositeBearing = m_mapBearing;
                    m_haveCompositeState = true;
                    if (drewTile) {
                        recordCounter(QStringLiteral("map.compositeUpload"));
                    }
                }
            }

            QSGTexture *texture = m_textures.value(QStringLiteral("__composite__"), nullptr);
            if (!texture) {
                root->mapNode->setRect(0, 0, width(), height());
            } else {
                root->mapNode->setOwnsTexture(false);
                root->mapNode->setTexture(texture);
                root->mapNode->setRect(0, 0, width(), height());
                root->mapNode->markDirty(QSGNode::DirtyGeometry);
                root->mapNode->markDirty(QSGNode::DirtyMaterial);
            }
        } else {
            root->mapNode->setRect(0, 0, 0, 0);

            int uploadedTileCount = 0;
            for (auto it = tileImagesToUpload.constBegin(); it != tileImagesToUpload.constEnd(); ++it) {
                QSGTexture *oldTexture = m_textures.take(it.key());
                delete oldTexture;

                QSGTexture *texture = window()->createTextureFromImage(it.value());
                if (texture) {
                    m_textures.insert(it.key(), texture);
                    ++uploadedTileCount;
                }
            }
            if (uploadedTileCount > 0) {
                recordCounter(QStringLiteral("map.tileUpload"), uploadedTileCount);
            }

            QMatrix4x4 mapMatrix;
            mapMatrix.translate(float(width() / 2.0), float(height() / 2.0));
            mapMatrix.rotate(float(-m_mapBearing), 0.0f, 0.0f, 1.0f);
            mapMatrix.translate(float(-centerWorld.x()), float(-centerWorld.y()));
            root->mapTransformNode->setMatrix(mapMatrix);

            QSet<QString> visibleTileKeys;
            visibleTileKeys.reserve(tiles.size());
            for (const VisibleTile &tile : tiles) {
                QSGTexture *texture = m_textures.value(tile.key, nullptr);
                if (!texture) {
                    continue;
                }
                visibleTileKeys.insert(tile.key);

                QSGSimpleTextureNode *tileNode = root->tileNodes.value(tile.key, nullptr);
                if (!tileNode) {
                    tileNode = new QSGSimpleTextureNode;
                    tileNode->setOwnsTexture(false);
                    tileNode->setFiltering(QSGTexture::Nearest);
                    root->tileRoot->appendChildNode(tileNode);
                    root->tileNodes.insert(tile.key, tileNode);
                }

                if (tileNode->texture() != texture) {
                    tileNode->setTexture(texture);
                    tileNode->markDirty(QSGNode::DirtyMaterial);
                }
                if (tileNode->rect() != tile.rect) {
                    tileNode->setRect(tile.rect);
                    tileNode->markDirty(QSGNode::DirtyGeometry);
                }
            }

            const auto nodeKeys = root->tileNodes.keys();
            for (const QString &key : nodeKeys) {
                if (visibleTileKeys.contains(key)) {
                    continue;
                }
                QSGSimpleTextureNode *tileNode = root->tileNodes.take(key);
                root->tileRoot->removeChildNode(tileNode);
                delete tileNode;
            }
        }
    }

    if (m_routePath.size() >= 2) {
        QVector<QPointF> routePoints;
        routePoints.reserve(m_routePath.size());
        QPointF lastKeptPoint;
        bool haveLastKeptPoint = false;
        for (int routeIndex = 0; routeIndex < m_routePath.size(); ++routeIndex) {
            const QVariant &entry = m_routePath.at(routeIndex);
            const QVariantMap point = entry.toMap();
            const QPointF screen = projectToScreen(point.value(QStringLiteral("lat")).toDouble(),
                                                   point.value(QStringLiteral("lng")).toDouble(),
                                                   z,
                                                   centerWorld);
            if (haveLastKeptPoint) {
                const qreal dx = screen.x() - lastKeptPoint.x();
                const qreal dy = screen.y() - lastKeptPoint.y();
                const bool lastPoint = routeIndex == (m_routePath.size() - 1);
                if (!lastPoint && ((dx * dx) + (dy * dy) < (kRouteCullDistancePx * kRouteCullDistancePx))) {
                    continue;
                }
            }
            routePoints.append(screen);
            lastKeptPoint = screen;
            haveLastKeptPoint = true;
        }

        if (routePoints.size() >= 2) {
            auto *geometry = root->routeNode->geometry();
            geometry->allocate(routePoints.size());
            QSGGeometry::Point2D *points = geometry->vertexDataAsPoint2D();
            for (int index = 0; index < routePoints.size(); ++index) {
                points[index].set(float(routePoints.at(index).x()), float(routePoints.at(index).y()));
            }
            root->routeNode->markDirty(QSGNode::DirtyGeometry);
            recordCounter(QStringLiteral("map.routeVertices"), routePoints.size());
        } else {
            root->routeNode->geometry()->allocate(0);
            root->routeNode->markDirty(QSGNode::DirtyGeometry);
        }
    } else {
        root->routeNode->geometry()->allocate(0);
        root->routeNode->markDirty(QSGNode::DirtyGeometry);
    }

    if (m_vehicleVisible) {
        auto *geometry = root->vehicleNode->geometry();
        if (geometry->vertexCount() != 3) {
            geometry->allocate(3);
        }
        QSGGeometry::Point2D *points = geometry->vertexDataAsPoint2D();

        const QPointF vehiclePoint = projectToScreen(m_vehicleLat, m_vehicleLng, z, centerWorld);
        const float cx = float(vehiclePoint.x());
        const float cy = float(vehiclePoint.y());
        const float headingRad = qDegreesToRadians(m_vehicleBearing);
        const float cosH = qCos(headingRad);
        const float sinH = qSin(headingRad);
        const auto rotatePoint = [&](float dx, float dy) -> QPointF {
            return QPointF(cx + (dx * cosH - dy * sinH), cy + (dx * sinH + dy * cosH));
        };

        const QPointF nose = rotatePoint(0.0f, -18.0f);
        const QPointF left = rotatePoint(-11.0f, 11.0f);
        const QPointF right = rotatePoint(11.0f, 11.0f);
        points[0].set(float(nose.x()), float(nose.y()));
        points[1].set(float(left.x()), float(left.y()));
        points[2].set(float(right.x()), float(right.y()));
        root->vehicleNode->markDirty(QSGNode::DirtyGeometry);
    } else {
        root->vehicleNode->geometry()->allocate(0);
        root->vehicleNode->markDirty(QSGNode::DirtyGeometry);
    }

    return root;
}
