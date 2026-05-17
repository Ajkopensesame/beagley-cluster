#pragma once

#include <QColor>
#include <QQuickItem>

class QSGNode;

class NativePanelItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(QColor borderColor READ borderColor WRITE setBorderColor NOTIFY borderColorChanged)
    Q_PROPERTY(qreal borderWidth READ borderWidth WRITE setBorderWidth NOTIFY borderWidthChanged)

public:
    explicit NativePanelItem(QQuickItem *parent = nullptr);

    QColor color() const { return m_color; }
    void setColor(const QColor &color);

    QColor borderColor() const { return m_borderColor; }
    void setBorderColor(const QColor &color);

    qreal borderWidth() const { return m_borderWidth; }
    void setBorderWidth(qreal borderWidth);

signals:
    void colorChanged();
    void borderColorChanged();
    void borderWidthChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    QColor m_color = QColor(5, 7, 13);
    QColor m_borderColor = QColor(29, 76, 74);
    qreal m_borderWidth = 0.0;
};
