#include "SmokeProbe.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariant>
#include <QtGlobal>
#include <cstdio>

namespace {

struct Captured {
    QtMsgType type;
    QString text;
};

QList<Captured> g_captured;
bool g_capturing = false;

// Known-benign warnings. Everything else that is a warning/critical fails the test.
// Each entry MUST say why it is benign; add new entries only with a justification.
struct AllowEntry {
    const char *pattern;
    const char *why;
};
const AllowEntry kAllowList[] = {
    // MainV3 probes for an optional qml-dev override file via a Loader. In a compiled
    // build the file intentionally does not exist (see the comment above that Loader in
    // MainV3.qml); Qt reports the miss as a warning.
    {R"(SkinShowOverride\.qml: No such file or directory)",
     "optional qml-dev-only override, absent by design in compiled builds"},
    // Emitted by the offscreen QPA plugin when the window asks to be raised; the
    // offscreen platform has no window stacking.
    {R"(This plugin does not support (raise|propagateSizeHints|setParent)\(\))",
     "offscreen QPA platform limitation"},
    // The link-lost scenarios deliberately point the live client at a refused port.
    // VehicleStateClient logs the failed connect/reconnect; that is the condition under
    // test, not a defect.
    {R"(\[VehicleStateClient\] socket error "Connection refused")",
     "expected connection failure noise in the never-connects scenario"},
};

bool isAllowed(const QString &text, QString *why = nullptr)
{
    for (const AllowEntry &entry : kAllowList) {
        if (QRegularExpression(QString::fromLatin1(entry.pattern)).match(text).hasMatch()) {
            if (why)
                *why = QString::fromLatin1(entry.why);
            return true;
        }
    }
    return false;
}

void handler(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    const QString formatted = qFormatLogMessage(type, context, message);
    std::fprintf(stderr, "%s\n", formatted.toLocal8Bit().constData());
    std::fflush(stderr);
    if (g_capturing && (type == QtWarningMsg || type == QtCriticalMsg || type == QtFatalMsg))
        g_captured.append({type, message});
}

QStringList g_failures;

void check(bool ok, const QString &what)
{
    std::fprintf(stderr, "[SMOKE] %s: %s\n", ok ? "ok  " : "FAIL", what.toLocal8Bit().constData());
    if (!ok)
        g_failures << what;
}

int envInt(const char *name, int fallback)
{
    bool ok = false;
    const int v = qEnvironmentVariable(name).toInt(&ok);
    return ok ? v : fallback;
}

// Collect every object with one of `names` from both the visual tree and the QObject tree
// (items declared inside Loaders / Repeaters are only reachable through one of them).
void collect(QObject *node, const QSet<QString> &names, QSet<QObject *> &seen, QList<QObject *> &out)
{
    if (!node || seen.contains(node))
        return;
    seen.insert(node);
    if (names.contains(node->objectName()))
        out << node;
    if (auto *item = qobject_cast<QQuickItem *>(node)) {
        for (QQuickItem *child : item->childItems())
            collect(child, names, seen, out);
    }
    for (QObject *child : node->children())
        collect(child, names, seen, out);
}

QList<QObject *> findAll(QQuickWindow *window, const QSet<QString> &names)
{
    QSet<QObject *> seen;
    QList<QObject *> out;
    collect(window->contentItem(), names, seen, out);
    collect(window, names, seen, out);
    return out;
}

struct Probe {
    QQmlApplicationEngine *engine = nullptr;
    QQuickWindow *window = nullptr;
    QString expect;
    int framesWanted = 5;
    int minMs = 1500;
    int timeoutMs = 30000;
    int frames = 0;
    QElapsedTimer clock;
    QStringList lastProblems;
};

Probe g_probe;

// Judges the state-dependent assertions. Returns the list of problems (empty = holds).
QStringList judgeState(const Probe &p)
{
    QStringList problems;
    const bool expectLinkLost = p.expect == QLatin1String("linklost");

    // The backend's own view, straight from the context property main.cpp installs.
    QObject *vehicleState = p.engine->rootContext()->contextProperty(QStringLiteral("vehicleState")).value<QObject *>();
    if (!vehicleState) {
        problems << QStringLiteral("context property vehicleState is missing");
    } else {
        const bool linkLost = vehicleState->property("linkLost").toBool();
        if (linkLost != expectLinkLost)
            problems << QStringLiteral("vehicleState.linkLost=%1, expected %2").arg(linkLost).arg(expectLinkLost);
    }

    // LINK LOST telltale (MainV3 + MainEmbedded both name their W.LinkLostTelltale).
    const QList<QObject *> telltales = findAll(p.window, {QStringLiteral("linkLostTelltale")});
    if (telltales.size() != 1) {
        problems << QStringLiteral("expected exactly one objectName=linkLostTelltale, found %1").arg(telltales.size());
    } else {
        auto *item = qobject_cast<QQuickItem *>(telltales.first());
        const bool visible = item && item->isVisible() && item->width() > 0 && item->height() > 0;
        if (visible != expectLinkLost)
            problems << QStringLiteral("LINK LOST telltale visible=%1, expected %2").arg(visible).arg(expectLinkLost);
    }

    // Gauge readouts: MainV3 speed + rpm, MainEmbedded speed + tach pods.
    const QList<QObject *> readouts = findAll(
        p.window, {QStringLiteral("speedValueText"), QStringLiteral("rpmValueText"), QStringLiteral("gaugeReadout")});
    if (readouts.size() < 2) {
        problems << QStringLiteral("expected >=2 gauge readouts (speedValueText/rpmValueText/gaugeReadout), found %1")
                        .arg(readouts.size());
    }
    static const QRegularExpression number(QStringLiteral(R"(^\d+(\.\d+)?$)"));
    for (QObject *readout : readouts) {
        const QString text = readout->property("text").toString();
        const QString label = readout->objectName() + QStringLiteral("='") + text + QStringLiteral("'");
        if (expectLinkLost) {
            if (text != QLatin1String("--"))
                problems << QStringLiteral("readout %1 should be '--' when link is lost").arg(label);
        } else {
            if (text == QLatin1String("--") || !number.match(text).hasMatch())
                problems << QStringLiteral("readout %1 should be a number with live (mock) data").arg(label);
        }
    }
    return problems;
}

void finish()
{
    g_capturing = false; // teardown-time binding noise is not part of the assertions

    QStringList unexpected;
    for (const Captured &c : g_captured) {
        QString why;
        if (isAllowed(c.text, &why))
            std::fprintf(stderr, "[SMOKE] allowed warning (%s): %s\n", why.toLocal8Bit().constData(),
                         c.text.left(200).toLocal8Bit().constData());
        else
            unexpected << c.text;
    }
    check(unexpected.isEmpty(),
          QStringLiteral("zero unexpected QML/Qt warnings or errors (%1 unexpected)").arg(unexpected.size()));
    for (const QString &line : unexpected)
        std::fprintf(stderr, "[SMOKE]   unexpected: %s\n", line.toLocal8Bit().constData());

    check(!g_probe.lastProblems.size(), QStringLiteral("state assertions (%1)").arg(g_probe.expect));
    for (const QString &line : g_probe.lastProblems)
        std::fprintf(stderr, "[SMOKE]   %s\n", line.toLocal8Bit().constData());

    std::fprintf(stderr, "[SMOKE] RESULT %s (%lld ms, %d frames)\n", g_failures.isEmpty() ? "PASS" : "FAIL",
                 static_cast<long long>(g_probe.clock.elapsed()), g_probe.frames);
    QCoreApplication::exit(g_failures.isEmpty() ? 0 : 1);
}

void poll()
{
    const bool framesDone = g_probe.frames >= g_probe.framesWanted;
    const bool timeUp = g_probe.clock.elapsed() >= g_probe.minMs;
    const bool timedOut = g_probe.clock.elapsed() >= g_probe.timeoutMs;
    if (!timedOut && !(framesDone && timeUp))
        return;

    // The content item only receives the window size once the platform window is exposed,
    // so it is judged after the first frames rather than at start().
    QQuickItem *content = g_probe.window->contentItem();
    g_probe.lastProblems = judgeState(g_probe);
    const bool sizeOk = content->width() == 1920 && content->height() == 720;
    // Live data needs a moment to arrive; keep polling until everything holds or the limit.
    if (!timedOut && (!g_probe.lastProblems.isEmpty() || !sizeOk))
        return;

    check(framesDone, QStringLiteral("rendered >= %1 frames without crashing (got %2)")
                          .arg(g_probe.framesWanted).arg(g_probe.frames));
    check(sizeOk, QStringLiteral("content item size is 1920x720 (got %1x%2)")
                      .arg(content->width()).arg(content->height()));
    finish();
}

} // namespace

namespace SmokeProbe {

bool enabled()
{
    return qEnvironmentVariableIntValue("BEAGLEY_SMOKE_TEST") != 0;
}

void installMessageHandler()
{
    g_capturing = true;
    qInstallMessageHandler(handler);
}

void start(QQmlApplicationEngine &engine)
{
    g_probe.engine = &engine;
    g_probe.expect = qEnvironmentVariable("BEAGLEY_SMOKE_EXPECT", QStringLiteral("live"));
    g_probe.framesWanted = envInt("BEAGLEY_SMOKE_FRAMES", 5);
    g_probe.minMs = envInt("BEAGLEY_SMOKE_MIN_MS", 1500);
    g_probe.timeoutMs = envInt("BEAGLEY_SMOKE_TIMEOUT_MS", 30000);
    g_probe.clock.start();

    // Structural assertions (one-shot).
    check(!engine.rootObjects().isEmpty(), QStringLiteral("QML root object created"));
    for (QObject *object : engine.rootObjects()) {
        if ((g_probe.window = qobject_cast<QQuickWindow *>(object)))
            break;
    }
    check(g_probe.window != nullptr, QStringLiteral("root object is a QQuickWindow"));
    if (!g_probe.window) {
        finish();
        return;
    }
    check(g_probe.window->width() == 1920 && g_probe.window->height() == 720,
          QStringLiteral("window size is 1920x720 (got %1x%2)").arg(g_probe.window->width()).arg(g_probe.window->height()));
    QObject::connect(g_probe.window, &QQuickWindow::frameSwapped, g_probe.window, [] { ++g_probe.frames; });
    auto *timer = new QTimer(g_probe.window);
    timer->setInterval(100);
    QObject::connect(timer, &QTimer::timeout, timer, [] { poll(); });
    timer->start();
}

} // namespace SmokeProbe
