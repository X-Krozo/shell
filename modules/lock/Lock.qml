pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.misc
import qs.services

Scope {
    id: root
    property alias lock: lock

    // systemctl command run when a lock-with-suspend sequence completes.
    // Normal requests keep the default; flow routers override it per request
    // (see requestLock/requestSuspend), so a normal lockAndSuspend after an
    // idle/launcher request can't be hijacked by a stale override.
    readonly property var defaultSuspendCommand: ["systemctl", "suspend"]
    property var suspendCommand: root.defaultSuspendCommand

    // Normalised (dashes/underscores stripped, lowercased) suspend-family
    // action specifiers -> the systemctl command used after the lock settles,
    // mirroring the names SessionManager::exec understands.
    readonly property var suspendCommands: ({
        suspend: ["systemctl", "suspend"],
        suspendthenhibernate: ["systemctl", "suspend-then-hibernate"],
        hibernate: ["systemctl", "hibernate"]
    })

    // Single-word suspend-family specifier -> command list, or null when the
    // specifier isn't suspend-family (callers fall through to their own
    // handling — SessionManager, Hypr dispatch, execDetached).
    function suspendCommandFor(action: var): var {
        if (typeof action !== "string")
            return null;
        return root.suspendCommands[action.replace(/-|_/g, "").toLowerCase()] ?? null;
    }

    // Every lock path funnels through requestLock() so suspend-after-lock
    // and already-locked guards stay in one place. Unlock needs no hook:
    // nothing is moved on lock, so there is nothing to restore.
    // `command` overrides the systemctl op used after the lock (undefined ->
    // default), so suspend-then-hibernate flows keep their semantics.
    function requestLock(suspendAfter: bool, command: var): void {
        if (suspendAfter)
            root.suspendCommand = command ?? root.defaultSuspendCommand;

        if (lock.locked) {
            if (suspendAfter)
                suspendTimer.restart();
            return;
        }
        lock.locked = true;
        if (suspendAfter)
            suspendTimer.restart();
    }

    // Suspend through the lock. Direct logind paths sleep while the desktop
    // is still visible — logind only sends PrepareForSleep (the signal that
    // triggers requestLock(false) upstream) milliseconds before the machine
    // sleeps, so the lock surface, its entry animation and the background
    // would never show beforehand.
    function requestSuspend(command: var): void {
        root.requestLock(true, command);
    }

    // Locking grabs the keyboard mid-gesture: a Super release that lands on
    // the lock screen never reaches the shell, so clear any held Super state
    // here or numbers/subscripts get stuck on.
    // (Handled inline on the WlSessionLock above.)

    WlSessionLock {
        id: lock

        signal unlock

        // Inline handler (not Connections+target): runs on lock flips.
        // Note the unlock side never fires (quickshell skips the
        // locked=false notification); restore is poll-driven, this else
        // branch is only a fallback.
        onLockedChanged: {
            if (lock.locked)
                Hypr.superReleased();
        }

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false

        // Force a load of a screencopy so the one in the lock works
        // My guess is the ICC backend loads async on first request, which if the lock is
        // the first request it fails to capture (because it's async and the compositor
        // refuses capture when locked)
        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: root.requestLock(false)
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    IpcHandler {
        function lock(): void {
            root.requestLock(false);
        }

        function unlock(): void {
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        function lockAndSuspend(): void {
            root.requestLock(true);
        }

        // Suspend-family router for flows without a lock object (launcher,
        // script-side callers): <action> is a suspend-family specifier —
        // suspend / suspend-then-hibernate / hibernate, hyphens and case
        // ignore. Unrecognised <action> keeps the default systemd suspend.
        function lockThen(action: string): void {
            root.requestSuspend(root.suspendCommandFor(action));
        }

        target: "lock"
    }

    Timer {
        id: suspendTimer

        // The lock's entry animation finishes in ~750ms; when the lock uses a
        // wallpaper background its zoom runs 2000ms and needs the extra room,
        // otherwise the system would sleep mid-zoom (screencopy backgrounds
        // need only the 1500ms the entry animation takes).
        interval: GlobalConfig.lock.useWallpaper ? 2100 : 1500
        repeat: false
        onTriggered: Quickshell.execDetached(root.suspendCommand)
    }

    // A second requestLock(true) racing the first re-arms this timer INSIDE
    // the ~2s lock window (idle timeout + lid close in the same breath); if
    // logind freezes userspace before it fires, the timer survives S3
    // (CLOCK_MONOTONIC pauses) and fires ~2s into the next wake — the
    // instant-re-suspend-on-wake bug. Kill it at both ends of a sleep.
    Connections {
        // qmllint disable detached-signals
        function onAboutToSleep(): void {
            suspendTimer.stop();
        }

        function onResumed(): void {
            suspendTimer.stop();
        }

        target: SessionManager
    }
}
