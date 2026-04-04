#include "OpenNavigationProvider.h"

#include <QJsonArray>
#include <QJsonObject>
#include <QUrlQuery>
#include <QtMath>

namespace {
double jsonNumber(const QJsonValue &value, double fallback = 0.0)
{
    if (value.isDouble()) {
        return value.toDouble();
    }
    if (value.isString()) {
        bool ok = false;
        const double parsed = value.toString().toDouble(&ok);
        if (ok) {
            return parsed;
        }
    }
    return fallback;
}

QString firstNonEmpty(const QStringList &values, const QString &fallback = QString())
{
    for (const QString &value : values) {
        if (!value.trimmed().isEmpty()) {
            return value.trimmed();
        }
    }
    return fallback;
}

double resultDistance(double originLat, double originLng, double lat, double lng, double fallback)
{
    if (!qIsFinite(originLat) || !qIsFinite(originLng)) {
        return fallback;
    }
    static constexpr double kEarthRadius = 6371000.0;
    const double dLat = qDegreesToRadians(lat - originLat);
    const double dLng = qDegreesToRadians(lng - originLng);
    const double lat1 = qDegreesToRadians(originLat);
    const double lat2 = qDegreesToRadians(lat);
    const double sinLat = qSin(dLat / 2.0);
    const double sinLng = qSin(dLng / 2.0);
    const double h = sinLat * sinLat + qCos(lat1) * qCos(lat2) * sinLng * sinLng;
    return 2.0 * kEarthRadius * qAsin(qSqrt(qBound(0.0, h, 1.0)));
}
} // namespace

OpenNavigationProvider::OpenNavigationProvider()
    : m_geocoderUrl(qEnvironmentVariableIsSet("BEAGLEY_NAV_GEOCODER_URL")
            ? QString::fromUtf8(qgetenv("BEAGLEY_NAV_GEOCODER_URL")).trimmed()
            : QStringLiteral("https://photon.komoot.io/api"))
    , m_fallbackGeocoderUrl(qEnvironmentVariableIsSet("BEAGLEY_NAV_FALLBACK_GEOCODER_URL")
            ? QString::fromUtf8(qgetenv("BEAGLEY_NAV_FALLBACK_GEOCODER_URL")).trimmed()
            : QStringLiteral("https://nominatim.openstreetmap.org/search"))
    , m_routerUrl(qEnvironmentVariableIsSet("BEAGLEY_NAV_ROUTER_URL")
            ? QString::fromUtf8(qgetenv("BEAGLEY_NAV_ROUTER_URL")).trimmed()
            : QStringLiteral("https://router.project-osrm.org/route/v1/driving"))
{
}

QNetworkRequest OpenNavigationProvider::buildSearchRequest(const QString &query) const
{
    QUrl url(m_geocoderUrl);
    QUrlQuery urlQuery(url);
    urlQuery.addQueryItem(QStringLiteral("limit"), QStringLiteral("5"));
    urlQuery.addQueryItem(QStringLiteral("q"), query);
    url.setQuery(urlQuery);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    return request;
}

QNetworkRequest OpenNavigationProvider::buildFallbackSearchRequest(const QString &query) const
{
    QUrl url(m_fallbackGeocoderUrl);
    QUrlQuery urlQuery(url);
    urlQuery.addQueryItem(QStringLiteral("format"), QStringLiteral("jsonv2"));
    urlQuery.addQueryItem(QStringLiteral("limit"), QStringLiteral("5"));
    urlQuery.addQueryItem(QStringLiteral("q"), query);
    url.setQuery(urlQuery);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("User-Agent", QByteArrayLiteral("BeagleyCluster/1.0"));
    return request;
}

QList<SearchResultData> OpenNavigationProvider::parseSearchResponse(const QByteArray &payload, double originLat, double originLng) const
{
    QList<SearchResultData> results;
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (doc.isObject()) {
        const QVariantMap root = doc.object().toVariantMap();
        const QVariantList features = root.value(QStringLiteral("features")).toList();
        for (int index = 0; index < features.size(); ++index) {
            const SearchResultData result = parseFeatureResult(features.at(index).toMap(), originLat, originLng, index);
            if (!result.label.isEmpty()) {
                results.append(result);
            }
        }
    } else if (doc.isArray()) {
        const QVariantList items = doc.array().toVariantList();
        for (int index = 0; index < items.size(); ++index) {
            const SearchResultData result = parseNominatimResult(items.at(index).toMap(), originLat, originLng, index);
            if (!result.label.isEmpty()) {
                results.append(result);
            }
        }
    }
    std::sort(results.begin(), results.end(), [](const SearchResultData &left, const SearchResultData &right) {
        if (qFuzzyCompare(left.distanceMeters, right.distanceMeters)) {
            return left.primary < right.primary;
        }
        return left.distanceMeters < right.distanceMeters;
    });
    return results;
}

QNetworkRequest OpenNavigationProvider::buildRouteRequest(double originLat, double originLng, double destLat, double destLng) const
{
    Q_UNUSED(originLat)
    Q_UNUSED(originLng)
    Q_UNUSED(destLat)
    Q_UNUSED(destLng)

    QNetworkRequest request(QUrl(m_routerUrl
        + QStringLiteral("/")
        + QString::number(originLng, 'f', 6)
        + QStringLiteral(",")
        + QString::number(originLat, 'f', 6)
        + QStringLiteral(";")
        + QString::number(destLng, 'f', 6)
        + QStringLiteral(",")
        + QString::number(destLat, 'f', 6)
        + QStringLiteral("?overview=full&geometries=geojson&steps=true&alternatives=false")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    return request;
}

QByteArray OpenNavigationProvider::buildRouteBody(double originLat, double originLng, double destLat, double destLng) const
{
    Q_UNUSED(originLat)
    Q_UNUSED(originLng)
    Q_UNUSED(destLat)
    Q_UNUSED(destLng)
    return QByteArray();
}

RouteData OpenNavigationProvider::parseRouteResponse(const QByteArray &payload, const QVariantMap &destination) const
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isObject()) {
        return {};
    }
    return parseOsrmRoute(doc.object().toVariantMap(), destination);
}

bool OpenNavigationProvider::searchUsesPost() const
{
    return false;
}

bool OpenNavigationProvider::routeUsesPost() const
{
    return false;
}

QString OpenNavigationProvider::geocoderUrl() const
{
    return m_geocoderUrl;
}

QString OpenNavigationProvider::fallbackGeocoderUrl() const
{
    return m_fallbackGeocoderUrl;
}

QString OpenNavigationProvider::routerUrl() const
{
    return m_routerUrl;
}

double OpenNavigationProvider::metersBetween(double aLat, double aLng, double bLat, double bLng)
{
    static constexpr double kEarthRadius = 6371000.0;
    const double dLat = qDegreesToRadians(bLat - aLat);
    const double dLng = qDegreesToRadians(bLng - aLng);
    const double lat1 = qDegreesToRadians(aLat);
    const double lat2 = qDegreesToRadians(bLat);
    const double sinLat = qSin(dLat / 2.0);
    const double sinLng = qSin(dLng / 2.0);
    const double h = sinLat * sinLat + qCos(lat1) * qCos(lat2) * sinLng * sinLng;
    return 2.0 * kEarthRadius * qAsin(qSqrt(qBound(0.0, h, 1.0)));
}

QString OpenNavigationProvider::trimmedJoin(const QStringList &parts)
{
    QStringList filtered;
    for (const QString &part : parts) {
        const QString trimmed = part.trimmed();
        if (!trimmed.isEmpty()) {
            filtered.append(trimmed);
        }
    }
    return filtered.join(QStringLiteral(", "));
}

QVariantMap OpenNavigationProvider::searchResultToVariant(const SearchResultData &result)
{
    return {
        {QStringLiteral("id"), result.id},
        {QStringLiteral("label"), result.label},
        {QStringLiteral("primary"), result.primary},
        {QStringLiteral("secondary"), result.secondary},
        {QStringLiteral("lat"), result.lat},
        {QStringLiteral("lng"), result.lng},
        {QStringLiteral("distanceMeters"), result.distanceMeters},
    };
}

QString OpenNavigationProvider::formatInstruction(const QString &type, const QString &modifier, const QString &road, int exitNumber)
{
    const QString lowerType = type.trimmed().toLower();
    const QString lowerModifier = modifier.trimmed().toLower();
    QString base = QStringLiteral("Continue");

    if (lowerType == QLatin1String("depart")) {
        base = QStringLiteral("Depart");
    } else if (lowerType == QLatin1String("arrive")) {
        base = QStringLiteral("Arrive");
    } else if (lowerType == QLatin1String("turn")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("Turn") : QStringLiteral("Turn %1").arg(lowerModifier);
    } else if (lowerType == QLatin1String("merge")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("Merge") : QStringLiteral("Merge %1").arg(lowerModifier);
    } else if (lowerType == QLatin1String("fork")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("Keep") : QStringLiteral("Keep %1").arg(lowerModifier);
    } else if (lowerType == QLatin1String("on ramp")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("Take ramp") : QStringLiteral("Take ramp %1").arg(lowerModifier);
    } else if (lowerType == QLatin1String("off ramp")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("Take exit") : QStringLiteral("Exit %1").arg(lowerModifier);
    } else if (lowerType == QLatin1String("roundabout") || lowerType == QLatin1String("rotary")) {
        base = exitNumber > 0
            ? QStringLiteral("At the roundabout, take exit %1").arg(exitNumber)
            : QStringLiteral("Enter roundabout");
    } else if (lowerType == QLatin1String("end of road")) {
        base = lowerModifier.isEmpty() ? QStringLiteral("At end of road") : QStringLiteral("At end, turn %1").arg(lowerModifier);
    }

    if (lowerType == QLatin1String("arrive")) {
        return road.isEmpty() ? QStringLiteral("Arrive at destination") : QStringLiteral("Arrive at %1").arg(road);
    }
    if (road.isEmpty()) {
        return base;
    }
    if (base == QLatin1String("Continue")) {
        return QStringLiteral("Continue on %1").arg(road);
    }
    if (base.startsWith(QLatin1String("At the roundabout"))) {
        return road.isEmpty() ? base : QStringLiteral("%1 onto %2").arg(base, road);
    }
    return QStringLiteral("%1 onto %2").arg(base, road);
}

SearchResultData OpenNavigationProvider::parseFeatureResult(const QVariantMap &feature, double originLat, double originLng, int index) const
{
    const QVariantMap properties = feature.value(QStringLiteral("properties")).toMap();
    const QVariantMap geometry = feature.value(QStringLiteral("geometry")).toMap();
    const QVariantList coordinates = geometry.value(QStringLiteral("coordinates")).toList();
    if (coordinates.size() < 2) {
        return {};
    }

    const double lng = coordinates.at(0).toDouble();
    const double lat = coordinates.at(1).toDouble();
    if (!qIsFinite(lat) || !qIsFinite(lng)) {
        return {};
    }

    SearchResultData result;
    result.id = QStringLiteral("search-%1").arg(index);
    result.primary = firstNonEmpty({
        properties.value(QStringLiteral("name")).toString(),
        properties.value(QStringLiteral("street")).toString(),
        properties.value(QStringLiteral("city")).toString(),
        properties.value(QStringLiteral("country")).toString(),
        QStringLiteral("Destination"),
    });
    result.secondary = trimmedJoin({
        properties.value(QStringLiteral("street")).toString(),
        properties.value(QStringLiteral("city")).toString(),
        properties.value(QStringLiteral("state")).toString(),
        properties.value(QStringLiteral("country")).toString(),
    });
    result.label = trimmedJoin({
        properties.value(QStringLiteral("name")).toString(),
        properties.value(QStringLiteral("street")).toString(),
        properties.value(QStringLiteral("city")).toString(),
        properties.value(QStringLiteral("state")).toString(),
        properties.value(QStringLiteral("country")).toString(),
    });
    result.lat = lat;
    result.lng = lng;
    result.distanceMeters = resultDistance(originLat, originLng, lat, lng, index);
    return result;
}

SearchResultData OpenNavigationProvider::parseNominatimResult(const QVariantMap &item, double originLat, double originLng, int index) const
{
    const double lat = item.value(QStringLiteral("lat")).toString().toDouble();
    const double lng = item.value(QStringLiteral("lon")).toString().toDouble();
    if (!qIsFinite(lat) || !qIsFinite(lng)) {
        return {};
    }

    const QString label = item.value(QStringLiteral("display_name")).toString().trimmed();
    const QStringList parts = label.split(QLatin1Char(','));

    SearchResultData result;
    result.id = QStringLiteral("search-%1").arg(index);
    result.label = label;
    result.primary = parts.mid(0, 2).join(QStringLiteral(", ")).trimmed();
    result.secondary = parts.mid(2).join(QStringLiteral(", ")).trimmed();
    if (result.primary.isEmpty()) {
        result.primary = label;
    }
    if (result.secondary.isEmpty()) {
        result.secondary = QStringLiteral("OpenStreetMap result");
    }
    result.lat = lat;
    result.lng = lng;
    result.distanceMeters = resultDistance(originLat, originLng, lat, lng, index);
    return result;
}

RouteData OpenNavigationProvider::parseOsrmRoute(const QVariantMap &root, const QVariantMap &destination) const
{
    RouteData data;
    data.destination = destination;

    const QVariantList routes = root.value(QStringLiteral("routes")).toList();
    if (routes.isEmpty()) {
        return data;
    }

    const QVariantMap route = routes.first().toMap();
    const QVariantMap geometry = route.value(QStringLiteral("geometry")).toMap();
    const QVariantList coordinates = geometry.value(QStringLiteral("coordinates")).toList();
    if (coordinates.size() < 2) {
        return data;
    }

    data.distanceMeters = route.value(QStringLiteral("distance")).toDouble();
    data.durationSeconds = route.value(QStringLiteral("duration")).toDouble();
    data.geometry = coordinates;

    int stepIndex = 0;
    const QVariantList legs = route.value(QStringLiteral("legs")).toList();
    for (const QVariant &legValue : legs) {
        const QVariantMap leg = legValue.toMap();
        const QVariantList steps = leg.value(QStringLiteral("steps")).toList();
        for (const QVariant &stepValue : steps) {
            const QVariantMap step = stepValue.toMap();
            const QVariantMap maneuver = step.value(QStringLiteral("maneuver")).toMap();
            const QVariantList location = maneuver.value(QStringLiteral("location")).toList();
            if (location.size() < 2) {
                continue;
            }

            RouteManeuverData item;
            item.id = QStringLiteral("maneuver-%1").arg(stepIndex++);
            item.type = maneuver.value(QStringLiteral("type")).toString();
            item.modifier = maneuver.value(QStringLiteral("modifier")).toString();
            item.road = firstNonEmpty({
                step.value(QStringLiteral("name")).toString(),
                step.value(QStringLiteral("ref")).toString(),
            });
            item.exit = maneuver.value(QStringLiteral("exit")).toInt();
            item.instruction = formatInstruction(item.type, item.modifier, item.road, item.exit);
            item.lat = location.at(1).toDouble();
            item.lng = location.at(0).toDouble();
            item.distanceMeters = step.value(QStringLiteral("distance")).toDouble();
            item.durationSeconds = step.value(QStringLiteral("duration")).toDouble();
            data.maneuvers.append(item);
        }
    }

    return data;
}
