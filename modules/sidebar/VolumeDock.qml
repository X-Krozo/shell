pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState

    readonly property bool shouldBeActive: root.screenState.appVolumes
    property real offsetScale: shouldBeActive ? 0 : 1
    property double openedAt: 0
    // Set on the first genuine open; the one-shot boot timer below only
    // fires if nothing ever opened the dock this boot (persisted flag).
    property bool bootDone: false

    readonly property string hoveredName: {
        const delegate = hoveredIndex >= 0 ? sliders.itemAt(hoveredIndex) : null;
        return delegate?.modelData ? Audio.getStreamName(delegate.modelData) ?? "" : "";
    }

    property real tooltipExtent: hoveredName.length > 0 ? tooltip.implicitHeight + Tokens.spacing.medium : 0

    // Hold the last label while the pill fades. Clearing hover would otherwise
    // zero the label, snapping the pill to a sliver mid-fade. The power menu
    // gets the same stability from its fixed-width measurer.
    property string pillText: ""

    onHoveredNameChanged: if (hoveredName !== "")
        pillText = hoveredName

    // Horizontal slide exactly like the OSD: parks off-screen right when
    // shut, slides left into place while fading in.
    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5) * offsetScale
    // Collapse to zero when shut (like the OSD loader unloading) so the
    // background blob vanishes with the panel instead of lingering.
    // Fixed box (body only): the hover tooltip floats above it and grows
    // only the background blob, never moving the dock — power-menu logic.
    // Zero when shut so the blob vanishes with the panel.
    implicitWidth: offsetScale < 1 ? body.implicitWidth : 0
    implicitHeight: offsetScale < 1 ? body.implicitHeight : 0
    opacity: 1 - offsetScale

    function show(): void {
        root.bootDone = true;
        root.screenState.appVolumes = true;
        openedAt = Date.now();
        hideTimer.restart();
    }

    Behavior on offsetScale {
        Anim {}
    }

    // No auto-hide: stays until GIF-toggled or the OSD/session closes.
    // The timer only throttles re-show pacing (see show()).
    Timer {
        id: hideTimer

        interval: Config.osd.hideDelay
    }

    // One-shot boot close: a persisted appVolumes=true would otherwise
    // strand the dock open (no auto-hide by design). Fires once after
    // boot; any genuine open cancels it via bootDone, so it never
    // auto-hides after.
    Timer {
        id: bootCloseTimer

        interval: Config.osd.hideDelay
        running: root.screenState.appVolumes && !root.bootDone
        onTriggered: root.screenState.appVolumes = false
    }

    // Follow the transient panels: OSD or session closing takes the dock
    // along, so it never strands (covers every close path at once).
    // GIF toggles restart the fuse here so the toggle needs no wiring.
    Connections {
        target: root.screenState

        function onAppVolumesChanged(): void {
            if (root.screenState.appVolumes) {
                // A genuine open cancels the one-shot boot close below;
                // without this the boot timer would shut every GIF-toggle
                // open ~2s later (show() is never called on that path).
                root.bootDone = true;
                openedAt = Date.now();
                hideTimer.restart();
            }
        }

        function onSessionChanged(): void {
            if (!root.screenState.session)
                root.screenState.appVolumes = false;
        }
    }

    Behavior on tooltipExtent {
        Anim {}
    }

    StyledRect {
        id: body

        anchors.centerIn: parent

        implicitWidth: layout.implicitWidth + Tokens.padding.large * 2
        implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
        // Transparent: the background blob (volumeDockBg) carries the theme,
        // exactly like OSD content over osdBg.
        radius: Tokens.rounding.extraLarge
        color: "transparent"

        RowLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            StyledText {
                visible: Audio.streams.length === 0
                Layout.alignment: Qt.AlignCenter
                text: qsTr("No apps")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }

            Repeater {
                id: sliders

                model: Audio.streams

                delegate: ColumnLayout {
                    id: column

                    required property PwNode modelData
                    required property int index

                    spacing: Tokens.spacing.extraSmall

                    // Literal copy of the OSD slider block (osd/Content.qml)
                    CustomMouseArea {
                        function onWheel(event: WheelEvent) {
                            const current = Audio.getStreamVolume(column.modelData);
                            if (event.angleDelta.y > 0)
                                Audio.setStreamVolume(column.modelData, Math.min(1.0, current + GlobalConfig.services.audioIncrement));
                            else if (event.angleDelta.y < 0)
                                Audio.setStreamVolume(column.modelData, Math.max(0, current - GlobalConfig.services.audioIncrement));
                        }

                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Tokens.sizes.osd.sliderWidth
                        implicitHeight: Tokens.sizes.osd.sliderHeight

                        FilledSlider {
                            id: streamSlider

                            objectName: "appvol"
                            anchors.fill: parent

                            icon: Icons.getVolumeIcon(value, column.modelData?.audio?.muted ?? false)
                            value: column.modelData?.audio?.volume ?? 0
                            externalValue: column.modelData?.audio?.volume ?? 0
                            onMoved: {
                                Audio.setStreamVolume(column.modelData, value);
                                hideTimer.restart();
                            }
                            onHoveredChanged: {
                                if (streamSlider.hovered)
                                    root.hoveredIndex = column.index;
                                else if (root.hoveredIndex === column.index)
                                    root.hoveredIndex = -1;
                            }
                        }
                    }

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Tokens.sizes.osd.sliderWidth * 0.55
                        Layout.preferredHeight: Tokens.sizes.osd.sliderWidth * 0.55
                        source: Icons.getAppIcon(Audio.getStreamName(column.modelData), "image-missing")
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
            }
        }
    }

    property int hoveredIndex: -1

    // Hover pill mirrors the power-menu tooltip: same paddings, font,
    // scale-in and seat growth (width stays content-based: app names vary).
    StyledRect {
        id: tooltip

        anchors.bottom: body.top
        anchors.bottomMargin: 4
        anchors.horizontalCenter: body.horizontalCenter

        implicitWidth: label.implicitWidth + Tokens.padding.extraSmall * 2
        implicitHeight: label.implicitHeight + Tokens.padding.medium * 2

        visible: opacity > 0
        opacity: root.hoveredName.length > 0 ? 1 : 0
        scale: root.hoveredName.length > 0 ? 1 : 0.6
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        transformOrigin: Item.Bottom

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {
                type: Anim.StandardSmall
            }
        }

        StyledText {
            id: label

            anchors.centerIn: parent
            text: root.pillText
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.builders.medium.scale(0.75).build()
        }
    }
}
