#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 vedant-sec
# SPDX-License-Identifier: MIT

"""Local mock of the HTB v4 API + end-to-end test of htb_spawn.py.

Runs the real backend against a fake API so the whole ladder can be verified
without touching hackthebox.com or spawning anything.

    python3 dev/test_backend.py
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, unquote, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "plasmoid", "org.htb.machinelauncher",
                      "contents", "scripts", "htb_spawn.py")

ACTIVE = [
    {"id": 57, "name": "Soccer", "os": "linux", "difficultyText": "Easy"},
    {"id": 58, "name": "Responder", "os": "windows", "difficultyText": "Easy"},
]
RETIRED = [
    {"id": 1, "name": "Lame", "os": "linux", "difficultyText": "Easy"},
    {"id": 2, "name": "Blue", "os": "windows", "difficultyText": "Easy"},
    {"id": 3, "name": "Cap", "os": "linux", "difficultyText": "Easy"},
    {"id": 4, "name": "Capital", "os": "linux", "difficultyText": "Medium"},
]

PAGE_SIZE = 2                 # deliberately small so paging is exercised
SPAWN_AFTER_POLLS = 2         # pretend HTB needs a couple of seconds
PORT = 0

STATE = {
    "active": None,
    "polls": 0,
    "term": 0,
    "forbid_active": False,
    "forbid_retired": False,
    "forbid_search": False,
    "forbid_profile": False,
    # current HTB v4 returns 404 for both list routes (verified live);
    # flip to True to exercise the crawl fallback
    "lists_work": False,
    "expires_at": "",
    "resets": 0,
    "spawns": 0,
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self):
        if self.headers.get("Authorization") != "Bearer test-token":
            self._json(401, {"error": "Unauthenticated."})
            return False
        return True

    def _listing(self, url, items):
        page = int(parse_qs(url.query).get("page", ["1"])[0])
        start = (page - 1) * PAGE_SIZE
        chunk = items[start:start + PAGE_SIZE]
        links = {}
        if start + PAGE_SIZE < len(items):
            links["next"] = f"http://127.0.0.1:{PORT}{url.path}?page={page + 1}"
        meta = {"last_page": (len(items) + PAGE_SIZE - 1) // PAGE_SIZE}
        self._json(200, {"data": chunk, "links": links, "meta": meta})

    def do_GET(self):
        if not self._auth():
            return
        url = urlparse(self.path)
        path = url.path

        if path.endswith("/user/info"):
            return self._json(200, {"info": {"id": 7, "name": "tester"}})

        if path.endswith("/machine/list/retired") or path.endswith("/machine/list"):
            if not STATE["lists_work"]:
                return self._json(404, {"message":
                    f"The route api/v4{path} could not be found."})
            if path.endswith("retired"):
                if STATE["forbid_retired"]:
                    return self._json(403, {"message": "Retired machines need a subscription"})
                return self._listing(url, RETIRED)
            if STATE["forbid_active"]:
                return self._json(403, {"message": "Forbidden"})
            return self._listing(url, ACTIVE)

        if path.endswith("/search/fetch") or path.endswith("/machine/search"):
            if STATE["forbid_search"]:
                return self._json(404, {"message": "not found"})
            query = parse_qs(url.query).get("query", [""])[0].lower()
            hits = [m for m in ACTIVE + RETIRED if query in m["name"].lower()]
            return self._json(200, {"machines": hits})

        if "/machine/profile/" in path:
            if STATE["forbid_profile"]:
                return self._json(404, {"message": "Machine not found"})
            wanted = unquote(path.rsplit("/", 1)[-1]).strip().lower()
            for machine in ACTIVE + RETIRED:
                if machine["name"].lower() == wanted:
                    return self._json(200, {"info": machine})
            return self._json(404, {"message": "Machine not found"})

        if path.endswith("/machine/active"):
            if STATE["active"] is None:
                return self._json(200, {"info": {}})
            STATE["polls"] += 1
            spawning = STATE["polls"] < SPAWN_AFTER_POLLS
            if not STATE["expires_at"]:
                STATE["expires_at"] = time.strftime(
                    "%Y-%m-%d %H:%M:%S", time.gmtime(time.time() + 86400))
            return self._json(200, {"info": {
                "id": STATE["active"],
                "name": "Soccer",
                "ip": None if spawning else "10.129.42.7",
                "isSpawning": spawning,
                "expires_at": STATE["expires_at"],
            }})

        return self._json(404, {"message": "not found"})

    def do_POST(self):
        if not self._auth():
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        path = urlparse(self.path).path

        if "/machine/profile/" in path:
            if STATE["forbid_profile"]:
                return self._json(404, {"message": "Machine not found"})
            wanted = unquote(path.rsplit("/", 1)[-1]).strip().lower()
            for machine in ACTIVE + RETIRED:
                if machine["name"].lower() == wanted:
                    return self._json(200, {"info": machine})
            return self._json(404, {"message": "Machine not found"})

        if path.endswith("/machine/active"):
            STATE["active"] = body.get("machine_id")
            STATE["polls"] = 0
            return self._json(200, {"message": "Machine spawned"})

        # --- current HTB v4 VM lifecycle routes (verified live) -------------
        if path.endswith("/vm/spawn"):
            if body.get("machine_id") not in {m["id"] for m in ACTIVE + RETIRED}:
                return self._json(404, {"message": "No results for this machine"})
            STATE["active"] = body["machine_id"]
            STATE["polls"] = 0
            STATE["spawns"] += 1
            STATE["expires_at"] = time.strftime(
                "%Y-%m-%d %H:%M:%S", time.gmtime(time.time() + 86400))
            return self._json(200, {"message": "Machine spawned"})

        if path.endswith("/vm/terminate"):
            # like the real endpoint: terminates the active machine, id ignored
            STATE["active"] = None
            STATE["term"] += 1
            return self._json(200, {"message": "Machine terminated.", "success": True})

        if path.endswith("/vm/reset"):
            if body.get("machine_id") not in {m["id"] for m in ACTIVE + RETIRED}:
                return self._json(422, {"message": "The selected machine id is invalid."})
            STATE["resets"] += 1
            STATE["polls"] = 0
            STATE["expires_at"] = time.strftime(
                "%Y-%m-%d %H:%M:%S", time.gmtime(time.time() + 86400))
            return self._json(200, {"message": "Machine reset"})

        # --- retired routes must fail exactly like the real API -------------
        if path.endswith("/machine/active"):
            return self._json(405, {"message": "The POST method is not supported for "
                                    "route api/v4/machine/active. Supported methods: GET, HEAD."})

        return self._json(404, {"message": f"The route api/v4{path} could not be found."})

    def do_DELETE(self):
        if not self._auth():
            return
        STATE["active"] = None
        return self._json(200, {"message": "terminated"})


def run(args, env, timeout=120):
    return subprocess.run([sys.executable, SCRIPT] + args, capture_output=True,
                          text=True, env=env, timeout=timeout)


def last_json(stdout):
    lines = [line for line in stdout.strip().splitlines() if line.startswith("{")]
    return json.loads(lines[-1]) if lines else {}


def main():
    global PORT
    server = HTTPServer(("127.0.0.1", 0), Handler)
    PORT = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    env = dict(os.environ)
    env["HTB_LAUNCHER_API"] = f"http://127.0.0.1:{PORT}"
    # hermetic: hide `ip` so tests do not depend on the host having a tunnel up,
    # and give the backend a throwaway HOME/XDG tree so tool autodetection never
    # picks up the developer's real BurpSuite install
    env["PATH"] = tempfile.mkdtemp(prefix="htb-test-bin-")
    sandbox_home = tempfile.mkdtemp(prefix="htb-test-home-")
    apps = os.path.join(sandbox_home, ".local", "share", "applications")
    os.makedirs(apps, exist_ok=True)
    env["HOME"] = sandbox_home
    env["XDG_DATA_HOME"] = os.path.join(sandbox_home, ".local", "share")
    env["XDG_DATA_DIRS"] = os.path.join(sandbox_home, "share")
    env["XDG_CONFIG_HOME"] = os.path.join(sandbox_home, ".config")
    env.pop("HTB_TOKEN", None)          # token must come from the applet config

    failures = []

    def check(name, cond, extra=""):
        print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else f"  {extra}"))
        if not cond:
            failures.append(name)

    def reset(**kw):
        STATE.update({"active": None, "polls": 0, "term": 0,
                      "forbid_active": False, "forbid_retired": False,
                      "forbid_search": False, "forbid_profile": False,
                      "lists_work": False, "expires_at": "", "resets": 0,
                      "spawns": 0})
        STATE.update(kw)

    def api_phase(machine, **kw):
        reset(**kw)
        job = {"machine": machine, "token": "test-token"}
        return run(["--phase", "api", "--job-json", json.dumps(job)], env)

    print("1) reject bad token")
    r = run(["--phase", "api", "--job-json",
             json.dumps({"machine": "Soccer", "token": "nope"})], env)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("token error surfaced", "rejected" in r.stdout.lower(), r.stdout)

    print("2) api phase resolves an active machine")
    r = api_phase("soccer")
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("state done", payload.get("state") == "done", payload)
    check("machine id", payload.get("machine_id") == 57, payload)
    check("detail has name+os", "Soccer" in payload["detail"] and "LINUX" in payload["detail"], payload)

    print("3) retired machine resolved by direct profile lookup ('cap')")
    r = api_phase("cap")
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("resolved Cap", payload.get("machine") == "Cap", payload)
    check("machine id 3", payload.get("machine_id") == 3, payload)

    print("3b) ... and by crawling the paginated retired list if profile 404s")
    r = api_phase("cap", forbid_profile=True, lists_work=True)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("resolved Cap via crawl", payload.get("machine") == "Cap", payload)
    check("machine id 3", payload.get("machine_id") == 3, payload)

    print("4) unique partial name ('soc' -> Soccer)")
    r = api_phase("soc", forbid_profile=True, lists_work=True)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("resolved Soccer", payload.get("machine") == "Soccer", payload)

    print("5) ambiguous partial name is refused")
    r = api_phase("ca", forbid_profile=True, lists_work=True)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("lists candidates", "matches several machines" in r.stdout, r.stdout)

    print("6) unknown name gives a clean 404 message")
    r = api_phase("zzz")
    payload = last_json(r.stdout)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("says not found", "not found on HTB" in payload.get("detail", ""), payload)
    check("mentions 404", "404" in payload.get("detail", ""), payload)

    print("6b) crawl reports what it scanned when the profile route fails")
    r = api_phase("zzz", forbid_profile=True, forbid_search=True, lists_work=True)
    payload = last_json(r.stdout)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("scanned count", "scanned 6 machines" in payload.get("detail", ""), payload)

    print("7) forbidden retired list is surfaced in the message")
    r = api_phase("red", forbid_profile=True, forbid_retired=True,
                  forbid_search=True, lists_work=True)
    payload = last_json(r.stdout)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("mentions HTTP 403", "403" in payload.get("detail", ""), payload)
    check("mentions retired list", "retired list" in payload.get("detail", ""), payload)

    print("8) search endpoint rescues a lookup when listings fail")
    r = api_phase("cap", forbid_profile=True, forbid_active=True,
                  forbid_retired=True, lists_work=True)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("resolved via search", payload.get("machine") == "Cap", payload)

    print("9) diagnose explains the lookup")
    reset()
    r = run(["--diagnose", "--job-json",
             json.dumps({"machine": "cap", "token": "test-token"})], env)
    report = json.loads(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("user resolved", report.get("user") == "tester", report)
    check("tools reported", "burpsuite" in report.get("tools", {}), report)
    check("retired route reported dead", report["/machine/list/retired"]["count"] == 0, report)
    check("profile lookup found it", report.get("profile_lookup") == "Cap", report)
    check("resolved Cap", report.get("resolved") == "Cap", report)

    print("10) full ladder (spawn waits for the IP)")
    reset()
    job = {"machine": "Soccer", "token": "test-token", "vpn_mode": "none",
           "launch_burp": False, "launch_firefox": False}
    r = run(["--all", "--job-json", json.dumps(job)], env)
    lines = [json.loads(line) for line in r.stdout.strip().splitlines() if line.startswith("{")]
    by_stage = {line["stage"]: line for line in lines}
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("api done", by_stage.get("api", {}).get("state") == "done", lines)
    check("spawn done", by_stage.get("spawn", {}).get("state") == "done", lines)
    check("spawn ip", by_stage.get("spawn", {}).get("ip") == "10.129.42.7", lines)
    check("used POST /vm/spawn", STATE["spawns"] == 1, STATE)
    check("vpn skipped", by_stage.get("vpn", {}).get("state") == "skipped", lines)
    check("burp skipped", by_stage.get("burp", {}).get("state") == "skipped", lines)
    check("firefox skipped", by_stage.get("firefox", {}).get("state") == "skipped", lines)
    check("final done", by_stage.get("__final__", {}).get("state") == "done", lines)

    print("11) existing machine is reused, not respawned")
    reset(active=57, polls=99)
    job = {"machine": "Soccer", "token": "test-token", "machine_id": 57,
           "vpn_mode": "none", "launch_burp": False, "launch_firefox": False}
    r = run(["--phase", "spawn", "--job-json", json.dumps(job)], env)
    payload = last_json(r.stdout)
    check("state done", payload.get("state") == "done", payload)
    check("no terminate", STATE["term"] == 0, STATE)
    check("says already deployed", "already" in payload.get("detail", ""), payload)

    print("12) switching machines terminates the old one")
    reset(active=1, polls=99)
    job = {"machine": "Soccer", "token": "test-token", "machine_id": 57,
           "vpn_mode": "none", "launch_burp": False, "launch_firefox": False,
           "terminate_existing": True}
    r = run(["--phase", "spawn", "--job-json", json.dumps(job)], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("terminated old machine", STATE["term"] == 1, STATE)
    check("used POST /vm/terminate", STATE["term"] == 1, STATE)
    check("spawned ip", payload.get("ip") == "10.129.42.7", payload)

    print("14) burp: missing tool asks for the setting")
    job = {"launch_burp": True, "burp_cmd": "burpsuite"}
    r = run(["--phase", "burp", "--job-json", json.dumps(job)], env)
    payload = last_json(r.stdout)
    check("warn state", payload.get("state") == "warn", payload)
    check("points at settings", "in settings" in payload.get("detail", ""), payload)

    print("15) burp: detected from a burp*.desktop entry")
    with open(os.path.join(apps, "burpsuite-professional.desktop"), "w") as fh:
        fh.write("[Desktop Entry]\nName=BurpSuite Professional\n"
                 "Exec=/bin/echo burp %U\n")
    r = run(["--phase", "burp", "--job-json", json.dumps(job)], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("done state", payload.get("state") == "done", payload)
    check("reports what it launched", "launched echo" in payload.get("detail", ""), payload)

    print("16) burp: explicit setting wins over autodetection")
    job2 = {"launch_burp": True, "burp_cmd": "/bin/true"}
    r = run(["--phase", "burp", "--job-json", json.dumps(job2)], env)
    payload = last_json(r.stdout)
    check("done state", payload.get("state") == "done", payload)
    check("launched true", "launched /bin/true" in payload.get("detail", "") or
          "launched true" in payload.get("detail", ""), payload)

    print("17) terminate stops the active machine")
    reset(active=57, polls=99)
    r = run(["--phase", "terminate", "--job-json",
             json.dumps({"token": "test-token"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("done state", payload.get("state") == "done", payload)
    check("reports machine name", "Soccer" in payload.get("detail", ""), payload)
    check("active cleared", STATE["active"] is None, STATE)

    print("17b) terminate with nothing running is not an error")
    reset()
    r = run(["--phase", "terminate", "--job-json",
             json.dumps({"token": "test-token"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("skipped state", payload.get("state") == "skipped", payload)
    check("message", "no machine is running" in payload.get("detail", ""), payload)

    print("19) status reports the active machine and its expiry")
    reset(active=57, polls=99)
    r = run(["--phase", "status", "--job-json", json.dumps({"token": "test-token"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("done state", payload.get("state") == "done", payload)
    check("machine name", payload.get("machine") == "Soccer", payload)
    check("has ip", payload.get("ip") == "10.129.42.7", payload)
    check("has expiry", bool(payload.get("expires_at")), payload)
    check("lifetime", payload.get("lifetime") == 86400, payload)

    print("20) reset restarts the machine and refreshes the expiry")
    reset(active=57, polls=99)
    r = run(["--phase", "reset", "--job-json", json.dumps({"token": "test-token"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("done state", payload.get("state") == "done", payload)
    check("reset endpoint used", STATE["resets"] == 1, STATE)
    check("new expiry returned", bool(payload.get("expires_at")), payload)
    check("same ip back", payload.get("ip") == "10.129.42.7", payload)
    check("says timer reset", "timer reset" in payload.get("detail", ""), payload)

    print("20b) reset with nothing running is not an error")
    reset()
    r = run(["--phase", "reset", "--job-json", json.dumps({"token": "test-token"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("skipped state", payload.get("state") == "skipped", payload)

    print("22) token is read from Plasma's applet config, not argv")
    os.makedirs(env["XDG_CONFIG_HOME"], exist_ok=True)
    appletrc = os.path.join(env["XDG_CONFIG_HOME"],
                            "plasma-org.kde.plasma.desktop-appletsrc")
    with open(appletrc, "w") as fh:
        fh.write("[Containments][1][Applets][9]\n"
                 "plugin=org.kde.digitalclock\n"
                 "[Containments][1][Applets][9][Configuration][General]\n"
                 "appToken=wrong-foreign-token\n"
                 "[Containments][1][Applets][2]\n"
                 "plugin=org.htb.machinelauncher\n"
                 "[Containments][1][Applets][2][Configuration][General]\n"
                 "appToken=test-token\\n\n"      # escaped trailing newline in the value
                 "lastMachine=Cap\n")
    reset(active=57, polls=99)
    r = run(["--phase", "status", "--job-json", json.dumps({"machine": "Soccer"})], env)
    payload = last_json(r.stdout)
    check("exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("done state", payload.get("state") == "done", payload)
    check("only our applet's token used", "wrong-foreign-token" not in r.stdout, r.stdout)
    check("token never echoed", "test-token" not in r.stdout, r.stdout)

    print("22b) missing token is reported, not guessed")
    bare = dict(env)
    bare["HOME"] = tempfile.mkdtemp(prefix="htb-test-bare-")
    bare["XDG_CONFIG_HOME"] = os.path.join(bare["HOME"], ".config")
    r = run(["--phase", "status", "--job-json", json.dumps({"machine": "Soccer"})], bare)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("mentions the App Token", "App Token" in r.stdout, r.stdout)

    print("22c) redaction helper scrubs bearer tokens")
    import importlib.util
    spec = importlib.util.spec_from_file_location("htb_spawn_under_test", SCRIPT)
    hb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hb)
    raw = "Bearer abcdefghijklmnopqrstuvwxyz0123456789"
    check("bearer redacted", "abcdefghij" not in hb.redact(raw), hb.redact(raw))
    check("long secret redacted",
          "abcdefghij" not in hb.redact("x abcdefghijklmnopqrstuvwxyz0123456789 y"),
          hb.redact("x abcdefghijklmnopqrstuvwxyz0123456789 y"))

    print("21) vpn phase requires a profile")
    job = {"vpn_mode": "pkexec", "vpn_config": "/nonexistent/x.ovpn"}
    r = run(["--phase", "vpn", "--job-json", json.dumps(job)], env)
    check("exit != 0", r.returncode != 0, r.stdout)
    check("profile message", "profile not found" in r.stdout.lower(), r.stdout)

    server.shutdown()

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        return 1
    print("all backend checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
