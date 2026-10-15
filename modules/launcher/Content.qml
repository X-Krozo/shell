pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services
import qs.modules.overview

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge
    readonly property bool showingGrid: !forceListView && search.text === "" && !hasTyped
    property bool hasTyped: false
    property bool swapping: false
    property bool forceListView: false

    implicitWidth: showingGrid ? grid.width + padding * 2 : listWrapper.width + padding * 2
    implicitHeight: {
        if (showingGrid) {
            const gridMaxH = root.maxHeight - search.implicitHeight - root.padding * 3;
            const cappedGridH = Math.min(grid.height, gridMaxH);
            // Paddings: top inset + grid-search gap + search bottom margin
            return search.height + cappedGridH + root.padding * 2 + search.anchors.bottomMargin;
        }
        return search.height + listWrapper.height + root.padding + search.anchors.bottomMargin;
    }

    onShowingGridChanged: {
        swapping = true;
        swapTimer.restart();
        OverviewState.open = root.screenState.launcher && showingGrid;
    }

    Timer {
        id: swapTimer
        interval: 300
        onTriggered: root.swapping = false
    }

    Behavior on implicitWidth {
        enabled: root.swapping
        Anim {}
    }
    Behavior on implicitHeight {
        enabled: root.swapping
        Anim {}
    }

    Connections {
        target: root.screenState
        function onLauncherChanged(): void {
            if (root.screenState.launcher) {
                root.hasTyped = false;
                HyprlandData.updateAll();
            }
            OverviewState.open = root.screenState.launcher && showingGrid;
        }
    }

    Item {
        id: listWrapper

        visible: !root.showingGrid
        opacity: root.showingGrid ? 0 : 1
        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    WorkspaceGrid {
        id: grid

        visible: root.showingGrid
        opacity: root.showingGrid ? 1 : 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding
        screen: root.screen
        onActivated: root.screenState.launcher = false

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Connections {
        target: root.screenState
        function onLauncherChanged(): void {
            OverviewState.open = root.screenState.launcher && root.showingGrid;
        }
    }
    IconButton {
        id: appDrawerBtn

        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.verticalCenter: search.verticalCenter
        objectName: "launcherAppDrawer"

        type: IconButton.Tonal
        isToggle: true
        isRound: true
        icon: "apps"

        checked: root.forceListView
        onClicked: {
            root.forceListView = !root.forceListView;
            root.hasTyped = false;
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: appDrawerBtn.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.leftMargin: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: root.showingGrid
            ? qsTr("Type to search for apps, press Space to browse · Backspace to return to grid")
            : qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onTextChanged: {
            if (text.length > 0)
                root.hasTyped = true;
        }

        onAccepted: {
            if (root.showingGrid) return;
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()
        Keys.onLeftPressed: {
            if (list.showWallpapers)
                list.currentList?.decrementCurrentIndex();
        }
        Keys.onRightPressed: {
            if (list.showWallpapers)
                list.currentList?.incrementCurrentIndex();
        }

        Keys.onEscapePressed: {
            // Scoped close-all: only fires while this surface owns focus,
            // so apps keep Esc everywhere else.
            root.screenState.session = false;
            root.screenState.launcher = false;
            root.screenState.dashboard = false;
            root.screenState.sidebar = false;
            root.screenState.osd = false;
            root.screenState.utilities = false;
            root.screenState.appVolumes = false;
            root.screenState.nexus = false;
            root.screenState.mediaFullscreen = false;
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Backspace && search.text.length === 0 && root.hasTyped) {
                root.hasTyped = false;
                event.accepted = true;
                return;
            }

            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
