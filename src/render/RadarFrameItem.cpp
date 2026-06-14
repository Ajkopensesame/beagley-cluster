#include "RadarFrameItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QHash>
#include <QImageReader>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QtMath>

namespace {
struct ColoredRect {
    QRectF rect;
    QColor color;
};

struct ColoredLine {
    QPointF start;
    QPointF end;
    QColor color;
};

class RadarVectorRoot final : public QSGNode
{
public:
    int sourceRevision = -1;
    int mapRevision = -1;
    int geometryRevision = -1;
    QSize size;
};

bool radarSampleColor(QRgb pixel, QColor &color)
{
    if (qAlpha(pixel) < 24) {
        return false;
    }

    const int r = qRed(pixel);
    const int g = qGreen(pixel);
    const int b = qBlue(pixel);
    const int maxChannel = qMax(r, qMax(g, b));
    const int minChannel = qMin(r, qMin(g, b));
    const int spread = maxChannel - minChannel;

    if (maxChannel < 96 || spread < 40) {
        return false;
    }

    const bool blueReturn = b >= 140
        && g >= 95
        && r <= 140
        && (b - r) >= 40
        && (g - r) >= 8;
    const bool greenReturn = g >= 140
        && r <= 155
        && b <= 155
        && (g - qMax(r, b)) >= 28;
    const bool yellowReturn = r >= 175
        && g >= 160
        && b <= 160
        && (r - b) >= 32
        && (g - b) >= 28;
    const bool orangeReturn = r >= 190
        && g >= 90
        && g <= 185
        && b <= 130
        && (r - g) >= 22;
    const bool redReturn = r >= 200
        && g <= 110
        && b <= 120
        && (r - qMax(g, b)) >= 45;
    const bool purpleReturn = r >= 140
        && b >= 140
        && g <= 135
        && spread >= 50;
    if (!blueReturn && !greenReturn && !yellowReturn && !orangeReturn && !redReturn && !purpleReturn) {
        return false;
    }

    if (redReturn) {
        color = QColor(255, 45, 60, 238);
    } else if (orangeReturn) {
        color = QColor(255, 132, 38, 236);
    } else if (yellowReturn) {
        color = QColor(255, 224, 64, 234);
    } else if (greenReturn) {
        color = QColor(50, 255, 92, 232);
    } else if (purpleReturn) {
        color = QColor(186, 112, 255, 232);
    } else {
        color = QColor(64, 204, 255, 232);
    }
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

void appendRect(QVector<ColoredRect> &rects, const QRectF &rect, const QColor &color)
{
    if (rect.width() <= 0 || rect.height() <= 0 || color.alpha() <= 0) {
        return;
    }
    rects.append({rect, color});
}

int appendRadarSamples(QVector<ColoredRect> &rects, const QImage &image, const QSize &targetSize, bool circular)
{
    const QRectF sourceRect = croppedSourceRect(image, targetSize);
    const qreal scaleX = qreal(targetSize.width()) / sourceRect.width();
    const qreal scaleY = qreal(targetSize.height()) / sourceRect.height();
    const int sampleStep = targetSize.width() < 180
        ? 2
        : (targetSize.width() >= 260
              ? 2
              : qBound(3,
                       int(qRound(qMax(sourceRect.width() / qMax(1, targetSize.width()),
                                       sourceRect.height() / qMax(1, targetSize.height())))),
                       5));
    const qreal minimumSampleSize = targetSize.width() < 130 ? 4.2 : (targetSize.width() < 180 ? 3.0 : 1.6);
    const qreal sampleWidth = qMax<qreal>(minimumSampleSize, sampleStep * scaleX * 1.16);
    const qreal sampleHeight = qMax<qreal>(minimumSampleSize, sampleStep * scaleY * 1.16);
    const QPointF clipCenter(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal clipRadius = qMin(targetSize.width(), targetSize.height()) * 0.5 - 1.0;
    const qreal clipRadiusSquared = clipRadius * clipRadius;

    int totalSamples = 0;
    const int left = qMax(0, int(qFloor(sourceRect.left())));
    const int right = qMin(image.width() - 1, int(qCeil(sourceRect.right())));
    const int top = qMax(0, int(qFloor(sourceRect.top())));
    const int bottom = qMin(image.height() - 1, int(qCeil(sourceRect.bottom())));

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
            appendRect(rects, QRectF(itemX, itemY, sampleWidth, sampleHeight), color);
            ++totalSamples;
        }
    }
    return totalSamples;
}

void appendGuideLines(QVector<ColoredLine> &lines, const QSize &targetSize)
{
    const QColor color(88, 255, 225, 54);
    const QPointF center(targetSize.width() * 0.5, targetSize.height() * 0.5);
    lines.append({QPointF(center.x(), targetSize.height() * 0.13),
                  QPointF(center.x(), targetSize.height() * 0.87),
                  color});
    lines.append({QPointF(targetSize.width() * 0.18, center.y()),
                  QPointF(targetSize.width() * 0.82, center.y()),
                  color});

    const qreal shortSide = qMin(targetSize.width(), targetSize.height());
    for (int ring = 1; ring <= 3; ++ring) {
        const qreal radius = shortSide * (0.13 + ring * 0.095);
        const int segments = 28;
        QPointF previous(center.x() + radius, center.y());
        for (int i = 1; i <= segments; ++i) {
            const qreal angle = (M_PI * 2.0 * i) / segments;
            QPointF next(center.x() + std::cos(angle) * radius,
                         center.y() + std::sin(angle) * radius);
            lines.append({previous, next, color});
            previous = next;
        }
    }
}

void appendGpsMarker(QVector<ColoredRect> &rects, const QSize &targetSize)
{
    const qreal shortSide = qMin(targetSize.width(), targetSize.height());
    const QPointF center(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal outer = qBound<qreal>(5.0, shortSide * 0.032, 11.0);
    const qreal inner = qBound<qreal>(2.6, shortSide * 0.018, 6.0);
    appendRect(rects, QRectF(center.x() - outer, center.y() - outer, outer * 2.0, outer * 2.0),
               QColor(88, 255, 225, 112));
    appendRect(rects, QRectF(center.x() - inner, center.y() - inner, inner * 2.0, inner * 2.0),
               QColor(247, 251, 255, 232));
}

QSGGeometryNode *createFlatRectNode(const QVector<QRectF> &rects, const QColor &color)
{
    if (rects.isEmpty()) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), rects.size() * 6);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    auto *vertices = geometry->vertexDataAsPoint2D();
    int index = 0;
    for (const QRectF &rect : rects) {
        const float x1 = float(rect.left());
        const float y1 = float(rect.top());
        const float x2 = float(rect.right());
        const float y2 = float(rect.bottom());
        vertices[index++].set(x1, y1);
        vertices[index++].set(x2, y1);
        vertices[index++].set(x1, y2);
        vertices[index++].set(x2, y1);
        vertices[index++].set(x2, y2);
        vertices[index++].set(x1, y2);
    }

    auto *node = new QSGGeometryNode;
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);
    auto *material = new QSGFlatColorMaterial;
    material->setColor(color);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

void appendRectNodes(QSGNode *root, const QVector<ColoredRect> &rects)
{
    QHash<QRgb, QVector<QRectF>> groups;
    for (const ColoredRect &item : rects) {
        groups[item.color.rgba()].append(item.rect);
    }
    for (auto it = groups.cbegin(); it != groups.cend(); ++it) {
        if (auto *node = createFlatRectNode(it.value(), QColor::fromRgba(it.key()))) {
            root->appendChildNode(node);
        }
    }
}

QSGGeometryNode *createFlatLineNode(const QVector<ColoredLine> &lines, const QColor &color)
{
    if (lines.isEmpty()) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), lines.size() * 2);
    geometry->setDrawingMode(QSGGeometry::DrawLines);
    geometry->setLineWidth(1.0f);
    auto *vertices = geometry->vertexDataAsPoint2D();
    int index = 0;
    for (const ColoredLine &item : lines) {
        vertices[index++].set(float(item.start.x()), float(item.start.y()));
        vertices[index++].set(float(item.end.x()), float(item.end.y()));
    }

    auto *node = new QSGGeometryNode;
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);
    auto *material = new QSGFlatColorMaterial;
    material->setColor(color);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

void appendLineNodes(QSGNode *root, const QVector<ColoredLine> &lines)
{
    QHash<QRgb, QVector<ColoredLine>> groups;
    for (const ColoredLine &item : lines) {
        groups[item.color.rgba()].append(item);
    }
    for (auto it = groups.cbegin(); it != groups.cend(); ++it) {
        if (auto *node = createFlatLineNode(it.value(), QColor::fromRgba(it.key()))) {
            root->appendChildNode(node);
        }
    }
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
    if (!m_ready || m_image.isNull() || width() <= 0 || height() <= 0) {
        delete oldNode;
        return nullptr;
    }

    const QSize targetSize(qMax(1, int(qCeil(width()))), qMax(1, int(qCeil(height()))));
    auto *root = static_cast<RadarVectorRoot *>(oldNode);
    const bool rebuild = !root
        || root->sourceRevision != m_sourceRevision
        || root->mapRevision != m_mapRevision
        || root->geometryRevision != m_geometryRevision
        || root->size != targetSize;
    if (!rebuild) {
        return root;
    }

    delete root;
    root = new RadarVectorRoot;
    root->sourceRevision = m_sourceRevision;
    root->mapRevision = m_mapRevision;
    root->geometryRevision = m_geometryRevision;
    root->size = targetSize;

    QVector<ColoredRect> rects;
    QVector<ColoredLine> lines;
    if (m_backgroundVisible) {
        appendRect(rects, QRectF(0, 0, targetSize.width(), targetSize.height()), QColor(3, 8, 13, 235));
    }
    if (m_guidesVisible) {
        appendGuideLines(lines, targetSize);
    }
    const int totalSamples = appendRadarSamples(rects, m_image, targetSize, m_circular);
    appendGpsMarker(rects, targetSize);

    appendRectNodes(root, rects);
    appendLineNodes(root, lines);

    qInfo().noquote() << "[RadarFrameItem] vector samples" << totalSamples
                      << targetSize.width() << "x" << targetSize.height()
                      << "flatColor true"
                      << "mapIgnored" << !m_mapImage.isNull()
                      << "circular" << m_circular;
    return root;
}
