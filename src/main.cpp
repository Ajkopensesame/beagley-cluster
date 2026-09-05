#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QDebug>

#include "data/VehicleStateClient.h"
#include "data/MockVehicleStateClient.h"
#include "data/VehicleStateSource.h"

#ifdef WITH_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

int main(int argc, char *argv[])
{
#ifdef WITH_WEBENGINE
    const bool noMap =
        qEnvironmentVariableIsSet("BEAGLEY_NO_MAP") &&
        qEnvironmentVariableIntValue("BEAGLEY_NO_MAP") != 0;
#else
    const bool noMap = true;
#endif

    // QGuiApplication must exist before WebEngineQuick::initialize()
    QGuiApplication app(argc, argv);

#ifdef WITH_WEBENGINE
    // MUST be called on the Qt GUI thread, after QGuiApplication is constructed.
    if (!noMap) {
        QtWebEngineQuick::initialize();

        // Optional resource sanity check (only meaningful when WebEngine is enabled)
        const QString testPath = QStringLiteral(":/web/test/index.html");
        qDebug() << "[RES] exists" << testPath << "=" << QFile(testPath).exists();
        qDebug() << "[RES] size  " << testPath << "=" << QFile(testPath).size();
    }
#endif

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("BEAGLEY_NO_MAP", noMap);

    // vehicle_state backend: BEAGLEY_VEHICLE_BACKEND=mock|live (default live).
    // Context property is always `vehicleState` (same QML property names).
    const QString backend =
        qEnvironmentVariable("BEAGLEY_VEHICLE_BACKEND", QStringLiteral("live"))
            .trimmed()
            .toLower();
    const bool useMock = (backend == QLatin1String("mock"));

    VehicleStateSource *vehicleState = nullptr;
    if (useMock) {
        vehicleState = new MockVehicleStateClient(&app);
        qDebug() << "[main] BEAGLEY_VEHICLE_BACKEND=mock";
    } else {
        vehicleState = new VehicleStateClient(&app);
        qDebug() << "[main] BEAGLEY_VEHICLE_BACKEND=live";
    }
    engine.rootContext()->setContextProperty("vehicleState", vehicleState);

    engine.loadFromModule("BeagleY", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
