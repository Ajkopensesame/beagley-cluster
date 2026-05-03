#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QtQml/qqml.h>
#include <QFile>
#include <QFileInfo>
#include <QDebug>
#include <QDir>
#include <QElapsedTimer>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QNetworkRequest>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>
#include <QStringList>
#include <QVariantMap>
#include <QJsonDocument>
#include <QDateTime>
#include <QImage>

#include "data/VehicleStateClient.h"
#include "navigation/NavigationService.h"
#include "render/ClusterRenderModel.h"
#include "render/NativeRasterMapItem.h"
#include "render/PerformanceMetrics.h"
#include "render/RadarFrameItem.h"
#include "render/RasterFrameItem.h"
#include "system/NowPlayingService.h"
#include "system/RadarImageService.h"
#include "system/WiFiSetupService.h"

#ifdef WITH_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

class BeagleyNetworkAccessManager final : public QNetworkAccessManager
{
public:
    explicit BeagleyNetworkAccessManager(const QByteArray &userAgent, QObject *parent = nullptr)
        : QNetworkAccessManager(parent)
        , m_userAgent(userAgent)
    {
        auto *diskCache = new QNetworkDiskCache(this);
        const QString cacheRoot = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
            + QStringLiteral("/osm-tiles");
        QDir().mkpath(cacheRoot);
        diskCache->setCacheDirectory(cacheRoot);
        diskCache->setMaximumCacheSize(256 * 1024 * 1024);
        setCache(diskCache);
    }

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData) override
    {
        QNetworkRequest patchedRequest(request);
        const QUrl url = patchedRequest.url();
        const QString host = url.host().toLower();
        const QString path = url.path().toLower();
        const bool osmOrOpenfreemapHost =
            host == QLatin1String("tile.openstreetmap.org")
            || host == QLatin1String("staticmap.openstreetmap.de")
            || host == QLatin1String("tiles.openfreemap.org")
            || host == QLatin1String("assets.openfreemap.com")
            || host.endsWith(QLatin1String(".openfreemap.org"));
        const bool bomHost =
            host == QLatin1String("bom.gov.au")
            || host == QLatin1String("www.bom.gov.au")
            || host.endsWith(QLatin1String(".bom.gov.au"));
        const bool vectorAssetPath = path.endsWith(QLatin1String(".pbf"))
            || path.endsWith(QLatin1String(".json"))
            || path.endsWith(QLatin1String(".png"))
            || path.endsWith(QLatin1String(".jpg"))
            || path.endsWith(QLatin1String(".jpeg"))
            || path.contains(QLatin1String("/glyphs/"))
            || path.contains(QLatin1String("/fonts/"))
            || path.contains(QLatin1String("/sprites/"));
        if (osmOrOpenfreemapHost || vectorAssetPath || bomHost) {
            if (!patchedRequest.hasRawHeader("User-Agent")) {
                patchedRequest.setRawHeader("User-Agent", m_userAgent);
            }
        }
        if (osmOrOpenfreemapHost || vectorAssetPath) {
            patchedRequest.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
            patchedRequest.setAttribute(QNetworkRequest::CacheSaveControlAttribute, true);
        }
        return QNetworkAccessManager::createRequest(op, patchedRequest, outgoingData);
    }

private:
    QByteArray m_userAgent;
};

class BeagleyNetworkAccessManagerFactory final : public QQmlNetworkAccessManagerFactory
{
public:
    explicit BeagleyNetworkAccessManagerFactory(const QByteArray &userAgent)
        : m_userAgent(userAgent)
    {
    }

    QNetworkAccessManager *create(QObject *parent) override
    {
        return new BeagleyNetworkAccessManager(m_userAgent, parent);
    }

private:
    QByteArray m_userAgent;
};

static void appendChromiumFlag(const QByteArray &flag)
{
    QByteArray flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS").trimmed();
    const QList<QByteArray> parts = flags.split(' ');
    if (!parts.contains(flag)) {
        if (!flags.isEmpty()) {
            flags.append(' ');
        }
        flags.append(flag);
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
    }
}

static bool isEmbeddedPlatformName(const QString &platformName)
{
    const QString normalized = platformName.trimmed().toLower();
    return normalized == QLatin1String("linuxfb")
        || normalized == QLatin1String("eglfs")
        || normalized == QLatin1String("minimalegl");
}

static QString normalizedSetting(const QByteArray &rawValue, const QString &fallback)
{
    const QString trimmed = QString::fromUtf8(rawValue).trimmed().toLower();
    return trimmed.isEmpty() ? fallback : trimmed;
}

static bool envEnabled(const char *name, bool fallback)
{
    if (!qEnvironmentVariableIsSet(name)) {
        return fallback;
    }
    const QString value = QString::fromUtf8(qgetenv(name)).trimmed().toLower();
    if (value.isEmpty()) {
        return fallback;
    }
    return value != QLatin1String("0")
        && value != QLatin1String("false")
        && value != QLatin1String("off")
        && value != QLatin1String("no");
}

static bool gpuGatePasses(const QString &gateFilePath, QString *detailsOut)
{
    QFile gateFile(gateFilePath);
    if (!gateFile.exists()) {
        if (detailsOut) {
            *detailsOut = QStringLiteral("missing gate file");
        }
        return false;
    }
    if (!gateFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (detailsOut) {
            *detailsOut = QStringLiteral("gate file unreadable");
        }
        return false;
    }
    const QString content = QString::fromUtf8(gateFile.readAll()).toLower();
    if (!content.contains(QStringLiteral("status=pass"))) {
        if (detailsOut) {
            *detailsOut = QStringLiteral("gate status is not pass");
        }
        return false;
    }
    if (content.contains(QStringLiteral("llvmpipe"))
        || content.contains(QStringLiteral("swrast"))
        || content.contains(QStringLiteral("kms_swrast"))
        || content.contains(QStringLiteral("software"))) {
        if (detailsOut) {
            *detailsOut = QStringLiteral("gate reports software renderer");
        }
        return false;
    }
    const QFileInfo gateInfo(gateFile);
    const qint64 ageSec = gateInfo.lastModified().toUTC().secsTo(QDateTime::currentDateTimeUtc());
    if (ageSec > 3600) {
        if (detailsOut) {
            *detailsOut = QStringLiteral("gate file stale");
        }
        return false;
    }
    if (detailsOut) {
        *detailsOut = QStringLiteral("ok");
    }
    return true;
}

static QString graphicsApiName(QSGRendererInterface::GraphicsApi api)
{
    switch (api) {
    case QSGRendererInterface::Unknown:
        return QStringLiteral("Unknown");
    case QSGRendererInterface::Software:
        return QStringLiteral("Software");
    case QSGRendererInterface::OpenVG:
        return QStringLiteral("OpenVG");
    case QSGRendererInterface::OpenGL:
        return QStringLiteral("OpenGL");
    case QSGRendererInterface::Direct3D11:
        return QStringLiteral("Direct3D11");
    case QSGRendererInterface::Vulkan:
        return QStringLiteral("Vulkan");
    case QSGRendererInterface::Metal:
        return QStringLiteral("Metal");
    case QSGRendererInterface::Null:
        return QStringLiteral("Null");
    default:
        return QStringLiteral("Other");
    }
}

int main(int argc, char *argv[])
{
#ifdef WITH_WEBENGINE
    const bool noMap =
        qEnvironmentVariableIsSet("BEAGLEY_NO_MAP") &&
        qEnvironmentVariableIntValue("BEAGLEY_NO_MAP") != 0;
#else
    const bool noMap = true;
#endif
    const bool forceSnapshotMap =
        qEnvironmentVariableIsSet("BEAGLEY_FORCE_SNAPSHOT_MAP") &&
        qEnvironmentVariableIntValue("BEAGLEY_FORCE_SNAPSHOT_MAP") != 0;
    const QString requestedPlatformName = QString::fromUtf8(qgetenv("QT_QPA_PLATFORM"));
    const bool embeddedDisplayRequested = isEmbeddedPlatformName(requestedPlatformName);
    const bool requireGpuGate = envEnabled("BEAGLEY_REQUIRE_GPU_GATE", embeddedDisplayRequested);
    const QString gpuGateFile = qEnvironmentVariableIsSet("BEAGLEY_GPU_GATE_FILE")
        ? QString::fromUtf8(qgetenv("BEAGLEY_GPU_GATE_FILE")).trimmed()
        : QStringLiteral("/tmp/beagley_gpu_gate.ok");
    if (requireGpuGate) {
        QString gateDetails;
        if (!gpuGatePasses(gpuGateFile, &gateDetails)) {
            qCritical().noquote()
                << QStringLiteral("[GPU-GATE] failed: %1 (file=%2)")
                       .arg(gateDetails, gpuGateFile);
            return 32;
        }
        qInfo().noquote() << QStringLiteral("[GPU-GATE] pass file=%1").arg(gpuGateFile);
    }
    QString renderProfile = normalizedSetting(qgetenv("BEAGLEY_RENDER_PROFILE"),
                                              embeddedDisplayRequested ? QStringLiteral("embedded")
                                                                       : QStringLiteral("desktop"));
    QString effectLevel = normalizedSetting(qgetenv("BEAGLEY_EFFECT_LEVEL"),
                                            renderProfile == QLatin1String("embedded")
                                                ? QStringLiteral("low")
                                                : QStringLiteral("high"));
    QString mapRenderer = normalizedSetting(qgetenv("BEAGLEY_MAP_RENDERER"),
                                            renderProfile == QLatin1String("embedded")
                                                ? QStringLiteral("native-online")
                                                : QStringLiteral("web"));
    if (mapRenderer == QLatin1String("tile") || mapRenderer == QLatin1String("snapshot")) {
        mapRenderer = QStringLiteral("native-online");
    }
    if (mapRenderer == QLatin1String("maplibre")) {
        mapRenderer = QStringLiteral("maplibre-native");
    }
    if (mapRenderer != QLatin1String("web")
        && mapRenderer != QLatin1String("native")
        && mapRenderer != QLatin1String("native-online")
        && mapRenderer != QLatin1String("maplibre-native")) {
        mapRenderer = renderProfile == QLatin1String("embedded")
            ? QStringLiteral("native-online")
            : QStringLiteral("web");
    }
    QString mapBootMode = normalizedSetting(qgetenv("BEAGLEY_MAP_BOOT_MODE"),
                                            renderProfile == QLatin1String("embedded")
                                                ? QStringLiteral("staged")
                                                : QStringLiteral("direct"));
    QString mapStyleMode = normalizedSetting(qgetenv("BEAGLEY_MAP_STYLE_MODE"),
                                             renderProfile == QLatin1String("embedded")
                                                 ? QStringLiteral("embedded")
                                                 : QStringLiteral("desktop"));
    const bool stressScene =
        qEnvironmentVariableIsSet("BEAGLEY_STRESS_SCENE") &&
        qEnvironmentVariableIntValue("BEAGLEY_STRESS_SCENE") != 0;
    const bool preferSnapshotMap = forceSnapshotMap || mapRenderer != QLatin1String("web");
#ifdef WITH_MAPLIBRE_NATIVE
    const bool mapLibreNativeAvailable = true;
#else
    const bool mapLibreNativeAvailable = false;
#endif

    if (mapRenderer == QLatin1String("maplibre-native")
        && !qEnvironmentVariableIsSet("QSG_RHI_BACKEND")) {
        qputenv("QSG_RHI_BACKEND", QByteArrayLiteral("opengl"));
    }
    if (renderProfile == QLatin1String("embedded") && !qEnvironmentVariableIsSet("QSG_RENDER_LOOP")) {
        qputenv("QSG_RENDER_LOOP", QByteArrayLiteral("threaded"));
    }
    qputenv("BEAGLEY_RENDER_PROFILE", renderProfile.toUtf8());
    qputenv("BEAGLEY_EFFECT_LEVEL", effectLevel.toUtf8());
    qputenv("BEAGLEY_MAP_RENDERER", mapRenderer.toUtf8());

#ifdef WITH_WEBENGINE
    if (!noMap && !preferSnapshotMap) {
        QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
        if (qEnvironmentVariableIsSet("BEAGLEY_WEBENGINE_SOFTWARE") &&
            qEnvironmentVariableIntValue("BEAGLEY_WEBENGINE_SOFTWARE") != 0) {
            const QString webEngineMode = normalizedSetting(
                qgetenv("BEAGLEY_WEBENGINE_MODE"),
                QStringLiteral("swiftshader_driver"));
            appendChromiumFlag(QByteArrayLiteral("--use-gl=angle"));
            appendChromiumFlag(QByteArrayLiteral("--ignore-gpu-blocklist"));
            appendChromiumFlag(QByteArrayLiteral("--enable-webgl"));
            if (webEngineMode == QLatin1String("swiftshader_webgl")) {
                appendChromiumFlag(QByteArrayLiteral("--use-angle=swiftshader-webgl"));
                appendChromiumFlag(QByteArrayLiteral("--enable-unsafe-swiftshader"));
            } else if (webEngineMode == QLatin1String("disable_gpu")) {
                appendChromiumFlag(QByteArrayLiteral("--disable-gpu"));
            } else {
                appendChromiumFlag(QByteArrayLiteral("--use-angle=swiftshader"));
            }
        }
        QtWebEngineQuick::initialize();
    }
#endif

    QGuiApplication app(argc, argv);
    qmlRegisterType<NativeRasterMapItem>("BeagleY", 1, 0, "NativeRasterMapItem");
    qmlRegisterType<RadarFrameItem>("BeagleY", 1, 0, "RadarFrameItem");
    qmlRegisterType<RasterFrameItem>("BeagleY", 1, 0, "RasterFrameItem");
    QCoreApplication::setApplicationName(QStringLiteral("BeagleyCluster"));
    QCoreApplication::setApplicationVersion(QStringLiteral("1.0"));
    QCoreApplication::setOrganizationName(QStringLiteral("Beagley"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("beagley.local"));
    const QString actualPlatformName = QGuiApplication::platformName();
    const bool embeddedDisplay = isEmbeddedPlatformName(actualPlatformName) || embeddedDisplayRequested;
    if (embeddedDisplay && renderProfile != QLatin1String("embedded")) {
        renderProfile = QStringLiteral("embedded");
    }
    const bool perfMetricsEnabled = qEnvironmentVariableIsSet("BEAGLEY_PROFILE_METRICS")
        ? qEnvironmentVariableIntValue("BEAGLEY_PROFILE_METRICS") != 0
        : (renderProfile == QLatin1String("embedded"));

#ifdef WITH_WEBENGINE
    if (!noMap && !preferSnapshotMap) {
        const QString testPath = QStringLiteral(":/web/test/index.html");
        qDebug() << "[RES] exists" << testPath << "=" << QFile(testPath).exists();
        qDebug() << "[RES] size  " << testPath << "=" << QFile(testPath).size();
    }
#endif

    QQmlApplicationEngine engine;
    const QByteArray mapUserAgent = qEnvironmentVariableIsSet("BEAGLEY_MAP_USER_AGENT")
        ? qgetenv("BEAGLEY_MAP_USER_AGENT")
        : QByteArrayLiteral("BeagleyCluster/1.0 (Qt 6 Linux demo)");
    const QString mapStyleUrl = qEnvironmentVariableIsSet("BEAGLEY_MAP_STYLE_URL")
        ? QString::fromUtf8(qgetenv("BEAGLEY_MAP_STYLE_URL")).trimmed()
        : (mapStyleMode == QLatin1String("embedded")
            ? QStringLiteral("qrc:/web/map/styles/embedded-liberty.json")
            : QStringLiteral("https://tiles.openfreemap.org/styles/liberty"));
    engine.setNetworkAccessManagerFactory(new BeagleyNetworkAccessManagerFactory(mapUserAgent));
    engine.rootContext()->setContextProperty("BEAGLEY_NO_MAP", noMap);
    engine.rootContext()->setContextProperty("BEAGLEY_FORCE_SNAPSHOT_MAP", forceSnapshotMap);
    engine.rootContext()->setContextProperty("BEAGLEY_EMBEDDED_DISPLAY", embeddedDisplay);
    engine.rootContext()->setContextProperty("BEAGLEY_MAP_STYLE_URL", mapStyleUrl);
    engine.rootContext()->setContextProperty("BEAGLEY_MAP_BOOT_MODE", mapBootMode);
    engine.rootContext()->setContextProperty("BEAGLEY_MAP_STYLE_MODE", mapStyleMode);
    engine.rootContext()->setContextProperty("BEAGLEY_MAPLIBRE_NATIVE_AVAILABLE", mapLibreNativeAvailable);
    engine.rootContext()->setContextProperty("BEAGLEY_RENDER_PROFILE", renderProfile);
    engine.rootContext()->setContextProperty("BEAGLEY_EFFECT_LEVEL", effectLevel);
    engine.rootContext()->setContextProperty("BEAGLEY_MAP_RENDERER", mapRenderer);
    engine.rootContext()->setContextProperty(
        "BEAGLEY_WEBENGINE_SOFTWARE",
        qEnvironmentVariableIsSet("BEAGLEY_WEBENGINE_SOFTWARE")
            && qEnvironmentVariableIntValue("BEAGLEY_WEBENGINE_SOFTWARE") != 0);
    engine.rootContext()->setContextProperty("BEAGLEY_STRESS_SCENE", stressScene);
    engine.rootContext()->setContextProperty("BEAGLEY_PROFILE_METRICS", perfMetricsEnabled);
    PerformanceMetrics perfMetrics(perfMetricsEnabled);
    engine.rootContext()->setContextProperty("performanceMetrics", &perfMetrics);
    qInfo() << "[BOOT] uiVariant env =" << qgetenv("BEAGLEY_UI_VARIANT")
            << "hubUrl =" << qgetenv("VEHICLE_HUB_WS_URL")
            << "mapStyle =" << mapStyleUrl
            << "platform =" << actualPlatformName
            << "embedded =" << embeddedDisplay
            << "gpuGateRequired =" << requireGpuGate
            << "gpuGateFile =" << gpuGateFile
            << "renderProfile =" << renderProfile
            << "effectLevel =" << effectLevel
            << "mapRenderer =" << mapRenderer
            << "mapLibreNativeAvailable =" << mapLibreNativeAvailable
            << "mapBootMode =" << mapBootMode
            << "mapStyleMode =" << mapStyleMode
            << "webEngineMode =" << normalizedSetting(qgetenv("BEAGLEY_WEBENGINE_MODE"),
                                                      QStringLiteral("swiftshader_driver"))
            << "renderLoop =" << qgetenv("QSG_RENDER_LOOP")
            << "stressScene =" << stressScene
            << "perfMetrics =" << perfMetricsEnabled;

    // Live vehicle_state from BBB (WebSocket) exposed to QML as `vehicleState`
    VehicleStateClient vehicleState;
    engine.rootContext()->setContextProperty("vehicleState", &vehicleState);
    WiFiSetupService wifiSetup;
    engine.rootContext()->setContextProperty("wifiSetup", &wifiSetup);
    NavigationService navigation(&vehicleState, &wifiSetup);
    engine.rootContext()->setContextProperty("navigation", &navigation);
    ClusterRenderModel clusterRenderModel(&vehicleState, &navigation);
    engine.rootContext()->setContextProperty("clusterRenderModel", &clusterRenderModel);
    NowPlayingService nowPlaying;
    engine.rootContext()->setContextProperty("nowPlaying", &nowPlaying);
    RadarImageService radarImage(mapUserAgent);
    engine.rootContext()->setContextProperty("radarImage", &radarImage);

    const QString uiVariantOverride = QString::fromUtf8(qgetenv("BEAGLEY_UI_VARIANT")).trimmed().toLower();
    const bool uiVariantExplicit = !uiVariantOverride.isEmpty();
    QString uiVariant = uiVariantExplicit
                            ? uiVariantOverride
                            : (renderProfile == QLatin1String("embedded")
                                  ? QStringLiteral("embedded")
                                  : QStringLiteral("v3"));
    if (embeddedDisplay
        && !uiVariantExplicit
        && uiVariant != QLatin1String("embedded")
        && uiVariant != QLatin1String("appliance")) {
        qWarning() << "[UI] forcing embedded variant on embedded display, requested =" << uiVariant;
        uiVariant = QStringLiteral("embedded");
    }
    QString entryPoint;
    if (uiVariant == QLatin1String("embedded") || uiVariant == QLatin1String("appliance")) {
        entryPoint = QStringLiteral("MainEmbedded");
    } else if (uiVariant == QLatin1String("legacy") || uiVariant == QLatin1String("v1")) {
        entryPoint = QStringLiteral("Main");
    } else if (uiVariant == QLatin1String("v2")) {
        entryPoint = QStringLiteral("MainV2");
    } else {
        entryPoint = QStringLiteral("MainV3");
    }

    qDebug() << "[UI] variant =" << uiVariant << "entry =" << entryPoint;
    const auto loadEntryPoint = [&](const QString &entry) {
        const QString qmlDevRoot = QString::fromUtf8(qgetenv("BEAGLEY_QML_DEV_ROOT")).trimmed();
        if (!qmlDevRoot.isEmpty()) {
            const QDir devRoot(qmlDevRoot);
            const QString qmlDevFile = QString::fromUtf8(qgetenv("BEAGLEY_QML_DEV_FILE")).trimmed();
            QStringList candidates;
            if (!qmlDevFile.isEmpty()) {
                candidates.append(qmlDevFile);
            }
            candidates.append(devRoot.filePath(QStringLiteral("src/ui/%1.qml").arg(entry)));
            candidates.append(devRoot.filePath(QStringLiteral("ui/%1.qml").arg(entry)));
            candidates.append(devRoot.filePath(QStringLiteral("%1.qml").arg(entry)));

            for (const QString &candidate : candidates) {
                const QFileInfo info(candidate);
                if (!info.isFile()) {
                    continue;
                }

                engine.addImportPath(info.absolutePath());
                engine.addImportPath(devRoot.absolutePath());
                qInfo() << "[UI-DEV] loading QML from filesystem"
                        << "root =" << devRoot.absolutePath()
                        << "entry =" << info.absoluteFilePath();
                engine.load(QUrl::fromLocalFile(info.absoluteFilePath()));
                return;
            }

            qCritical() << "[UI-DEV] BEAGLEY_QML_DEV_ROOT is set but entry QML was not found"
                        << "root =" << devRoot.absolutePath()
                        << "entry =" << entry
                        << "candidates =" << candidates;
            return;
        }

#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
        engine.loadFromModule("BeagleY", entry);
#else
        const QList<QPair<QString, QUrl>> candidates = {
            {
                QStringLiteral(":/qt/qml/BeagleY/src/ui/%1.qml").arg(entry),
                QUrl(QStringLiteral("qrc:/qt/qml/BeagleY/src/ui/%1.qml").arg(entry)),
            },
            {
                QStringLiteral(":/BeagleY/src/ui/%1.qml").arg(entry),
                QUrl(QStringLiteral("qrc:/BeagleY/src/ui/%1.qml").arg(entry)),
            },
            {
                QStringLiteral(":/qt/qml/BeagleY/%1.qml").arg(entry),
                QUrl(QStringLiteral("qrc:/qt/qml/BeagleY/%1.qml").arg(entry)),
            },
            {
                QStringLiteral(":/BeagleY/%1.qml").arg(entry),
                QUrl(QStringLiteral("qrc:/BeagleY/%1.qml").arg(entry)),
            },
        };
        for (const auto &candidate : candidates) {
            if (QFile::exists(candidate.first)) {
                engine.load(candidate.second);
                return;
            }
        }
        QStringList resourceCandidates;
        for (const auto &candidate : candidates) {
            resourceCandidates.append(candidate.first);
        }
        qWarning() << "[UI] no QML entry found for" << entry << resourceCandidates;
#endif
    };
    loadEntryPoint(entryPoint);

    // Only desktop-oriented variants should fall back to the legacy Main UI.
    // On the embedded appliance path that fallback can reintroduce optional
    // WebEngine dependencies that the production build intentionally excludes.
    const bool allowLegacyMainFallback =
        renderProfile != QLatin1String("embedded")
        && uiVariant != QLatin1String("embedded")
        && uiVariant != QLatin1String("appliance");
    if (engine.rootObjects().isEmpty()
        && allowLegacyMainFallback
        && entryPoint != QLatin1String("Main")) {
        qWarning() << "[UI] failed to load" << entryPoint << "- falling back to Main";
        loadEntryPoint(QStringLiteral("Main"));
    }

    if (engine.rootObjects().isEmpty())
        return -1;

    for (QObject *object : engine.rootObjects()) {
        if (auto *window = qobject_cast<QQuickWindow *>(object)) {
            perfMetrics.attachWindow(window);
            qInfo() << "[Render]"
                    << "graphicsApi =" << graphicsApiName(window->rendererInterface()->graphicsApi())
                    << "sceneGraphBackend =" << window->sceneGraphBackend()
                    << "persistentGraphics =" << window->isPersistentGraphics()
                    << "persistentSceneGraph =" << window->isPersistentSceneGraph();
            const QString screenshotPath =
                QString::fromUtf8(qgetenv("BEAGLEY_SCREENSHOT_PATH")).trimmed();
            if (!screenshotPath.isEmpty()) {
                bool ok = false;
                const int delayMs = QString::fromUtf8(qgetenv("BEAGLEY_SCREENSHOT_DELAY_MS"))
                                        .toInt(&ok);
                const int captureDelayMs = ok ? qMax(0, delayMs) : 3000;
                QTimer::singleShot(captureDelayMs, window, [window, screenshotPath, &app]() {
                    const QImage image = window->grabWindow();
                    const bool saved = !image.isNull() && image.save(screenshotPath);
                    qInfo() << "[Screenshot] path =" << screenshotPath
                            << "size =" << image.size()
                            << "saved =" << saved;
                    const QString exitValue =
                        QString::fromUtf8(qgetenv("BEAGLEY_SCREENSHOT_EXIT")).trimmed().toLower();
                    if (exitValue == QLatin1String("1")
                        || exitValue == QLatin1String("true")
                        || exitValue == QLatin1String("yes")) {
                        app.quit();
                    }
                });
            }
            break;
        }
    }

    return app.exec();
}
