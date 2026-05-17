#pragma once

#include <QColor>
#include <QQuickItem>

class QSGNode;

class GaugeArcItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(qreal startAngleDeg READ startAngleDeg WRITE setStartAngleDeg NOTIFY geometryChanged)
    Q_PROPERTY(qreal sweepAngleDeg READ sweepAngleDeg WRITE setSweepAngleDeg NOTIFY geometryChanged)
    Q_PROPERTY(qreal startProgress READ startProgress WRITE setStartProgress NOTIFY geometryChanged)
    Q_PROPERTY(qreal endProgress READ endProgress WRITE setEndProgress NOTIFY geometryChanged)
    Q_PROPERTY(qreal radiusFactor READ radiusFactor WRITE setRadiusFactor NOTIFY geometryChanged)
    Q_PROPERTY(qreal strokeWidth READ strokeWidth WRITE setStrokeWidth NOTIFY geometryChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(int segments READ segments WRITE setSegments NOTIFY geometryChanged)
    Q_PROPERTY(bool roundedCaps READ roundedCaps WRITE setRoundedCaps NOTIFY geometryChanged)

public:
    explicit GaugeArcItem(QQuickItem *parent = nullptr);

    qreal startAngleDeg() const { return m_startAngleDeg; }
    void setStartAngleDeg(qreal value);

    qreal sweepAngleDeg() const { return m_sweepAngleDeg; }
    void setSweepAngleDeg(qreal value);

    qreal startProgress() const { return m_startProgress; }
    void setStartProgress(qreal value);

    qreal endProgress() const { return m_endProgress; }
    void setEndProgress(qreal value);

    qreal radiusFactor() const { return m_radiusFactor; }
    void setRadiusFactor(qreal value);

    qreal strokeWidth() const { return m_strokeWidth; }
    void setStrokeWidth(qreal value);

    QColor color() const { return m_color; }
    void setColor(const QColor &value);

    int segments() const { return m_segments; }
    void setSegments(int value);

    bool roundedCaps() const { return m_roundedCaps; }
    void setRoundedCaps(bool value);

signals:
    void geometryChanged();
    void colorChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void scheduleGeometryUpdate();

    qreal m_startAngleDeg = 225.0;
    qreal m_sweepAngleDeg = 210.0;
    qreal m_startProgress = 0.0;
    qreal m_endProgress = 1.0;
    qreal m_radiusFactor = 0.405;
    qreal m_strokeWidth = 8.0;
    QColor m_color = Qt::white;
    int m_segments = 96;
    bool m_roundedCaps = true;
};
