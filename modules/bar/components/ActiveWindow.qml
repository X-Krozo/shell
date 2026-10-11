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

    readonly property string windowTitle: {
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
        // Cap length; Title fades the tail edge (see fadeMask below)
        return name.length > 75 ? name.slice(0, 75) : name;
    }

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

    clip: true
    implicitWidth: horizontal ? icon.implicitWidth + current.implicitWidth + current.anchors.leftMargin : Math.max(icon.implicitWidth, current.implicitHeight)
    implicitHeight: horizontal ? Math.max(icon.implicitHeight, current.implicitHeight) : icon.implicitHeight + current.implicitWidth + current.anchors.topMargin

    Loader {
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
    }

    Title {
        id: text2
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: root.maxSize - (root.horizontal ? icon.width + root.current.anchors.leftMargin : icon.height)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        enabled: root.horizontal

        Anim {}
    }

    component Title: StyledText {
        id: text

        // Fade the tail edge when the name was capped at 75 chars.
        // Local coords, so it follows the rotation for vertical bars.
        layer.enabled: root.windowTitle.length >= 75
        layer.effect: Mask {
            maskSource: fadeMask
        }

        anchors.horizontalCenter: root.horizontal ? undefined : icon.horizontalCenter
        anchors.verticalCenter: root.horizontal ? icon.verticalCenter : undefined
        anchors.left: root.horizontal ? icon.right : undefined
        anchors.top: root.horizontal ? undefined : icon.bottom
        anchors.leftMargin: root.horizontal ? Tokens.spacing.small : 0
        anchors.topMargin: root.horizontal ? 0 : Tokens.spacing.small

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0
        horizontalAlignment: Text.AlignLeft

        transform: [
            Translate {
                x: !root.horizontal && root.Config.bar.activeWindow.inverted ? -text.implicitWidth + text.implicitHeight : 0
            },
            Rotation {
                angle: root.horizontal ? 0 : root.Config.bar.activeWindow.inverted ? 270 : 90
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        width: root.horizontal ? implicitWidth : implicitHeight
        height: root.horizontal ? implicitHeight : implicitWidth

        Rectangle {
            id: fadeMask

            anchors.fill: parent
            visible: false
            layer.enabled: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
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

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
