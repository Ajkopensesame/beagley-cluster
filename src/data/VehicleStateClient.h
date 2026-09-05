#pragma once

#include "VehicleStateSource.h"

#include <QWebSocket>
#include <QTimer>
#include <QDateTime>

class VehicleStateClient : public VehicleStateSource
{
    Q_OBJECT

public:
    explicit VehicleStateClient(QObject *parent = nullptr);

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &msg);
    void checkStale();

private:
    void scheduleReconnect();
    void connectNow();

    QWebSocket m_ws;
    QTimer m_watchdog;
    QTimer m_reconnect;

    QString m_url;

    qint64 m_lastGoodRxMs = 0;
    int m_backoffMs = 250;
};
