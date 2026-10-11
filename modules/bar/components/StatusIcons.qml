pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.components.status

StyledRect {
    id: root

    required property bool horizontal

    property color colour: Colours.palette.m3secondary
    readonly property alias items: iconColumn

    transformOrigin: Item.Center
    scale: bar.hoveredEntry === "statusIcons" ? 1.06 : 1

    Behavior on scale {
        Anim {}
    }

    readonly property int spacing: Tokens.spacing.medium / 2

    // Index of the first/last entry that isn't collapsed, for edge margin gating
    readonly property int firstPresent: {
        const values = model.values;
        for (let i = 0; i < values.length; i++)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }
    readonly property int lastPresent: {
        const values = model.values;
        for (let i = values.length - 1; i >= 0; i--)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }

    // Entries that can shrink to nothing, spacing included
    function collapsed(entry: var): bool {
        if (entry.id === "lockStatus")
            return !Hypr.capsLock && !Hypr.numLock;
        return false;
    }

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    clip: true
    implicitWidth: horizontal ? iconColumn.implicitWidth + Tokens.padding.medium * 2 : Tokens.sizes.bar.innerWidth
    implicitHeight: horizontal ? Tokens.sizes.bar.innerWidth : iconColumn.implicitHeight + Tokens.padding.medium * 2

    GridLayout {
        id: iconColumn

        // Only one orientation's anchors resolve, the others are undefined
        // qmllint disable Quick.anchor-combinations
        anchors.left: horizontal ? undefined : parent.left
        anchors.right: horizontal ? undefined : parent.right
        anchors.bottom: horizontal ? undefined : parent.bottom
        anchors.horizontalCenter: horizontal ? parent.horizontalCenter : undefined
        anchors.verticalCenter: horizontal ? parent.verticalCenter : undefined
        anchors.bottomMargin: horizontal ? 0 : Tokens.padding.medium
        // qmllint enable Quick.anchor-combinations

        columns: horizontal ? -1 : 1
        rowSpacing: spacing
        columnSpacing: spacing

        Repeater {
            model: ScriptModel {
                id: model

                values: root.Config.bar.statusIcons.values.filter(e => e.enabled)
            }

            DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "lockStatus"
                    delegate: EntryWrapper {
                        LockStatus {
                            colour: root.colour
                            parentSpacing: root.spacing
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "audio"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2

                        MaterialIcon {
                            animate: true
                            text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "microphone"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2
                        name: "audio" // Mic opens audio popout

                        MaterialIcon {
                            animate: true
                            text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "kbLayout"
                    delegate: EntryWrapper {
                        StyledText {
                            animate: true
                            text: Hypr.kbLayout
                            color: root.colour
                            font: Tokens.font.mono.medium
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "network"
                    delegate: EntryWrapper {
                        MaterialIcon {
                            animate: true
                            text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                            color: root.colour
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: EntryWrapper {
                        BluetoothStatus {
                            colour: root.colour
                            horizontal: root.horizontal
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "battery"
                    delegate: EntryWrapper {
                        BatteryStatus {
                            colour: root.colour
                        }
                    }
                }
            }
        }
    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        property int margin: root.spacing / 2
        readonly property bool present: !root.collapsed(modelData)
        property real topGap: !horizontal && present && index !== root.firstPresent ? margin : 0
        property real bottomGap: !horizontal && present && index !== root.lastPresent ? margin : 0
        property real leftGap: horizontal && present && index !== root.firstPresent ? margin : 0
        property real rightGap: horizontal && present && index !== root.lastPresent ? margin : 0
        default property Item item
        property string name: modelData.id.toLowerCase()

        Layout.alignment: horizontal ? Qt.AlignVCenter : Qt.AlignHCenter
        Layout.topMargin: Math.round(topGap)
        Layout.bottomMargin: Math.round(bottomGap)
        Layout.leftMargin: Math.round(leftGap)
        Layout.rightMargin: Math.round(rightGap)

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item

        MouseArea {
            anchors.fill: parent
            z: 1000
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            propagateComposedEvents: true
            cursorShape: Qt.PointingHandCursor
            onClicked: event => {
                const pos = mapToItem(root, event.x, event.y);
                if (geometry.barContains(pos.x, pos.y))
                    bar.togglePopout(geometry.axisPos(pos.x, pos.y));
            }
        }

        Behavior on topGap {
            Anim {
                type: Anim.SlowEffects
            }
        }

        Behavior on bottomGap {
            Anim {
                type: Anim.SlowEffects
            }
        }

        Behavior on leftGap {
            Anim {
                type: Anim.SlowEffects
            }
        }

        Behavior on rightGap {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
}
