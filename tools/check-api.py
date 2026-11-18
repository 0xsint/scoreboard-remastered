#!/usr/bin/env python3
"""Check the add-on's game API calls against ESO's API documentation.

    python3 tools/check-api.py <path-to>/ESOUIDocumentation.txt [addon dir]

ESOUIDocumentation.txt ships with ZeniMax's UI source (github.com/esoui/esoui).
It marks functions add-ons may not call:

    * IsKeyDown *private* (...)       ZeniMax UI only, never callable by add-ons
    * Foo *protected* (...)           callable by add-ons only outside combat

This script lists every global function the add-on calls (directly, or by name
through SBR.API / SBR.HasAPI) that the documentation marks private or protected,
and exits non-zero if there are any. Functions defined in the UI's own Lua (for
example ZO_GetClassIcon, GetBattlegroundTeamColor) are not in this file and are
not checked here.
"""
import glob
import os
import re
import sys


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    doc = open(sys.argv[1], encoding="utf-8").read()
    root = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    access = {}
    for m in re.finditer(r"^\* ([A-Za-z_][A-Za-z0-9_]*)(?: \*(private|protected)\*)? ?\(", doc, re.M):
        access.setdefault(m.group(1), m.group(2) or "public")

    called = {}
    for f in sorted(glob.glob(os.path.join(root, "*.lua")) + glob.glob(os.path.join(root, "Data", "*.lua"))
                    + glob.glob(os.path.join(root, "UI", "*.lua")) + glob.glob(os.path.join(root, "lang", "*.lua"))):
        src = open(f, encoding="utf-8").read()
        rel = os.path.relpath(f, root)
        for m in re.finditer(r"(?<![\w.:])([A-Z][A-Za-z0-9_]+)\s*\(", src):
            called.setdefault(m.group(1), set()).add(rel)
        for m in re.finditer(r'SBR\.(?:API|HasAPI)\("([A-Za-z0-9_]+)"', src):
            called.setdefault(m.group(1), set()).add(rel)

    documented = sorted(n for n in called if n in access)
    bad = [(n, access[n]) for n in documented if access[n] != "public"]
    print(f"{len(documented)} documented game API functions called")
    for name, kind in bad:
        print(f"  {kind}: {name} ({', '.join(sorted(called[name]))})")
    if not bad:
        print("  none are private or protected")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
