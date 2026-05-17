#include "GaugeArcItem.h"

#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>

#include <QtMath>

#include <algorithm>
#include <vector>

namespace {
constexpr qreal kMinSweepRadians = 0.0001;

qreal clampProgress(qreal value)
{
    if (!qIsFinite(value)) {
        return 0.0;
    }
    return qBound(0.0, value, 1.0);
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

    const int cappedSegments = qBound(6, segments, 18);
    for (int i = 0; i < cappedSegments; ++i) {
        const qreal a0 = (2.0 * M_PI * i) / cappedSegments;
        const qreal a1 = (2.0 * M_PI * (i + 1)) / cappedSegments;
        appendTriangle(vertices,
                       center,
                       QPointF(center.x() + qCos(a0) * radius, center.y() + qSin(a0) * radius),
                       QPointF(center.x() + qCos(a1) * radius, center.y() + qSin(a1) * radius));
    }
}
} // namespace

GaugeArcItem::GaugeArcItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

void GaugeArcItem::setStartAngleDeg(qreal value)
{
    if (qFuzzyCompare(m_startAngleDeg, value)) {
        return;
    }
    m_startAngleDeg = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setSweepAngleDeg(qreal value)
{
    if (qFuzzyCompare(m_sweepAngleDeg, value)) {
        return;
    }
    m_sweepAngleDeg = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setStartProgress(qreal value)
{
    value = clampProgress(value);
    if (qFuzzyCompare(m_startProgress, value)) {
        return;
    }
    m_startProgress = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setEndProgress(qreal value)
{
    value = clampProgress(value);
    if (qFuzzyCompare(m_endProgress, value)) {
        return;
    }
    m_endProgress = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setRadiusFactor(qreal value)
{
    value = qMax(0.0, value);
    if (qFuzzyCompare(m_radiusFactor, value)) {
        return;
    }
    m_radiusFactor = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setStrokeWidth(qreal value)
{
    value = qMax(0.0, value);
    if (qFuzzyCompare(m_strokeWidth, value)) {
        return;
    }
    m_strokeWidth = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setColor(const QColor &value)
{
    if (m_color == value) {
        return;
    }
    m_color = value;
    update();
    emit colorChanged();
}

void GaugeArcItem::setSegments(int value)
{
    value = qBound(8, value, 192);
    if (m_segments == value) {
        return;
    }
    m_segments = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::setRoundedCaps(bool value)
{
    if (m_roundedCaps == value) {
        return;
    }
    m_roundedCaps = value;
    scheduleGeometryUpdate();
}

void GaugeArcItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        scheduleGeometryUpdate();
    }
}

void GaugeArcItem::scheduleGeometryUpdate()
{
    update();
    emit geometryChanged();
}

QSGNode *GaugeArcItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const qreal itemWidth = width();
    const qreal itemHeight = height();
    const qreal diameter = qMin(itemWidth, itemHeight);
    const qreal stroke = m_strokeWidth;
    const qreal radius = diameter * m_radiusFactor;

    qreal startProgress = clampProgress(m_startProgress);
    qreal endProgress = clampProgress(m_endProgress);
    if (endProgress < startProgress) {
        std::swap(startProgress, endProgress);
    }

    const qreal sweepRadians = qDegreesToRadians(m_sweepAngleDeg) * (endProgress - startProgress);
    if (itemWidth <= 0.0
        || itemHeight <= 0.0
        || radius <= 0.0
        || stroke <= 0.0
        || qAbs(sweepRadians) <= kMinSweepRadians
        || !m_color.isValid()
        || m_color.alpha() == 0) {
        delete oldNode;
        return nullptr;
    }

    auto *node = static_cast<QSGGeometryNode *>(oldNode);
    if (!node) {
        node = new QSGGeometryNode;
        auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), 0);
        geometry->setDrawingMode(QSGGeometry::DrawTriangles);
        node->setGeometry(geometry);
        node->setFlag(QSGNode::OwnsGeometry);

        auto *material = new QSGFlatColorMaterial;
        material->setColor(m_color);
        node->setMaterial(material);
        node->setFlag(QSGNode::OwnsMaterial);
    }

    const QPointF center(itemWidth / 2.0, itemHeight / 2.0);
    const qreal halfStroke = stroke / 2.0;
    const qreal innerRadius = qMax(0.0, radius - halfStroke);
    const qreal outerRadius = radius + halfStroke;
    const qreal startRadians = qDegreesToRadians(m_startAngleDeg - 90.0)
        + qDegreesToRadians(m_sweepAngleDeg) * startProgress;
    const qreal endRadians = startRadians + sweepRadians;
    const int segmentCount = qBound(1,
                                    int(qCeil(qAbs(sweepRadians) / (2.0 * M_PI) * m_segments)),
                                    m_segments);

    auto point = [center](qreal angle, qreal pointRadius) {
        return QPointF(center.x() + qCos(angle) * pointRadius,
                       center.y() + qSin(angle) * pointRadius);
    };

    std::vector<QPointF> vertices;
    vertices.reserve((segmentCount * 2 + 36) * 3);

    for (int i = 0; i < segmentCount; ++i) {
        const qreal t0 = qreal(i) / segmentCount;
        const qreal t1 = qreal(i + 1) / segmentCount;
        const qreal a0 = startRadians + sweepRadians * t0;
        const qreal a1 = startRadians + sweepRadians * t1;

        const QPointF outer0 = point(a0, outerRadius);
        const QPointF inner0 = point(a0, innerRadius);
        const QPointF outer1 = point(a1, outerRadius);
        const QPointF inner1 = point(a1, innerRadius);

        appendTriangle(vertices, outer0, inner0, outer1);
        appendTriangle(vertices, outer1, inner0, inner1);
    }

    if (m_roundedCaps) {
        appendDisc(vertices, point(startRadians, radius), halfStroke, 12);
        appendDisc(vertices, point(endRadians, radius), halfStroke, 12);
    }

    auto *geometry = node->geometry();
    geometry->allocate(int(vertices.size()));
    auto *points = geometry->vertexDataAsPoint2D();
    for (int i = 0; i < int(vertices.size()); ++i) {
        points[i].set(float(vertices[i].x()), float(vertices[i].y()));
    }

    auto *material = static_cast<QSGFlatColorMaterial *>(node->material());
    material->setColor(m_color);
    node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
    return node;
}
