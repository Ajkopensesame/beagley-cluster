#pragma once

#include <QJsonObject>
#include <QJsonValue>
#include <QString>

// Pure helpers for the vehicle-hub `vehicle_state` wire contract
// (https://github.com/Ajkopensesame/vehicle-hub, PROTOCOL.md).
namespace VehicleStateFrame {

// Good-frame rule: only a frame with the four gauge keys AND the indicators,
// warnings and _health objects refreshes the link-health clock. Partial frames are
// still applied by the client but do not keep the link alive.
inline bool isGood(const QJsonObject &obj)
{
    return obj.contains(QStringLiteral("speedKph"))
        && obj.contains(QStringLiteral("rpm"))
        && obj.contains(QStringLiteral("fuelPct"))
        && obj.contains(QStringLiteral("coolantC"))
        && obj.value(QStringLiteral("indicators")).isObject()
        && obj.value(QStringLiteral("warnings")).isObject()
        && obj.value(QStringLiteral("_health")).isObject();
}

} // namespace VehicleStateFrame
