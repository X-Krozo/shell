pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import M3Shapes
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.widgets
import qs.services

Item {
    id: root

    readonly property real centerX: width / 2
    readonly property real centerY: height / 2
    readonly property real spacing: Tokens.spacing.medium
    property real coverSize: Tokens.sizes.dashboard.mediaCoverArtSize
    readonly property real maxMagnitude: (width - root.coverSize) / 2 - spacing

    ServiceRef {
        // Only hold the analyzer alive while the dashboard is actually on
        // screen: a permanent ref (the tabs-load-once change) made cava + the
        // PipeWire capture run 24/7, and their per-tick binding churn starved
        // the shell's own animations (bar slide / panel blobs).
        service: root.visible ? Audio.cava : null
    }

    Shape {
        anchors.fill: parent
        asynchronous: true
        preferredRendererType: Shape.CurveRenderer
        data: bars.instances
    }

    Variants {
        id: bars

        model: Array.from({
            length: GlobalConfig.services.visualiserBars
        }, (_, i) => i)

        ShapePath {
            id: bar

            required property int modelData
            readonly property real value: Math.max(1e-2, Math.min(1, Audio.cava.values[modelData]))

            readonly property real angle: modelData * 2 * Math.PI / GlobalConfig.services.visualiserBars
            readonly property real dist: shapeEdgeDist + value * root.maxMagnitude
            readonly property real shapeEdgeDist: {
                cover.shape.rotation; // Update when shape rotation changes
                const sDist = cover.shape.distanceAtAngle(modelData * 360 / GlobalConfig.services.visualiserBars + 90);
                return sDist + root.spacing + strokeWidth / 2;
            }
            readonly property real cos: Math.cos(angle)
            readonly property real sin: Math.sin(angle)

            asynchronous: true
            capStyle: root.Tokens.rounding.scale === 0 ? ShapePath.SquareCap : ShapePath.RoundCap
            strokeWidth: root.coverSize / Tokens.sizes.dashboard.mediaCoverArtSize * (360 / GlobalConfig.services.visualiserBars - root.Tokens.spacing.small / 4)
            strokeColor: Colours.palette.m3primary

            startX: root.centerX + shapeEdgeDist * cos
            startY: root.centerY + shapeEdgeDist * sin

            PathLine {
                x: root.centerX + bar.dist * bar.cos
                y: root.centerY + bar.dist * bar.sin
            }

            Behavior on strokeColor {
                CAnim {}
            }
        }
    }

    CoverArt {
        id: cover

        anchors.centerIn: parent
        shape.shape: MaterialShape.Cookie9Sided
        implicitWidth: root.coverSize
        implicitHeight: root.coverSize
    }
}
