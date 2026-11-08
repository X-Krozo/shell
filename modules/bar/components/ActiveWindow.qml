pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property var bar
    required property Brightness.Monitor monitor
    required property bool horizontal
    property color colour: Colours.palette.m3primary

    // The compacted name, unbounded. Display truncation happens separately.
    readonly property string fullTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return Tr.trCtx("Desktop", "shown when no window is focused");
        let name = title;
        if (Config.bar.activeWindow.compact) {
            // " - " (standard hyphen), " — " (em dash), " – " (en dash)
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                name = parts[parts.length - 1].trim();
        }
        return name;
    }

    // opencode squashes session titles to 37 chars + "…" before the window
    // title ever reaches us; the session list service restores the originals.
    readonly property string windowName: {
        if (!root.fullTitle.startsWith("OC | "))
            return root.fullTitle;
        const restored = OpenCodeTitle.fullTitleFor(root.fullTitle.slice(5));
        return restored === "" ? root.fullTitle : `OC | ${restored}`;
    }

    // The 75-char cap is the pill's VIEWPORT, not the content cut: the name
    // renders in full and statically shows exactly the first 75 chars with
    // the faded tail; hovering arms the marquee that slides chars 76+ past
    // the viewport.
    readonly property string windowTitle: windowName.length > 75 ? windowName.slice(0, 75) : windowName

    // True when the cap viewport applies (its abrupt end needs the fade)
    readonly property bool truncated: windowName.length > 75

    readonly property int maxSize: {
        const children = bar.children.filter(c => c.entryId && c.item !== this);
        const otherSize = children.reduce((acc, curr) => acc + (curr.entryId === "spacer" || curr.item == null ? 0 : horizontal ? (curr.item.nonAnimWidth ?? curr.item.implicitWidth) : (curr.item.nonAnimHeight ?? curr.item.implicitHeight)), 0);
        // Length - 2 cause repeater counts as a child
        const available = horizontal ? bar.width : bar.height;
        const spacing = horizontal ? bar.columnSpacing : bar.rowSpacing;
        const greedy = available - otherSize - spacing * (bar.children.length - 1) - bar.axisPadding * 2;
        if (!horizontal)
            return greedy;

        const logoWidth = children.filter(c => c.entryId === "logo").reduce((acc, curr) => acc + (curr.item?.implicitWidth ?? 0), 0);
        // Cap so the left cluster (logo + this) never exceeds half the bar, keeping ws centerable
        const leftCap = available / 2 - bar.axisPadding * 2 - logoWidth - spacing * 2;
        return Math.min(greedy, leftCap);
    }
    property Title current: text1

    // Title marquee, mirroring the dock tooltip: the name renders unelided
    // inside a fixed clip window (the pill's slot minus an inset each side)
    // and slides only while the name overflows. Same pacing: hold 800ms,
    // ~30 px/s, pause 700ms at the tail, warp, repeat.
    readonly property real slotInset: Tokens.spacing.small
    readonly property real titleSlot: metrics.elideWidth
    readonly property real windowWidth: Math.max(0, titleSlot - slotInset * 2)

    // Viewport for 75+-char names: exactly the px width of the first 75
    // chars (same font), clamped to the slot — the static rest state cuts
    // crisply at the 75th char (no fade on content), hover reveals what's
    // beyond via the marquee.
    readonly property real cap75: Math.min(metrics.advanceWidth, windowWidth)
    property real slideOffset: 0
    property string marqueeKey: root.windowName + "|" + current.overflowWidth.toFixed(3)

    onMarqueeKeyChanged: {
        if (titleMarquee.running)
            titleMarquee.restart();
    }

    clip: true
    implicitWidth: horizontal ? icon.implicitWidth + current.implicitWidth + current.anchors.leftMargin : Math.max(icon.implicitWidth, current.implicitHeight)
    implicitHeight: horizontal ? Math.max(icon.implicitHeight, current.implicitHeight) : icon.implicitHeight + current.implicitWidth + current.anchors.topMargin

    Loader {
        id: hoverLoader

        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    popouts.currentCenter = root.bar.axisCenterOf(root);
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    // Hover over the pill arms the marquee (unhovers snap back to the
    // static 75+fade state)
    readonly property bool hovered: hoverLoader.item?.containsMouse ?? false

    MaterialIcon {
        id: icon

        anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
        anchors.left: root.horizontal ? parent.left : undefined

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour
    }

    Title {
        id: text1

        property string pageName: "t1"
    }

    Title {
        id: text2

        property string pageName: "t2"
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        // Slot the pill gives the title. The name itself renders unelided and
        // marquees when too long; elideWidth only sizes the window.
        elideWidth: root.maxSize - (root.horizontal ? icon.width + root.current.anchors.leftMargin : icon.height)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            // Snapshot fidelity without racing the global state: holding the
            // full name, only 75+-char names are over the viewport cap.
            // reveal reset guards a ws-switch landing mid-seam (would leave
            // the page permanently faded otherwise).
            next.reveal = 1;
            next.text = root.windowName;
            next.faded = next.text.length > 75;
            root.current = next;
        }
    }

    SequentialAnimation {
        id: titleMarquee

        loops: Animation.Infinite
        // Hover-gated: the pill sits static (75 chars + fade) unless the
        // pointer is on it.
        running: root.hovered && root.current.overflow && root.windowWidth > 0

        // Lead-in hold: let the name be read before the slide starts
        // (also applies at the top of every loop).
        PauseAnimation {
            duration: 800
        }

        PropertyAnimation {
            target: root
            property: "slideOffset"
            from: 0
            to: root.current.overflowWidth
            duration: Math.max(1, Math.round(root.current.overflowWidth * 1000 / 60)) // ~60 px/s
            easing.type: Easing.Linear
        }

        PauseAnimation {
            duration: 700
        }

        // Loop seam: fade out, hide the reset-to-zero inside the invisible
        // moment, fade back in — no visible jump. Holding each half a full
        // animation beat keeps the blink soft.
        ScriptAction {
            script: root.current.reveal = 0
        }

        PauseAnimation {
            duration: 350
        }

        ScriptAction {
            script: root.slideOffset = 0
        }

        ScriptAction {
            script: root.current.reveal = 1
        }

        PauseAnimation {
            duration: 350
        }

        onRunningChanged: {
            if (running)
                easeBack.stop();
            else if (root.slideOffset > 0)
                easeBack.start();
            else
                root.slideOffset = 0;
        }
    }

    // Ease-back on unhover / title change: glides the title home from
    // wherever the slide left it, instead of snapping.
    NumberAnimation {
        id: easeBack

        target: root
        property: "slideOffset"
        to: 0
        duration: 300
        easing.type: Easing.OutCubic
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        enabled: root.horizontal

        Anim {}
    }

    // Clip window the title lives in: the pill's slot minus an inset each
    // side, so the mask keeps a constant visible gap at the window edges
    // (same idea as the dock tooltip). The fade mask is glued to the window —
    // left AND right — for exactly the same overflowing name, whichever
    // workspace it came from; names that fit stay crisp with no mask at all.
    component Title: Item {
        id: text

        // Crossfade pages swap the name through this alias
        property alias text: label.text
        property string pageName: ""

        // Faded state snapshot taken when this page received its text: the
        // mask follows the PAGE's own content through the crossfade, not the
        // live global title — otherwise a quick ws switch (which flips the
        // global title mid-animation) strips the outgoing page's mask while
        // it is still fading out.
        property bool faded: false

        // Marquee seam factor: the loop's reset-to-zero moment is masked by
        // a quick fade out / in of the page (rides the opacity Behavior).
        property real reveal: 1


        // Per-page clip window: normal pages hug through the whole slot;
        // 75+-char pages pin at cap75 (the px width of the first 75 chars),
        // so the rest of the full name awaits the hover marquee.
        readonly property real windowCap: faded ? root.cap75 : root.windowWidth
        readonly property bool overflow: label.implicitWidth > windowCap
        // Slide range: carries the name left until its tail sits ~92% across
        // the window — a touch inside the reveal band's readable edge,
        // without the long overshoot creeping most of the name into view.
        readonly property real overflowWidth: Math.max(0, label.implicitWidth - windowCap * 0.92)


        readonly property bool inverted: !root.horizontal && root.Config.bar.activeWindow.inverted

        // Mask: truncated or marqueeing pages fade (each page's own
        // snapshot / overflow); fitting, un-truncated names stay crisp.
        layer.enabled: faded || overflow
        layer.effect: Mask {
            maskSource: fadeMask
        }

        anchors.horizontalCenter: root.horizontal ? undefined : icon.horizontalCenter
        anchors.verticalCenter: root.horizontal ? icon.verticalCenter : undefined
        anchors.left: root.horizontal ? icon.right : undefined
        anchors.top: root.horizontal ? undefined : icon.bottom
        anchors.leftMargin: root.horizontal ? Tokens.spacing.small : 0
        anchors.topMargin: root.horizontal ? 0 : Tokens.spacing.small

        // Hug the name until it reaches its cap (the slot normally, the
        // marquee width for 75+-char names); overshooting names pin there,
        // where the marquee and fades take over.
        width: root.horizontal ? Math.min(label.implicitWidth, windowCap) : label.implicitHeight
        height: root.horizontal ? label.implicitHeight : Math.min(label.implicitWidth, windowCap)

        // Report the window extents as implicit size: the pill's own
        // implicitWidth/implicitHeight are computed from this (the old
        // StyledText provided them itself; Items default to 0, which collapsed
        // the pill and clipped the whole window away).
        implicitWidth: width
        implicitHeight: height

        opacity: (root.current === this ? 1 : 0) * reveal

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledText {
            id: label

            // Static: flush left against the icon, showing the first 75
            // chars through the viewport; hovering walks the title left by
            // slideOffset — from flush-left, so engaging the marquee never
            // nudges the name — revealing chars 76+ past the boundary.
            x: text.overflow ? -root.slideOffset : 0
            anchors.verticalCenter: parent.verticalCenter

            width: implicitWidth
            height: implicitHeight

            text: root.windowName
            font: metrics.font
            color: root.colour
            horizontalAlignment: Text.AlignLeft

            transform: [
                Translate {
                    x: text.inverted ? -label.implicitWidth + label.implicitHeight : 0
                },
                Rotation {
                    angle: root.horizontal ? 0 : text.inverted ? 270 : 90
                    origin.x: label.implicitHeight / 2
                    origin.y: label.implicitHeight / 2
                }
            ]
        }

        Rectangle {
            id: fadeMask

            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                orientation: root.horizontal ? Gradient.Horizontal : Gradient.Vertical
                GradientStop {
                    position: 0.0
                    // Exit band: opaque at rest (crisp flush-left edge); its
                    // transparency deepens within the first ~20px of travel
                    // (~0.7s at marquee speed) — quick, but not a pop.
                    color: Qt.rgba(0, 0, 0, 1 - Math.min(1.0, root.slideOffset / Math.max(1, Math.min(20, text.overflowWidth * 0.6))))
                }
                GradientStop {
                    position: 0.07
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 0.85
                    color: Qt.rgba(0, 0, 0, 1)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0, 0, 0, 0)
                }
            }
        }
    }
}
