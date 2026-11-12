#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT

# Install / upgrade the HTB Machine Launcher plasmoid.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE/plasmoid/org.htb.machinelauncher"
ID="org.htb.machinelauncher"

if [[ ! -f "$PKG/metadata.json" ]]; then
    echo "error: package not found at $PKG" >&2
    exit 1
fi

chmod +x "$PKG/contents/scripts/htb_spawn.py"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$ID"; then
    echo ">> upgrading $ID"
    kpackagetool6 --type Plasma/Applet --upgrade "$PKG"
else
    echo ">> installing $ID"
    kpackagetool6 --type Plasma/Applet --install "$PKG"
fi

echo
echo "Done. Next steps:"
echo "  1. Right-click the desktop -> Enter Edit Mode -> Add Widgets..."
echo "  2. Search for \"HTB Machine Launcher\" and drag it onto the desktop"
echo "  3. Right-click the widget -> Configure -> Launcher -> paste your App Token"
echo
echo "If the widget does not appear, restart plasmashell:"
echo "  systemctl --user restart plasma-plasmashell.service"
