#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT

"""HTB Machine Launcher - backend runner for the KDE Plasma widget.

The widget drives one rung of the ladder per invocation (``--phase``):

    api     -> authenticate with labs.hackthebox.com and resolve the machine
    spawn   -> deploy the machine and wait for an IP
    vpn     -> bring up the OpenVPN tunnel (if not already up)
    burp    -> launch BurpSuite
    firefox -> launch Firefox on the machine URL

Each run prints a single JSON object on stdout and exits:

    {"stage": "spawn", "state": "done", "detail": "deployed at 10.129.1.2",
     "ip": "10.129.1.2"}

``state`` is one of: done, warn, skipped, error.  Errors exit non-zero, so the
widget can simply look at the exit code + payload.

The job arrives as one percent-encoded JSON blob (``--job``) so no secret is
ever split across shell arguments.  Standard library only - no pip packages.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import traceback
from urllib import error, parse, request

API_BASE = os.environ.get("HTB_LAUNCHER_API", "https://labs.hackthebox.com/api/v4")

# The App Token is never passed on a command line: the widget stores it in the
# plasmoid configuration and this backend reads it straight from Plasma's config
# file, so it cannot show up in `ps`.
PLASMOID_ID = "org.htb.machinelauncher"
APPLETRC_NAME = "plasma-org.kde.plasma.desktop-appletsrc"
CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache"),
    "htb-launcher")
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) htb-launcher/1.0"

SPAWN_TIMEOUT = 420      # seconds to wait for HTB to hand out an IP
VPN_TIMEOUT = 120        # seconds to wait for the tunnel interface

PHASES = ("api", "spawn", "vpn", "burp", "firefox")


# --------------------------------------------------------------------------- #
# plumbing
# --------------------------------------------------------------------------- #
def _kconfig_unescape(value: str) -> str:
    if "\\" not in value:
        return value
    out = []
    it = iter(value)
    for char in it:
        if char != "\\":
            out.append(char)
            continue
        nxt = next(it, "")
        out.append({"n": "\n", "t": "\t", "s": " ", "\\": "\\"}.get(nxt, nxt))
    return "".join(out)


def _kconfig_entries(path: str):
    """Yield (group_path_tuple, key, value) from a KConfig file."""
    group: tuple = ()
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line[0] in "#;":
                continue
            if line.startswith("[") and line.endswith("]"):
                group = tuple(part for part in line[1:-1].split("][") if part)
                continue
            if "=" in line:
                key, value = line.split("=", 1)
                yield group, key.strip(), _kconfig_unescape(value.strip())


def token_from_plasmoid_config(path: str | None = None) -> str:
    """Read the App Token from Plasma's applet config for this widget."""
    if path is None:
        config_home = (os.environ.get("XDG_CONFIG_HOME")
                       or os.path.join(os.path.expanduser("~"), ".config"))
        path = os.path.join(config_home, APPLETRC_NAME)
    try:
        entries = list(_kconfig_entries(path))
    except OSError:
        return ""

    plugins = {group: value for group, key, value in entries if key == "plugin"}
    for group, key, value in entries:
        if key != "appToken" or not value:
            continue
        if len(group) < 2 or group[-2:] != ("Configuration", "General"):
            continue
        if plugins.get(group[:-2]) == PLASMOID_ID:
            return value.strip()
    return ""


def emit(stage: str, state: str, detail: str = "", **extra) -> None:
    payload = {"stage": stage, "state": state, "detail": redact(detail)}
    payload.update(extra)
    try:
        sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except (BrokenPipeError, OSError):
        raise SystemExit(0)


_BEARER_RE = re.compile(r"(Bearer\s+)\S+", re.IGNORECASE)
_LONG_SECRET_RE = re.compile(r"[A-Za-z0-9\-_.=+/]{32,}")


def redact(text: str) -> str:
    """Never let a credential reach the widget log / stderr."""
    text = str(text)
    text = _BEARER_RE.sub(r"\1<redacted>", text)
    return _LONG_SECRET_RE.sub("<redacted>", text)


class StageError(RuntimeError):
    """Failure that belongs to a specific rung of the ladder."""

    def __init__(self, stage: str, message: str):
        super().__init__(message)
        self.stage = stage


ROUTE_ERROR_HINTS = ("could not be found", "method is not supported")


def is_route_error(exc: BaseException) -> bool:
    text = str(exc).lower()
    return any(hint in text for hint in ROUTE_ERROR_HINTS)


def friendly_error(exc: BaseException) -> str:
    """Turn HTB's raw errors into something actionable."""
    if isinstance(exc, ApiError) and exc.status == 429:
        return ("HTB rate limit (too many API calls) - wait a minute, then press "
                "SPAWN again; a machine that already finished spawning is reused")
    if is_route_error(exc):
        return (f"HTB changed their API ({exc}). "
                "Update the widget: https://github.com/vedant-sec/OneClickHTB")
    return str(exc)


class ApiError(RuntimeError):
    def __init__(self, status: int, message: str, retry_after: float | None = None):
        super().__init__(message)
        self.status = status
        self.retry_after = retry_after


# --------------------------------------------------------------------------- #
# HTB API
# --------------------------------------------------------------------------- #
def _message(data) -> str:
    if isinstance(data, dict):
        msg = data.get("message")
        if isinstance(msg, str) and msg.strip():
            return msg.strip()
        if isinstance(msg, dict):
            bits = []
            for key, value in msg.items():
                if isinstance(value, list):
                    value = ", ".join(str(v) for v in value)
                bits.append(f"{key}: {value}")
            if bits:
                return "; ".join(bits)
        errs = data.get("errors")
        if errs:
            return str(errs)
        err = data.get("error")
        if isinstance(err, str) and err.strip():
            return err.strip()
    return "request failed"


def _api(method: str, path: str, token: str | None = None, payload=None,
         timeout: int = 45):
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = request.Request(API_BASE + path, data=body, method=method)
    req.add_header("User-Agent", USER_AGENT)
    req.add_header("Accept", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return json.loads(raw) if raw.strip() else {}
    except error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            data = json.loads(raw)
        except Exception:
            data = {"message": raw.strip()[:300]}
        retry_after = None
        header = exc.headers.get("Retry-After") if exc.headers else None
        if header:
            try:
                retry_after = float(header)
            except ValueError:
                retry_after = None
        raise ApiError(exc.code, _message(data), retry_after) from None
    except error.URLError as exc:
        raise ApiError(0, f"cannot reach labs.hackthebox.com ({exc.reason})") from None
    except (TimeoutError, OSError) as exc:
        raise ApiError(0, redact(f"network error ({exc})")) from None
    except Exception as exc:
        raise ApiError(0, redact(f"request failed ({type(exc).__name__}: {exc})")) from None


def api(method: str, path: str, token: str | None = None, payload=None,
        tries: int = 3):
    """HTTP with retries for server errors.

    429 is deliberately *not* retried here: retrying a rate limit in a loop is
    exactly what keeps the limit tripped. Callers that can afford to wait (the
    spawn poller) handle 429 themselves with a real backoff.
    """
    last: ApiError | None = None
    for attempt in range(tries):
        try:
            return _api(method, path, token, payload)
        except ApiError as exc:
            last = exc
            if exc.status in (500, 502, 503, 504) and attempt + 1 < tries:
                time.sleep(2 + attempt * 2)
                continue
            raise
    raise last  # pragma: no cover


def check_token(token: str) -> dict:
    try:
        data = api("GET", "/user/info", token)
    except ApiError as exc:
        if exc.status == 401:
            raise ApiError(401, "HTB rejected the App Token (401) - "
                                "check it in the widget settings") from None
        raise
    info = data.get("info")
    return info if isinstance(info, dict) else {}


PAGE_LIMIT = 40


def _machine_items(data) -> list:
    """Pull the machine array out of a listing response (shape-tolerant)."""
    if not isinstance(data, dict):
        return []
    items = data.get("data")
    if isinstance(items, dict):
        items = items.get("machines") or items.get("data") or []
    if isinstance(items, list):
        return [m for m in items if isinstance(m, dict)]
    return []


def crawl_machines(token: str, path: str):
    """Walk every page of a machine listing. Returns (machines, notes)."""
    machines: list = []
    notes: list = []
    page = 1
    while page <= PAGE_LIMIT:
        try:
            try:
                data = api("GET", f"{path}?page={page}&per_page=100", token)
            except ApiError as exc:
                if exc.status not in (400, 422):   # per_page not understood
                    raise
                data = api("GET", f"{path}?page={page}", token)
        except ApiError as exc:
            label = "retired list" if path.endswith("retired") else "active list"
            notes.append(f"{label}: HTTP {exc.status} {exc}".strip())
            break

        items = _machine_items(data)
        if not items:
            break
        machines.extend(items)

        links = data.get("links") or {}
        meta = data.get("meta") or {}
        last = meta.get("last_page") or meta.get("total_pages") or 0
        has_next = bool(links.get("next"))
        if not has_next and not (isinstance(last, int) and page < last):
            break
        page += 1
    else:
        notes.append(f"stopped after {PAGE_LIMIT} pages")
    return machines, notes


def search_machines(token: str, query: str) -> list:
    """Best-effort name search - works even when a listing is unavailable."""
    query = query.strip()
    if not query:
        return []
    encoded = parse.quote(query)
    for path in (f"/search/fetch?query={encoded}",
                 f"/machine/search?query={encoded}"):
        try:
            data = api("GET", path, token)
        except ApiError:
            continue
        if not isinstance(data, dict):
            continue
        buckets = []
        for key in ("machines", "data", "results"):
            value = data.get(key)
            if isinstance(value, list):
                buckets.extend(value)
            elif isinstance(value, dict):
                for sub in ("machines", "data", "results"):
                    if isinstance(value.get(sub), list):
                        buckets.extend(value[sub])
        found = [m for m in buckets
                 if isinstance(m, dict) and m.get("id") and m.get("name")]
        if found:
            return found
    return []


def profile_machine(token: str, name: str):
    """Direct lookup: GET /machine/profile/<name> (case-insensitive on HTB).

    Returns (machine, note). This is the cheap, canonical path and also works
    for retired machines - the list crawl below is only a fallback.
    """
    try:
        data = api("GET", f"/machine/profile/{parse.quote(name.strip())}", token)
    except ApiError as exc:
        if exc.status in (400, 404, 422):
            return None, f"profile lookup HTTP {exc.status}"
        raise
    info = data.get("info") if isinstance(data, dict) else None
    if isinstance(info, dict) and info.get("id"):
        return info, ""
    return None, "profile lookup returned no machine"


def find_machine(token: str, name: str):
    """Resolve a machine by name.

    Order of preference:
      1. GET /machine/profile/<name>  - canonical, works for active + retired
      2. the search endpoint          - survives when listings are unavailable
      3. crawling /machine/list[/retired] - older deployments / partial names

    Returns (machine, detail); ``machine`` is None on failure and ``detail``
    explains what was actually attempted.
    """
    target = name.strip().lower()
    if not target:
        return None, "no machine name given"

    notes: list = []
    machine, note = profile_machine(token, name)
    if machine:
        return machine, ""
    if note:
        notes.append(note)

    # search endpoint: cheap and still alive when the list routes are not
    try:
        hits = search_machines(token, name)
    except ApiError as exc:
        hits = []
        notes.append(f"search: HTTP {exc.status}")

    for candidate in hits:
        if str(candidate.get("name", "")).strip().lower() == target:
            return candidate, ""

    # listings (may be retired in newer API revisions - 404 notes are dropped)
    pools: list = []
    for path in ("/machine/list", "/machine/list/retired"):
        machines, crawl_notes = crawl_machines(token, path)
        notes.extend(crawl_notes)
        pools.append(machines)
        for candidate in machines:
            if str(candidate.get("name", "")).strip().lower() == target:
                return candidate, ""

    # a single unambiguous partial match ("cap" -> "Cap")
    partial = {}
    for candidate in hits + [m for machines in pools for m in machines]:
        found = str(candidate.get("name", "")).strip()
        if found and target in found.lower():
            partial[found.lower()] = candidate
    if len(partial) == 1:
        return next(iter(partial.values())), ""
    if len(partial) > 1:
        names = ", ".join(sorted(str(m.get("name", "?")) for m in partial.values()))
        raise StageError("api", f"'{name.strip()}' matches several machines: {names}")

    scanned = sum(len(machines) for machines in pools)
    useful = [n for n in notes if "HTTP 404" not in n]   # dead routes are noise
    detail = f"machine '{name.strip()}' not found on HTB (profile lookup returned 404"
    if scanned:
        detail += f", scanned {scanned} machines"
    detail += ")"
    if useful:
        detail += f" [{'; '.join(useful)}]"
    return None, detail


def describe(machine: dict) -> str:
    bits = [str(machine.get("name") or "?")]
    os_name = machine.get("os")
    if os_name:
        bits.append(str(os_name).upper())
    diff = machine.get("difficultyText") or machine.get("difficulty")
    if diff:
        bits.append(str(diff))
    return "  ·  ".join(bits)


def active_info(token: str) -> dict:
    try:
        data = api("GET", "/machine/active", token)
    except ApiError as exc:
        if exc.status in (400, 404):
            return {}
        raise
    info = data.get("info") or data.get("data")
    return info if isinstance(info, dict) else {}


def active_info_patient(token: str, tries: int = 3) -> dict:
    """active_info() that waits out a short rate limit instead of failing."""
    for attempt in range(tries):
        try:
            return active_info(token)
        except ApiError as exc:
            if exc.status == 429 and attempt + 1 < tries:
                wait = exc.retry_after or 10 * (attempt + 1)
                print(f"HTB rate limit - retrying in {wait:.0f}s", file=sys.stderr)
                time.sleep(wait)
                continue
            raise
    return {}


def terminate_machine(token: str, machine_id=None) -> bool:
    """Terminate the active machine.

    HTB moved the VM lifecycle to /api/v4/vm/* (verified live 2026-11-12:
    /machine/terminate and /machine/reset are gone). Older routes are kept as
    fallbacks so the widget does not break if they come back.
    """
    payload = {"machine_id": machine_id} if machine_id else {}
    attempts = (
        ("POST", "/vm/terminate", payload),
        ("POST", "/machine/terminate", None),
        ("DELETE", "/machine/active", None),
    )
    for method, path, body in attempts:
        try:
            api(method, path, token, body)
            return True
        except ApiError as exc:
            if exc.status in (404, 405):
                continue
            raise
    return False


def spawn_machine(token: str, machine_id, terminate_existing: bool) -> dict:
    for attempt in range(3):
        try:
            return api("POST", "/vm/spawn", token, {"machine_id": machine_id})
        except ApiError as exc:
            if exc.status == 429:
                if attempt < 2:
                    wait = exc.retry_after or 15 * (attempt + 1)
                    print(f"HTB rate limit while spawning - retrying in {wait:.0f}s",
                          file=sys.stderr)
                    time.sleep(wait)
                    continue
                raise

            text = str(exc).lower()
            retryable = any(k in text for k in ("already", "active machine",
                                                "assigned", "terminate"))
            if terminate_existing and retryable:
                terminate_machine(token, machine_id)
                time.sleep(4)
                return api("POST", "/vm/spawn", token, {"machine_id": machine_id})
            raise
    raise ApiError(0, "could not reach HTB's spawn endpoint")


def wait_for_machine(token: str, machine_id, timeout: int = SPAWN_TIMEOUT):
    """Wait until the machine has an IP. Returns (ip, expires_at, name).

    Polls with an increasing delay (4 s -> 15 s) so a slow spawn costs ~30
    requests instead of ~100, and treats 429 as "keep waiting" rather than a
    fatal error - the box usually finishes spawning anyway.
    """
    deadline = time.time() + timeout
    delay = 4.0
    while time.time() < deadline:
        try:
            info = active_info(token)
        except ApiError as exc:
            if exc.status != 429:
                raise
            wait = exc.retry_after or min(delay * 2, 30)
            print(f"HTB rate limit while waiting - backing off {wait:.0f}s",
                  file=sys.stderr)
            time.sleep(min(wait, max(0.0, deadline - time.time())))
            delay = min(delay * 1.5, 20)
            continue

        if info and str(info.get("id", "")) == str(machine_id):
            ip = info.get("ip")
            if ip and not info.get("isSpawning"):
                return (str(ip), str(info.get("expires_at") or ""),
                        info.get("name"))

        time.sleep(min(delay, max(0.0, deadline - time.time())))
        delay = min(delay * 1.25, 15)
    raise ApiError(0, f"timed out after {timeout}s waiting for an IP "
                      "(HTB queue may be busy - press SPAWN again, an already "
                      "running machine is reused)")


MACHINE_LIFETIME = 24 * 3600     # seconds HTB keeps a machine alive per spawn


# --------------------------------------------------------------------------- #
# VPN
# --------------------------------------------------------------------------- #
def tunnel() -> tuple[str, str] | None:
    try:
        out = subprocess.run(["ip", "-o", "-4", "addr", "show"],
                             capture_output=True, text=True, timeout=10).stdout
    except Exception:
        return None
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        iface = parts[1].rstrip(":")
        if iface.startswith(("tun", "tap", "wg", "ppp")) and parts[2] == "inet":
            return iface, parts[3].split("/")[0]
    return None


def vpn_hint(code: int) -> str:
    return {
        126: "authorization cancelled",
        127: "openvpn or pkexec not installed",
        1: "openvpn failed - check the profile and the log",
    }.get(code, f"openvpn exited with code {code}")


def start_vpn(config_path: str, mode: str):
    os.makedirs(CACHE_DIR, exist_ok=True)
    log_path = os.path.join(CACHE_DIR, "openvpn.log")
    log = open(log_path, "ab", buffering=0)

    if mode == "pkexec":
        argv = ["pkexec", "openvpn", "--config", config_path]
    elif mode in ("sudo", "sudo-n"):
        argv = ["sudo", "-n", "openvpn", "--config", config_path]
    else:
        raise ApiError(0, f"unsupported VPN mode '{mode}'")

    if not shutil.which(argv[0]):
        raise ApiError(0, f"'{argv[0]}' not found - pick another VPN launch mode")

    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log,
                            stderr=log, start_new_session=True)
    return proc, log_path


def wait_vpn(proc, log_path: str, timeout: int = VPN_TIMEOUT):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = tunnel()
        if found:
            return found
        if proc is not None and proc.poll() is not None and proc.returncode != 0:
            raise ApiError(0, f"{vpn_hint(proc.returncode)} - see {log_path}")
        time.sleep(1)
    raise ApiError(0, f"no tunnel interface after {timeout}s - see {log_path}")


# --------------------------------------------------------------------------- #
# apps
# --------------------------------------------------------------------------- #
def resolve_command(spec: str | None):
    spec = (spec or "").strip()
    if not spec:
        return None
    try:
        parts = shlex.split(spec)
    except ValueError:
        return None
    if not parts:
        return None
    exe = os.path.expanduser(parts[0])
    if os.sep in exe:
        if os.access(exe, os.X_OK):
            return [exe] + parts[1:]
        return None
    found = shutil.which(exe)
    if not found:
        return None
    return [found] + parts[1:]


def launch_argv(argv) -> bool:
    if not argv:
        return False
    try:
        subprocess.Popen(list(argv),
                         stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL,
                         start_new_session=True,
                         cwd=os.path.expanduser("~"))
        return True
    except OSError:
        return False


def launch(spec: str | None, extra_args=()) -> bool:
    argv = resolve_command(spec)
    if argv is None:
        return False
    return launch_argv(argv + list(extra_args))


BURP_NAMES = ("burpsuite", "burpsuite_pro", "burpsuiteprofessional",
              "burpsuitepro", "burp", "burpsuite-community")

BURP_LAUNCHERS = (
    "~/Downloads/BurpSuite_pro/burpsuite_pro_launcher",
    "~/Downloads/BurpSuitePro/burpsuite_pro_launcher",
    "~/BurpSuite_pro/burpsuite_pro_launcher",
    "~/BurpSuitePro/burpsuite_pro_launcher",
    "~/tools/BurpSuite_pro/burpsuite_pro_launcher",
    "~/BurpSuiteCommunity/burpsuite_community_launcher",
    "~/Downloads/BurpSuiteCommunity/burpsuite_community_launcher",
    "~/BurpSuiteCommunity/burpsuite_community.sh",
)

BURP_JARS = (
    "~/BurpSuiteCommunity/burpsuite_community*.jar",
    "~/Downloads/BurpSuiteCommunity/burpsuite_community*.jar",
    "~/BurpSuiteCommunity/*community*.jar",
)


def desktop_exec_lines() -> list:
    """Exec= lines of every *burp*.desktop entry in the XDG data dirs."""
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dirs = [os.path.join(data_home, "applications")]
    for base in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if base:
            dirs.append(os.path.join(base, "applications"))

    lines = []
    for directory in dirs:
        try:
            entries = sorted(os.listdir(directory))
        except OSError:
            continue
        for name in entries:
            if not name.endswith(".desktop") or "burp" not in name.lower():
                continue
            try:
                with open(os.path.join(directory, name), encoding="utf-8",
                          errors="replace") as fh:
                    for line in fh:
                        if line.startswith("Exec="):
                            lines.append(line[5:].strip())
                            break
            except OSError:
                continue
    return lines


def burp_argv(spec: str | None):
    """Find BurpSuite. Returns (argv, label) or (None, reason).

    Order: explicit setting -> PATH -> burp*.desktop Exec -> known launchers
    -> community jar -> flatpak.
    """
    explicit = (spec or "").strip()
    if explicit:
        argv = resolve_command(explicit)
        if argv:
            return argv, explicit.split()[0]

    for name in BURP_NAMES:
        argv = resolve_command(name)
        if argv:
            return argv, name

    for exec_line in desktop_exec_lines():
        cleaned = re.sub(r"\s*%[a-zA-Z]", "", exec_line).strip()
        argv = resolve_command(cleaned)
        if argv:
            return argv, os.path.basename(argv[0])

    for launcher in BURP_LAUNCHERS:
        path = os.path.expanduser(launcher)
        if os.access(path, os.X_OK):
            return [path], os.path.basename(path)

    java = shutil.which("java")
    if java:
        for pattern in BURP_JARS:
            jars = sorted(glob.glob(os.path.expanduser(pattern)))
            jars = [j for j in jars if "loader" not in os.path.basename(j).lower()]
            if jars:
                return [java, "-jar", jars[-1]], os.path.basename(jars[-1])

    if shutil.which("flatpak"):
        try:
            listed = subprocess.run(
                ["flatpak", "list", "--app", "--columns=application"],
                capture_output=True, text=True, timeout=10).stdout
            if "com.portswigger.BurpSuite" in listed.split():
                return ["flatpak", "run", "com.portswigger.BurpSuite"], "flatpak BurpSuite"
        except (OSError, subprocess.SubprocessError):
            pass

    return None, explicit or "burpsuite"


# --------------------------------------------------------------------------- #
# phases
# --------------------------------------------------------------------------- #
def token_of(job: dict) -> str:
    """Resolve the App Token: explicit job value (CLI/tests) > env > config."""
    explicit = str(job.get("token") or "").strip()
    if explicit:
        return explicit
    from_env = os.environ.get("HTB_TOKEN", "").strip()
    if from_env:
        return from_env
    return token_from_plasmoid_config()


def guarded(stage: str, fn, *args, **kwargs):
    try:
        return fn(*args, **kwargs)
    except StageError:
        raise
    except ApiError as exc:
        raise StageError(stage, friendly_error(exc)) from None
    except (OSError, ValueError) as exc:
        raise StageError(stage, str(exc)) from None


def phase_api(job: dict) -> dict:
    token = token_of(job)
    machine_name = str(job.get("machine") or "").strip()
    if not token:
        raise StageError("api", "no App Token configured - open Configure -> "
                                "Launcher, paste it and press Apply")
    if not machine_name:
        raise StageError("api", "no machine name given")

    profile = guarded("api", check_token, token)
    machine, detail = guarded("api", find_machine, token, machine_name)
    if not machine:
        raise StageError("api", detail)

    who = profile.get("name") or "operator"
    return {
        "state": "done",
        "detail": describe(machine),
        "machine_id": machine.get("id"),
        "machine": machine.get("name"),
        "user": who,
    }


def phase_spawn(job: dict) -> dict:
    token = token_of(job)
    machine_id = job.get("machine_id")
    if not token or not machine_id:
        raise StageError("spawn", "missing credentials or machine id")

    info = guarded("spawn", active_info_patient, token)
    same = (info and str(info.get("id", "")) == str(machine_id)
            and info.get("ip") and not info.get("isSpawning"))
    if same:
        ip = str(info["ip"])
        return {"state": "done", "detail": f"already deployed at {ip}", "ip": ip,
                "expires_at": str(info.get("expires_at") or ""),
                "machine": info.get("name"), "lifetime": MACHINE_LIFETIME}

    if info and info.get("id") and str(info.get("id")) != str(machine_id):
        if not job.get("terminate_existing", True):
            raise StageError("spawn", "another machine is already active - "
                                      "enable auto-terminate or stop it on HTB")
        terminate_machine(token)
        time.sleep(3)

    reply = guarded("spawn", spawn_machine, token, machine_id,
                    bool(job.get("terminate_existing", True)))

    # some API revisions answer with the machine already resolved - if so we
    # can skip polling entirely
    reply_info = reply.get("info") if isinstance(reply, dict) else None
    if (isinstance(reply_info, dict) and reply_info.get("ip")
            and not reply_info.get("isSpawning")
            and str(reply_info.get("id", "")) == str(machine_id)):
        ip = str(reply_info["ip"])
        return {"state": "done", "detail": f"deployed at {ip}", "ip": ip,
                "expires_at": str(reply_info.get("expires_at") or ""),
                "machine": reply_info.get("name"), "lifetime": MACHINE_LIFETIME}

    ip, expires_at, name = guarded("spawn", wait_for_machine, token, machine_id)
    return {"state": "done", "detail": f"deployed at {ip}", "ip": ip,
            "expires_at": expires_at, "machine": name,
            "lifetime": MACHINE_LIFETIME}


def phase_vpn(job: dict) -> dict:
    mode = str(job.get("vpn_mode") or "pkexec").lower()
    has_ip = shutil.which("ip") is not None

    if has_ip:
        found = tunnel()
        if found:
            return {"state": "done", "detail": f"tunnel up on {found[0]} ({found[1]})",
                    "iface": found[0]}

    if mode == "none":
        return {"state": "skipped", "detail": "VPN launch disabled in settings"}

    config = os.path.expanduser(str(job.get("vpn_config") or "").strip())
    if not config:
        raise StageError("vpn", "no OpenVPN profile configured")
    if not os.path.isfile(config):
        raise StageError("vpn", f"profile not found: {config}")

    if not has_ip:
        return {"state": "warn",
                "detail": "iproute2 ('ip') not installed - cannot verify the tunnel, skipped"}

    proc, log_path = guarded("vpn", start_vpn, config, mode)
    iface, addr = guarded("vpn", wait_vpn, proc, log_path)
    return {"state": "done", "detail": f"tunnel up on {iface} ({addr})", "iface": iface}


def phase_burp(job: dict) -> dict:
    if not job.get("launch_burp", True):
        return {"state": "skipped", "detail": "disabled in settings"}
    argv, label = burp_argv(job.get("burp_cmd"))
    if not argv:
        return {"state": "warn",
                "detail": f"BurpSuite not found ('{label}') - set its command in settings"}
    if not launch_argv(argv):
        return {"state": "warn", "detail": f"could not start {label}"}
    return {"state": "done", "detail": f"launched {label}"}


def phase_firefox(job: dict) -> dict:
    if not job.get("launch_firefox", True):
        return {"state": "skipped", "detail": "disabled in settings"}
    ip = str(job.get("ip") or "")
    url = f"http://{ip}" if (job.get("open_url", True) and ip) else ""
    spec = job.get("firefox_cmd") or "firefox"
    if launch(spec, [url] if url else []):
        return {"state": "done", "detail": url or "Firefox launched"}
    return {"state": "warn", "detail": f"'{spec}' not found - skipped"}


def phase_terminate(job: dict) -> dict:
    """Stop the machine that is currently active (if any)."""
    token = token_of(job)
    if not token:
        raise StageError("terminate", "no App Token configured - open Configure -> "
                                      "Launcher, paste it and press Apply")

    info = guarded("terminate", active_info_patient, token)
    if not info or not info.get("id"):
        return {"state": "skipped", "detail": "no machine is running"}

    machine_id = info.get("id")
    name = str(info.get("name") or f"id {machine_id}")
    guarded("terminate", terminate_machine, token, machine_id)

    deadline = time.time() + 45
    while time.time() < deadline:
        if not active_info(token):
            return {"state": "done", "detail": f"{name} terminated"}
        time.sleep(2)
    return {"state": "warn",
            "detail": f"{name}: termination requested, HTB is still shutting it down"}


def phase_status(job: dict) -> dict:
    """Report the machine that is currently active (read-only)."""
    token = token_of(job)
    if not token:
        raise StageError("status", "no App Token configured")
    info = guarded("status", active_info_patient, token)
    if not info or not info.get("id"):
        return {"state": "skipped", "detail": "no machine is running"}
    return {
        "state": "done",
        "detail": f"{info.get('name')} is up at {info.get('ip')}",
        "machine": info.get("name"),
        "machine_id": info.get("id"),
        "ip": str(info.get("ip") or ""),
        "expires_at": str(info.get("expires_at") or ""),
        "spawning": bool(info.get("isSpawning")),
        "lifetime": MACHINE_LIFETIME,
    }


def reset_machine(token: str, machine_id) -> None:
    """Restart the active machine (which resets its 24h timer)."""
    for path in ("/vm/reset", "/machine/reset"):
        try:
            api("POST", path, token, {"machine_id": machine_id})
            return
        except ApiError as exc:
            if exc.status not in (400, 404, 405):
                raise
    # last resort: a terminate + spawn has the same effect
    terminate_machine(token, machine_id)
    time.sleep(3)
    spawn_machine(token, machine_id, False)


def phase_reset(job: dict) -> dict:
    token = token_of(job)
    if not token:
        raise StageError("reset", "no App Token configured - open Configure -> "
                                  "Launcher, paste it and press Apply")

    info = guarded("reset", active_info_patient, token)
    if not info or not info.get("id"):
        return {"state": "skipped", "detail": "no machine is running"}

    machine_id = info.get("id")
    name = str(info.get("name") or f"id {machine_id}")

    guarded("reset", reset_machine, token, machine_id)
    ip, expires_at, _ = guarded("reset", wait_for_machine, token, machine_id,
                                timeout=240)
    return {"state": "done", "detail": f"{name} restarted · timer reset",
            "machine": name, "machine_id": machine_id, "ip": ip,
            "expires_at": expires_at, "lifetime": MACHINE_LIFETIME}


PHASE_FUNCS = {
    "api": phase_api,
    "spawn": phase_spawn,
    "vpn": phase_vpn,
    "burp": phase_burp,
    "firefox": phase_firefox,
    "terminate": phase_terminate,
    "status": phase_status,
    "reset": phase_reset,
}


def run_phase(name: str, job: dict) -> dict:
    func = PHASE_FUNCS.get(name)
    if func is None:
        raise StageError(name, f"unknown phase '{name}'")
    return func(job)


def run_all(job: dict) -> int:
    """CLI helper: run every phase in order against a single job."""
    for name in PHASES:
        try:
            result = run_phase(name, job)
        except StageError as exc:
            emit(exc.stage, "error", str(exc))
            return 1
        emit(name, result.pop("state", "done"), result.pop("detail", ""), **result)
        for key in ("machine_id", "ip", "machine"):
            if key in result:
                job[key] = result[key]
    emit("__final__", "done", "ready", ip=job.get("ip", ""))
    return 0


def run_demo(job: dict) -> int:
    """Offline preview - prints the whole ladder with a small delay."""
    machine = str(job.get("machine") or "Soccer")
    script = [
        ("api", "running", "authenticating with labs.hackthebox.com..."),
        ("api", "done", f"{machine}  ·  LINUX  ·  Easy", {}),
        ("spawn", "done", "deployed at 10.129.42.7", {"ip": "10.129.42.7"}),
        ("vpn", "done", "tunnel up on tun0 (10.10.14.23)", {}),
        ("burp", "done", "BurpSuite launched", {}),
        ("firefox", "done", "http://10.129.42.7", {}),
    ]
    for stage, state, detail, extra in script:
        emit(stage, state, detail, **extra)
        time.sleep(0.9)
    emit("__final__", "done", "ready", ip="10.129.42.7", machine=machine)
    return 0


def _probe(method: str, path: str, token: str, payload=None):
    try:
        api(method, path, token, payload)
        return 200, "ok"
    except ApiError as exc:
        return exc.status, str(exc)


def probe_routes(token: str) -> dict:
    """Read-only health check of the routes the widget depends on.

    ``/vm/terminate`` is intentionally not probed: it ignores the id and would
    stop the machine that is currently running.
    """
    checks = (
        ("profile", "GET", "/machine/profile/Cap", None),
        ("active", "GET", "/machine/active", None),
        ("spawn", "POST", "/vm/spawn", {"machine_id": 999999}),
        ("reset", "POST", "/vm/reset", {"machine_id": 999999}),
    )
    report = {}
    for name, method, path, payload in checks:
        status, message = _probe(method, path, token, payload)
        dead = "could not be found" in message.lower() or \
               "method is not supported" in message.lower()
        report[name] = {
            "request": f"{method} {path}",
            "status": status,
            "alive": not dead,
            "note": message[:120],
        }
    report["terminate"] = {
        "request": "POST /vm/terminate",
        "status": None,
        "alive": None,
        "note": "not probed - it would stop the running machine",
    }
    return report


def diagnose(job: dict) -> dict:
    """Explain what a machine lookup actually sees (CLI debugging aid)."""
    token = token_of(job)
    query = str(job.get("machine") or "").strip()
    report: dict = {"query": query, "token_present": bool(token)}
    if not token:
        report["error"] = "no App Token given"
        return report

    try:
        report["user"] = (check_token(token) or {}).get("name")
    except ApiError as exc:
        report["user_error"] = str(exc)

    for path in ("/machine/list", "/machine/list/retired"):
        machines, notes = crawl_machines(token, path)
        report[path] = {
            "count": len(machines),
            "notes": notes,
            "matches": [m.get("name") for m in machines
                        if query and query.lower() in str(m.get("name", "")).lower()],
        }

    try:
        prof, note = profile_machine(token, query)
        report["profile_lookup"] = prof.get("name") if prof else (note or "not found")
    except ApiError as exc:
        report["profile_lookup"] = f"error: {exc}"

    report["search_endpoint"] = [m.get("name") for m in search_machines(token, query)]

    burp, burp_label = burp_argv(job.get("burp_cmd"))
    try:
        report["routes"] = probe_routes(token)
    except ApiError as exc:
        report["routes"] = {"error": str(exc)}

    report["tools"] = {
        "burpsuite": burp[0] if burp else f"not found ({burp_label})",
        "firefox": (resolve_command(job.get("firefox_cmd") or "firefox") or ["not found"])[0],
        "openvpn": shutil.which("openvpn") or "not found",
        "pkexec": shutil.which("pkexec") or "not found",
        "tunnel": (tunnel() or "down"),
    }

    try:
        machine, detail = find_machine(token, query)
        report["resolved"] = machine.get("name") if machine else None
        report["detail"] = detail
    except StageError as exc:
        report["resolved"] = None
        report["detail"] = str(exc)
    return report


# --------------------------------------------------------------------------- #
# entry point
# --------------------------------------------------------------------------- #
def build_job(args) -> dict:
    if args.job_json:
        return json.loads(args.job_json)
    if args.job:
        return json.loads(parse.unquote(args.job))
    return {}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="HTB Machine Launcher backend")
    parser.add_argument("--phase", choices=PHASES + ("terminate", "status", "reset"),
                        help="ladder rung to execute (or terminate/status/reset)")
    parser.add_argument("--job", help="percent-encoded JSON job (used by the widget)")
    parser.add_argument("--job-json", help="raw JSON job (handy for testing)")
    parser.add_argument("--machine", help="override machine name")
    parser.add_argument("--token", help="override App Token")
    parser.add_argument("--demo", action="store_true", help="simulate the whole ladder")
    parser.add_argument("--all", action="store_true", help="run every phase in order")
    parser.add_argument("--diagnose", action="store_true",
                        help="print what the machine lookup actually sees")
    args = parser.parse_args(argv)

    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    try:
        job = build_job(args)
    except Exception as exc:
        emit("api", "error", f"bad job payload: {exc}")
        return 2

    if args.machine:
        job["machine"] = args.machine
    if args.token:
        job["token"] = args.token

    try:
        if args.diagnose:
            print(json.dumps(diagnose(job), indent=2, ensure_ascii=False))
            return 0
        if args.demo:
            return run_demo(job)
        if args.all or not args.phase:
            return run_all(job)

        result = run_phase(args.phase, job)
        emit(args.phase, result.pop("state", "done"),
             result.pop("detail", ""), **result)
        return 0
    except StageError as exc:
        emit(exc.stage, "error", str(exc))
        return 1
    except KeyboardInterrupt:
        emit(args.phase or "api", "error", "cancelled")
        return 130
    except Exception as exc:
        emit(args.phase or "api", "error",
             redact(f"unexpected backend error ({type(exc).__name__}: {exc})"))
        return 1


if __name__ == "__main__":
    sys.exit(main())
