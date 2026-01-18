import QtQuick 2.15
import QtWebEngine

Item {
    id: root
    anchors.fill: parent

    // Demo vehicle pose (later replaced by GPS / BBB data)
    property real lat: -27.4698
    property real lng: 153.0251
    property real bearing: 0

    WebEngineView {
        id: web
        anchors.fill: parent
        url: "qrc:/web/map/index.html"

        settings.javascriptEnabled: true
        settings.errorPageEnabled: true

        // REQUIRED so qrc:/ content can load https:// tiles/scripts
        settings.localContentCanAccessRemoteUrls: true

        profile: WebEngineProfile {
            offTheRecord: true
        }

        onLoadingChanged: function(req) {
            console.log(
                "[WEB] load status:",
                req.status,
                "url:", req.url,
                "error:", req.errorString
            )
        }
    }

    // Drive the map from QML (VM-safe, no WebGL required)
    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            bearing = (bearing + 2) % 360
            lat = lat + Math.sin(bearing * Math.PI / 180) * 0.00002
            lng = lng + Math.cos(bearing * Math.PI / 180) * 0.00002

            const js =
                "if (window.setVehiclePose) {" +
                "  window.setVehiclePose(" +
                lat + "," + lng + "," + bearing +
                ");" +
                "}";

            web.runJavaScript(js)
        }
    }
}
