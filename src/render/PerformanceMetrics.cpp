#include "PerformanceMetrics.h"

#include <QJsonDocument>
#include <QVariantMap>

#include <algorithm>
#include <cmath>

PerformanceMetrics::PerformanceMetrics(bool enabled, QObject *parent)
    : QObject(parent)
    , m_enabled(enabled)
{
    m_flushTimer.setInterval(1000);
    connect(&m_flushTimer, &QTimer::timeout, this, &PerformanceMetrics::flush);
    if (m_enabled) {
        m_windowClock.start();
        m_flushTimer.start();
    }
}

void PerformanceMetrics::attachWindow(QQuickWindow *window)
{
    if (!m_enabled || !window || m_window == window) {
        return;
    }

    m_window = window;
    connect(window, &QQuickWindow::frameSwapped, this, [this]() {
        if (!m_enabled) {
            return;
        }
        const qint64 nowMs = m_windowClock.elapsed();
        if (m_lastFrameMs > 0) {
            m_frameIntervalsMs.append(int(nowMs - m_lastFrameMs));
        }
        m_lastFrameMs = nowMs;
        ++m_frameCount;
    });
}

void PerformanceMetrics::recordPaint(const QString &bucket)
{
    recordCounter(bucket, 1);
}

void PerformanceMetrics::recordCounter(const QString &bucket, int amount)
{
    if (!m_enabled || bucket.isEmpty() || amount == 0) {
        return;
    }
    m_counters[bucket] = m_counters.value(bucket) + amount;
}

void PerformanceMetrics::flush()
{
    if (!m_enabled) {
        return;
    }

    QList<int> sorted = QList<int>(m_frameIntervalsMs.begin(), m_frameIntervalsMs.end());
    std::sort(sorted.begin(), sorted.end());

    const auto percentile = [&](double ratio) -> int {
        if (sorted.isEmpty()) {
            return 0;
        }
        const int index = qBound(0, int(std::round((sorted.size() - 1) * ratio)), sorted.size() - 1);
        return sorted.at(index);
    };

    QVariantMap counterMap;
    for (auto it = m_counters.cbegin(); it != m_counters.cend(); ++it) {
        counterMap.insert(it.key(), it.value());
    }

    qInfo().noquote()
        << QStringLiteral("[Perf] fps=%1 frame_p50_ms=%2 frame_p95_ms=%3 frame_p99_ms=%4 counters=%5")
               .arg(m_frameCount)
               .arg(percentile(0.50))
               .arg(percentile(0.95))
               .arg(percentile(0.99))
               .arg(QString::fromUtf8(QJsonDocument::fromVariant(counterMap).toJson(QJsonDocument::Compact)));

    m_frameCount = 0;
    m_frameIntervalsMs.clear();
    m_counters.clear();
}
