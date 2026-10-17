pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.bar

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions
    readonly property alias geometry: geometry

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: contentItem.Config.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: contentItem.Config.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : contentItem.Config.border.thickness

    // Fullscreen: the shell stays behind the fullscreen app unless
    // `showOverFullscreen` opts the whole thing over, but the OSD is always
    // allowed over it so its sliders stay draggable there. The fullscreen mask
    // below exposes only the OSD strip, so nothing else of the shell is visible
    // or hit-testable over a fullscreen app.
    readonly property bool shellOverFullscreen: contentItem.Config.general.showOverFullscreen
    readonly property bool osdOverFullscreen: contentItem.Config.osd.enabled && root.hasFullscreen

    property color surfaceColour: Colours.tPalette.m3surface

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (contentItem.Config[panel].enabled)
                thresholds.push(contentItem.Config[panel].dragThreshold);
        return Math.max(...thresholds, 10);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        panels.popouts.close();
    }

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: root.osdOverFullscreen || (fsTransitionProg > 0 && root.shellOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top
    // NOTE: osd excluded from keyboard focus: it must never steal keys from
    // apps (media keys are global shortcuts; its sliders are mouse-driven).
    WlrLayershell.keyboardFocus: screenState.launcher || screenState.session || screenState.mediaFullscreen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: hasFullscreen ? emptyRegion : regions

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Behavior on fsTransitionProg {
        Anim {
            type: Anim.SlowSpatial
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on surfaceColour {
        CAnim {}
    }

    EdgeGeometry {
        id: geometry

        bar: bar
        win: root
        configPosition: "top"
        configDashboardPosition: "left"
    }

    Region {
        id: emptyRegion

        // Fullscreen input mask. The OSD strip is always live so its sliders
        // stay draggable over a fullscreen app; the notifications strip is only
        // added when the whole shell is allowed over fullscreen, otherwise it
        // would swallow clicks meant for the app underneath.
        x: root.shellOverFullscreen ? panels.notifications.x + geometry.insetLeft(root.borderThickness) : 0
        y: root.shellOverFullscreen ? panels.notifications.y + geometry.insetTop(root.borderThickness) : 0
        width: root.shellOverFullscreen ? panels.notifications.width : 0
        height: root.shellOverFullscreen ? panels.notifications.height : 0

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + root.borderThickness
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        geometry: geometry
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.contentItem.Config;
            // NOTE: osd deliberately excluded: it pops on every Audio/brightness
            // init (including shell start) and must never steal input; its
            // sliders are mouse-driven and media keys are global shortcuts.
            if ((s.launcher && conf.launcher.enabled) || (s.session && conf.session.enabled) || (s.sidebar && conf.sidebar.enabled) || (s.utilities && conf.utilities.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.dashboard = false;
            root.screenState.osd = false;
            root.screenState.utilities = false;
            // The dock is an OSD sibling: no grab of its own, so it rides the
            // same clear, otherwise it strands when the click lands on an app.
            root.screenState.appVolumes = false;
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    StyledRect {
        anchors.fill: parent
        opacity: (root.screenState.session && Config.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0
        color: Colours.palette.m3scrim

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    Item {
        anchors.fill: parent
        // Slow fade around fullscreen mirrors the restart entrance: the
        // layer stays mapped (media overlays keep working), only its
        // visibility melts out and back in alongside the border morph.
        opacity: root.surfaceColour.a * (root.hasFullscreen ? 0 : 1)
        Behavior on opacity {
            Anim {
                type: Anim.SlowSpatial
                easing.type: Easing.InOutQuad
            }
        }
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: false
            blurMax: 0
            shadowColor: Qt.alpha(Colours.palette.m3shadow, Math.max(0, root.shadowOpacity))
        }

        BlobGroup {
            id: blobGroup

            color: root.surfaceColour
            smoothing: root.contentItem.Config.border.smoothing
        }

        BlobInvertedRect {
            anchors.fill: parent
            anchors.margins: -50 // Make border thicker to smooth out bulge from closed drawers
            group: blobGroup
            radius: root.borderRounding
            borderLeft: geometry.insetLeft(root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderRight: root.borderThickness - anchors.margins - root.sdfBorderOffset
            borderTop: geometry.insetTop(root.borderThickness) - anchors.margins - root.sdfBorderOffset
            borderBottom: geometry.insetBottom(root.borderThickness) - anchors.margins - root.sdfBorderOffset
        }

        PanelBg {
            id: dashBg

            panel: panels.dashboard
            deformAmount: 0.1
        }

        PanelBg {
            id: launcherBg

            panel: panels.launcher
            deformAmount: 0.1
            // Parks downward: further down when closed, never toward the screen.
            y: (panel.visible ? panel.y : panel.y + 100) + geometry.insetTop(root.borderThickness)
        }

        PanelBg {
            id: sessionBg

            panel: panels.sessionWrapper
            open: panels.session.visible
            deformAmount: 0.2
            x: (panels.session.visible ? panels.sessionWrapper.x + panels.session.x : panels.sessionWrapper.x + panels.session.x + 100) + geometry.insetLeft(root.borderThickness)
            implicitWidth: panels.session.visible ? panels.session.width : 1
            // Seat for the hover tooltip: grows upward, buttons never move.
            y: panels.sessionWrapper.y + panels.session.y + geometry.insetTop(root.borderThickness) - panels.session.tipExtent
            implicitHeight: panels.session.visible ? panels.session.height + panels.session.tipExtent : 1
        }

        PanelBg {
            id: sidebarBg

            panel: panels.sidebar
            deformAmount: 0.03
            // Parks rightward: further right when closed, never toward the screen.
            x: (panel.visible ? panel.x : panel.x + 100) + geometry.insetLeft(root.borderThickness)
            implicitHeight: panel.height * (1 / rawDeformMatrix.m22) + 2
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [utilsBg]
            bottomLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: osdBg

            panel: panels.osdWrapper
            open: panels.osd.visible
            deformAmount: 0.25
            x: (panels.osd.visible ? panels.osdWrapper.x + panels.osd.x : panels.osdWrapper.x + panels.osd.x + 100) + geometry.insetLeft(root.borderThickness)
            implicitWidth: panels.osd.visible ? panels.osd.width : 1
            // Wrapper never hides (height collapses to 0); gate on the
            // inner panel so the blob never goes degenerate at rest.
            implicitHeight: panels.osd.visible ? panels.osdWrapper.height : 1
        }

        PanelBg {
            id: volumeDockBg

            panel: panels.volumeDockWrapper
            open: panels.volumeDock.visible
            deformAmount: 0.25
            // Expanded drawer: while a tooltip is up the blob grows upward into
            // the label slot so the label sits on the drawer's glass. No
            // sideways growth at all — the slot is a compact fixed width, so a
            // long app name is ellipsised instead of widening the panel. Read
            // through a local so the parked/open branches can't disagree.
            property real tooltipExtent: panels.volumeDock.visible ? panels.volumeDock.tooltipExtent : 0
            x: (panels.volumeDock.visible ? panels.volumeDockWrapper.x + panels.volumeDock.x : panels.volumeDockWrapper.x + panels.volumeDock.x + 100) + geometry.insetLeft(root.borderThickness)
            implicitWidth: panels.volumeDock.visible ? panels.volumeDock.width : 1
            // Follows the dive via the dock's live y.
            y: panels.volumeDockWrapper.y + panels.volumeDock.y + geometry.insetTop(root.borderThickness) - tooltipExtent
            implicitHeight: panels.volumeDock.visible ? panels.volumeDock.height + tooltipExtent : 1
        }

        PanelBg {
            id: notifsBg

            panel: panels.notifications
        }

        PanelBg {
            id: utilsBg

            panel: panels.utilities
            deformAmount: panels.sidebar.visible ? 0.1 : 0.15
            // Parks downward: further down when closed, never toward the screen.
            y: (panel.visible ? panel.y : panel.y + 100) + geometry.insetTop(root.borderThickness)
            exclude: panels.sidebar.offsetScale > 0.08 ? [] : [sidebarBg]
            topLeftRadius: Math.max(0, Math.min(1, panels.sidebar.offsetScale / 0.3)) * radius
        }

        PanelBg {
            id: popoutBg

            // Extra extent to prevent axis movement deformation partially detaching panel from bar
            property real extraExtent: panels.popouts.isDetached ? 0 : (panels.popouts.hasCurrent ? 0.2 : 0)

            panel: panels.popoutsWrapper
            open: panels.popoutsWrapper.visible
            deformAmount: panels.popouts.isDetached ? 0.05 : panels.popouts.hasCurrent ? 0.15 : 0.1
            x: (panels.popoutsWrapper.visible ? panels.popoutsWrapper.x + panels.popouts.x : panels.popoutsWrapper.x + panels.popouts.x - 100) + geometry.insetLeft(root.borderThickness) - (geometry.horizontal ? 0 : panels.popouts.width * extraExtent)
            y: (panels.popoutsWrapper.visible ? panels.popoutsWrapper.y + panels.popouts.y : panels.popoutsWrapper.y + panels.popouts.y - 100) + geometry.insetTop(root.borderThickness) - (geometry.barOnTop ? panels.popouts.height * extraExtent : 0)
            implicitWidth: panels.popoutsWrapper.visible ? panels.popouts.width * (geometry.horizontal ? 1 : 1 + extraExtent) : 1
            implicitHeight: panels.popoutsWrapper.visible ? panels.popouts.height * (geometry.horizontal ? 1 + extraExtent : 1) : 1

            Behavior on extraExtent {
                Anim {}
            }
        }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        bar: bar
        geometry: geometry
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        FullscreenMedia {
            id: mediaFullscreen

            screenState: root.screenState
            bar: bar
            geometry: geometry
            borderThickness: root.borderThickness
        }

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            geometry: geometry
            borderThickness: root.borderThickness

            utilities.horizontalStretch: (sidebarBg.rawDeformMatrix.m11 - 1) / 2 + 1
            utilities.deformMatrix: utilsBg.rawDeformMatrix

            dashboard.transform: Matrix4x4 {
                matrix: dashBg.deformMatrix
            }
            launcher.transform: Matrix4x4 {
                matrix: launcherBg.deformMatrix
            }
            session.transform: Matrix4x4 {
                matrix: sessionBg.deformMatrix
            }
            sidebar.transform: Matrix4x4 {
                matrix: sidebarBg.deformMatrix
            }
            osd.transform: Matrix4x4 {
                matrix: osdBg.deformMatrix
            }
            volumeDock.transform: Matrix4x4 {
                matrix: volumeDockBg.deformMatrix
            }
            notifications.transform: Matrix4x4 {
                matrix: notifsBg.deformMatrix
            }
            utilities.transform: Matrix4x4 {
                matrix: utilsBg.deformMatrix
            }
            popouts.transform: Matrix4x4 {
                matrix: popoutBg.deformMatrix
            }
        }

        BarWrapper {
            id: bar

            // Anchored on one corner and sized by binding: an opposing pair of anchors sizes the
            // item instead, and keeps that size once the pair is dropped
            anchors.left: parent.left
            anchors.top: geometry.barOnBottom ? undefined : parent.top
            anchors.bottom: geometry.barOnBottom ? parent.bottom : undefined

            width: geometry.horizontal ? parent.width : implicitWidth
            height: geometry.horizontal ? implicitHeight : parent.height

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts
            position: geometry.position

            fullscreen: root.hasFullscreen
        }
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    // PARKED-BLOB RULES (read before touching!): the ring + blobs share
    // one SDF shader. A parked blob MUST leave the merge group entirely
    // (open ? blobGroup : null): merely moving it off-screen still lets its
    // SDF fringe eat the ring (1px rows / holes at rest), and collapsing it
    // to 0 in any dimension NaN-poisons the shader (stable garbage slabs).
    // Absolute far-away positions are banned too (wide blobs stay on-screen).
    // Parked = ungrouped + 1x1. Open/animation states track the panel.
    component PanelBg: BlobRect {
        required property Item panel
        property real deformAmount: 0.15
        // Ungroup when parked: an unregistered shape contributes no SDF,
        // so it can neither merge with the ring nor strand damage.
        // (Defaults to panel visibility; shells that never hide override it.)
        property bool open: panel.visible

        group: open ? blobGroup : null
        // Parked panels park their blobs off-screen: a parked blob would
        // otherwise smin-merge with the border ring and dim window borders.
        x: (panel.visible ? panel.x : panel.x - 100) + geometry.insetLeft(root.borderThickness)
        y: (panel.visible ? panel.y : panel.y - 100) + geometry.insetTop(root.borderThickness)
        implicitWidth: panel.visible ? panel.width : 1
        implicitHeight: panel.visible ? panel.height : 1
        radius: Tokens.rounding.extraLarge
        deformScale: (deformAmount * Config.appearance.deformScale) / 10000
    }
}
