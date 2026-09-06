import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
    id: root
    property var shell: null
    readonly property var library: shell ? shell.appLibrary : null
    signal toggleRequested(string screenName)
    signal closeRequested()
    property var panels: []

    IpcHandler {
        target: "local.desktop-apps"
        function toggle(screenName: string): void { root.toggleRequested(screenName) }
        function close(): void { root.closeRequested() }
        function status(): string {
            return JSON.stringify({ ready: !!root.library, apps: root.library ? root.library.sortedEntries("").length : 0, screens: root.panels.map(p => ({name: p.modelData.name, revealed: p.revealed, expanded: p.expanded})) })
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            property bool expanded: false
            property bool revealed: false
            property var entries: []
            screen: modelData
            anchors.bottom: true
            margins.bottom: 0
            implicitWidth: Math.min(420, modelData.width - 32)
            implicitHeight: Math.min(472, modelData.height - 48)
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "local-desktop-apps"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: Region { item: hoverZone }

            Item {
                id: hoverZone
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: panel.revealed ? surface.width : 184
                height: panel.revealed ? surface.height + 12 : 8
            }
            HoverHandler {
                id: dockHover
                blocking: false
                onHoveredChanged: {
                    if (hovered) {
                        hideTimer.stop()
                        panel.revealed = true
                    } else hideTimer.restart()
                }
            }
            Timer {
                id: hideTimer
                interval: 450
                onTriggered: if (!dockHover.hovered && !panel.expanded) panel.revealed = false
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 4; radius: 2
                color: Color.accent
                opacity: panel.revealed ? 0 : 0.65
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            function refresh() {
                entries = root.library ? root.library.sortedEntries(search.text) : []
                grid.positionViewAtBeginning()
            }
            function toggle() { expanded = !expanded }
            onExpandedChanged: {
                if (expanded) {
                    revealed = true
                    hideTimer.stop()
                    if (root.library) root.library.refreshIcons()
                    refresh()
                } else {
                    search.text = ""
                    search.focus = false
                    hideTimer.restart()
                }
            }
            Connections {
                target: root
                function onToggleRequested(screenName) {
                    if (screenName === panel.modelData.name) panel.toggle()
                }
                function onCloseRequested() { panel.expanded = false }
                function onLibraryChanged() { panel.refresh() }
            }
            Connections {
                target: root.library
                function onAppsChanged() { panel.refresh() }
            }
            Component.onCompleted: {
                root.panels = root.panels.concat([panel])
                refresh()
            }
            Component.onDestruction: root.panels = root.panels.filter(p => p !== panel)

            Rectangle {
                id: surface
                anchors.bottom: parent.bottom
                anchors.bottomMargin: panel.revealed ? 12 : -76
                anchors.horizontalCenter: parent.horizontalCenter
                width: panel.expanded ? panel.width : 184
                height: panel.expanded ? panel.height - 12 : 64
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                radius: 28
                color: Color.background
                border.color: Color.accent
                border.width: 1
                clip: true
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                Item {
                    anchors.fill: parent
                    opacity: panel.expanded ? 0 : 1
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    Grid {
                        x: 22
                        y: 16
                        columns: 3
                        spacing: 5
                        scale: tileMouse.pressed ? 0.9 : (tileMouse.containsMouse ? 1.1 : 1)
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Repeater {
                            model: 9
                            Rectangle { width: 7; height: 7; radius: 2; color: Color.foreground }
                        }
                    }
                    Text {
                        x: 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Apps   ⌃"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: 14
                    }
                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        enabled: !panel.expanded
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.role: Accessible.Button
                        Accessible.name: "Open app drawer"
                        onClicked: panel.toggle()
                    }
                }

                Item {
                    width: panel.width
                    height: panel.height - 12
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: panel.expanded ? 1 : 0
                    visible: opacity > 0
                    enabled: panel.expanded
                    Behavior on opacity { NumberAnimation { duration: 230 } }
                    Keys.onEscapePressed: panel.expanded = false

                    Text {
                        x: 20; y: 18
                        text: "Your apps"
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        width: 32; height: 32
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 12
                        radius: 16
                        color: closeMouse.containsMouse ? Color.accent : "transparent"
                        Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 24; color: closeMouse.containsMouse ? Color.background : Color.foreground }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            Accessible.role: Accessible.Button
                            Accessible.name: "Close app drawer"
                            onClicked: panel.expanded = false
                        }
                    }
                    Rectangle {
                        x: 16; y: 58
                        width: parent.width - 32; height: 36
                        radius: 12
                        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.margins: 10
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: 13
                            selectByMouse: true
                            clip: true
                            onTextChanged: panel.refresh()
                            Keys.onEscapePressed: panel.expanded = false
                            Text {
                                visible: !search.text && !search.activeFocus
                                text: "Search apps…"
                                color: Color.muted
                                font: search.font
                            }
                        }
                    }
                    GridView {
                        id: grid
                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 108
                        anchors.bottomMargin: 38
                        cellWidth: width / 4
                        cellHeight: 92
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: panel.entries
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        delegate: Item {
                            id: appCell
                            required property var modelData
                            width: grid.cellWidth
                            height: grid.cellHeight
                            readonly property var entry: modelData.entry
                            readonly property string appName: root.library ? root.library.entryName(entry) : ""
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 16
                                color: Color.accent
                                opacity: appMouse.containsMouse ? 0.15 : 0
                            }
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 10
                                width: 38; height: 38
                                sourceSize.width: 76; sourceSize.height: 76
                                source: root.library ? root.library.iconSource(appCell.entry.icon) : ""
                                fillMode: Image.PreserveAspectFit
                            }
                            Text {
                                x: 4; y: 55
                                width: parent.width - 8
                                text: appCell.appName
                                color: Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: 11
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                            MouseArea {
                                id: appMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                Accessible.role: Accessible.Button
                                Accessible.name: appCell.appName
                                onClicked: {
                                    if (root.library) root.library.launch(appCell.entry.id, appCell.appName)
                                    panel.expanded = false
                                }
                            }
                            ToolTip.visible: appMouse.containsMouse
                            ToolTip.delay: 650
                            ToolTip.text: appCell.appName
                        }
                    }
                    Text {
                        visible: panel.entries.length === 0
                        anchors.centerIn: grid
                        text: root.library ? "No matching apps" : "Loading apps…"
                        color: Color.muted
                        font.pixelSize: 14
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 14
                        text: panel.entries.length + " apps · scroll to browse"
                        color: Color.muted
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
