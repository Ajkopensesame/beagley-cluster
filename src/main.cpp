#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;

    // Load QML module entry point
    engine.loadFromModule("BeagleY", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
