#include "WiFiSsidUtils.h"

#include <QRegularExpression>
#include <QSet>

namespace {

int hexValue(QChar c)
{
    if (c >= QLatin1Char('0') && c <= QLatin1Char('9')) {
        return c.unicode() - QLatin1Char('0').unicode();
    }
    if (c >= QLatin1Char('a') && c <= QLatin1Char('f')) {
        return 10 + (c.unicode() - QLatin1Char('a').unicode());
    }
    if (c >= QLatin1Char('A') && c <= QLatin1Char('F')) {
        return 10 + (c.unicode() - QLatin1Char('A').unicode());
    }
    return -1;
}

} // namespace

namespace WiFiSsidUtils {

QString decodeIwEscapedSsid(const QString &rawSsid)
{
    QByteArray decodedBytes;
    decodedBytes.reserve(rawSsid.size());

    int i = 0;
    while (i < rawSsid.size()) {
        if (i + 3 < rawSsid.size() &&
            rawSsid[i] == QLatin1Char('\\') &&
            rawSsid[i + 1] == QLatin1Char('x')) {
            const int hi = hexValue(rawSsid[i + 2]);
            const int lo = hexValue(rawSsid[i + 3]);
            if (hi >= 0 && lo >= 0) {
                decodedBytes.append(static_cast<char>((hi << 4) | lo));
                i += 4;
                continue;
            }
        }

        const QString oneChar = rawSsid.mid(i, 1);
        decodedBytes.append(oneChar.toUtf8());
        ++i;
    }

    return QString::fromUtf8(decodedBytes);
}

QString normalizeSsidForConnect(const QString &ssid)
{
    return decodeIwEscapedSsid(ssid).trimmed();
}

QVector<ScanRow> parseIwScanNetworks(const QString &scanText)
{
    QVector<ScanRow> rows;
    QSet<QString> seenSsids;

    const auto appendRow = [&](const QString &rawSsid, double signalDbm, bool secure) {
        const QString decoded = decodeIwEscapedSsid(rawSsid).trimmed();
        if (decoded.isEmpty() || seenSsids.contains(decoded)) {
            return;
        }

        seenSsids.insert(decoded);
        rows.push_back(ScanRow{decoded, signalDbm, secure});
    };

    QString currentSsid;
    double currentSignal = -999.0;
    bool currentSecure = false;

    const auto flushCurrent = [&]() {
        appendRow(currentSsid, currentSignal, currentSecure);
    };

    const QStringList lines = scanText.split(QLatin1Char('\n'));
    const QRegularExpression signalRe(QStringLiteral("^\\s*signal:\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*dBm"),
                                      QRegularExpression::CaseInsensitiveOption);
    const QRegularExpression ssidRe(QStringLiteral("^\\s*SSID:\\s*(.*)$"));

    for (const QString &line : lines) {
        if (line.startsWith(QStringLiteral("BSS "))) {
            flushCurrent();
            currentSsid.clear();
            currentSignal = -999.0;
            currentSecure = false;
            continue;
        }

        if (!line.startsWith(QStringLiteral("bssid")) && line.contains(QLatin1Char('\t'))) {
            const QStringList columns = line.split(QLatin1Char('\t'));
            if (columns.size() >= 5) {
                bool signalOk = false;
                const double signal = columns.at(2).trimmed().toDouble(&signalOk);
                const QString flags = columns.at(3);
                const QString ssid = columns.mid(4).join(QLatin1Char('\t')).trimmed();
                if (signalOk) {
                    appendRow(ssid,
                              signal,
                              flags.contains(QStringLiteral("WPA"), Qt::CaseInsensitive));
                    continue;
                }
            }
        }

        const QRegularExpressionMatch signalMatch = signalRe.match(line);
        if (signalMatch.hasMatch()) {
            currentSignal = signalMatch.captured(1).toDouble();
            continue;
        }

        const QRegularExpressionMatch ssidMatch = ssidRe.match(line);
        if (ssidMatch.hasMatch()) {
            currentSsid = ssidMatch.captured(1).trimmed();
            continue;
        }

        const QString trimmed = line.trimmed();
        if (trimmed.startsWith(QStringLiteral("RSN:")) ||
            trimmed.startsWith(QStringLiteral("WPA:"))) {
            currentSecure = true;
        }
    }

    flushCurrent();
    return rows;
}

} // namespace WiFiSsidUtils
