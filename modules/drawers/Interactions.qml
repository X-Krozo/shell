import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property ScreenState screenState
    required property Panels panels
    required property Bar.BarWrapper bar
    required property EdgeGeometry geometry
    required property real borderThickness
    required property bool fullscreen

    property point dragStart
    property bool pressedHere
    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = geometry.insetTop(borderThickness) + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = geometry.insetLeft(borderThickness) + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < geometry.insetLeft(borderThickness) + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    // A left bar's popout starts at the screen edge, so a one-sided bound is enough for it. A
    // horizontal bar's is centred on the hovered entry, so it needs bounding on both sides.
    function inPopoutArea(x: real, y: real): bool {
        const panel = panels.popoutsWrapper;
        if (!geometry.horizontal)
            return inLeftPanel(panel, x, y);
        return withinPanelWidth(panel, x, y) && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - Config.border.minThickness, geometry.insetLeft(borderThickness) + panel.x) && withinPanelHeight(panel, x, y);
    }

    // The volume dock is an OSD sibling, so treat it as a panel area: a click
    // on it is not "outside", and hovering its sliders must not time out the OSD.
    function inVolumeDock(x: real, y: real): bool {
        return panels.volumeDock.visible && withinPanelWidth(panels.volumeDockWrapper, x, y) && withinPanelHeight(panels.volumeDockWrapper, x, y);
    }

    // The OSD can open without a pointer move (volume keys, wheel on a slider),
    // so re-arm hover on open: otherwise the fuse would close the OSD beneath a
    // pointer that is already parked on the dock.
    Connections {
        target: screenState

        function onOsdChanged(): void {
            if (screenState.osd && root.containsMouse && inVolumeDock(root.mouseX, root.mouseY))
                root.panels.osd.hovered = true;
        }
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(Config.border.minThickness, geometry.insetTop(Config.border.thickness) + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(Config.border.minThickness, geometry.insetBottom(Config.border.thickness) + panelHeight) - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function inDashboardArea(x: real, y: real): bool {
        if (geometry.dashboardOnLeft) {
            if (geometry.barOnLeft && geometry.barContains(x, y))
                return false;
            const panelWidth = panels.dashboard.width * (1 - panels.dashboard.offsetScale);
            const edgeThreshold = Math.max(Config.border.minThickness, Config.border.rounding);
            return x < Math.max(edgeThreshold, geometry.insetLeft(Config.border.thickness) + panelWidth) && withinPanelHeight(panels.dashboard, x, y);
        }
        if (geometry.barOnTop && geometry.barContains(x, y))
            return false;
        return inTopPanel(panels.dashboard, x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (geometry.barContains(event.x, event.y)) {
            bar.handleWheel(geometry.axisPos(event.x, event.y), event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true
    propagateComposedEvents: true
    cursorShape: {
        // Hand only over entries that actually respond to clicks
        if (!geometry.barContains(mouseX, mouseY))
            return Qt.ArrowCursor;
        return ["logo", "workspaces", "tray", "statusIcons", "power"].includes(bar.entryAt(geometry.axisPos(mouseX, mouseY))) ? Qt.PointingHandCursor : Qt.ArrowCursor;
    }

    onPressed: event => { dragStart = Qt.point(event.x, event.y); pressedHere = true; }
    onReleased: event => { pressedHere = false; }

    // Click-to-toggle bar popouts: click the icon/area itself; same name already open closes it
    onClicked: event => {
        // Ignore clicks that were actually drags (moved more than 5px from press).
        // Only when the press was seen here; clicks propagated from bar children
        // carry no local press.
        if (pressedHere) {
            const dx = event.x - dragStart.x;
            const dy = event.y - dragStart.y;
            if (dx * dx + dy * dy > 25)  // 5px threshold
                return;
        }

        // Close OSD when clicking outside OSD area (always, regardless of bar click).
        // Ignored within the open grace period so the opening gesture can't close it.
        if (screenState.osd && Date.now() - panels.osd.openedAt > 400 && !inRightPanel(panels.osdWrapper, event.x, event.y) && !inVolumeDock(event.x, event.y)) {
            screenState.osd = false;
            // While the OSD is open the mask spans the whole window, so this
            // click never reaches the app beneath and therefore never clears
            // the session menu's focus grab — dismiss the menu here instead
            // (unless the click actually landed on the session panel).
            if (!inRightPanel(panels.sessionWrapper, event.x, event.y))
                screenState.session = false;
            return;
        }

        // Click-to-toggle bar popouts: click the icon/area itself; same name already open closes it
        if (!geometry.barContains(event.x, event.y))
            return;
        const before = (popouts.currentName ?? "") + (popouts.hasCurrent ? "|open" : "|closed");
        bar.checkPopout(geometry.axisPos(event.x, event.y));
        if (popouts.hasCurrent && (popouts.currentName ?? "") + "|open" === before) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }
    onContainsMouseChanged: {
        if (!containsMouse) {
            bar.hoveredEntry = "";
            // Never hide the OSD on mouse-leave: it stays until toggled,
            // clicked outside, or escaped (a fresh open would otherwise die
            // on the next mouse motion after its 400ms grace).
            if (!osdShortcutActive) {
                root.panels.osd.hovered = false;
            }

            if (Config.dashboard.showOnHover && !dashboardShortcutActive)
                screenState.dashboard = false;

            if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;

            if (Config.sidebar.showOnHover)
                screenState.sidebar = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y) || inVolumeDock(x, y);
            return;
        }

        // Track OSD hover so its auto-close fuse pauses while the pointer
        // is over the panel (sliders consume their own hover events, so the
        // global tracker is the only reliable source). The volume dock counts
        // too, so its sliders can't let the OSD time out underneath.
        root.panels.osd.hovered = root.screenState.osd && (inRightPanel(panels.osdWrapper, x, y) || inVolumeDock(x, y));

        // Show bar in non-exclusive mode on hover
        if (!screenState.bar && Config.bar.showOnHover && geometry.barContains(x, y, true))
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && geometry.barContains(dragStart.x, dragStart.y, true)) {
            const barDrag = geometry.inwardDrag(dragX, dragY);
            if (barDrag > Config.bar.dragThreshold)
                screenState.bar = true;
            else if (barDrag < -Config.bar.dragThreshold)
                screenState.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show OSD on drag from right edge
            if (pressed && inRightPanel(panels.osdWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.osdWrapper, x, y)) {
                if (dragX < -Config.sidebar.dragThreshold)
                    panels.osd.show(true);
                else if (dragX > Config.sidebar.dragThreshold && Date.now() - panels.osd.openedAt > 400)
                    screenState.osd = false;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, geometry.insetLeft(borderThickness) + panels.sidebar.x);

            // Show sidebar on hover (top-right corner, bounded by notification panel height)
            if (Config.sidebar.showOnHover) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = x > Math.min(width - Config.border.minThickness, geometry.insetLeft(borderThickness) + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar)
                    screenState.sidebar = true;
            }

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    screenState.sidebar = true;
            } else if (showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                screenState.sidebar = true;
            }
} else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);

            // Show OSD on drag from right edge
            if (pressed && outOfSidebar && inRightPanel(panels.osdWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.osdWrapper, x, y)) {
                if (dragX < -Config.sidebar.dragThreshold)
                    panels.osd.show(true);
                else if (dragX > Config.sidebar.dragThreshold && Date.now() - panels.osd.openedAt > 400)
                    screenState.osd = false;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > Config.session.dragThreshold)
                    screenState.session = false;
            }

            // Show/hide sidebar on hover
            if (Config.sidebar.showOnHover && !pressed) {
                const sidebarTriggerY = Math.max(Config.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = x > Math.min(width - Config.border.minThickness, geometry.insetLeft(borderThickness) + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar) {
                    screenState.sidebar = true;
                } else {
                    const inSidebarArea = inRightPanel(panels.sidebar, x, y) || inRightPanel(panels.sessionWrapper, x, y);
                    if (!inSidebarArea)
                        screenState.sidebar = false;
                }
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                screenState.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (Config.launcher.showOnHover) {
            if (!screenState.launcher && inBottomPanel(panels.launcher, x, y) && !(geometry.barOnBottom && geometry.barContains(x, y)))
                screenState.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && !(geometry.barOnBottom && geometry.barContains(dragStart.x, dragStart.y)) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                screenState.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                screenState.launcher = false;
        }

        // Show dashboard on hover, or show/hide on drag if hover is disabled
        if (Config.dashboard.showOnHover) {
            const showDashboard = inDashboardArea(x, y);
            if (!dashboardShortcutActive) {
                screenState.dashboard = showDashboard;
            } else if (showDashboard) {
                dashboardShortcutActive = false;
            }
        } else if (pressed && inDashboardArea(dragStart.x, dragStart.y) && (geometry.dashboardOnLeft ? withinPanelHeight(panels.dashboard, x, y) : withinPanelWidth(panels.dashboard, x, y))) {
            const dashThreshold = Config.dashboard.dragThreshold || 10;
            const dashDrag = geometry.dashboardOnLeft ? dragX : dragY;
            if (dashDrag > dashThreshold)
                screenState.dashboard = true;
            else if (dashDrag < -dashThreshold)
                screenState.dashboard = false;
        }

        // Show/hide utilities on drag from bottom edge
        const utilsThreshold = Config.sidebar.dragThreshold || 10;
        if (pressed && inBottomPanel(panels.utilities, dragStart.x, dragStart.y, true) && withinPanelWidth(panels.utilities, x, y)) {
            if (dragY < -utilsThreshold)
                screenState.utilities = true;
            else if (dragY > utilsThreshold)
                screenState.utilities = false;
        }

        // Bar popouts are click-toggled; keep the open one while the cursor is on
        // its panel or on the bar itself (so it survives the trip from icon to panel)
        if ((!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inPopoutArea(x, y) && !geometry.barContains(x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        // Track the bar entry under the cursor for hover cursor/effects
        bar.hoveredEntry = geometry.barContains(x, y) ? bar.entryAt(geometry.axisPos(x, y)) : "";
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.screenState.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inDashboardArea(root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.screenState.dashboard = false;
                }
                if (!inOsdArea) {
                    root.screenState.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.screenState.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inDashboardArea(root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.screenState.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.screenState.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.screenState
    }
}
