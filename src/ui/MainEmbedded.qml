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
    readonly property color accent: "#4CD9FF"
    readonly property color accentWarm: "#FFB03B"
    readonly property color panelFill: "#081220"
    readonly property color panelStroke: "#14324A"
    readonly property color warningFill: cluster.activeWarnings > 0 ? "#5B1010" : "#10261A"
    readonly property color warningStroke: cluster.activeWarnings > 0 ? "#C93A3A" : "#1F7A45"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#081321" }
            GradientStop { position: 0.55; color: "#040914" }
            GradientStop { position: 1.0; color: "#010205" }
        }
    }

    EmbeddedStatusRibbon {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 78
        cluster: root.cluster
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
            cluster: root.cluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            needleColor: root.accentWarm
        }

        EmbeddedMapPod {
            id: mapPod
            width: parent.width - speedPod.width - tachPod.width - parent.spacing * 2
            cluster: root.cluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            metrics: performanceMetrics
        }

        EmbeddedTachPod {
            id: tachPod
            width: 452
            cluster: root.cluster
            panelFill: root.panelFill
            panelStroke: root.panelStroke
            needleColor: root.accent
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
    }
}
