// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

// Pill button with a soft neon bloom.
import QtQuick
import QtQuick.Effects

Item {
    id: btn

    property string label: "SPAWN"
    property color accentColor: "#9fef00"
    property color labelColor: "#06120a"
    property bool hovered: false
    property bool busy: false

    signal clicked()

    implicitWidth: 108
    implicitHeight: 46
    opacity: enabled ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: btn.accentColor
        opacity: btn.hovered ? 0.34 : 0.16
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 48
        }
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.lighter(btn.accentColor, btn.hovered ? 1.22 : 1.10) }
            GradientStop { position: 1.0; color: Qt.darker(btn.accentColor, btn.hovered ? 1.02 : 1.20) }
        }
    }

    Rectangle {
        anchors.fill: body
        radius: body.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.38) }
            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, 0.02) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
        }
    }

    Text {
        anchors.centerIn: parent
        text: btn.label
        color: btn.labelColor
        font.pixelSize: 12
        font.bold: true
        font.letterSpacing: 1.8
    }

    MouseArea {
        anchors.fill: parent
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onEntered: btn.hovered = true
        onExited: btn.hovered = false
        onClicked: btn.clicked()
    }
}
