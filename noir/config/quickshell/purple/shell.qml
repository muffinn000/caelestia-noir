import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris

ShellRoot {
    id: root
    readonly property string sans: "Google Sans Flex"
    readonly property string mono: "JetBrainsMono Nerd Font"
    property date now: new Date()
    property int seconds: 1500
    property bool running: false
    property bool rest: false
    property double deadline: 0
    property var tasks: []
    property bool tasksLoaded: false
    property bool timerLoaded: false
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property string timeText: Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0")
    property int memoryPercent: 0

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    function launch(drawer) { Quickshell.execDetached(["caelestia", "shell", "drawers", "toggle", drawer]); }
    function focusWorkspace(number) {
        Hyprland.dispatch(Hyprland.usingLua ? 'hl.dsp.focus({ workspace = "' + number + '" })' : "workspace " + number);
    }
    function addTask(value) {
        const task = value.trim().slice(0, 160);
        if (task && tasksLoaded) { tasks = tasks.concat([task]); taskFile.setText(JSON.stringify(tasks)); }
    }
    function completeTask(index) {
        if (!tasksLoaded || index < 0 || index >= tasks.length) return;
        const copy = tasks.slice(); copy.splice(index, 1); tasks = copy;
        taskFile.setText(JSON.stringify(tasks));
    }
    function saveTimer() {
        if (timerLoaded) timerFile.setText(JSON.stringify({seconds, running, rest, deadline}));
    }
    function toggleTimer() {
        if (running) seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
        else { if (seconds <= 0) seconds = rest ? 300 : 1500; deadline = Date.now() + seconds * 1000; }
        running = !running; saveTimer();
    }
    function resetTimer() { running = false; seconds = rest ? 300 : 1500; deadline = 0; saveTimer(); }
    function setMode(isRest) { rest = isRest; resetTimer(); }
    function addFive() { seconds += 300; if (running) deadline += 300000; saveTimer(); }

    IpcHandler {
        target: "desktop"
        function status(): string { return JSON.stringify({seconds: root.seconds, running: root.running, rest: root.rest, tasks: root.tasks}); }
        function resetTimer(): void { root.resetTimer(); }
        function toggleTimer(): void { root.toggleTimer(); }
        function addTask(value: string): void { root.addTask(value); }
        function completeTask(index: int): void { root.completeTask(index); }
    }
    FileView {
        id: taskFile
        path: Quickshell.env("HOME") + "/.local/state/purple-desktop/tasks.json"
        printErrors: false
        onLoaded: {
            try { const data = JSON.parse(text()); if (Array.isArray(data)) root.tasks = data.filter(t => typeof t === "string"); }
            catch (error) { console.warn("Could not read existing tasks; file preserved:", error); return; }
            root.tasksLoaded = true;
        }
        onLoadFailed: { root.tasksLoaded = true; }
    }
    FileView {
        id: timerFile
        path: Quickshell.env("HOME") + "/.local/state/purple-desktop/timer.json"
        printErrors: false
        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.rest = !!state.rest;
                root.seconds = Math.max(0, Number(state.seconds) || 0);
                root.deadline = Number(state.deadline) || 0;
                root.running = !!state.running && root.deadline > 0;
            } catch (error) { console.warn("Could not read timer:", error); }
            root.timerLoaded = true;
        }
        onLoadFailed: { root.timerLoaded = true; }
    }
    FileView {
        id: memory
        path: "/proc/meminfo"
        onLoaded: {
            const data = text();
            const total = /MemTotal:\s+(\d+)/.exec(data);
            const available = /MemAvailable:\s+(\d+)/.exec(data);
            if (total && available) root.memoryPercent = Math.round(100 * (1 - Number(available[1]) / Number(total[1])));
        }
    }
    Timer { interval: 5000; running: true; repeat: true; onTriggered: memory.reload() }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            root.now = new Date();
            if (root.running) {
                root.seconds = Math.max(0, Math.ceil((root.deadline - Date.now()) / 1000));
                if (root.seconds === 0) {
                    root.running = false; root.saveTimer();
                    Quickshell.execDetached(["notify-send", "NOIR · Фокус", root.rest ? "Перерыв окончен. Можно продолжать." : "Сессия завершена. Время передохнуть."]);
                }
            }
        }
    }

    component Label: Text {
        color: "#f5f5f5"; font.family: root.sans; font.pixelSize: 13
        renderType: Text.NativeRendering
    }
    component Caption: Label {
        color: "#a0a0a0"; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1.5
    }
    component Action: Rectangle {
        id: control
        property string title
        property string tip: ""
        property var action
        property bool inverted: false
        implicitWidth: 34; implicitHeight: 30; radius: 7
        color: hit.containsMouse ? (inverted ? "#d4d4d4" : "#303030") : (inverted ? "#f5f5f5" : "transparent")
        Behavior on color { ColorAnimation { duration: 140 } }
        Label { anchors.centerIn: parent; text: control.title; color: control.inverted ? "#101010" : "#eeeeee"; font.family: root.mono; font.pixelSize: 13 }
        MouseArea { id: hit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (control.action) control.action() }
        ToolTip.visible: hit.containsMouse && tip.length > 0
        ToolTip.text: tip
        ToolTip.delay: 650
    }
    component Separator: Rectangle { width: 1; height: 16; color: "#383838"; anchors.verticalCenter: parent.verticalCenter }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            readonly property var monitor: Hyprland.monitorFor(modelData)
            readonly property int currentWs: monitor?.activeWorkspace?.id ?? 1
            readonly property var visibleWorkspace: Hyprland.workspaces.values.find(w => w.name === monitor?.lastIpcObject.specialWorkspace?.name) ?? monitor?.activeWorkspace
            readonly property bool fullscreen: visibleWorkspace?.toplevels.values.some(w => w.lastIpcObject.fullscreen > 1) ?? false
            screen: modelData
            visible: !fullscreen
            anchors { top: true; left: true; right: true }
            margins { top: 10; left: 14; right: 14 }
            implicitHeight: 40; exclusiveZone: 52; color: "transparent"
            WlrLayershell.namespace: "noir-top"
            // Caelestia's edge gesture region covers the top of empty workspaces.
            // Use a higher layer so input does not depend on shell startup order.
            WlrLayershell.layer: WlrLayer.Overlay
            Rectangle {
                anchors.fill: parent; color: "#f20b0b0b"; radius: 10; border.width: 1; border.color: "#333333"
                Row {
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    spacing: 7
                    Action { title: "◈"; inverted: true; tip: "Приложения"; action: () => root.launch("launcher") }
                    Caption { anchors.verticalCenter: parent.verticalCenter; text: "NOIR"; color: "#eeeeee"; font.bold: true; width: 49; leftPadding: 7 }
                    Separator {}
                    Repeater {
                        model: 5
                        Rectangle {
                            id: workspace
                            required property int index
                            readonly property bool selected: bar.currentWs === index + 1
                            readonly property bool occupied: Hyprland.workspaces.values.some(w => w.id === index + 1 && w.toplevels.values.length > 0)
                            width: selected ? 44 : 32; height: 28; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: selected ? "#ededed" : wsHit.containsMouse ? "#282828" : "transparent"
                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Label { anchors.centerIn: parent; text: (workspace.index + 1).toString().padStart(2,"0"); font.family: root.mono; font.pixelSize: 11; color: workspace.selected ? "#101010" : workspace.occupied ? "#dedede" : "#888888" }
                            Rectangle { width: 3; height: 3; radius: 2; color: "#a0a0a0"; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
 visible: workspace.occupied && !workspace.selected }
                            MouseArea { id: wsHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.focusWorkspace(workspace.index + 1) }
                        }
                    }
                    Action { title: "⌕"; tip: "Обзор"; action: () => root.launch("dashboard") }
                }
                Item {
                    anchors.centerIn: parent; width: 126; height: 30
                    Row {
                        anchors.centerIn: parent; spacing: 12
                        Caption { anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDateTime(root.now, "dd.MM"); color: "#9a9a9a" }
                        Label { text: Qt.formatDateTime(root.now, "HH:mm"); font.family: root.mono; font.pixelSize: 13; font.bold: true }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.launch("dashboard") }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
 spacing: 9
                    Caption { anchors.verticalCenter: parent.verticalCenter; text: "RAM " + root.memoryPercent + "%"; visible: bar.width > 1200 }
                    Separator {}
                    Item {
                        width: bar.width > 1600 ? 160 : 32; height: 30
                        Label { anchors { fill: parent; verticalCenter: parent.verticalCenter }
 verticalAlignment: Text.AlignVCenter; text: root.player ? "♫  " + (root.player.trackTitle || "Музыка") : "♫"; elide: Text.ElideRight; color: "#c4c4c4"; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (root.player?.canTogglePlaying) root.player.togglePlaying() }
                    }
                    Action { title: root.sink?.audio?.muted ? "󰝟" : "󰕾"; tip: "Звук · колесо — громкость"; action: () => root.launch("sidebar")
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; onWheel: event => { if (root.sink?.audio) root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + (event.angleDelta.y > 0 ? 0.05 : -0.05))); } }
                    }
                    Action { title: "󰂚"; tip: "Уведомления"; action: () => root.launch("sidebar") }
                    Separator {}
                    Action { title: "⏻"; tip: "Меню сессии"; action: () => root.launch("session") }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { bottom: true; left: true }
            margins { bottom: 88; left: 58 }
            implicitWidth: 350; implicitHeight: 230; exclusiveZone: -1; color: "transparent"
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "noir-signature"
            mask: Region {}
            Label { x: -5; y: 0; text: "NOIR"; font.pixelSize: 112; font.weight: Font.Light; font.letterSpacing: -4 }
            Caption { x: 4; y: 142; text: "LESS, BUT BETTER."; font.letterSpacing: 3; color: "#a0a0a0" }
            Rectangle { x: 4; y: 176; width: 270; height: 1; color: "#414141" }
            Caption { x: 4; y: 196; text: "CRYO / MONOCHROME EDITION"; font.pixelSize: 9; color: "#8a8a8a" }
        }
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
        anchors { top: true; left: true }
 margins { top: 112; left: 58 }
        implicitWidth: 530; implicitHeight: 232; color: "transparent"; exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "noir-clock"
        mask: Region {}
        Caption { x: 3; y: 0; text: "LOCAL TIME   /   CHIȘINĂU"; font.pixelSize: 10; color: "#a4a4a4" }
        Label { x: -5; y: 15; text: Qt.formatDateTime(root.now, "HH:mm"); font.family: root.sans; font.pixelSize: 132; font.weight: Font.Light; font.letterSpacing: -6 }
        Row { x: 4; y: 180; spacing: 13
            Rectangle { width: 25; height: 2; color: "#eeeeee"; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Qt.locale("ru_RU").toString(root.now, "dddd, d MMMM"); font.pixelSize: 17; color: "#c0c0c0" }
        }
        Caption { x: 4; y: 217; text: "ТИШЕ ВОКРУГ. ЯСНЕЕ ВНУТРИ."; font.pixelSize: 9; color: "#888888" }
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
        anchors { top: true; right: true }
 margins { top: 112; right: 48 }
        implicitWidth: 272; implicitHeight: 302; color: "transparent"; exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "noir-focus"
        Rectangle {
            anchors.fill: parent; radius: 18; color: "#eeeeee"
            Caption { x: 22; y: 20; text: "01 / ВНИМАНИЕ"; color: "#535353" }
            Rectangle { x: parent.width - 29; y: 23; width: 6; height: 6; radius: 3; color: root.running ? "#161616" : "#ababab" }
            Row {
                x: 20; y: 49; spacing: 4
                Repeater {
                    model: ["Фокус", "Перерыв"]
                    Rectangle {
                        required property string modelData; required property int index
                        readonly property bool selected: root.rest === (index === 1)
                        width: 114; height: 30; radius: 7; color: selected ? "#171717" : "transparent"
                        Label { anchors.centerIn: parent; text: parent.modelData; color: parent.selected ? "#f7f7f7" : "#616161"; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setMode(parent.index === 1) }
                    }
                }
            }
            Label { anchors.horizontalCenter: parent.horizontalCenter; y: 103; text: root.timeText; font.family: root.mono; font.pixelSize: 55; font.weight: Font.Light; font.letterSpacing: -3; color: "#151515" }
            Caption { anchors.horizontalCenter: parent.horizontalCenter; y: 173; text: root.running ? "ОДНА ЗАДАЧА ЗА РАЗ" : root.rest ? "ВЫДОХНИ. НЕ СПЕШИ." : "ВРЕМЯ ДЛЯ ГЛАВНОГО"; color: "#666666"; font.pixelSize: 9; font.letterSpacing: 1 }
            Rectangle { x: 23; y: 207; width: parent.width - 46; height: 3; radius: 2; color: "#d3d3d3"
                Rectangle { width: parent.width * Math.min(1, Math.max(0, root.seconds / (root.rest ? 300 : 1500))); height: 3; radius: 2; color: "#252525"; Behavior on width { NumberAnimation { duration: 500 } } }
            }
            Row {
                anchors { bottom: parent.bottom; bottomMargin: 20; horizontalCenter: parent.horizontalCenter }
 spacing: 9
                Action { title: "↺"; width: 39; height: 37; inverted: true; tip: "Сбросить"; color: "#dddddd"; action: () => root.resetTimer() }
                Rectangle { width: 132; height: 37; radius: 8; color: startHit.containsMouse ? "#383838" : "#151515"
                    Label { anchors.centerIn: parent; text: root.running ? "Ⅱ  Пауза" : "▶  Начать"; font.pixelSize: 12 }
                    MouseArea { id: startHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleTimer() }
                }
                Action { title: "+5"; width: 39; height: 37; inverted: true; tip: "Ещё 5 минут"; color: "#dddddd"; action: () => root.addFive() }
            }
        }
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
        anchors { bottom: true; right: true }
 margins { bottom: 54; right: 48 }
        implicitWidth: 300; implicitHeight: 288; color: "transparent"; exclusiveZone: -1
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.namespace: "noir-tasks"
        Rectangle {
            anchors.fill: parent; radius: 16; color: "#f2111111"; border.width: 1; border.color: "#3a3a3a"
            Caption { x: 22; y: 21; text: "02 / НА СЕГОДНЯ"; color: "#b2b2b2" }
            Caption { anchors { right: parent.right; rightMargin: 22 }
 y: 21; text: root.tasks.length.toString().padStart(2, "0"); color: "#eeeeee" }
            Rectangle { x: 22; y: 47; width: parent.width - 44; height: 1; color: "#333333" }
            Column {
                x: 23; y: 83; spacing: 10; visible: root.tasks.length === 0
                Label { text: "Свободная голова."; font.pixelSize: 20; color: "#e2e2e2" }
                Label { text: "Запиши важное. Остальное подождёт."; font.pixelSize: 11; color: "#939393" }
            }
            ListView {
                x: 17; y: 58; width: parent.width - 34; height: 157; clip: true; spacing: 5; model: root.tasks
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    id: taskRow
                    required property string modelData; required property int index
                    width: ListView.view.width; height: 36; radius: 6; color: taskHit.containsMouse ? "#2b2b2b" : "#1b1b1b"
                    Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 3; color: "transparent"; border.width: 1; border.color: taskHit.containsMouse ? "#ffffff" : "#777777" }
                    Label { x: 32; width: parent.width - 43; anchors.verticalCenter: parent.verticalCenter; text: taskRow.modelData; font.pixelSize: 12; elide: Text.ElideRight }
                    MouseArea { id: taskHit; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.completeTask(taskRow.index) }
                    ToolTip.visible: taskHit.containsMouse
                    ToolTip.text: modelData + "\nНажми, чтобы завершить"
                    ToolTip.delay: 800
                }
            }
            TextField {
                id: taskInput
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 17 }
 height: 38
                enabled: root.tasksLoaded; maximumLength: 160
                leftPadding: 12; rightPadding: 12
                placeholderText: "+  Добавить задачу"; color: "#f1f1f1"; placeholderTextColor: "#999999"; selectionColor: "#e0e0e0"; selectedTextColor: "#111111"; font.family: root.sans; font.pixelSize: 12
                background: Rectangle { radius: 8; color: "#202020"; border.width: 1; border.color: taskInput.activeFocus ? "#a0a0a0" : "#3b3b3b" }
                onAccepted: { if (text.trim()) { root.addTask(text); text = ""; } }
                Keys.onEscapePressed: focus = false
            }
        }
    }
}
