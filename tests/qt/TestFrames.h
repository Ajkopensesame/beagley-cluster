#pragma once

#include <QByteArray>

// Builds RFC 6455 frames for tests. Server->client frames are normally unmasked;
// `mask=true` produces a masked frame to exercise the decoder's unmasking.
inline QByteArray makeFrame(quint8 opcode, const QByteArray &payload,
                            bool fin = true, bool mask = false)
{
    QByteArray f;
    f.append(char((fin ? 0x80 : 0x00) | (opcode & 0x0f)));
    const int maskBit = mask ? 0x80 : 0x00;
    const quint64 n = quint64(payload.size());
    if (n < 126) {
        f.append(char(maskBit | int(n)));
    } else if (n <= 0xffff) {
        f.append(char(maskBit | 126));
        f.append(char((n >> 8) & 0xff));
        f.append(char(n & 0xff));
    } else {
        f.append(char(maskBit | 127));
        for (int i = 7; i >= 0; --i)
            f.append(char((n >> (8 * i)) & 0xff));
    }
    if (mask) {
        const char key[4] = {char(0x12), char(0x34), char(0x56), char(0x78)};
        f.append(key, 4);
        QByteArray m = payload;
        for (int i = 0; i < m.size(); ++i)
            m[i] = char(quint8(m.at(i)) ^ quint8(key[i % 4]));
        f += m;
    } else {
        f += payload;
    }
    return f;
}

inline QByteArray textFrame(const QByteArray &payload, bool mask = false)
{
    return makeFrame(0x1, payload, true, mask);
}
