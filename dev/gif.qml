// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT
//
// Dev-only: renders the demo run to PNG frames, then ffmpeg turns them into
// docs/demo.gif.    qml6 dev/gif.qml
import QtQuick
import QtQuick.Window

Window {
    width: 480
    height: 720
    visible: true

    Rectangle {
        id: stage
        anchors.fill: parent

        gradient: Gradient {
            GradientStop { position: 0.0; color: "#10201b" }
            GradientStop { position: 0.55; color: "#07100e" }
            GradientStop { position: 1.0; color: "#04080a" }
        }

        Rectangle {
            width: 340
            height: 340
            radius: 170
            x: -90
            y: 30
            color: "#9fef00"
            opacity: 0.10
        }

        Rectangle {
            width: 280
            height: 280
            radius: 140
            x: 300
            y: 430
            color: "#26e0c8"
            opacity: 0.10
        }

        Loader {
            id: widget
            width: 404
            height: 640
            anchors.centerIn: parent
            source: "../plasmoid/org.htb.machinelauncher/contents/ui/Widget.qml"
            onLoaded: {
                item.width = width
                item.height = height
                item.demoMode = true
                item.loadMachine("Soccer")
                item.start()
            }
        }
    }

    property int frame: 0
    readonly property int maxFrames: 84

    function pad(n) {
        if (n < 10) return "000" + n
        if (n < 100) return "00" + n
        if (n < 1000) return "0" + n
        return "" + n
    }

    function grab() {
        if (frame >= maxFrames) {
            Qt.quit()
            return
        }
        stage.grabToImage(function (result) {
            result.saveToFile("/tmp/opencode/frames/f" + pad(frame) + ".png")
            frame += 1
            tick.start()
        }, Qt.size(stage.width, stage.height))
    }

    Timer {
        interval: 500
        running: true
        onTriggered: grab()
    }

    Timer {
        id: tick
        interval: 95
        onTriggered: grab()
    }
}
