#pragma once

#include <QHash>
#include <QImage>
#include <QMutex>
#include <QPointer>
#include <QQuickItem>
#include <QSet>
#include <QVariantList>

class QNetworkAccessManager;
class QSGNode;
class QSGTexture;

class NativeRasterMapItem : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(double centerLat READ centerLat WRITE setCenterLat NOTIFY viewChanged)
    Q_PROPERTY(double centerLng READ centerLng WRITE setCenterLng NOTIFY viewChanged)
    Q_PROPERTY(double zoom READ zoom WRITE setZoom NOTIFY viewChanged)
    Q_PROPERTY(double vehicleBearing READ vehicleBearing WRITE setVehicleBearing NOTIFY viewChanged)
    Q_PROPERTY(bool vehicleVisible READ vehicleVisible WRITE setVehicleVisible NOTIFY viewChanged)
    Q_PROPERTY(QVariantList routePath READ routePath WRITE setRoutePath NOTIFY routePathChanged)
    Q_PROPERTY(QString tileUrlTemplate READ tileUrlTemplate WRITE setTileUrlTemplate NOTIFY tileUrlTemplateChanged)
    Q_PROPERTY(QString userAgent READ userAgent WRITE setUserAgent NOTIFY userAgentChanged)
    Q_PROPERTY(QString cacheDirectory READ cacheDirectory WRITE setCacheDirectory NOTIFY cacheDirectoryChanged)
    Q_PROPERTY(QObject *metrics READ metrics WRITE setMetrics NOTIFY metricsChanged)

public:
    explicit NativeRasterMapItem(QQuickItem *parent = nullptr);
    ~NativeRasterMapItem() override;

    double centerLat() const { return m_centerLat; }
    double centerLng() const { return m_centerLng; }
    double zoom() const { return m_zoom; }
    double vehicleBearing() const { return m_vehicleBearing; }
    bool vehicleVisible() const { return m_vehicleVisible; }
    QVariantList routePath() const { return m_routePath; }
    QString tileUrlTemplate() const { return m_tileUrlTemplate; }
    QString userAgent() const { return m_userAgent; }
    QString cacheDirectory() const { return m_cacheDirectory; }
    QObject *metrics() const { return m_metrics; }

    void setCenterLat(double value);
    void setCenterLng(double value);
    void setZoom(double value);
    void setVehicleBearing(double value);
    void setVehicleVisible(bool value);
    void setRoutePath(const QVariantList &path);
    void setTileUrlTemplate(const QString &value);
    void setUserAgent(const QString &value);
    void setCacheDirectory(const QString &value);
    void setMetrics(QObject *metricsObject);

signals:
    void viewChanged();
    void routePathChanged();
    void tileUrlTemplateChanged();
    void userAgentChanged();
    void cacheDirectoryChanged();
    void metricsChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void componentComplete() override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    struct VisibleTile {
        QString key;
        int z = 0;
        int x = 0;
        int y = 0;
        QRectF rect;
    };

    void ensureNetwork();
    void updateVisibleTiles();
    QList<VisibleTile> visibleTiles() const;
    QPointF projectToWorld(double lat, double lng, double zoomLevel) const;
    QPointF projectToScreen(double lat, double lng, double zoomLevel, const QPointF &topLeftWorld) const;
    QString tileKey(int z, int x, int y) const;
    void requestTile(int z, int x, int y);
    void recordCounter(const QString &bucket, int amount = 1);

    double m_centerLat = -27.4698;
    double m_centerLng = 153.0251;
    double m_zoom = 14.0;
    double m_vehicleBearing = 0.0;
    bool m_vehicleVisible = true;
    QVariantList m_routePath;
    QString m_tileUrlTemplate = QStringLiteral("https://tile.openstreetmap.org/{z}/{x}/{y}.png");
    QString m_userAgent = QStringLiteral("BeagleyCluster/1.0");
    QString m_cacheDirectory;
    QPointer<QObject> m_metrics;
    bool m_componentReady = false;

    mutable QMutex m_tileMutex;
    QHash<QString, QImage> m_tileImages;
    QSet<QString> m_pendingTiles;
    QSet<QString> m_dirtyTextures;
    QNetworkAccessManager *m_network = nullptr;

    QHash<QString, QSGTexture *> m_textures;
};
