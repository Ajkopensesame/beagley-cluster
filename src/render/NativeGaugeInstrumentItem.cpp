#include "NativeGaugeInstrumentItem.h"

#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>

#include <QtMath>

#include <algorithm>
#include <vector>

namespace {
constexpr qreal kPrimaryStartDeg = 225.0;
constexpr qreal kPrimarySweepDeg = 210.0;
constexpr qreal kAuxStartDeg = 87.0;
constexpr qreal kAuxSweepDeg = 126.0;

qreal finiteOr(qreal value, qreal fallback)
{
    return qIsFinite(value) ? value : fallback;
}

qreal clampProgress(qreal value)
{
    return qBound(0.0, finiteOr(value, 0.0), 1.0);
}

QColor withAlpha(QColor color, int alpha)
{
    color.setAlpha(qBound(0, alpha, 255));
    return color;
}

qreal angleRadians(qreal degrees)
{
    return qDegreesToRadians(degrees - 90.0);
}

QPointF polarPoint(const QPointF &center, qreal angle, qreal radius)
{
    return QPointF(center.x() + qCos(angle) * radius,
                   center.y() + qSin(angle) * radius);
}

void appendTriangle(std::vector<QPointF> &vertices,
                    const QPointF &a,
                    const QPointF &b,
                    const QPointF &c)
{
    vertices.push_back(a);
    vertices.push_back(b);
    vertices.push_back(c);
}

void appendDisc(std::vector<QPointF> &vertices, const QPointF &center, qreal radius, int segments)
{
    if (radius <= 0.0 || segments < 3) {
        return;
    }

    const int cappedSegments = qBound(12, segments, 96);
    for (int i = 0; i < cappedSegments; ++i) {
        const qreal a0 = (2.0 * M_PI * i) / cappedSegments;
        const qreal a1 = (2.0 * M_PI * (i + 1)) / cappedSegments;
        appendTriangle(vertices,
                       center,
                       polarPoint(center, a0, radius),
                       polarPoint(center, a1, radius));
    }
}

void appendArcBand(std::vector<QPointF> &vertices,
                   const QPointF &center,
                   qreal radius,
                   qreal strokeWidth,
                   qreal startDeg,
                   qreal sweepDeg,
                   qreal startProgress,
                   qreal endProgress,
                   int segments,
                   bool roundedCaps)
{
    if (radius <= 0.0 || strokeWidth <= 0.0 || segments < 1) {
        return;
    }

    startProgress = clampProgress(startProgress);
    endProgress = clampProgress(endProgress);
    if (endProgress < startProgress) {
        std::swap(startProgress, endProgress);
    }

    const qreal actualSweepDeg = sweepDeg * (endProgress - startProgress);
    if (qAbs(actualSweepDeg) < 0.01) {
        return;
    }

    const qreal startAngle = angleRadians(startDeg + sweepDeg * startProgress);
    const qreal sweepAngle = qDegreesToRadians(actualSweepDeg);
    const qreal halfStroke = strokeWidth * 0.5;
    const qreal innerRadius = qMax(0.0, radius - halfStroke);
    const qreal outerRadius = radius + halfStroke;
    const int segmentCount = qBound(1,
                                    int(qCeil(qAbs(actualSweepDeg) / qMax(1.0, qAbs(sweepDeg)) * segments)),
                                    qMax(1, segments));

    for (int i = 0; i < segmentCount; ++i) {
        const qreal t0 = qreal(i) / segmentCount;
        const qreal t1 = qreal(i + 1) / segmentCount;
        const qreal a0 = startAngle + sweepAngle * t0;
        const qreal a1 = startAngle + sweepAngle * t1;

        const QPointF outer0 = polarPoint(center, a0, outerRadius);
        const QPointF inner0 = polarPoint(center, a0, innerRadius);
        const QPointF outer1 = polarPoint(center, a1, outerRadius);
        const QPointF inner1 = polarPoint(center, a1, innerRadius);

        appendTriangle(vertices, outer0, inner0, outer1);
        appendTriangle(vertices, outer1, inner0, inner1);
    }

    if (roundedCaps) {
        appendDisc(vertices, polarPoint(center, startAngle, radius), halfStroke, 16);
        appendDisc(vertices, polarPoint(center, startAngle + sweepAngle, radius), halfStroke, 16);
    }
}

void appendTick(std::vector<QPointF> &vertices,
                const QPointF &center,
                qreal angle,
                qreal innerRadius,
                qreal outerRadius,
                qreal halfWidth)
{
    const QPointF inner = polarPoint(center, angle, innerRadius);
    const QPointF outer = polarPoint(center, angle, outerRadius);
    const QPointF tangent(-qSin(angle) * halfWidth, qCos(angle) * halfWidth);

    const QPointF p0 = inner + tangent;
    const QPointF p1 = inner - tangent;
    const QPointF p2 = outer + tangent;
    const QPointF p3 = outer - tangent;
    appendTriangle(vertices, p2, p0, p3);
    appendTriangle(vertices, p3, p0, p1);
}

QSGGeometryNode *createGeometryNode(const QColor &color)
{
    auto *node = new QSGGeometryNode;
    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    node->setGeometry(geometry);
    node->setFlag(QSGNode::OwnsGeometry);

    auto *material = new QSGFlatColorMaterial;
    material->setColor(color);
    node->setMaterial(material);
    node->setFlag(QSGNode::OwnsMaterial);
    return node;
}

void setGeometry(QSGGeometryNode *node, const std::vector<QPointF> &vertices, const QColor &color)
{
    auto *geometry = node->geometry();
    geometry->allocate(int(vertices.size()));
    auto *points = geometry->vertexDataAsPoint2D();
    for (int i = 0; i < int(vertices.size()); ++i) {
        points[i].set(float(vertices[i].x()), float(vertices[i].y()));
    }
    static_cast<QSGFlatColorMaterial *>(node->material())->setColor(color);
    node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
}

class NativeGaugeNode final : public QSGNode
{
public:
    NativeGaugeNode()
        : background(createGeometryNode(QColor(QStringLiteral("#03070E"))))
        , track(createGeometryNode(QColor(Qt::white)))
        , auxTrack(createGeometryNode(QColor(Qt::white)))
        , ticks(createGeometryNode(QColor(Qt::white)))
        , primaryArc(createGeometryNode(QColor(Qt::white)))
        , auxArc(createGeometryNode(QColor(Qt::white)))
        , centerDot(createGeometryNode(QColor(Qt::white)))
    {
        appendChildNode(background);
        appendChildNode(track);
        appendChildNode(auxTrack);
        appendChildNode(ticks);
        appendChildNode(primaryArc);
        appendChildNode(auxArc);
        appendChildNode(centerDot);
    }

    QSGGeometryNode *background = nullptr;
    QSGGeometryNode *track = nullptr;
    QSGGeometryNode *auxTrack = nullptr;
    QSGGeometryNode *ticks = nullptr;
    QSGGeometryNode *primaryArc = nullptr;
    QSGGeometryNode *auxArc = nullptr;
    QSGGeometryNode *centerDot = nullptr;
    QSizeF geometrySize;
    int staticRevision = -1;
    int dynamicRevision = -1;
};
} // namespace

NativeGaugeInstrumentItem::NativeGaugeInstrumentItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

NativeGaugeInstrumentItem::~NativeGaugeInstrumentItem() = default;

void NativeGaugeInstrumentItem::setKind(const QString &value)
{
    const QString normalized = value.trimmed().toLower();
    const QString next = normalized == QLatin1String("tach") ? QStringLiteral("tach") : QStringLiteral("speed");
    if (m_kind == next) {
        return;
    }
    m_kind = next;
    invalidateStaticGeometry();
    invalidateDynamicGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setValue(qreal value)
{
    value = qMax(0.0, finiteOr(value, 0.0));
    if (qFuzzyCompare(m_value, value)) {
        return;
    }
    m_value = value;
    invalidateDynamicGeometry();
    emit valueChanged();
}

void NativeGaugeInstrumentItem::setMaxValue(qreal value)
{
    value = qMax(1.0, finiteOr(value, 1.0));
    if (qFuzzyCompare(m_maxValue, value)) {
        return;
    }
    m_maxValue = value;
    invalidateDynamicGeometry();
    emit geometryInputChanged();
}

void NativeGaugeInstrumentItem::setAuxProgress(qreal value)
{
    value = clampProgress(value);
    if (qFuzzyCompare(m_auxProgress, value)) {
        return;
    }
    m_auxProgress = value;
    invalidateDynamicGeometry();
    emit geometryInputChanged();
}

void NativeGaugeInstrumentItem::setPrimaryColor(const QColor &value)
{
    if (m_primaryColor == value) {
        return;
    }
    m_primaryColor = value;
    invalidateDynamicGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setAuxColor(const QColor &value)
{
    if (m_auxColor == value) {
        return;
    }
    m_auxColor = value;
    invalidateDynamicGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setChromeColor(const QColor &value)
{
    if (m_chromeColor == value) {
        return;
    }
    m_chromeColor = value;
    invalidateStaticGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setLowEffectMode(bool value)
{
    if (m_lowEffectMode == value) {
        return;
    }
    m_lowEffectMode = value;
    invalidateStaticGeometry();
    invalidateDynamicGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        invalidateStaticGeometry();
        invalidateDynamicGeometry();
    }
}

void NativeGaugeInstrumentItem::invalidateStaticGeometry()
{
    ++m_staticRevision;
    update();
}

void NativeGaugeInstrumentItem::invalidateDynamicGeometry()
{
    ++m_dynamicRevision;
    update();
}

QSGNode *NativeGaugeInstrumentItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const qreal itemWidth = width();
    const qreal itemHeight = height();
    const qreal side = qMin(itemWidth, itemHeight);
    if (side <= 4.0) {
        delete oldNode;
        return nullptr;
    }

    auto *node = static_cast<NativeGaugeNode *>(oldNode);
    if (!node) {
        node = new NativeGaugeNode;
    }

    const QSizeF itemSize(itemWidth, itemHeight);
    const bool sizeChanged = node->geometrySize != itemSize;
    const bool staticChanged = sizeChanged || node->staticRevision != m_staticRevision;
    const bool dynamicChanged = sizeChanged || node->dynamicRevision != m_dynamicRevision;
    if (!staticChanged && !dynamicChanged) {
        return node;
    }

    const QPointF center(itemWidth * 0.5, itemHeight * 0.5);
    const qreal radius = side * 0.405;
    const qreal stroke = side * (m_lowEffectMode ? 0.020 : 0.024);
    const qreal auxStroke = side * 0.014;
    const qreal auxRadius = side * 0.360;
    const int arcSegments = m_lowEffectMode ? 96 : 128;
    if (staticChanged) {
        std::vector<QPointF> backgroundVertices;
        std::vector<QPointF> trackVertices;
        std::vector<QPointF> auxTrackVertices;
        std::vector<QPointF> tickVertices;
        std::vector<QPointF> centerVertices;

        appendDisc(backgroundVertices, center, side * 0.414, 64);
        appendArcBand(trackVertices, center, radius, stroke, kPrimaryStartDeg, kPrimarySweepDeg, 0.0, 1.0, arcSegments, true);
        appendArcBand(auxTrackVertices, center, auxRadius, auxStroke, kAuxStartDeg, kAuxSweepDeg, 0.0, 1.0, 64, true);
        appendDisc(centerVertices, center, side * 0.0085, 18);

        const int minorCount = m_kind == QLatin1String("tach") ? 16 : 14;
        const int majorEvery = 2;
        for (int i = 0; i <= minorCount; ++i) {
            const qreal progress = qreal(i) / qreal(minorCount);
            const qreal angle = angleRadians(kPrimaryStartDeg + kPrimarySweepDeg * progress);
            const bool major = (i % majorEvery) == 0;
            appendTick(tickVertices,
                       center,
                       angle,
                       radius - stroke * (major ? 2.25 : 1.50),
                       radius + stroke * (major ? 1.75 : 1.15),
                       stroke * (major ? 0.18 : 0.115));
        }

        setGeometry(node->background, backgroundVertices, withAlpha(QColor(QStringLiteral("#010309")), 254));
        setGeometry(node->track, trackVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 48 : 62));
        setGeometry(node->auxTrack, auxTrackVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 44 : 58));
        setGeometry(node->ticks, tickVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 132 : 160));
        setGeometry(node->centerDot, centerVertices, withAlpha(m_chromeColor, 150));
        node->staticRevision = m_staticRevision;
    }

    if (dynamicChanged) {
        const qreal mainProgress = clampProgress(m_value / qMax(1.0, m_maxValue));
        std::vector<QPointF> primaryVertices;
        std::vector<QPointF> auxVertices;

        appendArcBand(primaryVertices, center, radius, stroke, kPrimaryStartDeg, kPrimarySweepDeg, 0.0, mainProgress, arcSegments, true);
        appendArcBand(auxVertices, center, auxRadius, auxStroke, kAuxStartDeg, kAuxSweepDeg, 1.0 - m_auxProgress, 1.0, 64, true);
        setGeometry(node->primaryArc, primaryVertices, withAlpha(m_primaryColor, 235));
        setGeometry(node->auxArc, auxVertices, withAlpha(m_auxColor, 224));
        node->dynamicRevision = m_dynamicRevision;
    }

    node->geometrySize = itemSize;
    return node;
}
