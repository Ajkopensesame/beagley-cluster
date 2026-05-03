import QtQuick 2.15
import "telltales" as Telltales

Item {
    id: root

    width: 112
    height: 112

    property string icon: ""
    property string warningKey: ""
    property color color: "#FF3B3B"
    property color accentColor: color
    property color cutoutColor: "#050A12"
    property real strokeWidth: Math.max(5, Math.min(width, height) * 0.078)

    readonly property string resolvedIcon: String(warningKey.length > 0 ? warningKey : icon).toLowerCase()

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.resolvedIcon) {
            case "brake": return brakeComp
            case "charge": return batteryComp
            case "battery": return batteryComp
            case "check": return checkEngineComp
            case "checkengine": return checkEngineComp
            case "fuel": return fuelComp
            case "oil": return oilComp
            case "door": return doorComp
            case "at": return atTempComp
            case "highbeam": return highBeamComp
            case "high_beam": return highBeamComp
            default: return warningComp
            }
        }
    }

    Component {
        id: brakeComp
        Telltales.BrakeTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: batteryComp
        Telltales.BatteryTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: checkEngineComp
        Telltales.CheckEngineTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: fuelComp
        Telltales.FuelTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: oilComp
        Telltales.OilTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: doorComp
        Telltales.DoorTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: atTempComp
        Telltales.AtTempTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: highBeamComp
        Telltales.HighBeamTelltale {
            width: root.width
            height: root.height
            color: root.color
            accentColor: root.accentColor
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }

    Component {
        id: warningComp
        Telltales.WarningTelltale {
            width: root.width
            height: root.height
            color: root.color
            cutoutColor: root.cutoutColor
            strokeWidth: root.strokeWidth
        }
    }
}
