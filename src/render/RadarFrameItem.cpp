#include "RadarFrameItem.h"

#include <QDebug>
#include <QFileInfo>
#include <QImageReader>
#include <QHash>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QtMath>

namespace {
class RadarVectorRoot final : public QSGNode
{
public:
    int revision = -1;
    int geometryRevision = -1;
    QSize size;
};

int quantizeColorChannel(int value)
{
    return qBound(0, ((value + 8) / 16) * 16, 255);
}

QRgb quantizedColorKey(const QColor &color)
{
    return qRgba(quantizeColorChannel(color.red()),
                 quantizeColorChannel(color.green()),
                 quantizeColorChannel(color.blue()),
                 color.alpha());
}

QColor colorFromKey(QRgb key)
{
    return QColor(qRed(key), qGreen(key), qBlue(key), qAlpha(key));
}

bool sampleFrameColor(QRgb pixel, QColor &color)
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

    if (maxChannel < 24) {
        return false;
    }

    const bool brightNeutral = maxChannel > 172 && spread < 92;
    const bool saturatedReturn = maxChannel > 96 && spread > 36;
    const bool brightReturn = maxChannel > 140 && spread > 18;
    if (brightNeutral || saturatedReturn || brightReturn) {
        color = QColor(r, g, b, 255);
        return true;
    }

    color = QColor(qBound(0, int(r * 0.92), 255),
                   qBound(0, int(g * 0.92), 255),
                   qBound(0, int(b * 0.92), 255),
                   248);
    return true;
}

QSGGeometryNode *makeRectNode(const QRectF &rect, const QColor &color)
{
    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 6);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    QSGGeometry::Point2D *vertices = geometry->vertexDataAsPoint2D();
    vertices[0].set(float(rect.left()), float(rect.top()));
    vertices[1].set(float(rect.right()), float(rect.top()));
    vertices[2].set(float(rect.left()), float(rect.bottom()));
    vertices[3].set(float(rect.right()), float(rect.top()));
    vertices[4].set(float(rect.right()), float(rect.bottom()));
    vertices[5].set(float(rect.left()), float(rect.bottom()));

    auto *node = new QSGGeometryNode;
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);
    auto *material = new QSGFlatColorMaterial;
    material->setColor(color);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

QSGGeometryNode *makeCircleNode(const QPointF &center, qreal radius, const QColor &color, int segments = 72)
{
    if (radius <= 0) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), segments * 3);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    QSGGeometry::Point2D *vertices = geometry->vertexDataAsPoint2D();
    int cursor = 0;
    for (int i = 0; i < segments; ++i) {
        const qreal a0 = (2.0 * M_PI * i) / segments;
        const qreal a1 = (2.0 * M_PI * (i + 1)) / segments;
        vertices[cursor++].set(float(center.x()), float(center.y()));
        vertices[cursor++].set(float(center.x() + qCos(a0) * radius),
                               float(center.y() + qSin(a0) * radius));
        vertices[cursor++].set(float(center.x() + qCos(a1) * radius),
                               float(center.y() + qSin(a1) * radius));
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

struct RadarSample {
    QRectF rect;
};

QSGGeometryNode *makeSampleNode(const QVector<RadarSample> &samples, const QColor &color)
{
    if (samples.isEmpty()) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), samples.size() * 6);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    QSGGeometry::Point2D *vertices = geometry->vertexDataAsPoint2D();
    int cursor = 0;
    for (const RadarSample &sample : samples) {
        const QRectF &rect = sample.rect;
        vertices[cursor++].set(float(rect.left()), float(rect.top()));
        vertices[cursor++].set(float(rect.right()), float(rect.top()));
        vertices[cursor++].set(float(rect.left()), float(rect.bottom()));
        vertices[cursor++].set(float(rect.right()), float(rect.top()));
        vertices[cursor++].set(float(rect.right()), float(rect.bottom()));
        vertices[cursor++].set(float(rect.left()), float(rect.bottom()));
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

QSGGeometryNode *makeLineNode(const QVector<QPointF> &points, const QColor &color, float width)
{
    if (points.size() < 2) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), points.size());
    geometry->setDrawingMode(QSGGeometry::DrawLineStrip);
    geometry->setLineWidth(width);
    QSGGeometry::Point2D *vertices = geometry->vertexDataAsPoint2D();
    for (int i = 0; i < points.size(); ++i) {
        vertices[i].set(float(points.at(i).x()), float(points.at(i).y()));
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

void appendRadarSamples(RadarVectorRoot *root, const QImage &image, const QSize &targetSize, bool circular)
{
    const QRectF sourceRect = croppedSourceRect(image, targetSize);
    const qreal scaleX = qreal(targetSize.width()) / sourceRect.width();
    const qreal scaleY = qreal(targetSize.height()) / sourceRect.height();
    const qreal sourceToTarget = qMax(sourceRect.width() / qMax(1, targetSize.width()),
                                      sourceRect.height() / qMax(1, targetSize.height()));
    const int minimumStep = targetSize.width() >= 480 ? 4 : (targetSize.width() >= 180 ? 5 : 6);
    const int sampleStep = qBound(minimumStep, int(qCeil(sourceToTarget)), 7);
    const qreal sampleWidth = qMax<qreal>(1.4, sampleStep * scaleX * 1.28);
    const qreal sampleHeight = qMax<qreal>(1.4, sampleStep * scaleY * 1.28);
    const QPointF clipCenter(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal clipRadius = qMin(targetSize.width(), targetSize.height()) * 0.5 - 1.0;
    const qreal clipRadiusSquared = clipRadius * clipRadius;

    QHash<QRgb, QVector<RadarSample>> samplesByColor;
    int totalSamples = 0;
    const int left = qMax(0, int(qFloor(sourceRect.left())));
    const int right = qMin(image.width() - 1, int(qCeil(sourceRect.right())));
    const int top = qMax(0, int(qFloor(sourceRect.top())));
    const int bottom = qMin(image.height() - 1, int(qCeil(sourceRect.bottom())));
    for (int y = top; y <= bottom; y += sampleStep) {
        const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = left; x <= right; x += sampleStep) {
            QColor color;
            if (!sampleFrameColor(line[x], color)) {
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
            const QRgb key = quantizedColorKey(color);
            samplesByColor[key].append(RadarSample{QRectF(itemX, itemY, sampleWidth, sampleHeight)});
            ++totalSamples;
        }
    }

    for (auto it = samplesByColor.constBegin(); it != samplesByColor.constEnd(); ++it) {
        if (auto *node = makeSampleNode(it.value(), colorFromKey(it.key()))) {
            root->appendChildNode(node);
        }
    }

    qInfo().noquote() << "[RadarFrameItem] palette samples" << totalSamples
                      << "step" << sampleStep << "target"
                      << targetSize.width() << "x" << targetSize.height()
                      << "colors" << samplesByColor.size()
                      << "circular" << circular;
}

void appendRadarGuides(RadarVectorRoot *root, const QSize &targetSize)
{
    const QColor guideColor(88, 255, 225, 48);
    const QPointF center(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal radiusBase = qMin(targetSize.width(), targetSize.height()) / 7.0;
    constexpr int kSegments = 96;
    for (int ring = 1; ring <= 3; ++ring) {
        QVector<QPointF> points;
        points.reserve(kSegments + 1);
        const qreal radius = radiusBase * ring;
        for (int i = 0; i <= kSegments; ++i) {
            const qreal angle = (2.0 * M_PI * i) / kSegments;
            points.append(QPointF(center.x() + qCos(angle) * radius,
                                  center.y() + qSin(angle) * radius));
        }
        if (auto *node = makeLineNode(points, guideColor, 1.0f)) {
            root->appendChildNode(node);
        }
    }

    QVector<QPointF> vertical;
    vertical << QPointF(center.x(), targetSize.height() * 0.08)
             << QPointF(center.x(), targetSize.height() * 0.92);
    if (auto *node = makeLineNode(vertical, guideColor, 1.0f)) {
        root->appendChildNode(node);
    }

    QVector<QPointF> horizontal;
    horizontal << QPointF(targetSize.width() * 0.20, center.y())
               << QPointF(targetSize.width() * 0.80, center.y());
    if (auto *node = makeLineNode(horizontal, guideColor, 1.0f)) {
        root->appendChildNode(node);
    }
}
} // namespace

RadarFrameItem::RadarFrameItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
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
    update();
}

QSGNode *RadarFrameItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    if (!m_ready || m_image.isNull() || width() <= 0 || height() <= 0) {
        delete oldNode;
        return nullptr;
    }

    const QSize targetSize(qMax(1, int(width())), qMax(1, int(height())));
    auto *root = static_cast<RadarVectorRoot *>(oldNode);
    const bool rebuild = !root
        || root->revision != m_sourceRevision
        || root->geometryRevision != m_geometryRevision
        || root->size != targetSize;
    if (!rebuild) {
        return root;
    }

    delete root;
    root = new RadarVectorRoot;
    root->revision = m_sourceRevision;
    root->geometryRevision = m_geometryRevision;
    root->size = targetSize;
    if (m_backgroundVisible) {
        if (m_circular) {
            root->appendChildNode(makeCircleNode(QPointF(targetSize.width() * 0.5, targetSize.height() * 0.5),
                                                 qMin(targetSize.width(), targetSize.height()) * 0.5,
                                                 QColor(3, 4, 10)));
        } else {
            root->appendChildNode(makeRectNode(QRectF(0, 0, targetSize.width(), targetSize.height()),
                                               QColor(3, 4, 10)));
        }
    }
    appendRadarSamples(root, m_image, targetSize, m_circular);
    if (m_guidesVisible) {
        appendRadarGuides(root, targetSize);
    }
    return root;
}
