#include <QByteArray>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

namespace {

void ensureUtf8Locale()
{
    const QByteArray lcAll = qgetenv("LC_ALL");
    const QByteArray lang = qgetenv("LANG");
    if (lcAll.isEmpty() || lcAll == "C" || lcAll == "POSIX") {
        qputenv("LC_ALL", QByteArrayLiteral("C.UTF-8"));
    }
    if (lang.isEmpty() || lang == "C" || lang == "POSIX") {
        qputenv("LANG", QByteArrayLiteral("C.UTF-8"));
    }
}

QString defaultStatePath()
{
    const QString configured = QString::fromUtf8(qgetenv("BEAGLEY_NOW_PLAYING_STATE_PATH")).trimmed();
    if (!configured.isEmpty()) {
        return configured;
    }
#if defined(Q_OS_LINUX)
    return QStringLiteral("/run/beagley-nowplaying/state.json");
#else
    return QDir::tempPath() + QStringLiteral("/beagley-nowplaying-state.json");
#endif
}

QString stringValue(const QJsonObject &object, const QString &key)
{
    const QJsonValue value = object.value(key);
    if (value.isString()) {
        return value.toString();
    }
    if (value.isBool()) {
        return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
    }
    if (value.isDouble()) {
        return QString::number(value.toInt());
    }
    return QString();
}

void printLine(QTextStream &out, const QString &key, const QJsonObject &object)
{
    out << key << '=' << stringValue(object, key) << '\n';
}

} // namespace

int main(int argc, char **argv)
{
    ensureUtf8Locale();

    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("nowplayingctl"));
    QCoreApplication::setApplicationVersion(QStringLiteral("1.0"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Inspect cached BeagleY now-playing state."));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("command"),
                                 QStringLiteral("Command to run. Supported: status."));

    const QCommandLineOption pathOption({ QStringLiteral("p"), QStringLiteral("path") },
                                        QStringLiteral("State JSON path."),
                                        QStringLiteral("path"),
                                        defaultStatePath());
    const QCommandLineOption jsonOption(QStringLiteral("json"),
                                        QStringLiteral("Print the raw cached JSON."));
    parser.addOption(pathOption);
    parser.addOption(jsonOption);
    parser.process(app);

    const QStringList args = parser.positionalArguments();
    const QString command = args.isEmpty() ? QStringLiteral("status") : args.first();
    if (command != QLatin1String("status")) {
        QTextStream(stderr) << "unsupported command: " << command << '\n';
        return 2;
    }

    const QString path = parser.value(pathOption);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        QTextStream(stderr) << "state=missing\npath=" << path
                            << "\ndetail=No now-playing state file\n";
        return 2;
    }

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        QTextStream(stderr) << "state=invalid\npath=" << path
                            << "\ndetail=" << parseError.errorString() << '\n';
        return 3;
    }

    QTextStream out(stdout);
    if (parser.isSet(jsonOption)) {
        out << document.toJson(QJsonDocument::Indented);
        return 0;
    }

    const QJsonObject object = document.object();
    printLine(out, QStringLiteral("state"), object);
    printLine(out, QStringLiteral("backend"), object);
    printLine(out, QStringLiteral("source"), object);
    printLine(out, QStringLiteral("available"), object);
    printLine(out, QStringLiteral("playing"), object);
    printLine(out, QStringLiteral("status"), object);
    printLine(out, QStringLiteral("detail"), object);
    printLine(out, QStringLiteral("title"), object);
    printLine(out, QStringLiteral("artist"), object);
    printLine(out, QStringLiteral("album"), object);
    printLine(out, QStringLiteral("playback_http_status"), object);
    printLine(out, QStringLiteral("token_http_status"), object);
    printLine(out, QStringLiteral("spotify_refresh_configured"), object);
    printLine(out, QStringLiteral("spotify_token_usable"), object);
    printLine(out, QStringLiteral("error"), object);
    printLine(out, QStringLiteral("updated_utc"), object);
    return 0;
}
