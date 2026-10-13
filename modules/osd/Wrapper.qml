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

    // Fresh (user-opened) OSD waits on a long fuse so sliders stay reachable;
    // interacting switches to the normal fuse from the next change.
    // Startup opens (Audio/brightness init flood) must still auto-hide, so
    // opens during the boot window use the normal fuse.
    property bool booting: true

    Timer {
        interval: 3000
        running: true
        onTriggered: root.booting = false
    }

    // Timestamp of the last open; close paths check Date.now() - openedAt
    // imperatively so the opening gesture can never count as click-outside.
    // (A binding would latch: nothing re-triggers it after it turns true.)
    property double openedAt: 0

    function show(longFuse = false): void {
        // Drag-opens wait on a long fuse (reach the sliders first); system
        // opens (keys, BT/device changes, boot) use the normal fuse.
        if (!screenState.osd)
            timer.interval = (longFuse && !booting) ? root.Config.osd.hideDelay * 3 : root.Config.osd.hideDelay;
        screenState.osd = true;
        openedAt = Date.now();
        timer.restart();
    }

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;
    }

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (Date.now() - root.openedAt < 400)
                return;
            if (root.shouldBeActive && !content.containsMouse) {
                root.screenState.osd = false;
            }
        }
    }

    Connections {
        function onMutedChanged(): void {
            // Boot flood (Audio init) updates values without popping the
            // panel: with no auto-hide, a boot open would strand it.
            if (!root.booting)
                root.show();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            if (!root.booting)
                root.show();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            if (!root.booting && root.micVisible)
                root.show();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            if (!root.booting && root.micVisible)
                root.show();
            root.sourceVolume = Audio.sourceVolume;
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            if (!root.booting)
                root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }

        target: root.monitor
    }

    // No auto-hide: the OSD stays until toggled, clicked outside, or
    // escaped. The timer only throttles re-show pacing (see show()).
    Timer {
        id: timer

        interval: root.Config.osd.hideDelay
    }

    Connections {
        // Direct slider use switches to the normal fuse from the next change.
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
        active: root.shouldBeActive || root.visible

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
