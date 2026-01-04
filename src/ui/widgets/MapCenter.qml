import QtQuick 2.15
import QtQuick.Controls 2.15
import QtWebEngine

Item {
    id: root
    anchors.fill: parent

    property bool loaded: false
    property string err: ""
    property string webglResult: ""
    property string injectResult: ""

    Rectangle {
        anchors.fill: parent
        color: "black"
        radius: 18
        clip: true

        WebEngineView {
            id: web
            anchors.fill: parent

            // Must match the resource path actually compiled by qt_add_resources(...)
            url: "qrc:/web/src/ui/web/map/index.html"

            settings.javascriptEnabled: true
            settings.localStorageEnabled: true
            settings.errorPageEnabled: false
            settings.fullScreenSupportEnabled: false

            // ---- Permissions (older API) ----
            onFeaturePermissionRequested: function(securityOrigin, feature) {
                var f = String(feature).toLowerCase();
                if (f.indexOf("geo") !== -1) {
                    web.grantFeaturePermission(securityOrigin, feature, true);
                } else {
                    web.grantFeaturePermission(securityOrigin, feature, false);
                }
            }

            // ---- Permissions (newer API on some Qt 6 builds) ----
            onPermissionRequested: function(permission) {
                var t = String(permission.permissionType).toLowerCase();
                if (t.indexOf("geolocation") !== -1 || t.indexOf("location") !== -1) {
                    permission.grant();
                } else {
                    permission.deny();
                }
            }

            onLoadingChanged: function(loadRequest) {
                // Numeric statuses are most portable across QtWebEngine QML builds:
                // 0 = LoadStarted, 1 = LoadStopped, 2 = LoadSucceeded, 3 = LoadFailed
                if (loadRequest.status === 0) {
                    root.loaded = false;
                    root.err = "";
                } else if (loadRequest.status === 2) {
                    root.loaded = true;
                    // Inject a location from QML (no browser geolocation needed)
                    injectTimer.restart()
                    root.err = "";
                } else if (loadRequest.status === 3) {
                    root.loaded = false;
                    root.err = loadRequest.errorString || "Load failed";
                }
            }
        }

                Timer {
            id: clearBannerTimer
            interval: 5000
            repeat: false
            onTriggered: {
                // Only clear if we're showing the success banner (don't wipe real errors)
                if (root.err === "Injected ✅") root.err = ""
            }
        }

Timer {
            id: injectTimer
            interval: 120
            repeat: false
            onTriggered: {
                web.runJavaScript(
                    "try { " +
                    "  if (typeof window.setVehicleLocation !== 'function') throw 'setVehicleLocation missing'; " +
                    "  window.setVehicleLocation(-27.4698,153.0251,'Brisbane (QML injected)'); " +
                    "  'ok'; " +
                    "} catch(e) { 'err:' + e; }",
                    function(result) {
                        // Probe WebGL (MapLibre needs it)
                        web.runJavaScript(
                            "try{var c=document.createElement('canvas');var gl=c.getContext('webgl')||c.getContext('experimental-webgl');gl?'webgl:ok':'webgl:fail';}catch(e){'webgl:err:'+e;}",
                            function(r2){ root.webglResult = (r2 ? String(r2) : 'webgl:unknown'); }
                        );

                        root.injectResult = String(result)
                        if (root.injectResult.indexOf("err:") === 0) {
                            root.err = root.injectResult
                        } else {
                            root.err = ""   // clear error if OK
                        }
                    }
                )
            }
        }

        // Top overlay status bar (loading / error)
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: visible ? 52 : 0
            color: "#AA000000"
            visible: true

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                color: "white"
                font.pixelSize: 14
                elide: Text.ElideRight
                text: root.err.length > 0
    ? ("Map: " + root.err)
    : (root.loaded
        ? ("Map: loaded | inject=" + (root.injectResult.length ? root.injectResult : "…") + " | webgl=" + (root.webglResult.length ? root.webglResult : "…"))
        : "Map: loading…")
            }
        }
    }
}
