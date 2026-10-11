pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property HyprlandMonitor monitor
    required property bool horizontal

    readonly property int activeSpecialId: monitor?.lastIpcObject.specialWorkspace?.id ?? 0
    readonly property var wsIds: {
        const allMonitors = !Config.bar.workspaces.perMonitor;
        return Hypr.workspaces.values.filter(w => w.name.startsWith("special:") && (allMonitors || w.monitor === root.monitor)).map(w => w.id);
    }

    GridLayout {
        id: layout

        anchors.centerIn: parent
        columns: root.horizontal ? -1 : 1
        rowSpacing: Math.floor(Tokens.spacing.small)
        columnSpacing: Math.floor(Tokens.spacing.small)

        Repeater {
            id: workspaces

            model: ScriptModel {
                values: root.wsIds
            }

            delegate: Workspace {
                activeWsId: root.activeSpecialId
                ws: modelData
                monitor: root.monitor
                horizontal: root.horizontal
                offMonitorColour: Colours.palette.m3outline
                displayType: Config.bar.workspaces.specialDisplayType
                showWindows: Config.bar.workspaces.showWindowsOnSpecialWorkspaces
                iconRules: GlobalConfig.bar.workspaces.specialWorkspaceIcons
            }
        }
    }

    Loader {
        asynchronous: true
        anchors.horizontalCenter: root.horizontal ? undefined : parent.horizontalCenter
        anchors.verticalCenter: root.horizontal ? parent.verticalCenter : undefined
        active: Config.bar.workspaces.activeIndicator

        sourceComponent: ActiveIndicator {
            activeWsId: root.activeSpecialId
            workspaces: workspaces
            mask: layout
            horizontal: root.horizontal

            indicatorColour: Colours.palette.m3tertiary
            contentColour: Colours.palette.m3onTertiary
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: layout
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            const ws = (layout.childAt(event.x, event.y) as Workspace)?.ws; // qmllint disable incompatible-type
            if (ws) {
                const match = Hypr.workspaces.values.find(w => w.id === ws);
                if (match)
                    Hypr.toggleSpecial(Hypr.trimWsName(match.name));
                else
                    Hypr.toggleSpecial("special");
            } else {
                Hypr.toggleSpecial("special");
            }
        }
    }
}