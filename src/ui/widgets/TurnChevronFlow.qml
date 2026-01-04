import QtQuick 2.15
import QtQuick.Shapes 1.15

Item {
    id: root

    implicitWidth: row.width
    width: implicitWidth
    height: 64

    // ===== API =====
    property bool active: false
    property string side: "left"          // "left" or "right"
    property int chevrons: 12

    // ===== Sequence timing =====
    property int sweepMs: 1000            // full sweep duration
    property int pauseMs: 180             // all-off pause between sweeps

    // ===== Geometry / style =====
    property real gap: 2
    property real thickness: 5.5
    property real thicknessOuter: 9.5      // max stroke at outside chevrons
    property real thicknessPulseBoost: 2.2 // extra stroke while active

    // Tail tuning (longer tail = smaller decay)
    property real tailDecay: 0.28        // smaller = longer tail (try 0.12–0.25)
    property real tailFloor: 0.01        // minimum faint tail alpha (0.0–0.08)
    property real chevronWidth: 16
    property real chevronHeight: 32
    property color onColor: "#00E676"

    // ===== Head + tail tuning =====
    property real pulseWidth: 1.15        // head width (in chevrons)
    property real pulseSharpness: 1.7

    property real tailLen: 6.0            // how many chevrons the tail spans
    property real tailMax: 0.65           // tail brightness behind the head
    property real tailFalloff: 0.7        // lower = longer/smoother tail

    // Optional: scaling can read as jitter. Keep subtle, or set both to 0/1.
    property real nestStep: 0.0           // set 0 for no nesting scale
    property real activeScale: 1.0        // set 1.0 for no pulse scale

    // ===== Animated sweep position =====
    // pos is continuous and driven by Qt animation (smooth)
    property real pos: 0.0
    property bool inSweep: false

    SequentialAnimation {
        id: sweepAnim
        running: root.active
        loops: Animation.Infinite

        ScriptAction { script: root.inSweep = true }

        NumberAnimation {
            target: root
            property: "pos"
            from: 0.0
            to: Math.max(0.0, root.chevrons - 1)
            duration: Math.max(1, root.sweepMs)
            easing.type: Easing.Linear
        }

        ScriptAction { script: root.inSweep = false }
        PauseAnimation { duration: Math.max(0, root.pauseMs) }

        ScriptAction { script: root.pos = 0.0 }
    }

    onActiveChanged: {
        if (!active) {
            inSweep = false
            pos = 0.0
        }
    }

    // Convert visual index to "inside -> outside" rank
    function outwardRank(visualIndex) {
        if (root.side === "left") return (root.chevrons - 1 - visualIndex) // inside is rightmost
        return visualIndex                                                 // inside is leftmost
    }

    // Tail model: bright head, exponential fade behind, OFF ahead

    // Tail model: bright head, exponential fade behind, OFF ahead
    // Goal: when head is at the last chevron, the first can still be barely visible.

    // Tail model: bright head, exponential fade behind, OFF ahead
    // Goal: when head is at the last chevron, the first can still be barely visible.
    function alphaFor(i) {
        if (!root.active || !root.inSweep) return 0.0

        var li = root.outwardRank(i)   // logical index (0=inside)
        var delta = root.pos - li      // >0 => behind the head, <0 => ahead

        // Ahead of the head: off (keeps directionality, prevents forward glow)
        if (delta < 0) return 0.0

        // Head shaping (keeps the head crisp)
        // delta=0 => 1, delta grows => decays smoothly
        var headFactor = Math.exp(-Math.abs(delta) * 1.1)

        // Tail behind the head, with a faint floor so the start stays barely visible
        var tail = Math.max(root.tailFloor, Math.exp(-delta * root.tailDecay))

        var a = tail * headFactor
        return Math.max(0.0, Math.min(1.0, a))
    }
    Item {
        id: row
        anchors.centerIn: parent
        width: root.chevrons * root.chevronWidth + (root.chevrons - 1) * root.gap
        height: root.chevronHeight

        Repeater {
            model: root.chevrons

            Item {
                width: root.chevronWidth
                height: root.chevronHeight
                x: index * (root.chevronWidth + root.gap)
                y: 0

                readonly property real a: root.alphaFor(index)
                readonly property int r: root.outwardRank(index)
                readonly property real baseScale: 1.0 + (r * root.nestStep)
                // scale removed (Shapes + scaling = shimmer)
                scale: 1
                Shape {
                    preferredRendererType: Shape.CurveRenderer
                    anchors.fill: parent
                    antialiasing: true

                    ShapePath {
                        strokeWidth: (function() {
                            var n = Math.max(2, root.chevrons);
                            var r = root.outwardRank(index);
                            var t = r / (n - 1); // 0..1 (inside->outside)
                            var base = root.thickness + t * (root.thicknessOuter - root.thickness);
                            return base + (a * root.thicknessPulseBoost);
                        })()
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        fillColor: "transparent"
                        strokeColor: Qt.rgba(root.onColor.r, root.onColor.g, root.onColor.b, a)

                        startX: (root.side === "left") ? width : 0
                        startY: 0
                        PathLine { x: width / 2; y: height / 2 }
                        PathLine { x: (root.side === "left") ? width : 0; y: height }
                    }
                }
            }
        }
    }
}
