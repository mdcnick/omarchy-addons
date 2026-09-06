import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var stats: ({})
    property var history: ({cpu: [], ram: [], disk: [], net: []})
    property real lastSample: 0
    property bool fresh: false
    property var activeCard: null
    property var palette: ({})
    readonly property color themeBackground: palette.background || "#1a1b26"
    readonly property color themeText: palette.foreground || "#a9b1d6"
    readonly property color themeMuted: palette.light_foreground || palette.foreground || "#a9b1d6"
    readonly property color themeAccent: palette.accent || "#7aa2f7"
    readonly property color themeGreen: palette.green || "#9ece6a"
    readonly property color themeYellow: palette.yellow || "#e0af68"
    function tint(color, alpha) { return Qt.rgba(color.r, color.g, color.b, alpha); }
    function readPalette(text) {
        const next = {};
        for (const line of text.split("\n")) {
            const match = line.match(/^\s*([a-z_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["']/);
            if (match) next[match[1]] = match[2];
        }
        palette = next;
    }
    FileView {
        id: themeFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/theme/colors.toml"
        watchChanges: true
        onLoaded: root.readPalette(text())
        onFileChanged: reload()
    }
    // Reload also follows theme-directory symlink replacements.
    Timer { interval: 5000; running: true; repeat: true; onTriggered: themeFile.reload() }
    readonly property var targetScreen: {
        const screens = Quickshell.screens.slice().sort((a, b) => a.x - b.x || a.y - b.y);
        return screens.find(s => s.name === (Quickshell.env("RESOURCE_MONITOR") || "HDMI-A-1")) || (screens.length ? screens[Math.floor(screens.length / 2)] : null);
    }
    onTargetScreenChanged: activeCard = null

    function accept(data) {
        stats = data;
        lastSample = Date.now();
        fresh = true;
        const next = {};
        for (const key of ["cpu", "ram", "disk", "net"]) {
            const value = key === "disk" ? data.diskRate : key === "net" ? data.netRate : data[key];
            next[key] = (history[key] || []).concat([value || 0]).slice(-30);
        }
        history = next;
    }
    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: root.fresh = sampler.running && Date.now() - root.lastSample < 7000
    }
    Process {
        id: sampler
        command: ["python3", "-u", Qt.resolvedUrl("metrics.py").toString().replace("file://", "")]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                try { root.accept(JSON.parse(line)); } catch (error) { console.warn(error); }
            }
        }
    }
    PanelWindow {
        visible: root.targetScreen !== null
        screen: root.targetScreen
        anchors { top: true; left: true; right: true }
        implicitHeight: 36
        color: "transparent"
        exclusionMode: ExclusionMode.Auto
        WlrLayershell.namespace: "system-resources-strip"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        ResourceSurface {
            width: Math.min(parent.width, 760)
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    component ResourceSurface: Item {
            id: surface
            clip: true
            property bool showHeader: height >= 115 && width >= 280
            property int pad: width < 160 || height < 55 ? 2 : 8
            Text {
                visible: surface.showHeader
                x: 12; y: 9
                text: "SYSTEM RESOURCES"
                color: root.themeText; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
            }
            Item {
                id: cards
                x: surface.pad
                y: surface.showHeader ? 28 : surface.pad
                width: Math.max(0, surface.width - surface.pad * 2)
                height: Math.max(0, Math.min(120, surface.height - y - surface.pad))
                property int columns: width < 210 && height > 65 ? 2 : 4
                property int rows: columns === 2 ? 2 : 1
                property int gap: width < 240 ? 2 : 6
                Repeater {
                    model: ["cpu", "ram", "disk", "net"]
                    ResourceCard {
                        required property int index
                        required property string modelData
                        kind: modelData
                        x: (index % cards.columns) * (width + cards.gap)
                        y: Math.floor(index / cards.columns) * (height + cards.gap)
                        width: Math.max(0, (cards.width - (cards.columns - 1) * cards.gap) / cards.columns)
                        height: Math.max(0, (cards.height - (cards.rows - 1) * cards.gap) / cards.rows)
                    }
                }
            }
        }
    component ResourceCard: Rectangle {
        id: card
        required property string kind
        readonly property string label: ({cpu: "CPU", ram: "MEMORY", disk: "STORAGE", net: "NETWORK"})[kind]
        readonly property color accent: ({cpu: root.palette.blue || root.themeAccent, ram: root.palette.magenta || root.themeAccent, disk: root.themeGreen, net: root.themeYellow})[kind]
        readonly property string value: !root.fresh ? "—" : kind === "net" ? "↓ " + root.stats.download : root.stats[kind] + "%"
        readonly property string detail: kind === "cpu" ? root.stats.cores + " cores" : kind === "ram" ? root.stats.ramDetail || "" : kind === "disk" ? root.stats.diskDetail || "" : "↑ " + (root.stats.upload || "—")
        readonly property real usage: kind === "net" ? 0 : root.stats[kind] || 0
        readonly property bool compact: height < 55
        readonly property bool open: root.activeCard === card && card.QsWindow.window && card.QsWindow.window.visible
        readonly property var entries: root.stats[kind + "Rows"] || []
        color: hover.containsMouse ? root.tint(root.themeAccent, 0.12) : "transparent"
        radius: Math.min(8, height / 4)
        clip: true
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            x: card.width < 60 ? 3 : 8
            y: card.compact ? Math.max(1, (card.height - height) / 2) : 6
            width: card.compact ? Math.max(0, card.width * 0.38 - x) : Math.max(0, card.width - 12)
            text: card.width < 105 ? ({cpu: "CPU", ram: "RAM", disk: "SSD", net: "NET"})[card.kind] : card.label
            font.pixelSize: card.compact ? 9 : 10; font.bold: true
            color: card.accent; elide: Text.ElideRight
            visible: card.width > 30 && card.height > 13
        }
        Text {
            x: card.compact && card.width > 30 ? card.width * 0.4 : 8
            y: card.compact ? Math.max(0, (card.height - height) / 2) : Math.max(22, (card.height - height) / 2)
            width: Math.max(0, card.width - x - 5)
            text: card.value
            font.pixelSize: card.compact ? 12 : Math.min(25, card.width < 100 ? 16 : 22)
            font.bold: true; color: root.themeText; elide: Text.ElideRight
            visible: card.height > 13
        }
        Text {
            x: 8; y: parent.height - height - 10
            width: Math.max(0, parent.width - 16)
            text: card.detail; color: root.tint(root.themeMuted, 0.85); font.pixelSize: 10; elide: Text.ElideRight
            visible: card.height >= 90 && card.width >= 110
        }
        Rectangle {
            x: 4; y: parent.height - 3; height: 2
            width: Math.max(0, parent.width - 8); color: root.tint(root.themeText, 0.15)
            visible: card.height > 5
            Rectangle {
                height: parent.height; color: card.accent
                width: parent.width * (card.kind === "net" ? (root.stats.netRate || 0) / Math.max(1, ...(root.history.net || [])) : card.usage / 100)
                opacity: root.fresh ? 0.9 : 0.25
                Behavior on width { NumberAnimation { duration: 350 } }
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent; hoverEnabled: true
            onEntered: { closeTimer.stop(); openTimer.restart(); }
            onExited: { openTimer.stop(); closeTimer.restart(); }
            onClicked: root.activeCard = card.open ? null : card
        }
        Timer { id: openTimer; interval: 180; onTriggered: root.activeCard = card }
        Timer {
            id: closeTimer; interval: 260
            onTriggered: if (!hover.containsMouse && !popupHover.hovered && card.open) root.activeCard = null
        }

        PopupWindow {
            id: popup
            visible: card.open
            implicitWidth: 420
            implicitHeight: 400
            color: "transparent"
            anchor {
                id: popupAnchor
                window: card.QsWindow.window
                edges: Edges.Bottom | Edges.Left
                gravity: Edges.Bottom | Edges.Right
                adjustment: PopupAdjustment.All
                onAnchoring: {
                    const point = card.QsWindow.window.contentItem.mapFromItem(card, 0, card.height);
                    popupAnchor.rect.x = Math.round(point.x);
                    popupAnchor.rect.y = Math.round(point.y + 4);
                    popupAnchor.rect.width = 1; popupAnchor.rect.height = 1;
                }
            }
            Rectangle {
                anchors.fill: parent; radius: 12
                color: root.tint(root.themeBackground, 0.88); border.color: root.tint(root.themeAccent, 0.45); border.width: 1
                HoverHandler {
                    id: popupHover
                    onHoveredChanged: { if (hovered) closeTimer.stop(); else closeTimer.restart(); }
                }
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 9
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: card.label; color: card.accent; font.bold: true; font.pixelSize: 12 }
                        Item { Layout.fillWidth: true }
                        Text { text: root.fresh ? "LIVE · 2s" : "WAITING FOR DATA"; color: root.fresh ? root.themeGreen : root.themeYellow; font.pixelSize: 10 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.kind === "cpu" ? card.value + " total · " + card.detail : card.kind === "net" ? card.value + "   " + card.detail : card.value + " used · " + card.detail
                        color: root.themeText; font.pixelSize: 18; font.bold: true; elide: Text.ElideRight
                    }
                    Canvas {
                        id: chart
                        Layout.fillWidth: true; Layout.preferredHeight: 48
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const values = root.history[card.kind] || [];
                            if (values.length < 2) return;
                            const cap = card.kind === "cpu" || card.kind === "ram" ? 100 : Math.max(1, ...values);
                            ctx.strokeStyle = root.tint(root.themeText, 0.2); ctx.lineWidth = 1;
                            ctx.beginPath(); ctx.moveTo(0, height - 2); ctx.lineTo(width, height - 2); ctx.stroke();
                            ctx.strokeStyle = card.accent; ctx.lineWidth = 2; ctx.beginPath();
                            for (let i = 0; i < values.length; i++) {
                                const x = i * width / 29;
                                const y = height - 3 - (height - 6) * values[i] / cap;
                                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                            }
                            ctx.stroke();
                        }
                        Connections { target: root; function onHistoryChanged() { if (card.open) chart.requestPaint(); } }
                        Connections { target: card; function onOpenChanged() { if (card.open) chart.requestPaint(); } }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.kind === "cpu" ? "Top processes · 100% = one CPU core" : card.kind === "ram" ? "Top processes · resident memory (RSS)" : card.kind === "disk" ? root.stats.ioNote || "Reading disk activity…" : root.stats.netNote || "Reading network activity…"
                        color: root.tint(root.themeMuted, 0.85); font.pixelSize: 10; wrapMode: Text.WordWrap
                    }
                    ListView {
                        id: ranking
                        Layout.fillWidth: true; Layout.fillHeight: true
                        clip: true; spacing: 4; interactive: true
                        model: ListModel { id: rankedModel }
                        function sync() {
                            if (!card.open) return;
                            const rows = card.entries;
                            const keys = rows.map(r => r.key);
                            for (let i = rankedModel.count - 1; i >= 0; i--) {
                                if (keys.indexOf(rankedModel.get(i).key) === -1) rankedModel.remove(i);
                            }
                            for (let i = 0; i < rows.length; i++) {
                                let found = -1;
                                for (let j = i; j < rankedModel.count; j++) if (rankedModel.get(j).key === rows[i].key) { found = j; break; }
                                if (found === -1) rankedModel.insert(i, rows[i]);
                                else { if (found !== i) rankedModel.move(found, i, 1); rankedModel.set(i, rows[i]); }
                            }
                        }
                        Connections { target: card; function onEntriesChanged() { ranking.sync(); } function onOpenChanged() { ranking.sync(); } }
                        move: Transition { NumberAnimation { properties: "x,y"; duration: 400; easing.type: Easing.OutCubic } }
                        moveDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: 400; easing.type: Easing.OutCubic } }
                        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 } }
                        delegate: Item {
                            required property string name
                            required property string value
                            required property string detail
                            required property real level
                            width: ranking.width; height: 31
                            Rectangle {
                                anchors.left: parent.left; anchors.bottom: parent.bottom
                                height: 2; width: parent.width * level; color: card.accent; opacity: 0.6
                                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            }
                            Text { text: name; width: parent.width - 112; color: root.themeText; font.pixelSize: 12; elide: Text.ElideRight }
                            Text { text: value; anchors.right: parent.right; color: card.accent; font.pixelSize: 12; font.bold: true }
                            Text { text: detail; y: 16; width: parent.width; color: root.tint(root.themeMuted, 0.8); font.pixelSize: 9; elide: Text.ElideRight }
                        }
                        Text { anchors.centerIn: parent; visible: rankedModel.count === 0; text: "No visible activity"; color: root.tint(root.themeMuted, 0.8); font.pixelSize: 12 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.kind === "net" ? "All traffic, including UDP: " + (root.stats.netInterfaces || "Reading…") + "\nOpen connections: " + (root.stats.connections || "Reading…") : "60s history · bars relative to busiest entry"
                        color: root.tint(root.themeMuted, 0.8); font.pixelSize: 10; wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
