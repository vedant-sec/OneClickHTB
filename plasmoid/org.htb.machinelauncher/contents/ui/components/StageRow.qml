// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

// One rung of the ladder: node + rail stub + glass box.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: row

    property string label: ""
    property string info: ""
    property string rowState: "pending"   // pending | running | done | warn | skipped | error
    property int stageIndex: 0

    readonly property color neon: "#9fef00"
    readonly property color danger: "#ff4d6d"
    readonly property color warn: "#ffb020"
    readonly property color dim: "#7d938d"

    readonly property bool isActive: rowState === "running"
    readonly property bool isDone: rowState === "done"
    readonly property bool isError: rowState === "error"
    readonly property bool isWarn: rowState === "warn"
    readonly property bool isSkipped: rowState === "skipped"
    readonly property bool isPending: rowState === "pending"
    readonly property bool lit: isActive || isDone
    readonly property color accent: isError ? danger : (isWarn ? warn : neon)

    readonly property color fillLeft: isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.11)
                                    : isDone ? Qt.rgba(0.624, 0.937, 0.0, 0.055)
                                    : isError ? Qt.rgba(1.0, 0.30, 0.43, 0.10)
                                    : isWarn ? Qt.rgba(1.0, 0.69, 0.13, 0.08)
                                    : Qt.rgba(1, 1, 1, 0.032)
    readonly property color fillRight: isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.02)
                                     : isDone ? Qt.rgba(1, 1, 1, 0.018)
                                     : isError ? Qt.rgba(1, 1, 1, 0.02)
                                     : Qt.rgba(1, 1, 1, 0.014)

    readonly property string statusText: {
        switch (rowState) {
        case "running": return "RUNNING"
        case "done":    return "OK"
        case "error":   return "FAILED"
        case "warn":    return "WARN"
        case "skipped": return "SKIP"
        default:        return "QUEUED"
        }
    }

    readonly property string titleColor: isActive ? "#eaffd0"
                                       : isDone ? "#d8f7b4"
                                       : isError ? "#ffd7de"
                                       : isWarn ? "#ffe6bd"
                                       : "#a9bcb7"

    readonly property string detailColor: isActive ? "#9fef00"
                                        : isError ? "#ff849b"
                                        : isWarn ? "#ffc45c"
                                        : isDone ? "#7f9c78"
                                        : "#66786f"

    property real haloPulse: 0.16
    property real shimmerX: 0

    implicitWidth: 340
    implicitHeight: 58

    // ---- rail stub ------------------------------------------------------- //
    Rectangle {
        x: 27
        y: Math.round(row.height / 2) - 0.5
        width: 17
        height: 1
        color: row.lit ? Qt.rgba(0.624, 0.937, 0.0, 0.45) : Qt.rgba(1, 1, 1, 0.09)
        Behavior on color { ColorAnimation { duration: 220 } }
    }

    // ---- node ------------------------------------------------------------ //
    Item {
        id: node
        width: 28
        height: 28
        x: 0
        y: Math.round((row.height - height) / 2)

        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 16
            height: width
            radius: width / 2
            color: row.accent
            opacity: row.isActive ? row.haloPulse : (row.isDone ? 0.16 : 0.0)
            layer.enabled: opacity > 0.002
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: 40
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: row.isDone ? row.accent
                 : row.isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.12)
                 : Qt.rgba(1, 1, 1, 0.03)
            border.width: 1.4
            border.color: row.isDone ? Qt.rgba(0.624, 0.937, 0.0, 1.0)
                        : row.isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.85)
                        : (row.isError || row.isWarn) ? row.accent
                        : Qt.rgba(1, 1, 1, 0.15)
            Behavior on color { ColorAnimation { duration: 220 } }
            Behavior on border.color { ColorAnimation { duration: 220 } }
        }

        Text {
            anchors.centerIn: parent
            visible: row.isDone || row.isError || row.isWarn || row.isSkipped
            text: row.isDone ? "\u2713" : row.isError ? "\u2715" : row.isWarn ? "!" : "\u2013"
            color: row.isDone ? "#06120a" : row.accent
            font.pixelSize: row.isDone ? 15 : 13
            font.bold: true
        }

        Text {
            anchors.centerIn: parent
            visible: row.isPending
            text: ("0" + (row.stageIndex + 1)).slice(-2)
            color: Qt.rgba(1, 1, 1, 0.32)
            font.pixelSize: 9
            font.bold: true
            font.letterSpacing: 0.5
        }

        Canvas {
            id: spinner
            anchors.fill: parent
            visible: row.isActive
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "#9fef00"
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                var r = Math.min(width, height) / 2 - 3
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, r, 0.25, Math.PI * 1.25)
                ctx.stroke()
            }
            RotationAnimation on rotation {
                running: row.isActive
                from: 0
                to: 360
                duration: 1100
                loops: Animation.Infinite
            }
        }
    }

    SequentialAnimation on haloPulse {
        running: row.isActive
        loops: Animation.Infinite
        NumberAnimation { to: 0.42; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.14; duration: 900; easing.type: Easing.InOutSine }
    }

    // ---- glass box ------------------------------------------------------- //
    Rectangle {
        id: box
        anchors.left: parent.left
        anchors.leftMargin: 44
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: 14
        color: "transparent"
        border.width: 1
        border.color: row.isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.55)
                      : row.isDone ? Qt.rgba(0.624, 0.937, 0.0, 0.22)
                      : row.isError ? Qt.rgba(1.0, 0.30, 0.43, 0.55)
                      : row.isWarn ? Qt.rgba(1.0, 0.69, 0.13, 0.45)
                      : Qt.rgba(1, 1, 1, 0.07)
        Behavior on border.color { ColorAnimation { duration: 220 } }

        Rectangle {
            id: fill
            anchors.fill: parent
            anchors.margins: 1
            radius: box.radius - 1
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: row.fillLeft }
                GradientStop { position: 1.0; color: row.fillRight }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 18
                radius: fill.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.045) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }

            Rectangle {
                visible: row.isActive
                y: fill.height - 2
                width: fill.width * 0.45
                height: 2
                radius: 1
                x: row.shimmerX
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.624, 0.937, 0.0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.624, 0.937, 0.0, 0.95) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.624, 0.937, 0.0, 0.0) }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: row.label
                    color: row.titleColor
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.35
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.info
                    color: row.detailColor
                    font.pixelSize: 9
                    elide: Text.ElideRight
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: pillText.implicitWidth + 16
                Layout.preferredHeight: 18
                radius: 9
                color: row.isActive ? Qt.rgba(0.624, 0.937, 0.0, 0.16)
                     : row.isDone ? Qt.rgba(0.624, 0.937, 0.0, 0.10)
                     : row.isError ? Qt.rgba(1.0, 0.30, 0.43, 0.18)
                     : row.isWarn ? Qt.rgba(1.0, 0.69, 0.13, 0.18)
                     : Qt.rgba(1, 1, 1, 0.05)

                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: row.statusText
                    color: row.isPending ? Qt.rgba(1, 1, 1, 0.32) : row.accent
                    font.pixelSize: 8
                    font.bold: true
                    font.letterSpacing: 1.0
                }
            }
        }
    }

    NumberAnimation on shimmerX {
        running: row.isActive
        loops: Animation.Infinite
        from: -180
        to: 380
        duration: 1700
        easing.type: Easing.InOutQuad
    }
}
