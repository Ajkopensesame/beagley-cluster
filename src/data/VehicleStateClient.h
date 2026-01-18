#pragma once

#include <QObject>
#include <QWebSocket>
#include <QTimer>
#include <QDateTime>

class VehicleStateClient : public QObject
{
    Q_OBJECT

    // Link health
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool linkStale READ linkStale NOTIFY linkStaleChanged)
    Q_PROPERTY(int  rxAgeMs READ rxAgeMs NOTIFY rxAgeMsChanged)

    // Indicators (truth from BBB)
    Q_PROPERTY(bool leftIndicator READ leftIndicator NOTIFY leftIndicatorChanged)
    Q_PROPERTY(bool rightIndicator READ rightIndicator NOTIFY rightIndicatorChanged)
    Q_PROPERTY(bool highBeam READ highBeam NOTIFY highBeamChanged)

    // Warnings (truth from BBB)
    Q_PROPERTY(bool warnBrake READ warnBrake NOTIFY warnBrakeChanged)
    Q_PROPERTY(bool warnOil READ warnOil NOTIFY warnOilChanged)
    Q_PROPERTY(bool warnCharge READ warnCharge NOTIFY warnChargeChanged)
    Q_PROPERTY(bool warnDoor READ warnDoor NOTIFY warnDoorChanged)

    // BBB-declared stale (separate from linkStale)
    Q_PROPERTY(bool bbbStale READ bbbStale NOTIFY bbbStaleChanged)

public:
    explicit VehicleStateClient(QObject *parent = nullptr);

    bool connected() const { return m_connected; }
    bool linkStale() const { return m_linkStale; }
    int  rxAgeMs() const { return m_rxAgeMs; }

    bool leftIndicator() const { return m_leftIndicator; }
    bool rightIndicator() const { return m_rightIndicator; }
    bool highBeam() const { return m_highBeam; }

    bool warnBrake() const { return m_warnBrake; }
    bool warnOil() const { return m_warnOil; }
    bool warnCharge() const { return m_warnCharge; }
    bool warnDoor() const { return m_warnDoor; }

    bool bbbStale() const { return m_bbbStale; }

signals:
    void connectedChanged();
    void linkStaleChanged();
    void rxAgeMsChanged();

    void leftIndicatorChanged();
    void rightIndicatorChanged();
    void highBeamChanged();

    void warnBrakeChanged();
    void warnOilChanged();
    void warnChargeChanged();
    void warnDoorChanged();

    void bbbStaleChanged();

private slots:
    void onConnected();
    void onDisconnected();
    void onTextMessageReceived(const QString &msg);
    void checkStale();

private:
    void scheduleReconnect();
    void connectNow();

    void setConnected(bool v);
    void setLinkStale(bool v);
    void setRxAgeMs(int v);

    void setLeftIndicator(bool v);
    void setRightIndicator(bool v);
    void setHighBeam(bool v);

    void setWarnBrake(bool v);
    void setWarnOil(bool v);
    void setWarnCharge(bool v);
    void setWarnDoor(bool v);

    void setBbbStale(bool v);

private:
    QWebSocket m_ws;
    QTimer m_watchdog;
    QTimer m_reconnect;

    QString m_url;

    qint64 m_lastGoodRxMs = 0;
    int m_backoffMs = 250;

    bool m_connected = false;
    bool m_linkStale = true;
    int  m_rxAgeMs = 0;

    bool m_leftIndicator = false;
    bool m_rightIndicator = false;
    bool m_highBeam = false;

    bool m_warnBrake = false;
    bool m_warnOil = false;
    bool m_warnCharge = false;
    bool m_warnDoor = false;

    bool m_bbbStale = true;
};
