#include "system/WiFiSsidUtils.h"

#include <cmath>
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

void testDecodeEscapedUnicode()
{
    const QString raw = QStringLiteral("Josh\\xe2\\x80\\x99s iPhone");
    const QString expected = QString::fromUtf8("Josh\xe2\x80\x99s iPhone");
    expectEqual(WiFiSsidUtils::decodeIwEscapedSsid(raw), expected, "decode escaped unicode apostrophe");
}

void testDecodeAsciiUntouched()
{
    const QString ascii = QStringLiteral("MyHotspot24G");
    expectEqual(WiFiSsidUtils::decodeIwEscapedSsid(ascii), ascii, "plain ASCII SSID unchanged");
}

void testDecodeInvalidEscapeSafeFallback()
{
    const QString invalid = QStringLiteral("SSID\\xG1");
    expectEqual(WiFiSsidUtils::decodeIwEscapedSsid(invalid), invalid, "invalid hex escape remains unchanged");
}

void testParseScanOutput()
{
    const QString scan = QStringLiteral(
        "BSS 00:11:22:33:44:55(on wlan0)\n"
        "\tsignal: -63.00 dBm\n"
        "\tSSID: Josh\\xe2\\x80\\x99s iPhone\n"
        "\tRSN:\n"
        "BSS 66:77:88:99:aa:bb(on wlan0)\n"
        "\tsignal: -48.00 dBm\n"
        "\tSSID: GarageWiFi\n");

    const QVector<WiFiSsidUtils::ScanRow> rows = WiFiSsidUtils::parseIwScanNetworks(scan);
    expectTrue(rows.size() == 2, "parse scan should yield two networks");
    if (rows.size() != 2) {
        return;
    }

    const QString expectedUnicode = QString::fromUtf8("Josh\xe2\x80\x99s iPhone");
    expectEqual(rows[0].ssid, expectedUnicode, "first SSID decoded from escaped bytes");
    expectTrue(rows[0].secure, "first SSID marked secure from RSN");
    expectTrue(std::abs(rows[0].signalDbm - (-63.0)) < 0.01, "first SSID signal parsed");

    expectEqual(rows[1].ssid, QStringLiteral("GarageWiFi"), "second SSID parsed");
    expectTrue(!rows[1].secure, "second SSID default open when no WPA/RSN marker");
    expectTrue(std::abs(rows[1].signalDbm - (-48.0)) < 0.01, "second SSID signal parsed");
}

} // namespace

int main()
{
    testDecodeEscapedUnicode();
    testDecodeAsciiUntouched();
    testDecodeInvalidEscapeSafeFallback();
    testParseScanOutput();

    if (g_failures == 0) {
        std::cout << "wifi_ssid_utils_test: PASS\n";
        return 0;
    }

    std::cerr << "wifi_ssid_utils_test: " << g_failures << " failure(s)\n";
    return 1;
}
