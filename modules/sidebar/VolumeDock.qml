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
        return delegate?.modelData?.label ?? "";
    }

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

    // How far the pill's bottom edge sits BELOW the dock body's top edge:
    // positive tucks the label down onto the drawer's shoulder.
    // How far the pill's bottom edge sits BELOW the dock body's top edge:
    // positive tucks the label down onto the drawer's shoulder.
    readonly property real tooltipDrop: 1

    // Drawer glass showing around the label slot — how much taller the
    // expanded drawer is than the label itself (above it) while a tooltip is
    // up. Purely a glass margin; the label's own size is unchanged.
    readonly property real tooltipPad: 20

    // Expanded-drawer extent: while a tooltip is up the dock's background blob
    // grows upward just enough to reach the label slot (plus tooltipPad of
    // glass around it), so the label sits on the drawer's own glass. It never
    // grows sideways — the slot is a compact fixed width (see tooltipWidth), so
    // a long app name is cut with an ellipsis instead of widening the panel.
    // Keyed on the hovered name alone (exactly like the power menu's tipExtent):
    // the drawer starts collapsing the moment the pointer leaves a slider, in
    // parallel with the label's fade — latching it on the fade instead made the
    // collapse lag a whole animation behind.
    property real tooltipExtent: hoveredName.length > 0 ? Math.max(0, tooltip.implicitHeight - root.tooltipDrop) + root.tooltipPad : 0

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
                visible: root.rows.length === 0
                Layout.alignment: Qt.AlignCenter
                text: qsTr("No apps")
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }

            Repeater {
                id: sliders

                model: root.rows

                delegate: ColumnLayout {
                    id: column

                    // One per app: either a real playback stream ({label,
                    // stream}) or a GHOST row for a quiet-but-audio-capable
                    // app's window ({label, stream: null}) — the ghost's
                    // remembered volume reapplies on stream reconnect.
                    required property var modelData
                    required property int index

                    readonly property string label: modelData.label
                    readonly property PwNode stream: modelData.stream

                    spacing: Tokens.spacing.extraSmall

                    // Literal copy of the OSD slider block (osd/Content.qml)
                    CustomMouseArea {
                        function currentVolume(): real {
                            return column.stream ? Audio.getStreamVolume(column.stream) : Audio.getGhostVolume(column.label);
                        }

                        function onWheel(event: WheelEvent) {
                            let target = currentVolume();
                            if (event.angleDelta.y > 0)
                                target = Math.min(1, target + GlobalConfig.services.audioIncrement);
                            else if (event.angleDelta.y < 0)
                                target = Math.max(0, target - GlobalConfig.services.audioIncrement);
                            if (column.stream)
                                Audio.setStreamVolume(column.stream, target);
                            Audio.setGhostVolume(column.label, target);
                            hideTimer.restart();
                        }

                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Tokens.sizes.osd.sliderWidth
                        implicitHeight: Tokens.sizes.osd.sliderHeight

                        FilledSlider {
                            id: streamSlider

                            objectName: "appvol"
                            anchors.fill: parent

                            icon: Icons.getVolumeIcon(value, column.stream ? column.stream.audio?.muted ?? false : false)
                            value: column.stream ? Audio.getStreamVolume(column.stream) : Audio.getGhostVolume(column.label)
                            externalValue: column.stream ? Audio.getStreamVolume(column.stream) : Audio.getGhostVolume(column.label)
                            onMoved: {
                                if (column.stream)
                                    Audio.setStreamVolume(column.stream, value);
                                Audio.setGhostVolume(column.label, value);
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

                    // Icon of the stream's app; themed music note when the
                    // stream has no desktop entry (CLI tools etc.). Slots are
                    // same-size siblings so layout never jumps between the two.
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Tokens.sizes.osd.sliderWidth * 0.55
                        Layout.preferredHeight: Tokens.sizes.osd.sliderWidth * 0.55

                        readonly property string appIcon: Icons.getAppStreamIcon(column.label)

                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            visible: parent.appIcon !== ""
                            source: parent.appIcon
                        }

                        MaterialIcon {
                            anchors.fill: parent
                            visible: parent.appIcon === ""
                            text: "music_note"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                }
            }
        }
    }

    // Real playback streams first, then GHOST rows: one per active window of
    // an audio-capable app (remembered the first time any of its streams
    // connected) whose stream is currently disconnected. Ghosts die with their
    // window (binding on Hypr.toplevels) and receive the remembered volume
    // once the app's stream reconnects.
    readonly property var rows: {
        const list = [];
        const seen = [];
        for (const stream of Audio.streams) {
            const label = Audio.getStreamName(stream);
            list.push({ label: label, stream: stream });
            seen.push(label.toLowerCase());
        }
        for (const toplevel of Hypr.toplevels.values) {
            const className = String(toplevel.lastIpcObject?.class ?? "");
            if (!className || !Audio.isAudioAppClass(className))
                continue;
            if (Audio.getAppStream(className))
                continue; // a real stream row already covers this app
            const label = className.split(/[ ._-]/)[0];
            if (seen.some(s => s === label.toLowerCase()))
                continue;
            list.push({ label: label, stream: null });
            seen.push(label.toLowerCase());
        }
        return list;
    }

    property int hoveredIndex: -1


    // Hover pill mirrors the power-menu tooltip: same paddings, font and
    // scale-in. Compact fixed-width slot — deliberately narrower than the dock
    // body (and never wider, so it can't hang off the panel over the
    // wallpaper). It never follows the hovered app name, so nothing about the
    // panel resizes per app; a name that doesn't fit is cut with an ellipsis.
    // Horizontal inset the label gives up on each side of the fixed pill:
    // same pill dimensions, tighter text area (long names overflow sooner,
    // feeding the marquee).
    readonly property real slotInset: Tokens.spacing.small

    readonly property real tooltipWidth: Math.min(110, Math.max(0, body.width - Tokens.padding.extraSmall * 2))

    StyledRect {
        id: tooltip

        anchors.bottom: body.top
        anchors.bottomMargin: -root.tooltipDrop
        // Nudged a few px right of the dock body's centre, like the power
        // menu's tooltip (which sits 4px right of its buttons).
        anchors.horizontalCenter: body.horizontalCenter
        anchors.horizontalCenterOffset: 4

        implicitWidth: root.tooltipWidth + Tokens.padding.extraSmall * 2
        implicitHeight: label.implicitHeight + Tokens.padding.small * 2

        visible: opacity > 0
        opacity: root.hoveredName.length > 0 ? 1 : 0
        scale: root.hoveredName.length > 0 ? 1 : 0.6
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large
        transformOrigin: Item.Bottom
        clip: true

        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {
                type: Anim.StandardSmall
            }
        }

        // Text window: the label only ever renders inside the padded slot, so
        // the pill's left/right padding keeps a constant visible gap at every
        // point of the marquee — including mid-slide and at the pause.
        Item {
            clip: true

            width: label.slotWidth
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            // No measurer: the slot width is fixed (see tooltipWidth), so the
            // label lays itself out against it on a single line. Names longer
            // than the slot get the usual marquee: slide right-to-left until
            // the end shows, pause, warp back, repeat; short names stay
            // dead-centre.
            StyledText {
                id: label

                readonly property real slotWidth: root.tooltipWidth - root.slotInset * 2
                readonly property bool overflow: implicitWidth > slotWidth
                readonly property real overflowWidth: Math.max(0, implicitWidth - slotWidth)

                property real slideOffset: 0

                width: implicitWidth
                // Static: centred in the window; sliding: the left edge walks
                // from the window's left boundary rightward by slideOffset
                // until its right end sits on the right boundary.
                x: overflow ? -slideOffset : (parent.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideNone
                horizontalAlignment: Text.AlignHCenter
                text: root.pillText
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.builders.medium.scale(0.75).build()

                SequentialAnimation {
                    id: marquee

                    loops: Animation.Infinite
                    running: tooltip.visible && label.overflow

                    // Lead-in hold: let the name be read before the slide
                    // starts (also applies at the top of every loop).
                    PauseAnimation {
                        duration: 800
                    }
                    PropertyAnimation {
                        target: label
                        property: "slideOffset"
                        from: 0
                        to: label.overflowWidth
                        duration: Math.round(label.overflowWidth * 1000 / 30) // ~30 px/s
                        easing.type: Easing.Linear
                    }
                    PauseAnimation {
                        duration: 700
                    }
                    onRunningChanged: {
                        if (!running)
                            label.slideOffset = 0
                    }
                }

                // A fresh latched label (or different overflow width) must start
                // its slide from the left edge, not resume mid-flight.
                property string restartKey: root.pillText + "|" + overflowWidth

                onRestartKeyChanged: {
                    if (marquee.running)
                        marquee.restart();
                }

                function debugState(): string {
                    return `label=${root.pillText} iw=${implicitWidth} slot=${slotWidth} overflow=${overflow} marquee=${marquee.running} x=${x}`;
                }

            }
        }
    }
}
