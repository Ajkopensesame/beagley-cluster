#pragma once

#include <QColor>
#include <QElapsedTimer>
#include <QQuickItem>
#include <QString>

class QSGNode;

class NativeGaugeInstrumentItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QString kind READ kind WRITE setKind NOTIFY appearanceChanged)
    Q_PROPERTY(qreal value READ value WRITE setValue NOTIFY valueChanged)
    Q_PROPERTY(qreal maxValue READ maxValue WRITE setMaxValue NOTIFY geometryInputChanged)
    Q_PROPERTY(qreal auxProgress READ auxProgress WRITE setAuxProgress NOTIFY geometryInputChanged)
    Q_PROPERTY(QColor primaryColor READ primaryColor WRITE setPrimaryColor NOTIFY appearanceChanged)
    Q_PROPERTY(QColor auxColor READ auxColor WRITE setAuxColor NOTIFY appearanceChanged)
    Q_PROPERTY(QColor chromeColor READ chromeColor WRITE setChromeColor NOTIFY appearanceChanged)
    Q_PROPERTY(bool lowEffectMode READ lowEffectMode WRITE setLowEffectMode NOTIFY appearanceChanged)
    Q_PROPERTY(QString centerText READ centerText WRITE setCenterText NOTIFY textChanged)
    Q_PROPERTY(QString statusText READ statusText WRITE setStatusText NOTIFY textChanged)
    Q_PROPERTY(QString bottomText READ bottomText WRITE setBottomText NOTIFY textChanged)
    Q_PROPERTY(QString bottomSubText READ bottomSubText WRITE setBottomSubText NOTIFY textChanged)
    Q_PROPERTY(QString driveModeText READ driveModeText WRITE setDriveModeText NOTIFY textChanged)
    Q_PROPERTY(bool overdrive READ overdrive WRITE setOverdrive NOTIFY textChanged)
    Q_PROPERTY(bool highBeam READ highBeam WRITE setHighBeam NOTIFY textChanged)

public:
    explicit NativeGaugeInstrumentItem(QQuickItem *parent = nullptr);
    ~NativeGaugeInstrumentItem() override;

    QString kind() const { return m_kind; }
    void setKind(const QString &value);

    qreal value() const { return m_value; }
    void setValue(qreal value);

    qreal maxValue() const { return m_maxValue; }
    void setMaxValue(qreal value);

    qreal auxProgress() const { return m_auxProgress; }
    void setAuxProgress(qreal value);

    QColor primaryColor() const { return m_primaryColor; }
    void setPrimaryColor(const QColor &value);

    QColor auxColor() const { return m_auxColor; }
    void setAuxColor(const QColor &value);

    QColor chromeColor() const { return m_chromeColor; }
    void setChromeColor(const QColor &value);

    bool lowEffectMode() const { return m_lowEffectMode; }
    void setLowEffectMode(bool value);

    QString centerText() const { return m_centerText; }
    void setCenterText(const QString &value);

    QString statusText() const { return m_statusText; }
    void setStatusText(const QString &value);

    QString bottomText() const { return m_bottomText; }
    void setBottomText(const QString &value);

    QString bottomSubText() const { return m_bottomSubText; }
    void setBottomSubText(const QString &value);

    QString driveModeText() const { return m_driveModeText; }
    void setDriveModeText(const QString &value);

    bool overdrive() const { return m_overdrive; }
    void setOverdrive(bool value);

    bool highBeam() const { return m_highBeam; }
    void setHighBeam(bool value);

signals:
    void valueChanged();
    void geometryInputChanged();
    void appearanceChanged();
    void textChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void invalidateGeometry();
    void invalidateText(bool immediate = false);
    int textBucketFor(qreal value) const;

    QString m_kind = QStringLiteral("speed");
    qreal m_value = 0.0;
    qreal m_maxValue = 140.0;
    qreal m_auxProgress = 0.0;
    QColor m_primaryColor = QColor(QStringLiteral("#C7B7FF"));
    QColor m_auxColor = QColor(QStringLiteral("#C7B7FF"));
    QColor m_chromeColor = QColor(QStringLiteral("#C7B7FF"));
    bool m_lowEffectMode = true;
    QString m_centerText;
    QString m_statusText;
    QString m_bottomText;
    QString m_bottomSubText;
    QString m_driveModeText;
    bool m_overdrive = false;
    bool m_highBeam = false;

    int m_geometryRevision = 0;
    int m_textRevision = 0;
    QElapsedTimer m_textThrottle;
};
