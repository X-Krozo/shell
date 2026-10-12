pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // Tooltip seat: height the panel blob extends upward while a tooltip
    // shows. Pill size is fixed (measurer-based), so this never loops.
    // Plain property (not readonly): the Behavior below needs to assign it.
    property real tipExtent: layout.hoveredName.length > 0 ? tipPill.implicitHeight + 14 : 0

    Behavior on tipExtent {
        Anim {}
    }

    // Menu close strands nothing: forget hover state with it.
    Connections {
        target: root.screenState

        function onSessionChanged() {
            if (!root.screenState.session) {
                layout.hoveredName = "";
                gifHover.tip = "";
            }
        }
    }

    Column {
        id: layout

        padding: Tokens.padding.large
        rightPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
        spacing: Tokens.spacing.large

        property string hoveredName: ""

        SessionButton {
            id: lock

        icon: "lock"
        tooltip: "Lock"
        command: ["qs", "-c", "caelestia", "ipc", "call", "lock", "lock"]

        KeyNavigation.down: suspend

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    lock.forceActiveFocus();
            }

            target: root.screenState
        }
    }

    SessionButton {
        id: suspend

        icon: "bedtime"
        tooltip: "Sleep"
        command: ["suspend"]

        KeyNavigation.up: lock
        KeyNavigation.down: logout
    }

    SessionButton {
        id: logout

        icon: Config.session.icons.logout
        tooltip: "Log out"
        command: Config.session.commands.logout

        KeyNavigation.up: suspend
        KeyNavigation.down: shutdown
    }

    AnimatedImage {
        id: gifImg

        width: Tokens.sizes.session.button
        height: Tokens.sizes.session.button
        sourceSize.width: width * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1)

        playing: visible
        asynchronous: true
        speed: Config.general.sessionGifSpeed
        source: Paths.absolutePath(Config.paths.sessionGif)
        fillMode: AnimatedImage.PreserveAspectFit

        // Click toggles the OSD sliders; hover shows uptime as DD:HH:MM.
        // No hover wash on the artwork itself.
        StateLayer {
            id: gifHover

            anchors.fill: parent
            radius: 0
            showHoverBackground: false
            showRipple: false

            property string tip: ""

            onClicked: root.screenState.osd = !root.screenState.osd
            onContainsMouseChanged: {
                if (containsMouse) {
                    uptimeProc.running = true;
                } else {
                    // Never strand the uptime text: clear it on leave even
                    // if a refresh landed mid-hover, then forget the stamp.
                    const h = parent.parent.hoveredName; // qmllint disable missing-property
                    if ((tip !== "" && h === tip) || /^\d\d:\d\d:\d\d$/.test(h))
                        parent.parent.hoveredName = ""; // qmllint disable missing-property
                    tip = "";
                }
            }

            Process {
                id: uptimeProc

                command: ["cat", "/proc/uptime"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const s = Math.floor(parseFloat(text.split(" ")[0]) || 0);
                        const d = String(Math.floor(s / 86400)).padStart(2, "0");
                        const h = String(Math.floor(s % 86400 / 3600)).padStart(2, "0");
                        const m = String(Math.floor(s % 3600 / 60)).padStart(2, "0");
                        gifHover.tip = `${d}:${h}:${m}`;
                        if (gifHover.containsMouse)
                            gifHover.parent.parent.hoveredName = gifHover.tip; // qmllint disable missing-property
                    }
                }
            }
        }
    }

    SessionButton {
        id: shutdown

        icon: Config.session.icons.shutdown
        tooltip: "Shut down"
        command: Config.session.commands.shutdown

        KeyNavigation.up: logout
        KeyNavigation.down: reboot
    }

    SessionButton {
        id: reboot

        icon: Config.session.icons.reboot
        tooltip: "Restart"
        command: Config.session.commands.reboot

        KeyNavigation.up: shutdown
        KeyNavigation.down: hibernate
    }

    SessionButton {
        id: hibernate

        icon: Config.session.icons.hibernate
        tooltip: "Hibernate"
        command: Config.session.commands.hibernate

        KeyNavigation.up: reboot
    }
    }

    // In-panel tooltip: fixed slot at the top (panel never moves), panel
    // background, glass finish (restrained top sheen, hairline light
    // border). Only fades/scales in.
    StyledRect {
        id: tipPill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: layout.top
        anchors.bottomMargin: 4

        implicitWidth: tipMeasurer.implicitWidth + Tokens.padding.extraSmall * 2
        implicitHeight: tipMeasurer.implicitHeight + Tokens.padding.medium * 2

        visible: opacity > 0
        opacity: layout.hoveredName.length > 0 ? 1 : 0
        scale: layout.hoveredName.length > 0 ? 1 : 0.6
        radius: Tokens.rounding.large
        transformOrigin: Item.Bottom

        gradient: Gradient {
            orientation: Gradient.Vertical

            GradientStop {
                position: 0
                color: Qt.rgba(1, 1, 1, 0.13)
            }

            GradientStop {
                position: 0.45
                color: Qt.rgba(1, 1, 1, 0.03)
            }

            GradientStop {
                position: 1
                color: Qt.rgba(1, 1, 1, 0.0)
            }
        }
        Behavior on opacity {
            Anim {}
        }

        Behavior on scale {
            Anim {
                type: Anim.StandardSmall
            }
        }

        // Hidden measurer on the longest label: width never jumps.
        StyledText {
            id: tipMeasurer

            visible: false
            text: "Shut down"
            font: Tokens.font.body.builders.medium.scale(0.75).build()
        }

        StyledText {
            id: tipLabel

            anchors.centerIn: parent
            text: layout.hoveredName
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.builders.medium.scale(0.75).build()
        }
    }

    component SessionButton: IconButton {
        id: button

        required property list<string> command

        function exec(): void {
            if (!SessionManager.exec(command))
                Quickshell.execDetached(command);
        }

        // Keyboard focus follows the mouse: hovering a button focuses it,
        // so Enter always triggers the button under the cursor. The shared
        // tooltip above reads the hovered button via parent (scope-safe).
        property string tooltip: ""
        onHoveredChanged: {
            if (hovered) {
                forceActiveFocus();
                parent.hoveredName = tooltip; // qmllint disable missing-property
            } else if (tooltip !== "" && parent.hoveredName === tooltip) { // qmllint disable missing-property
                parent.hoveredName = ""; // qmllint disable missing-property
            }
        }

        implicitWidth: Tokens.sizes.session.button
        implicitHeight: Tokens.sizes.session.button

        inactiveColour: activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        inactiveOnColour: activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
        radius: pressed ? Tokens.rounding.medium : activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        font: Tokens.font.icon.builders.large.scale(1.3).build()
        onClicked: exec()

        Keys.onEnterPressed: exec()
        Keys.onReturnPressed: exec()
        Keys.onEscapePressed: root.screenState.session = false
        Keys.onPressed: event => {
            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && KeyNavigation.down) {
                    KeyNavigation.down.focus = true;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab && KeyNavigation.down) {
                KeyNavigation.down.focus = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            }
        }
    }
}
