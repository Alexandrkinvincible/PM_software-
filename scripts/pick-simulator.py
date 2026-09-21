#!/usr/bin/env python3
"""Print candidate "<iPad device type id> <iOS runtime id>" pairs, best first.

Naming a simulator device in CI is a slow-motion breakage: Apple renames
them and adds generations every year, and the job fails months later for
a reason nobody remembers. So ask the runner what it has.

The subtlety that bit us first time round: having a device type and having
a runtime does NOT mean they go together. A 2017 iPad Pro and iOS 26 are
both present on the runner, and pairing them fails with "Incompatible
device". Each runtime publishes the device types it actually supports, so
that is what we read, rather than inferring from names.

Several candidates are printed so the caller can fall through if creating
one fails for a reason we cannot see from here.
"""
import json
import re
import subprocess
import sys


def simctl(*args: str) -> dict:
    return json.loads(subprocess.check_output(["xcrun", "simctl", *args, "-j"]))


def version_key(v: str) -> list[int]:
    return [int(p) for p in re.findall(r"\d+", v)] or [0]


def screen_inches(name: str) -> float:
    """13 from "iPad Pro 13-inch (M4)", 12.9 from "iPad Pro (12.9-inch) …"."""
    m = re.search(r"(\d+(?:\.\d+)?)\s*-?\s*inch", name)
    return float(m.group(1)) if m else 0.0


def main() -> int:
    runtimes = [
        r for r in simctl("list", "runtimes")["runtimes"]
        if r.get("platform") == "iOS" and r.get("isAvailable")
    ]
    if not runtimes:
        print("No available iOS runtimes on this runner.", file=sys.stderr)
        return 1

    # Newest runtime first.
    runtimes.sort(key=lambda r: version_key(r.get("version", "0")), reverse=True)

    printed = 0
    for runtime in runtimes:
        supported = runtime.get("supportedDeviceTypes") or []
        ipads = [d for d in supported if d.get("productFamily") == "iPad"]

        # Widest screen first — the two-column layout only appears there —
        # preferring a Pro when sizes tie.
        ipads.sort(
            key=lambda d: (screen_inches(d["name"]), "Pro" in d["name"], d["name"]),
            reverse=True,
        )

        for device in ipads[:3]:
            print(device["identifier"], runtime["identifier"])
            printed += 1

    if printed == 0:
        print("No runtime on this runner supports any iPad.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
