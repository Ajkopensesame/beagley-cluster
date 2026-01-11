import QtQuick 2.15
import "icons"

Item {
    id: root
    width: 96
    height: 96

    // canonical keys: "brake"|"charge"|"check"|"fuel"|"door"|"at"|"oil"
    property string warningKey: ""
    property color color: "red"

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.warningKey) {
            case "brake":  return brakeComp
            case "charge": return chargeComp
            case "check":  return checkComp
            case "fuel":   return fuelComp
            case "door":   return doorComp
            case "at":     return atComp
            case "oil":    return oilComp
            default:       return null
            }
        }
    }

    Component { id: brakeComp;  BrakeIcon  { color: root.color } }
    Component { id: chargeComp; ChargeIcon { color: root.color } }
    Component { id: checkComp;  CheckIcon  { color: root.color } }
    Component { id: fuelComp;   FuelIcon   { color: root.color } }
    Component { id: oilComp;    OilIcon    { color: root.color } }
    Component { id: doorComp;   DoorIcon   { color: root.color } }
    Component { id: atComp;     ATIcon     { color: root.color } }
}
