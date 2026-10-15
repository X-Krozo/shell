pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Controls a Wi-Fi hotspot that shares the current Wi-Fi uplink with a phone.
// The heavy lifting lives in the root-owned helper /usr/local/bin/caelestia-hotspot
// (allowed passwordlessly via /etc/sudoers.d/caelestia-hotspot), so this only
// shells out to `sudo -n <helper> start|stop|status`.
Singleton {
    id: root

    readonly property string helper: "/usr/local/bin/caelestia-hotspot"

    property bool enabled: false
    property bool busy: false
    property string lastError: ""

    function refresh(): void {
        if (!busy)
            statusProc.running = true;
    }

    function setEnabled(on: bool): void {
        if (busy || on === enabled)
            return;

        busy = true;
        lastError = "";
        actionProc.command = ["sudo", "-n", root.helper, on ? "start" : "stop"];
        actionProc.running = true;
    }

    function toggle(): void {
        setEnabled(!enabled);
    }

    Process {
        id: statusProc

        command: ["sudo", "-n", root.helper, "status"]

        stdout: StdioCollector {
            id: statusOut
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            Qt.callLater(() => {
                if (code === 0)
                    root.enabled = statusOut.text.trim() === "on";
            });
        }
    }

    Process {
        id: actionProc

        stdout: StdioCollector {}

        stderr: StdioCollector {
            id: actionErr
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            Qt.callLater(() => {
                root.busy = false;
                root.lastError = code === 0 ? "" : actionErr.text.trim();
                refreshTimer.restart();
            });
        }
    }

    // Give create_ap a moment to fork/register before re-reading the state.
    Timer {
        id: refreshTimer

        interval: 1000
        onTriggered: root.refresh()
    }

    // Keep the switch in sync with changes made outside the shell.
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
