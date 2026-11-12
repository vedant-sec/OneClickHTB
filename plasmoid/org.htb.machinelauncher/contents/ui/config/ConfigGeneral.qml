// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_appToken: tokenField.text
    property string cfg_vpnMode: "pkexec"
    property alias cfg_vpnConfig: vpnField.text
    property alias cfg_burpCommand: burpField.text
    property alias cfg_firefoxCommand: firefoxField.text
    property alias cfg_launchBurp: burpCheck.checked
    property alias cfg_launchFirefox: firefoxCheck.checked
    property alias cfg_openMachineUrl: urlCheck.checked
    property alias cfg_terminateExisting: terminateCheck.checked

    // ------------------------------------------------------------------ //
    QQC2.Label {
        Kirigami.FormData.isSection: true
        textFormat: Text.RichText
        text: "Grab an <b>App Token</b> from " +
              "<a href=\"https://app.hackthebox.com/profile/settings\">app.hackthebox.com/profile/settings</a>" +
              " &rarr; <i>App Tokens</i>."
        onLinkActivated: (link) => Qt.openUrlExternally(link)
    }

    QQC2.TextField {
        id: tokenField
        Kirigami.FormData.label: "App Token:"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        echoMode: revealToken.checked ? TextInput.Normal : TextInput.Password
        placeholderText: "HTB API token"
        selectByMouse: true
    }

    QQC2.CheckBox {
        id: revealToken
        text: "Show token"
    }

    // ------------------------------------------------------------------ //
    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: "OpenVPN"
    }

    QQC2.ComboBox {
        id: vpnModeCombo
        Kirigami.FormData.label: "Connect using:"
        textRole: "text"
        valueRole: "value"
        model: [
            { text: "pkexec (graphical password prompt)", value: "pkexec" },
            { text: "sudo -n (passwordless sudo)", value: "sudo-n" },
            { text: "none (tunnel already up)", value: "none" }
        ]
        function syncFromConfig() {
            var i = indexOfValue(page.cfg_vpnMode)
            if (i >= 0 && i !== currentIndex)
                currentIndex = i
        }
        Component.onCompleted: syncFromConfig()
        onActivated: page.cfg_vpnMode = currentValue
    }

    Connections {
        target: page
        function onCfg_vpnModeChanged() { vpnModeCombo.syncFromConfig() }
    }

    RowLayout {
        Kirigami.FormData.label: "Profile:"

        QQC2.TextField {
            id: vpnField
            Layout.fillWidth: true
            placeholderText: "~/.config/htb/lab.ovpn"
        }

        QQC2.Button {
            text: "Browse…"
            onClicked: vpnDialog.open()
        }
    }

    FileDialog {
        id: vpnDialog
        title: "Select an OpenVPN profile"
        nameFilters: ["OpenVPN profiles (*.ovpn)", "All files (*)"]
        onAccepted: {
            var p = String(selectedFile)
            if (p.indexOf("file://") === 0)
                p = p.substring(7)
            try { p = decodeURIComponent(p) } catch (e) {}
            vpnField.text = p
        }
    }

    // ------------------------------------------------------------------ //
    QQC2.Label {
        Kirigami.FormData.isSection: true
        text: "Tooling"
    }

    QQC2.TextField {
        id: burpField
        Kirigami.FormData.label: "BurpSuite command:"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        placeholderText: "burpsuite"
    }

    QQC2.TextField {
        id: firefoxField
        Kirigami.FormData.label: "Firefox command:"
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        placeholderText: "firefox"
    }

    QQC2.CheckBox {
        id: burpCheck
        text: "Launch BurpSuite after the tunnel is up"
    }

    QQC2.CheckBox {
        id: firefoxCheck
        text: "Launch Firefox"
    }

    QQC2.CheckBox {
        id: urlCheck
        text: "Open http://<machine-ip> in Firefox"
    }

    QQC2.CheckBox {
        id: terminateCheck
        text: "Terminate a previously spawned machine when needed"
    }

    QQC2.Label {
        Kirigami.FormData.isSection: true
        textFormat: Text.RichText
        text: "<i>Tip: the OpenVPN stage is skipped automatically when a tun/wg interface " +
              "with an address already exists.</i>"
    }
}
