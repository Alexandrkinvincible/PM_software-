#!/usr/bin/env python3
"""Print "<iPad device type id> <newest iOS runtime id>".

Naming a simulator device in CI is a slow-motion breakage: Apple renames
them and adds generations every year, and the job fails months later for
a reason nobody remembers. This asks the runner what it has instead.
"""
import json
import subprocess
import sys


def simctl(*args: str) -> dict:
    return json.loads(subprocess.check_output(["xcrun", "simctl", *args, "-j"]))


def main() -> int:
    types = simctl("list", "devicetypes")["devicetypes"]
    ipads = [t for t in types if "iPad" in t["name"] and t.get("isAvailable", True)]
    if not ipads:
        print("No iPad simulator device types on this runner.", file=sys.stderr)
        return 1
    # Prefer a Pro — the widest screen, so the two-column layout shows.
    ipads.sort(key=lambda t: ("Pro" not in t["name"], t["name"]))

    runtimes = simctl("list", "runtimes")["runtimes"]
    ios = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable")]
    if not ios:
        print("No available iOS runtimes on this runner.", file=sys.stderr)
        return 1
    ios.sort(key=lambda r: [int(p) for p in r["version"].split(".") if p.isdigit()])

    print(ipads[0]["identifier"], ios[-1]["identifier"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
