pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc
import qs.services

Scope {
    id: root
    property alias lock: lock

    // Every lock path funnels through requestLock() so suspend-after-lock
    // and already-locked guards stay in one place. Unlock needs no hook:
    // nothing is moved on lock, so there is nothing to restore.
    function requestLock(suspendAfter: bool): void {
        if (lock.locked) {
            if (suspendAfter)
                suspendTimer.restart();
            return;
        }
        lock.locked = true;
        if (suspendAfter)
            suspendTimer.restart();
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

        target: "lock"
    }

    Timer {
        id: suspendTimer

        interval: 1500
        repeat: false
        onTriggered: Quickshell.execDetached(["systemctl", "suspend"])
    }
}
