// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

// Plasma 6 requires the root item to be a PlasmoidItem.
// Everything visual lives in Widget.qml so the UI can also be rendered with
// plain `qml6` outside plasmashell (see dev/).
PlasmoidItem {
    id: applet

    // we paint our own liquid glass - keep the theme frame away
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // desktop widget: always the glass representation, never the compact one
    preferredRepresentation: fullRepresentation

    fullRepresentation: Widget {
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight
        Layout.minimumWidth: 340
        Layout.minimumHeight: implicitHeight
    }
}
