#pragma once

#include <QObject>
#include <QTcpSocket>
#include <QTimer>
#include <QDateTime>
#include <QString>
#include <QUrl>
#include <QVector>
#include <limits>

class VehicleStateClient : public QObject
{
    Q_OBJECT

    // Link health
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool linkStale READ linkStale NOTIFY linkStaleChanged)
    Q_PROPERTY(int  rxAgeMs READ rxAgeMs NOTIFY rxAgeMsChanged)
    Q_PROPERTY(bool vehicleStateSeen READ vehicleStateSeen NOTIFY vehicleStateSeenChanged)

    // Indicators (truth from BBB)
    Q_PROPERTY(bool leftIndicator READ leftIndicator NOTIFY leftIndicatorChanged)
    Q_PROPERTY(bool rightIndicator READ rightIndicator NOTIFY rightIndicatorChanged)
    Q_PROPERTY(bool highBeam READ highBeam NOTIFY highBeamChanged)

    // Warnings (truth from BBB)
    Q_PROPERTY(bool warnBrake READ warnBrake NOTIFY warnBrakeChanged)
    Q_PROPERTY(bool warnOil READ warnOil NOTIFY warnOilChanged)
    Q_PROPERTY(bool warnCharge READ warnCharge NOTIFY warnChargeChanged)
    Q_PROPERTY(bool warnDoor READ warnDoor NOTIFY warnDoorChanged)
    Q_PROPERTY(bool warnCheckEngine READ warnCheckEngine NOTIFY warnCheckEngineChanged)
    Q_PROPERTY(bool warnAT READ warnAT NOTIFY warnATChanged)
    Q_PROPERTY(bool warnFuelLow READ warnFuelLow NOTIFY warnFuelLowChanged)

    // BBB-declared stale (separate from linkStale)
    Q_PROPERTY(bool bbbStale READ bbbStale NOTIFY bbbStaleChanged)

    // Normalized diagnostic status emitted by the BBB hub.
    Q_PROPERTY(bool diagnosticOk READ diagnosticOk NOTIFY diagnosticChanged)
    Q_PROPERTY(QString diagnosticSeverity READ diagnosticSeverity NOTIFY diagnosticChanged)
    Q_PROPERTY(QString diagnosticStatus READ diagnosticStatus NOTIFY diagnosticChanged)
    Q_PROPERTY(QString diagnosticSummary READ diagnosticSummary NOTIFY diagnosticChanged)
    Q_PROPERTY(int diagnosticFindingCount READ diagnosticFindingCount NOTIFY diagnosticChanged)

    // Core analogs (truth from BBB)
    Q_PROPERTY(double speedKph READ speedKph NOTIFY speedKphChanged)
    Q_PROPERTY(int    rpm READ rpm NOTIFY rpmChanged)
    Q_PROPERTY(double fuelPct READ fuelPct NOTIFY fuelPctChanged)
    Q_PROPERTY(double coolantC READ coolantC NOTIFY coolantCChanged)
    Q_PROPERTY(QString gear READ gear NOTIFY gearChanged)
    Q_PROPERTY(bool overdrive READ overdrive NOTIFY overdriveChanged)
    Q_PROPERTY(QString drivetrainMode READ drivetrainMode NOTIFY drivetrainModeChanged)
    Q_PROPERTY(bool transferLock READ transferLock NOTIFY transferLockChanged)
    Q_PROPERTY(double gpsLat READ gpsLat NOTIFY gpsLatChanged)
    Q_PROPERTY(double gpsLng READ gpsLng NOTIFY gpsLngChanged)
    Q_PROPERTY(double gpsBearing READ gpsBearing NOTIFY gpsBearingChanged)
    Q_PROPERTY(double gpsAccuracyM READ gpsAccuracyM NOTIFY gpsAccuracyMChanged)
    Q_PROPERTY(qint64 gpsTimestampMs READ gpsTimestampMs NOTIFY gpsTimestampMsChanged)
    Q_PROPERTY(bool gpsFixValid READ gpsFixValid NOTIFY gpsFixValidChanged)
    Q_PROPERTY(bool gpsEverValid READ gpsEverValid NOTIFY gpsEverValidChanged)
    Q_PROPERTY(QString gpsSource READ gpsSource NOTIFY gpsSourceChanged)
    Q_PROPERTY(int gpsSatellites READ gpsSatellites NOTIFY gpsSatellitesChanged)
    Q_PROPERTY(bool gpsHeadingReliable READ gpsHeadingReliable NOTIFY gpsHeadingReliableChanged)
    Q_PROPERTY(double gpsSpeedKph READ gpsSpeedKph NOTIFY gpsSpeedKphChanged)
    Q_PROPERTY(bool gpsPoseValid READ gpsPoseValid NOTIFY gpsPoseValidChanged)

public:
    explicit VehicleStateClient(QObject *parent = nullptr);

    bool connected() const { return m_connected; }
    bool linkStale() const { return m_linkStale; }
    int  rxAgeMs() const { return m_rxAgeMs; }
    bool vehicleStateSeen() const { return m_vehicleStateSeen; }

    bool leftIndicator() const { return m_leftIndicator; }
    bool rightIndicator() const { return m_rightIndicator; }
    bool highBeam() const { return m_highBeam; }

    bool warnBrake() const { return m_warnBrake; }
    bool warnOil() const { return m_warnOil; }
    bool warnCharge() const { return m_warnCharge; }
    bool warnDoor() const { return m_warnDoor; }
    bool warnCheckEngine() const { return m_warnCheckEngine; }
    bool warnAT() const { return m_warnAT; }
    bool warnFuelLow() const { return m_warnFuelLow; }

    bool bbbStale() const { return m_bbbStale; }
    bool diagnosticOk() const { return m_diagnosticOk; }
    QString diagnosticSeverity() const { return m_diagnosticSeverity; }
    QString diagnosticStatus() const { return m_diagnosticStatus; }
    QString diagnosticSummary() const { return m_diagnosticSummary; }
    int diagnosticFindingCount() const { return m_diagnosticFindingCount; }

    double speedKph() const { return m_speedKph; }
    int    rpm() const { return m_rpm; }
    double fuelPct() const { return m_fuelPct; }
    double coolantC() const { return m_coolantC; }
    QString gear() const { return m_gear; }
    bool overdrive() const { return m_overdrive; }
    QString drivetrainMode() const { return m_drivetrainMode; }
    bool transferLock() const { return m_transferLock; }
    double gpsLat() const { return m_gpsLat; }
    double gpsLng() const { return m_gpsLng; }
    double gpsBearing() const { return m_gpsBearing; }
    double gpsAccuracyM() const { return m_gpsAccuracyM; }
    qint64 gpsTimestampMs() const { return m_gpsTimestampMs; }
    bool gpsFixValid() const { return m_gpsFixValid; }
    bool gpsEverValid() const { return m_gpsEverValid; }
    QString gpsSource() const { return m_gpsSource; }
    int gpsSatellites() const { return m_gpsSatellites; }
    bool gpsHeadingReliable() const { return m_gpsHeadingReliable; }
    double gpsSpeedKph() const { return m_gpsSpeedKph; }
    bool gpsPoseValid() const { return m_gpsPoseValid; }

signals:
    void connectedChanged();
    void linkStaleChanged();
    void rxAgeMsChanged();
    void vehicleStateSeenChanged();

    void leftIndicatorChanged();
    void rightIndicatorChanged();
    void highBeamChanged();

    void warnBrakeChanged();
    void warnOilChanged();
    void warnChargeChanged();
    void warnDoorChanged();
    void warnCheckEngineChanged();
    void warnATChanged();
    void warnFuelLowChanged();
    void bbbStaleChanged();
    void diagnosticChanged();

    void speedKphChanged();
    void rpmChanged();
    void fuelPctChanged();
    void coolantCChanged();
    void gearChanged();
    void overdriveChanged();
    void drivetrainModeChanged();
    void transferLockChanged();
    void gpsLatChanged();
    void gpsLngChanged();
    void gpsBearingChanged();
    void gpsAccuracyMChanged();
    void gpsTimestampMsChanged();
    void gpsFixValidChanged();
    void gpsEverValidChanged();
    void gpsSourceChanged();
    void gpsSatellitesChanged();
    void gpsHeadingReliableChanged();
    void gpsSpeedKphChanged();
    void gpsPoseValidChanged();

private slots:
    void onSocketConnected();
    void onSocketReadyRead();
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &msg);
    void checkStale();
    void playNextReplayFrame();

private:
    void loadReplayFrames(const QString &path);
    void scheduleReconnect();
    void connectNow();
    void sendHandshakeRequest();
    void processSocketBuffer();
    void processHandshake();
    void processFrameBuffer();
    void sendControlFrame(quint8 opcode, const QByteArray &payload = QByteArray());

    void setConnected(bool v);
    void setLinkStale(bool v);
    void setRxAgeMs(int v);
    void setVehicleStateSeen(bool v);

    void setLeftIndicator(bool v);
    void setRightIndicator(bool v);
    void setHighBeam(bool v);

    void setWarnBrake(bool v);
    void setWarnOil(bool v);
    void setWarnCharge(bool v);
    void setWarnDoor(bool v);
    void setWarnCheckEngine(bool v);
    void setWarnAT(bool v);
    void setWarnFuelLow(bool v);
    void setBbbStale(bool v);
    void setDiagnosticOk(bool v);
    void setDiagnosticSeverity(const QString &v);
    void setDiagnosticStatus(const QString &v);
    void setDiagnosticSummary(const QString &v);
    void setDiagnosticFindingCount(int v);

    void setSpeedKph(double v);
    void setRpm(int v);
    void setFuelPct(double v);
    void setCoolantC(double v);
    void setGear(const QString &v);
    void setOverdrive(bool v);
    void setDrivetrainMode(const QString &v);
    void setTransferLock(bool v);
    void setGpsLat(double v);
    void setGpsLng(double v);
    void setGpsBearing(double v);
    void setGpsAccuracyM(double v);
    void setGpsTimestampMs(qint64 v);
    void setGpsFixValid(bool v);
    void setGpsSource(const QString &v);
    void setGpsSatellites(int v);
    void setGpsHeadingReliable(bool v);
    void setGpsSpeedKph(double v);
    void setGpsPoseValid(bool v);

private:
    QTcpSocket m_socket;
    QTimer m_watchdog;
    QTimer m_reconnect;
    QTimer m_replayTimer;

    QString m_url;
    QUrl m_connectUrl;
    QByteArray m_socketBuffer;
    QByteArray m_fragmentBuffer;
    QByteArray m_handshakeKey;
    bool m_handshakeComplete = false;
    bool m_fragmentIsText = false;
    bool m_replayMode = false;
    bool m_replayLoop = false;
    int m_replayIndex = 0;
    QVector<QString> m_replayFrames;
    QVector<int> m_replayDelaysMs;

    qint64 m_lastGoodRxMs = 0;
    int m_backoffMs = 250;

    bool m_connected = false;
    bool m_linkStale = true;
    int  m_rxAgeMs = 0;
    bool m_vehicleStateSeen = false;

    bool m_leftIndicator = false;
    bool m_rightIndicator = false;
    bool m_highBeam = false;

    bool m_warnBrake = false;
    bool m_warnOil = false;
    bool m_warnCharge = false;
    bool m_warnDoor = false;
    bool m_warnCheckEngine = false;
    bool m_warnAT = false;
    bool m_warnFuelLow = false;
    bool m_bbbStale = true;
    bool m_diagnosticOk = true;
    QString m_diagnosticSeverity = QStringLiteral("unknown");
    QString m_diagnosticStatus = QStringLiteral("unknown");
    QString m_diagnosticSummary;
    int m_diagnosticFindingCount = 0;

    double m_speedKph = 0.0;
    int    m_rpm = 0;
    double m_fuelPct = 0.0;
    double m_coolantC = 0.0;
    QString m_gear = QStringLiteral("P");
    bool m_overdrive = false;
    QString m_drivetrainMode = QStringLiteral("2wd");
    bool m_transferLock = false;
    double m_gpsLat = std::numeric_limits<double>::quiet_NaN();
    double m_gpsLng = std::numeric_limits<double>::quiet_NaN();
    double m_gpsBearing = 0.0;
    double m_gpsAccuracyM = 0.0;
    qint64 m_gpsTimestampMs = 0;
    bool m_gpsFixValid = false;
    bool m_gpsEverValid = false;
    QString m_gpsSource;
    int m_gpsSatellites = 0;
    bool m_gpsHeadingReliable = false;
    double m_gpsSpeedKph = 0.0;
    bool m_gpsPoseValid = false;
};
