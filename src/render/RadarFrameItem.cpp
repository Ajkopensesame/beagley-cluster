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

int quantizeColorChannel(int value, int bucket)
{
    return qBound(0, ((value + (bucket / 2)) / bucket) * bucket, 255);
}

QRgb quantizedColorKey(const QColor &color, int bucket = 16)
{
    return qRgba(quantizeColorChannel(color.red(), bucket),
                 quantizeColorChannel(color.green(), bucket),
                 quantizeColorChannel(color.blue(), bucket),
                 color.alpha());
}

QColor colorFromKey(QRgb key)
{
    return QColor(qRed(key), qGreen(key), qBlue(key), qAlpha(key));
}

bool sampleRadarReturnColor(QRgb pixel, QColor &color, bool glow)
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

    if (maxChannel < 92 || spread < 30) {
        return false;
    }

    const bool cyanReturn = ((b > 135 && g > 110 && r < 132 && b > r + 42)
                             || (g > 142 && b > 108 && r < 122 && g > r + 44));
    const bool yellowReturn = r > 150 && g > 132 && b < 142 && qMin(r, g) > b + 32;
    const bool orangeReturn = r > 166 && g > 92 && g < 170 && b < 112 && r > b + 58;
    const bool intenseReturn = maxChannel > 202 && spread > 48
        && ((b > r + 35 && g > r + 20) || (r > b + 45 && g > b + 20));

    if (!(cyanReturn || yellowReturn || orangeReturn || intenseReturn)) {
        return false;
    }

    if (cyanReturn) {
        color = glow ? QColor(31, 206, 255, 78) : QColor(0, 188, 235, 226);
        return true;
    }
    if (yellowReturn) {
        color = glow ? QColor(255, 226, 96, 70) : QColor(255, 214, 72, 218);
        return true;
    }
    if (orangeReturn) {
        color = glow ? QColor(255, 134, 54, 76) : QColor(255, 112, 44, 224);
        return true;
    }

    color = glow ? QColor(255, 245, 210, 62) : QColor(252, 248, 206, 198);
    return true;
}

enum class BaseMapClass {
    None,
    Water,
    Forest,
    Road,
    Land
};

BaseMapClass classifyBaseMapPixel(QRgb pixel)
{
    if (qAlpha(pixel) < 24) {
        return BaseMapClass::None;
    }

    QColor ignored;
    if (sampleRadarReturnColor(pixel, ignored, false)) {
        return BaseMapClass::None;
    }

    const int r = qRed(pixel);
    const int g = qGreen(pixel);
    const int b = qBlue(pixel);
    const int maxChannel = qMax(r, qMax(g, b));
    const int minChannel = qMin(r, qMin(g, b));
    const int spread = maxChannel - minChannel;

    if (maxChannel < 48) {
        return BaseMapClass::None;
    }

    // Dark labels and single-pixel map details are the main source of the
    // "static" look when converted to primitive rectangles.
    if (maxChannel < 116 && spread < 64) {
        return BaseMapClass::None;
    }

    const bool water = b > r + 10 && g > r + 4 && b > 82;
    const bool forest = g > r + 8 && g > b + 1 && g > 72;
    const bool road = r > 128 && g > 78 && b > 62 && r > b + 16 && r >= g;
    const bool neutralLand = spread < 56 && maxChannel > 126;

    if (water) {
        return BaseMapClass::Water;
    }
    if (forest) {
        return BaseMapClass::Forest;
    }
    if (road) {
        return BaseMapClass::Road;
    }
    if (neutralLand) {
        return BaseMapClass::Land;
    }
    return BaseMapClass::None;
}

QColor baseMapClassColor(BaseMapClass klass)
{
    switch (klass) {
    case BaseMapClass::Water:
        return QColor(40, 88, 98, 162);
    case BaseMapClass::Forest:
        return QColor(37, 84, 58, 130);
    case BaseMapClass::Road:
        return QColor(118, 86, 78, 116);
    case BaseMapClass::Land:
        return QColor(56, 62, 72, 118);
    case BaseMapClass::None:
        break;
    }
    return QColor();
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

struct SamplePlan {
    QRectF sourceRect;
    qreal scaleX = 1.0;
    qreal scaleY = 1.0;
    qreal sourceToTarget = 1.0;
    QPointF clipCenter;
    qreal clipRadiusSquared = 0.0;
    int left = 0;
    int right = 0;
    int top = 0;
    int bottom = 0;
};

SamplePlan makeSamplePlan(const QImage &image, const QSize &targetSize)
{
    SamplePlan plan;
    const QRectF sourceRect = croppedSourceRect(image, targetSize);
    plan.sourceRect = sourceRect;
    plan.scaleX = qreal(targetSize.width()) / sourceRect.width();
    plan.scaleY = qreal(targetSize.height()) / sourceRect.height();
    plan.sourceToTarget = qMax(sourceRect.width() / qMax(1, targetSize.width()),
                               sourceRect.height() / qMax(1, targetSize.height()));
    plan.clipCenter = QPointF(targetSize.width() * 0.5, targetSize.height() * 0.5);
    const qreal clipRadius = qMin(targetSize.width(), targetSize.height()) * 0.5 - 1.0;
    plan.clipRadiusSquared = clipRadius * clipRadius;
    plan.left = qMax(0, int(qFloor(sourceRect.left())));
    plan.right = qMin(image.width() - 1, int(qCeil(sourceRect.right())));
    plan.top = qMax(0, int(qFloor(sourceRect.top())));
    plan.bottom = qMin(image.height() - 1, int(qCeil(sourceRect.bottom())));
    return plan;
}

using ColorSampler = bool (*)(QRgb, QColor &);

bool sampleRadarCore(QRgb pixel, QColor &color)
{
    return sampleRadarReturnColor(pixel, color, false);
}

bool sampleRadarGlow(QRgb pixel, QColor &color)
{
    return sampleRadarReturnColor(pixel, color, true);
}

int baseMapStep(const SamplePlan &plan, const QSize &targetSize)
{
    const int minimumStep = targetSize.width() >= 480 ? 14 : (targetSize.width() >= 180 ? 16 : 20);
    return qBound(minimumStep, int(qCeil(plan.sourceToTarget * 3.2)), 28);
}

int radarReturnStep(const SamplePlan &plan, const QSize &targetSize)
{
    const int minimumStep = targetSize.width() >= 480 ? 2 : (targetSize.width() >= 180 ? 3 : 5);
    return qBound(minimumStep, int(qCeil(plan.sourceToTarget * 1.35)), 7);
}

void appendSampleLayer(RadarVectorRoot *root,
                       const QImage &image,
                       const QSize &targetSize,
                       bool circular,
                       const SamplePlan &plan,
                       int sampleStep,
                       qreal coverage,
                       int colorBucket,
                       ColorSampler sampler,
                       const char *label)
{
    const qreal bottomGuard = circular
        ? 0.0
        : qMax<qreal>(4.0, qMin(targetSize.width(), targetSize.height()) * 0.012);
    const QRectF itemBounds(0, 0, targetSize.width(), qMax<qreal>(1.0, targetSize.height() - bottomGuard));
    const qreal cellWidth = sampleStep * plan.scaleX;
    const qreal cellHeight = sampleStep * plan.scaleY;
    const qreal sampleWidth = qMax<qreal>(1.0, cellWidth * coverage);
    const qreal sampleHeight = qMax<qreal>(1.0, cellHeight * coverage);
    const qreal insetX = qMax<qreal>(0.0, (sampleWidth - cellWidth) * 0.5);
    const qreal insetY = qMax<qreal>(0.0, (sampleHeight - cellHeight) * 0.5);

    QHash<QRgb, QVector<RadarSample>> samplesByColor;
    int totalSamples = 0;
    for (int y = plan.top; y <= plan.bottom; y += sampleStep) {
        const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = plan.left; x <= plan.right; x += sampleStep) {
            QColor color;
            if (!sampler(line[x], color)) {
                continue;
            }
            const qreal itemX = (x - plan.sourceRect.left()) * plan.scaleX;
            const qreal itemY = (y - plan.sourceRect.top()) * plan.scaleY;
            if (circular) {
                const qreal dx = itemX - plan.clipCenter.x();
                const qreal dy = itemY - plan.clipCenter.y();
                if ((dx * dx) + (dy * dy) > plan.clipRadiusSquared) {
                    continue;
                }
            }
            const QRectF rect = QRectF(itemX - insetX,
                                       itemY - insetY,
                                       sampleWidth,
                                       sampleHeight)
                                    .intersected(itemBounds);
            if (rect.isEmpty()) {
                continue;
            }
            const QRgb key = quantizedColorKey(color, colorBucket);
            samplesByColor[key].append(RadarSample{rect});
            ++totalSamples;
        }
    }

    for (auto it = samplesByColor.constBegin(); it != samplesByColor.constEnd(); ++it) {
        if (auto *node = makeSampleNode(it.value(), colorFromKey(it.key()))) {
            root->appendChildNode(node);
        }
    }

    qInfo().noquote() << "[RadarFrameItem]" << label << "samples" << totalSamples
                      << "step" << sampleStep << "target"
                      << targetSize.width() << "x" << targetSize.height()
                      << "colors" << samplesByColor.size()
                      << "circular" << circular;
}

void appendBaseMapLayer(RadarVectorRoot *root,
                        const QImage &image,
                        const QSize &targetSize,
                        bool circular,
                        const SamplePlan &plan,
                        int blockStep)
{
    const qreal bottomGuard = circular
        ? 0.0
        : qMax<qreal>(4.0, qMin(targetSize.width(), targetSize.height()) * 0.012);
    const QRectF itemBounds(0, 0, targetSize.width(), qMax<qreal>(1.0, targetSize.height() - bottomGuard));
    const qreal cellWidth = blockStep * plan.scaleX;
    const qreal cellHeight = blockStep * plan.scaleY;
    const int sampleStride = qMax(2, blockStep / 4);

    QHash<QRgb, QVector<RadarSample>> samplesByColor;
    int totalSamples = 0;
    int acceptedBlocks = 0;
    for (int y = plan.top; y <= plan.bottom; y += blockStep) {
        for (int x = plan.left; x <= plan.right; x += blockStep) {
            int water = 0;
            int forest = 0;
            int road = 0;
            int land = 0;
            int valid = 0;
            int total = 0;
            const int yEnd = qMin(plan.bottom, y + blockStep - 1);
            const int xEnd = qMin(plan.right, x + blockStep - 1);
            for (int sy = y; sy <= yEnd; sy += sampleStride) {
                const QRgb *line = reinterpret_cast<const QRgb *>(image.constScanLine(sy));
                for (int sx = x; sx <= xEnd; sx += sampleStride) {
                    ++total;
                    const BaseMapClass klass = classifyBaseMapPixel(line[sx]);
                    switch (klass) {
                    case BaseMapClass::Water:
                        ++water;
                        ++valid;
                        break;
                    case BaseMapClass::Forest:
                        ++forest;
                        ++valid;
                        break;
                    case BaseMapClass::Road:
                        ++road;
                        ++valid;
                        break;
                    case BaseMapClass::Land:
                        ++land;
                        ++valid;
                        break;
                    case BaseMapClass::None:
                        break;
                    }
                }
            }

            ++totalSamples;
            if (valid < qMax(2, total / 4)) {
                continue;
            }

            BaseMapClass dominant = BaseMapClass::Land;
            int dominantCount = land;
            if (water > dominantCount) {
                dominant = BaseMapClass::Water;
                dominantCount = water;
            }
            if (forest > dominantCount) {
                dominant = BaseMapClass::Forest;
                dominantCount = forest;
            }
            if (road > dominantCount && road >= qMax(2, valid / 3)) {
                dominant = BaseMapClass::Road;
                dominantCount = road;
            }
            if (dominantCount < qMax(2, valid / 3)) {
                continue;
            }

            const qreal itemX = (x - plan.sourceRect.left()) * plan.scaleX;
            const qreal itemY = (y - plan.sourceRect.top()) * plan.scaleY;
            const QPointF center(itemX + cellWidth * 0.5, itemY + cellHeight * 0.5);
            if (circular) {
                const qreal dx = center.x() - plan.clipCenter.x();
                const qreal dy = center.y() - plan.clipCenter.y();
                if ((dx * dx) + (dy * dy) > plan.clipRadiusSquared) {
                    continue;
                }
            }

            const QRectF rect = QRectF(itemX,
                                       itemY,
                                       qMax<qreal>(1.0, cellWidth + 0.65),
                                       qMax<qreal>(1.0, cellHeight + 0.65))
                                    .intersected(itemBounds);
            if (rect.isEmpty()) {
                continue;
            }

            const QColor color = baseMapClassColor(dominant);
            if (!color.isValid()) {
                continue;
            }
            samplesByColor[quantizedColorKey(color, 8)].append(RadarSample{rect});
            ++acceptedBlocks;
        }
    }

    for (auto it = samplesByColor.constBegin(); it != samplesByColor.constEnd(); ++it) {
        if (auto *node = makeSampleNode(it.value(), colorFromKey(it.key()))) {
            root->appendChildNode(node);
        }
    }

    qInfo().noquote() << "[RadarFrameItem] base-map-blocks samples" << totalSamples
                      << "accepted" << acceptedBlocks
                      << "step" << blockStep << "target"
                      << targetSize.width() << "x" << targetSize.height()
                      << "colors" << samplesByColor.size()
                      << "circular" << circular;
}

void appendRadarSamples(RadarVectorRoot *root, const QImage &image, const QSize &targetSize, bool circular)
{
    const SamplePlan plan = makeSamplePlan(image, targetSize);
    const int baseStep = baseMapStep(plan, targetSize);
    const int returnStep = radarReturnStep(plan, targetSize);

    appendBaseMapLayer(root, image, targetSize, circular, plan, baseStep);
    appendSampleLayer(root,
                      image,
                      targetSize,
                      circular,
                      plan,
                      returnStep,
                      3.10,
                      32,
                      sampleRadarGlow,
                      "radar-glow");
    appendSampleLayer(root,
                      image,
                      targetSize,
                      circular,
                      plan,
                      returnStep,
                      1.48,
                      16,
                      sampleRadarCore,
                      "radar-core");
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
