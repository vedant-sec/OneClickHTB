// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

// Frosted input field with a neon focus ring.
import QtQuick

Item {
    id: field

    property alias text: input.text
    property alias echoMode: input.echoMode
    property alias inputItem: input
    property alias placeholderText: hint.text
    property bool fieldEnabled: true
    property color accentColor: "#9fef00"
    property color textColor: "#eaf7ee"

    signal accepted()

    implicitHeight: 46
    implicitWidth: 200

    Rectangle {
        id: shell
        anchors.fill: parent
        radius: 13
        color: Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: input.activeFocus ? Qt.rgba(0.624, 0.937, 0.0, 0.70)
                                        : Qt.rgba(1, 1, 1, 0.09)
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }

    Rectangle {
        anchors.fill: shell
        anchors.margins: 1
        radius: shell.radius - 1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.07) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.00) }
        }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        verticalAlignment: TextInput.AlignVCenter
        color: field.textColor
        font.pixelSize: 13
        selectByMouse: true
        selectionColor: Qt.rgba(0.624, 0.937, 0.0, 0.35)
        selectedTextColor: "#07120a"
        clip: true
        enabled: field.fieldEnabled
        onAccepted: field.accepted()

        Text {
            id: hint
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            elide: Text.ElideRight
            visible: input.text.length === 0
            color: Qt.rgba(1, 1, 1, 0.26)
            font: input.font
        }
    }
}
