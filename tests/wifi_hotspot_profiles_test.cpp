#include "system/WiFiHotspotProfiles.h"

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

void expectEqual(int actual, int expected, const char *message)
{
    if (actual == expected) {
        return;
    }
    std::cerr << "FAIL: " << message << "\n";
    std::cerr << "  expected: " << expected << "\n";
    std::cerr << "  actual:   " << actual << "\n";
    ++g_failures;
}

void testParseAnnotatedProfiles()
{
    const QString wpaFile = QStringLiteral(
        "ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev\n"
        "update_config=1\n"
        "country=AU\n"
        "\n"
        "# BEAGLEY_PROFILE id=iphone-primary fallback=172.20.10.6/28\n"
        "network={\n"
        "\tssid=\"Josh’s iPhone\"\n"
        "\tpsk=abcdef123456\n"
        "\tpriority=100\n"
        "\tid_str=\"iphone-primary\"\n"
        "\tscan_ssid=1\n"
        "}\n"
        "\n"
        "# BEAGLEY_PROFILE id=shop-hotspot fallback=-\n"
        "network={\n"
        "\tssid=\"GarageWiFi\"\n"
        "\tpsk=123456abcdef\n"
        "\tpriority=80\n"
        "\tid_str=\"shop-hotspot\"\n"
        "\tscan_ssid=1\n"
        "}\n");

    const QVector<WiFiHotspotProfiles::SavedProfile> profiles =
        WiFiHotspotProfiles::parseWpaSupplicantProfiles(wpaFile);

    expectEqual(profiles.size(), 2, "two saved hotspot profiles parsed");
    if (profiles.size() != 2) {
        return;
    }

    expectEqual(profiles[0].id, QStringLiteral("iphone-primary"), "first profile id parsed");
    expectEqual(profiles[0].ssid, QString::fromUtf8("Josh\xe2\x80\x99s iPhone"), "first profile ssid parsed");
    expectEqual(profiles[0].priority, 100, "first profile priority parsed");
    expectEqual(profiles[0].fallbackAddress, QStringLiteral("172.20.10.6/28"), "first profile fallback parsed");
    expectTrue(profiles[0].hasPsk, "first profile detected hashed psk");

    expectEqual(profiles[1].id, QStringLiteral("shop-hotspot"), "second profile id parsed");
    expectEqual(profiles[1].fallbackAddress, QString(), "dash fallback maps to empty");
}

void testFindActiveProfileBySsid()
{
    const QVector<WiFiHotspotProfiles::SavedProfile> profiles = {
        {QStringLiteral("low"), QStringLiteral("SharedSSID"), 20, QString(), true},
        {QStringLiteral("high"), QStringLiteral("SharedSSID"), 100, QStringLiteral("172.20.10.6/28"), true},
        {QStringLiteral("other"), QStringLiteral("OtherSSID"), 80, QString(), true},
    };

    const WiFiHotspotProfiles::SavedProfile active =
        WiFiHotspotProfiles::findProfileForSsid(profiles, QStringLiteral("SharedSSID"));
    expectEqual(active.id, QStringLiteral("high"), "highest priority matching ssid wins");
    expectEqual(active.fallbackAddress, QStringLiteral("172.20.10.6/28"), "active profile fallback preserved");
}

} // namespace

int main()
{
    testParseAnnotatedProfiles();
    testFindActiveProfileBySsid();

    if (g_failures == 0) {
        std::cout << "wifi_hotspot_profiles_test: PASS\n";
        return 0;
    }

    std::cerr << "wifi_hotspot_profiles_test: " << g_failures << " failure(s)\n";
    return 1;
}
