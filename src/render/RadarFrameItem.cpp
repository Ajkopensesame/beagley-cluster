#include "RadarFrameItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QPainterPath>
#include <QQuickWindow>
#include <QSGNode>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QtMath>

namespace {
class RadarTextureRoot final : public QSGNode
{
public:
    RadarTextureRoot()
    {
        imageNode = new QSGSimpleTextureNode;
        imageNode->setOwnsTexture(true);
        appendChildNode(imageNode);
    }

    int revision = -1;
    int mapRevision = -1;
    int geometryRevision = -1;
    QSize size;
    QSGSimpleTextureNode *imageNode = nullptr;
};

bool radarSampleColor(QRgb pixel, QColor &color)
{
    const int r = qRed(pixel);
    const int g = qGreen(pixel);
    const int b = qBlue(pixel);
    const int maxChannel = qMax(r, qMax(g, b));
    const int minChannel = qMin(r, qMin(g, b));
    const int spread = maxChannel - minChannel;

    if (maxChannel < 96 || spread < 44) {
        return false;
    }

    // The source PNG includes a detailed BOM basemap. Only keep colours that
    // match radar-return palettes; otherwise roads, terrain, labels, and coast
    // shading turn into noisy scene-graph geometry on the BeagleY GPU.
    const bool blueReturn = b >= 140
        && g >= 95
        && r <= 130
        && (b - r) >= 45
        && (g - r) >= 10;
    const bool yellowReturn = r >= 180
        && g >= 170
        && b <= 150
        && (r - b) >= 40
        && (g - b) >= 35;
    const bool orangeReturn = r >= 195
        && g >= 95
        && g <= 178
        && b <= 120
        && (r - g) >= 24;
    const bool redReturn = r >= 205
        && g <= 105
        && b <= 115
        && (r - qMax(g, b)) >= 50;
    const bool purpleReturn = r >= 145
        && b >= 145
        && g <= 130
        && spread >= 54;
    if (!blueReturn && !yellowReturn && !orangeReturn && !redReturn && !purpleReturn) {
        return false;
    }

    color = QColor(r, g, b, 232);
    return true;
}

QRectF croppedSourceRect(const QImage &image, const QSize &targetSize)
{
    const qreal sourceAspect = qreal(image.width()) / qreal(image.height());
    const qreal targetAspect = qreal(targetSize.width()) / qreal(targetSize.height());
    QRectF sourceRect(image.rect());
    if (sourceAspect > targetAspect) {
        const qreal cropWidth = image.height() * targetAspect;
        sourceRect.setX((image.width() - cropWidth) * 0.5);
        sourceRect.setWidth(cropWidth);
    } else if (sourceAspect < targetAspect) {
        const qreal cropHeight = image.width() / targetAspect;
        sourceRect.setY((image.height() - cropHeight) * 0.5);
        sourceRect.setHeight(cropHeight);
    }
    return sourceRect;
}

void drawRadarGuides(QPainter &painter, const QSize &targetSize)
{
    painter.save();
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(QPen(QColor(88, 255, 225, 46), 1.2));

    const QPointF center(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal radiusBase = qMin(targetSize.width(), targetSize.height()) / 7.0;
    for (int ring = 1; ring <= 3; ++ring) {
        const qreal radius = radiusBase * ring;
        painter.drawEllipse(center, radius, radius);
    }

    painter.drawLine(QPointF(center.x(), targetSize.height() * 0.08),
                     QPointF(center.x(), targetSize.height() * 0.92));
    painter.drawLine(QPointF(targetSize.width() * 0.20, center.y()),
                     QPointF(targetSize.width() * 0.80, center.y()));
    painter.restore();
}

void drawMapBackground(QPainter &painter, const QImage &image, const QSize &targetSize)
{
    const QRectF sourceRect = croppedSourceRect(image, targetSize);
    painter.save();
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setOpacity(1.0);
    painter.drawImage(QRectF(0, 0, targetSize.width(), targetSize.height()), image, sourceRect);
    painter.fillRect(QRectF(0, 0, targetSize.width(), targetSize.height()), QColor(18, 86, 118, 8));
    painter.restore();
}

int drawRadarSamples(QPainter &painter, const QImage &image, const QSize &targetSize, bool circular)
{
    const QRectF sourceRect = croppedSourceRect(image, targetSize);
    const qreal scaleX = qreal(targetSize.width()) / sourceRect.width();
    const qreal scaleY = qreal(targetSize.height()) / sourceRect.height();
    const int sampleStep = targetSize.width() >= 260
        ? 2
        : qBound(3,
                 int(qRound(qMax(sourceRect.width() / qMax(1, targetSize.width()),
                                 sourceRect.height() / qMax(1, targetSize.height())))),
                 5);
    const qreal sampleWidth = qMax<qreal>(1.4, sampleStep * scaleX * 1.10);
    const qreal sampleHeight = qMax<qreal>(1.4, sampleStep * scaleY * 1.10);
    const QPointF clipCenter(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal clipRadius = qMin(targetSize.width(), targetSize.height()) * 0.5 - 1.0;
    const qreal clipRadiusSquared = clipRadius * clipRadius;

    int totalSamples = 0;
    const int left = qMax(0, int(qFloor(sourceRect.left())));
    const int right = qMin(image.width() - 1, int(qCeil(sourceRect.right())));
    const int top = qMax(0, int(qFloor(sourceRect.top())));
    const int bottom = qMin(image.height() - 1, int(qCeil(sourceRect.bottom())));

    painter.save();
    painter.setRenderHint(QPainter::Antialiasing, false);
    for (int y = top; y <= bottom; y += sampleStep) {
        const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = left; x <= right; x += sampleStep) {
            QColor color;
            if (!radarSampleColor(line[x], color)) {
                continue;
            }
            const qreal itemX = (x - sourceRect.left()) * scaleX;
            const qreal itemY = (y - sourceRect.top()) * scaleY;
            if (circular) {
                const qreal dx = itemX - clipCenter.x();
                const qreal dy = itemY - clipCenter.y();
                if ((dx * dx) + (dy * dy) > clipRadiusSquared) {
                    continue;
                }
            }
            painter.fillRect(QRectF(itemX, itemY, sampleWidth, sampleHeight), color);
            ++totalSamples;
        }
    }
    painter.restore();
    return totalSamples;
}

void drawGpsMarker(QPainter &painter, const QSize &targetSize)
{
    const QPointF center(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal shortSide = qMin(targetSize.width(), targetSize.height());
    const qreal dotRadius = qBound<qreal>(3.8, shortSide * 0.018, 10.0);

    painter.save();
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setPen(QPen(QColor(88, 255, 225, 136), qMax<qreal>(1.2, dotRadius * 0.28)));
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(center, dotRadius * 2.15, dotRadius * 2.15);
    painter.setPen(QPen(QColor(247, 251, 255, 220), qMax<qreal>(1.0, dotRadius * 0.20)));
    painter.setBrush(QColor(88, 255, 225, 235));
    painter.drawEllipse(center, dotRadius, dotRadius);
    painter.setPen(Qt::NoPen);
    painter.setBrush(QColor(247, 251, 255, 245));
    painter.drawEllipse(center, dotRadius * 0.42, dotRadius * 0.42);
    painter.restore();
}

QImage renderRadarFrameImage(const QImage &source,
                             const QImage &mapSource,
                             const QSize &targetSize,
                             bool circular,
                             bool backgroundVisible,
                             bool guidesVisible)
{
    QImage output(targetSize, QImage::Format_ARGB32_Premultiplied);
    output.fill(circular ? Qt::transparent : (backgroundVisible ? QColor(3, 4, 10) : Qt::transparent));

    QPainter painter(&output);
    if (circular) {
        QPainterPath path;
        path.addEllipse(QRectF(0, 0, targetSize.width(), targetSize.height()));
        painter.setClipPath(path);
    }
    if (circular && backgroundVisible) {
        painter.fillRect(QRectF(0, 0, targetSize.width(), targetSize.height()), QColor(3, 4, 10));
    }
    if (backgroundVisible && !mapSource.isNull()) {
        drawMapBackground(painter, mapSource, targetSize);
    }
    if (guidesVisible) {
        drawRadarGuides(painter, targetSize);
    }
    const int totalSamples = drawRadarSamples(painter, source, targetSize, circular);
    drawGpsMarker(painter, targetSize);
    painter.end();

    qInfo().noquote() << "[RadarFrameItem] palette samples" << totalSamples
                      << targetSize.width() << "x" << targetSize.height()
                      << "texture true"
                      << "circular" << circular;
    return output;
}
} // namespace

RadarFrameItem::RadarFrameItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    setClip(true);
}

RadarFrameItem::~RadarFrameItem() = default;

void RadarFrameItem::setSource(const QUrl &source)
{
    if (m_source == source) {
        return;
    }

    m_source = source;
    emit sourceChanged();
    loadSource();
}

void RadarFrameItem::setMapSource(const QUrl &source)
{
    if (m_mapSource == source) {
        return;
    }

    m_mapSource = source;
    emit mapSourceChanged();
    loadMapSource();
}

void RadarFrameItem::setCircular(bool circular)
{
    if (m_circular == circular) {
        return;
    }
    m_circular = circular;
    ++m_geometryRevision;
    emit circularChanged();
    update();
}

void RadarFrameItem::setBackgroundVisible(bool visible)
{
    if (m_backgroundVisible == visible) {
        return;
    }
    m_backgroundVisible = visible;
    ++m_geometryRevision;
    emit backgroundVisibleChanged();
    update();
}

void RadarFrameItem::setGuidesVisible(bool visible)
{
    if (m_guidesVisible == visible) {
        return;
    }
    m_guidesVisible = visible;
    ++m_geometryRevision;
    emit guidesVisibleChanged();
    update();
}

void RadarFrameItem::loadSource()
{
    ++m_sourceRevision;
    m_image = QImage();

    if (m_source.isEmpty()) {
        setReady(false);
        update();
        return;
    }

    if (!m_source.isLocalFile()) {
        qWarning().noquote() << "[RadarFrameItem] unsupported non-local source" << m_source;
        setReady(false);
        update();
        return;
    }

    const QString path = m_source.toLocalFile();
    if (!QFileInfo::exists(path)) {
        qWarning().noquote() << "[RadarFrameItem] source missing" << path;
        setReady(false);
        update();
        return;
    }

    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        qWarning().noquote() << "[RadarFrameItem] failed to read" << path << reader.errorString();
        setReady(false);
        update();
        return;
    }

    m_image = image.convertToFormat(QImage::Format_ARGB32);
    qInfo().noquote() << "[RadarFrameItem] loaded" << path << m_image.width() << "x" << m_image.height();
    setReady(true);
    update();
}

void RadarFrameItem::loadMapSource()
{
    ++m_mapRevision;
    m_mapImage = QImage();

    if (m_mapSource.isEmpty()) {
        update();
        return;
    }

    if (!m_mapSource.isLocalFile()) {
        qWarning().noquote() << "[RadarFrameItem] unsupported non-local map source" << m_mapSource;
        update();
        return;
    }

    const QString path = m_mapSource.toLocalFile();
    if (!QFileInfo::exists(path)) {
        qWarning().noquote() << "[RadarFrameItem] map source missing" << path;
        update();
        return;
    }

    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        qWarning().noquote() << "[RadarFrameItem] failed to read map" << path << reader.errorString();
        update();
        return;
    }

    m_mapImage = image.convertToFormat(QImage::Format_ARGB32);
    qInfo().noquote() << "[RadarFrameItem] loaded map" << path << m_mapImage.width() << "x" << m_mapImage.height();
    update();
}

void RadarFrameItem::setReady(bool ready)
{
    if (m_ready == ready) {
        return;
    }
    m_ready = ready;
    emit readyChanged();
}

void RadarFrameItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() == oldGeometry.size()) {
        return;
    }
    ++m_geometryRevision;
    update();
}

QSGNode *RadarFrameItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (!m_ready || m_image.isNull() || width() <= 0 || height() <= 0 || !window()) {
        delete oldNode;
        return nullptr;
    }

    const QSize targetSize(qMax(1, int(width())), qMax(1, int(height())));
    auto *root = static_cast<RadarTextureRoot *>(oldNode);
    const bool rebuild = !root
        || root->revision != m_sourceRevision
        || root->mapRevision != m_mapRevision
        || root->geometryRevision != m_geometryRevision
        || root->size != targetSize;
    if (!rebuild) {
        return root;
    }

    delete root;
    root = new RadarTextureRoot;
    root->revision = m_sourceRevision;
    root->mapRevision = m_mapRevision;
    root->geometryRevision = m_geometryRevision;
    root->size = targetSize;

    const QImage frame = renderRadarFrameImage(m_image,
                                               m_mapImage,
                                               targetSize,
                                               m_circular,
                                               m_backgroundVisible,
                                               m_guidesVisible);
    QSGTexture *texture = window()->createTextureFromImage(frame);
    if (!texture) {
        delete root;
        return nullptr;
    }

    root->imageNode->setTexture(texture);
    root->imageNode->setFiltering(QSGTexture::Linear);
    root->imageNode->setRect(0, 0, width(), height());
    root->imageNode->markDirty(QSGNode::DirtyGeometry);
    root->imageNode->markDirty(QSGNode::DirtyMaterial);
    return root;
}
