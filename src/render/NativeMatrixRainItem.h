#pragma once

#include <QColor>
#include <QQuickItem>

class QSGNode;

class NativeMatrixRainItem : public QQuickItem
{
    Q_OBJECT

    Q_PROPERTY(QColor rainColor READ rainColor WRITE setRainColor NOTIFY rainColorChanged)
    Q_PROPERTY(QColor glowColor READ glowColor WRITE setGlowColor NOTIFY glowColorChanged)
    Q_PROPERTY(bool effectEnabled READ effectEnabled WRITE setEffectEnabled NOTIFY effectEnabledChanged)
    Q_PROPERTY(QString effectLevel READ effectLevel WRITE setEffectLevel NOTIFY effectLevelChanged)
    Q_PROPERTY(qreal phase READ phase WRITE setPhase NOTIFY phaseChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)
    Q_PROPERTY(int fontPx READ fontPx WRITE setFontPx NOTIFY fontPxChanged)
    Q_PROPERTY(qreal density READ density WRITE setDensity NOTIFY densityChanged)
    Q_PROPERTY(qreal speedMultiplier READ speedMultiplier WRITE setSpeedMultiplier NOTIFY speedMultiplierChanged)
    Q_PROPERTY(qreal driftScale READ driftScale WRITE setDriftScale NOTIFY driftScaleChanged)
    Q_PROPERTY(int tailLength READ tailLength WRITE setTailLength NOTIFY tailLengthChanged)
    Q_PROPERTY(qreal headAlpha READ headAlpha WRITE setHeadAlpha NOTIFY headAlphaChanged)
    Q_PROPERTY(qreal tailMinAlpha READ tailMinAlpha WRITE setTailMinAlpha NOTIFY tailMinAlphaChanged)
    Q_PROPERTY(bool circularMask READ circularMask WRITE setCircularMask NOTIFY circularMaskChanged)
    Q_PROPERTY(qreal maskCenterX READ maskCenterX WRITE setMaskCenterX NOTIFY maskCenterXChanged)
    Q_PROPERTY(qreal maskCenterY READ maskCenterY WRITE setMaskCenterY NOTIFY maskCenterYChanged)
    Q_PROPERTY(qreal maskRadius READ maskRadius WRITE setMaskRadius NOTIFY maskRadiusChanged)

public:
    explicit NativeMatrixRainItem(QQuickItem *parent = nullptr);
    ~NativeMatrixRainItem() override;

    QColor rainColor() const { return m_rainColor; }
    QColor glowColor() const { return m_glowColor; }
    bool effectEnabled() const { return m_effectEnabled; }
    QString effectLevel() const { return m_effectLevel; }
    qreal phase() const { return m_phase; }
    int columns() const { return m_columns; }
    int fontPx() const { return m_fontPx; }
    qreal density() const { return m_density; }
    qreal speedMultiplier() const { return m_speedMultiplier; }
    qreal driftScale() const { return m_driftScale; }
    int tailLength() const { return m_tailLength; }
    qreal headAlpha() const { return m_headAlpha; }
    qreal tailMinAlpha() const { return m_tailMinAlpha; }
    bool circularMask() const { return m_circularMask; }
    qreal maskCenterX() const { return m_maskCenterX; }
    qreal maskCenterY() const { return m_maskCenterY; }
    qreal maskRadius() const { return m_maskRadius; }

    void setRainColor(const QColor &color);
    void setGlowColor(const QColor &color);
    void setEffectEnabled(bool enabled);
    void setEffectLevel(const QString &level);
    void setPhase(qreal phase);
    void setColumns(int columns);
    void setFontPx(int fontPx);
    void setDensity(qreal density);
    void setSpeedMultiplier(qreal multiplier);
    void setDriftScale(qreal scale);
    void setTailLength(int tailLength);
    void setHeadAlpha(qreal alpha);
    void setTailMinAlpha(qreal alpha);
    void setCircularMask(bool enabled);
    void setMaskCenterX(qreal value);
    void setMaskCenterY(qreal value);
    void setMaskRadius(qreal value);

signals:
    void rainColorChanged();
    void glowColorChanged();
    void effectEnabledChanged();
    void effectLevelChanged();
    void phaseChanged();
    void columnsChanged();
    void fontPxChanged();
    void densityChanged();
    void speedMultiplierChanged();
    void driftScaleChanged();
    void tailLengthChanged();
    void headAlphaChanged();
    void tailMinAlphaChanged();
    void circularMaskChanged();
    void maskCenterXChanged();
    void maskCenterYChanged();
    void maskRadiusChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

private:
    void markDirty();

    QColor m_rainColor = QColor(QStringLiteral("#C7B7FF"));
    QColor m_glowColor = QColor(QStringLiteral("#EAD7FF"));
    bool m_effectEnabled = true;
    QString m_effectLevel = QStringLiteral("high");
    qreal m_phase = 0.0;
    int m_columns = 0;
    int m_fontPx = 13;
    qreal m_density = 0.35;
    qreal m_speedMultiplier = 0.10;
    qreal m_driftScale = 0.18;
    int m_tailLength = 26;
    qreal m_headAlpha = 0.45;
    qreal m_tailMinAlpha = 0.02;
    bool m_circularMask = false;
    qreal m_maskCenterX = 0.0;
    qreal m_maskCenterY = 0.0;
    qreal m_maskRadius = 0.0;
    int m_revision = 0;
    int m_geometryRevision = 0;
};
