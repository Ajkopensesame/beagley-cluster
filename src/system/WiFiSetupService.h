#pragma once

#include "WiFiHotspotProfiles.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>

class QProcess;
class QNetworkReply;

class WiFiSetupService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList networks READ networks NOTIFY networksChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString statusDetail READ statusDetail NOTIFY statusDetailChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(bool hasIpLease READ hasIpLease NOTIFY connectionChanged)
    Q_PROPERTY(QString currentSsid READ currentSsid NOTIFY connectionChanged)
    Q_PROPERTY(bool internetReachable READ internetReachable NOTIFY internetReachableChanged)
    Q_PROPERTY(bool hasSavedConfig READ hasSavedConfig NOTIFY savedConfigChanged)
    Q_PROPERTY(QString networkState READ networkState NOTIFY networkStateChanged)
    Q_PROPERTY(bool promptVisible READ promptVisible NOTIFY promptVisibleChanged)
    Q_PROPERTY(bool onboardingEnabled READ onboardingEnabled CONSTANT)
    Q_PROPERTY(QString wizardTrigger READ wizardTrigger CONSTANT)
    Q_PROPERTY(bool setupRequired READ setupRequired NOTIFY setupRequiredChanged)
    Q_PROPERTY(QString setupMessageShort READ setupMessageShort NOTIFY setupMessagesChanged)
    Q_PROPERTY(QString setupMessageDetail READ setupMessageDetail NOTIFY setupMessagesChanged)
    Q_PROPERTY(bool configWriteEnabled READ configWriteEnabled CONSTANT)
    Q_PROPERTY(QString interfaceName READ interfaceName WRITE setInterfaceName NOTIFY interfaceNameChanged)

public:
    explicit WiFiSetupService(QObject *parent = nullptr);

    QVariantList networks() const { return m_networks; }
    bool busy() const { return m_busy; }
    QString status() const { return m_status; }
    QString statusDetail() const { return m_statusDetail; }
    bool connected() const { return m_connected; }
    bool hasIpLease() const { return m_hasIpLease; }
    QString currentSsid() const { return m_currentSsid; }
    bool internetReachable() const { return m_internetReachable; }
    bool hasSavedConfig() const { return m_hasSavedConfig; }
    QString networkState() const { return m_networkState; }
    bool promptVisible() const { return m_promptVisible; }
    bool onboardingEnabled() const { return m_onboardingEnabled; }
    QString wizardTrigger() const { return m_wizardTrigger; }
    bool setupRequired() const { return m_setupRequired; }
    QString setupMessageShort() const { return m_setupMessageShort; }
    QString setupMessageDetail() const { return m_setupMessageDetail; }
    bool configWriteEnabled() const { return m_configWriteEnabled; }
    QString interfaceName() const { return m_interfaceName; }

    Q_INVOKABLE void refreshStatus();
    Q_INVOKABLE void scanNetworks();
    Q_INVOKABLE void connectToNetwork(const QString &ssid,
                                      const QString &passphrase,
                                      const QString &countryCode = QStringLiteral("AU"));
    Q_INVOKABLE void showPrompt();
    Q_INVOKABLE void dismissPrompt();

    void setInterfaceName(const QString &name);

signals:
    void networksChanged();
    void busyChanged();
    void statusChanged();
    void statusDetailChanged();
    void connectionChanged();
    void internetReachableChanged();
    void savedConfigChanged();
    void networkStateChanged();
    void promptVisibleChanged();
    void setupRequiredChanged();
    void setupMessagesChanged();
    void interfaceNameChanged();

private:
    enum class Task {
        None,
        Scan,
        Connect
    };

    struct ExecResult {
        int exitCode = -1;
        QString stdOut;
        QString stdErr;
    };

    ExecResult runCommand(const QString &program,
                          const QStringList &args,
                          const QByteArray &stdinData = QByteArray(),
                          int timeoutMs = 6000) const;
    bool refreshStatusInternal(bool forceProbe);
    void scheduleReconcile(int delayMs = -1);
    void refreshSavedConfig();
    void startInternetProbe();
    void parseScanOutput(const QString &scanText);
    void setStatus(const QString &value);
    void setStatusDetail(const QString &value);
    void setBusy(bool value);
    void setPromptVisible(bool value);
    void setHasIpLease(bool value);
    void setInternetReachable(bool value);
    void setHasSavedConfig(bool value);
    void setNetworkState(const QString &value);
    QString managedAdminPassword(QString *errorOut = nullptr) const;
    bool shouldAutoShowPrompt() const;
    void updateSetupMessaging();
    void setSetupRequired(bool value);
    void setSetupMessages(const QString &shortMessage, const QString &detailMessage);

    QVariantList m_networks;
    bool m_busy = false;
    QString m_status = QStringLiteral("Wi-Fi not configured.");
    QString m_statusDetail;
    bool m_connected = false;
    bool m_hasIpLease = false;
    QString m_currentSsid;
    bool m_internetReachable = false;
    bool m_hasSavedConfig = false;
    QString m_networkState = QStringLiteral("waiting_for_hotspot");
    bool m_promptVisible = false;
    bool m_promptDismissed = false;
    bool m_onboardingEnabled = true;
    QString m_wizardTrigger = QStringLiteral("no_config");
    QString m_interfaceName = QStringLiteral("wlan0");
    bool m_configWriteEnabled = true;
    bool m_setupRequired = false;
    QString m_setupMessageShort;
    QString m_setupMessageDetail;
    bool m_forceProbeOnNextRefresh = true;
    qint64 m_lastProbeStartedMs = 0;
    QString m_lastProbeError;
    QString m_adminPasswordFile;
    QVector<WiFiHotspotProfiles::SavedProfile> m_savedProfiles;
    QString m_activeProfileId;
    QString m_activeFallbackAddress;

    Task m_activeTask = Task::None;
    QProcess *m_process = nullptr;
    QNetworkAccessManager m_network;
    QTimer m_reconcileTimer;
    QPointer<QNetworkReply> m_internetReply;
    QString m_internetCheckUrl;
};
