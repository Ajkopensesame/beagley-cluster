import QtQuick 2.15
import QtQuick.Controls 2.15
import QtWebEngine

Item {
    id: root
    anchors.fill: parent

    property bool loaded: false
    property string err: ""

    Rectangle {
        anchors.fill: parent
        color: "black"
        radius: 18
        clip: true

        WebEngineView {
            id: web
            anchors.fill: parent

            // NOTE: We'll switch this to a simpler qrc path in Step 2.
            url: "qrc:/web/src/ui/web/map/index.html"

            settings.javascriptEnabled: true
            settings.localStorageEnabled: true
            settings.errorPageEnabled: false
            settings.fullScreenSupportEnabled: false
            settings.localContentCanAccessRemoteUrls: true

            onLoadingChanged: function(loadRequest) {
                // Avoid WebEngineLoadRequest enum (not always in scope on Qt 6/macOS).
                // Empirically stable numeric values:
                // 0 = LoadStarted, 1 = LoadStopped, 2 = LoadSucceeded, 3 = LoadFailed
                if (loadRequest.status === 0) {
                    root.loaded = false
                    root.err = ""
                } else if (loadRequest.status === 2) {
                    root.loaded = true
                    root.err = ""
                } else if (loadRequest.status === 3) {
                    root.loaded = false
                    root.err = loadRequest.errorString || "Load failed"
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: visible ? 52 : 0
            color: "#AA000000"
            visible: (!root.loaded) || (root.err.length > 0)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                color: "white"
                font.pixelSize: 14
                elide: Text.ElideRight
                text: root.err.length > 0 ? ("Map: " + root.err) : "Map: loading…"
            }
        }
    }
}
