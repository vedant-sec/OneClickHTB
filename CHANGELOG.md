# Changelog

All notable changes to **OneClickHTB**. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [1.0.0] — 2026-11-13

First public release.

### Added

- Five-rung ladder widget: **HTB API → spawn → OpenVPN → BurpSuite → Firefox**,
  with queued / spinning / ✓ / ✕ states and a live shimmer on the active rung.
- Liquid-glass, neon-on-dark UI: frosted panel, drifting light blobs, rim light,
  specular sheen, drawn ladder mark, per-rung glow and a runtime log overlay.
- Live machine read-out in the header: `Cap · active 16h 56m · expires in 7h 04m`,
  derived from HTB's `expires_at` and ticking every second.
- **STOP** (terminate whatever machine is active, then reset the widget) and
  **RESET** (restart the machine, which resets its 24 h timer).
- BurpSuite auto-detection: explicit setting → `PATH` → any `*burp*.desktop`
  `Exec=` line → known launcher/jar paths → Flatpak.
- Offline demo mode for previews and store screenshots.
- `--diagnose` report: user, machine lookup, tool detection, tunnel and
  per-route health (`/machine/profile`, `/machine/active`, `/vm/spawn`,
  `/vm/reset`) using a bogus id so it is always safe to run.

### Security

- The App Token is **never passed on a command line**: the backend reads it from
  Plasma's applet config, so it cannot appear in `ps` output.
- Every backend message is scrubbed through a redaction pass (`Bearer …` and
  long secret-looking strings become `<redacted>`), including the log drawer.
- MIT licensed, SPDX headers on every source file.

### Fixed

- HTB moved the VM lifecycle to `/api/v4/vm/*` — `POST /machine/active`,
  `/machine/terminate` and `/machine/reset` now answer `405`/`404`. Spawn,
  stop and reset use the new routes with legacy fallbacks.
- Machine lookup uses `GET /machine/profile/<name>` (case-insensitive, works for
  retired machines) instead of the removed `/machine/list` routes.
- Plasma 6 packaging rules: root item must be a `PlasmoidItem`, and
  `ConfigCategory.source` is resolved relative to `contents/ui/`.
- Tokens pasted with a trailing newline no longer produce
  `Invalid header value` errors.
- Clear error when the Python interpreter is missing (`exit 127`).

### Packaging

- `./install.sh` with dependency checks, icon installation and `--uninstall`.
- `scripts/pack.py` builds `dist/oneclickhtb-<version>.plasmoid`.
- `packaging/PKGBUILD` for AUR.

[1.0.0]: https://github.com/vedant-sec/OneClickHTB/releases/tag/v1.0.0
