pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config

Region {
    id: root

    required property EdgeGeometry geometry
    required property Panels panels
    required property var win

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness
    // Edge-drag trigger zones are minThickness wide; closed panels keep exactly
    // that sliver so app UI (e.g. scrollbars) under the wrappers stays clickable
    readonly property real minThickness: win.contentItem.Config.border.minThickness

    x: geometry.insetLeft(clampedThickness, true) + win.dragMaskPadding
    y: geometry.insetTop(clampedThickness, true) + win.dragMaskPadding
    width: win.width - geometry.insetLeft(clampedThickness, true) - clampedThickness - win.dragMaskPadding * 2
    height: win.height - geometry.insetTop(clampedThickness, true) - geometry.insetBottom(clampedThickness, true) - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        x: root.geometry.dashboardOnLeft ? 0 : panel.x + root.geometry.insetLeft(root.borderThickness)
        y: root.geometry.dashboardOnLeft ? panel.y + root.geometry.insetTop(root.borderThickness) : 0
        width: root.geometry.dashboardOnLeft ? panel.width * (1 - root.panels.dashboard.offsetScale) + root.geometry.insetLeft(root.borderThickness) : panel.width
        height: root.geometry.dashboardOnLeft ? panel.height : panel.height * (1 - root.panels.dashboard.offsetScale) + root.geometry.insetTop(root.borderThickness)
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height
        height: panel.height * (1 - root.panels.launcher.offsetScale) + root.geometry.insetBottom(root.borderThickness)
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        // Anchor at the panel's real left edge and extend right over the
        // sidebar: when panels stack, a right-edge-anchored strip leaves the
        // panel itself uncovered, clicks fall through and the focus grab
        // clears (closing the session). Sliver at the edge while closed.
        x: root.win.screenState.session ? panel.x + root.geometry.insetLeft(root.borderThickness) : root.win.width - width
        width: root.win.screenState.session ? panel.width + root.borderThickness + sidebarRegion.width : root.minThickness
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.win.width - width
        width: root.win.screenState.sidebar ? panel.width + root.borderThickness : root.minThickness
    }

    R {
        panel: root.panels.osdWrapper
        // Same stacking rule as session: anchor at the panel's real left edge
        // and extend right over session/sidebar, else slider clicks fall
        // through and the grab clear closes the power menu. Bare trigger
        // sliver while closed so app UI underneath stays clickable.
        x: root.panels.osd.shouldBeActive ? panel.x + root.geometry.insetLeft(root.borderThickness) : root.win.width - width
        width: root.panels.osd.shouldBeActive ? panel.width + root.borderThickness + sessionRegion.width : root.minThickness
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.geometry.insetTop(root.borderThickness)
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - height
        height: panel.height * (1 - root.panels.utilities.offsetScale) + root.geometry.insetBottom(root.borderThickness)
    }

    R {
        panel: root.panels.popoutsWrapper
        // Full target size while open: the visual grows in via offsetScale, but input
        // must cover it from the first frame or a fast mouse leaves the window
        // mid-animation and the popout closes itself.
        width: root.geometry.horizontal ? panel.width : root.panels.popouts.hasCurrent ? root.panels.popouts.nonAnimWidth : panel.width * (1 - root.panels.popoutsWrapper.offsetScale)
        height: root.geometry.horizontal ? root.panels.popouts.hasCurrent ? root.panels.popouts.nonAnimHeight : panel.height * (1 - root.panels.popoutsWrapper.offsetScale) : panel.height
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.geometry.insetLeft(root.borderThickness)
        y: panel.y + root.geometry.insetTop(root.borderThickness)
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
