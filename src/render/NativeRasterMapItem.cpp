#include "NativeRasterMapItem.h"

#include <QDir>
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
#include <QStandardPaths>
#include <QUrl>

#include <QtMath>

namespace {
constexpr int kTileSizePx = 256;
constexpr qreal kRouteCullDistancePx = 3.0;

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
        tileLayer = new QSGNode;
        appendChildNode(tileLayer);

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

    QSGNode *tileLayer = nullptr;
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
        updateVisibleTiles();
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
        updateVisibleTiles();
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
        updateVisibleTiles();
    }
    emit viewChanged();
    update();
}

void NativeRasterMapItem::setVehicleBearing(double value)
{
    if (qFuzzyCompare(m_vehicleBearing, value)) {
        return;
    }
    m_vehicleBearing = value;
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
    if (m_componentReady) {
        updateVisibleTiles();
    }
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
        updateVisibleTiles();
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
    updateVisibleTiles();
}

void NativeRasterMapItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (!m_componentReady || newGeometry.size() == oldGeometry.size()) {
        return;
    }
    updateVisibleTiles();
    update();
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
    const QPointF topLeftWorld = centerWorld - QPointF(width() / 2.0, height() / 2.0);

    const int minTileX = int(std::floor(topLeftWorld.x() / kTileSizePx)) - 1;
    const int minTileY = int(std::floor(topLeftWorld.y() / kTileSizePx)) - 1;
    const int maxTileX = int(std::ceil((topLeftWorld.x() + width()) / kTileSizePx)) + 1;
    const int maxTileY = int(std::ceil((topLeftWorld.y() + height()) / kTileSizePx)) + 1;

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
            tile.rect = QRectF((tileX * kTileSizePx) - topLeftWorld.x(),
                               (tileY * kTileSizePx) - topLeftWorld.y(),
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
                                             const QPointF &topLeftWorld) const
{
    return projectToWorld(lat, lng, zoomLevel) - topLeftWorld;
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
    const QList<VisibleTile> tiles = visibleTiles();
    for (const VisibleTile &tile : tiles) {
        requestTile(tile.z, tile.x, tile.y);
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

    QHash<QString, QImage> tileImages;
    QSet<QString> dirtyTextures;
    {
        QMutexLocker locker(&m_tileMutex);
        tileImages = m_tileImages;
        dirtyTextures = m_dirtyTextures;
        m_dirtyTextures.clear();
    }

    for (const QString &key : dirtyTextures) {
        QSGTexture *texture = m_textures.take(key);
        delete texture;
    }

    const QList<VisibleTile> tiles = visibleTiles();
    QSet<QString> visibleKeys;
    for (const VisibleTile &tile : tiles) {
        visibleKeys.insert(tile.key);
        const QImage image = tileImages.value(tile.key);
        if (image.isNull()) {
            continue;
        }

        QSGTexture *texture = m_textures.value(tile.key, nullptr);
        if (!texture && window()) {
            texture = window()->createTextureFromImage(image);
            m_textures.insert(tile.key, texture);
            recordCounter(QStringLiteral("map.tileUpload"));
        }
        if (!texture) {
            continue;
        }

        QSGSimpleTextureNode *node = root->tileNodes.value(tile.key, nullptr);
        if (!node) {
            node = new QSGSimpleTextureNode;
            root->tileLayer->appendChildNode(node);
            root->tileNodes.insert(tile.key, node);
        }
        node->setOwnsTexture(false);
        node->setTexture(texture);
        node->setRect(tile.rect);
        node->markDirty(QSGNode::DirtyGeometry);
        node->markDirty(QSGNode::DirtyMaterial);
    }

    const QList<QString> existingKeys = root->tileNodes.keys();
    for (const QString &key : existingKeys) {
        if (visibleKeys.contains(key)) {
            continue;
        }

        if (QSGSimpleTextureNode *node = root->tileNodes.take(key)) {
            root->tileLayer->removeChildNode(node);
            delete node;
        }

        QSGTexture *texture = m_textures.take(key);
        delete texture;
    }

    const int z = qRound(m_zoom);
    const QPointF centerWorld = projectToWorld(m_centerLat, m_centerLng, z);
    const QPointF topLeftWorld = centerWorld - QPointF(width() / 2.0, height() / 2.0);

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
                                                   topLeftWorld);
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

        const float cx = float(width() * 0.5);
        const float cy = float(height() * 0.5);
        const float headingRad = qDegreesToRadians(m_vehicleBearing - 90.0);
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

    recordCounter(QStringLiteral("map.visibleTileSet"));
    return root;
}
