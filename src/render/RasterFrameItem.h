#pragma once

#include <QImage>
#include <QQuickItem>
#include <QSize>
#include <QUrl>

class QSGNode;

class RasterFrameItem : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool circular READ circular WRITE setCircular NOTIFY circularChanged)

public:
    explicit RasterFrameItem(QQuickItem *parent = nullptr);
    ~RasterFrameItem() override;

    QUrl source() const { return m_source; }
    bool ready() const { return m_ready; }
    bool circular() const { return m_circular; }

    void setSource(const QUrl &source);
    void setCircular(bool circular);

signals:
    void sourceChanged();
    void readyChanged();
    void circularChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void loadSource();
    void setReady(bool ready);

    QUrl m_source;
    QImage m_image;
    bool m_ready = false;
    bool m_circular = false;
    int m_sourceRevision = 0;
    int m_geometryRevision = 0;
};
