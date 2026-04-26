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
    QString street;
    QString houseNumber;
    QString city;
    QString state;
    QString country;
    QString countryCode;
    QString category;
    QString resultType;
    QString addressType;
    QString osmKey;
    QString osmValue;
    double lat = 0.0;
    double lng = 0.0;
    double distanceMeters = 0.0;
    double importance = 0.0;
    double rankScore = 0.0;
    int sourceOrder = 0;
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

    QNetworkRequest buildSearchRequest(const QString &query, double originLat, double originLng) const;
    QNetworkRequest buildFallbackSearchRequest(const QString &query, double originLat, double originLng) const;
    QList<SearchResultData> parseSearchResponse(const QByteArray &payload, const QString &query, double originLat, double originLng) const;

    QNetworkRequest buildRouteRequest(double originLat, double originLng, double destLat, double destLng) const;
    QByteArray buildRouteBody(double originLat, double originLng, double destLat, double destLng) const;
    RouteData parseRouteResponse(const QByteArray &payload, const QVariantMap &destination) const;
    QList<RouteData> parseRouteAlternativesResponse(const QByteArray &payload, const QVariantMap &destination) const;

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
    RouteData parseOsrmRouteVariant(const QVariantMap &route, const QVariantMap &destination) const;

    QString m_geocoderUrl;
    QString m_fallbackGeocoderUrl;
    QString m_routerUrl;
    QString m_searchCountryCode;
    QString m_searchLanguage;
};
