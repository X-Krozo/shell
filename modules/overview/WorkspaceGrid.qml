pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.components
import qs.services
import qs.utils

Item {
    id: root
    required property ShellScreen screen
    signal activated()

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property var monData: monitor?.lastIpcObject ?? null
    readonly property string activeSpecial: monitor?.lastIpcObject.specialWorkspace?.name ?? ""
    readonly property bool onSpecial: activeSpecial !== ""
    readonly property real monScale: monData?.scale ?? 1
    readonly property var reserved: monData?.reserved ?? [0, 0, 0, 0] // [left, top, right, bottom]
    readonly property real logicalWidth: ((monData?.width ?? screen.width) - reserved[0] - reserved[2]) / monScale
    readonly property real logicalHeight: ((monData?.height ?? screen.height) - reserved[1] - reserved[3]) / monScale
    readonly property int activeWsId: Math.max(1, Math.min(100, Hypr.activeWsId))
    readonly property int perPage: OverviewState.rows * OverviewState.columns
    readonly property int perPageRegular: perPage - 1
    readonly property int page: Math.floor((activeWsId - 1) / perPageRegular)
    readonly property real cardSpacing: Tokens.spacing.extraSmall
    readonly property real cardWidth: logicalWidth * OverviewState.zoomW
    readonly property real cardHeight: logicalHeight * OverviewState.zoomH

    implicitWidth: OverviewState.columns * cardWidth + (OverviewState.columns - 1) * cardSpacing + 2 * padding
    implicitHeight: OverviewState.rows * cardHeight + (OverviewState.rows - 1) * cardSpacing + 2 * padding
    readonly property real padding: Tokens.padding.extraSmall

    function wsAtCell(rowIndex: int, colIndex: int): int {
        if (rowIndex === OverviewState.rows - 1 && colIndex === OverviewState.columns - 1)
            return -1;
        return page * perPageRegular + rowIndex * OverviewState.columns + colIndex + 1;
    }
    function wsCol(wsId: int): int {
        return Math.floor((wsId - 1) % perPageRegular) % OverviewState.columns;
    }
    function wsRow(wsId: int): int {
        return Math.floor(Math.floor((wsId - 1) % perPageRegular) / OverviewState.columns);
    }

    // Drop-target tracking via card DropAreas
    property int dragTargetWs: -2
    property var swapLocks: ({})

    function clearSwapLock(addr: string): void {
        delete root.swapLocks[addr];
    }

    function lockSwap(a: string, expectedAtA: var, b: string, expectedAtB: var): void {
        root.swapLocks[a] = expectedAtA;
        root.swapLocks[b] = expectedAtB;
        staleLockTimer.restart();
    }


    Timer {
        id: staleLockTimer

        interval: 1500
        onTriggered: root.swapLocks = {}
    }
    // Magic (special) workspace card is the bottom-right cell (wsValue -1); -2 = no valid drop target
    readonly property int magicWsValue: -1
    readonly property int nowhereWsValue: -2



    // Corner radius
    function cellRadius(rowIdx: int, colIdx: int, topLeft: bool, topRight: bool, bottomLeft: bool, bottomRight: bool): real {
        const outer = Tokens.rounding.large;
        const inner = Tokens.rounding.small;
        if (topLeft)
            return (rowIdx === 0 && colIdx === 0) ? outer : inner;
        if (topRight)
            return (rowIdx === 0 && colIdx === OverviewState.columns - 1) ? outer : inner;
        if (bottomLeft)
            return (rowIdx === OverviewState.rows - 1 && colIdx === 0) ? outer : inner;
        if (bottomRight)
            return (rowIdx === OverviewState.rows - 1 && colIdx === OverviewState.columns - 1) ? outer : inner;
        return inner;
    }

    // Workspace cards
    StyledRect {
        id: cards

        anchors.centerIn: parent
        width: root.implicitWidth - 2 * root.padding
        height: root.implicitHeight - 2 * root.padding
        radius: Tokens.rounding.extraLarge
        color: "transparent"

        Repeater {
            model: OverviewState.rows * OverviewState.columns

            delegate: StyledRect {
                id: card

                required property int index
                readonly property int rowIdx: Math.floor(index / OverviewState.columns)
                readonly property int colIdx: index % OverviewState.columns
                readonly property int wsValue: root.wsAtCell(rowIdx, colIdx)
                readonly property bool isSpecial: wsValue === -1
                readonly property bool isActive: isSpecial ? root.onSpecial : wsValue === root.activeWsId
                readonly property bool isDropTarget: root.dragTargetWs === wsValue

                x: colIdx * (root.cardWidth + root.cardSpacing)
                y: rowIdx * (root.cardHeight + root.cardSpacing)
                width: root.cardWidth
                height: root.cardHeight
                radius: Tokens.rounding.small
                topLeftRadius: root.cellRadius(rowIdx, colIdx, true, false, false, false)
                topRightRadius: root.cellRadius(rowIdx, colIdx, false, true, false, false)
                bottomLeftRadius: root.cellRadius(rowIdx, colIdx, false, false, true, false)
                bottomRightRadius: root.cellRadius(rowIdx, colIdx, false, false, false, true)
                color: isDropTarget ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerLow
                // No active border here — the gliding indicator above is the single source
                border.width: isDropTarget ? 2 : 0
                border.color: Colours.palette.m3secondary

                Behavior on border.color {
                    CAnim {}
                }

                StyledText {
                    visible: !card.isSpecial
                    anchors.centerIn: parent
                    text: parent.wsValue
                    color: Colours.palette.m3outlineVariant
                    font.pointSize: parent.height * 0.4
                    font.weight: Font.DemiBold

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                MaterialIcon {
                    visible: card.isSpecial
                    anchors.centerIn: parent
                    text: "✦︎"
                    fill: 1
                    color: Colours.palette.m3outlineVariant
                    font.pointSize: parent.height * 0.35
                }

                StateLayer {
                    id: hover

                    radius: Tokens.rounding.small

                    function clickAction(): void {
                        if (card.isSpecial)
                            Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("magic")' : 'togglespecialworkspace magic');
                        else
                            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${card.wsValue} })` : `workspace ${card.wsValue}`);
                        root.activated();
                    }
                    onClicked: event => {
                        if (event.button === Qt.LeftButton)
                            clickAction();
                    }
                }

                DropArea {
                    anchors.fill: parent

                    onEntered: drag => root.dragTargetWs = card.wsValue
                    onExited: () => {
                        if (root.dragTargetWs === card.wsValue)
                            root.dragTargetWs = -2;
                    }
                }
            }
        }
    }

    // Looks up the preview delegate for an address (used to apply swap geometry instantly)
    function previewByAddress(addr: string): WindowPreview {
        for (let i = 0; i < windowSpace.data.length; ++i) {
            const w = windowSpace.data[i];
            if (typeof w?.address === "string" && w.address === addr)
                return w;
        }
        return null;
    }

    // Reordering helper: returns the address of the first tiled preview.
    function windowAddressAt(x: real, y: real, curWs: int, exceptAddress: string): string {
        let found = "";
        for (let i = 0; i < windowSpace.data.length; ++i) {
            const w = windowSpace.data[i];
            if (typeof w?.address !== "string")
                continue;
            const wsName = w.ipc?.workspace?.name ?? "";
            if (wsName.startsWith("special:"))
                continue;
            if ((w.ipc?.workspace?.id ?? -1) !== curWs)
                continue;
            if (w.address === exceptAddress || w.address === "")
                continue;
            if (w.ipc?.floating)
                continue;
            if (x >= w.x && x <= w.x + w.width && y >= w.y && y <= w.y + w.height)
                found = w.address;
        }
        return found;
    }

    // Live window previews positioned over the cards
    Item {
        id: windowSpace

        anchors.centerIn: parent
        width: cards.width
        height: cards.height

        Repeater {
            id: previews

            model: ScriptModel {
                values: {
                    const start = root.page * root.perPageRegular;
                    return Hypr.toplevels.values.filter(t => {
                        const addr = t.lastIpcObject?.address ?? t.address ?? "";
                        const clean = String(addr).replace(/^0x/i, "").toLowerCase();
                        const w = HyprlandData.windowByAddress[addr] ?? HyprlandData.windowByAddress[clean] ?? HyprlandData.windowByAddress["0x" + clean] ?? t.lastIpcObject;
                        if (!w || w.hidden)
                            return false;
                        const ws = w.workspace ?? t.workspace;
                        if (!ws)
                            return false;
                        if ((ws.name ?? "").startsWith("special:"))
                            return true;
                        const wsId = ws.id;
                        if (wsId < start + 1 || wsId > start + root.perPageRegular)
                            return false;
                        return true;
                    });
                }
            }

            delegate: WindowPreview {
                id: preview

                required property var modelData

                toplevel: modelData
                windowData: {
                    const addr = modelData?.lastIpcObject?.address ?? modelData?.address ?? "";
                    const clean = String(addr).replace(/^0x/i, "").toLowerCase();
                    return HyprlandData.windowByAddress[addr] ?? HyprlandData.windowByAddress[clean] ?? HyprlandData.windowByAddress["0x" + clean] ?? modelData?.lastIpcObject ?? null;
                }
                grid: root
                monData: root.monData
                reserved: root.reserved
                dimmed: ((windowData?.monitor ?? modelData.lastIpcObject?.monitor ?? monData?.id) !== monData?.id)

                onWindowDataChanged: {
                    const g = preview.grid;
                    const expectedAt = g?.swapLocks?.[preview.address];
                    if (expectedAt) {
                        const freshAt = preview.windowData?.at;
                        if (Array.isArray(freshAt) && Math.abs((freshAt[0] ?? -1) - expectedAt[0]) <= 1 && Math.abs((freshAt[1] ?? -1) - expectedAt[1]) <= 1) {
                            const newLocks = Object.assign({}, g.swapLocks);
                            delete newLocks[preview.address];
                            g.swapLocks = newLocks;
                        } else {
                            return;
                        }
                        // IMMED already set correct geometry — do NOT call computeTarget()
                        // here: the ipc binding can read stale data in this event and would
                        // recompute the tiles back to their old slots, undoing the swap.
                        return;
                    }
                    // Pass the freshly changed object explicitly: reading root.ipc inside
                    // this handler still returns the PREVIOUS event's data (the ipc binding
                    // is evaluated one tick behind windowDataChanged), which would
                    // recompute the tile back to its old spot after a float/unfloat.
                    preview.computeTarget(preview.windowData);
                }
                Component.onCompleted: preview.computeTarget()
            }
        }
    }

    // Active workspace indicator drawn above previews
    StyledRect {
        id: activeBorder

        anchors.centerIn: parent
        width: cards.width
        height: cards.height
        color: "transparent"

        readonly property int rowIdx: root.onSpecial ? OverviewState.rows - 1 : root.wsRow(root.activeWsId)
        readonly property int colIdx: root.onSpecial ? OverviewState.columns - 1 : root.wsCol(root.activeWsId)

        Rectangle {
            x: parent.colIdx * (root.cardWidth + root.cardSpacing)
            y: parent.rowIdx * (root.cardHeight + root.cardSpacing)
            width: root.cardWidth
            height: root.cardHeight
            radius: Tokens.rounding.small
            topLeftRadius: root.cellRadius(parent.rowIdx, parent.colIdx, true, false, false, false)
            topRightRadius: root.cellRadius(parent.rowIdx, parent.colIdx, false, true, false, false)
            bottomLeftRadius: root.cellRadius(parent.rowIdx, parent.colIdx, false, false, true, false)
            bottomRightRadius: root.cellRadius(parent.rowIdx, parent.colIdx, false, false, false, true)
            color: "transparent"
            border.width: 2
            border.color: Colours.palette.m3primary

            Behavior on x {
                NumberAnimation {
                    duration: 200
                    easing: Tokens.anim.expressiveDefaultEffects
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: 200
                    easing: Tokens.anim.expressiveDefaultEffects
                }
            }
            Behavior on topLeftRadius {
                NumberAnimation {
                    duration: 400
                    easing: Tokens.anim.emphasizedDecel
                }
            }
            Behavior on topRightRadius {
                NumberAnimation {
                    duration: 400
                    easing: Tokens.anim.emphasizedDecel
                }
            }
            Behavior on bottomLeftRadius {
                NumberAnimation {
                    duration: 400
                    easing: Tokens.anim.emphasizedDecel
                }
            }
            Behavior on bottomRightRadius {
                NumberAnimation {
                    duration: 400
                    easing: Tokens.anim.emphasizedDecel
                }
            }
            Behavior on border.color {
                CAnim {}
            }
        }
    }
}
