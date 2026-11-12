// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT


// Dev-only: renders the widget (demo mode) and writes PNG snapshots.
//   mkdir -p /tmp/opencode && qmlscene6 dev/shot.qml
import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 440
    height: 700
    visible: true
    color: "#0a0d10"

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#101c17" }
            GradientStop { position: 0.5; color: "#07110e" }
            GradientStop { position: 1.0; color: "#04080a" }
        }
    }

    Rectangle {
        width: 320
        height: 320
        radius: 160
        x: -80
        y: 40
        color: "#9fef00"
        opacity: 0.10
    }

    Rectangle {
        width: 260
        height: 260
        radius: 130
        x: 260
        y: 420
        color: "#26e0c8"
        opacity: 0.10
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        width: 404
        height: 640
        source: "../plasmoid/org.htb.machinelauncher/contents/ui/Widget.qml"
    }

    Timer {
        interval: 400
        running: true
        repeat: false
        onTriggered: {
            loader.item.width = loader.width
            loader.item.height = loader.height
            loader.item.demoMode = true
            loader.item.loadMachine("Soccer")
            loader.item.start()
        }
    }

    Timer {
        interval: 2600
        running: true
        repeat: false
        onTriggered: loader.grabToImage(function (r) {
            r.saveToFile("/tmp/opencode/htb-preview-running.png")
        }, Qt.size(loader.width, loader.height))
    }

    Timer {
        interval: 9000
        running: true
        repeat: false
        onTriggered: {
            loader.grabToImage(function (r) {
                r.saveToFile("/tmp/opencode/htb-preview-done.png")
            }, Qt.size(loader.width, loader.height))
            quitTimer.start()
        }
    }

    Timer {
        id: quitTimer
        interval: 800
        onTriggered: Qt.quit()
    }
}
