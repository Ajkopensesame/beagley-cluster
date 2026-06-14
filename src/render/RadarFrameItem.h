#pragma once

#include <QImage>
#include <QQuickPaintedItem>
#include <QSize>
#include <QUrl>

class QPainter;

class RadarFrameItem : public QQuickPaintedItem
{
    Q_OBJECT

    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QUrl mapSource READ mapSource WRITE setMapSource NOTIFY mapSourceChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool circular READ circular WRITE setCircular NOTIFY circularChanged)
    Q_PROPERTY(bool backgroundVisible READ backgroundVisible WRITE setBackgroundVisible NOTIFY backgroundVisibleChanged)
    Q_PROPERTY(bool guidesVisible READ guidesVisible WRITE setGuidesVisible NOTIFY guidesVisibleChanged)

public:
    explicit RadarFrameItem(QQuickItem *parent = nullptr);
    ~RadarFrameItem() override;

    QUrl source() const { return m_source; }
    QUrl mapSource() const { return m_mapSource; }
    bool ready() const { return m_ready; }
    bool circular() const { return m_circular; }
    bool backgroundVisible() const { return m_backgroundVisible; }
    bool guidesVisible() const { return m_guidesVisible; }

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

protected:
    void paint(QPainter *painter) override;

private:
    void loadSource();
    void loadMapSource();
    void setReady(bool ready);

    QUrl m_source;
    QUrl m_mapSource;
    QImage m_image;
    QImage m_mapImage;
    bool m_ready = false;
    bool m_circular = false;
    bool m_backgroundVisible = true;
    bool m_guidesVisible = true;
};
