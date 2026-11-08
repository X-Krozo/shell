pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Controls a Wi-Fi hotspot that shares the current Wi-Fi uplink with a phone.
// The heavy lifting lives in the root-owned helper /usr/local/bin/caelestia-hotspot
// (allowed passwordlessly via /etc/sudoers.d/caelestia-hotspot), so this only
// shells out to `sudo -n <helper> start|stop|sync`.
Singleton {
    id: root

    readonly property string helper: "/usr/local/bin/caelestia-hotspot"

    property bool enabled: false
    property bool busy: false
    property string lastError: ""

    // Guards against a sync that started before an action finishing after it:
    // every action bumps `generation`, and refresh() tags the sync it starts with
    // the current value. A sync whose tag no longer matches was observed before
    // the action and its result is no longer ground truth.
    property int generation: 0
    property int syncGeneration: 0
    property bool pendingRefresh: false

    function refresh(): void {
        if (busy || statusProc.running) {
            pendingRefresh = true;
            return;
        }

        pendingRefresh = false;
        syncGeneration = generation;
        statusProc.running = true;
    }

    function setEnabled(on: bool): void {
        if (busy || on === enabled)
            return;

        generation++;
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

        // `sync` reports hotspot state AND re-follows the uplink: if the wifi
        // changed networks while the AP ran, the helper rebuilds it on the new
        // channel (ip: phones blip a few seconds, then reassociate with the
        // new uplink behind the same hotspot).
        command: ["sudo", "-n", root.helper, "sync"]

        stdout: StdioCollector {
            id: statusOut
        }

        stderr: StdioCollector {
            id: statusErr
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            Qt.callLater(() => {
                if (syncGeneration === generation) {
                    const was = root.enabled;
                    if (code === 0)
                        root.enabled = statusOut.text.trim() === "on";

                    // A helper error (e.g. a rebuild whose start failed) is our
                    // best explanation for the state: keep it visible until the
                    // state moves on its own or the user acts (setEnabled clears).
                    const errMsg = statusErr.text.trim();
                    if (errMsg !== "")
                        root.lastError = errMsg;
                    else if (root.enabled !== was)
                        root.lastError = "";
                }

                // Drain a refresh that was skipped because this sync was still
                // running (or an action was in progress).
                if (root.pendingRefresh)
                    root.refresh();
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
                // Set lastError before busy so observers of onBusyChanged can
                // rely on it reflecting the completed action.
                root.lastError = code === 0 ? "" : actionErr.text.trim();
                root.busy = false;
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
