#!/usr/bin/env python3
"""Cross-module reference check.

Catches the class of mistake this codebase can actually make without an
interpreter to hand: a module required by a path that does not exist, and a
`Module.fn(...)` call where the module never defines `fn`.
"""
import re, sys, pathlib

root = pathlib.Path(".")
files = sorted([p for p in root.rglob("*.lua")])
src = {str(p): p.read_text() for p in files}

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from lualint import strip   # character-wise: strings BEFORE comments, which
                            # matters because a Lua string may contain "--"

def module_path(name):
    return root / (name.replace(".", "/") + ".lua")

def exports(path):
    if not path.exists(): return None
    t = strip(path.read_text())
    names = set()
    # local M = {} ... function M.x / M.x = / M:x
    for m in re.finditer(r"function\s+([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)", t):
        names.add(m.group(2))
    for m in re.finditer(r"^\s*([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*=", t, re.M):
        names.add(m.group(2))
    # table-literal returns:  Mesh.FOO = { ... } handled above; also `X = {`
    for m in re.finditer(r"^\s{2}([A-Za-z_]\w*)\s*=", t, re.M):
        names.add(m.group(1))
    return names

problems = []
checked = 0
for f, s in src.items():
    t = strip(s)
    tq = strip(s, keep_strings=True)   # comments gone, strings intact
    for m in re.finditer(r'(?:local\s+([A-Za-z_]\w*)\s*=\s*)?require\(\s*"([\w.]+)"\s*\)', tq):
        alias, name = m.group(1), m.group(2)
        p = module_path(name)
        if not p.exists():
            problems.append(f"{f}: require(\"{name}\") -> {p} does not exist")
            continue
        checked += 1
        if not alias: continue
        ex = exports(p)
        used = set(re.findall(r"\b" + re.escape(alias) + r"[.:]([A-Za-z_]\w*)", t))
        for u in sorted(used - ex):
            problems.append(f"{f}: {alias}.{u} -- {name} does not define '{u}'")

for m in problems: print(m)
print(("XREF FAIL %d" % len(problems)) if problems else ("XREF OK -- %d files, %d requires checked" % (len(src), checked)))
sys.exit(1 if problems else 0)
