pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    required property bool horizontal
    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.medium : Tokens.spacing.extraSmall

    property bool expanded

    // Edge-zoom, X axis only (see Workspaces.qml): the pill's left and right
    // edges slide outward on hover while the top and bottom never move, so it
    // can't read as a rise. The Grid and expand chevron cancel the X factor.
    property real zoom: bar.hoveredEntry === "tray" ? 1.06 : 1

    Behavior on zoom {
        Anim {}
    }

    transform: Scale {
        xScale: root.zoom
        yScale: 1
        origin.x: root.width / 2
        origin.y: root.height / 2
    }

    readonly property real nonAnimWidth: {
        if (!horizontal)
            return Tokens.sizes.bar.innerWidth;
        if (!Config.bar.tray.compact)
            return layout.implicitWidth + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitWidth + layout.implicitWidth + spacing + pad;
        return Math.max(Config.bar.tray.background ? height : 0, expandIcon.implicitWidth + pad);
    }
    readonly property real nonAnimHeight: {
        if (horizontal)
            return Tokens.sizes.bar.innerWidth;
        if (!Config.bar.tray.compact)
            return layout.implicitHeight + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitHeight + layout.implicitHeight + spacing + pad;
        return Math.max(Config.bar.tray.background ? width : 0, expandIcon.implicitHeight + pad);
    }

    clip: true
    visible: horizontal ? width > 0 : height > 0

    implicitWidth: horizontal ? nonAnimWidth : Tokens.sizes.bar.innerWidth
    implicitHeight: horizontal ? Tokens.sizes.bar.innerWidth : nonAnimHeight

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    Grid {
        id: layout

        // Cancel the root's X-only edge zoom (see Workspaces.qml): net X = 1
        // and Y = 1 every frame, so tray pixmaps are never resampled; only
        // the pill background scales. The Grid is edge-anchored, so the
        // inverse pivot is the root's centre mapped into this Grid's coords.
        transform: Scale {
            xScale: 1 / root.zoom
            yScale: 1
            origin.x: root.width / 2 - layout.x
            origin.y: root.height / 2 - layout.y
        }

        anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
        anchors.top: root.horizontal ? undefined : parent.top
        anchors.left: root.horizontal ? parent.left : undefined
        anchors.topMargin: root.horizontal ? 0 : root.padding
        anchors.leftMargin: root.horizontal ? root.padding : 0
        columns: root.horizontal ? Math.max(1, items.count) : 1
        spacing: Tokens.spacing.small

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

        Loader {
            id: expandIcon

            asynchronous: true

            // Same X-only inverse-zoom cancel as the Grid above, pivoted at
            // the root centre so the chevron stays pixel-crisp while the pill
            // grows.
            transform: Scale {
                xScale: 1 / root.zoom
                yScale: 1
                origin.x: root.width / 2 - expandIcon.x
                origin.y: root.height / 2 - expandIcon.y
            }

            anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
        anchors.right: root.horizontal ? parent.right : undefined
        anchors.bottom: root.horizontal ? undefined : parent.bottom

        active: Config.bar.tray.compact && items.count > 0

        sourceComponent: Item {
            implicitWidth: root.horizontal ? expandIconInner.implicitWidth - Tokens.padding.small : expandIconInner.implicitWidth
            implicitHeight: root.horizontal ? expandIconInner.implicitHeight : expandIconInner.implicitHeight - Tokens.padding.small

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
                anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
                anchors.right: root.horizontal ? parent.right : undefined
                anchors.bottom: root.horizontal ? undefined : parent.bottom
                anchors.rightMargin: root.horizontal ? (Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small) : 0
                anchors.bottomMargin: root.horizontal ? 0 : Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small
                text: "expand_less"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                rotation: (root.horizontal ? 270 : 0) + (root.expanded ? 180 : 0)

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    Anim {}
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: event => {
                        if (event.button === Qt.RightButton) {
                            if (expandIconInner.contextMenu)
                                expandIconInner.contextMenu.open();
                        } else {
                            root.expanded = !root.expanded;
                        }
                    }
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        enabled: root.horizontal

        Anim {}
    }
}
