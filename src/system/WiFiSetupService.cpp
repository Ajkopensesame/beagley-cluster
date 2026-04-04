#include "WiFiSetupService.h"
#include "WiFiSsidUtils.h"

#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QTimer>
#include <QUrl>

namespace {
constexpr int kDisconnectedReconcileMs = 5000;
constexpr int kAssociatedReconcileMs = 15000;
constexpr int kProbeTransferTimeoutMs = 5000;

QString shellQuote(const QString &value)
{
    QString quoted = value;
    quoted.replace('\'', QStringLiteral("'\"'\"'"));
    return QStringLiteral("'") + quoted + QStringLiteral("'");
}

QString valueForPrefix(const QString &text, const QString &prefix)
{
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        if (line.startsWith(prefix)) {
            return line.mid(prefix.size()).trimmed();
        }
    }
    return QString();
}

QString blockForMarkers(const QString &text, const QString &beginMarker, const QString &endMarker)
{
    const int beginIndex = text.indexOf(beginMarker);
    if (beginIndex < 0) {
        return QString();
    }

    const int start = beginIndex + beginMarker.size();
    int end = text.indexOf(endMarker, start);
    if (end < 0) {
        end = text.size();
    }

    return text.mid(start, end - start).trimmed();
}

QString summarizeJournal(const QString &journal, int maxLines = 6)
{
    QStringList lines;
    for (const QString &line : journal.split(QLatin1Char('\n'))) {
        const QString trimmed = line.trimmed();
        if (!trimmed.isEmpty()) {
            lines.append(trimmed);
        }
    }
    if (lines.isEmpty()) {
        return QString();
    }

    if (lines.size() > maxLines) {
        lines = lines.mid(lines.size() - maxLines);
    }

    return QStringLiteral("Recent wpa_supplicant log: ") + lines.join(QStringLiteral(" | "));
}

QString profileIdForSsid(const QString &ssid)
{
    QString id = ssid.toLower();
    id.replace(QRegularExpression(QStringLiteral("[^a-z0-9_-]+")), QStringLiteral("-"));
    id.replace(QRegularExpression(QStringLiteral("-{2,}")), QStringLiteral("-"));
    while (id.startsWith(QLatin1Char('-'))) {
        id.remove(0, 1);
    }
    while (id.endsWith(QLatin1Char('-'))) {
        id.chop(1);
    }
    if (id.isEmpty()) {
        id = QStringLiteral("ui-hotspot");
    }
    return id;
}

QString enrichStatusDetail(const QString &baseDetail,
                           const QVector<WiFiHotspotProfiles::SavedProfile> &profiles,
                           const QString &activeProfileId,
                           const QString &activeFallbackAddress)
{
    QStringList sections;
    if (!baseDetail.isEmpty()) {
        sections << baseDetail;
    }

    if (!profiles.isEmpty()) {
        sections << QStringLiteral("Saved hotspot profiles: %1.").arg(profiles.size());
    }
    if (!activeProfileId.isEmpty()) {
        sections << QStringLiteral("Active saved profile: %1.").arg(activeProfileId);
    }
    if (!activeFallbackAddress.isEmpty()) {
        sections << QStringLiteral("Configured hotspot SSH fallback: %1.").arg(activeFallbackAddress);
    }

    return sections.join(QLatin1Char('\n'));
}

QString classifyAssociationCategory(const QString &state, const QString &combinedText)
{
    if (state.compare(QStringLiteral("4WAY_HANDSHAKE"), Qt::CaseInsensitive) == 0 ||
        combinedText.contains(QStringLiteral("pre-shared key may be incorrect"), Qt::CaseInsensitive) ||
        combinedText.contains(QStringLiteral("WRONG_KEY"), Qt::CaseInsensitive) ||
        combinedText.contains(QStringLiteral("authentication failed"), Qt::CaseInsensitive)) {
        return QStringLiteral("auth-failed");
    }

    if (state.compare(QStringLiteral("SCANNING"), Qt::CaseInsensitive) == 0 ||
        state.compare(QStringLiteral("DISCONNECTED"), Qt::CaseInsensitive) == 0 ||
        state.compare(QStringLiteral("INACTIVE"), Qt::CaseInsensitive) == 0 ||
        state.compare(QStringLiteral("ASSOCIATING"), Qt::CaseInsensitive) == 0 ||
        state.compare(QStringLiteral("INTERFACE_DISABLED"), Qt::CaseInsensitive) == 0 ||
        combinedText.contains(QStringLiteral("No network configuration found"), Qt::CaseInsensitive)) {
        return QStringLiteral("ssid-not-found");
    }

    return QStringLiteral("timeout");
}

QString categoryDetail(const QString &category)
{
    if (category == QStringLiteral("auth-failed")) {
        return QStringLiteral("Password likely wrong.");
    }
    if (category == QStringLiteral("ssid-not-found")) {
        return QStringLiteral("SSID not matched or out of range.");
    }
    return QStringLiteral("Association timed out.");
}

QString normalizedWizardTrigger(const QString &raw)
{
    const QString value = raw.trimmed().toLower();
    if (value == QLatin1String("offline") || value == QLatin1String("manual")) {
        return value;
    }
    return QStringLiteral("no_config");
}

bool envFlagEnabled(const char *name)
{
    if (!qEnvironmentVariableIsSet(name)) {
        return false;
    }

    const QString value = QString::fromUtf8(qgetenv(name)).trimmed().toLower();
    return value == QLatin1String("1")
        || value == QLatin1String("true")
        || value == QLatin1String("yes")
        || value == QLatin1String("on");
}

QString wpaFileForInterface(const QString &interfaceName)
{
    return QStringLiteral("/etc/wpa_supplicant/wpa_supplicant-%1.conf").arg(interfaceName);
}

struct StatusSnapshot {
    QString state;
    QString status;
    QString detail;
};

StatusSnapshot describeStatus(bool hasSavedConfig,
                              bool interfacePresent,
                              bool connected,
                              bool hasIpLease,
                              bool internetReachable,
                              bool probeInFlight,
                              const QString &interfaceName,
                              const QString &currentSsid,
                              const QString &lastProbeError)
{
    if (!hasSavedConfig) {
        return {
            QStringLiteral("no_config"),
            QStringLiteral("No saved hotspot profile."),
            QStringLiteral("Select your hotspot and enter the password to finish setup.")
        };
    }

    if (!interfacePresent) {
        return {
            QStringLiteral("waiting_for_hotspot"),
            QStringLiteral("Wi-Fi interface unavailable."),
            QStringLiteral("Expected interface %1 was not found. Saved hotspot config is present but the radio is not ready.")
                .arg(interfaceName)
        };
    }

    if (!connected) {
        return {
            QStringLiteral("waiting_for_hotspot"),
            QStringLiteral("Waiting for hotspot."),
            QStringLiteral("Saved hotspot profile detected on %1. Keep the hotspot powered on and within range.")
                .arg(interfaceName)
        };
    }

    if (!hasIpLease) {
        const QString ssidLabel = currentSsid.isEmpty() ? QStringLiteral("saved hotspot") : currentSsid;
        return {
            QStringLiteral("associated_no_ip"),
            QStringLiteral("Associated, waiting for IP."),
            QStringLiteral("Connected to %1 on %2 but DHCP has not completed yet.").arg(ssidLabel, interfaceName)
        };
    }

    if (!internetReachable) {
        QString detail;
        if (probeInFlight) {
            detail = QStringLiteral("Connected to %1 on %2. Checking internet reachability now.")
                         .arg(currentSsid, interfaceName);
        } else if (!lastProbeError.isEmpty()) {
            detail = QStringLiteral("Connected to %1 on %2 but the internet probe failed: %3")
                         .arg(currentSsid, interfaceName, lastProbeError);
        } else {
            detail = QStringLiteral("Connected to %1 on %2 but internet access is not available.")
                         .arg(currentSsid, interfaceName);
        }
        return {
            QStringLiteral("no_internet"),
            QStringLiteral("Hotspot connected, no internet."),
            detail
        };
    }

    return {
        QStringLiteral("online"),
        QStringLiteral("Hotspot online."),
        QStringLiteral("Connected to %1 on %2 with internet reachability confirmed.")
            .arg(currentSsid, interfaceName)
    };
}
} // namespace

WiFiSetupService::WiFiSetupService(QObject *parent)
    : QObject(parent)
    , m_interfaceName(qEnvironmentVariableIsSet("BEAGLEY_WIFI_INTERFACE")
            ? QString::fromUtf8(qgetenv("BEAGLEY_WIFI_INTERFACE")).trimmed()
            : QStringLiteral("wlan0"))
    , m_onboardingEnabled(qEnvironmentVariableIsSet("BEAGLEY_WIFI_ONBOARDING")
            ? envFlagEnabled("BEAGLEY_WIFI_ONBOARDING")
            : (qEnvironmentVariableIsSet("BEAGLEY_WIFI_ALLOW_UI_CONFIG")
                ? envFlagEnabled("BEAGLEY_WIFI_ALLOW_UI_CONFIG")
                : true))
    , m_wizardTrigger(normalizedWizardTrigger(qEnvironmentVariableIsSet("BEAGLEY_WIFI_WIZARD_TRIGGER")
            ? QString::fromUtf8(qgetenv("BEAGLEY_WIFI_WIZARD_TRIGGER"))
            : QStringLiteral("no_config")))
    , m_configWriteEnabled(m_onboardingEnabled)
    , m_adminPasswordFile(qEnvironmentVariableIsSet("BEAGLEY_WIFI_ADMIN_PASSWORD_FILE")
            ? QString::fromUtf8(qgetenv("BEAGLEY_WIFI_ADMIN_PASSWORD_FILE")).trimmed()
            : QStringLiteral("/etc/beagley-wifi/admin_password"))
    , m_internetCheckUrl(qEnvironmentVariableIsSet("BEAGLEY_INTERNET_CHECK_URL")
            ? QString::fromUtf8(qgetenv("BEAGLEY_INTERNET_CHECK_URL")).trimmed()
            : QStringLiteral("https://connectivitycheck.gstatic.com/generate_204"))
{
    if (m_interfaceName.isEmpty()) {
        m_interfaceName = QStringLiteral("wlan0");
    }
    if (m_adminPasswordFile.isEmpty()) {
        m_adminPasswordFile = QStringLiteral("/etc/beagley-wifi/admin_password");
    }

    m_reconcileTimer.setSingleShot(true);
    connect(&m_reconcileTimer, &QTimer::timeout, this, [this]() {
        const bool forceProbe = m_forceProbeOnNextRefresh;
        m_forceProbeOnNextRefresh = false;
        refreshStatusInternal(forceProbe);
        scheduleReconcile();
    });

    QTimer::singleShot(0, this, [this]() {
        refreshStatusInternal(true);
        scheduleReconcile();
    });
}

void WiFiSetupService::setInterfaceName(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty() || trimmed == m_interfaceName) {
        return;
    }
    m_interfaceName = trimmed;
    m_forceProbeOnNextRefresh = true;
    emit interfaceNameChanged();
    refreshStatus();
}

void WiFiSetupService::setStatus(const QString &value)
{
    if (m_status == value) {
        return;
    }
    m_status = value;
    emit statusChanged();
}

void WiFiSetupService::setStatusDetail(const QString &value)
{
    if (m_statusDetail == value) {
        return;
    }
    m_statusDetail = value;
    emit statusDetailChanged();
}

void WiFiSetupService::setBusy(bool value)
{
    if (m_busy == value) {
        return;
    }
    m_busy = value;
    emit busyChanged();
}

void WiFiSetupService::setPromptVisible(bool value)
{
    if (m_promptVisible == value) {
        return;
    }
    m_promptVisible = value;
    emit promptVisibleChanged();
}

void WiFiSetupService::setHasIpLease(bool value)
{
    if (m_hasIpLease == value) {
        return;
    }
    m_hasIpLease = value;
    qInfo() << "[WiFiSetupService] ipLease" << m_interfaceName << "=" << m_hasIpLease;
    emit connectionChanged();
}

void WiFiSetupService::setInternetReachable(bool value)
{
    if (m_internetReachable == value) {
        return;
    }
    m_internetReachable = value;
    qInfo() << "[WiFiSetupService] internetReachable" << m_interfaceName << "=" << m_internetReachable;
    emit internetReachableChanged();
}

void WiFiSetupService::setHasSavedConfig(bool value)
{
    if (m_hasSavedConfig == value) {
        return;
    }
    m_hasSavedConfig = value;
    emit savedConfigChanged();
}

void WiFiSetupService::setNetworkState(const QString &value)
{
    if (m_networkState == value) {
        return;
    }
    m_networkState = value;
    emit networkStateChanged();
}

void WiFiSetupService::setSetupRequired(bool value)
{
    if (m_setupRequired == value) {
        return;
    }
    m_setupRequired = value;
    emit setupRequiredChanged();
}

void WiFiSetupService::setSetupMessages(const QString &shortMessage, const QString &detailMessage)
{
    if (m_setupMessageShort == shortMessage && m_setupMessageDetail == detailMessage) {
        return;
    }
    m_setupMessageShort = shortMessage;
    m_setupMessageDetail = detailMessage;
    emit setupMessagesChanged();
}

void WiFiSetupService::updateSetupMessaging()
{
    const bool onboardingActive = m_onboardingEnabled
        && (!m_hasSavedConfig || m_wizardTrigger == QLatin1String("offline"));
    const bool required = onboardingActive
        && (!m_hasSavedConfig || m_networkState != QLatin1String("online"));

    QString shortMessage;
    QString detailMessage;

    if (required) {
        if (!m_hasSavedConfig) {
            shortMessage = QStringLiteral("Set up Wi-Fi");
            detailMessage = QStringLiteral("No saved hotspot profile. Select your hotspot and enter the password.");
        } else if (m_networkState == QLatin1String("no_internet")) {
            shortMessage = QStringLiteral("Connected, no internet");
            detailMessage = QStringLiteral("Hotspot is connected but internet is unavailable.");
        } else if (m_networkState == QLatin1String("associated_no_ip")) {
            shortMessage = QStringLiteral("Connected, waiting for IP");
            detailMessage = QStringLiteral("Hotspot associated. Waiting for DHCP to finish.");
        } else {
            shortMessage = QStringLiteral("Waiting for hotspot");
            detailMessage = QStringLiteral("Turn on your hotspot and keep it nearby.");
        }
    } else {
        shortMessage = QStringLiteral("Hotspot online");
        detailMessage = QStringLiteral("Wi-Fi is connected and ready.");
    }

    setSetupRequired(required);
    setSetupMessages(shortMessage, detailMessage);
}

QString WiFiSetupService::managedAdminPassword(QString *errorOut) const
{
    QString fileError;
    QFile file(m_adminPasswordFile);
    if (file.exists()) {
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString secret = QString::fromUtf8(file.readAll()).trimmed();
            if (!secret.isEmpty()) {
                if (errorOut) {
                    errorOut->clear();
                }
                return secret;
            }
            fileError = QStringLiteral("Admin secret is empty: %1").arg(m_adminPasswordFile);
        } else {
            fileError = QStringLiteral("Cannot read admin secret file: %1").arg(m_adminPasswordFile);
        }
    } else {
        fileError = QStringLiteral("Missing admin secret file: %1").arg(m_adminPasswordFile);
    }

    const QString envValue = QString::fromUtf8(qgetenv("BEAGLEY_WIFI_ADMIN_PASSWORD")).trimmed();
    if (!envValue.isEmpty()) {
        if (errorOut) {
            errorOut->clear();
        }
        return envValue;
    }

    if (errorOut) {
        *errorOut = fileError.isEmpty()
            ? QStringLiteral("No managed admin secret configured.")
            : fileError;
    }
    return QString();
}

bool WiFiSetupService::shouldAutoShowPrompt() const
{
    if (!m_onboardingEnabled) {
        return false;
    }
    if (m_wizardTrigger == QLatin1String("manual")) {
        return false;
    }
    if (m_wizardTrigger == QLatin1String("offline")) {
        return m_networkState != QLatin1String("online");
    }
    return !m_hasSavedConfig;
}

WiFiSetupService::ExecResult WiFiSetupService::runCommand(const QString &program,
                                                          const QStringList &args,
                                                          const QByteArray &stdinData,
                                                          int timeoutMs) const
{
    ExecResult result;
    QProcess process;
    process.start(program, args);
    if (!process.waitForStarted(1000)) {
        result.stdErr = QStringLiteral("Failed to start ") + program;
        return result;
    }
    if (!stdinData.isEmpty()) {
        process.write(stdinData);
    }
    process.closeWriteChannel();
    process.waitForFinished(timeoutMs);

    result.exitCode = process.exitCode();
    result.stdOut = QString::fromUtf8(process.readAllStandardOutput());
    result.stdErr = QString::fromUtf8(process.readAllStandardError());
    return result;
}

void WiFiSetupService::refreshSavedConfig()
{
    const QString path = wpaFileForInterface(m_interfaceName);
    QFileInfo info(path);
    bool hasConfig = false;
    m_savedProfiles.clear();

    if (info.exists() && info.isFile()) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString contents = QString::fromUtf8(file.readAll());
            m_savedProfiles = WiFiHotspotProfiles::parseWpaSupplicantProfiles(contents);
            hasConfig = !m_savedProfiles.isEmpty();
        }
    }

    setHasSavedConfig(hasConfig);
}

bool WiFiSetupService::refreshStatusInternal(bool forceProbe)
{
    if (m_busy || m_process != nullptr) {
        scheduleReconcile(1000);
        return false;
    }

    refreshSavedConfig();

    bool interfacePresent = false;
    const ExecResult ifaceCheck = runCommand(QStringLiteral("bash"),
                                             {QStringLiteral("-lc"),
                                              QStringLiteral("ip link show ") + shellQuote(m_interfaceName)});
    interfacePresent = ifaceCheck.exitCode == 0;

    if (!interfacePresent) {
        m_activeProfileId.clear();
        m_activeFallbackAddress.clear();
        bool stateChanged = false;
        if (m_connected) {
            m_connected = false;
            stateChanged = true;
        }
        if (!m_currentSsid.isEmpty()) {
            m_currentSsid.clear();
            stateChanged = true;
        }
        if (stateChanged) {
            emit connectionChanged();
        }

        setHasIpLease(false);
        setInternetReachable(false);
        m_lastProbeError.clear();
        const StatusSnapshot snapshot = describeStatus(m_hasSavedConfig,
                                                       false,
                                                       false,
                                                       false,
                                                       false,
                                                       false,
                                                       m_interfaceName,
                                                       QString(),
                                                       QString());
        setNetworkState(snapshot.state);
        setStatus(snapshot.status);
        setStatusDetail(enrichStatusDetail(snapshot.detail,
                                           m_savedProfiles,
                                           m_activeProfileId,
                                           m_activeFallbackAddress));
        updateSetupMessaging();
        if (shouldAutoShowPrompt() && !m_promptDismissed) {
            setPromptVisible(true);
        }
        return false;
    }

    const ExecResult ipResult = runCommand(QStringLiteral("bash"),
                                           {QStringLiteral("-lc"),
                                            QStringLiteral("ip -4 -br a show ") + shellQuote(m_interfaceName)});
    const bool hasIpLeaseNow = ipResult.exitCode == 0
        && ipResult.stdOut.contains(QStringLiteral(" UP "))
        && ipResult.stdOut.contains(QLatin1Char('.'));
    setHasIpLease(hasIpLeaseNow);

    const ExecResult linkResult = runCommand(QStringLiteral("bash"),
                                             {QStringLiteral("-lc"),
                                              QStringLiteral("iw dev ") + shellQuote(m_interfaceName) + QStringLiteral(" link")});
    const QString linkText = linkResult.stdOut + QLatin1Char('\n') + linkResult.stdErr;

    const QRegularExpression ssidRe(QStringLiteral("^\\s*SSID:\\s*(.+)\\s*$"),
                                    QRegularExpression::MultilineOption);
    const QRegularExpressionMatch ssidMatch = ssidRe.match(linkText);

    bool connectedNow = false;
    QString ssidNow;
    if (ssidMatch.hasMatch()) {
        connectedNow = true;
        ssidNow = ssidMatch.captured(1).trimmed();
    } else if (linkText.contains(QStringLiteral("Not connected"), Qt::CaseInsensitive)) {
        connectedNow = false;
    }

    bool connectionStateChanged = false;
    if (m_connected != connectedNow) {
        m_connected = connectedNow;
        connectionStateChanged = true;
    }
    if (m_currentSsid != ssidNow) {
        m_currentSsid = ssidNow;
        connectionStateChanged = true;
    }
    if (connectionStateChanged) {
        emit connectionChanged();
    }

    const WiFiHotspotProfiles::SavedProfile activeProfile =
        WiFiHotspotProfiles::findProfileForSsid(m_savedProfiles, m_currentSsid);
    m_activeProfileId = activeProfile.id;
    m_activeFallbackAddress = activeProfile.fallbackAddress;

    if (!m_connected || !m_hasIpLease) {
        if (m_internetReply) {
            m_internetReply->abort();
            m_internetReply.clear();
        }
        m_lastProbeError.clear();
        setInternetReachable(false);
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool probeInFlight = !m_internetReply.isNull();
    const bool probeDue = m_connected
        && m_hasIpLease
        && !probeInFlight
        && (forceProbe
            || m_lastProbeStartedMs == 0
            || (nowMs - m_lastProbeStartedMs) >= kAssociatedReconcileMs);
    if (probeDue) {
        startInternetProbe();
    }

    const StatusSnapshot snapshot = describeStatus(m_hasSavedConfig,
                                                   true,
                                                   m_connected,
                                                   m_hasIpLease,
                                                   m_internetReachable,
                                                   !m_internetReply.isNull(),
                                                   m_interfaceName,
                                                   m_currentSsid,
                                                   m_lastProbeError);
    setNetworkState(snapshot.state);
    setStatus(snapshot.status);
    setStatusDetail(enrichStatusDetail(snapshot.detail,
                                       m_savedProfiles,
                                       m_activeProfileId,
                                       m_activeFallbackAddress));
    updateSetupMessaging();

    if (shouldAutoShowPrompt()) {
        if (!m_promptDismissed) {
            setPromptVisible(true);
        }
    } else {
        m_promptDismissed = false;
        setPromptVisible(false);
    }

    return true;
}

void WiFiSetupService::scheduleReconcile(int delayMs)
{
    const int effectiveDelay = delayMs >= 0
        ? delayMs
        : ((m_connected && m_hasIpLease) ? kAssociatedReconcileMs : kDisconnectedReconcileMs);
    m_reconcileTimer.start(qMax(0, effectiveDelay));
}

void WiFiSetupService::startInternetProbe()
{
    if (!m_connected || !m_hasIpLease || m_internetCheckUrl.isEmpty() || m_internetReply) {
        return;
    }

    const QUrl url(m_internetCheckUrl);
    QNetworkRequest request(url);
    request.setTransferTimeout(kProbeTransferTimeoutMs);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    qInfo() << "[WiFiSetupService] probing internet via" << request.url();

    m_lastProbeStartedMs = QDateTime::currentMSecsSinceEpoch();
    QNetworkReply *reply = m_network.get(request);
    m_internetReply = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = reply->error() == QNetworkReply::NoError
            || httpStatus == 204
            || httpStatus == 304;
        if (!ok) {
            m_lastProbeError = reply->errorString();
            qWarning() << "[WiFiSetupService] internet probe failed" << reply->url() << reply->errorString();
        } else {
            m_lastProbeError.clear();
        }

        setInternetReachable(ok);
        reply->deleteLater();
        if (m_internetReply == reply) {
            m_internetReply.clear();
        }

        refreshStatusInternal(false);
        if (!ok) {
            scheduleReconcile(0);
        } else {
            scheduleReconcile();
        }
    });
}

void WiFiSetupService::refreshStatus()
{
    m_forceProbeOnNextRefresh = true;
    refreshStatusInternal(true);
    scheduleReconcile();
}

void WiFiSetupService::parseScanOutput(const QString &scanText)
{
    QVariantList rows;
    const QVector<WiFiSsidUtils::ScanRow> parsedRows = WiFiSsidUtils::parseIwScanNetworks(scanText);
    rows.reserve(parsedRows.size());
    for (const WiFiSsidUtils::ScanRow &scanRow : parsedRows) {
        QVariantMap row;
        row.insert(QStringLiteral("ssid"), scanRow.ssid);
        row.insert(QStringLiteral("signalDbm"), scanRow.signalDbm);
        row.insert(QStringLiteral("secure"), scanRow.secure);
        rows.append(row);
    }

    m_networks = rows;
    emit networksChanged();
}

void WiFiSetupService::scanNetworks()
{
    if (m_busy || m_process != nullptr) {
        return;
    }

    setBusy(true);
    setStatus(QStringLiteral("Scanning nearby Wi-Fi networks..."));
    setStatusDetail(QStringLiteral("Running a passive scan on %1 for diagnostics.").arg(m_interfaceName));
    m_activeTask = Task::Scan;

    m_process = new QProcess(this);
    connect(m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus) {
        const QString stdOut = QString::fromUtf8(m_process->readAllStandardOutput());
        const QString stdErr = QString::fromUtf8(m_process->readAllStandardError());

        if (exitCode == 0) {
            parseScanOutput(stdOut);
            if (m_networks.isEmpty()) {
                setStatus(QStringLiteral("No SSIDs found."));
                setStatusDetail(QStringLiteral("Move closer to the hotspot or refresh the scan again."));
            } else {
                setStatus(QStringLiteral("Found %1 network(s).").arg(m_networks.size()));
                setStatusDetail(QStringLiteral("Diagnostics scan completed on %1.").arg(m_interfaceName));
            }
        } else {
            setStatus(QStringLiteral("Wi-Fi scan failed."));
            setStatusDetail(stdErr.trimmed().isEmpty()
                                ? QStringLiteral("The scan command returned no error details.")
                                : stdErr.trimmed());
        }

        m_process->deleteLater();
        m_process = nullptr;
        m_activeTask = Task::None;
        setBusy(false);
        scheduleReconcile(0);
    });

    const QString command = QStringLiteral("iw dev ") + shellQuote(m_interfaceName) + QStringLiteral(" scan");
    m_process->start(QStringLiteral("bash"), {QStringLiteral("-lc"), command});
}

void WiFiSetupService::connectToNetwork(const QString &ssid,
                                        const QString &passphrase,
                                        const QString &countryCode)
{
    if (!m_onboardingEnabled) {
        setStatus(QStringLiteral("Wi-Fi setup disabled."));
        setStatusDetail(QStringLiteral("Onboarding is disabled by BEAGLEY_WIFI_ONBOARDING=0."));
        return;
    }

    if (m_busy || m_process != nullptr) {
        return;
    }

    const QString normalizedSsid = WiFiSsidUtils::normalizeSsidForConnect(ssid);
    if (normalizedSsid.isEmpty()) {
        setStatus(QStringLiteral("SSID is required."));
        setStatusDetail(QStringLiteral("Pick a hotspot from the scan list before attempting to connect."));
        return;
    }
    if (passphrase.size() < 8) {
        setStatus(QStringLiteral("Wi-Fi password too short."));
        setStatusDetail(QStringLiteral("Wi-Fi password must be at least 8 characters (entered %1).")
                            .arg(passphrase.size()));
        return;
    }

    const bool runningAsRoot = (runCommand(QStringLiteral("id"), {QStringLiteral("-u")}, QByteArray(), 1000)
                                    .stdOut.trimmed() == QStringLiteral("0"));
    QString adminPassword;
    if (!runningAsRoot) {
        QString secretError;
        adminPassword = managedAdminPassword(&secretError);
        if (adminPassword.isEmpty()) {
            setStatus(QStringLiteral("Device setup incomplete."));
            setStatusDetail(secretError
                + QStringLiteral("\nProvide BEAGLEY_WIFI_ADMIN_PASSWORD_FILE or BEAGLEY_WIFI_ADMIN_PASSWORD."));
            setPromptVisible(true);
            updateSetupMessaging();
            return;
        }
    }

    const QString safeIface = shellQuote(m_interfaceName);
    const QString safeCountry = shellQuote(countryCode.trimmed().isEmpty()
                                               ? QStringLiteral("AU")
                                               : countryCode.trimmed().left(2).toUpper());
    const QString safeSsid = shellQuote(normalizedSsid);
    const QString safePass = shellQuote(passphrase);
    const QString safeProfileId = shellQuote(profileIdForSsid(normalizedSsid));

    const QString script = QStringLiteral(
        "set -euo pipefail\n"
        "IFACE=%1\n"
        "COUNTRY=%2\n"
        "SSID=%3\n"
        "PASS=%4\n"
        "PROFILE_ID=%5\n"
        "WPA_FILE=\"/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf\"\n"
        "NET_FILE=\"/etc/systemd/network/${IFACE}.network\"\n"
        "TMP_FILE=$(mktemp)\n"
        "trap 'rm -f \"$TMP_FILE\"' EXIT\n"
        "mkdir -p /etc/wpa_supplicant /etc/systemd/network\n"
        "{\n"
        "  echo \"ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev\"\n"
        "  echo \"update_config=1\"\n"
        "  echo \"country=${COUNTRY}\"\n"
        "  echo \"ap_scan=1\"\n"
        "  echo \"fast_reauth=1\"\n"
        "  echo\n"
        "  echo \"# BEAGLEY_PROFILE id=${PROFILE_ID} fallback=-\"\n"
        "  wpa_passphrase \"$SSID\" \"$PASS\" | awk -v profile_id=\"$PROFILE_ID\" '\\''\n"
        "    /^[[:space:]]*#psk=/ { next }\n"
        "    /^\\}/ {\n"
        "      print \"\\tpriority=100\"\n"
        "      print \"\\tid_str=\\\"\" profile_id \"\\\"\"\n"
        "      print \"\\tscan_ssid=1\"\n"
        "      print\n"
        "      next\n"
        "    }\n"
        "    { print }\n"
        "  '\\''\n"
        "} > \"$TMP_FILE\"\n"
        "install -m 600 \"$TMP_FILE\" \"$WPA_FILE\"\n"
        "cat > \"$NET_FILE\" <<'EOF'\n"
        "[Match]\n"
        "Name=%6\n"
        "Type=wlan\n"
        "\n"
        "[Link]\n"
        "RequiredForOnline=no\n"
        "\n"
        "[Network]\n"
        "DHCP=ipv4\n"
        "\n"
        "[DHCPv4]\n"
        "RouteMetric=200\n"
        "EOF\n"
        "ip link set \"$IFACE\" up || true\n"
        "systemctl daemon-reload\n"
        "systemctl enable \"wpa_supplicant@${IFACE}.service\"\n"
        "systemctl restart \"wpa_supplicant@${IFACE}.service\"\n"
        "wpa_cli -i \"$IFACE\" reconfigure >/dev/null 2>&1 || true\n"
        "systemctl restart systemd-networkd\n"
        "ASSOC_STATE=UNKNOWN\n"
        "ASSOC_STATUS=\"\"\n"
        "for _ in $(seq 1 20); do\n"
        "  ASSOC_STATUS=$(wpa_cli -i \"$IFACE\" status 2>/dev/null || true)\n"
        "  ASSOC_STATE=$(printf \"%s\\n\" \"$ASSOC_STATUS\" | awk -F= '$1==\"wpa_state\"{print $2; exit}')\n"
        "  if [ -z \"$ASSOC_STATE\" ]; then ASSOC_STATE=UNKNOWN; fi\n"
        "  if [ \"$ASSOC_STATE\" = \"COMPLETED\" ]; then break; fi\n"
        "  sleep 1\n"
        "done\n"
        "echo \"ASSOC_STATE=$ASSOC_STATE\"\n"
        "echo \"ASSOC_STATUS_BEGIN\"\n"
        "printf \"%s\\n\" \"$ASSOC_STATUS\"\n"
        "echo \"ASSOC_STATUS_END\"\n"
        "echo \"WPA_JOURNAL_BEGIN\"\n"
        "journalctl -u \"wpa_supplicant@${IFACE}.service\" -n 40 --no-pager || true\n"
        "echo \"WPA_JOURNAL_END\"\n"
        "iw dev \"$IFACE\" link || true\n"
        "ip -br a show \"$IFACE\" || true\n")
        .arg(safeIface, safeCountry, safeSsid, safePass, safeProfileId, m_interfaceName);

    setBusy(true);
    setStatus(QStringLiteral("Provisioning hotspot profile..."));
    setStatusDetail(QStringLiteral("Saving Wi-Fi profile for %1.").arg(normalizedSsid));
    m_activeTask = Task::Connect;

    m_process = new QProcess(this);
    connect(m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus) {
        const QString stdOut = QString::fromUtf8(m_process->readAllStandardOutput());
        const QString stdErr = QString::fromUtf8(m_process->readAllStandardError());
        const QString assocState = valueForPrefix(stdOut, QStringLiteral("ASSOC_STATE="));
        const QString assocStatus = blockForMarkers(stdOut,
                                                    QStringLiteral("ASSOC_STATUS_BEGIN"),
                                                    QStringLiteral("ASSOC_STATUS_END"));
        const QString journalBlock = blockForMarkers(stdOut,
                                                     QStringLiteral("WPA_JOURNAL_BEGIN"),
                                                     QStringLiteral("WPA_JOURNAL_END"));
        const QString combinedText = stdOut + QLatin1Char('\n') + stdErr + QLatin1Char('\n')
            + assocStatus + QLatin1Char('\n') + journalBlock;
        const QString journalSummary = summarizeJournal(journalBlock);

        if (exitCode == 0) {
            refreshSavedConfig();
            refreshStatusInternal(true);
            if (m_connected || assocState.compare(QStringLiteral("COMPLETED"), Qt::CaseInsensitive) == 0) {
                setStatus(QStringLiteral("Wi-Fi connected."));
                setStatusDetail(QStringLiteral("Connected to %1.").arg(m_currentSsid));
                setPromptVisible(false);
            } else {
                const QString category = classifyAssociationCategory(assocState, combinedText);
                const QString stateValue = assocState.isEmpty() ? QStringLiteral("UNKNOWN") : assocState;
                QString statusLine = QStringLiteral("[%1] %2 state=%3")
                                         .arg(category, categoryDetail(category), stateValue);
                if (!journalSummary.isEmpty()) {
                    statusLine += QLatin1Char('\n') + journalSummary;
                }
                setStatus(QStringLiteral("Wi-Fi profile saved, still connecting."));
                setStatusDetail(statusLine);
                setPromptVisible(true);
            }
        } else {
            const QString category = classifyAssociationCategory(assocState, combinedText);
            const QString stderrSummary = stdErr.trimmed().isEmpty()
                ? QStringLiteral("unknown error")
                : stdErr.trimmed();
            QString detailLine = QStringLiteral("[%1] Wi-Fi setup failed: %2")
                                     .arg(category, stderrSummary);
            if (!journalSummary.isEmpty()) {
                detailLine += QLatin1Char('\n') + journalSummary;
            }
            setStatus(QStringLiteral("Wi-Fi setup failed."));
            setStatusDetail(detailLine);
            setPromptVisible(true);
        }

        updateSetupMessaging();
        m_process->deleteLater();
        m_process = nullptr;
        m_activeTask = Task::None;
        setBusy(false);
        scheduleReconcile(0);
    });

    if (runningAsRoot) {
        m_process->start(QStringLiteral("bash"), {QStringLiteral("-lc"), script});
    } else {
        m_process->start(QStringLiteral("sudo"),
                         {QStringLiteral("-S"),
                          QStringLiteral("-p"),
                          QString(),
                          QStringLiteral("bash"),
                          QStringLiteral("-lc"),
                          script});
        m_process->write(adminPassword.toUtf8());
        m_process->write("\n");
        m_process->closeWriteChannel();
    }
}

void WiFiSetupService::showPrompt()
{
    m_promptDismissed = false;
    setPromptVisible(true);
    refreshStatus();
}

void WiFiSetupService::dismissPrompt()
{
    m_promptDismissed = true;
    setPromptVisible(false);
}
