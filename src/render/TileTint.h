#pragma once

#include <QImage>
#include <algorithm>

// Dark colour treatment for light raster map tiles (keyless fallback map).
//
// The Carto "dark_all" tiles the fallback map used to fetch now return an "API KEY
// REQUIRED" watermark, so the dark theme uses ordinary OSM tiles and darkens them
// locally: invert, then rotate hue by 180 degrees (the classic CSS
// `invert(1) hue-rotate(180deg)` trick) so water stays bluish and land/roads become dark
// grey instead of an inverted-colour negative. Header-only so it can be unit-tested
// without the scene graph.
namespace TileTint {

inline QImage darken(const QImage &source)
{
    if (source.isNull())
        return source;
    QImage image = source.convertToFormat(QImage::Format_ARGB32);
    for (int y = 0; y < image.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(image.scanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QRgb px = line[x];
            const float r = 1.0f - qRed(px) / 255.0f;
            const float g = 1.0f - qGreen(px) / 255.0f;
            const float b = 1.0f - qBlue(px) / 255.0f;
            // hue-rotate(180deg) matrix (luminance-preserving)
            const float nr = -0.574f * r + 1.430f * g + 0.144f * b;
            const float ng = 0.426f * r + 0.430f * g + 0.144f * b;
            const float nb = 0.426f * r + 1.430f * g - 0.856f * b;
            auto to8 = [](float v) { return static_cast<int>(std::clamp(v, 0.0f, 1.0f) * 255.0f + 0.5f); };
            line[x] = qRgba(to8(nr), to8(ng), to8(nb), qAlpha(px));
        }
    }
    return image;
}

} // namespace TileTint
