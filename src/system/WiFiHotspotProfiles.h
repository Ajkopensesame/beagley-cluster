#pragma once

#include <QString>
#include <QVector>

namespace WiFiHotspotProfiles {

struct SavedProfile {
    QString id;
    QString ssid;
    int priority = 0;
    QString fallbackAddress;
    bool hasPsk = false;
};

QVector<SavedProfile> parseWpaSupplicantProfiles(const QString &contents);
SavedProfile findProfileForSsid(const QVector<SavedProfile> &profiles, const QString &ssid);

} // namespace WiFiHotspotProfiles
