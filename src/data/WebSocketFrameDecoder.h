#pragma once

#include <QByteArray>
#include <QString>
#include <QVector>

// Minimal, bounded RFC 6455 frame decoder used by VehicleStateClient (the client
// speaks raw TCP WebSocket to the BBB hub). It is a plain class with no socket or
// Qt event-loop dependency so it can be unit tested with byte buffers.
//
// Handles: text frames (unmasked or masked), fragmented text (continuation
// frames), ping and close. Pong and unknown opcodes are ignored. Binary frames
// are ignored.
//
// Limits (a hostile or buggy peer cannot grow memory without bound):
//   - a single frame payload may be at most kMaxPayloadBytes;
//   - a reassembled fragmented message may be at most kMaxPayloadBytes;
//   - the internal input buffer never exceeds kMaxBufferBytes.
// On a violation feed() returns Status::ProtocolError, errorString() describes it,
// and the decoder stays in the error state until reset(); the caller is expected to
// drop the connection.
class WebSocketFrameDecoder
{
public:
    static constexpr int kMaxPayloadBytes = 64 * 1024;
    static constexpr int kMaxBufferBytes = 256 * 1024;

    enum class EventType { Text, Ping, Close };

    struct Event {
        EventType type = EventType::Text;
        QByteArray payload; // Text: complete UTF-8 message; Ping/Close: control payload
    };

    enum class Status { Ok, ProtocolError };

    // Append received bytes and decode every complete frame, appending to *events
    // in arrival order. Decoding stops after a Close event (later bytes are dropped).
    Status feed(const QByteArray &data, QVector<Event> *events);

    bool hasError() const { return !m_error.isEmpty(); }
    QString errorString() const { return m_error; }

    // Bytes currently buffered (incomplete frame data); exposed for tests.
    int bufferedBytes() const { return m_buffer.size(); }

    void reset();

private:
    Status decodeBuffered(QVector<Event> *events);
    Status fail(const QString &message);

    QByteArray m_buffer;
    QByteArray m_fragment;
    bool m_fragmentIsText = false;
    bool m_closed = false;
    QString m_error;
};
