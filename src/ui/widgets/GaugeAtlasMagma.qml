import QtQuick 2.15
import BeagleY 1.0

// Concept-baked molten band without QtGraphicalEffects (not on appliance).
// Atlas Image + ShaderEffect progress wedge (GPU). Drive-safe: no Canvas.
Item {
    id: root

    property real progress: 0.0
    property real startAngleDeg: 225
    property real sweepAngleDeg: 210
    property real radiusFactor: 0.405
    property real strokeWidthFactor: 0.053
    property bool richMode: false
    property real lavaPhase: 0.0
    property url annulusSource: Qt.resolvedUrl("../assets/skin-v2/lava-annulus.png")

    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))
    readonly property real strokePx: Math.max(10, Math.min(width, height) * strokeWidthFactor)
    readonly property bool showBand: clampedProgress > 0.002
    readonly property real side: Math.min(width, height)

    // Soft under-bloom
    GaugeArcItem {
        anchors.fill: parent
        z: 0
        visible: root.showBand
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: root.clampedProgress
        radiusFactor: root.radiusFactor
        strokeWidth: root.strokePx * (root.richMode ? 1.35 : 1.15)
        color: Qt.rgba(1.0, 0.42, 0.08, root.richMode ? 0.42 : 0.30)
        segments: root.richMode ? 40 : 28
        roundedCaps: true
    }

    GaugeArcItem {
        anchors.fill: parent
        z: 0
        visible: root.showBand && root.clampedProgress > 0.04
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: 0.0
        endProgress: Math.min(root.clampedProgress, Math.max(0.06, root.clampedProgress * 0.42))
        radiusFactor: root.radiusFactor + 0.006
        strokeWidth: root.strokePx * 0.85
        color: Qt.rgba(0.72, 0.08, 0.22, root.richMode ? 0.28 : 0.18)
        segments: 24
        roundedCaps: true
    }

    Image {
        id: atlasImage
        anchors.centerIn: parent
        width: root.side
        height: root.side
        source: root.annulusSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: false
    }

    ShaderEffectSource {
        id: atlasSrc
        sourceItem: atlasImage
        hideSource: true
        live: false
        textureSize: Qt.size(640, 640)
        smooth: true
    }

    Connections {
        target: atlasImage
        onStatusChanged: {
            if (atlasImage.status === Image.Ready)
                atlasSrc.scheduleUpdate()
        }
    }

    ShaderEffect {
        id: atlasFx
        anchors.centerIn: parent
        width: root.side
        height: root.side
        z: 2
        visible: root.showBand && atlasImage.status === Image.Ready
        blending: true
        supportsAtlasTextures: false

        property variant source: atlasSrc
        property real progress: root.clampedProgress
        property real startAngleDeg: root.startAngleDeg
        property real sweepAngleDeg: root.sweepAngleDeg
        property real radiusFactor: root.radiusFactor
        // Half-band in UV units (radius is diameter*factor / side = factor when square)
        property real bandHalf: (root.strokePx * 0.58) / Math.max(1.0, root.side)
        property real soft: root.richMode ? 0.0045 : 0.0035

        fragmentShader: "
            varying highp vec2 qt_TexCoord0;
            uniform sampler2D source;
            uniform lowp float qt_Opacity;
            uniform highp float progress;
            uniform highp float startAngleDeg;
            uniform highp float sweepAngleDeg;
            uniform highp float radiusFactor;
            uniform highp float bandHalf;
            uniform highp float soft;

            void main() {
                highp vec2 p = qt_TexCoord0 - vec2(0.5, 0.5);
                highp float r = length(p);
                // Match GaugeArcItem: angle = rad(start-90) + rad(sweep)*u ; y-down cos/sin
                highp float ang = atan(p.y, p.x);
                highp float startRad = radians(startAngleDeg - 90.0);
                highp float sweepRad = radians(sweepAngleDeg);
                // Unwrap relative angle into [0, 2pi)
                highp float rel = ang - startRad;
                rel = mod(rel + 6.28318530718, 6.28318530718);
                highp float u = rel / max(sweepRad, 0.0001);
                highp float inSweep = step(0.0, u) * step(u, max(progress, 0.0));
                highp float band = 1.0 - smoothstep(bandHalf, bandHalf + soft, abs(r - radiusFactor));
                lowp vec4 tex = texture2D(source, qt_TexCoord0);
                // Lift concept magma midtones (baked atlas tends dark under eglfs)
                highp vec3 rgb = tex.rgb;
                rgb = mix(rgb, rgb * vec3(1.35, 1.18, 0.85) + vec3(0.08, 0.03, 0.0), 0.55);
                rgb = clamp(rgb, 0.0, 1.0);
                lowp float a = tex.a * band * inSweep;
                gl_FragColor = vec4(rgb * a, a) * qt_Opacity;
            }
        "
    }

    // Hot tip punch
    GaugeArcItem {
        anchors.fill: parent
        z: 3
        visible: root.showBand && root.clampedProgress > 0.01
        startAngleDeg: root.startAngleDeg
        sweepAngleDeg: root.sweepAngleDeg
        startProgress: Math.max(0.0, root.clampedProgress - (root.richMode ? 0.14 : 0.16))
        endProgress: root.clampedProgress
        radiusFactor: root.radiusFactor
        strokeWidth: root.strokePx * 0.72
        color: Qt.rgba(1.0, 0.96, 0.72, root.richMode ? 0.88 : 0.78)
        segments: 20
        roundedCaps: true
    }
}
