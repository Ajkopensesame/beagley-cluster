#pragma once

#include <QString>
#include <QVector>

namespace WiFiSsidUtils {

struct ScanRow {
    QString ssid;
    double signalDbm = -999.0;
    bool secure = false;
};

QString decodeIwEscapedSsid(const QString &rawSsid);
QString normalizeSsidForConnect(const QString &ssid);
QVector<ScanRow> parseIwScanNetworks(const QString &scanText);

} // namespace WiFiSsidUtils
