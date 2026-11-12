// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

// Liquid-glass shell: translucent dark panel, neon rim light, drifting blobs.
import QtQuick
import QtQuick.Effects

Item {
    id: panel

    property color accent: "#9fef00"
    property color accentAlt: "#26e0c8"

    // ambient bloom behind the panel
    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 32
        color: panel.accent
        opacity: 0.10
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 64
        }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: 26
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.13)
        clip: true

        gradient: Gradient {
            GradientStop { position: 0.00; color: Qt.rgba(0.62, 0.94, 0.30, 0.34) }
            GradientStop { position: 0.30; color: Qt.rgba(1.00, 1.00, 1.00, 0.05) }
            GradientStop { position: 0.72; color: Qt.rgba(0.62, 0.94, 0.00, 0.09) }
            GradientStop { position: 1.00; color: Qt.rgba(0.10, 0.75, 0.70, 0.20) }
        }

        // frosted body
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: frame.radius - 1

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(0.055, 0.086, 0.094, 0.93) }
                GradientStop { position: 0.5; color: Qt.rgba(0.031, 0.055, 0.063, 0.95) }
                GradientStop { position: 1.0; color: Qt.rgba(0.016, 0.031, 0.039, 0.97) }
            }
        }

        // ---- liquid light blobs -------------------------------------- //
        Rectangle {
            id: blobA
            width: 250
            height: 250
            radius: width / 2
            x: 190
            y: -110
            color: panel.accent
            opacity: 0.13
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 80
            }
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { to: 150; duration: 14000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 210; duration: 14000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: -70; duration: 17000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -130; duration: 17000; easing.type: Easing.InOutSine }
            }
        }

        Rectangle {
            id: blobB
            width: 210
            height: 210
            radius: width / 2
            x: -80
            y: 380
            color: panel.accentAlt
            opacity: 0.10
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 80
            }
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation { to: -30; duration: 16000; easing.type: Easing.InOutSine }
                NumberAnimation { to: -90; duration: 16000; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on y {
                loops: Animation.Infinite
                NumberAnimation { to: 330; duration: 19000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 400; duration: 19000; easing.type: Easing.InOutSine }
            }
        }

        // specular sheen on the top edge
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 110
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }

        // diagonal glass reflection
        Rectangle {
            x: -60
            y: -140
            width: 120
            height: 700
            rotation: 18
            opacity: 0.05
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 1.0) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
            }
        }
    }

    // crisp highlight along the very top
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 42
        anchors.rightMargin: 42
        anchors.topMargin: 1
        height: 1
        radius: 1
        color: Qt.rgba(1, 1, 1, 0.55)
        opacity: 0.45
    }
}
