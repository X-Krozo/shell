pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components.effects
import qs.services
import qs.utils

MouseArea {
    id: root

    required property SystemTrayItem modelData

    // Tray indicators that ignore the standard Activate call, keyed by item
    // title: focus the app window when it exists, otherwise launch the app.
    readonly property var openRules: ({
        "tauonmb": { match: "tauonmb", launch: ["tauonmb"] }
    })

    function openOrFocus(): void {
        const rule = openRules[modelData.title];
        if (!rule) {
            modelData.activate();
            return;
        }
        const win = Hypr.toplevels.values.find(t => t.lastIpcObject?.class === rule.match);
        if (win)
            win.activate();
        else
            Quickshell.execDetached(rule.launch);
    }

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    implicitWidth: Tokens.font.body.small.pointSize * 2
    implicitHeight: Tokens.font.body.small.pointSize * 2

    onClicked: event => {
        if (event.button === Qt.LeftButton) {
            root.openOrFocus();
        } else {
            // Shell-rendered menu is the primary path; use the app's own
            // secondary action only when it has no menu to show.
            if (!modelData.hasMenu)
                modelData.secondaryActivate();
            const p = root.mapToItem(bar, root.width / 2, root.height / 2);
            bar.togglePopout(bar.horizontal ? p.x : p.y);
        }
    }

    ColouredIcon {
        id: icon

        anchors.fill: parent
        source: Icons.getTrayIcon(root.modelData.id, root.modelData.icon)
        colour: Colours.palette.m3secondary
        layer.enabled: Config.bar.tray.recolour
    }
}
