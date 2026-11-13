#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT
#
# Install / upgrade / remove the OneClickHTB plasmoid (KDE Plasma 6).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE/plasmoid/org.htb.machinelauncher"
ID="org.htb.machinelauncher"
ICON_SRC="$HERE/assets/icons/oneclickhtb.svg"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
ICON_DST="$ICON_DIR/oneclickhtb.svg"

ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m %s\n' "$*"; }
die()  { printf '  \033[31merr\033[0m  %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
OneClickHTB — KDE Plasma 6 widget

Usage: ./install.sh [--uninstall] [--help]

  (no option)   install or upgrade the widget for the current user
  --uninstall   remove the widget and its icon
  --help        this text

Requires KDE Plasma 6 (the plasmoid API 6.0), python3 and iproute2.
EOF
}

check_plasma() {
    command -v kpackagetool6 >/dev/null 2>&1 \
        || die "kpackagetool6 not found - this widget needs KDE Plasma 6 (Plasma 5 is not supported)."

    if command -v plasmashell >/dev/null 2>&1; then
        local version
        version="$(plasmashell --version 2>/dev/null | awk '{print $2}' | cut -d. -f1)"
        if [[ "${version:-6}" =~ ^[0-9]+$ ]] && (( version < 6 )); then
            die "Plasma $version detected - this widget requires Plasma 6."
        fi
    fi
    ok "KDE Plasma 6 detected"
}

check_deps() {
    if command -v python3 >/dev/null 2>&1; then
        ok "python3: $(command -v python3)"
    else
        warn "python3 not found - the ladder cannot run (install python, or set a path in Configure)"
    fi

    if command -v ip >/dev/null 2>&1; then
        ok "iproute2 detected"
    else
        warn "iproute2 ('ip') not found - the VPN stage cannot verify the tunnel"
    fi

    if command -v pkexec >/dev/null 2>&1 || command -v sudo >/dev/null 2>&1; then
        ok "elevation helper detected"
    else
        warn "neither pkexec nor sudo found - the OpenVPN stage will not start"
    fi

    command -v openvpn >/dev/null 2>&1 \
        && ok "openvpn detected" \
        || warn "openvpn not found - the VPN stage will be skipped"
}

install_icon() {
    [[ -f "$ICON_SRC" ]] || return 0
    install -Dm644 "$ICON_SRC" "$ICON_DST"
    ok "icon installed to $ICON_DST"
}

uninstall() {
    check_plasma
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$ID"; then
        kpackagetool6 --type Plasma/Applet --remove "$ID"
        ok "removed $ID"
    else
        warn "$ID is not installed"
    fi
    rm -f "$ICON_DST"
    echo
    echo "Your App Token is still stored in Plasma's config. Remove it with:"
    echo "  Configure -> Launcher -> clear 'App Token' -> Apply"
    echo "or delete the widget's config group from"
    echo "  ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --uninstall|--remove|-r) uninstall; exit 0 ;;
    "") ;;
    *) usage; exit 1 ;;
esac

[[ -f "$PKG/metadata.json" ]] || die "package not found at $PKG"

echo "OneClickHTB"
check_plasma
check_deps
chmod +x "$PKG/contents/scripts/htb_spawn.py"

if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$ID"; then
    kpackagetool6 --type Plasma/Applet --upgrade "$PKG" >/dev/null
    ok "upgraded $ID"
else
    kpackagetool6 --type Plasma/Applet --install "$PKG" >/dev/null
    ok "installed $ID"
fi

install_icon

cat <<'EOF'

Next steps
  1. Right-click the desktop -> Enter Edit Mode -> Add Widgets...
  2. Search for "OneClickHTB" and drag it onto the desktop
  3. Right-click the widget -> Configure -> Launcher -> paste your App Token

If the widget does not appear, restart the shell:
  systemctl --user restart plasma-plasmashell.service
EOF
