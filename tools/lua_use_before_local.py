#!/usr/bin/env python3
"""tools/lua_use_before_local.py -- a file-local called above its own `local` line.

WHY THIS EXISTS, AND IT IS NOT STYLE.

    local function helper() ... end     -- line 900
    ...
    helper()                            -- line 400

Lua does not resolve `helper` at line 400 to the local at line 900. The local
is not in scope yet, so the name is looked up as a GLOBAL, found to be nil, and
THE CALL RAISES. Nothing warns; the file loads; the function runs until the
first time that line is reached.

It has cost this project twice, both times invisibly:

  * Gen4Commands' `itemKey` was defined around line 531 and used at 427 and 488
    inside g4_buffer, so EVERY `buffertmhmmovename` in the game raised.
  * Gen4Battle's `bottomScreenUp` was defined with the menus and used by
    drawTextArea three hundred lines above, so every menu frame raised -- and
    because draw() wraps the text area in a pcall so a fault there cannot take
    the battlers down with it, the only symptom was the text box, the buttons
    and the move list ALL MISSING. Reported from play as three separate things
    that were never written.

Both were found by reading. This finds them by looking.

Run:  python3 tools/lua_use_before_local.py [root]
"""
import os, re, sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
DIRS = ("src", "tools")


def strip(line):
    """Comments and string literals out -- a name inside either is not a call.

    This is what a first cut of the scan got wrong: `"...missing (23 x 3)"`
    matched as a call to `missing`. A checker with false positives is one
    people learn to skip.
    """
    out, i, n = [], 0, len(line)
    quote = None
    while i < n:
        c = line[i]
        if quote:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "\"'":
            quote = c
            i += 1
            continue
        if c == "-" and i + 1 < n and line[i + 1] == "-":
            break
        out.append(c)
        i += 1
    return "".join(out)


DEF = re.compile(r"^local(?:\s+function)?\s+([A-Za-z_][A-Za-z_0-9]*)\s*(\(|=|$)")


def scan(path):
    src = open(path, "rb").read().decode("utf-8", "replace").replace("\r\n", "\n")
    lines = src.split("\n")
    where = {}
    for i, raw in enumerate(lines, 1):
        m = DEF.match(strip(raw).rstrip())
        if m:
            where.setdefault(m.group(1), i)
    hits = []
    for name, at in where.items():
        pattern = re.compile(r"(^|[^.:\w])" + re.escape(name) + r"\s*\(")
        for i, raw in enumerate(lines[: at - 1], 1):
            if pattern.search(strip(raw)):
                hits.append((i, name, at))
                break
    return hits


def main():
    total, files = 0, 0
    for d in DIRS:
        base = os.path.join(ROOT, d)
        for dirpath, _, names in os.walk(base):
            for name in sorted(names):
                if not name.endswith(".lua"):
                    continue
                path = os.path.join(dirpath, name)
                files += 1
                for line, who, at in sorted(scan(path)):
                    rel = os.path.relpath(path, ROOT)
                    print("  %s:%d calls `%s`, which is local at line %d"
                          % (rel, line, who, at))
                    total += 1
    print("\n%d files scanned, %d use-before-local site(s)" % (files, total))
    # A CANARY, because a scanner that matches nothing passes everything.
    probe = "local x = 1\nf()\nlocal function f() end\n"
    tmp = os.path.join(ROOT, ".ubl_probe.lua")
    try:
        open(tmp, "w").write(probe)
        if not scan(tmp):
            print("CANARY FAILED: the scan does not find a planted fault")
            return 2
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    print("canary ok (a planted fault is found)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
