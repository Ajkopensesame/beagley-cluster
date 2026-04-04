#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>

class NavigationService;
class VehicleStateClient;

class ClusterRenderModel final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool linkOk READ linkOk NOTIFY statusChanged)
    Q_PROPERTY(bool truthOk READ truthOk NOTIFY statusChanged)
    Q_PROPERTY(bool internetOk READ internetOk NOTIFY statusChanged)
    Q_PROPERTY(bool gpsOk READ gpsOk NOTIFY statusChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(QString networkText READ networkText NOTIFY statusChanged)
    Q_PROPERTY(QString warningSummary READ warningSummary NOTIFY statusChanged)
    Q_PROPERTY(int activeWarnings READ activeWarnings NOTIFY statusChanged)

    Q_PROPERTY(double speedKph READ speedKph NOTIFY analogChanged)
    Q_PROPERTY(int rpm READ rpm NOTIFY analogChanged)
    Q_PROPERTY(double fuelPct READ fuelPct NOTIFY analogChanged)
    Q_PROPERTY(double coolantC READ coolantC NOTIFY analogChanged)
    Q_PROPERTY(QString gear READ gear NOTIFY analogChanged)
    Q_PROPERTY(QString drivetrainMode READ drivetrainMode NOTIFY analogChanged)
    Q_PROPERTY(bool overdrive READ overdrive NOTIFY analogChanged)
    Q_PROPERTY(bool leftIndicator READ leftIndicator NOTIFY analogChanged)
    Q_PROPERTY(bool rightIndicator READ rightIndicator NOTIFY analogChanged)
    Q_PROPERTY(bool highBeam READ highBeam NOTIFY analogChanged)

    Q_PROPERTY(double mapLat READ mapLat NOTIFY mapChanged)
    Q_PROPERTY(double mapLng READ mapLng NOTIFY mapChanged)
    Q_PROPERTY(double mapBearing READ mapBearing NOTIFY mapChanged)
    Q_PROPERTY(double mapZoom READ mapZoom NOTIFY mapChanged)
    Q_PROPERTY(QVariantList routePath READ routePath NOTIFY mapChanged)
    Q_PROPERTY(QString nextInstruction READ nextInstruction NOTIFY guidanceChanged)
    Q_PROPERTY(QString guidanceDetail READ guidanceDetail NOTIFY guidanceChanged)
    Q_PROPERTY(QString etaText READ etaText NOTIFY guidanceChanged)

public:
    explicit ClusterRenderModel(VehicleStateClient *vehicleState,
                                NavigationService *navigation,
                                QObject *parent = nullptr);

    bool linkOk() const { return m_linkOk; }
    bool truthOk() const { return m_truthOk; }
    bool internetOk() const { return m_internetOk; }
    bool gpsOk() const { return m_gpsOk; }
    QString statusText() const { return m_statusText; }
    QString networkText() const { return m_networkText; }
    QString warningSummary() const { return m_warningSummary; }
    int activeWarnings() const { return m_activeWarnings; }

    double speedKph() const { return m_speedKph; }
    int rpm() const { return m_rpm; }
    double fuelPct() const { return m_fuelPct; }
    double coolantC() const { return m_coolantC; }
    QString gear() const { return m_gear; }
    QString drivetrainMode() const { return m_drivetrainMode; }
    bool overdrive() const { return m_overdrive; }
    bool leftIndicator() const { return m_leftIndicator; }
    bool rightIndicator() const { return m_rightIndicator; }
    bool highBeam() const { return m_highBeam; }

    double mapLat() const { return m_mapLat; }
    double mapLng() const { return m_mapLng; }
    double mapBearing() const { return m_mapBearing; }
    double mapZoom() const { return m_mapZoom; }
    QVariantList routePath() const { return m_routePath; }
    QString nextInstruction() const { return m_nextInstruction; }
    QString guidanceDetail() const { return m_guidanceDetail; }
    QString etaText() const { return m_etaText; }

signals:
    void statusChanged();
    void analogChanged();
    void mapChanged();
    void guidanceChanged();

private:
    void syncStatus();
    void syncGuidance();
    void syncRoutePath();
    void tick();

    VehicleStateClient *m_vehicleState = nullptr;
    NavigationService *m_navigation = nullptr;
    QTimer m_tickTimer;

    bool m_linkOk = false;
    bool m_truthOk = false;
    bool m_internetOk = false;
    bool m_gpsOk = false;
    QString m_statusText = QStringLiteral("BOOT");
    QString m_networkText = QStringLiteral("OFFLINE");
    QString m_warningSummary = QStringLiteral("SYSTEMS NOMINAL");
    int m_activeWarnings = 0;

    double m_speedKph = 0.0;
    double m_targetSpeedKph = 0.0;
    int m_rpm = 0;
    double m_targetRpm = 0.0;
    double m_fuelPct = 0.0;
    double m_targetFuelPct = 0.0;
    double m_coolantC = 0.0;
    double m_targetCoolantC = 0.0;
    QString m_gear = QStringLiteral("-");
    QString m_drivetrainMode = QStringLiteral("2WD");
    bool m_overdrive = false;
    bool m_leftIndicator = false;
    bool m_rightIndicator = false;
    bool m_highBeam = false;

    double m_mapLat = 0.0;
    double m_mapLng = 0.0;
    double m_mapBearing = 0.0;
    double m_mapZoom = 14.0;
    QVariantList m_routePath;
    QString m_nextInstruction;
    QString m_guidanceDetail;
    QString m_etaText;
};
