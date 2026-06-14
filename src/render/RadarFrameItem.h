#pragma once

#include <QImage>
#include <QQuickItem>
#include <QUrl>
#include <QVariantList>

class QSGNode;

class RadarFrameItem : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QUrl mapSource READ mapSource WRITE setMapSource NOTIFY mapSourceChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool circular READ circular WRITE setCircular NOTIFY circularChanged)
    Q_PROPERTY(bool backgroundVisible READ backgroundVisible WRITE setBackgroundVisible NOTIFY backgroundVisibleChanged)
    Q_PROPERTY(bool guidesVisible READ guidesVisible WRITE setGuidesVisible NOTIFY guidesVisibleChanged)
    Q_PROPERTY(QVariantList samples READ samples NOTIFY samplesChanged)

public:
    explicit RadarFrameItem(QQuickItem *parent = nullptr);
    ~RadarFrameItem() override;

    QUrl source() const { return m_source; }
    QUrl mapSource() const { return m_mapSource; }
    bool ready() const { return m_ready; }
    bool circular() const { return m_circular; }
    bool backgroundVisible() const { return m_backgroundVisible; }
    bool guidesVisible() const { return m_guidesVisible; }
    QVariantList samples() const { return m_samples; }

    void setSource(const QUrl &source);
    void setMapSource(const QUrl &source);
    void setCircular(bool circular);
    void setBackgroundVisible(bool visible);
    void setGuidesVisible(bool visible);

signals:
    void sourceChanged();
    void mapSourceChanged();
    void readyChanged();
    void circularChanged();
    void backgroundVisibleChanged();
    void guidesVisibleChanged();
    void samplesChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void loadSource();
    void loadMapSource();
    void refreshSamples();
    void setReady(bool ready);

    QUrl m_source;
    QUrl m_mapSource;
    QImage m_image;
    QImage m_mapImage;
    QVariantList m_samples;
    bool m_ready = false;
    bool m_circular = false;
    bool m_backgroundVisible = true;
    bool m_guidesVisible = true;
    int m_sourceRevision = 0;
    int m_mapRevision = 0;
    int m_geometryRevision = 0;
};
