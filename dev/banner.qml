// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT
//
// Dev-only: renders docs/social-preview.png (1280x640) for the GitHub repo.
//    qml6 dev/banner.qml
import QtQuick
import QtQuick.Window

Window {
    width: 1280
    height: 640
    visible: true

    Rectangle {
        id: stage
        anchors.fill: parent

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#0b1613" }
            GradientStop { position: 0.55; color: "#070f0d" }
            GradientStop { position: 1.0; color: "#04080a" }
        }

        Rectangle {
            width: 620
            height: 620
            radius: 310
            x: -180
            y: -220
            color: "#9fef00"
            opacity: 0.10
        }

        Rectangle {
            width: 520
            height: 520
            radius: 260
            x: 860
            y: 340
            color: "#26e0c8"
            opacity: 0.09
        }

        Column {
            x: 78
            y: 120
            width: 560
            spacing: 22

            Text {
                text: "KDE PLASMA 6 WIDGET"
                color: "#9fef00"
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 3.5
            }

            Text {
                text: "OneClickHTB"
                color: "#f2fff4"
                font.pixelSize: 72
                font.bold: true
                font.letterSpacing: -1
            }

            Text {
                width: 540
                text: "Spawn a Hack The Box machine, dial the VPN and open your toolkit — from a neon ladder on your desktop."
                color: "#a8bcb2"
                font.pixelSize: 21
                wrapMode: Text.WordWrap
                lineHeight: 1.25
            }

            Item { width: 1; height: 8 }

            Column {
                spacing: 12

                Repeater {
                    model: [
                        "five-rung ladder: API → spawn → VPN → Burp → Firefox",
                        "live machine uptime, expiry countdown, STOP and RESET",
                        "any distro with Plasma 6 — Wayland or X11"
                    ]

                    delegate: Row {
                        spacing: 12
                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3
                            y: 9
                            color: "#9fef00"
                        }
                        Text {
                            text: modelData
                            color: "#d6e6dc"
                            font.pixelSize: 17
                        }
                    }
                }
            }

            Item { width: 1; height: 10 }

            Text {
                text: "github.com/vedant-sec/OneClickHTB"
                color: "#6f8a7c"
                font.pixelSize: 16
                font.family: "monospace"
            }
        }

        // widget screenshot
        Image {
            source: "../docs/preview-ready.png"
            width: 376
            height: 596
            anchors.right: parent.right
            anchors.rightMargin: 84
            anchors.verticalCenter: parent.verticalCenter
            smooth: true
        }
    }

    Timer {
        interval: 900
        running: true
        onTriggered: {
            stage.grabToImage(function (result) {
                result.saveToFile("/home/arceus/Desktop/htb-project/docs/social-preview.png")
                Qt.quit()
            }, Qt.size(stage.width, stage.height))
        }
    }
}
