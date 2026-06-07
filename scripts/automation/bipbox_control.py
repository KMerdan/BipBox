#!/usr/bin/env python3
"""bipbox_control.py — drive the running Bipbox app via its localhost control API.

Start the app with the API enabled:
    BIPBOX_CONTROL_API=1 BIPBOX_CONTROL_PORT=7777 .build/Bipbox.app/Contents/MacOS/BipboxApp

Then, for example:
    python3 scripts/automation/bipbox_control.py state
    python3 scripts/automation/bipbox_control.py add ~/Downloads --depth all
    python3 scripts/automation/bipbox_control.py search report
    python3 scripts/automation/bipbox_control.py navigate inbox

No third-party deps (uses urllib). Set BIPBOX_CONTROL_TOKEN to match the app.
"""
import json
import os
import sys
import urllib.request

BASE = f"http://127.0.0.1:{os.environ.get('BIPBOX_CONTROL_PORT', '7777')}"
TOKEN = os.environ.get("BIPBOX_CONTROL_TOKEN")


def _request(path, method="GET", body=None):
    headers = {"Content-Type": "application/json"}
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.load(resp)


def state():
    return _request("/state")


def command(**fields):
    return _request("/command", method="POST", body=fields)


def _summarize(snap):
    print(json.dumps({
        "section": snap.get("section"),
        "selection": snap.get("selection"),
        "items": snap.get("itemCount"),
        "pending": snap.get("pendingCount"),
        "sources": [s["name"] for s in snap.get("sources", [])],
        "graph": (snap.get("graph") or {}).get("center"),
    }, indent=2))


def main():
    args = sys.argv[1:]
    if not args or args[0] == "state":
        _summarize(state()); return
    verb, rest = args[0], args[1:]
    if verb == "add":
        path = os.path.expanduser(rest[0])
        depth = "all" if "--depth" in rest and "all" in rest else "top"
        _summarize(command(action="addFolder", path=path, depth=depth))
    elif verb == "search":
        _summarize(command(action="search", query=" ".join(rest)))
    elif verb == "navigate":
        _summarize(command(action="navigate", target=rest[0]))
    elif verb == "select":
        _summarize(command(action="select", target=rest[0]))
    elif verb == "raw":
        _summarize(command(**json.loads(rest[0])))
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main()
