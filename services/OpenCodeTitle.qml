pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

import qs.services
import qs.utils

// Restores what opencode squashes away. opencode hard-truncates the terminal
// title it sets to 37 chars + "…" before anything else sees it (verified in
// its binary: slice(0,37) + "…" once the title passes 40 chars), so window
// titles can never reach the bar's 75-char cap. This polls opencode's own
// session list and offers squash -> full-title lookups so the bar can show
// the complete session title for "OC | …" windows.
Singleton {
    id: root

    function squash(title: string): string {
        return title.length > 40 ? title.slice(0, 37) + "…" : title;
    }

    // Squashed title -> full session title
    property var sessions: ({})


    // Full session title for a squashed one, or "" when the title wasn't
    // truncated (it is already complete) or the session list hasn't seen it.
    function fullTitleFor(squashed: string): string {
        if (!squashed.endsWith("…"))
            return "";
        return root.sessions[squashed] ?? "";
    }

    // Only poll while an OC window exists — otherwise this is wasted spawns.
    readonly property bool ocWindowExists: Hypr.toplevels.values.some(t => t.title.startsWith("OC | "))

    onOcWindowExistsChanged: {
        if (ocWindowExists)
            root.refresh();
    }

    function refresh(): void {
        if (!ocWindowExists || listProc.running)
            return;
        listProc.running = true;
    }

    Timer {
        interval: 5000
        running: root.ocWindowExists
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc

        command: ["opencode", "api", "session.list"]

        stdout: StdioCollector {
            id: listOut
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            const parsed = (() => {
                try {
                    const reply = JSON.parse(listOut.text.trim());
                    return Array.isArray(reply) ? reply : reply?.data ?? [];
                } catch (e) {
                    console.warn("[openctitle]", "bad reply:", e);
                    return [];
                }
            })();

            const next = {};
            for (const session of parsed) {
                if (typeof session?.title === "string" && session.title.length > 0)
                    next[root.squash(session.title)] = session.title;
            }
            root.sessions = next;
        }
    }
}
