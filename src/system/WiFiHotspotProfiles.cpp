#include "WiFiHotspotProfiles.h"

#include <QRegularExpression>

namespace {

QString stripOuterQuotes(const QString &value)
{
    QString trimmed = value.trimmed();
    if (trimmed.size() >= 2 && trimmed.startsWith(QLatin1Char('"')) && trimmed.endsWith(QLatin1Char('"'))) {
        trimmed = trimmed.mid(1, trimmed.size() - 2);
    }
    trimmed.replace(QStringLiteral("\\\""), QStringLiteral("\""));
    trimmed.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
    return trimmed;
}

} // namespace

namespace WiFiHotspotProfiles {

QVector<SavedProfile> parseWpaSupplicantProfiles(const QString &contents)
{
    QVector<SavedProfile> profiles;

    QString pendingId;
    QString pendingFallback;
    SavedProfile current;
    bool inNetwork = false;

    const QRegularExpression markerRe(QStringLiteral(R"(^#\s*BEAGLEY_PROFILE(?:\s+id=([^\s]+))?(?:\s+fallback=([^\s]+))?\s*$)"));
    const QRegularExpression ssidRe(QStringLiteral(R"(^\s*ssid=(.+)\s*$)"));
    const QRegularExpression pskRe(QStringLiteral(R"(^\s*psk=(.+)\s*$)"));
    const QRegularExpression priorityRe(QStringLiteral(R"(^\s*priority=(\d+)\s*$)"));
    const QRegularExpression idStrRe(QStringLiteral(R"(^\s*id_str=(.+)\s*$)"));

    const QStringList lines = contents.split(QLatin1Char('\n'));
    for (const QString &rawLine : lines) {
        const QString line = rawLine.trimmed();

        const QRegularExpressionMatch markerMatch = markerRe.match(line);
        if (markerMatch.hasMatch()) {
            pendingId = markerMatch.captured(1).trimmed();
            pendingFallback = markerMatch.captured(2).trimmed();
            if (pendingFallback == QStringLiteral("-") || pendingFallback == QStringLiteral("none")) {
                pendingFallback.clear();
            }
            continue;
        }

        if (line == QStringLiteral("network={")) {
            inNetwork = true;
            current = SavedProfile{};
            current.id = pendingId;
            current.fallbackAddress = pendingFallback;
            continue;
        }

        if (!inNetwork) {
            continue;
        }

        if (line == QStringLiteral("}")) {
            if (!current.ssid.isEmpty()) {
                profiles.append(current);
            }
            inNetwork = false;
            pendingId.clear();
            pendingFallback.clear();
            current = SavedProfile{};
            continue;
        }

        const QRegularExpressionMatch ssidMatch = ssidRe.match(line);
        if (ssidMatch.hasMatch()) {
            current.ssid = stripOuterQuotes(ssidMatch.captured(1));
            continue;
        }

        const QRegularExpressionMatch pskMatch = pskRe.match(line);
        if (pskMatch.hasMatch()) {
            Q_UNUSED(pskMatch);
            current.hasPsk = true;
            continue;
        }

        const QRegularExpressionMatch priorityMatch = priorityRe.match(line);
        if (priorityMatch.hasMatch()) {
            current.priority = priorityMatch.captured(1).toInt();
            continue;
        }

        const QRegularExpressionMatch idStrMatch = idStrRe.match(line);
        if (idStrMatch.hasMatch() && current.id.isEmpty()) {
            current.id = stripOuterQuotes(idStrMatch.captured(1));
        }
    }

    return profiles;
}

SavedProfile findProfileForSsid(const QVector<SavedProfile> &profiles, const QString &ssid)
{
    SavedProfile best;
    bool found = false;

    for (const SavedProfile &profile : profiles) {
        if (profile.ssid != ssid) {
            continue;
        }
        if (!found || profile.priority > best.priority) {
            best = profile;
            found = true;
        }
    }

    return best;
}

} // namespace WiFiHotspotProfiles
