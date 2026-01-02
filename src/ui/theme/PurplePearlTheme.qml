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
        const s = Math.max(0, Number(speedKph) || 0);

        // Smooth transitions:
        // 0..115: pearlLow -> pearlHigh
        // 115..130: pearlHigh -> danger
        const t1 = clamp(s / 115.0, 0, 1);
        const t2 = clamp((s - 115.0) / 15.0, 0, 1);

        function lerp(a, b, t) { return a + (b - a) * t; }
        function mix(c1, c2, t) {
            return Qt.rgba(
                lerp(c1.r, c2.r, t),
                lerp(c1.g, c2.g, t),
                lerp(c1.b, c2.b, t),
                lerp(c1.a, c2.a, t)
            );
        }

        const base = mix(pearlLow, pearlHigh, t1);
        return mix(base, danger, t2);
    }

    // NOTE: third arg maxRpm is optional; TachGauge should pass it for best results.
    function rpmColor(rpm, redlineStart, maxRpm) {
        const r = Math.max(0, Number(rpm) || 0);
        const red = (redlineStart !== undefined) ? Number(redlineStart) : 5000;
        const max = (maxRpm !== undefined) ? Number(maxRpm) : 6500;

        // Smooth transitions:
        // 0..redline: pearlLow -> pearlHigh
        // redline..max: pearlHigh -> danger
        const t1 = clamp(r / Math.max(1, red), 0, 1);
        const t2 = clamp((r - red) / Math.max(1, (max - red)), 0, 1);

        function lerp(a, b, t) { return a + (b - a) * t; }
        function mix(c1, c2, t) {
            return Qt.rgba(
                lerp(c1.r, c2.r, t),
                lerp(c1.g, c2.g, t),
                lerp(c1.b, c2.b, t),
                lerp(c1.a, c2.a, t)
            );
        }

        const base = mix(pearlLow, pearlHigh, t1);
        return mix(base, danger, t2);
    }

    function tickAlpha(isMajor) {
        if (isNight) return isMajor ? 0.55 : 0.32;
        return isMajor ? 0.70 : 0.45;
    }
}
