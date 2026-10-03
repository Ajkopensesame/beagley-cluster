#pragma once

#include "VehicleStateSource.h"
#include "WebSocketFrameDecoder.h"

#include <QTcpSocket>
#include <QTimer>
#include <QElapsedTimer>
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
    ~VehicleStateClient() override;

private slots:
    void onSocketConnected();
    void onSocketReadyRead();
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &msg);
    void checkStale();
    void playNextReplayFrame();
    void onConnectTimeout();

private:
    void loadReplayFrames(const QString &path);
    void scheduleReconnect();
    void connectNow();
    void sendHandshakeRequest();
    void processSocketBuffer();
    void processHandshake();
    void processDecodedEvents(const QVector<WebSocketFrameDecoder::Event> &events);
    void failConnection(const QString &reason);
    void handleLinkDown();
    qint64 nowMs() const { return m_clock.elapsed(); }
    void logParseProblem(const QString &what);
    void sendControlFrame(quint8 opcode, const QByteArray &payload = QByteArray());

    QTcpSocket m_socket;
    QTimer m_watchdog;
    QTimer m_reconnect;
    QTimer m_replayTimer;

    QString m_url;
    QUrl m_connectUrl;
    QByteArray m_socketBuffer; // HTTP upgrade response only; frames go to m_decoder
    WebSocketFrameDecoder m_decoder;
    QTimer m_connectTimeout;
    QByteArray m_handshakeKey;
    bool m_handshakeComplete = false;
    bool m_replayMode = false;
    bool m_replayLoop = false;
    int m_replayIndex = 0;
    QVector<QString> m_replayFrames;
    QVector<int> m_replayDelaysMs;

    // Monotonic clock for link health (wall-clock jumps - NTP, no RTC - must not
    // cause false stale/fresh). m_lastGoodRxMs is only valid if m_hasGoodFrame.
    QElapsedTimer m_clock;
    qint64 m_lastGoodRxMs = 0;
    bool m_hasGoodFrame = false;

    qint64 m_lastParseLogMs = -1;
    int m_suppressedParseLogs = 0;
    int m_backoffMs = 250;
};
