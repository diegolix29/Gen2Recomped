#!/usr/bin/env python3
"""A blunt Lua 5.1 sanity check.

Not a parser.  It strips comments and strings, then checks that block
keywords balance and that no Lua 5.2+/5.3-only syntax slipped in -- which
is the failure this codebase can actually have, because LOVE runs LuaJIT
and the author was writing without an interpreter to hand.
"""
import re, sys, pathlib

OPENERS = {"function", "if", "for", "while", "do"}
BAD = [
    (re.compile(r"[^~=<>]~[^=]"), "bitwise xor `~` is 5.3-only (LuaJIT is 5.1)"),
    (re.compile(r"//"),           "floor-div `//` is 5.3-only"),
    (re.compile(r"\bgoto\b"),     "`goto` is 5.2+"),
    (re.compile(r"[^.]\.\.\.[^.]?\s*=") , "cannot assign to ..."),
    (re.compile(r"\bcontinue\b"), "`continue` is not Lua"),
    (re.compile(r"<<|>>"),        "bit shifts are 5.3-only"),
    (re.compile(r"\|(?![|])"),    "bitwise or is 5.3-only"),
    (re.compile(r"[^-]&(?![&])"), "bitwise and is 5.3-only"),
]

def strip(src, keep_strings=False):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                j = n if j < 0 else j + len(close)
                out.append("\n" * src[i:j].count("\n")); i = j; continue
            j = src.find("\n", i); j = n if j < 0 else j
            i = j; continue
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\": j += 2; continue
                if src[j] == c: j += 1; break
                if src[j] == "\n": break
                j += 1
            out.append(src[i:j] if keep_strings else '""'); i = j; continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i)
            j = n if j < 0 else j + len(close)
            out.append((src[i:j] if keep_strings else '""') + ("" if keep_strings else "\n" * src[i:j].count("\n"))); i = j; continue
        out.append(c); i += 1
    return "".join(out)

def check(path):
    src = pathlib.Path(path).read_text()
    clean = strip(src)
    errs = []
    for ln, line in enumerate(clean.split("\n"), 1):
        for rx, msg in BAD:
            if rx.search(line):
                errs.append(f"{path}:{ln}: {msg}: {src.split(chr(10))[ln-1].strip()[:70]}")
    depth, stack = 0, []
    for ln, line in enumerate(clean.split("\n"), 1):
        toks = re.findall(r"\b[A-Za-z_]\w*\b", line)
        # `for ... do`, `while ... do`: the do is the opener, not the for
        j = 0
        while j < len(toks):
            t = toks[j]
            if t in ("for", "while"):
                pass  # its `do` will open
            elif t == "if":
                depth += 1; stack.append((ln, "if"))
            elif t == "function":
                depth += 1; stack.append((ln, "function"))
            elif t == "do":
                depth += 1; stack.append((ln, "do"))
            elif t == "repeat":
                depth += 1; stack.append((ln, "repeat"))
            elif t == "end":
                if not stack: errs.append(f"{path}:{ln}: stray `end`")
                else:
                    o = stack.pop()
                    if o[1] == "repeat":
                        errs.append(f"{path}:{ln}: `end` closing a `repeat` opened at line {o[0]}")
                depth -= 1
            elif t == "until":
                if stack and stack[-1][1] == "repeat": stack.pop(); depth -= 1
                else: errs.append(f"{path}:{ln}: stray `until`")
            j += 1
    for ln, kind in stack:
        errs.append(f"{path}:{ln}: unclosed `{kind}`")
    # bracket balance
    for name, o, c in (("()", "(", ")"), ("{}", "{", "}"), ("[]", "[", "]")):
        if clean.count(o) != clean.count(c):
            errs.append(f"{path}: unbalanced {name}: {clean.count(o)} vs {clean.count(c)}")
    errs += undefined_calls(path, clean)
    return errs


# --------------------------------------------------------------- undefined calls
#
# THE CHECK THAT WOULD HAVE CAUGHT `M`.
#
# Every panel opens with `local M = Theme.m` and one of them did not, so a
# button that was only reachable once a selection existed called a nil global
# and took the frame down.  Nothing in the balance check can see that, and
# with no Lua interpreter in the loop there is nothing else that would.
#
# This is deliberately conservative: it only flags a BARE identifier used in
# call position -- `foo(...)`, never `a.foo(...)` or `a:foo(...)` -- that is
# not a Lua 5.1 global, not a file-level local, not a local or parameter in
# the enclosing top-level function, and not a global this file itself assigns.
# A name it cannot account for is reported; anything it is unsure of is not.
LUA_GLOBALS = set("""
assert collectgarbage dofile error getfenv getmetatable ipairs load loadfile
loadstring module next pairs pcall print rawequal rawget rawlen rawset require
select setfenv setmetatable tonumber tostring type unpack xpcall
coroutine debug io math os package string table bit jit
love arg newproxy
""".split())

_NAME = r"[A-Za-z_][A-Za-z0-9_]*"

def _locals_in(text):
    """Every name this chunk of source introduces as a local or a parameter."""
    names = set()
    for m in re.finditer(r"\blocal\s+(?:function\s+)?(" + _NAME +
                         r"(?:\s*,\s*" + _NAME + r")*)", text):
        for part in m.group(1).split(","):
            names.add(part.strip())
    # parameter lists of every function header, including anonymous ones
    for m in re.finditer(r"\bfunction\b[^(\n]*\(([^)]*)\)", text):
        for part in m.group(1).split(","):
            part = part.strip()
            if re.fullmatch(_NAME, part):
                names.add(part)
    # `for i = ...` / `for k, v in ...`
    for m in re.finditer(r"\bfor\s+(" + _NAME + r"(?:\s*,\s*" + _NAME +
                         r")*)\s*(?:=|\bin\b)", text):
        for part in m.group(1).split(","):
            names.add(part.strip())
    # a method definition binds `self`
    if re.search(r"\bfunction\s+" + _NAME + r"(?:\." + _NAME + r")*:", text):
        names.add("self")
    return names

def undefined_calls(path, clean):
    errs = []
    lines = clean.split("\n")
    # top-level function blocks: a `function` or `local function` at column 0
    starts = [i for i, l in enumerate(lines)
              if re.match(r"^(local\s+)?function\b", l)]
    head = "\n".join(lines[:starts[0]]) if starts else clean
    # file-level scope: everything outside those blocks, plus any name this
    # file assigns as a global (a fork may define one on purpose)
    outer = set(_locals_in(head))
    for m in re.finditer(r"^(" + _NAME + r")\s*=", clean, re.M):
        outer.add(m.group(1))
    for m in re.finditer(r"\bfunction\s+(" + _NAME + r")\b", clean):
        outer.add(m.group(1))

    bounds = starts + [len(lines)]
    for a, b in zip(bounds, bounds[1:]):
        block = "\n".join(lines[a:b])
        known = outer | _locals_in(block) | LUA_GLOBALS
        for m in re.finditer(r"(?<![\w.:])(" + _NAME + r")\s*\(", block):
            name = m.group(1)
            if name in known:
                continue
            # keywords are not calls
            if name in ("function", "if", "while", "for", "return", "and",
                        "or", "not", "elseif", "until", "in", "then", "do",
                        "end", "local", "else", "repeat", "break", "nil",
                        "true", "false"):
                continue
            ln = a + block[:m.start()].count("\n") + 1
            errs.append("%s:%d: calls `%s`, which is not a local here nor a"
                        " Lua global -- a missing `local %s = ...`?"
                        % (path, ln, name, name))
    return errs

if __name__ == "__main__":
    bad = 0
    for p in sys.argv[1:]:
        e = check(p)
        for m in e: print(m)
        bad += len(e)
    print(("FAIL %d" % bad) if bad else "OK  " + str(len(sys.argv) - 1) + " file(s)")
    sys.exit(1 if bad else 0)
