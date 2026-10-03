#include <QtTest>

#include "TestFrames.h"
#include "data/WebSocketFrameDecoder.h"

using Decoder = WebSocketFrameDecoder;

class TstWebSocketFrameDecoder : public QObject
{
    Q_OBJECT

private slots:
    void unmaskedText()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(textFrame("hello"), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].type, Decoder::EventType::Text);
        QCOMPARE(ev[0].payload, QByteArray("hello"));
    }

    void maskedText()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(textFrame("masked payload", true), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload, QByteArray("masked payload"));
    }

    void extendedLength16()
    {
        const QByteArray payload(300, 'x');
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(textFrame(payload), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload, payload);
    }

    void maxPayloadIsAccepted()
    {
        const QByteArray payload(Decoder::kMaxPayloadBytes, 'y');
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(textFrame(payload), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload.size(), int(Decoder::kMaxPayloadBytes));
    }

    void partialFrameAcrossFeedsByteByByte()
    {
        const QByteArray frame = textFrame("partial-frame-test", true);
        Decoder d;
        QVector<Decoder::Event> ev;
        for (int i = 0; i < frame.size(); ++i) {
            QCOMPARE(d.feed(frame.mid(i, 1), &ev), Decoder::Status::Ok);
            if (i < frame.size() - 1)
                QCOMPARE(ev.size(), 0);
        }
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload, QByteArray("partial-frame-test"));
        QCOMPARE(d.bufferedBytes(), 0);
    }

    void multipleFramesInOneFeed()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        const QByteArray data = textFrame("a") + textFrame("bb") + textFrame("ccc");
        QCOMPARE(d.feed(data, &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 3);
        QCOMPARE(ev[2].payload, QByteArray("ccc"));
    }

    void fragmentedText()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        const QByteArray data = makeFrame(0x1, "Hel", false)
                              + makeFrame(0x0, "lo ", false)
                              + makeFrame(0x0, "world", true);
        QCOMPARE(d.feed(data, &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload, QByteArray("Hello world"));
    }

    void orphanContinuationIsIgnored()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(makeFrame(0x0, "stray", true), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 0);
    }

    void pingIsReported()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(makeFrame(0x9, "hi"), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].type, Decoder::EventType::Ping);
        QCOMPARE(ev[0].payload, QByteArray("hi"));
    }

    void pongAndBinaryAreIgnored()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        const QByteArray data = makeFrame(0xA, "p") + makeFrame(0x2, "bin") + textFrame("ok");
        QCOMPARE(d.feed(data, &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
        QCOMPARE(ev[0].payload, QByteArray("ok"));
    }

    void closeStopsDecoding()
    {
        Decoder d;
        QVector<Decoder::Event> ev;
        const QByteArray data = textFrame("before") + makeFrame(0x8, QByteArray("\x03\xe8", 2))
                              + textFrame("after");
        QCOMPARE(d.feed(data, &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 2);
        QCOMPARE(ev[0].type, Decoder::EventType::Text);
        QCOMPARE(ev[1].type, Decoder::EventType::Close);
        // Further input after close is dropped.
        ev.clear();
        QCOMPARE(d.feed(textFrame("late"), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 0);
    }

    void oversizedFrameRejectedAtHeader()
    {
        // A 64-bit length just over the limit. Only the 10-byte header is supplied:
        // the decoder must reject without waiting for (or buffering) the payload.
        QByteArray header;
        header.append(char(0x81));
        header.append(char(127));
        const quint64 n = quint64(Decoder::kMaxPayloadBytes) + 1;
        for (int i = 7; i >= 0; --i)
            header.append(char((n >> (8 * i)) & 0xff));
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(header, &ev), Decoder::Status::ProtocolError);
        QVERIFY(d.hasError());
        QVERIFY(d.errorString().contains(QStringLiteral("exceeds")));
        QCOMPARE(ev.size(), 0);
    }

    void hugeSixtyFourBitLengthIsNotTruncated()
    {
        // 0x1_0000_0005 would truncate to 5 as an int; it must be rejected instead.
        QByteArray header;
        header.append(char(0x81));
        header.append(char(127));
        const quint64 n = (quint64(1) << 32) + 5;
        for (int i = 7; i >= 0; --i)
            header.append(char((n >> (8 * i)) & 0xff));
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(header, &ev), Decoder::Status::ProtocolError);
    }

    void oversizedFragmentedMessageRejected()
    {
        const QByteArray chunk(Decoder::kMaxPayloadBytes / 2 + 1, 'z');
        Decoder d;
        QVector<Decoder::Event> ev;
        const QByteArray data = makeFrame(0x1, chunk, false) + makeFrame(0x0, chunk, true);
        QCOMPARE(d.feed(data, &ev), Decoder::Status::ProtocolError);
        QCOMPARE(ev.size(), 0);
    }

    void largeBurstExceedingBufferLimitIsDecodedInSlices()
    {
        // ~400 KB in a single feed (> kMaxBufferBytes) of valid frames must decode fully.
        const QByteArray payload(1000, 'q');
        QByteArray data;
        const int frames = 400;
        for (int i = 0; i < frames; ++i)
            data += textFrame(payload);
        QVERIFY(data.size() > Decoder::kMaxBufferBytes);
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(data, &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), frames);
        QVERIFY(d.bufferedBytes() <= Decoder::kMaxBufferBytes);
    }

    void errorIsStickyUntilReset()
    {
        QByteArray header;
        header.append(char(0x81));
        header.append(char(127));
        for (int i = 0; i < 8; ++i)
            header.append(char(0x7f));
        Decoder d;
        QVector<Decoder::Event> ev;
        QCOMPARE(d.feed(header, &ev), Decoder::Status::ProtocolError);
        QCOMPARE(d.feed(textFrame("x"), &ev), Decoder::Status::ProtocolError);
        QCOMPARE(ev.size(), 0);
        d.reset();
        QVERIFY(!d.hasError());
        QCOMPARE(d.feed(textFrame("x"), &ev), Decoder::Status::Ok);
        QCOMPARE(ev.size(), 1);
    }
};

QTEST_APPLESS_MAIN(TstWebSocketFrameDecoder)
#include "tst_websocket_frame_decoder.moc"
