import QtQuick 2.15

QtObject {
    id: theme

    // Day/Night
    property bool isNight: true
    property bool followSystem: true

    function updateFromSystem(palette) {
        if (!followSystem || !palette) return;
        const w = palette.window;
        const avg = (w.r + w.g + w.b) / 3.0;
        theme.isNight = (avg < 0.5);
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

    // Core semantic colors
    readonly property color bg:    isNight ? "#000000" : "#F5F3FF"
    readonly property color panel: isNight ? "#0B0714" : "#FFFFFF"
    readonly property color text:  isNight ? "#E6FFFFFF" : "#1A0F2E"

    readonly property color pearlLow:  isNight ? "#C7B7FF" : "#7E57C2"
    readonly property color pearlHigh: isNight ? "#5E35B1" : "#311B92"
    readonly property color danger:    isNight ? "#FF3B3B" : "#C62828"

    function speedColor(speedKph) {
        const s = Math.round(speedKph);
        if (s <= 50)  return pearlLow;
        if (s <= 115) return pearlHigh;
        return danger;
    }

    function rpmColor(rpm, redlineStart) {
        const v = Math.round(rpm);
        const red = (redlineStart !== undefined) ? redlineStart : 5000;
        if (v < red) return pearlHigh;
        return danger;
    }

    function tickAlpha(isMajor) {
        if (isNight) return isMajor ? 0.55 : 0.32;
        return isMajor ? 0.70 : 0.45;
    }
}
