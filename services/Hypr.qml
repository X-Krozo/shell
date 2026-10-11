pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.I18n
import Caelestia.Services
import qs.components.misc

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors
    readonly property bool usingLua: Hyprland.usingLua

    // Address of the focused window, captured once at startup. Quickshell only
    // learns the active toplevel from focus events, so right after a (re)start
    // Hyprland.activeToplevel is null (bar shows "Desktop") until the first
    // focus change. Matching the startup address fills that gap; live focus
    // state always wins once it arrives.
    property string startupActiveAddress: ""

    readonly property HyprlandToplevel activeToplevel: {
        const want = root.startupActiveAddress.replace(/^0x/, "");
        const fb = want ? toplevels.values.find(w => String(w.address).replace(/^0x/, "") === want) ?? null : null;
        const t = Hyprland.activeToplevel ?? fb;
        return t?.workspace?.name.startsWith("special:") || Hyprland.focusedWorkspace?.toplevels.values.length > 0 ? t : null;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property string lastSpecialWorkspace: ""

    // Snapshot for Super-chord detection (a chord must never toggle the launcher)
    property int pressWsId: -1
    property int pressWinCount: -1
    property string pressWinAddr: ""

    // Super-hold workspace numbers: set by the workspaceNumbers shortcut.
    // showNumbers appears after a short delay (no flash on quick taps) and
    // clears on release; heldTooLong marks holds past the tap threshold.
    property bool showNumbers: false
    property bool superHeldTooLong: false
    // True between a press and its matching release; guards against stray or
    // reordered release deliveries toggling anything.
    property bool superPressedCycle: false

    Timer {
        id: showNumbersTimer

        interval: 150
        onTriggered: root.showNumbers = true
    }

    Timer {
        id: tapTimer

        interval: 850
        onTriggered: root.superHeldTooLong = true
    }

    function superPressed(): void {
        root.superPressedCycle = true;
        root.pressWsId = focusedWorkspace?.id ?? -1;
        root.pressWinCount = toplevels.values.length;
        root.pressWinAddr = activeToplevel?.address ?? "";
        root.showNumbers = false;
        root.superHeldTooLong = false;
        showNumbersTimer.restart();
        tapTimer.restart();
    }

    function superHadChord(): bool {
        return (focusedWorkspace?.id ?? -1) !== root.pressWsId || toplevels.values.length !== root.pressWinCount || (activeToplevel?.address ?? "") !== root.pressWinAddr;
    }

    function superReleased(): void {
        showNumbersTimer.stop();
        tapTimer.stop();
        root.showNumbers = false;
        root.superPressedCycle = false;
    }

    signal configReloaded

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function focusWorkspace(ws: var): void {
        dispatch(usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
    }

    function toggleSpecial(name: string): void {
        dispatch(usingLua ? `hl.dsp.workspace.toggle_special("${name}")` : `togglespecialworkspace ${name}`);
    }

    function cycleSpecialWorkspace(direction: string): void {
        const openSpecials = workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0);

        if (openSpecials.length === 0)
            return;

        const activeSpecial = focusedMonitor.lastIpcObject.specialWorkspace.name ?? "";

        if (!activeSpecial) {
            if (lastSpecialWorkspace) {
                const workspace = workspaces.values.find(w => w.name === lastSpecialWorkspace);
                if (workspace && workspace.lastIpcObject.windows > 0) {
                    focusWorkspace(lastSpecialWorkspace);
                    return;
                }
            }
            focusWorkspace(openSpecials[0].name);
            return;
        }

        const currentIndex = openSpecials.findIndex(w => w.name === activeSpecial);
        let nextIndex = 0;

        if (currentIndex !== -1) {
            if (direction === "next")
                nextIndex = (currentIndex + 1) % openSpecials.length;
            else
                nextIndex = (currentIndex - 1 + openSpecials.length) % openSpecials.length;
        }

        focusWorkspace(openSpecials[nextIndex].name);
    }

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
    }

    function trimWsName(name: string): string {
        return name.startsWith("special:") ? name.slice("special:".length) : name;
    }

    function toplevelsForWs(ws: int, ignoredTags = []): list<HyprlandToplevel> {
        return toplevels.values.filter(t => t.workspace && t.workspace.id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: HyprlandToplevel, ignoredTags = []): bool {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc?.class || !ipc.mapped)
            return true;

        return ipc.tags?.some(tag => ignoredTags.includes(tag.replace(/\*$/, ""))) ?? false;
    }

    function reloadDynamicConfs(): void {
        if (usingLua) {
            extras.batchMessage(['eval hl.bind("Caps_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })', 'eval hl.bind("Num_Lock", hl.dsp.global("caelestia:refreshDevices"), { locked = true, non_consuming = true, ignore_mods = true, release = true })']);
        } else {
            extras.batchMessage(["keyword bindlni ,Caps_Lock,global,caelestia:refreshDevices", "keyword bindlni ,Num_Lock,global,caelestia:refreshDevices"]);
        }
    }

    onUsingLuaChanged: reloadDynamicConfs()
    Component.onCompleted: {
        reloadDynamicConfs();
        startupActiveProc.running = true;
    }

    Process {
        id: startupActiveProc

        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.startupActiveAddress = JSON.parse(text.trim())?.address ?? "";
                } catch (e) {
                    root.startupActiveAddress = "";
                }
            }
        }
    }

    Connections {
        function onActiveToplevelChanged(): void {
            if (Hyprland.activeToplevel)
                root.startupActiveAddress = "";
        }

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                Hyprland.refreshToplevels();
                Hyprland.refreshWorkspaces();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
            }
        }

        target: Hyprland
    }

    Connections {
        function onLastIpcObjectChanged(): void {
            const specialName = root.focusedMonitor.lastIpcObject.specialWorkspace.name;

            if (specialName && specialName.startsWith("special:")) {
                root.lastSpecialWorkspace = specialName;
            }
        }

        target: root.focusedMonitor
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return root.workspaces.values.filter(w => w.name.startsWith("special:") && w.lastIpcObject.windows > 0).map(w => w.name).join("\n");
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras

        usingLua: Hyprland.usingLua
    }
}
