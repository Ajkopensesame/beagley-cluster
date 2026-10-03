#include <QtTest>

#include "render/TileTint.h"
#include "config/ClusterConfig.h"

class TstTileTint : public QObject
{
    Q_OBJECT

    static qreal luma(QRgb c) { return (0.2126 * qRed(c) + 0.7152 * qGreen(c) + 0.0722 * qBlue(c)) / 255.0; }

private slots:
    void lightLandBecomesDark()
    {
        QImage tile(4, 4, QImage::Format_ARGB32);
        tile.fill(qRgb(242, 239, 233)); // OSM land
        const QImage dark = TileTint::darken(tile);
        QCOMPARE(dark.size(), tile.size());
        QVERIFY2(luma(dark.pixel(1, 1)) < 0.15, "land must end up dark");
    }

    void waterStaysBluish()
    {
        QImage tile(2, 2, QImage::Format_ARGB32);
        tile.fill(qRgb(170, 211, 223)); // OSM water
        const QRgb px = TileTint::darken(tile).pixel(0, 0);
        QVERIFY2(qBlue(px) > qRed(px), "hue rotation keeps water blue-ish, not orange");
        QVERIFY(luma(px) < 0.35);
    }

    void alphaPreservedAndNullSafe()
    {
        QImage tile(2, 2, QImage::Format_ARGB32);
        tile.fill(qRgba(255, 255, 255, 77));
        QCOMPARE(qAlpha(TileTint::darken(tile).pixel(0, 0)), 77);
        QVERIFY(TileTint::darken(QImage()).isNull());
    }

    void tileUrlConfigDefaultsAndOverride()
    {
        qunsetenv("BEAGLEY_MAP_TILE_URL");
        qunsetenv("BEAGLEY_MAP_TILE_DARKEN");
        QCOMPARE(ClusterConfig::mapTileUrl(), QStringLiteral("https://tile.openstreetmap.org/{z}/{x}/{y}.png"));
        QVERIFY(!ClusterConfig::mapTileUrl().contains(QLatin1String("cartocdn")));
        QVERIFY(ClusterConfig::mapTileDarken());
        qputenv("BEAGLEY_MAP_TILE_URL", " https://tiles.example/{z}/{x}/{y}.png ");
        qputenv("BEAGLEY_MAP_TILE_DARKEN", "0");
        QCOMPARE(ClusterConfig::mapTileUrl(), QStringLiteral("https://tiles.example/{z}/{x}/{y}.png"));
        QVERIFY(!ClusterConfig::mapTileDarken());
        qunsetenv("BEAGLEY_MAP_TILE_URL");
        qunsetenv("BEAGLEY_MAP_TILE_DARKEN");
    }
};

QTEST_MAIN(TstTileTint)
#include "tst_tile_tint.moc"
