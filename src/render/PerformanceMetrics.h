#pragma once

#include <QElapsedTimer>
#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QTimer>
#include <QVector>

class PerformanceMetrics final : public QObject
{
    Q_OBJECT

public:
    explicit PerformanceMetrics(bool enabled, QObject *parent = nullptr);

    void attachWindow(QQuickWindow *window);
    bool enabled() const { return m_enabled; }

    Q_INVOKABLE void recordPaint(const QString &bucket);
    Q_INVOKABLE void recordCounter(const QString &bucket, int amount = 1);

private:
    void flush();

    bool m_enabled = false;
    QPointer<QQuickWindow> m_window;
    QElapsedTimer m_windowClock;
    QTimer m_flushTimer;
    qint64 m_lastFrameMs = 0;
    int m_frameCount = 0;
    QVector<int> m_frameIntervalsMs;
    QHash<QString, int> m_counters;
};
