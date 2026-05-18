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

void testNearMeCategorySearchUsesLocalProviderHints()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QNetworkRequest request = provider.buildSearchRequest(QStringLiteral("servo near me"), -26.4597, 153.0);
    const QUrlQuery query(request.url());

    expectTrue(request.url().host().contains(QStringLiteral("photon"), Qt::CaseInsensitive), "category search should still use Photon first");
    expectEqual(query.queryItemValue(QStringLiteral("q")), QStringLiteral("petrol station"), "servo near me should become a provider-friendly local fuel query");
    expectEqual(query.queryItemValue(QStringLiteral("osm_tag")), QStringLiteral("amenity:fuel"), "fuel category should constrain Photon by OSM tag");

    const QNetworkRequest fallback = provider.buildFallbackSearchRequest(QStringLiteral("chemist near me"), -26.4597, 153.0);
    const QUrlQuery fallbackQuery(fallback.url());
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("q")), QStringLiteral("pharmacy"), "chemist near me should become pharmacy for fallback search");
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("bounded")), QStringLiteral("1"), "near-me category fallback should stay inside local viewbox");
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("countrycodes")), QStringLiteral("au"), "near-me category fallback should keep local country hint");
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

void testLocalCategoryRankingUnderstandsAustralianAliases()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray payload = R"JSON(
{
  "features": [
    {
      "properties": {
        "name": "Servo",
        "country": "Italy",
        "countrycode": "IT",
        "osm_key": "place",
        "osm_value": "village",
        "type": "city"
      },
      "geometry": { "type": "Point", "coordinates": [11.7876309, 46.0583563] }
    },
    {
      "properties": {
        "name": "Puma Petrol Station",
        "street": "David Low Way",
        "city": "Peregian Beach",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "amenity",
        "osm_value": "fuel",
        "type": "house"
      },
      "geometry": { "type": "Point", "coordinates": [153.0938557, -26.489616] }
    }
  ]
}
)JSON";

    const QList<SearchResultData> results = provider.parseSearchResponse(payload, QStringLiteral("servo near me"), -26.4597, 153.0);
    expectTrue(!results.isEmpty(), "servo alias results should not be empty");
    if (results.isEmpty()) {
        return;
    }
    expectEqual(results.first().primary, QStringLiteral("Puma Petrol Station"), "local fuel POI should outrank global places named Servo");
}

void testAddressRankingPrefersClosestMatchingRoad()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray payload = R"JSON(
[
  {
    "display_name": "David Low Way, Maroochydore, Queensland, 4558, Australia",
    "lat": "-26.6570300",
    "lon": "153.0890900",
    "category": "highway",
    "type": "secondary",
    "addresstype": "road",
    "importance": 0.95,
    "address": {
      "road": "David Low Way",
      "city": "Maroochydore",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  },
  {
    "display_name": "David Low Way, Peregian Beach, Queensland, 4573, Australia",
    "lat": "-26.4896160",
    "lon": "153.0938557",
    "category": "highway",
    "type": "secondary",
    "addresstype": "road",
    "importance": 0.25,
    "address": {
      "road": "David Low Way",
      "suburb": "Peregian Beach",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  }
]
)JSON";

    const QList<SearchResultData> results = provider.parseSearchResponse(payload, QStringLiteral("David Low Way"), -26.4897, 153.0940);
    expectTrue(!results.isEmpty(), "address ranking results should not be empty");
    if (results.isEmpty()) {
        return;
    }
    expectTrue(results.first().label.contains(QStringLiteral("Peregian Beach")), "closest matching road should rank before farther high-importance road");
}

void testPartialAddressPredictionUsesLocalAddressFallback()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QNetworkRequest primary = provider.buildSearchRequest(QStringLiteral("David Low"), -26.4593, 152.9990);
    const QUrl primaryUrl = primary.url();

    expectTrue(primaryUrl.host().contains(QStringLiteral("photon"), Qt::CaseInsensitive),
        "partial address prediction should keep Photon as the fast autocomplete primary");

    const QNetworkRequest fallback = provider.buildFallbackSearchRequest(QStringLiteral("David Low"), -26.4593, 152.9990);
    const QUrlQuery fallbackQuery(fallback.url());

    expectTrue(fallback.url().host().contains(QStringLiteral("nominatim"), Qt::CaseInsensitive),
        "partial address prediction fallback should use Nominatim");
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("layer")), QStringLiteral("address"),
        "partial address prediction fallback should request the address layer");
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("bounded")), QStringLiteral("1"),
        "partial address prediction fallback should stay bounded near the vehicle");
    expectEqual(fallbackQuery.queryItemValue(QStringLiteral("countrycodes")), QStringLiteral("au"),
        "partial address prediction fallback should keep the local country hint");
}

void testPartialAddressRankingPrefersNearbyStreetPrediction()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray payload = R"JSON(
[
  {
    "display_name": "David Low Way, Maroochydore, Queensland, 4558, Australia",
    "lat": "-26.6570300",
    "lon": "153.0890900",
    "category": "highway",
    "type": "secondary",
    "addresstype": "road",
    "importance": 0.95,
    "address": {
      "road": "David Low Way",
      "city": "Maroochydore",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  },
  {
    "display_name": "David Low Way, Peregian Beach, Queensland, 4573, Australia",
    "lat": "-26.4896160",
    "lon": "153.0938557",
    "category": "highway",
    "type": "secondary",
    "addresstype": "road",
    "importance": 0.25,
    "address": {
      "road": "David Low Way",
      "suburb": "Peregian Beach",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  }
]
)JSON";

    const QList<SearchResultData> results = provider.parseSearchResponse(payload, QStringLiteral("David Low"), -26.4593, 152.9990);
    expectTrue(!results.isEmpty(), "partial address ranking results should not be empty");
    if (results.isEmpty()) {
        return;
    }
    expectTrue(results.first().label.contains(QStringLiteral("Peregian Beach")), "nearby street prediction should rank before farther high-importance road");
}

void testPartialAddressMergeKeepsCloserAutocompleteFirst()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray photonPayload = R"JSON(
{
  "features": [
    {
      "properties": {
        "name": "David Low Way",
        "city": "Peregian Beach",
        "state": "Queensland",
        "country": "Australia",
        "countrycode": "AU",
        "osm_key": "highway",
        "osm_value": "primary",
        "type": "street"
      },
      "geometry": { "type": "Point", "coordinates": [153.0956146, -26.4787904] }
    }
  ]
}
)JSON";
    const QByteArray nominatimPayload = R"JSON(
[
  {
    "display_name": "David Low Way, Yaroomba, Coolum Beach, Queensland, 4573, Australia",
    "lat": "-26.5583100",
    "lon": "153.0954100",
    "category": "highway",
    "type": "primary",
    "addresstype": "road",
    "importance": 0.95,
    "address": {
      "road": "David Low Way",
      "suburb": "Yaroomba",
      "city": "Coolum Beach",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  }
]
)JSON";

    const QList<SearchResultData> primary = provider.parseSearchResponse(photonPayload, QStringLiteral("David Low"), -26.4593, 152.9990);
    expectTrue(provider.shouldRunFallbackSearch(primary, QStringLiteral("David Low")), "partial address autocomplete should run local refinement");
    const QList<SearchResultData> fallback = provider.parseSearchResponse(nominatimPayload, QStringLiteral("David Low"), -26.4593, 152.9990);
    const QList<SearchResultData> merged = provider.mergeSearchResults(primary, fallback);
    expectTrue(!merged.isEmpty(), "merged partial address results should not be empty");
    if (merged.isEmpty()) {
        return;
    }
    expectTrue(merged.first().label.contains(QStringLiteral("Peregian Beach")), "closer autocomplete result should stay first after fallback merge");
}

void testWeakCategorySearchRefinesWithFallbackMerge()
{
    qputenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE", "AU");
    OpenNavigationProvider provider;
    const QByteArray photonPayload = R"JSON(
{
  "features": [
    {
      "properties": {
        "name": "Supermarket",
        "city": "Thiniscole/Siniscola",
        "country": "Italy",
        "countrycode": "IT",
        "osm_key": "shop",
        "osm_value": "supermarket",
        "type": "house"
      },
      "geometry": { "type": "Point", "coordinates": [9.6969838, 40.5753426] }
    }
  ]
}
)JSON";
    const QByteArray nominatimPayload = R"JSON(
[
  {
    "display_name": "Woolworths, Poinciana Avenue, Tewantin, Queensland, 4565, Australia",
    "lat": "-26.3911409",
    "lon": "153.0382864",
    "name": "Woolworths",
    "category": "shop",
    "type": "supermarket",
    "addresstype": "shop",
    "importance": 0.5,
    "address": {
      "road": "Poinciana Avenue",
      "town": "Tewantin",
      "state": "Queensland",
      "country": "Australia",
      "country_code": "au"
    }
  }
]
)JSON";

    const QList<SearchResultData> primary = provider.parseSearchResponse(photonPayload, QStringLiteral("supermarket near me"), -26.4597, 153.0);
    expectTrue(provider.shouldRunFallbackSearch(primary, QStringLiteral("supermarket near me")), "far generic category result should trigger fallback refinement");

    const QList<SearchResultData> fallback = provider.parseSearchResponse(nominatimPayload, QStringLiteral("supermarket near me"), -26.4597, 153.0);
    const QList<SearchResultData> merged = provider.mergeSearchResults(primary, fallback);
    expectTrue(!merged.isEmpty(), "merged category results should not be empty");
    if (merged.isEmpty()) {
        return;
    }
    expectEqual(merged.first().primary, QStringLiteral("Woolworths"), "local fallback result should replace weak global category result at top");
}

} // namespace

int main()
{
    testPlaceSearchRequestUsesPhoton();
    testAddressSearchRequestUsesBoundedNominatim();
    testNearMeCategorySearchUsesLocalProviderHints();
    testPlaceRankingPrefersSettlementOverNearbyPoi();
    testLocalCategoryRankingUnderstandsAustralianAliases();
    testAddressRankingPrefersClosestMatchingRoad();
    testPartialAddressPredictionUsesLocalAddressFallback();
    testPartialAddressRankingPrefersNearbyStreetPrediction();
    testPartialAddressMergeKeepsCloserAutocompleteFirst();
    testWeakCategorySearchRefinesWithFallbackMerge();

    if (g_failures == 0) {
        std::cout << "navigation_search_ranking_test: PASS\n";
        return 0;
    }

    std::cerr << "navigation_search_ranking_test: " << g_failures << " failure(s)\n";
    return 1;
}
