import QtQuick 2.15
import QtQuick.Controls 2.15
import QtWebEngine

Item {
    id: root
    anchors.fill: parent

    // Optional: toggle overlay easily
    property bool debugOverlay: true

    // This should already be set by your MapCenter wrapper before creating MapCenterWeb
    property url mapUrl: "qrc:/src/ui/web/map/index.html"
    property string statusText: "init"

    Rectangle {
        id: overlay
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: debugOverlay ? 54 : 0
        visible: debugOverlay
        opacity: 0.85

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            Text {
                id: line1
                text: "[Map] url=" + web.url + "  loading=" + web.loading
                font.pixelSize: 14
                color: "white"
                elide: Text.ElideRight
            }
            Text {
                id: line2
                text: statusText
                font.pixelSize: 14
                color: "white"
                elide: Text.ElideRight
            }
        }
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        url: root.mapUrl

        settings.javascriptEnabled: true
        settings.localContentCanAccessRemoteUrls: true
        settings.localContentCanAccessFileUrls: true
        settings.errorPageEnabled: true
        settings.fullScreenSupportEnabled: false

        // For embedded stability: avoid persistent cache/cookies unless you explicitly want them.
        profile: WebEngineProfile {
            offTheRecord: true
        }

        onLoadingChanged: function(loadRequest) {
            // loadRequest.status: LoadStartedStatus / LoadStoppedStatus / LoadSucceededStatus / LoadFailedStatus
            statusText = "[Map] status=" + loadRequest.status
                       + " err=" + loadRequest.errorString
                       + " code=" + loadRequest.errorCode;

            console.log(statusText);

            if (loadRequest.url && loadRequest.url.toString().length > 0) {
                console.log("[Map] loading url:", loadRequest.url.toString());
            }

            // Helpful when it stalls on "MapLibre loading..."
            if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                console.log("[Map] Load started");
            } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                console.log("[Map] Load succeeded");
            } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                console.log("[Map] Load FAILED:", loadRequest.errorString, "code=", loadRequest.errorCode);
            }
        }

        // ✅ Qt 6: correct console hook
        onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceId) {
            // level is a number; keep it numeric so it never breaks across Qt versions.
            console.log("[MapConsole] level=" + level
                        + " line=" + lineNumber
                        + " src=" + sourceId
                        + " msg=" + message);
        }

        onNavigationRequested: function(request) {
            console.log("[MapNav] type=" + request.navigationType + " url=" + request.url);
            request.action = WebEngineNavigationRequest.AcceptRequest;
        }

        onRenderProcessTerminated: function(terminationStatus, exitCode) {
            console.log("[Map] RENDER PROCESS TERMINATED status=" + terminationStatus + " exitCode=" + exitCode);
            statusText = "[Map] RENDER PROCESS TERMINATED status=" + terminationStatus + " exitCode=" + exitCode;
        }
    }
}
