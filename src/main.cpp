#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QFile>
#include <QDebug>

#ifdef WITH_WEBENGINE
#include <QtWebEngineQuick/QtWebEngineQuick>
#endif

int main(int argc, char *argv[])
{
#ifdef WITH_WEBENGINE
    const bool noMap =
        qEnvironmentVariableIsSet("BEAGLEY_NO_MAP") &&
        qEnvironmentVariableIntValue("BEAGLEY_NO_MAP") != 0;

    // QtWebEngine MUST be initialized before QGuiApplication
    if (!noMap) {
        QtWebEngineQuick::initialize();
    }
#else
    const bool noMap = true;
#endif

    QGuiApplication app(argc, argv);

#ifdef WITH_WEBENGINE
    // 🔎 Definitive resource sanity check (Stage M1)
    const QString testPath = QStringLiteral(":/web/test/index.html");
    qDebug() << "[RES] exists" << testPath << "=" << QFile(testPath).exists();
    qDebug() << "[RES] size  " << testPath << "=" << QFile(testPath).size();
#endif

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("BEAGLEY_NO_MAP", noMap);

    engine.loadFromModule("BeagleY", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
