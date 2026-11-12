#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT

# Smoke test: load the applet in a real Plasma applet context (plasmawindowed
# creates an actual Plasma::Applet, so PlasmoidItem / Plasmoid.* / plasmoid
# configuration are all enforced) and fail on any QML error.
#
# A window pops up for ~10s while this runs.
set -uo pipefail

ID="org.htb.machinelauncher"
command -v plasmawindowed >/dev/null || { echo "plasmawindowed not installed"; exit 2; }

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

QT_FORCE_STDERR_LOGGING=1 timeout 10 plasmawindowed "$ID" >"$LOG" 2>&1 || true

if grep -qiE "error when loading applet|\\.qml:[0-9]+:[0-9]+:|must be of type PlasmoidItem|Non-existent attached object" "$LOG"; then
    echo "FAIL: QML errors while loading $ID"
    grep -viE "legacy metadata.desktop" "$LOG"
    exit 1
fi

echo "ok: $ID loaded with no QML errors"
