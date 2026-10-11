pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import M3Shapes
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

GridLayout {
    id: root

    required property int modelData
    required property int index
    required property int activeWsId
    required property int ws
    required property HyprlandMonitor monitor

    required property int displayType
    required property bool showWindows
    required property var iconRules
    required property bool horizontal
    property string activeLabel
    property string occupiedLabel
    property string label

    readonly property list<HyprlandToplevel> toplevels: Hypr.toplevelsForWs(ws, GlobalConfig.bar.workspaces.ignoredTags)
    readonly property bool isOccupied: toplevels.length > 0
    readonly property bool hasWindows: isOccupied && showWindows && Config.bar.workspaces.maxWindowIcons > 0
    readonly property bool focused: activeWsId === ws

    property color offMonitorColour: Colours.palette.m3outlineVariant
    readonly property bool onOtherMonitor: {
        if (Config.bar.workspaces.perMonitor)
            return false;
        const mon = Hypr.workspaces.values.find(w => w.id === ws)?.monitor;
        return mon && mon !== monitor;
    }
    readonly property color fgColour: {
        if (onOtherMonitor)
            return offMonitorColour;
        if (focused || isOccupied || Config.bar.workspaces.occupiedBg)
            return Colours.palette.m3onSurface;
        return Colours.layer(Colours.palette.m3outlineVariant, 2);
    }
    // Special (magic/scratchpad) workspaces render a ✦ label; Google Sans
    // lacks that glyph, so they use a symbols font that has it solid.
    readonly property bool isSpecialWs: (Hypr.workspaces.values.find(w => w.id === root.ws)?.name.startsWith("special:") ?? false)

    // Unanimated prop for others to use as reference
    readonly property int size: (horizontal ? implicitWidth : implicitHeight) + (hasWindows ? Tokens.padding.extraSmall : 0)
    // Base cell unit for the indicator overlays
    readonly property real slotSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small

    columns: horizontal ? -1 : 1
    rowSpacing: 0
    columnSpacing: 0

    Layout.alignment: horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
    Layout.preferredWidth: horizontal ? size : -1
    Layout.preferredHeight: horizontal ? -1 : size

    Behavior on Layout.preferredHeight {
        Anim {}
    }

    Behavior on Layout.preferredWidth {
        Anim {}
    }

    WsIconCacher {
        id: slotCacher
    }

    // Layer visibility for the indicator cell (ii-style: every layer persists
    // and cross-fades instead of swapping components)
    readonly property bool customShown: root.displayType === BarWorkspaceDisplay.Icons && !root.isOccupied && slotCacher.icon !== "" && !Hypr.showNumbers
    readonly property bool iconFull: root.isOccupied && !Hypr.showNumbers
    readonly property bool iconSub: root.isOccupied && Hypr.showNumbers
    readonly property bool showNum: Hypr.showNumbers || (!root.isOccupied && (root.focused || root.displayType === BarWorkspaceDisplay.Text || (root.displayType === BarWorkspaceDisplay.Icons && slotCacher.icon === "")))
    readonly property bool showDots: !showNum && !iconFull && !customShown

    Item {
        id: indicatorCell

        Layout.alignment: horizontal ? Qt.AlignVCenter | Qt.AlignHCenter : Qt.AlignHCenter | Qt.AlignVCenter
        Layout.preferredWidth: horizontal ? root.slotSize : -1
        Layout.preferredHeight: horizontal ? -1 : root.slotSize
        implicitWidth: root.slotSize
        implicitHeight: root.slotSize

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: root.slotSize

            color: root.fgColour
            scale: root.focused ? 2 / 3 : root.isOccupied ? 1 / 3 : 1 / 4
            shape: isOccupied ? MaterialShape.Square : MaterialShape.Circle
            opacity: root.showDots ? 1 : 0

            animationEasing: Tokens.anim.expressiveDefaultSpatial
            animationDuration: Tokens.anim.durations.expressiveDefaultSpatial * Tokens.anim.durations.scale

            Behavior on color {
                CAnim {}
            }

            Behavior on scale {
                Anim {}
            }

            Behavior on opacity {
                Anim {}
            }
        }

        StyledText {
            anchors.centerIn: parent
            text: {
                if (root.focused) {
                    const label = root.activeLabel;
                    if (label)
                        return label;
                }

                if (root.focused || root.isOccupied) {
                    const label = root.occupiedLabel;
                    if (label)
                        return label;
                }

                const label = root.label;
                if (label)
                    return label;

                const ws = Hypr.workspaces.values.find(w => w.id === root.ws);
                const wsName = !ws || ws.name == root.ws ? root.ws : root.isSpecialWs ? "✦" : Hypr.trimWsName(ws.name)[0];

                const capitalisation = Config.bar.workspaces.capitalisation;
                if (capitalisation === BarWorkspaceCapitalisation.Upper)
                    return String(wsName).toUpperCase();
                else if (capitalisation === BarWorkspaceCapitalisation.Lower)
                    return String(wsName).toLowerCase();
                return wsName;
            }
            // Readable on whatever is behind: pink pill only shows on
            // focused-empty slots, occupied slots sit on the dark bg pill
            // Specials stay pure white: the dynamic wallpaper scheme tints
            // onPrimary/onSurface, which can wash the glyph out.
            color: root.isSpecialWs ? "white" : root.focused && !root.isOccupied ? Colours.palette.m3onPrimary : root.fgColour
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            font.family: root.isSpecialWs ? "Noto Sans Symbols 2" : "Google Sans Flex"
            font.pointSize: Tokens.font.body.small.pointSize - 0.5
            opacity: root.showNum ? 1 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        Loader {
            anchors.centerIn: parent
            active: root.customShown
            opacity: root.customShown ? 1 : 0
            sourceComponent: iconComponent

            Behavior on opacity {
                Anim {}
            }
        }

        Item {
            // Main window icon (ii-style): full cell container, icon anchored
            // bottom-right; margins and size glide between centered-full and
            // corner-subscript, animated on every toggle
            anchors.fill: parent

            IconImage {
                id: appIcon

                readonly property var firstWindow: toplevels.length > 0 ? toplevels[0] : null

                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: root.iconFull ? (root.slotSize - root.slotSize * 0.68) / 2 : -4
                anchors.rightMargin: root.iconFull ? (root.slotSize - root.slotSize * 0.68) / 2 : -4
                implicitSize: root.iconFull ? root.slotSize * 0.68 : root.slotSize * 0.55
                width: implicitSize
                height: implicitSize
                opacity: (root.iconFull || root.iconSub) ? 1 : 0
                visible: opacity > 0
                source: firstWindow ? Icons.getAppIcon(firstWindow.lastIpcObject.class, "image-missing") : ""

                Behavior on opacity {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }

                Behavior on anchors.rightMargin {
                    Anim {}
                }

                Behavior on implicitSize {
                    Anim {}
                }
            }
        }
    }

    Component {
        id: iconComponent

        MaterialIcon {
            fill: 1
            grade: 25
            text: iconCacher.icon
            color: root.fgColour
            verticalAlignment: Qt.AlignVCenter

            WsIconCacher {
                id: iconCacher
            }
        }
    }

    Loader {
        id: windows

        asynchronous: true

        Layout.alignment: horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
        Layout.fillWidth: horizontal
        Layout.fillHeight: !horizontal
        Layout.leftMargin: horizontal ? -Tokens.sizes.bar.innerWidth / 10 : 0
        Layout.topMargin: horizontal ? 0 : -Tokens.sizes.bar.innerWidth / 10

        visible: active
        active: root.showWindows && Config.bar.workspaces.maxWindowIcons > 0

        sourceComponent: Grid {
            columns: root.horizontal ? Math.max(1, items.count) : 1
            spacing: 0

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
                    values: {
                        const windows = root.toplevels;
                        const maxIcons = Config.bar.workspaces.maxWindowIcons;
                        return maxIcons > 0 ? windows.slice(0, maxIcons) : windows;
                    }
                }

                IconImage {
                    required property var modelData

                    implicitSize: Tokens.sizes.bar.innerWidth * 0.42
                    source: Icons.getAppIcon(modelData.lastIpcObject.class, "image-missing")

                    Behavior on scale {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on x {
                        Anim {}
                    }
                }
            }
        }

        Behavior on Layout.preferredWidth {
            Anim {}
        }

        Behavior on Layout.preferredHeight {
            Anim {}
        }
    }

    component WsIconCacher: QtObject {
        id: cacher

        property string name
        readonly property string icon: Icons.matchIconRuleList(Hypr.trimWsName(name), root.iconRules)
        readonly property HyprlandWorkspace wsObj: Hypr.workspaces.values.find(w => w.id === root.ws) ?? null

        readonly property Connections conn: Connections {
            function onNameChanged(): void {
                cacher.updateName();
            }

            target: cacher.wsObj
        }

        function updateName(): void {
            if (wsObj)
                name = wsObj.name;
        }

        onWsObjChanged: updateName()
        Component.onCompleted: updateName()
    }
}