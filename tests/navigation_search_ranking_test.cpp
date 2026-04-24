#include "navigation/OpenNavigationProvider.h"

#include <QUrlQuery>

#include <iostream>

namespace {

int g_failures = 0;

void expectTrue(bool condition, const char *message)
{
    if (condition) {
        return;
    }
    std::cerr << "FAIL: " << message << "\n";
    ++g_failures;
}

void expectEqual(const QString &actual, const QString &expected, const char *message)
{
    if (actual == expected) {
        return;
    }
    std::cerr << "FAIL: " << message << "\n";
    std::cerr << "  expected: " << expected.toStdString() << "\n";
    std::cerr << "  actual:   " << actual.toStdString() << "\n";
    ++g_failures;
}

void testPlaceSearchRequestUsesPhoton()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QNetworkRequest request = provider.buildSearchRequest(QStringLiteral("Noosa"), -26.4597, 153.0);
    const QUrl url = request.url();
    const QUrlQuery query(url);

    expectTrue(url.host().contains(QStringLiteral("photon"), Qt::CaseInsensitive), "place search should use Photon");
    expectEqual(query.queryItemValue(QStringLiteral("q")), QStringLiteral("Noosa"), "place search query preserved");
    expectEqual(query.queryItemValue(QStringLiteral("lat")), QStringLiteral("-26.459700"), "place search lat bias applied");
    expectEqual(query.queryItemValue(QStringLiteral("lon")), QStringLiteral("153.000000"), "place search lon bias applied");
    expectTrue(query.queryItemValue(QStringLiteral("bounded")).isEmpty(), "place search should not be bounded");
}

void testAddressSearchRequestUsesBoundedNominatim()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QNetworkRequest request = provider.buildSearchRequest(QStringLiteral("1 Hastings Street"), -26.3897, 153.0910);
    const QUrl url = request.url();
    const QUrlQuery query(url);

    expectTrue(url.host().contains(QStringLiteral("nominatim"), Qt::CaseInsensitive), "address search should use Nominatim");
    expectEqual(query.queryItemValue(QStringLiteral("layer")), QStringLiteral("address"), "address search should request address layer");
    expectEqual(query.queryItemValue(QStringLiteral("bounded")), QStringLiteral("1"), "address search should be locally bounded first");
    expectEqual(query.queryItemValue(QStringLiteral("countrycodes")), QStringLiteral("au"), "address search should keep local country hint");

    const QNetworkRequest fallback = provider.buildFallbackSearchRequest(QStringLiteral("1 Hastings Street"), -26.3897, 153.0910);
    const QUrlQuery fallbackQuery(fallback.url());
    expectTrue(fallbackQuery.queryItemValue(QStringLiteral("bounded")).isEmpty(), "address fallback should broaden beyond the bounded first pass");
}

void testPlaceRankingPrefersSettlementOverNearbyPoi()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray payload = R"JSON(
{
  "features": [
    {
      "properties": {
        "name": "Noosa National Park",
        "city": "Marcus Beach",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "leisure",
        "osm_value": "nature_reserve",
        "type": "other"
      },
      "geometry": { "type": "Point", "coordinates": [153.091471, -26.4473531] }
    },
    {
      "properties": {
        "name": "Noosa Airport",
        "city": "Noosa Heads",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "aeroway",
        "osm_value": "aerodrome",
        "type": "house"
      },
      "geometry": { "type": "Point", "coordinates": [153.0634959, -26.422261] }
    },
    {
      "properties": {
        "name": "Noosa Heads",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "boundary",
        "osm_value": "administrative",
        "type": "district"
      },
      "geometry": { "type": "Point", "coordinates": [153.091049, -26.40014] }
    },
    {
      "properties": {
        "name": "Noosaville",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "boundary",
        "osm_value": "administrative",
        "type": "district"
      },
      "geometry": { "type": "Point", "coordinates": [153.05751, -26.4248421] }
    },
    {
      "properties": {
        "name": "Noosa Heads",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "place",
        "osm_value": "town",
        "type": "city"
      },
      "geometry": { "type": "Point", "coordinates": [153.0897466, -26.3970775] }
    }
  ]
}
)JSON";

    const QList<SearchResultData> results = provider.parseSearchResponse(payload, QStringLiteral("Noosa"), -26.4597, 153.0);
    expectTrue(!results.isEmpty(), "ranked Noosa results should not be empty");
    if (results.isEmpty()) {
        return;
    }

    expectEqual(results.first().primary, QStringLiteral("Noosa Heads"), "settlement result should outrank nearby airport");
    expectTrue(!results.first().label.contains(QStringLiteral("Airport"), Qt::CaseInsensitive), "top ranked Noosa result should not be the airport");
}

} // namespace

int main()
{
    testPlaceSearchRequestUsesPhoton();
    testAddressSearchRequestUsesBoundedNominatim();
    testPlaceRankingPrefersSettlementOverNearbyPoi();

    if (g_failures == 0) {
        std::cout << "navigation_search_ranking_test: PASS\n";
        return 0;
    }

    std::cerr << "navigation_search_ranking_test: " << g_failures << " failure(s)\n";
    return 1;
}
