// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasma5support as P5Support

import "components"

Item {
    id: root

    // ------------------------------------------------------------------ //
    // palette
    // ------------------------------------------------------------------ //
    readonly property color cNeon: "#9fef00"
    readonly property color cAqua: "#26e0c8"
    readonly property color cDanger: "#ff4d6d"
    readonly property color cWarn: "#ffb020"
    readonly property color cText: "#eaf7ee"
    readonly property color cTextDim: "#7d938d"

    // ------------------------------------------------------------------ //
    // state
    // ------------------------------------------------------------------ //
    property bool running: false
    property int elapsed: 0
    property string runState: "idle"      // idle | running | ready | failed
    property string machineIp: ""
    property string errText: ""
    property bool showLog: false
    property string logText: ""
    property bool demoMode: false          // offline preview of the ladder
    property bool stopping: false          // terminate request in flight
    property bool restarting: false        // machine reset in flight
    property string notice: ""
    property string _mode: "ladder"        // ladder | terminate | status | reset

    // active machine + timer
    property string machineName: ""
    property double activeSince: 0         // ms epoch, when the machine spawned
    property double expiresAt: 0           // ms epoch, from the API
    property double machineLifetime: 86400000
    property double nowTick: Date.now()

    readonly property bool hasMachine: machineName.length > 0 || machineIp.length > 0
    readonly property double activeMs: (activeSince > 0 && nowTick > activeSince)
                                       ? (nowTick - activeSince) : 0
    readonly property double remainingMs: (expiresAt > 0 && nowTick < expiresAt)
                                          ? (expiresAt - nowTick) : 0
    readonly property string activeLabel: formatSpan(activeMs)
    readonly property string expiryLabel: remainingMs > 0 ? formatSpan(remainingMs) : ""

    readonly property string headerSubtitle: {
        if (machineName.length === 0)
            return "labs.hackthebox.com  ·  automated deploy"
        var parts = [machineName]
        if (activeMs > 0)
            parts.push("active " + activeLabel)
        if (remainingMs > 0)
            parts.push("expires in " + expiryLabel)
        return parts.join("  ·  ")
    }

    property string _source: ""
    property string _buffer: ""
    property string _stderr: ""
    property var _lastResult: null
    property int phaseIndex: -1
    property var pending: ({})

    // live configuration (falls back to a stub outside plasmashell so the
    // widget can also be previewed with qmlscene6 during development)
    readonly property var cfg: (typeof plasmoid !== "undefined" && plasmoid && plasmoid.configuration)
                               ? plasmoid.configuration
                               : devCfg

    QtObject {
        id: devCfg
        property string appToken: ""
        property string vpnConfig: ""
        property string vpnMode: "pkexec"
        property string burpCommand: "burpsuite"
        property string firefoxCommand: "firefox"
        property bool launchBurp: true
        property bool launchFirefox: true
        property bool openMachineUrl: true
        property bool terminateExisting: true
        property string lastMachine: ""
    }

    readonly property string statusText: {
        switch (runState) {
        case "running":    return "RUNNING"
        case "stopping":   return "STOPPING"
        case "restarting": return "RESTARTING"
        case "active":     return "ACTIVE"
        case "ready":    return "READY"
        case "failed":   return "ERROR"
        default:         return "IDLE"
        }
    }

    readonly property color statusColor: {
        switch (runState) {
        case "running":    return cNeon
        case "stopping":   return cWarn
        case "restarting": return cWarn
        case "active":     return cAqua
        case "ready":      return cAqua
        case "failed":   return cDanger
        default:         return "#56645f"
        }
    }

    readonly property string scriptPath: {
        var u = Qt.resolvedUrl("../scripts/htb_spawn.py").toString()
        if (u.indexOf("file://") === 0)
            u = u.substring(7)
        try { u = decodeURIComponent(u) } catch (e) {}
        return u
    }

    implicitWidth: 400
    implicitHeight: body.implicitHeight + 36

    // ------------------------------------------------------------------ //
    // chrome
    // ------------------------------------------------------------------ //
    GlassPanel {
        anchors.fill: parent
        accent: root.cNeon
        accentAlt: root.cAqua
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ---------- header ---------- //
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: height / 2
                    color: root.cNeon
                    opacity: 0.18
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 32
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Qt.rgba(0.624, 0.937, 0.0, 0.10)
                    border.width: 1
                    border.color: Qt.rgba(0.624, 0.937, 0.0, 0.45)
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 11
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0.624, 0.937, 0.0, 0.16) }
                        GradientStop { position: 1.0; color: Qt.rgba(0.624, 0.937, 0.0, 0.01) }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "HTB"
                    color: root.cNeon
                    font.pixelSize: 13
                    font.bold: true
                    font.letterSpacing: 1.0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -1

                Text {
                    text: "MACHINE LAUNCHER"
                    color: root.cText
                    font.pixelSize: 14
                    font.bold: true
                    font.letterSpacing: 1.7
                }

                Text {
                    Layout.fillWidth: true
                    text: root.headerSubtitle
                    color: root.machineName.length > 0 ? root.cAqua : root.cTextDim
                    font.pixelSize: 9
                    font.letterSpacing: 0.3
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: statusRow.implicitWidth + 18
                implicitHeight: 22
                radius: 11
                color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.45)

                RowLayout {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 3
                        color: root.statusColor

                        SequentialAnimation on opacity {
                            running: root.running
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.15; duration: 620 }
                            NumberAnimation { to: 1.0; duration: 620 }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.statusText
                        color: root.statusColor
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.2
                    }
                }
            }
        }

        // ---------- machine input ---------- //
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            GlassField {
                id: machineField
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                placeholderText: "machine name  ·  e.g. Soccer"
                fieldEnabled: !root.running
                onAccepted: root.start()
            }

            NeonButton {
                id: actionButton
                Layout.preferredHeight: 46
                Layout.preferredWidth: 106
                enabled: !root.stopping && !root.restarting
                label: root.running ? "ABORT" : "SPAWN"
                accentColor: root.running ? root.cDanger : root.cNeon
                labelColor: root.running ? "#2b0710" : "#06120a"
                onClicked: root.start()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.demoMode && String(root.cfg.appToken || "").length === 0
            text: "\u26a0  No App Token yet — right-click the widget \u2192 Configure \u2192 Launcher."
            color: root.cWarn
            font.pixelSize: 9
            wrapMode: Text.WordWrap
        }

        // ---------- the ladder ---------- //
        Item {
            id: ladder
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: stageColumn.implicitHeight

            readonly property int rows: stageModel.count
            readonly property int rowH: 58
            readonly property int gap: 10

            Rectangle {
                x: 13
                y: 14
                width: 2
                height: Math.max(0, (ladder.rows - 1) * (ladder.rowH + ladder.gap))
                radius: 1
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.rgba(0.624, 0.937, 0.0, 0.55) }
                    GradientStop { position: 0.55; color: Qt.rgba(0.624, 0.937, 0.0, 0.20) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.07) }
                }
            }

            Column {
                id: stageColumn
                width: ladder.width
                spacing: ladder.gap

                Repeater {
                    model: ListModel {
                        id: stageModel
                        ListElement { stageId: "api";     label: "CONNECT TO HTB API";   info: "queued"; rowState: "pending" }
                        ListElement { stageId: "spawn";   label: "SPAWN MACHINE";        info: "queued"; rowState: "pending" }
                        ListElement { stageId: "vpn";     label: "CONNECT TO OPENVPN";   info: "queued"; rowState: "pending" }
                        ListElement { stageId: "burp";    label: "LAUNCH BURPSUITE";     info: "queued"; rowState: "pending" }
                        ListElement { stageId: "firefox"; label: "LAUNCH FIREFOX";       info: "queued"; rowState: "pending" }
                    }

                    delegate: StageRow {
                        width: stageColumn.width
                        height: ladder.rowH
                        stageIndex: index
                        label: model.label
                        info: model.info
                        rowState: model.rowState
                    }
                }
            }
        }

        // ---------- footer ---------- //
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.running ? ("elapsed " + root.formatTime(root.elapsed))
                    : root.stopping ? "terminating machine…"
                    : root.restarting ? "restarting machine…"
                    : root.notice.length > 0 ? root.notice
                    : root.errText.length > 0 ? root.errText
                    : root.runState === "ready" ? "deployment complete"
                    : root.runState === "active" ? "machine is up"
                    : "idle — enter a machine name"
                color: root.errText.length > 0 && !root.running && !root.stopping && !root.restarting
                       ? root.cDanger
                     : root.notice.length > 0 ? root.cAqua
                     : root.cTextDim
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            Rectangle {
                visible: root.machineIp.length > 0
                implicitWidth: ipText.implicitWidth + 16
                implicitHeight: 20
                radius: 10
                color: Qt.rgba(0.624, 0.937, 0.0, 0.12)
                border.width: 1
                border.color: Qt.rgba(0.624, 0.937, 0.0, 0.40)

                Text {
                    id: ipText
                    anchors.centerIn: parent
                    text: root.machineIp
                    color: root.cNeon
                    font.pixelSize: 9
                    font.bold: true
                    font.letterSpacing: 0.4
                }
            }

            Rectangle {
                id: restartChip
                implicitWidth: restartRow.implicitWidth + 18
                implicitHeight: 20
                radius: 10
                color: restartMouse.containsMouse && !root.restarting && !root.stopping
                       ? Qt.rgba(0.15, 0.88, 0.78, 0.22)
                       : Qt.rgba(0.15, 0.88, 0.78, 0.10)
                border.width: 1
                border.color: Qt.rgba(0.15, 0.88, 0.78, root.restarting ? 0.25 : 0.50)
                opacity: (root.restarting || root.stopping) ? 0.6 : 1.0
                Behavior on color { ColorAnimation { duration: 140 } }

                RowLayout {
                    id: restartRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "\u21bb"
                        color: root.cAqua
                        font.pixelSize: 10
                        font.bold: true
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.restarting ? "WAIT" : "RESET"
                        color: root.cAqua
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.1
                    }
                }

                MouseArea {
                    id: restartMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    enabled: !root.restarting && !root.stopping && !root.running
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.restartMachine()
                }
            }

            Rectangle {
                id: stopChip
                implicitWidth: stopRow.implicitWidth + 18
                implicitHeight: 20
                radius: 10
                color: stopMouse.containsMouse && !root.stopping
                       ? Qt.rgba(1.0, 0.30, 0.43, 0.22)
                       : Qt.rgba(1.0, 0.30, 0.43, 0.10)
                border.width: 1
                border.color: Qt.rgba(1.0, 0.30, 0.43, root.stopping ? 0.25 : 0.50)
                opacity: (root.stopping || root.restarting) ? 0.7 : 1.0
                Behavior on color { ColorAnimation { duration: 140 } }

                RowLayout {
                    id: stopRow
                    anchors.centerIn: parent
                    spacing: 5

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 6
                        Layout.preferredHeight: 6
                        radius: 1
                        color: root.cDanger
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.stopping ? "STOPPING" : "STOP"
                        color: root.cDanger
                        font.pixelSize: 8
                        font.bold: true
                        font.letterSpacing: 1.1
                    }
                }

                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    hoverEnabled: true
                    enabled: !root.stopping && !root.restarting
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.stopMachine()
                }
            }

            Text {
                text: root.showLog ? "hide log" : "log"
                color: root.cTextDim
                font.pixelSize: 10
                font.underline: logMouse.containsMouse

                MouseArea {
                    id: logMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showLog = !root.showLog
                }
            }
        }

    }

    // ---------- log overlay (does not change the widget size) ---------- //
    Rectangle {
        id: logOverlay
        anchors.fill: parent
        anchors.margins: 14
        visible: root.showLog
        radius: 16
        color: Qt.rgba(0.02, 0.045, 0.05, 0.95)
        border.width: 1
        border.color: Qt.rgba(0.624, 0.937, 0.0, 0.28)

        Rectangle {
            id: logHead
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "RUNTIME LOG"
                color: root.cNeon
                font.pixelSize: 9
                font.bold: true
                font.letterSpacing: 1.4
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2715 close"
                color: root.cTextDim
                font.pixelSize: 9
                font.underline: closeMouse.containsMouse

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showLog = false
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
            }
        }

        Flickable {
            id: logFlick
            anchors.top: logHead.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            contentHeight: logBody.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
                id: logBody
                width: logFlick.width
                text: root.logText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                color: "#8fb3a4"
                font.family: "monospace"
                font.pixelSize: 9
                onContentHeightChanged: logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)
            }
        }
    }

    // ------------------------------------------------------------------ //
    // backend bridge - one short-lived process per rung of the ladder
    // (the plasma "executable" engine only delivers stdout when the process
    //  exits, so each stage is its own process and QML walks the ladder)
    // ------------------------------------------------------------------ //
    readonly property var phases: ["api", "spawn", "vpn", "burp", "firefox"]

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []

        onNewData: (source, data) => {
            if (source !== root._source)
                return
            if (data["stdout"] !== undefined)
                root.feed(data["stdout"])
            if (data["stderr"] !== undefined) {
                var err = String(data["stderr"]).trim()
                if (err.length > 0) {
                    root._stderr = err
                    root.appendLog("! " + err)
                }
            }
            if (data["exit code"] !== undefined)
                root.phaseFinished(parseInt(data["exit code"]))
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.elapsed += 1
    }

    Timer {
        id: phaseGuard
        interval: 420000
        onTriggered: {
            if (!root.running && !root.stopping)
                return
            root.appendLog("[launcher] watchdog timeout")
            if (root.stopping) {
                root.killSource()
                root.stopping = false
                root.runState = root.machineIp.length > 0 ? "ready" : "idle"
                root.errText = "terminate timed out"
                root.notice = ""
            } else {
                root.abort()
            }
        }
    }

    Timer {
        id: noticeTimer
        interval: 4500
        onTriggered: root.notice = ""
    }

    // pick up a machine that is already running (spawned earlier or from the
    // website); delayed a moment so the plasmoid config is fully loaded
    Timer {
        id: initialSync
        interval: 1200
        onTriggered: {
            root.syncStatus()
            retrySync.restart()
        }
    }

    Timer {
        id: retrySync
        interval: 6000
        onTriggered: {
            if (!root.hasMachine && root.runState === "idle" && !root.running)
                root.syncStatus()
        }
    }

    // drives the "active for" / "expires in" labels
    Timer {
        interval: 1000
        repeat: true
        running: root.hasMachine
        onTriggered: root.nowTick = Date.now()
    }

    Timer {
        id: demoHold
        interval: 1150
        onTriggered: {
            if (!root.running)
                return
            var id = root.phases[root.phaseIndex]
            var res = root.demoResult(id)
            if (res.ip) {
                root.pending.ip = res.ip
                root.machineIp = res.ip
            }
            root.applyMachine(res)
            root.setStage(id, res.state, res.detail)
            root.appendLog("[demo] " + id + " — " + res.detail)
            root.nextPhase()
        }
    }

    Component.onCompleted: {
        if (root.cfg.lastMachine)
            machineField.text = root.cfg.lastMachine
        root.nowTick = Date.now()
        initialSync.restart()
    }

    // ------------------------------------------------------------------ //
    // ladder plumbing
    // ------------------------------------------------------------------ //
    function loadMachine(name) {
        machineField.text = String(name || "").trim()
    }

    function formatTime(seconds) {
        var m = Math.floor(seconds / 60)
        var s = seconds % 60
        return m > 0 ? (m + "m " + (s < 10 ? "0" : "") + s + "s") : (s + "s")
    }

    function appendLog(line) {
        if (!line || line.length === 0)
            return
        logText = logText + line + "\n"
        if (logText.length > 8000)
            logText = logText.slice(-8000)
    }

    function killSource() {
        if (_source.length > 0) {
            var s = _source
            _source = ""
            exec.disconnectSource(s)
        }
    }

    function stageIndexById(id) {
        for (var i = 0; i < stageModel.count; ++i) {
            if (stageModel.get(i).stageId === id)
                return i
        }
        return -1
    }

    function resetStages() {
        for (var i = 0; i < stageModel.count; ++i) {
            stageModel.setProperty(i, "rowState", "pending")
            stageModel.setProperty(i, "info", "queued")
        }
    }

    function setStage(id, state, detail) {
        var i = stageIndexById(id)
        if (i < 0)
            return
        if (detail !== undefined && detail !== null && String(detail).length > 0)
            stageModel.setProperty(i, "info", String(detail))
        stageModel.setProperty(i, "rowState", state)
    }

    function skipRest(id, detail) {
        var from = stageIndexById(id)
        for (var i = Math.max(0, from); i < stageModel.count; ++i) {
            if (stageModel.get(i).rowState === "pending") {
                stageModel.setProperty(i, "rowState", "skipped")
                stageModel.setProperty(i, "info", detail)
            }
        }
    }

    function phaseHint(id) {
        switch (id) {
        case "api":     return "authenticating…"
        case "spawn":   return "deploying · up to 3 min"
        case "vpn":     return "checking tunnel…"
        case "burp":    return "locating BurpSuite…"
        case "firefox": return "opening browser…"
        }
        return "working…"
    }

    function buildCommand(id) {
        // NOTE: the App Token is deliberately *not* part of the job - the
        // backend reads it from the plasmoid config so it never appears in a
        // command line (visible in `ps`).
        var job = {
            nonce: Date.now(),
            machine: machineField.text.trim(),
            machine_id: pending.machine_id || 0,
            ip: pending.ip || "",
            vpn_mode: root.cfg.vpnMode || "pkexec",
            vpn_config: root.cfg.vpnConfig || "",
            burp_cmd: root.cfg.burpCommand || "burpsuite",
            firefox_cmd: root.cfg.firefoxCommand || "firefox",
            launch_burp: root.cfg.launchBurp !== false,
            launch_firefox: root.cfg.launchFirefox !== false,
            open_url: root.cfg.openMachineUrl !== false,
            terminate_existing: root.cfg.terminateExisting !== false
        }
        return 'python3 "' + scriptPath + '" --phase ' + id
             + ' --job "' + encodeURIComponent(JSON.stringify(job)) + '"'
    }

    function formatServerTime(ms) {
        var d = new Date(ms)
        function p(n) { return (n < 10 ? "0" : "") + n }
        return d.getUTCFullYear() + "-" + p(d.getUTCMonth() + 1) + "-" + p(d.getUTCDate())
             + " " + p(d.getUTCHours()) + ":" + p(d.getUTCMinutes()) + ":" + p(d.getUTCSeconds())
    }

    function demoResult(id) {
        switch (id) {
        case "api":     return { state: "done", detail: "Soccer  ·  LINUX  ·  Easy", machine_id: 1 }
        case "spawn":   return { state: "done", detail: "deployed at 10.129.42.7",
                                 ip: "10.129.42.7", machine: "Soccer", lifetime: 86400,
                                 expires_at: formatServerTime(Date.now() + 86400000) }
        case "vpn":     return { state: "done", detail: "tunnel up on tun0 (10.10.14.23)" }
        case "burp":    return { state: "done", detail: "BurpSuite launched" }
        case "firefox": return { state: "done", detail: "http://10.129.42.7" }
        }
        return { state: "done", detail: "" }
    }

    function nextPhase() {
        if (!running)
            return

        var id = ""
        while (true) {
            phaseIndex += 1
            if (phaseIndex >= phases.length) {
                finishAll()
                return
            }
            id = phases[phaseIndex]
            if (id === "burp" && root.cfg.launchBurp === false) {
                setStage(id, "skipped", "disabled in settings")
                continue
            }
            if (id === "firefox" && root.cfg.launchFirefox === false) {
                setStage(id, "skipped", "disabled in settings")
                continue
            }
            break
        }

        setStage(id, "running", phaseHint(id))
        appendLog("[ladder] " + id)

        if (demoMode) {
            demoHold.restart()
            return
        }

        var cmd = buildCommand(id)
        _buffer = ""
        _stderr = ""
        _lastResult = null
        _source = cmd
        exec.connectSource(cmd)
        phaseGuard.restart()
    }

    function handleLine(line) {
        var msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            appendLog(line)
            return
        }
        _lastResult = msg
        if (msg.ip)
            machineIp = msg.ip
        if (msg.state === "running")
            setStage(msg.stage, "running", msg.detail)
    }

    function feed(chunk) {
        if (!chunk)
            return
        _buffer += chunk
        var idx
        while ((idx = _buffer.indexOf("\n")) >= 0) {
            var line = _buffer.substring(0, idx).trim()
            _buffer = _buffer.substring(idx + 1)
            if (line.length > 0)
                handleLine(line)
        }
    }

    function phaseFinished(code) {
        if (_source.length > 0) {
            var s = _source
            _source = ""
            Qt.callLater(function () { exec.disconnectSource(s) })
        }
        phaseGuard.stop()

        if (_mode === "terminate") {
            finishTerminate(code)
            return
        }
        if (_mode === "reset") {
            finishReset(code)
            return
        }
        if (_mode === "status") {
            finishStatus(code)
            return
        }

        if (!running || phaseIndex < 0 || phaseIndex >= phases.length)
            return

        var id = phases[phaseIndex]
        var res = _lastResult

        if (code !== 0 || !res || res.state === "error") {
            var detail = (res && res.detail) ? res.detail
                       : (_stderr.length > 0 ? _stderr.split("\n").pop()
                                             : "stage failed (exit " + code + ")")
            setStage(id, "error", detail)
            skipRest(id, "not reached")
            runState = "failed"
            errText = detail
            running = false
            appendLog("[launcher] failed at " + id)
            return
        }

        if (res.machine_id !== undefined && res.machine_id !== null && res.machine_id !== 0)
            pending.machine_id = res.machine_id
        if (res.machine)
            pending.machine = res.machine
        if (res.ip) {
            pending.ip = res.ip
            machineIp = res.ip
        }

        applyMachine(res)
        setStage(id, res.state || "done", res.detail || "")
        appendLog("[" + id + "] " + (res.state || "done")
                  + (res.detail ? " — " + res.detail : ""))
        nextPhase()
    }

    function finishAll() {
        running = false
        runState = "ready"
        errText = ""
        appendLog("[launcher] deployment complete")
        root.cfg.lastMachine = machineField.text.trim()
    }

    function start() {
        if (running) {
            abort()
            return
        }

        var machine = machineField.text.trim()
        if (demoMode && machine.length === 0) {
            machine = "Soccer"
            machineField.text = machine
        }
        if (machine.length === 0) {
            flash("enter a machine name")
            return
        }
        if (!/^[A-Za-z0-9][A-Za-z0-9 ._-]{0,48}$/.test(machine)) {
            flash("invalid machine name")
            return
        }

        var token = (root.cfg.appToken || "").toString().trim()
        if (!demoMode && token.length === 0) {
            flash("set your HTB App Token in the widget settings")
            return
        }

        _mode = "ladder"
        notice = ""
        stopping = false
        restarting = false
        machineName = ""
        expiresAt = 0
        activeSince = 0
        noticeTimer.stop()
        resetStages()
        logText = ""
        machineIp = ""
        errText = ""
        elapsed = 0
        phaseIndex = -1
        pending = ({})
        _lastResult = null
        _stderr = ""
        runState = "running"
        running = true
        appendLog("[launcher] " + (demoMode ? "demo run: " : "spawn: ") + machine)
        nextPhase()
    }

    function abort() {
        var id = (phaseIndex >= 0 && phaseIndex < phases.length) ? phases[phaseIndex] : ""
        killSource()
        phaseGuard.stop()
        demoHold.stop()

        if (id.length > 0) {
            var i = stageIndexById(id)
            if (i >= 0 && stageModel.get(i).rowState === "running")
                setStage(id, "error", "aborted")
        }
        skipRest("api", "aborted")

        running = false
        runState = "failed"
        errText = "aborted"
        appendLog("[launcher] aborted")
    }

    function parseServerTime(value) {
        if (!value)
            return 0
        var m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(String(value))
        if (!m)
            return 0
        return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
                        Number(m[4]), Number(m[5]), Number(m[6]))
    }

    function formatSpan(ms) {
        if (!(ms > 0))
            return "0s"
        var total = Math.floor(ms / 1000)
        var d = Math.floor(total / 86400)
        var h = Math.floor((total % 86400) / 3600)
        var m = Math.floor((total % 3600) / 60)
        var s = total % 60
        if (d > 0)
            return d + "d " + h + "h"
        if (h > 0)
            return h + "h " + m + "m"
        if (m > 0)
            return m + "m " + s + "s"
        return s + "s"
    }

    // take whatever the backend knows about the active machine
    function applyMachine(res) {
        if (!res)
            return
        var hasInfo = (res.ip !== undefined && res.ip !== "")
                   || (res.expires_at !== undefined && res.expires_at !== "")
        if (!hasInfo)
            return

        if (res.machine) {
            machineName = res.machine
            pending.machine = res.machine
        } else if (pending.machine) {
            machineName = pending.machine
        }
        if (res.ip) {
            machineIp = res.ip
            pending.ip = res.ip
        }
        if (res.lifetime)
            machineLifetime = Number(res.lifetime) * 1000

        var expiry = parseServerTime(res.expires_at)
        if (expiry > 0) {
            expiresAt = expiry
            var spawned = expiry - machineLifetime
            activeSince = (spawned > 0 && spawned <= Date.now()) ? spawned : Date.now()
        }
        nowTick = Date.now()
    }

    function syncStatus() {
        if (demoMode || running || stopping || restarting)
            return
        var token = (root.cfg.appToken || "").toString().trim()
        if (token.length === 0)
            return
        var job = { nonce: Date.now(), machine: machineField.text.trim() }
        var cmd = 'python3 "' + scriptPath + '" --phase status'
                + ' --job "' + encodeURIComponent(JSON.stringify(job)) + '"'
        _mode = "status"
        _buffer = ""
        _stderr = ""
        _lastResult = null
        _source = cmd
        exec.connectSource(cmd)
    }

    function finishStatus(code) {
        var res = _lastResult
        _mode = "ladder"
        if (code !== 0 || !res || res.state !== "done") {
            appendLog("[status] no active machine")
            return
        }
        applyMachine(res)
        if (runState === "idle")
            runState = "active"
        if (machineField.text.trim().length === 0 && res.machine)
            machineField.text = res.machine
        appendLog("[status] " + (res.detail || "machine active"))
    }

    function restartMachine() {
        if (restarting || stopping || running)
            return

        if (demoMode) {
            activeSince = Date.now()
            expiresAt = Date.now() + machineLifetime
            nowTick = Date.now()
            runState = "active"
            notice = "demo — timer reset"
            noticeTimer.restart()
            return
        }

        var token = (root.cfg.appToken || "").toString().trim()
        if (token.length === 0) {
            flash("set your HTB App Token first")
            return
        }

        restarting = true
        runState = "restarting"
        notice = ""
        errText = ""
        _mode = "reset"
        _buffer = ""
        _stderr = ""
        _lastResult = null

        var job = {
            nonce: Date.now(),
            machine: machineField.text.trim(),
            machine_id: pending.machine_id || 0
        }
        var cmd = 'python3 "' + scriptPath + '" --phase reset'
                + ' --job "' + encodeURIComponent(JSON.stringify(job)) + '"'
        appendLog("[launcher] restart requested")
        _source = cmd
        exec.connectSource(cmd)
        phaseGuard.restart()
    }

    function finishReset(code) {
        restarting = false
        _mode = "ladder"
        var res = _lastResult

        if (code !== 0 || !res || res.state === "error") {
            var detail = (res && res.detail) ? res.detail
                       : (_stderr.length > 0 ? _stderr.split("\n").pop()
                                            : "restart failed")
            appendLog("[restart] " + detail)
            errText = detail
            notice = ""
            runState = machineIp.length > 0 ? "ready" : "idle"
            return
        }

        if (res.state === "skipped") {
            notice = res.detail || "no machine is running"
            runState = "idle"
            noticeTimer.restart()
            return
        }

        applyMachine(res)
        runState = "active"
        notice = (res.machine || machineName || "machine") + " restarted · timer reset"
        noticeTimer.restart()
        appendLog("[restart] " + (res.detail || "done"))
    }

    function stopMachine() {
        if (stopping)
            return
        if (running)
            abort()

        if (demoMode) {
            resetWidget()
            notice = "demo mode — ladder reset"
            noticeTimer.restart()
            return
        }

        var token = (root.cfg.appToken || "").toString().trim()
        if (token.length === 0) {
            flash("set your HTB App Token first")
            return
        }

        stopping = true
        runState = "stopping"
        notice = ""
        errText = ""
        _mode = "terminate"
        _buffer = ""
        _stderr = ""
        _lastResult = null

        var job = {
            nonce: Date.now(),
            machine: machineField.text.trim(),
            machine_id: pending.machine_id || 0
        }
        var cmd = 'python3 "' + scriptPath + '" --phase terminate'
                + ' --job "' + encodeURIComponent(JSON.stringify(job)) + '"'

        appendLog("[launcher] terminate requested")
        _source = cmd
        exec.connectSource(cmd)
        phaseGuard.restart()
    }

    function finishTerminate(code) {
        stopping = false
        var res = _lastResult

        if (code !== 0 || !res || res.state === "error") {
            var detail = (res && res.detail) ? res.detail
                       : (_stderr.length > 0 ? _stderr.split("\n").pop()
                                            : "terminate failed")
            appendLog("[terminate] " + detail)
            errText = detail
            notice = ""
            _mode = "ladder"
            runState = machineIp.length > 0 ? "ready" : "idle"
            return
        }

        var what = res.detail || "machine stopped"
        appendLog("[terminate] " + what)
        resetWidget()
        notice = what
        noticeTimer.restart()
    }

    function resetWidget() {
        running = false
        stopping = false
        _mode = "ladder"
        phaseIndex = -1
        pending = ({})
        _lastResult = null
        _stderr = ""
        _buffer = ""
        machineIp = ""
        machineName = ""
        expiresAt = 0
        activeSince = 0
        restarting = false
        errText = ""
        elapsed = 0
        runState = "idle"
        resetStages()
        appendLog("[launcher] widget reset")
    }

    function flash(message) {
        errText = message
        runState = "failed"
        running = false
        flashTimer.restart()
    }

    Timer {
        id: flashTimer
        interval: 3500
        onTriggered: {
            if (!root.running && root.runState === "failed" && root.errText.length > 0
                    && root.machineIp.length === 0 && root.elapsed === 0) {
                root.runState = "idle"
                root.errText = ""
            }
        }
    }
}
