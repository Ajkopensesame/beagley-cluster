#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#ifdef WITH_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    const bool noMap = qEnvironmentVariableIsSet("BEAGLEY_NO_MAP") &&
                       qEnvironmentVariableIntValue("BEAGLEY_NO_MAP") != 0;

#ifdef WITH_WEBENGINE
    if (!noMap) {
        QtWebEngineQuick::initialize();
    }
#endif

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("BEAGLEY_NO_MAP", noMap);

    engine.loadFromModule("BeagleY", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
