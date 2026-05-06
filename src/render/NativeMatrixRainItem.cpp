#include "NativeMatrixRainItem.h"

#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGNode>
#include <QSize>
#include <QVector>
#include <QtGlobal>
#include <QtMath>

#include <array>
#include <cmath>

namespace {
class MatrixRainRoot final : public QSGNode
{
public:
    int revision = -1;
    int geometryRevision = -1;
    QSize size;
};

struct RainRect {
    QRectF rect;
};

uint hash32(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

qreal unitHash(uint value)
{
    return qreal(hash32(value) & 0x00ffffffu) / qreal(0x01000000u);
}

QColor withAlpha(const QColor &color, qreal alpha)
{
    QColor out(color);
    out.setAlphaF(qBound<qreal>(0.0, alpha, 1.0));
    return out;
}

QSGGeometryNode *makeRectsNode(const QVector<RainRect> &rects, const QColor &color)
{
    if (rects.isEmpty()) {
        return nullptr;
    }

    auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(), rects.size() * 6);
    geometry->setDrawingMode(QSGGeometry::DrawTriangles);
    QSGGeometry::Point2D *vertices = geometry->vertexDataAsPoint2D();

    int cursor = 0;
    for (const RainRect &sample : rects) {
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

bool rectInsideMask(const QRectF &rect, const QPointF &center, qreal radius)
{
    if (radius <= 0.0) {
        return false;
    }
    const QPointF p = rect.center();
    const qreal dx = p.x() - center.x();
    const qreal dy = p.y() - center.y();
    return (dx * dx) + (dy * dy) <= radius * radius;
}
} // namespace

NativeMatrixRainItem::NativeMatrixRainItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
}

NativeMatrixRainItem::~NativeMatrixRainItem() = default;

void NativeMatrixRainItem::markDirty()
{
    ++m_revision;
    update();
}

void NativeMatrixRainItem::setRainColor(const QColor &color)
{
    if (m_rainColor == color) {
        return;
    }
    m_rainColor = color;
    markDirty();
    emit rainColorChanged();
}

void NativeMatrixRainItem::setGlowColor(const QColor &color)
{
    if (m_glowColor == color) {
        return;
    }
    m_glowColor = color;
    markDirty();
    emit glowColorChanged();
}

void NativeMatrixRainItem::setEffectEnabled(bool enabled)
{
    if (m_effectEnabled == enabled) {
        return;
    }
    m_effectEnabled = enabled;
    markDirty();
    emit effectEnabledChanged();
}

void NativeMatrixRainItem::setEffectLevel(const QString &level)
{
    const QString normalized = level.trimmed().toLower();
    if (m_effectLevel == normalized) {
        return;
    }
    m_effectLevel = normalized;
    markDirty();
    emit effectLevelChanged();
}

void NativeMatrixRainItem::setPhase(qreal phase)
{
    if (qFuzzyCompare(m_phase, phase)) {
        return;
    }
    m_phase = phase;
    markDirty();
    emit phaseChanged();
}

void NativeMatrixRainItem::setColumns(int columns)
{
    columns = qMax(0, columns);
    if (m_columns == columns) {
        return;
    }
    m_columns = columns;
    markDirty();
    emit columnsChanged();
}

void NativeMatrixRainItem::setFontPx(int fontPx)
{
    fontPx = qBound(6, fontPx, 64);
    if (m_fontPx == fontPx) {
        return;
    }
    m_fontPx = fontPx;
    markDirty();
    emit fontPxChanged();
}

void NativeMatrixRainItem::setDensity(qreal density)
{
    density = qBound<qreal>(0.0, density, 1.0);
    if (qFuzzyCompare(m_density, density)) {
        return;
    }
    m_density = density;
    markDirty();
    emit densityChanged();
}

void NativeMatrixRainItem::setSpeedMultiplier(qreal multiplier)
{
    multiplier = qBound<qreal>(0.01, multiplier, 4.0);
    if (qFuzzyCompare(m_speedMultiplier, multiplier)) {
        return;
    }
    m_speedMultiplier = multiplier;
    markDirty();
    emit speedMultiplierChanged();
}

void NativeMatrixRainItem::setDriftScale(qreal scale)
{
    scale = qBound<qreal>(0.01, scale, 4.0);
    if (qFuzzyCompare(m_driftScale, scale)) {
        return;
    }
    m_driftScale = scale;
    markDirty();
    emit driftScaleChanged();
}

void NativeMatrixRainItem::setTailLength(int tailLength)
{
    tailLength = qBound(1, tailLength, 64);
    if (m_tailLength == tailLength) {
        return;
    }
    m_tailLength = tailLength;
    markDirty();
    emit tailLengthChanged();
}

void NativeMatrixRainItem::setHeadAlpha(qreal alpha)
{
    alpha = qBound<qreal>(0.0, alpha, 1.0);
    if (qFuzzyCompare(m_headAlpha, alpha)) {
        return;
    }
    m_headAlpha = alpha;
    markDirty();
    emit headAlphaChanged();
}

void NativeMatrixRainItem::setTailMinAlpha(qreal alpha)
{
    alpha = qBound<qreal>(0.0, alpha, 1.0);
    if (qFuzzyCompare(m_tailMinAlpha, alpha)) {
        return;
    }
    m_tailMinAlpha = alpha;
    markDirty();
    emit tailMinAlphaChanged();
}

void NativeMatrixRainItem::setCircularMask(bool enabled)
{
    if (m_circularMask == enabled) {
        return;
    }
    m_circularMask = enabled;
    markDirty();
    emit circularMaskChanged();
}

void NativeMatrixRainItem::setMaskCenterX(qreal value)
{
    if (qFuzzyCompare(m_maskCenterX, value)) {
        return;
    }
    m_maskCenterX = value;
    markDirty();
    emit maskCenterXChanged();
}

void NativeMatrixRainItem::setMaskCenterY(qreal value)
{
    if (qFuzzyCompare(m_maskCenterY, value)) {
        return;
    }
    m_maskCenterY = value;
    markDirty();
    emit maskCenterYChanged();
}

void NativeMatrixRainItem::setMaskRadius(qreal value)
{
    value = qMax<qreal>(0.0, value);
    if (qFuzzyCompare(m_maskRadius, value)) {
        return;
    }
    m_maskRadius = value;
    markDirty();
    emit maskRadiusChanged();
}

void NativeMatrixRainItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        ++m_geometryRevision;
        update();
    }
}

QSGNode *NativeMatrixRainItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const int itemWidth = qMax(1, int(width()));
    const int itemHeight = qMax(1, int(height()));
    if (!m_effectEnabled || m_effectLevel == QLatin1String("off") || itemWidth <= 1 || itemHeight <= 1) {
        delete oldNode;
        return nullptr;
    }

    const QSize targetSize(itemWidth, itemHeight);
    auto *root = static_cast<MatrixRainRoot *>(oldNode);
    const bool rebuild = !root
        || root->revision != m_revision
        || root->geometryRevision != m_geometryRevision
        || root->size != targetSize;
    if (!rebuild) {
        return root;
    }

    delete root;
    root = new MatrixRainRoot;
    root->revision = m_revision;
    root->geometryRevision = m_geometryRevision;
    root->size = targetSize;

    constexpr int kBuckets = 7;
    std::array<QVector<RainRect>, kBuckets> rainBuckets;
    std::array<QVector<RainRect>, 3> glowBuckets;

    const qreal fontPx = qBound<qreal>(6.0, m_fontPx, 64.0);
    const qreal colWidth = fontPx + 3.0;
    const int columns = m_columns > 0 ? m_columns : qMax(1, int(qFloor(itemWidth / colWidth)));
    const qreal activeDensity = qBound<qreal>(0.0, m_density, 1.0);
    const int tailLength = qBound(3, m_tailLength, 44);
    const bool lowMode = m_effectLevel == QLatin1String("low");
    const qreal speedCells = (lowMode ? 0.46 : 0.74)
        * qBound<qreal>(0.25, m_speedMultiplier * 7.0, 2.2)
        * qBound<qreal>(0.35, m_driftScale * 5.0, 1.6);
    const QPointF maskCenter(m_maskCenterX, m_maskCenterY);
    const qreal maskRadius = m_maskRadius;

    for (int column = 0; column < columns; ++column) {
        const qreal activeNoise = unitHash(uint(column + 1) * 977u);
        if (activeNoise > activeDensity) {
            continue;
        }

        const qreal offsetCells = unitHash(uint(column + 17) * 1879u)
            * (qreal(itemHeight) / fontPx + tailLength);
        const qreal pulse = 0.62 + 0.38 * qSin((m_phase * 1.15) + column * 0.73);
        const qreal drift = qSin((m_phase * 0.62) + column * 1.41) * qMin<qreal>(5.0, fontPx * 0.18);
        const qreal cycleCells = qreal(itemHeight) / fontPx + tailLength;
        qreal head = std::fmod(offsetCells + (m_phase * speedCells), cycleCells);
        if (head < 0.0) {
            head += cycleCells;
        }
        qreal x = column * colWidth + drift;
        const qreal cellW = qMax<qreal>(2.0, fontPx * (0.34 + 0.30 * unitHash(uint(column + 47) * 1291u)));
        const qreal cellH = qMax<qreal>(3.0, fontPx * 0.74);
        const qreal xInset = qMax<qreal>(0.0, (colWidth - cellW) * 0.5);

        for (int tail = 0; tail <= tailLength; ++tail) {
            const qreal row = head - tail;
            const qreal y = row * fontPx;
            if (y < -cellH || y > itemHeight + cellH) {
                continue;
            }

            const qreal falloff = 1.0 - (qreal(tail) / qreal(qMax(1, tailLength)));
            const qreal flicker = 0.72 + 0.28 * unitHash(uint(column * 4099 + tail * 811 + int(m_phase * 3.0)));
            const qreal alpha = (m_tailMinAlpha + (m_headAlpha - m_tailMinAlpha) * falloff) * pulse * flicker;
            if (alpha < 0.012) {
                continue;
            }

            const qreal segmentShrink = tail == 0 ? 0.0 : (1.0 - falloff) * cellW * 0.22;
            QRectF rect(x + xInset + segmentShrink * 0.5,
                        y,
                        qMax<qreal>(1.4, cellW - segmentShrink),
                        cellH);
            if (m_circularMask && !rectInsideMask(rect, maskCenter, maskRadius)) {
                continue;
            }

            if (tail == 0) {
                const int glowBucket = qBound(0, int(qFloor(alpha * 3.0)), 2);
                glowBuckets[glowBucket].append({rect.adjusted(-1.0, -1.0, 1.0, 1.0)});
            }
            const int bucket = qBound(0, int(qFloor(alpha * kBuckets)), kBuckets - 1);
            rainBuckets[bucket].append({rect});
        }
    }

    for (int i = 0; i < int(glowBuckets.size()); ++i) {
        const qreal alpha = (0.07 + i * 0.055);
        if (auto *node = makeRectsNode(glowBuckets[i], withAlpha(m_glowColor, alpha))) {
            root->appendChildNode(node);
        }
    }
    for (int i = 0; i < kBuckets; ++i) {
        const qreal alpha = qBound<qreal>(0.018, 0.035 + i * 0.052, 0.48);
        if (auto *node = makeRectsNode(rainBuckets[i], withAlpha(m_rainColor, alpha))) {
            root->appendChildNode(node);
        }
    }

    return root;
}
