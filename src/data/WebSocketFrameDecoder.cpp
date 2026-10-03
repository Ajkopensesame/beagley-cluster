#include "WebSocketFrameDecoder.h"

#include <algorithm>

void WebSocketFrameDecoder::reset()
{
    m_buffer.clear();
    m_fragment.clear();
    m_fragmentIsText = false;
    m_closed = false;
    m_error.clear();
}

WebSocketFrameDecoder::Status WebSocketFrameDecoder::fail(const QString &message)
{
    m_error = message;
    m_buffer.clear();
    m_fragment.clear();
    m_fragmentIsText = false;
    return Status::ProtocolError;
}

WebSocketFrameDecoder::Status WebSocketFrameDecoder::feed(const QByteArray &data,
                                                          QVector<Event> *events)
{
    if (hasError())
        return Status::ProtocolError;
    if (m_closed)
        return Status::Ok;

    // Append in slices so the buffer never exceeds kMaxBufferBytes, decoding
    // between slices. A leftover (incomplete) frame is always < kMaxBufferBytes
    // because oversized payloads are rejected as soon as their header is parsed.
    int pos = 0;
    while (pos < data.size()) {
        const int room = kMaxBufferBytes - m_buffer.size();
        if (room <= 0)
            return fail(QStringLiteral("input buffer limit exceeded"));
        const int take = std::min(room, int(data.size() - pos));
        m_buffer.append(data.constData() + pos, take);
        pos += take;

        if (decodeBuffered(events) != Status::Ok)
            return Status::ProtocolError;
        if (m_closed)
            return Status::Ok;
    }
    return Status::Ok;
}

WebSocketFrameDecoder::Status WebSocketFrameDecoder::decodeBuffered(QVector<Event> *events)
{
    while (true) {
        if (m_buffer.size() < 2)
            return Status::Ok;

        const quint8 byte0 = quint8(m_buffer.at(0));
        const quint8 byte1 = quint8(m_buffer.at(1));
        const bool fin = (byte0 & 0x80) != 0;
        const quint8 opcode = byte0 & 0x0f;
        const bool masked = (byte1 & 0x80) != 0;

        quint64 payloadLength = quint64(byte1 & 0x7f);
        int offset = 2;

        if (payloadLength == 126) {
            if (m_buffer.size() < offset + 2)
                return Status::Ok;
            payloadLength = (quint64(quint8(m_buffer.at(offset))) << 8)
                          | quint64(quint8(m_buffer.at(offset + 1)));
            offset += 2;
        } else if (payloadLength == 127) {
            if (m_buffer.size() < offset + 8)
                return Status::Ok;
            payloadLength = 0;
            for (int i = 0; i < 8; ++i)
                payloadLength = (payloadLength << 8) | quint64(quint8(m_buffer.at(offset + i)));
            offset += 8;
        }

        // Reject before waiting for (or allocating) the payload. Comparing as
        // quint64 avoids truncating a huge 64-bit length into an int.
        if (payloadLength > quint64(kMaxPayloadBytes)) {
            return fail(QStringLiteral("frame payload %1 exceeds limit %2")
                            .arg(payloadLength).arg(kMaxPayloadBytes));
        }
        const int length = int(payloadLength);

        QByteArray maskKey;
        if (masked) {
            if (m_buffer.size() < offset + 4)
                return Status::Ok;
            maskKey = m_buffer.mid(offset, 4);
            offset += 4;
        }

        if (m_buffer.size() < offset + length)
            return Status::Ok;

        QByteArray payload = m_buffer.mid(offset, length);
        m_buffer.remove(0, offset + length);

        if (masked) {
            for (int i = 0; i < payload.size(); ++i)
                payload[i] = char(quint8(payload.at(i)) ^ quint8(maskKey.at(i % 4)));
        }

        switch (opcode) {
        case 0x0: // continuation
            if (m_fragmentIsText) {
                if (m_fragment.size() + payload.size() > kMaxPayloadBytes)
                    return fail(QStringLiteral("fragmented message exceeds limit %1")
                                    .arg(kMaxPayloadBytes));
                m_fragment += payload;
                if (fin) {
                    events->append({EventType::Text, m_fragment});
                    m_fragment.clear();
                    m_fragmentIsText = false;
                }
            }
            break;
        case 0x1: // text
            if (fin) {
                events->append({EventType::Text, payload});
                m_fragment.clear();
                m_fragmentIsText = false;
            } else {
                m_fragment = payload;
                m_fragmentIsText = true;
            }
            break;
        case 0x8: // close
            events->append({EventType::Close, payload});
            m_buffer.clear();
            m_closed = true;
            return Status::Ok;
        case 0x9: // ping
            events->append({EventType::Ping, payload});
            break;
        default: // pong, binary, reserved: ignored
            break;
        }
    }
}
