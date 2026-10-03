#pragma once

#include <QByteArray>
#include <QString>

// Central runtime-configuration defaults for the vehicle-state link.
// Header-only on purpose (no CMake source-list change; easy to unit test).
namespace ClusterConfig {

// Default BBB vehicle-hub endpoint for the codex line. Scripts, env examples and
// the Yocto defaults use the same value; override at runtime with VEHICLE_HUB_WS_URL.
inline QString defaultHubUrl()
{
    return QStringLiteral("ws://10.24.0.7:8765");
}

// Hub URL after applying the VEHICLE_HUB_WS_URL override (empty/unset -> default).
inline QString hubUrl()
{
    const QString fromEnv = QString::fromUtf8(qgetenv("VEHICLE_HUB_WS_URL")).trimmed();
    return fromEnv.isEmpty() ? defaultHubUrl() : fromEnv;
}

// Raster map tile template for the keyless fallback map (and the radar base layer).
// Default: OpenStreetMap standard tiles. NOTE: OSM's tile usage policy requires a valid
// identifying User-Agent (the app sends one) and forbids heavy use; point this at your own
// tile server / a licensed provider for production fleets. Carto's old keyless
// light_all/dark_all/voyager endpoints now return an "API KEY REQUIRED" watermark and must
// not be used. Override with BEAGLEY_MAP_TILE_URL ({z}/{x}/{y} placeholders).
inline QString defaultMapTileUrl()
{
    return QStringLiteral("https://tile.openstreetmap.org/{z}/{x}/{y}.png");
}

inline QString mapTileUrl()
{
    const QString fromEnv = QString::fromUtf8(qgetenv("BEAGLEY_MAP_TILE_URL")).trimmed();
    return fromEnv.isEmpty() ? defaultMapTileUrl() : fromEnv;
}

// Whether the Dark map theme darkens the (light) fallback tiles locally. Default on;
// BEAGLEY_MAP_TILE_DARKEN=0 for a tile source that is already dark.
inline bool mapTileDarken()
{
    return !qEnvironmentVariableIsSet("BEAGLEY_MAP_TILE_DARKEN")
        || qEnvironmentVariableIntValue("BEAGLEY_MAP_TILE_DARKEN") != 0;
}

enum class VehicleBackend { Live, Mock };

// Resolve BEAGLEY_VEHICLE_BACKEND. Default is live. Anything but "mock"/"live"/empty
// falls back to live. The simulated mock backend is refused in the appliance
// production profile (BEAGLEY_APPLIANCE_PRODUCTION): it would put fake data on a
// real vehicle display. `warning` (optional) receives a message when the request
// was not honoured as given.
inline VehicleBackend resolveVehicleBackend(const QString &requested,
                                            bool applianceProduction,
                                            QString *warning = nullptr)
{
    const QString value = requested.trimmed().toLower();
    if (value == QLatin1String("mock")) {
        if (applianceProduction) {
            if (warning)
                *warning = QStringLiteral(
                    "BEAGLEY_VEHICLE_BACKEND=mock is not allowed in the appliance production "
                    "profile - using live");
            return VehicleBackend::Live;
        }
        return VehicleBackend::Mock;
    }
    if (!value.isEmpty() && value != QLatin1String("live") && warning)
        *warning = QStringLiteral("unknown BEAGLEY_VEHICLE_BACKEND '%1' - using live").arg(value);
    return VehicleBackend::Live;
}

} // namespace ClusterConfig
