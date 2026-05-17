#pragma once

#include <QColor>
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

signals:
    void valueChanged();
    void geometryInputChanged();
    void appearanceChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void invalidateStaticGeometry();
    void invalidateDynamicGeometry();

    QString m_kind = QStringLiteral("speed");
    qreal m_value = 0.0;
    qreal m_maxValue = 140.0;
    qreal m_auxProgress = 0.0;
    QColor m_primaryColor = QColor(QStringLiteral("#C7B7FF"));
    QColor m_auxColor = QColor(QStringLiteral("#C7B7FF"));
    QColor m_chromeColor = QColor(QStringLiteral("#C7B7FF"));
    bool m_lowEffectMode = true;

    int m_staticRevision = 0;
    int m_dynamicRevision = 0;
};
