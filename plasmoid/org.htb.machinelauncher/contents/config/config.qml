// SPDX-FileCopyrightText: 2026 vedant-sec
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.plasma.configuration

// NOTE: ConfigCategory.source is resolved relative to contents/ui/
// (see e.g. org.kde.plasma.systemmonitor), not contents/config/.
ConfigModel {
    ConfigCategory {
        name: "Launcher"
        icon: "configure"
        source: "config/ConfigGeneral.qml"
    }
}
