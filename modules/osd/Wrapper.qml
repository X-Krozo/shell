pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property bool sidebarOrSessionVisible

    // Hover state, driven by the global pointer tracker in Interactions.qml
    // (the sliders consume their own hover events, so this can't be a local
    // MouseArea). While true the auto-close fuse is paused.
    property bool hovered
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    readonly property bool shouldBeActive: screenState.osd && Config.osd.enabled && !(screenState.utilities && Config.utilities.enabled)
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? 12 : 0
    // Mic slider visibility (mirrors its WrappedLoader): source changes
    // only pop the OSD when there's a slider to show for them.
    readonly property bool micVisible: Config.osd.enableMicrophone && (!Config.osd.enableBrightness || !screenState.session)

    property real volume
    property bool muted
    property real sourceVolume
    property bool sourceMuted
    property real brightness

    // Timestamp of the last open; close paths check Date.now() - openedAt
    // imperatively so the opening gesture can never count as click-outside.
    property double openedAt: 0

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;
    }

    function show(longFuse = false): void {
        // Drag-opens wait on a long fuse (reach the sliders first); system
        // opens (keys, BT/device changes, boot) use the normal fuse.
        if (!screenState.osd)
            timer.interval = longFuse ? root.Config.osd.hideDelay * 3 : root.Config.osd.hideDelay;
        screenState.osd = true;
        openedAt = Date.now();
        timer.restart();
    }

    // Boot splash: pop immediately, then auto-close after hideDelay unless
    // hovered. (An interval-0 timer defers past object construction.)
    Timer {
        interval: 0
        running: true
        onTriggered: root.show()
    }

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight || 300 // Hard coded fallback for first open (keeps the drag-catch zone full-size while closed)
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Connections {
        function onMutedChanged(): void {
            root.show();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            root.show();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            if (root.micVisible)
                root.show();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            if (root.micVisible)
                root.show();
            root.sourceVolume = Audio.sourceVolume;
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }

        target: root.monitor
    }

    // Auto-close fuse: fires hideDelay after the last open, or 3s after the
    // pointer leaves the panel. Paused entirely while hovered.
    Timer {
        id: timer

        interval: root.Config.osd.hideDelay
        onTriggered: {
            if (!root.hovered)
                root.screenState.osd = false;
        }
    }

    onHoveredChanged: {
        if (root.hovered) {
            timer.stop();
        } else if (root.screenState.osd) {
            timer.interval = 3000;
            timer.restart();
        }
    }

    // Clear stale hover when the OSD closes with the pointer resting over its
    // region (no pointer move ⇒ Interactions can't refresh it), otherwise the
    // next open would see hovered=true and refuse to auto-close.
    onShouldBeActiveChanged: {
        if (!root.shouldBeActive)
            root.hovered = false;
    }

    Connections {
        // Direct slider use restarts the fuse from the next change.
        function onInteracted(): void {
            timer.interval = root.Config.osd.hideDelay;
            timer.restart();
        }

        target: content.item
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        asynchronous: true
        // Always loaded (in background at boot): opens show full content
        // instantly instead of sliding an empty panel while it loads.
        active: true

        sourceComponent: Content {
            monitor: root.monitor
            screenState: root.screenState
            volume: root.volume
            muted: root.muted
            sourceVolume: root.sourceVolume
            sourceMuted: root.sourceMuted
            brightness: root.brightness
        }
    }
}