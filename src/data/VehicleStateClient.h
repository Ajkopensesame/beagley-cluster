#pragma once

#include "VehicleStateSource.h"

#include <QTcpSocket>
#include <QTimer>
#include <QDateTime>
#include <QString>
#include <QUrl>
#include <QVector>

// Live hub link: raw-TCP WebSocket client for the BBB vehicle-hub `vehicle_state`
// stream (or a JSONL replay via BEAGLEY_REPLAY_FILE). All QML-facing properties
// and their setters live in VehicleStateSource.
class VehicleStateClient : public VehicleStateSource
{
    Q_OBJECT

public:
    explicit VehicleStateClient(QObject *parent = nullptr);

private slots:
    void onSocketConnected();
    void onSocketReadyRead();
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &msg);
    void checkStale();
    void playNextReplayFrame();

private:
    void loadReplayFrames(const QString &path);
    void scheduleReconnect();
    void connectNow();
    void sendHandshakeRequest();
    void processSocketBuffer();
    void processHandshake();
    void processFrameBuffer();
    void sendControlFrame(quint8 opcode, const QByteArray &payload = QByteArray());

    QTcpSocket m_socket;
    QTimer m_watchdog;
    QTimer m_reconnect;
    QTimer m_replayTimer;

    QString m_url;
    QUrl m_connectUrl;
    QByteArray m_socketBuffer;
    QByteArray m_fragmentBuffer;
    QByteArray m_handshakeKey;
    bool m_handshakeComplete = false;
    bool m_fragmentIsText = false;
    bool m_replayMode = false;
    bool m_replayLoop = false;
    int m_replayIndex = 0;
    QVector<QString> m_replayFrames;
    QVector<int> m_replayDelaysMs;

    qint64 m_lastGoodRxMs = 0;
    int m_backoffMs = 250;
};
