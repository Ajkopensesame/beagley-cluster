#pragma once

#include <QJsonDocument>
#include <QNetworkRequest>
#include <QVariantList>
#include <QVariantMap>

struct SearchResultData
{
    QString id;
    QString label;
    QString primary;
    QString secondary;
    double lat = 0.0;
    double lng = 0.0;
    double distanceMeters = 0.0;
};

struct RouteManeuverData
{
    QString id;
    QString type;
    QString modifier;
    QString instruction;
    QString road;
    double lat = 0.0;
    double lng = 0.0;
    double distanceMeters = 0.0;
    double durationSeconds = 0.0;
    double progressMeters = 0.0;
    int exit = 0;
};

struct RouteData
{
    QVariantMap destination;
    QVariantList geometry;
    QList<RouteManeuverData> maneuvers;
    double distanceMeters = 0.0;
    double durationSeconds = 0.0;
};

class OpenNavigationProvider
{
public:
    OpenNavigationProvider();

    QNetworkRequest buildSearchRequest(const QString &query) const;
    QNetworkRequest buildFallbackSearchRequest(const QString &query) const;
    QList<SearchResultData> parseSearchResponse(const QByteArray &payload, double originLat, double originLng) const;

    QNetworkRequest buildRouteRequest(double originLat, double originLng, double destLat, double destLng) const;
    QByteArray buildRouteBody(double originLat, double originLng, double destLat, double destLng) const;
    RouteData parseRouteResponse(const QByteArray &payload, const QVariantMap &destination) const;

    bool searchUsesPost() const;
    bool routeUsesPost() const;
    QString geocoderUrl() const;
    QString fallbackGeocoderUrl() const;
    QString routerUrl() const;

private:
    static double metersBetween(double aLat, double aLng, double bLat, double bLng);
    static QString trimmedJoin(const QStringList &parts);
    static QVariantMap searchResultToVariant(const SearchResultData &result);
    static QString formatInstruction(const QString &type, const QString &modifier, const QString &road, int exitNumber);

    SearchResultData parseFeatureResult(const QVariantMap &feature, double originLat, double originLng, int index) const;
    SearchResultData parseNominatimResult(const QVariantMap &item, double originLat, double originLng, int index) const;
    RouteData parseOsrmRoute(const QVariantMap &root, const QVariantMap &destination) const;

    QString m_geocoderUrl;
    QString m_fallbackGeocoderUrl;
    QString m_routerUrl;
};
