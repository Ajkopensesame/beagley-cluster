import QtQuick 2.15

QtObject {
    id: root

    // Final mapping:
    // red: brake, charge, a/t, door
    // yellow: check engine, fuel low
    readonly property color warnRed:    "#FF3B3B"
    readonly property color warnYellow: "#FFC107"

    function haloColor(key, fallbackColor) {
        var k = (key === undefined || key === null) ? "" : String(key).toLowerCase()

        // tolerate label-style keys too ("A/T", "CHECK", etc.)
        if (k.indexOf("check") !== -1) return warnYellow
        if (k.indexOf("fuel")  !== -1) return warnYellow

        if (k.indexOf("brake") !== -1) return warnRed
        if (k.indexOf("charge")!== -1) return warnRed
        if (k === "at" || k.indexOf("a/t") !== -1) return warnRed
        if (k.indexOf("door") !== -1) return warnRed

        return fallbackColor
    }
}
