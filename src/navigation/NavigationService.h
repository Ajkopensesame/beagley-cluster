#pragma once

#include <QDateTime>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <limits>

#include "../data/VehicleStateClient.h"
#include "OpenNavigationProvider.h"

class WiFiSetupService;

class NavigationService : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString state READ state NOTIFY navigationStateChanged)
    Q_PROPERTY(QString followMode READ followMode NOTIFY navigationStateChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
    Q_PROPERTY(QVariantList recents READ recents NOTIFY recentsChanged)
    Q_PROPERTY(QVariantMap activeRoute READ activeRoute NOTIFY routeChanged)
    Q_PROPERTY(QVariantMap nextManeuver READ nextManeuver NOTIFY guidanceChanged)
    Q_PROPERTY(QVariantMap followingManeuver READ followingManeuver NOTIFY guidanceChanged)
    Q_PROPERTY(QVariantMap banner READ banner NOTIFY guidanceChanged)
    Q_PROPERTY(QString eta READ eta NOTIFY guidanceChanged)
    Q_PROPERTY(double remainingDistanceMeters READ remainingDistanceMeters NOTIFY guidanceChanged)
    Q_PROPERTY(double remainingDurationSeconds READ remainingDurationSeconds NOTIFY guidanceChanged)
    Q_PROPERTY(double trafficDelaySeconds READ trafficDelaySeconds NOTIFY guidanceChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)
    Q_PROPERTY(QString networkStatus READ networkStatus NOTIFY networkStatusChanged)
    Q_PROPERTY(QString providerStatus READ providerStatus NOTIFY networkStatusChanged)
    Q_PROPERTY(bool bbbLinkOk READ bbbLinkOk NOTIFY networkStatusChanged)
    Q_PROPERTY(bool internetOk READ internetOk NOTIFY networkStatusChanged)
    Q_PROPERTY(QString ttsStatus READ ttsStatus NOTIFY ttsStatusChanged)
    Q_PROPERTY(QVariantMap mapPayload READ mapPayload NOTIFY mapPayloadChanged)
    Q_PROPERTY(QVariantMap mapVehiclePose READ mapVehiclePose NOTIFY mapVehiclePoseChanged)
    Q_PROPERTY(QVariantMap mapCameraHints READ mapCameraHints NOTIFY mapCameraHintsChanged)
    Q_PROPERTY(QVariantMap mapRouteOverlay READ mapRouteOverlay NOTIFY mapRouteOverlayChanged)
    Q_PROPERTY(QVariantMap mapGuidanceBanner READ mapGuidanceBanner NOTIFY mapGuidanceBannerChanged)
    Q_PROPERTY(QVariantMap mapConnectivity READ mapConnectivity NOTIFY mapConnectivityChanged)

public:
    explicit NavigationService(VehicleStateClient *vehicleState, WiFiSetupService *wifiSetup = nullptr, QObject *parent = nullptr);

    QString state() const { return m_state; }
    QString followMode() const { return m_followMode; }
    QVariantList searchResults() const { return m_searchResults; }
    QVariantList recents() const { return m_recents; }
    QVariantMap activeRoute() const { return m_activeRoute; }
    QVariantMap nextManeuver() const { return m_nextManeuver; }
    QVariantMap followingManeuver() const { return m_followingManeuver; }
    QVariantMap banner() const { return m_banner; }
    QString eta() const { return m_eta; }
    double remainingDistanceMeters() const { return m_remainingDistanceMeters; }
    double remainingDurationSeconds() const { return m_remainingDurationSeconds; }
    double trafficDelaySeconds() const { return m_trafficDelaySeconds; }
    bool muted() const { return m_muted; }
    QString networkStatus() const { return m_networkStatus; }
    QString providerStatus() const { return m_providerStatus; }
    bool bbbLinkOk() const { return m_bbbLinkOk; }
    bool internetOk() const { return m_internetOk; }
    QString ttsStatus() const { return m_ttsStatus; }
    QVariantMap mapPayload() const { return m_mapPayload; }
    QVariantMap mapVehiclePose() const { return m_mapVehiclePose; }
    QVariantMap mapCameraHints() const { return m_mapCameraHints; }
    QVariantMap mapRouteOverlay() const { return m_mapRouteOverlay; }
    QVariantMap mapGuidanceBanner() const { return m_mapGuidanceBanner; }
    QVariantMap mapConnectivity() const { return m_mapConnectivity; }

    Q_INVOKABLE void search(const QString &query);
    Q_INVOKABLE void selectSearchResult(const QString &id);
    Q_INVOKABLE void setDestination(double lat, double lng, const QString &label);
    Q_INVOKABLE void clearRoute();
    Q_INVOKABLE void setFollowEnabled(bool enabled);
    Q_INVOKABLE void setMuted(bool muted);
    Q_INVOKABLE void recenter();

signals:
    void navigationStateChanged();
    void searchResultsChanged();
    void recentsChanged();
    void routeChanged();
    void guidanceChanged();
    void mutedChanged();
    void networkStatusChanged();
    void ttsStatusChanged();
    void mapPayloadChanged();
    void mapVehiclePoseChanged();
    void mapCameraHintsChanged();
    void mapRouteOverlayChanged();
    void mapGuidanceBannerChanged();
    void mapConnectivityChanged();
    void voicePromptReady(const QString &text, const QString &promptId);
    void routeRecalculated();
    void rerouteStarted();
    void rerouteFailed();

private:
    struct RouteProfilePoint {
        double lat = 0.0;
        double lng = 0.0;
        double meters = 0.0;
    };

    struct SnapResult {
        double progressMeters = 0.0;
        double lateralMeters = 0.0;
    };

    struct Pose {
        double lat = std::numeric_limits<double>::quiet_NaN();
        double lng = std::numeric_limits<double>::quiet_NaN();
        double bearing = 0.0;
        double speedKph = 0.0;
    };

    void setState(const QString &state);
    void setFollowMode(const QString &followMode);
    void setSearchResults(const QVariantList &results);
    void setRecents(const QVariantList &recents);
    void setActiveRoute(const QVariantMap &route);
    void setNextManeuver(const QVariantMap &maneuver);
    void setFollowingManeuver(const QVariantMap &maneuver);
    void setBanner(const QVariantMap &banner);
    void setEta(const QString &eta);
    void setRemainingDistanceMeters(double meters);
    void setRemainingDurationSeconds(double seconds);
    void setTrafficDelaySeconds(double seconds);
    void setNetworkStatus(const QString &status);
    void setProviderStatus(const QString &status);
    void setBbbLinkOk(bool ok);
    void setInternetOk(bool ok);
    void setTtsStatus(const QString &status);
    void setMapPayload(const QVariantMap &payload);
    void setMapVehiclePose(const QVariantMap &payload);
    void setMapCameraHints(const QVariantMap &payload);
    void setMapRouteOverlay(const QVariantMap &payload);
    void setMapGuidanceBanner(const QVariantMap &payload);
    void setMapConnectivity(const QVariantMap &payload);

    void updateNavigationState();
    void updateConnectivityStatus();
    void requestRoute(bool reroute);
    void beginRouteRequest(bool reroute);
    void updateFromVehicle();
    void updateGuidance();
    void updateMapPayload();
    void runFallbackSearch(const QString &query, const Pose &pose);
    void maybeTriggerPrompts();
    void maybeRefreshRoute();
    void persistCache() const;
    void loadCache();
    void loadRecents();
    void saveRecents() const;
    QString cacheDirectory() const;
    Pose livePose() const;
    Pose currentPose() const;
    bool hotspotPathReady() const;
    bool providersAllowed() const;
    bool gpsReady() const;
    bool gpsReliableHeading() const;
    QVariantMap searchResultAt(const QString &id) const;
    QList<RouteProfilePoint> buildRouteProfile(const QVariantList &geometry) const;
    double metersBetween(double aLat, double aLng, double bLat, double bLng) const;
    double headingBetween(double aLat, double aLng, double bLat, double bLng) const;
    SnapResult snapToRoute(double lat, double lng) const;
    QVariantMap maneuverToVariant(const RouteManeuverData &maneuver, double remainingAfterMeters) const;
    QVariantMap destinationToVariant(double lat, double lng, const QString &label) const;
    QString classifyManeuver(const RouteManeuverData &maneuver) const;
    QString buildAdvancePrompt(const RouteManeuverData &maneuver, double distanceMeters) const;
    QString buildFinalPrompt(const RouteManeuverData &maneuver) const;
    double advancePromptDistance(double speedKph) const;
    double finalPromptDistance(double speedKph) const;
    double advancePromptSeconds(double speedKph) const;
    double finalPromptSeconds(double speedKph) const;
    QVariantMap buildCameraHints() const;
    void speakPrompt(const QString &text, const QString &promptId, bool highPriority = false);
    void ensureTtsReady();
    QString promptCachePath(const QString &text) const;
    QString playerExecutable() const;

    QPointer<VehicleStateClient> m_vehicleState;
    QPointer<WiFiSetupService> m_wifiSetup;
    OpenNavigationProvider m_provider;
    QNetworkAccessManager m_network;
    QTimer m_routeRefreshTimer;
    QTimer m_overviewTimer;
    QTimer m_rerouteVoiceTimer;

    QString m_state = QStringLiteral("idle");
    QString m_followMode = QStringLiteral("auto");
    QVariantList m_searchResults;
    QVariantList m_recents;
    QVariantMap m_activeRoute;
    QVariantMap m_nextManeuver;
    QVariantMap m_followingManeuver;
    QVariantMap m_banner;
    QString m_eta;
    double m_remainingDistanceMeters = 0.0;
    double m_remainingDurationSeconds = 0.0;
    double m_trafficDelaySeconds = 0.0;
    bool m_muted = false;
    QString m_networkStatus = QStringLiteral("connecting_hotspot");
    QString m_providerStatus = QStringLiteral("offline");
    bool m_bbbLinkOk = false;
    bool m_internetOk = false;
    QString m_ttsStatus = QStringLiteral("checking");
    QVariantMap m_mapPayload;
    QVariantMap m_mapVehiclePose;
    QVariantMap m_mapCameraHints;
    QVariantMap m_mapRouteOverlay;
    QVariantMap m_mapGuidanceBanner;
    QVariantMap m_mapConnectivity;

    QVariantMap m_destination;
    QList<RouteManeuverData> m_routeManeuvers;
    QList<RouteProfilePoint> m_routeProfile;
    QString m_lastSearchQuery;
    bool m_followEnabled = true;
    bool m_overviewActive = false;
    bool m_rerouting = false;
    bool m_routeRefreshPending = false;
    bool m_emitLegacyMapPayload = true;
    int m_offRouteHits = 0;
    qint64 m_regressionSinceMs = 0;
    double m_lastProgressMeters = 0.0;
    double m_currentProgressMeters = 0.0;
    double m_currentLateralMeters = 0.0;
    qint64 m_lastRouteRequestMs = 0;
    qint64 m_lastGpsBlockedLogMs = 0;
    QString m_lastAdvancePromptId;
    QString m_lastFinalPromptId;
    qint64 m_lastPromptMs = 0;
    int m_currentManeuverIndex = -1;
    Pose m_lastValidPose;
    bool m_hasLastValidPose = false;
    bool m_lastGpsReadyState = false;

    QString m_ttsEngine;
    QString m_ttsVoice;
    QString m_playerCommand;
    QString m_navCacheDir;
};
