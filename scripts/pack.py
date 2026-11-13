#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT
"""Build dist/oneclickhtb-<version>.plasmoid (a zip Plasma can install natively).

    ./scripts/pack.py

The metadata.json sits at the archive root, which is what KPackage expects for
`kpackagetool6 --install file.plasmoid` and "Install from file" in Plasma.
"""
from __future__ import annotations

import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = os.path.join(ROOT, "plasmoid", "org.htb.machinelauncher")
DIST = os.path.join(ROOT, "dist")


def main() -> int:
    meta_path = os.path.join(PKG, "metadata.json")
    if not os.path.isfile(meta_path):
        print(f"error: {meta_path} not found", file=sys.stderr)
        return 1

    with open(meta_path, encoding="utf-8") as fh:
        version = json.load(fh)["KPlugin"]["Version"]

    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, f"oneclickhtb-{version}.plasmoid")

    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, dirs, files in os.walk(PKG):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__")
            for name in sorted(files):
                if name.endswith((".pyc", ".pyo")):
                    continue
                full = os.path.join(root, name)
                archive.write(full, os.path.relpath(full, PKG))
                count += 1

    print(f"{out}  ({count} files, version {version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
