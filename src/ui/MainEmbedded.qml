import QtQuick 2.15
import QtQuick.Window 2.15

import BeagleY 1.0

Window {
    id: root

    width: 1920
    height: 720
    minimumWidth: 1920
    minimumHeight: 720
    maximumWidth: 1920
    maximumHeight: 720
    visible: true
    color: "#030814"
    visibility: Window.Windowed

    readonly property var cluster: clusterRenderModel
    readonly property bool stressScene: (typeof BEAGLEY_STRESS_SCENE !== "undefined" && BEAGLEY_STRESS_SCENE) ? true : false
    property real stressPhase: 0.0
    readonly property string uiFontFamily: embeddedUiFont.name.length > 0 ? embeddedUiFont.name : "sans-serif"
    readonly property color accent: "#4CD9FF"
    readonly property color accentWarm: "#FFB03B"
    readonly property color panelFill: "#081220"
    readonly property color panelStroke: "#14324A"
    readonly property color warningFill: cluster.activeWarnings > 0 ? "#5B1010" : "#10261A"
    readonly property color warningStroke: cluster.activeWarnings > 0 ? "#C93A3A" : "#1F7A45"
    readonly property var gaugeCluster: ({
        speedKph: root.stressScene ? (58 + 42 * Math.sin(root.stressPhase * 0.9)) : (root.cluster ? root.cluster.speedKph : 0),
        rpm: root.stressScene ? (2400 + 1650 * (0.5 + 0.5 * Math.sin(root.stressPhase * 1.15 + 0.4))) : (root.cluster ? root.cluster.rpm : 0),
        fuelPct: root.stressScene ? (48 + 14 * Math.sin(root.stressPhase * 0.12)) : (root.cluster ? root.cluster.fuelPct : 0),
        coolantC: root.stressScene ? (81 + 7 * Math.sin(root.stressPhase * 0.18 + 1.6)) : (root.cluster ? root.cluster.coolantC : 0),
        activeWarnings: root.cluster ? root.cluster.activeWarnings : 0,
        warningSummary: root.cluster ? root.cluster.warningSummary : "LINK DOWN",
        leftIndicator: root.stressScene ? Math.sin(root.stressPhase * 1.45) > 0.72 : !!(root.cluster && root.cluster.leftIndicator),
        rightIndicator: root.stressScene ? Math.sin(root.stressPhase * 1.20 + 2.8) > 0.72 : !!(root.cluster && root.cluster.rightIndicator)
    })

    Timer {
        interval: 50
        running: root.stressScene
        repeat: true
        onTriggered: root.stressPhase += interval / 1000.0
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#081321" }
            GradientStop { position: 0.55; color: "#040914" }
            GradientStop { position: 1.0; color: "#010205" }
        }
    }

    FontLoader {
        id: embeddedUiFont
        source: "qrc:/assets/fonts/Oxanium-Regular.ttf"
    }

    EmbeddedStatusRibbon {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 78
        cluster: root.cluster
        fontFamily: root.uiFontFamily
    }

    Row {
        anchors.top: parent.top
        anchors.topMargin: 100
        anchors.bottom: bottomRail.top
        anchors.bottomMargin: 18
        anchors.left: parent.left
        anchors.leftMargin: 26
        anchors.right: parent.right
        anchors.rightMargin: 26
        spacing: 22

        EmbeddedSpeedPod {
            id: speedPod
            width: 452
            cluster: root.gaugeCluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            needleColor: root.accentWarm
            fontFamily: root.uiFontFamily
        }

        EmbeddedMapPod {
            id: mapPod
            width: parent.width - speedPod.width - tachPod.width - parent.spacing * 2
            cluster: root.cluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            metrics: performanceMetrics
            fontFamily: root.uiFontFamily
        }

        EmbeddedTachPod {
            id: tachPod
            width: 452
            cluster: root.gaugeCluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            needleColor: root.accent
            fontFamily: root.uiFontFamily
        }
    }

    EmbeddedBottomRail {
        id: bottomRail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 92
        cluster: root.cluster
        fillColor: root.warningFill
        strokeColor: root.warningStroke
        fontFamily: root.uiFontFamily
    }
}
