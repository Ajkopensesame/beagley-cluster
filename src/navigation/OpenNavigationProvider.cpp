#include "OpenNavigationProvider.h"

#include <QLocale>
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>
#include <QUrlQuery>
#include <QtMath>

#include <algorithm>
#include <limits>

namespace {
constexpr int kSearchResultLimit = 8;
constexpr int kPhotonBiasZoom = 12;
constexpr double kPhotonBiasScale = 0.15;
constexpr double kNominatimViewboxRadiusKm = 60.0;

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

QString defaultSearchCountryCode()
{
    if (qEnvironmentVariableIsSet("BEAGLEY_NAV_SEARCH_COUNTRYCODE")) {
        return QString::fromUtf8(qgetenv("BEAGLEY_NAV_SEARCH_COUNTRYCODE")).trimmed().left(2).toUpper();
    }

    const QString localeName = QLocale::system().name();
    const int separator = localeName.indexOf(QLatin1Char('_'));
    return separator >= 0 ? localeName.mid(separator + 1).left(2).toUpper() : QString();
}

QString defaultSearchLanguage()
{
    if (qEnvironmentVariableIsSet("BEAGLEY_NAV_SEARCH_LANGUAGE")) {
        return QString::fromUtf8(qgetenv("BEAGLEY_NAV_SEARCH_LANGUAGE")).trimmed();
    }

    const QString language = QLocale::system().bcp47Name().trimmed();
    return language == QLatin1String("C") ? QString() : language;
}

QString photonLanguageCode(const QString &language)
{
    if (language.isEmpty()) {
        return {};
    }

    QString normalized = language.trimmed();
    const int dash = normalized.indexOf(QLatin1Char('-'));
    if (dash >= 0) {
        normalized = normalized.left(dash);
    }
    const int underscore = normalized.indexOf(QLatin1Char('_'));
    if (underscore >= 0) {
        normalized = normalized.left(underscore);
    }
    return normalized.toLower();
}

QString normalizedText(const QString &value)
{
    const QString decomposed = value.normalized(QString::NormalizationForm_D).toLower();
    QString out;
    out.reserve(decomposed.size());
    bool lastWasSpace = true;

    for (const QChar ch : decomposed) {
        if (ch.category() == QChar::Mark_NonSpacing || ch.category() == QChar::Mark_SpacingCombining) {
            continue;
        }
        if (ch.isLetterOrNumber()) {
            out.append(ch);
            lastWasSpace = false;
        } else if (!lastWasSpace) {
            out.append(QLatin1Char(' '));
            lastWasSpace = true;
        }
    }

    return out.trimmed().simplified();
}

QStringList tokenizeWords(const QString &value)
{
    const QString normalized = normalizedText(value);
    return normalized.isEmpty()
        ? QStringList()
        : normalized.split(QLatin1Char(' '), Qt::SkipEmptyParts);
}

void replaceTokenPhrase(QString *value, const QString &phrase, const QString &replacement)
{
    if (!value || value->isEmpty() || phrase.isEmpty()) {
        return;
    }

    QString padded = QStringLiteral(" ") + value->simplified() + QStringLiteral(" ");
    padded.replace(QStringLiteral(" ") + phrase + QStringLiteral(" "),
        QStringLiteral(" ") + replacement + QStringLiteral(" "));
    *value = padded.trimmed().simplified();
}

bool isSearchFillerToken(const QString &token)
{
    static const QStringList fillerTokens = {
        QStringLiteral("near"),
        QStringLiteral("nearby"),
        QStringLiteral("nearest"),
        QStringLiteral("closest"),
        QStringLiteral("around"),
        QStringLiteral("me"),
        QStringLiteral("my"),
        QStringLiteral("current"),
        QStringLiteral("location"),
        QStringLiteral("open"),
        QStringLiteral("now"),
    };
    return fillerTokens.contains(token);
}

bool queryHasNearMeIntent(const QString &query)
{
    const QString normalized = normalizedText(query);
    const QString padded = QStringLiteral(" ") + normalized + QStringLiteral(" ");
    return padded.contains(QStringLiteral(" near me "))
        || padded.contains(QStringLiteral(" nearby "))
        || padded.contains(QStringLiteral(" nearest "))
        || padded.contains(QStringLiteral(" closest "))
        || padded.contains(QStringLiteral(" around me "))
        || padded.contains(QStringLiteral(" current location "));
}

QString stripSearchIntentFillers(const QString &query)
{
    const QStringList tokens = tokenizeWords(query);
    QStringList kept;
    for (const QString &token : tokens) {
        if (!isSearchFillerToken(token)) {
            kept.append(token);
        }
    }
    return kept.join(QLatin1Char(' ')).simplified();
}

QString canonicalSearchQuery(const QString &query)
{
    QString normalized = stripSearchIntentFillers(query);
    if (normalized.isEmpty()) {
        normalized = normalizedText(query);
    }

    replaceTokenPhrase(&normalized, QStringLiteral("petrol stations"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("service stations"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("service station"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("gas stations"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("gas station"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("fuel stations"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("fuel station"), QStringLiteral("petrol station"));
    if (!normalized.contains(QStringLiteral("petrol station"))) {
        replaceTokenPhrase(&normalized, QStringLiteral("petrol"), QStringLiteral("petrol station"));
        replaceTokenPhrase(&normalized, QStringLiteral("fuel"), QStringLiteral("petrol station"));
        replaceTokenPhrase(&normalized, QStringLiteral("gas"), QStringLiteral("petrol station"));
    }
    replaceTokenPhrase(&normalized, QStringLiteral("servos"), QStringLiteral("petrol station"));
    replaceTokenPhrase(&normalized, QStringLiteral("servo"), QStringLiteral("petrol station"));

    replaceTokenPhrase(&normalized, QStringLiteral("coffee shops"), QStringLiteral("cafe"));
    replaceTokenPhrase(&normalized, QStringLiteral("coffee shop"), QStringLiteral("cafe"));
    replaceTokenPhrase(&normalized, QStringLiteral("coffees"), QStringLiteral("cafe"));
    replaceTokenPhrase(&normalized, QStringLiteral("coffee"), QStringLiteral("cafe"));
    replaceTokenPhrase(&normalized, QStringLiteral("cafes"), QStringLiteral("cafe"));

    replaceTokenPhrase(&normalized, QStringLiteral("chemists"), QStringLiteral("pharmacy"));
    replaceTokenPhrase(&normalized, QStringLiteral("chemist"), QStringLiteral("pharmacy"));
    replaceTokenPhrase(&normalized, QStringLiteral("drugstore"), QStringLiteral("pharmacy"));

    replaceTokenPhrase(&normalized, QStringLiteral("groceries"), QStringLiteral("supermarket"));
    replaceTokenPhrase(&normalized, QStringLiteral("grocery stores"), QStringLiteral("supermarket"));
    replaceTokenPhrase(&normalized, QStringLiteral("grocery store"), QStringLiteral("supermarket"));
    replaceTokenPhrase(&normalized, QStringLiteral("grocery"), QStringLiteral("supermarket"));
    replaceTokenPhrase(&normalized, QStringLiteral("supermarkets"), QStringLiteral("supermarket"));

    replaceTokenPhrase(&normalized, QStringLiteral("car parks"), QStringLiteral("parking"));
    replaceTokenPhrase(&normalized, QStringLiteral("car park"), QStringLiteral("parking"));
    replaceTokenPhrase(&normalized, QStringLiteral("parks"), QStringLiteral("park"));

    replaceTokenPhrase(&normalized, QStringLiteral("toilets"), QStringLiteral("toilet"));
    replaceTokenPhrase(&normalized, QStringLiteral("bathrooms"), QStringLiteral("toilet"));
    replaceTokenPhrase(&normalized, QStringLiteral("bathroom"), QStringLiteral("toilet"));
    replaceTokenPhrase(&normalized, QStringLiteral("restrooms"), QStringLiteral("toilet"));
    replaceTokenPhrase(&normalized, QStringLiteral("restroom"), QStringLiteral("toilet"));

    replaceTokenPhrase(&normalized, QStringLiteral("maccas"), QStringLiteral("mcdonalds"));
    replaceTokenPhrase(&normalized, QStringLiteral("woolies"), QStringLiteral("woolworths"));

    return normalized.simplified();
}

QString providerSearchQuery(const QString &query)
{
    const QString trimmed = query.trimmed();
    const QString canonical = canonicalSearchQuery(trimmed);
    if (canonical.isEmpty()) {
        return trimmed;
    }
    return canonical == normalizedText(trimmed) ? trimmed : canonical;
}

QStringList categoryIntentTokens(const QString &query)
{
    QStringList tokens = tokenizeWords(canonicalSearchQuery(query));
    const QString normalized = tokens.join(QLatin1Char(' '));
    const QString padded = QStringLiteral(" ") + normalized + QStringLiteral(" ");

    if (padded.contains(QStringLiteral(" petrol station "))) {
        tokens << QStringLiteral("fuel") << QStringLiteral("petrol") << QStringLiteral("station")
               << QStringLiteral("servo") << QStringLiteral("service") << QStringLiteral("gas");
    }
    if (padded.contains(QStringLiteral(" cafe "))) {
        tokens << QStringLiteral("coffee") << QStringLiteral("cafe");
    }
    if (padded.contains(QStringLiteral(" pharmacy "))) {
        tokens << QStringLiteral("chemist") << QStringLiteral("pharmacy") << QStringLiteral("drugstore");
    }
    if (padded.contains(QStringLiteral(" supermarket "))) {
        tokens << QStringLiteral("supermarket") << QStringLiteral("grocery") << QStringLiteral("groceries")
               << QStringLiteral("woolies") << QStringLiteral("woolworths") << QStringLiteral("coles");
    }
    if (padded.contains(QStringLiteral(" toilet "))) {
        tokens << QStringLiteral("toilet") << QStringLiteral("toilets") << QStringLiteral("bathroom")
               << QStringLiteral("restroom") << QStringLiteral("loo");
    }
    if (padded.contains(QStringLiteral(" parking "))) {
        tokens << QStringLiteral("parking") << QStringLiteral("carpark") << QStringLiteral("car") << QStringLiteral("park");
    }
    if (padded.contains(QStringLiteral(" restaurant "))) {
        tokens << QStringLiteral("restaurant") << QStringLiteral("food") << QStringLiteral("dining") << QStringLiteral("eat");
    }
    if (padded.contains(QStringLiteral(" hospital "))) {
        tokens << QStringLiteral("hospital") << QStringLiteral("medical") << QStringLiteral("emergency");
    }
    if (padded.contains(QStringLiteral(" airport "))) {
        tokens << QStringLiteral("airport") << QStringLiteral("aerodrome") << QStringLiteral("airfield");
    }

    tokens.removeDuplicates();
    return tokens;
}

QString photonOsmTagForQuery(const QString &query)
{
    const QString normalized = categoryIntentTokens(query).join(QLatin1Char(' '));
    const QString padded = QStringLiteral(" ") + normalized + QStringLiteral(" ");
    if (padded.contains(QStringLiteral(" petrol ")) || padded.contains(QStringLiteral(" fuel ")) || padded.contains(QStringLiteral(" servo "))) {
        return QStringLiteral("amenity:fuel");
    }
    if (padded.contains(QStringLiteral(" cafe ")) || padded.contains(QStringLiteral(" coffee "))) {
        return QStringLiteral("amenity:cafe");
    }
    if (padded.contains(QStringLiteral(" pharmacy ")) || padded.contains(QStringLiteral(" chemist "))) {
        return QStringLiteral("amenity:pharmacy");
    }
    if (padded.contains(QStringLiteral(" supermarket ")) || padded.contains(QStringLiteral(" grocery "))) {
        return QStringLiteral("shop:supermarket");
    }
    if (padded.contains(QStringLiteral(" toilet "))) {
        return QStringLiteral("amenity:toilets");
    }
    if (padded.contains(QStringLiteral(" parking "))) {
        return QStringLiteral("amenity:parking");
    }
    if (padded.contains(QStringLiteral(" restaurant "))) {
        return QStringLiteral("amenity:restaurant");
    }
    if (padded.contains(QStringLiteral(" hospital "))) {
        return QStringLiteral("amenity:hospital");
    }
    return {};
}

bool queryLooksLocalCategoryLike(const QString &query)
{
    const QString canonical = canonicalSearchQuery(query);
    if (queryHasNearMeIntent(query) && canonical != normalizedText(query)) {
        return true;
    }
    return !photonOsmTagForQuery(query).isEmpty();
}

QString addressLine(const QString &houseNumber, const QString &street)
{
    if (houseNumber.trimmed().isEmpty()) {
        return street.trimmed();
    }
    if (street.trimmed().isEmpty()) {
        return houseNumber.trimmed();
    }
    return houseNumber.trimmed() + QStringLiteral(" ") + street.trimmed();
}

QString searchViewbox(double originLat, double originLng, double radiusKm)
{
    if (!qIsFinite(originLat) || !qIsFinite(originLng) || radiusKm <= 0.0) {
        return {};
    }

    const double latDelta = radiusKm / 111.0;
    const double lonScale = qMax(0.2, qAbs(qCos(qDegreesToRadians(originLat))));
    const double lonDelta = radiusKm / (111.320 * lonScale);
    const double minLon = qMax(-180.0, originLng - lonDelta);
    const double maxLon = qMin(180.0, originLng + lonDelta);
    const double north = qMin(90.0, originLat + latDelta);
    const double south = qMax(-90.0, originLat - latDelta);

    return QStringLiteral("%1,%2,%3,%4")
        .arg(QString::number(minLon, 'f', 6),
             QString::number(north, 'f', 6),
             QString::number(maxLon, 'f', 6),
             QString::number(south, 'f', 6));
}

int prefixMatchCount(const QStringList &queryTokens, const QStringList &candidateTokens)
{
    int matches = 0;
    for (const QString &queryToken : queryTokens) {
        const auto found = std::find_if(candidateTokens.begin(), candidateTokens.end(), [&queryToken](const QString &candidate) {
            return candidate.startsWith(queryToken);
        });
        if (found != candidateTokens.end()) {
            ++matches;
        }
    }
    return matches;
}

QString firstQueryNumber(const QStringList &queryTokens)
{
    for (const QString &token : queryTokens) {
        for (const QChar ch : token) {
            if (ch.isDigit()) {
                return token;
            }
        }
    }
    return {};
}

bool tokenHasDigit(const QString &token)
{
    for (const QChar ch : token) {
        if (ch.isDigit()) {
            return true;
        }
    }
    return false;
}

bool isStreetTypeToken(const QString &token)
{
    static const QStringList streetTokens = {
        QStringLiteral("street"),
        QStringLiteral("st"),
        QStringLiteral("road"),
        QStringLiteral("rd"),
        QStringLiteral("avenue"),
        QStringLiteral("ave"),
        QStringLiteral("drive"),
        QStringLiteral("dr"),
        QStringLiteral("lane"),
        QStringLiteral("ln"),
        QStringLiteral("court"),
        QStringLiteral("ct"),
        QStringLiteral("place"),
        QStringLiteral("pl"),
        QStringLiteral("parade"),
        QStringLiteral("pde"),
        QStringLiteral("terrace"),
        QStringLiteral("tce"),
        QStringLiteral("crescent"),
        QStringLiteral("cres"),
        QStringLiteral("close"),
        QStringLiteral("circuit"),
        QStringLiteral("cct"),
        QStringLiteral("boulevard"),
        QStringLiteral("blvd"),
        QStringLiteral("highway"),
        QStringLiteral("hwy"),
        QStringLiteral("way"),
    };
    return streetTokens.contains(token);
}

bool queryLooksAddressLike(const QString &query)
{
    const QStringList tokens = tokenizeWords(query);
    if (tokens.isEmpty()) {
        return false;
    }

    for (const QString &token : tokens) {
        if (tokenHasDigit(token)) {
            return true;
        }
    }

    for (int index = 1; index < tokens.size(); ++index) {
        if (isStreetTypeToken(tokens.at(index))) {
            return true;
        }
    }

    return false;
}

bool queryLooksIncompleteNumericAddress(const QString &query)
{
    const QStringList tokens = tokenizeWords(query);
    bool hasNumber = false;
    bool hasUsefulText = false;
    for (const QString &token : tokens) {
        if (tokenHasDigit(token)) {
            hasNumber = true;
            continue;
        }
        if (isStreetTypeToken(token)) {
            return false;
        }
        if (token.size() >= 2) {
            hasUsefulText = true;
        }
    }
    return hasNumber && hasUsefulText;
}

QString incompleteNumericAddressPredictionQuery(const QString &query)
{
    QStringList kept;
    for (const QString &token : tokenizeWords(query)) {
        if (!tokenHasDigit(token) && !isSearchFillerToken(token)) {
            kept.append(token);
        }
    }
    return kept.join(QLatin1Char(' ')).simplified();
}

bool queryLooksAddressPredictionLike(const QString &query)
{
    if (queryLooksAddressLike(query)) {
        return true;
    }
    if (queryLooksLocalCategoryLike(query) || queryHasNearMeIntent(query)) {
        return false;
    }

    const QStringList tokens = tokenizeWords(query);
    if (tokens.size() < 2) {
        return false;
    }

    int usefulTokens = 0;
    for (const QString &token : tokens) {
        if (token.size() >= 2) {
            ++usefulTokens;
        }
    }

    return usefulTokens >= 2;
}

bool resultLooksSettlement(const SearchResultData &result)
{
    static const QStringList settlementTypes = {
        QStringLiteral("city"),
        QStringLiteral("district"),
        QStringLiteral("locality"),
        QStringLiteral("county"),
        QStringLiteral("state"),
        QStringLiteral("country"),
    };
    static const QStringList settlementAddressTypes = {
        QStringLiteral("city"),
        QStringLiteral("town"),
        QStringLiteral("village"),
        QStringLiteral("hamlet"),
        QStringLiteral("suburb"),
        QStringLiteral("neighbourhood"),
        QStringLiteral("municipality"),
        QStringLiteral("county"),
        QStringLiteral("state"),
        QStringLiteral("country"),
        QStringLiteral("district"),
    };

    const QString resultType = normalizedText(result.resultType);
    const QString addressType = normalizedText(result.addressType);
    const QString osmKey = normalizedText(result.osmKey);
    const QString osmValue = normalizedText(result.osmValue);
    const QString category = normalizedText(result.category);

    return settlementTypes.contains(resultType)
        || settlementAddressTypes.contains(addressType)
        || osmKey == QLatin1String("place")
        || (osmKey == QLatin1String("boundary") && osmValue == QLatin1String("administrative"))
        || category == QLatin1String("boundary");
}

bool resultLooksStreet(const SearchResultData &result)
{
    const QString resultType = normalizedText(result.resultType);
    const QString addressType = normalizedText(result.addressType);
    const QString osmKey = normalizedText(result.osmKey);
    const QString category = normalizedText(result.category);

    return resultType == QLatin1String("street")
        || addressType == QLatin1String("road")
        || osmKey == QLatin1String("highway")
        || category == QLatin1String("highway");
}

bool resultLooksAddressPoint(const SearchResultData &result)
{
    const QString resultType = normalizedText(result.resultType);
    const QString addressType = normalizedText(result.addressType);
    const QString osmValue = normalizedText(result.osmValue);

    return !result.houseNumber.trimmed().isEmpty()
        || (!result.street.trimmed().isEmpty()
            && (resultType == QLatin1String("house")
                || addressType == QLatin1String("house")
                || addressType == QLatin1String("building")
                || addressType == QLatin1String("place")
                || osmValue == QLatin1String("house")));
}

bool resultLooksNatural(const SearchResultData &result)
{
    const QString category = normalizedText(result.category);
    const QString osmKey = normalizedText(result.osmKey);
    const QString osmValue = normalizedText(result.osmValue);

    return category == QLatin1String("natural")
        || category == QLatin1String("waterway")
        || osmKey == QLatin1String("natural")
        || osmKey == QLatin1String("waterway")
        || (osmKey == QLatin1String("leisure") && osmValue == QLatin1String("nature reserve"));
}

bool resultLooksPoi(const SearchResultData &result)
{
    if (resultLooksSettlement(result) || resultLooksStreet(result)) {
        return false;
    }

    static const QStringList poiKeys = {
        QStringLiteral("amenity"),
        QStringLiteral("shop"),
        QStringLiteral("tourism"),
        QStringLiteral("leisure"),
        QStringLiteral("aeroway"),
        QStringLiteral("railway"),
        QStringLiteral("historic"),
        QStringLiteral("office"),
        QStringLiteral("craft"),
        QStringLiteral("emergency"),
        QStringLiteral("healthcare"),
        QStringLiteral("sport"),
        QStringLiteral("public transport"),
        QStringLiteral("building"),
    };

    const QString osmKey = normalizedText(result.osmKey);
    const QString category = normalizedText(result.category);
    const QString resultType = normalizedText(result.resultType);

    return poiKeys.contains(osmKey)
        || poiKeys.contains(category)
        || (resultType == QLatin1String("house") && !resultLooksAddressPoint(result));
}

QStringList categoryTokens(const SearchResultData &result)
{
    QStringList tokens = tokenizeWords(result.osmKey
        + QLatin1Char(' ')
        + result.osmValue
        + QLatin1Char(' ')
        + result.category
        + QLatin1Char(' ')
        + result.resultType
        + QLatin1Char(' ')
        + result.addressType);

    const QString osmKey = normalizedText(result.osmKey);
    const QString osmValue = normalizedText(result.osmValue);
    if (osmKey == QLatin1String("aeroway") || osmValue == QLatin1String("aerodrome")) {
        tokens << QStringLiteral("airport") << QStringLiteral("airfield");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("fuel")) {
        tokens << QStringLiteral("fuel") << QStringLiteral("petrol") << QStringLiteral("station")
               << QStringLiteral("servo") << QStringLiteral("service") << QStringLiteral("gas");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("cafe")) {
        tokens << QStringLiteral("cafe") << QStringLiteral("coffee");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("pharmacy")) {
        tokens << QStringLiteral("pharmacy") << QStringLiteral("chemist") << QStringLiteral("drugstore");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("restaurant")) {
        tokens << QStringLiteral("restaurant") << QStringLiteral("food") << QStringLiteral("dining");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("fast food")) {
        tokens << QStringLiteral("restaurant") << QStringLiteral("food") << QStringLiteral("takeaway") << QStringLiteral("fast");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("toilets")) {
        tokens << QStringLiteral("toilet") << QStringLiteral("toilets") << QStringLiteral("bathroom")
               << QStringLiteral("restroom") << QStringLiteral("loo");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("parking")) {
        tokens << QStringLiteral("parking") << QStringLiteral("carpark") << QStringLiteral("car") << QStringLiteral("park");
    }
    if (osmKey == QLatin1String("amenity") && osmValue == QLatin1String("hospital")) {
        tokens << QStringLiteral("hospital") << QStringLiteral("medical") << QStringLiteral("emergency");
    }
    if (osmKey == QLatin1String("shop") && osmValue == QLatin1String("supermarket")) {
        tokens << QStringLiteral("supermarket") << QStringLiteral("grocery") << QStringLiteral("groceries")
               << QStringLiteral("woolies") << QStringLiteral("woolworths") << QStringLiteral("coles");
    }
    if (osmKey == QLatin1String("shop") && osmValue == QLatin1String("mall")) {
        tokens << QStringLiteral("mall") << QStringLiteral("shopping") << QStringLiteral("centre") << QStringLiteral("center");
    }
    if (osmKey == QLatin1String("leisure") && osmValue == QLatin1String("nature reserve")) {
        tokens << QStringLiteral("park") << QStringLiteral("reserve") << QStringLiteral("national");
    }
    if (normalizedText(result.category) == QLatin1String("highway")) {
        tokens << QStringLiteral("street") << QStringLiteral("road");
    }

    tokens.removeDuplicates();
    return tokens;
}

bool queryMatchesCategory(const QStringList &queryTokens, const SearchResultData &result)
{
    const QStringList categories = categoryTokens(result);
    for (const QString &queryToken : queryTokens) {
        for (const QString &categoryToken : categories) {
            if (categoryToken == queryToken
                || (queryToken.size() >= 3 && categoryToken.startsWith(queryToken))
                || (categoryToken.size() >= 3 && queryToken.startsWith(categoryToken))) {
                return true;
            }
        }
    }
    return false;
}

double distanceScore(double distanceMeters)
{
    if (!qIsFinite(distanceMeters) || distanceMeters < 0.0) {
        return 0.0;
    }
    if (distanceMeters <= 5000.0) {
        return 18.0;
    }
    if (distanceMeters <= 20000.0) {
        return 12.0;
    }
    if (distanceMeters <= 60000.0) {
        return 8.0;
    }
    if (distanceMeters <= 150000.0) {
        return 4.0;
    }
    return 0.0;
}

double addressDistanceScore(double distanceMeters)
{
    if (!qIsFinite(distanceMeters) || distanceMeters < 0.0) {
        return 0.0;
    }
    if (distanceMeters <= 500.0) {
        return 70.0;
    }
    if (distanceMeters <= 2000.0) {
        return 58.0;
    }
    if (distanceMeters <= 5000.0) {
        return 46.0;
    }
    if (distanceMeters <= 10000.0) {
        return 44.0;
    }
    if (distanceMeters <= 15000.0) {
        return 34.0;
    }
    if (distanceMeters <= 30000.0) {
        return 22.0;
    }
    if (distanceMeters <= 60000.0) {
        return 10.0;
    }
    if (distanceMeters <= 150000.0) {
        return -24.0;
    }
    return -70.0;
}

double localIntentDistancePenalty(double distanceMeters)
{
    if (!qIsFinite(distanceMeters) || distanceMeters < 0.0) {
        return 0.0;
    }
    if (distanceMeters > 1000000.0) {
        return -280.0;
    }
    if (distanceMeters > 150000.0) {
        return -80.0;
    }
    if (distanceMeters > 60000.0) {
        return -30.0;
    }
    return 0.0;
}

double textMatchScore(const QString &queryNormalized, const QStringList &queryTokens, const SearchResultData &result)
{
    const QString primaryNormalized = normalizedText(result.primary);
    const QString labelNormalized = normalizedText(result.label);
    const QStringList candidateTokens = tokenizeWords(result.primary
        + QLatin1Char(' ')
        + result.label
        + QLatin1Char(' ')
        + result.street
        + QLatin1Char(' ')
        + result.city
        + QLatin1Char(' ')
        + result.houseNumber);

    double score = 0.0;
    if (!queryNormalized.isEmpty()) {
        if (primaryNormalized == queryNormalized) {
            score += 120.0;
        } else if (labelNormalized == queryNormalized) {
            score += 105.0;
        }

        if (primaryNormalized.startsWith(queryNormalized + QLatin1Char(' '))) {
            score += 85.0;
        } else if (labelNormalized.startsWith(queryNormalized + QLatin1Char(' '))) {
            score += 70.0;
        } else if (primaryNormalized.contains(queryNormalized)) {
            score += 35.0;
        } else if (labelNormalized.contains(queryNormalized)) {
            score += 25.0;
        }
    }

    const int matchedTokens = prefixMatchCount(queryTokens, candidateTokens);
    score += matchedTokens * 12.0;
    if (!queryTokens.isEmpty()) {
        if (matchedTokens == queryTokens.size()) {
            score += 24.0;
        } else if (matchedTokens == 0) {
            score -= 35.0;
        }
    }

    return score;
}

double categoryIntentScore(const SearchResultData &result, const QStringList &categoryQueryTokens)
{
    if (!queryMatchesCategory(categoryQueryTokens, result)) {
        return 0.0;
    }

    if (resultLooksPoi(result)) {
        return 38.0;
    }
    if (resultLooksStreet(result)) {
        return 18.0;
    }
    if (resultLooksNatural(result)) {
        return 14.0;
    }
    if (resultLooksSettlement(result)) {
        return -14.0;
    }
    return 10.0;
}

double addressIntentScore(const SearchResultData &result, const QStringList &queryTokens, const QStringList &categoryQueryTokens)
{
    double score = 0.0;

    if (resultLooksAddressPoint(result)) {
        score += 42.0;
    } else if (resultLooksStreet(result)) {
        score += 30.0;
    } else if (resultLooksSettlement(result)) {
        score += 16.0;
    } else if (resultLooksNatural(result)) {
        score -= 16.0;
    }

    if (resultLooksPoi(result) && !queryMatchesCategory(categoryQueryTokens, result)) {
        score -= 32.0;
    }

    const QString queryNumber = firstQueryNumber(queryTokens);
    if (!queryNumber.isEmpty()) {
        const QStringList houseTokens = tokenizeWords(result.houseNumber);
        if (!houseTokens.isEmpty()) {
            if (houseTokens.contains(queryNumber)) {
                score += 30.0;
            } else {
                score -= 24.0;
            }
        } else if (resultLooksStreet(result)) {
            score += 8.0;
        } else {
            score -= 12.0;
        }
    }

    return score;
}

double placeIntentScore(const SearchResultData &result, const QStringList &categoryQueryTokens)
{
    double score = 0.0;

    if (resultLooksSettlement(result)) {
        score += 42.0;
    } else if (resultLooksStreet(result)) {
        score += 18.0;
    } else if (resultLooksNatural(result)) {
        score += 10.0;
    } else if (resultLooksAddressPoint(result)) {
        score += 6.0;
    }

    if (resultLooksPoi(result) && !queryMatchesCategory(categoryQueryTokens, result)) {
        score -= 24.0;
    }

    return score;
}

double rankSearchResult(const SearchResultData &result, const QString &query, const QString &countryCodeHint)
{
    const QString effectiveQuery = canonicalSearchQuery(query);
    const QString queryNormalized = effectiveQuery.isEmpty() ? normalizedText(query) : effectiveQuery;
    const QStringList queryTokens = tokenizeWords(queryNormalized);
    const QStringList categoryQueryTokens = categoryIntentTokens(query);
    const bool addressLike = queryLooksAddressLike(queryNormalized);
    const bool addressPredictionLike = !addressLike && queryLooksAddressPredictionLike(queryNormalized);
    const bool addressMode = addressLike || addressPredictionLike;

    double score = textMatchScore(queryNormalized, queryTokens, result);
    score += categoryIntentScore(result, categoryQueryTokens);
    score += addressMode ? addressIntentScore(result, queryTokens, categoryQueryTokens) : placeIntentScore(result, categoryQueryTokens);
    score += distanceScore(result.distanceMeters);
    if (addressMode) {
        score += addressDistanceScore(result.distanceMeters);
    }
    if (addressPredictionLike) {
        if (resultLooksAddressPoint(result)) {
            score += 18.0;
        } else if (resultLooksStreet(result)) {
            score += 14.0;
        } else if (resultLooksPoi(result) && !queryMatchesCategory(categoryQueryTokens, result)) {
            score -= 14.0;
        }
    }
    if (queryLooksLocalCategoryLike(query) || queryHasNearMeIntent(query)) {
        score += localIntentDistancePenalty(result.distanceMeters);
    }
    score += qMin(8.0, result.importance * 12.0);
    score += qMax(0, kSearchResultLimit - result.sourceOrder) * 0.35;

    if (!countryCodeHint.isEmpty()
        && result.countryCode.compare(countryCodeHint, Qt::CaseInsensitive) == 0) {
        score += 10.0;
    }

    return score;
}

void sortSearchResults(QList<SearchResultData> *results)
{
    if (!results) {
        return;
    }
    std::stable_sort(results->begin(), results->end(), [](const SearchResultData &left, const SearchResultData &right) {
        if (qAbs(left.rankScore - right.rankScore) > 0.01) {
            return left.rankScore > right.rankScore;
        }
        if (qAbs(left.distanceMeters - right.distanceMeters) > 0.5) {
            return left.distanceMeters < right.distanceMeters;
        }
        if (left.sourceOrder != right.sourceOrder) {
            return left.sourceOrder < right.sourceOrder;
        }
        return left.primary < right.primary;
    });
}

bool sameSearchResult(const SearchResultData &left, const SearchResultData &right)
{
    const QString leftPrimary = normalizedText(left.primary);
    const QString rightPrimary = normalizedText(right.primary);
    const QString leftLabel = normalizedText(left.label);
    const QString rightLabel = normalizedText(right.label);
    const double distance = resultDistance(left.lat, left.lng, right.lat, right.lng, std::numeric_limits<double>::infinity());

    if (qIsFinite(distance) && distance <= 35.0) {
        return true;
    }
    if (!leftPrimary.isEmpty()
        && leftPrimary == rightPrimary
        && qIsFinite(distance)
        && distance <= 250.0) {
        return true;
    }
    if (!leftLabel.isEmpty()
        && leftLabel == rightLabel) {
        return true;
    }
    return false;
}

bool keepForIncompleteNumericAddress(const SearchResultData &result, const QString &countryCodeHint)
{
    if (!countryCodeHint.isEmpty()
        && !result.countryCode.isEmpty()
        && result.countryCode.compare(countryCodeHint, Qt::CaseInsensitive) != 0) {
        return false;
    }
    if (qIsFinite(result.distanceMeters)
        && result.distanceMeters >= 0.0
        && result.distanceMeters > 250000.0) {
        return false;
    }
    return true;
}

QList<SearchResultData> limitedSearchResults(QList<SearchResultData> results)
{
    sortSearchResults(&results);
    while (results.size() > kSearchResultLimit) {
        results.removeLast();
    }
    return results;
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
    , m_searchCountryCode(defaultSearchCountryCode())
    , m_searchLanguage(defaultSearchLanguage())
{
}

QNetworkRequest OpenNavigationProvider::buildSearchRequest(const QString &query, double originLat, double originLng) const
{
    const QString effectiveQuery = providerSearchQuery(query);

    if (queryLooksAddressLike(effectiveQuery)) {
        QUrl url(m_fallbackGeocoderUrl);
        QUrlQuery urlQuery(url);
        urlQuery.addQueryItem(QStringLiteral("format"), QStringLiteral("jsonv2"));
        urlQuery.addQueryItem(QStringLiteral("limit"), QString::number(kSearchResultLimit));
        urlQuery.addQueryItem(QStringLiteral("addressdetails"), QStringLiteral("1"));
        urlQuery.addQueryItem(QStringLiteral("layer"), QStringLiteral("address"));
        urlQuery.addQueryItem(QStringLiteral("bounded"), QStringLiteral("1"));
        urlQuery.addQueryItem(QStringLiteral("q"), effectiveQuery);
        if (!m_searchCountryCode.isEmpty()) {
            urlQuery.addQueryItem(QStringLiteral("countrycodes"), m_searchCountryCode.toLower());
        }
        const QString viewbox = searchViewbox(originLat, originLng, kNominatimViewboxRadiusKm);
        if (!viewbox.isEmpty()) {
            urlQuery.addQueryItem(QStringLiteral("viewbox"), viewbox);
        }
        url.setQuery(urlQuery);

        QNetworkRequest request(url);
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        request.setRawHeader("User-Agent", QByteArrayLiteral("BeagleyCluster/1.0"));
        if (!m_searchLanguage.isEmpty()) {
            request.setRawHeader("Accept-Language", m_searchLanguage.toUtf8());
        }
        return request;
    }

    QUrl url(m_geocoderUrl);
    QUrlQuery urlQuery(url);
    urlQuery.addQueryItem(QStringLiteral("limit"), QString::number(kSearchResultLimit));
    urlQuery.addQueryItem(QStringLiteral("q"), effectiveQuery);
    if (qIsFinite(originLat) && qIsFinite(originLng)) {
        urlQuery.addQueryItem(QStringLiteral("lat"), QString::number(originLat, 'f', 6));
        urlQuery.addQueryItem(QStringLiteral("lon"), QString::number(originLng, 'f', 6));
        urlQuery.addQueryItem(QStringLiteral("zoom"), QString::number(kPhotonBiasZoom));
        urlQuery.addQueryItem(QStringLiteral("location_bias_scale"), QString::number(kPhotonBiasScale, 'f', 2));
    }
    const QString osmTag = photonOsmTagForQuery(query);
    if (!osmTag.isEmpty()) {
        urlQuery.addQueryItem(QStringLiteral("osm_tag"), osmTag);
    }
    const QString languageCode = photonLanguageCode(m_searchLanguage);
    if (!languageCode.isEmpty()) {
        urlQuery.addQueryItem(QStringLiteral("lang"), languageCode);
    }
    url.setQuery(urlQuery);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("User-Agent", QByteArrayLiteral("BeagleyCluster/1.0"));
    return request;
}

QNetworkRequest OpenNavigationProvider::buildFallbackSearchRequest(const QString &query, double originLat, double originLng) const
{
    const QString effectiveQuery = providerSearchQuery(query);
    if (queryLooksIncompleteNumericAddress(effectiveQuery)) {
        const QString predictionQuery = incompleteNumericAddressPredictionQuery(effectiveQuery);
        if (!predictionQuery.isEmpty()) {
            QUrl url(m_geocoderUrl);
            QUrlQuery urlQuery(url);
            urlQuery.addQueryItem(QStringLiteral("limit"), QString::number(kSearchResultLimit));
            urlQuery.addQueryItem(QStringLiteral("q"), predictionQuery);
            if (qIsFinite(originLat) && qIsFinite(originLng)) {
                urlQuery.addQueryItem(QStringLiteral("lat"), QString::number(originLat, 'f', 6));
                urlQuery.addQueryItem(QStringLiteral("lon"), QString::number(originLng, 'f', 6));
                urlQuery.addQueryItem(QStringLiteral("zoom"), QString::number(kPhotonBiasZoom));
                urlQuery.addQueryItem(QStringLiteral("location_bias_scale"), QString::number(kPhotonBiasScale, 'f', 2));
            }
            const QString languageCode = photonLanguageCode(m_searchLanguage);
            if (!languageCode.isEmpty()) {
                urlQuery.addQueryItem(QStringLiteral("lang"), languageCode);
            }
            url.setQuery(urlQuery);

            QNetworkRequest request(url);
            request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
            request.setRawHeader("User-Agent", QByteArrayLiteral("BeagleyCluster/1.0"));
            return request;
        }
    }

    QUrl url(m_fallbackGeocoderUrl);
    QUrlQuery urlQuery(url);
    const bool addressLike = queryLooksAddressLike(effectiveQuery);
    const bool addressPredictionLike = !addressLike && queryLooksAddressPredictionLike(effectiveQuery);
    const bool localIntent = queryLooksLocalCategoryLike(query);
    urlQuery.addQueryItem(QStringLiteral("format"), QStringLiteral("jsonv2"));
    urlQuery.addQueryItem(QStringLiteral("limit"), QString::number(kSearchResultLimit));
    urlQuery.addQueryItem(QStringLiteral("addressdetails"), QStringLiteral("1"));
    urlQuery.addQueryItem(QStringLiteral("q"), effectiveQuery);
    if (addressLike || addressPredictionLike) {
        urlQuery.addQueryItem(QStringLiteral("layer"), QStringLiteral("address"));
        if (!m_searchCountryCode.isEmpty()) {
            urlQuery.addQueryItem(QStringLiteral("countrycodes"), m_searchCountryCode.toLower());
        }
    } else if (localIntent && !m_searchCountryCode.isEmpty()) {
        urlQuery.addQueryItem(QStringLiteral("countrycodes"), m_searchCountryCode.toLower());
    }
    const QString viewbox = searchViewbox(originLat, originLng, kNominatimViewboxRadiusKm);
    if (!viewbox.isEmpty()) {
        urlQuery.addQueryItem(QStringLiteral("viewbox"), viewbox);
        if (localIntent || addressPredictionLike) {
            urlQuery.addQueryItem(QStringLiteral("bounded"), QStringLiteral("1"));
        }
    }
    url.setQuery(urlQuery);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("User-Agent", QByteArrayLiteral("BeagleyCluster/1.0"));
    if (!m_searchLanguage.isEmpty()) {
        request.setRawHeader("Accept-Language", m_searchLanguage.toUtf8());
    }
    return request;
}

QList<SearchResultData> OpenNavigationProvider::parseSearchResponse(const QByteArray &payload, const QString &query, double originLat, double originLng) const
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

    if (queryLooksIncompleteNumericAddress(canonicalSearchQuery(query))) {
        for (auto it = results.begin(); it != results.end();) {
            if (keepForIncompleteNumericAddress(*it, m_searchCountryCode)) {
                ++it;
            } else {
                it = results.erase(it);
            }
        }
    }

    for (SearchResultData &result : results) {
        result.rankScore = rankSearchResult(result, query, m_searchCountryCode);
    }

    return limitedSearchResults(results);
}

bool OpenNavigationProvider::shouldRunFallbackSearch(const QList<SearchResultData> &primaryResults, const QString &query) const
{
    if (primaryResults.isEmpty()) {
        return true;
    }
    if (queryLooksIncompleteNumericAddress(canonicalSearchQuery(query))) {
        return true;
    }
    if (queryLooksAddressLike(canonicalSearchQuery(query))) {
        return false;
    }
    if (queryLooksAddressPredictionLike(canonicalSearchQuery(query))) {
        return true;
    }

    const bool localIntent = queryLooksLocalCategoryLike(query) || queryHasNearMeIntent(query);
    if (!localIntent) {
        return false;
    }

    const SearchResultData &top = primaryResults.first();
    if (!qIsFinite(top.distanceMeters) || top.distanceMeters < 0.0) {
        return true;
    }
    if (top.distanceMeters > 20000.0) {
        return true;
    }
    return top.rankScore < 90.0;
}

QList<SearchResultData> OpenNavigationProvider::mergeSearchResults(const QList<SearchResultData> &primaryResults, const QList<SearchResultData> &fallbackResults) const
{
    QList<SearchResultData> merged;
    const auto appendOrReplace = [&merged](const SearchResultData &candidate) {
        for (SearchResultData &existing : merged) {
            if (!sameSearchResult(existing, candidate)) {
                continue;
            }
            if (candidate.rankScore > existing.rankScore
                || (qAbs(candidate.rankScore - existing.rankScore) <= 0.01 && candidate.distanceMeters < existing.distanceMeters)) {
                existing = candidate;
            }
            return;
        }
        merged.append(candidate);
    };

    for (const SearchResultData &result : primaryResults) {
        appendOrReplace(result);
    }
    for (const SearchResultData &result : fallbackResults) {
        appendOrReplace(result);
    }
    return limitedSearchResults(merged);
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
        + QStringLiteral("?overview=full&geometries=geojson&steps=true&alternatives=true")));
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
    const QList<RouteData> routes = parseRouteAlternativesResponse(payload, destination);
    return routes.isEmpty() ? RouteData{} : routes.first();
}

QList<RouteData> OpenNavigationProvider::parseRouteAlternativesResponse(const QByteArray &payload, const QVariantMap &destination) const
{
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isObject()) {
        return {};
    }

    QList<RouteData> parsedRoutes;
    const QVariantList routes = doc.object().toVariantMap().value(QStringLiteral("routes")).toList();
    for (const QVariant &routeValue : routes) {
        const RouteData route = parseOsrmRouteVariant(routeValue.toMap(), destination);
        if (route.geometry.size() >= 2) {
            parsedRoutes.append(route);
        }
    }
    return parsedRoutes;
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

    const QString name = properties.value(QStringLiteral("name")).toString().trimmed();
    const QString street = properties.value(QStringLiteral("street")).toString().trimmed();
    const QString houseNumber = properties.value(QStringLiteral("housenumber")).toString().trimmed();
    const QString city = firstNonEmpty({
        properties.value(QStringLiteral("city")).toString(),
        properties.value(QStringLiteral("district")).toString(),
        properties.value(QStringLiteral("county")).toString(),
    });
    const QString state = properties.value(QStringLiteral("state")).toString().trimmed();
    const QString country = properties.value(QStringLiteral("country")).toString().trimmed();
    const QString address = addressLine(houseNumber, street);

    SearchResultData result;
    result.id = QStringLiteral("search-photon-%1").arg(index);
    result.street = street;
    result.houseNumber = houseNumber;
    result.city = city;
    result.state = state;
    result.country = country;
    result.countryCode = properties.value(QStringLiteral("countrycode")).toString().trimmed().toUpper();
    result.category = properties.value(QStringLiteral("osm_key")).toString().trimmed();
    result.resultType = properties.value(QStringLiteral("type")).toString().trimmed();
    result.addressType = result.resultType;
    result.osmKey = properties.value(QStringLiteral("osm_key")).toString().trimmed();
    result.osmValue = properties.value(QStringLiteral("osm_value")).toString().trimmed();
    result.importance = properties.value(QStringLiteral("importance")).toDouble();
    result.sourceOrder = index;
    result.primary = firstNonEmpty({
        name,
        address,
        city,
        state,
        country,
        QStringLiteral("Destination"),
    });
    result.secondary = trimmedJoin({
        name.isEmpty() ? QString() : address,
        city,
        state,
        country,
    });
    result.label = trimmedJoin({
        name,
        address,
        city,
        state,
        country,
    });
    if (result.label.isEmpty()) {
        result.label = result.primary;
    }
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
    const QVariantMap addressMap = item.value(QStringLiteral("address")).toMap();
    const QString name = item.value(QStringLiteral("name")).toString().trimmed();
    const QString houseNumber = firstNonEmpty({
        addressMap.value(QStringLiteral("house_number")).toString(),
        item.value(QStringLiteral("house_number")).toString(),
    });
    const QString street = firstNonEmpty({
        addressMap.value(QStringLiteral("road")).toString(),
        addressMap.value(QStringLiteral("street")).toString(),
        addressMap.value(QStringLiteral("pedestrian")).toString(),
        addressMap.value(QStringLiteral("footway")).toString(),
        addressMap.value(QStringLiteral("cycleway")).toString(),
    });
    const QString locality = firstNonEmpty({
        addressMap.value(QStringLiteral("suburb")).toString(),
        addressMap.value(QStringLiteral("neighbourhood")).toString(),
        addressMap.value(QStringLiteral("quarter")).toString(),
        addressMap.value(QStringLiteral("hamlet")).toString(),
        addressMap.value(QStringLiteral("village")).toString(),
        addressMap.value(QStringLiteral("town")).toString(),
        addressMap.value(QStringLiteral("city")).toString(),
        addressMap.value(QStringLiteral("municipality")).toString(),
        addressMap.value(QStringLiteral("county")).toString(),
    });
    const QString city = firstNonEmpty({
        addressMap.value(QStringLiteral("city")).toString(),
        addressMap.value(QStringLiteral("town")).toString(),
        addressMap.value(QStringLiteral("village")).toString(),
        addressMap.value(QStringLiteral("municipality")).toString(),
        addressMap.value(QStringLiteral("suburb")).toString(),
        addressMap.value(QStringLiteral("hamlet")).toString(),
    });
    const QString state = firstNonEmpty({
        addressMap.value(QStringLiteral("state")).toString(),
        addressMap.value(QStringLiteral("region")).toString(),
    });
    const QString country = addressMap.value(QStringLiteral("country")).toString().trimmed();
    const QString countryCode = firstNonEmpty({
        addressMap.value(QStringLiteral("country_code")).toString(),
        item.value(QStringLiteral("country_code")).toString(),
    }).toUpper();
    const QString address = addressLine(houseNumber, street);
    const QString localityLine = locality.compare(city, Qt::CaseInsensitive) == 0 ? QString() : locality;

    SearchResultData result;
    result.id = QStringLiteral("search-nominatim-%1").arg(index);
    result.street = street;
    result.houseNumber = houseNumber;
    result.city = city.isEmpty() ? locality : city;
    result.state = state;
    result.country = country;
    result.countryCode = countryCode;
    result.category = item.value(QStringLiteral("category")).toString().trimmed();
    result.resultType = item.value(QStringLiteral("type")).toString().trimmed();
    result.addressType = item.value(QStringLiteral("addresstype")).toString().trimmed();
    result.osmKey = result.category;
    result.osmValue = result.resultType;
    result.importance = item.value(QStringLiteral("importance")).toDouble();
    result.sourceOrder = index;
    result.label = label;
    result.primary = firstNonEmpty({
        name,
        address,
        street,
        locality,
        city,
        country,
        label,
    });
    result.secondary = trimmedJoin({
        name.isEmpty() ? QString() : address,
        localityLine,
        city,
        state,
        country,
    });
    if (result.primary.isEmpty()) {
        result.primary = label;
    }
    if (result.secondary.isEmpty()) {
        result.secondary = trimmedJoin({
            localityLine,
            city,
            state,
            country,
        });
    }
    if (result.secondary.isEmpty()) {
        result.secondary = QStringLiteral("OpenStreetMap result");
    }
    if (result.label.isEmpty()) {
        result.label = trimmedJoin({
            name,
            address,
            localityLine,
            city,
            state,
            country,
        });
    }
    if (result.label.isEmpty()) {
        result.label = result.primary;
    }
    result.lat = lat;
    result.lng = lng;
    result.distanceMeters = resultDistance(originLat, originLng, lat, lng, index);
    return result;
}

RouteData OpenNavigationProvider::parseOsrmRouteVariant(const QVariantMap &route, const QVariantMap &destination) const
{
    RouteData data;
    data.destination = destination;
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
