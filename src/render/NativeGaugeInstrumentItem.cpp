#include "NativeGaugeInstrumentItem.h"

#include <QFont>
#include <QImage>
#include <QPainter>
#include <QQuickWindow>
#include <QSGFlatColorMaterial>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGSimpleTextureNode>
#include <QSGTexture>
#include <QTimer>

#include <QtMath>

#include <algorithm>
#include <vector>

namespace {
constexpr qreal kPrimaryStartDeg = 225.0;
constexpr qreal kPrimarySweepDeg = 270.0;
constexpr qreal kAuxStartDeg = 242.0;
constexpr qreal kAuxSweepDeg = -124.0;

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

QString formatMainValue(const QString &kind, qreal value)
{
    if (kind == QLatin1String("tach")) {
        return QString::number(qRound(finiteOr(value, 0.0) / 100.0) / 10.0, 'f', 1);
    }
    return QString::number(qRound(finiteOr(value, 0.0)));
}

QString formatLabelValue(const QString &kind, int label)
{
    if (kind == QLatin1String("tach")) {
        return QString::number(label / 1000);
    }
    return QString::number(label);
}

void drawCenteredText(QPainter &painter,
                      const QRectF &rect,
                      const QString &text,
                      const QFont &font,
                      const QColor &color,
                      int flags = Qt::AlignCenter)
{
    if (text.isEmpty()) {
        return;
    }
    painter.setFont(font);
    painter.setPen(color);
    painter.drawText(rect, flags, text);
}

QImage renderTextImage(const QSize &size,
                       const QString &kind,
                       qreal value,
                       qreal auxProgress,
                       const QColor &primaryColor,
                       const QColor &auxColor,
                       const QColor &chromeColor,
                       const QString &centerText,
                       const QString &statusText,
                       const QString &bottomText,
                       const QString &bottomSubText,
                       const QString &driveModeText,
                       bool overdrive,
                       bool highBeam)
{
    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);

    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::TextAntialiasing, true);

    const qreal side = qMin(size.width(), size.height());
    const QPointF center(size.width() * 0.5, size.height() * 0.5);
    const qreal labelRadius = side * 0.355;
    const bool tach = kind == QLatin1String("tach");

    const QFont labelFont(QStringLiteral("Oxanium"), int(side * 0.036), QFont::DemiBold);
    const QFont unitFont(QStringLiteral("Oxanium"), int(side * 0.042), QFont::DemiBold);
    const QFont mainFont(QStringLiteral("Oxanium"), int(tach ? side * 0.150 : side * 0.185), QFont::DemiBold);
    const QFont centerFont(QStringLiteral("Oxanium"), int(side * 0.076), QFont::DemiBold);
    const QFont smallFont(QStringLiteral("Oxanium"), int(side * 0.034), QFont::DemiBold);
    const QFont microFont(QStringLiteral("Oxanium"), int(side * 0.026), QFont::DemiBold);

    const int labelMax = tach ? 8000 : 140;
    const int labelStep = tach ? 1000 : 20;
    for (int label = labelStep; label <= labelMax; label += labelStep) {
        const qreal progress = qreal(label) / qreal(labelMax);
        const qreal angle = angleRadians(kPrimaryStartDeg + kPrimarySweepDeg * progress);
        const QPointF pos = polarPoint(center, angle, labelRadius);
        QRectF rect(pos.x() - side * 0.045, pos.y() - side * 0.026, side * 0.09, side * 0.052);
        drawCenteredText(painter, rect, formatLabelValue(kind, label), labelFont, withAlpha(chromeColor, 190));
    }

    painter.setPen(Qt::NoPen);
    painter.setBrush(withAlpha(primaryColor, 34));
    painter.drawEllipse(center, side * 0.118, side * 0.118);

    drawCenteredText(painter,
                     QRectF(center.x() - side * 0.22, center.y() - side * 0.18, side * 0.44, side * 0.20),
                     formatMainValue(kind, value),
                     mainFont,
                     QColor(QStringLiteral("#F6F0FF")));
    drawCenteredText(painter,
                     QRectF(center.x() - side * 0.18, center.y() - side * 0.010, side * 0.36, side * 0.075),
                     tach ? QStringLiteral("RPM x1000") : QStringLiteral("KPH"),
                     unitFont,
                     withAlpha(chromeColor, 210));

    if (tach) {
        const QRectF topRect(center.x() - side * 0.16, center.y() - side * 0.300, side * 0.32, side * 0.070);
        drawCenteredText(painter, topRect, centerText.isEmpty() ? QStringLiteral("DRIVE") : centerText, smallFont, withAlpha(chromeColor, 210));

        const qreal railY = center.y() + side * 0.145;
        const qreal railW = side * 0.245;
        const qreal nodeR = side * 0.014;
        QPen railPen(withAlpha(chromeColor, 135), qMax(2.0, side * 0.006), Qt::SolidLine, Qt::RoundCap);
        painter.setPen(railPen);
        painter.drawLine(QPointF(center.x() - railW * 0.5, railY), QPointF(center.x() + railW * 0.5, railY));
        painter.setPen(Qt::NoPen);
        painter.setBrush(withAlpha(primaryColor, 220));
        painter.drawEllipse(QPointF(center.x() - railW * 0.5, railY), nodeR, nodeR);
        painter.drawEllipse(QPointF(center.x() + railW * 0.5, railY), nodeR, nodeR);
        painter.setBrush(withAlpha(chromeColor, 165));
        painter.drawEllipse(QPointF(center.x(), railY), nodeR * 0.78, nodeR * 0.78);

        drawCenteredText(painter,
                         QRectF(center.x() - side * 0.18, railY + side * 0.020, side * 0.36, side * 0.060),
                         driveModeText.isEmpty() ? QStringLiteral("2WD") : driveModeText,
                         smallFont,
                         withAlpha(primaryColor, 230));
        if (highBeam) {
            painter.setPen(QPen(withAlpha(QColor(QStringLiteral("#59D8FF")), 220), qMax(2.0, side * 0.006)));
            painter.setBrush(withAlpha(QColor(QStringLiteral("#59D8FF")), 28));
            painter.drawEllipse(QPointF(center.x(), center.y() + side * 0.285), side * 0.043, side * 0.043);
            drawCenteredText(painter,
                             QRectF(center.x() - side * 0.045, center.y() + side * 0.256, side * 0.09, side * 0.058),
                             QStringLiteral("HI"),
                             microFont,
                             QColor(QStringLiteral("#C7F3FF")));
        }
    } else {
        drawCenteredText(painter,
                         QRectF(center.x() - side * 0.060, center.y() - side * 0.318, side * 0.120, side * 0.100),
                         centerText.isEmpty() ? QStringLiteral("-") : centerText.left(2).toUpper(),
                         centerFont,
                         primaryColor);

        const QString odText = bottomText.isEmpty() ? QStringLiteral("------") : bottomText;
        drawCenteredText(painter,
                         QRectF(center.x() - side * 0.18, center.y() + side * 0.140, side * 0.36, side * 0.060),
                         odText,
                         smallFont,
                         withAlpha(chromeColor, 220));
        drawCenteredText(painter,
                         QRectF(center.x() - side * 0.18, center.y() + side * 0.190, side * 0.36, side * 0.040),
                         bottomSubText.isEmpty() ? QStringLiteral("KM") : bottomSubText,
                         microFont,
                         withAlpha(chromeColor, 155));

        const QString status = !statusText.isEmpty()
            ? statusText
            : (overdrive ? QStringLiteral("O/D") : QString());
        drawCenteredText(painter,
                         QRectF(center.x() - side * 0.18, center.y() + side * 0.250, side * 0.36, side * 0.054),
                         status,
                         smallFont,
                         withAlpha(primaryColor, status.isEmpty() ? 0 : 225));
    }

    const QString auxLeft = tach ? QStringLiteral("E") : QStringLiteral("C");
    const QString auxRight = tach ? QStringLiteral("F") : QStringLiteral("H");
    const QString auxCenter = tach ? QStringLiteral("FUEL") : QStringLiteral("COOLANT");
    const qreal auxRadius = side * 0.272;
    const qreal auxY = center.y() + side * 0.330;
    Q_UNUSED(auxProgress);
    drawCenteredText(painter,
                     QRectF(center.x() - auxRadius - side * 0.030, auxY - side * 0.020, side * 0.060, side * 0.040),
                     auxLeft,
                     microFont,
                     withAlpha(auxColor, 190));
    drawCenteredText(painter,
                     QRectF(center.x() + auxRadius - side * 0.030, auxY - side * 0.020, side * 0.060, side * 0.040),
                     auxRight,
                     microFont,
                     withAlpha(auxColor, 190));
    drawCenteredText(painter,
                     QRectF(center.x() - side * 0.12, auxY - side * 0.030, side * 0.24, side * 0.040),
                     auxCenter,
                     microFont,
                     withAlpha(chromeColor, 130));

    painter.end();
    return image;
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
        , text(new QSGSimpleTextureNode)
    {
        appendChildNode(background);
        appendChildNode(track);
        appendChildNode(auxTrack);
        appendChildNode(ticks);
        appendChildNode(primaryArc);
        appendChildNode(auxArc);
        appendChildNode(centerDot);
        appendChildNode(text);
    }

    ~NativeGaugeNode() override
    {
        text->setTexture(nullptr);
        delete textTexture;
    }

    void setTexture(QSGTexture *texture)
    {
        text->setTexture(nullptr);
        delete textTexture;
        textTexture = texture;
        text->setTexture(textTexture);
    }

    QSGGeometryNode *background = nullptr;
    QSGGeometryNode *track = nullptr;
    QSGGeometryNode *auxTrack = nullptr;
    QSGGeometryNode *ticks = nullptr;
    QSGGeometryNode *primaryArc = nullptr;
    QSGGeometryNode *auxArc = nullptr;
    QSGGeometryNode *centerDot = nullptr;
    QSGSimpleTextureNode *text = nullptr;
    QSGTexture *textTexture = nullptr;
    QSizeF geometrySize;
    int geometryRevision = -1;
    int textRevision = -1;
    QString textKey;
};
} // namespace

NativeGaugeInstrumentItem::NativeGaugeInstrumentItem(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents, true);
    m_textThrottle.start();
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
    invalidateGeometry();
    invalidateText(true);
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setValue(qreal value)
{
    value = qMax(0.0, finiteOr(value, 0.0));
    if (qFuzzyCompare(m_value, value)) {
        return;
    }
    const int oldBucket = textBucketFor(m_value);
    m_value = value;
    invalidateGeometry();
    if (textBucketFor(m_value) != oldBucket) {
        invalidateText(false);
    }
    emit valueChanged();
}

void NativeGaugeInstrumentItem::setMaxValue(qreal value)
{
    value = qMax(1.0, finiteOr(value, 1.0));
    if (qFuzzyCompare(m_maxValue, value)) {
        return;
    }
    m_maxValue = value;
    invalidateGeometry();
    invalidateText(true);
    emit geometryInputChanged();
}

void NativeGaugeInstrumentItem::setAuxProgress(qreal value)
{
    value = clampProgress(value);
    if (qFuzzyCompare(m_auxProgress, value)) {
        return;
    }
    m_auxProgress = value;
    invalidateGeometry();
    emit geometryInputChanged();
}

void NativeGaugeInstrumentItem::setPrimaryColor(const QColor &value)
{
    if (m_primaryColor == value) {
        return;
    }
    m_primaryColor = value;
    invalidateGeometry();
    invalidateText(false);
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setAuxColor(const QColor &value)
{
    if (m_auxColor == value) {
        return;
    }
    m_auxColor = value;
    invalidateGeometry();
    invalidateText(false);
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setChromeColor(const QColor &value)
{
    if (m_chromeColor == value) {
        return;
    }
    m_chromeColor = value;
    invalidateGeometry();
    invalidateText(false);
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setLowEffectMode(bool value)
{
    if (m_lowEffectMode == value) {
        return;
    }
    m_lowEffectMode = value;
    invalidateGeometry();
    emit appearanceChanged();
}

void NativeGaugeInstrumentItem::setCenterText(const QString &value)
{
    if (m_centerText == value) {
        return;
    }
    m_centerText = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setStatusText(const QString &value)
{
    if (m_statusText == value) {
        return;
    }
    m_statusText = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setBottomText(const QString &value)
{
    if (m_bottomText == value) {
        return;
    }
    m_bottomText = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setBottomSubText(const QString &value)
{
    if (m_bottomSubText == value) {
        return;
    }
    m_bottomSubText = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setDriveModeText(const QString &value)
{
    if (m_driveModeText == value) {
        return;
    }
    m_driveModeText = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setOverdrive(bool value)
{
    if (m_overdrive == value) {
        return;
    }
    m_overdrive = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::setHighBeam(bool value)
{
    if (m_highBeam == value) {
        return;
    }
    m_highBeam = value;
    invalidateText(true);
    emit textChanged();
}

void NativeGaugeInstrumentItem::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size()) {
        invalidateGeometry();
        invalidateText(true);
    }
}

void NativeGaugeInstrumentItem::invalidateGeometry()
{
    ++m_geometryRevision;
    update();
}

void NativeGaugeInstrumentItem::invalidateText(bool immediate)
{
    ++m_textRevision;
    update();
    if (!immediate && m_textThrottle.isValid() && m_textThrottle.elapsed() < 80) {
        QTimer::singleShot(80, this, [this, revision = m_textRevision]() {
            if (m_textRevision == revision) {
                update();
            }
        });
    }
}

int NativeGaugeInstrumentItem::textBucketFor(qreal value) const
{
    if (m_kind == QLatin1String("tach")) {
        return qRound(finiteOr(value, 0.0) / 100.0);
    }
    return qRound(finiteOr(value, 0.0));
}

QSGNode *NativeGaugeInstrumentItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    const qreal itemWidth = width();
    const qreal itemHeight = height();
    const qreal side = qMin(itemWidth, itemHeight);
    if (side <= 4.0 || !window()) {
        delete oldNode;
        return nullptr;
    }

    auto *node = static_cast<NativeGaugeNode *>(oldNode);
    if (!node) {
        node = new NativeGaugeNode;
    }

    const QSizeF itemSize(itemWidth, itemHeight);
    if (node->geometryRevision != m_geometryRevision || node->geometrySize != itemSize) {
        const QPointF center(itemWidth * 0.5, itemHeight * 0.5);
        const qreal radius = side * 0.405;
        const qreal stroke = side * (m_lowEffectMode ? 0.020 : 0.024);
        const qreal auxStroke = side * 0.014;
        const int arcSegments = m_lowEffectMode ? 96 : 128;
        const qreal mainProgress = clampProgress(m_value / qMax(1.0, m_maxValue));

        std::vector<QPointF> backgroundVertices;
        std::vector<QPointF> trackVertices;
        std::vector<QPointF> auxTrackVertices;
        std::vector<QPointF> tickVertices;
        std::vector<QPointF> primaryVertices;
        std::vector<QPointF> auxVertices;
        std::vector<QPointF> centerVertices;

        backgroundVertices.reserve(192);
        appendDisc(backgroundVertices, center, side * 0.414, 64);
        appendArcBand(trackVertices, center, radius, stroke, kPrimaryStartDeg, kPrimarySweepDeg, 0.0, 1.0, arcSegments, true);
        appendArcBand(auxTrackVertices, center, side * 0.270, auxStroke, kAuxStartDeg, kAuxSweepDeg, 0.0, 1.0, 64, true);
        appendArcBand(primaryVertices, center, radius, stroke, kPrimaryStartDeg, kPrimarySweepDeg, 0.0, mainProgress, arcSegments, true);
        appendArcBand(auxVertices, center, side * 0.270, auxStroke, kAuxStartDeg, kAuxSweepDeg, 0.0, m_auxProgress, 64, true);
        appendDisc(centerVertices, center, side * 0.0085, 18);

        const int minorCount = m_kind == QLatin1String("tach") ? 40 : 28;
        const int majorEvery = m_kind == QLatin1String("tach") ? 5 : 4;
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

        setGeometry(node->background, backgroundVertices, QColor(QStringLiteral("#010309")));
        setGeometry(node->track, trackVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 48 : 62));
        setGeometry(node->auxTrack, auxTrackVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 44 : 58));
        setGeometry(node->ticks, tickVertices, withAlpha(m_chromeColor, m_lowEffectMode ? 132 : 160));
        setGeometry(node->primaryArc, primaryVertices, withAlpha(m_primaryColor, 235));
        setGeometry(node->auxArc, auxVertices, withAlpha(m_auxColor, 224));
        setGeometry(node->centerDot, centerVertices, withAlpha(m_chromeColor, 150));

        node->geometrySize = itemSize;
        node->geometryRevision = m_geometryRevision;
    }

    const QString textKey = m_kind
        + QLatin1Char('|') + QString::number(textBucketFor(m_value))
        + QLatin1Char('|') + QString::number(width())
        + QLatin1Char('x') + QString::number(height())
        + QLatin1Char('|') + m_primaryColor.name(QColor::HexArgb)
        + QLatin1Char('|') + m_auxColor.name(QColor::HexArgb)
        + QLatin1Char('|') + m_chromeColor.name(QColor::HexArgb)
        + QLatin1Char('|') + m_centerText
        + QLatin1Char('|') + m_statusText
        + QLatin1Char('|') + m_bottomText
        + QLatin1Char('|') + m_bottomSubText
        + QLatin1Char('|') + m_driveModeText
        + QLatin1Char('|') + (m_overdrive ? QLatin1String("od1") : QLatin1String("od0"))
        + QLatin1Char('|') + (m_highBeam ? QLatin1String("hi1") : QLatin1String("hi0"));
    const bool textReady = !node->textTexture || !m_textThrottle.isValid() || m_textThrottle.elapsed() >= 80;
    if ((node->textRevision != m_textRevision || node->textKey != textKey || !node->textTexture) && textReady) {
        const QSize textureSize(qMax(1, int(qRound(itemWidth))), qMax(1, int(qRound(itemHeight))));
        QImage image = renderTextImage(textureSize,
                                       m_kind,
                                       m_value,
                                       m_auxProgress,
                                       m_primaryColor,
                                       m_auxColor,
                                       m_chromeColor,
                                       m_centerText,
                                       m_statusText,
                                       m_bottomText,
                                       m_bottomSubText,
                                       m_driveModeText,
                                       m_overdrive,
                                       m_highBeam);
        node->setTexture(window()->createTextureFromImage(image));
        node->text->setRect(QRectF(0, 0, itemWidth, itemHeight));
        node->text->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
        node->textRevision = m_textRevision;
        node->textKey = textKey;
        m_textThrottle.restart();
    } else if (node->text->rect() != QRectF(0, 0, itemWidth, itemHeight)) {
        node->text->setRect(QRectF(0, 0, itemWidth, itemHeight));
        node->text->markDirty(QSGNode::DirtyGeometry);
    }

    return node;
}
