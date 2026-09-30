#!/usr/bin/env python3
# Copyright (c) 2026 Cedric. All rights reserved.
# Source-available under the Gen2Recomped License (see LICENSE.md).
r"""
NAMING A MOVE-ANIMATION TASK FUNCTION IN A RETAIL ROM.

`RomExtractorGen3` recognises a visual task by its ADDRESS and then verifies,
by disassembling it, that it is the function being claimed. That is the right
way round -- but it leaves a chicken and egg: a retail dump names nothing, so
where does the first address come from? Today it comes from a move known to
call the function ("BIND's first task is AnimTask_SwayMon"), which works only
for a function somebody has already identified by hand.

This derives them wholesale, and without a symbol table, from a fact about the
cartridge rather than a reading of it:

    pret/pokeemerald builds byte-for-byte to this ROM, so the SET OF MOVES that
    call a named function is a fact. The set of moves that call an ADDRESS is
    also a fact, read out of the ROM's own script table. A name whose move-set
    is covered by exactly one address's move-set, minimally, is that address.

The ROM's sets are SUPERSETS of pret's: this walker takes the union of every
branch arm, including contest arms the transcription in
`tools/gen3_anim_expect.lua` flattens differently. So the test is containment
plus minimality, not equality -- and the extras are printed, because a superset
that is too large is how a wrong answer would look.

THREE ANSWERS ARE ALREADY KNOWN, and they are the proof this works rather than
decoration: `MON_SWAY.TASK` and `MON_LUNGE.TASK` in RomExtractorGen3.lua were
each derived by hand and verified by disassembly, and the dataset records
RAPID SPIN's task address in its own `source` string. All three have to come
back out of this, or it has proved nothing.

Usage:
  python3 tools/gen3_anim_task_addresses.py <rom.gba> <emerald/data/generated>
"""

import collections
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ---------------------------------------------------------------- the script
# Widths from pret's own asm/macros/battle_anim_script.inc. createsprite,
# createvisualtask and createsoundtask carry an argument count and are handled
# in the walker; everything else is fixed.
WIDTH = {
    0x00: 3, 0x01: 3, 0x04: 2, 0x05: 1, 0x06: 1, 0x07: 1, 0x08: 1, 0x09: 3,
    0x0A: 2, 0x0B: 2, 0x0C: 3, 0x0D: 1, 0x0E: 5, 0x0F: 1, 0x10: 4, 0x11: 9,
    0x12: 6, 0x13: 5, 0x14: 2, 0x15: 1, 0x16: 1, 0x17: 1, 0x18: 2, 0x19: 4,
    0x1A: 2, 0x1B: 7, 0x1C: 6, 0x1D: 5, 0x1E: 3, 0x20: 1, 0x21: 8, 0x22: 2,
    0x23: 2, 0x24: 5, 0x25: 4, 0x26: 7, 0x27: 7, 0x28: 2, 0x29: 1, 0x2A: 2,
    0x2B: 2, 0x2C: 2, 0x2D: 2, 0x2E: 2, 0x2F: 1,
}
END, RET, CALL, GOTO = 0x08, 0x0F, 0x0E, 0x13
TWOTURN, JMPTURN, JMPARG, JMPCONTEST = 0x11, 0x12, 0x21, 0x24
SPRITE, TASK, SOUNDTASK = 0x02, 0x03, 0x1F
SOUND_CMDS = {0x09, 0x19, 0x1B, 0x1C, 0x1D, 0x1F, 0x26, 0x27}
ROWS = 355          # move 0 ("no move") plus 354 moves


class Rom:
    def __init__(self, path):
        with open(path, "rb") as fh:
            self.b = fh.read()
        self.n = len(self.b)

    def u8(self, a):
        return self.b[a]

    def u16(self, a):
        return struct.unpack_from("<H", self.b, a)[0]

    def ptr(self, a):
        if a + 4 > self.n:
            return None
        v = struct.unpack_from("<I", self.b, a)[0]
        if 0x08000000 <= v < 0x08000000 + self.n:
            return v - 0x08000000
        return None

    def walk(self, entry, max_steps=4000):
        """Every branch arm of one animation script, as a union.

        Returns (task calls in order, scripts-with-a-sound flag, clean).
        A task address is masked to even HERE, once: the cartridge stores the
        THUMB bit and every consumer wants the function.
        """
        tasks, sounds, clean = [], 0, True
        seen, stack, steps = set(), [(entry, 0)], 0
        while stack:
            at, depth = stack.pop(0)
            if depth > 24:
                continue
            while True:
                steps += 1
                if steps > max_steps or at is None or at < 0 or at >= self.n:
                    clean = False
                    break
                if (at, depth) in seen:
                    break
                seen.add((at, depth))
                op = self.u8(at)
                if op in (END, RET):
                    break
                if op == TASK:
                    fn = self.ptr(at + 1)
                    if fn is None:
                        clean = False
                        break
                    argc = self.u8(at + 6)
                    args = [self.u16(at + 7 + 2 * i) for i in range(argc)]
                    tasks.append((fn & ~1, args))
                    at += 7 + 2 * argc
                    continue
                if op == SPRITE:
                    at += 7 + 2 * self.u8(at + 6)
                    continue
                if op == SOUNDTASK:
                    sounds += 1
                    at += 6 + 2 * self.u8(at + 5)
                    continue
                if op in SOUND_CMDS:
                    sounds += 1
                    at += WIDTH[op]
                    continue
                if op in (CALL, JMPCONTEST):
                    t = self.ptr(at + 1)
                    if t is None:
                        clean = False
                        break
                    stack.append((t, depth + 1))
                    at += 5
                    continue
                if op == GOTO:
                    t = self.ptr(at + 1)
                    if t is None:
                        clean = False
                        break
                    at = t
                    continue
                if op == TWOTURN:
                    a1, a2 = self.ptr(at + 1), self.ptr(at + 5)
                    if a1 is None or a2 is None:
                        clean = False
                        break
                    stack.append((a1, depth + 1))
                    stack.append((a2, depth + 1))
                    break
                if op == JMPTURN:
                    t = self.ptr(at + 2)
                    if t is None:
                        clean = False
                        break
                    stack.append((t, depth + 1))
                    at += 6
                    continue
                if op == JMPARG:
                    t = self.ptr(at + 4)
                    if t is None:
                        clean = False
                        break
                    stack.append((t, depth + 1))
                    at += 8
                    continue
                w = WIDTH.get(op)
                if w is None:
                    clean = False
                    break
                at += w
        return tasks, sounds, clean


def lua_blocks(text):
    """Every ["KEY"] = { ... } block at any depth, as key -> body."""
    out = {}
    for m in re.finditer(r'\["([A-Z0-9_]+)"\]\s*=\s*\{', text):
        i = m.end()
        depth, j = 1, i
        while depth > 0 and j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
            j += 1
        out.setdefault(m.group(1), text[i:j])
    return out


def table_candidates(rom):
    """Every 4-aligned offset where ROWS consecutive pointers all land on a
    byte an animation script may legally begin with.

    This is a filter, not an answer: the table sits inside a longer run of
    script pointers, so hundreds of sliding windows survive it. Which one is
    the table is settled below, by the addresses the extractor has already
    proved -- not by picking the longest run, which is some other table
    entirely.
    """
    is_ptr = bytearray(rom.n // 4)
    for a in range(0, rom.n - 4, 4):
        if rom.ptr(a) is not None:
            is_ptr[a >> 2] = 1
    windows, run = [], 0
    for i in range(len(is_ptr)):
        run = run + 1 if is_ptr[i] else 0
        if run >= ROWS:
            windows.append((i - ROWS + 1) * 4)
    legal = set(WIDTH) | {SPRITE, TASK, SOUNDTASK}
    out = []
    for b in windows:
        for k in range(ROWS):
            t = rom.ptr(b + k * 4)
            if t is None or rom.u8(t) not in legal:
                break
        else:
            out.append(b)
    return out


def pick_table(rom, cands, known):
    """The one candidate where every task address the extractor has already
    recorded is reachable from the row of the move that recorded it.

    An off-by-one base puts DIG's script in SKETCH's row, so this is not a
    tie-break -- it is the whole identification, and it is made of answers
    that were derived and disassembled somewhere else.
    """
    winners = []
    for b in cands:
        good = True
        for i, (_key, addrs) in known.items():
            e = rom.ptr(b + i * 4)
            if e is None:
                good = False
                break
            got = set(a for a, _ in rom.walk(e)[0])
            if not set(addrs) <= got:
                good = False
                break
        if good:
            winners.append(b)
    return winners


def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__.strip().splitlines()[-1] + "\n")
        return 2
    rom_path, data_dir = sys.argv[1], sys.argv[2]
    rom = Rom(rom_path)

    fails = []
    checks = [0]

    def ok(cond, msg):
        checks[0] += 1
        if not cond:
            fails.append(msg)
            print("FAIL: " + msg)

    print("-- 1. which move is which row")
    with open(os.path.join(data_dir, "moves.lua"), encoding="latin-1") as fh:
        moves_src = fh.read()
    idx2key, known = {}, {}
    for key, body in lua_blocks(moves_src).items():
        m = re.search(r"\n\s*index\s*=\s*(\d+)", body)
        if not m:
            continue
        idx2key[int(m.group(1))] = key
        addrs = set(int(x, 16) for x in
                    re.findall(r"ROM:createvisualtask ([0-9A-Fa-f]{6,8})", body))
        if addrs:
            known[int(m.group(1))] = (key, sorted(addrs))
    ok(len(idx2key) >= 350, "only %d moves carry an index" % len(idx2key))
    ok(len(known) >= 3, "the dataset records only %d task address(es); there "
       "is not enough already-proved material to identify the table" % len(known))
    print("   %d moves indexed; %d of them already name a task address"
          % (len(idx2key), len(known)))

    print("\n-- 2. the script table")
    cands = table_candidates(rom)
    print("   %d window(s) of %d pointers to plausible scripts" % (len(cands), ROWS))
    ok(len(cands) > 0, "no run of %d consecutive script pointers exists" % ROWS)
    winners = pick_table(rom, cands, known)
    print("   %d of them put every recorded address in its own row" % len(winners))
    ok(len(winners) == 1,
       "%d candidate tables satisfy the recorded addresses; one is needed"
       % len(winners))
    if len(winners) != 1:
        print("\n%d checks, %d failed" % (checks[0], len(fails)))
        return 1
    base = winners[0]
    print("   table at 0x%07X (%08X)" % (base, base + 0x08000000))

    clean = sounds = 0
    for i in range(ROWS):
        e = rom.ptr(base + i * 4)
        if e is None:
            continue
        _, s, c = rom.walk(e)
        clean += 1 if c else 0
        sounds += 1 if s else 0
    print("   %d/%d rows walk clean, %d carry a sound" % (clean, ROWS, sounds))
    ok(clean == ROWS, "%d row(s) do not walk as animation bytecode" % (ROWS - clean))
    # The real table gives ~345. A run of something else gives almost none, and
    # that gap is what makes this the table rather than a plausible neighbour.
    ok(sounds >= 200, "only %d rows carry a sound; this is not the table" % sounds)

    # THE PROOF THE ROWS LINE UP. These addresses were derived by hand and
    # verified by disassembly elsewhere; if the indexing were off by one they
    # would land in the wrong row and none of this would reproduce them.
    hit = tot = 0
    for i, (key, addrs) in known.items():
        got = set(a for a, _ in rom.walk(rom.ptr(base + i * 4))[0])
        for a in addrs:
            tot += 1
            if a in got:
                hit += 1
            else:
                print("   row %d (%s) does not reach 0x%07X" % (i, key, a))
    ok(tot > 0, "the dataset records no task address to check the rows against")
    ok(hit == tot, "%d of %d recorded task addresses are in their own row"
       % (hit, tot))
    print("   %d/%d recorded addresses found in their own row" % (hit, tot))

    print("\n-- 3. the call sets")
    with open(os.path.join(ROOT, "tools", "gen3_anim_expect.lua"),
              encoding="latin-1") as fh:
        expect_src = fh.read()
    name2keys = collections.defaultdict(set)
    blocks = lua_blocks(expect_src)
    withTasks = 0
    for key, body in blocks.items():
        t = re.search(r"tasks\s*=\s*\{(.*?)\}", body, re.S)
        if t is None:
            # A move whose script creates no visual task at all is a real row,
            # not a parse failure: it simply has no `tasks` to carry.
            continue
        withTasks += 1
        for n in set(re.findall(r'"([A-Za-z0-9_]+)"', t.group(1))):
            name2keys[n].add(key)
    ok(len(blocks) >= 350, "the expect table parsed to only %d rows" % len(blocks))
    ok(withTasks > 250, "only %d expect rows carry any task at all" % withTasks)
    print("   %d expect rows, %d of them calling at least one task"
          % (len(blocks), withTasks))

    addr2keys = collections.defaultdict(set)
    for i in range(1, ROWS):
        key = idx2key.get(i)
        if not key:
            continue
        for a, _ in rom.walk(rom.ptr(base + i * 4))[0]:
            addr2keys[a].add(key)
    print("   ROM: %d distinct task addresses; pret: %d distinct names"
          % (len(addr2keys), len(name2keys)))
    ok(len(addr2keys) > 100, "only %d task addresses found" % len(addr2keys))

    print("\n-- 4. the answer")
    # The three that are already known, then the five this exists to find.
    PROVEN = {
        "SwayMon": 0x0D5EB8,              # RomExtractorGen3.MON_SWAY.TASK
        "WindUpLunge": 0x0D5C50,          # RomExtractorGen3.MON_LUNGE.TASK
        "RapinSpinMonElevation": 0x15ADB0,  # the dataset's own RAPID SPIN source
    }
    WANTED = ["TranslateMonEllipticalRespectSide", "TranslateMonElliptical",
              "RotateMonSpriteToSide", "RotateMonToSideAndRestore",
              "RotateAuroraRingColors"]

    def resolve(name):
        want = name2keys.get(name, set())
        if not want:
            return None, "pret names no move that calls it"
        sup = sorted((len(s), a, s) for a, s in addr2keys.items() if want <= s)
        if not sup:
            return None, "no address is called by all %d of its moves" % len(want)
        size, addr, got = sup[0]
        if len(sup) > 1 and sup[1][0] == size:
            return None, "%d addresses tie at %d moves" % (
                sum(1 for x in sup if x[0] == size), size)
        return (addr, got - want), None

    print("   %-36s %-5s %-10s %s" % ("function", "pret", "address", "note"))
    derived = {}
    for name in list(PROVEN) + WANTED:
        res, why = resolve(name)
        if res is None:
            ok(False, "%s: %s" % (name, why))
            print("   %-36s %-5d %-10s %s"
                  % (name, len(name2keys.get(name, ())), "-", why))
            continue
        addr, extra = res
        derived[name] = addr
        note = ("+%d in the ROM set: %s" % (len(extra), ", ".join(sorted(extra)))
                if extra else "exact")
        print("   %-36s %-5d 0x%07X  %s"
              % (name, len(name2keys[name]), addr, note))

    for name, want in PROVEN.items():
        ok(derived.get(name) == want,
           "%s derived as %s but is known to be 0x%07X -- the derivation is "
           "wrong, not the constant"
           % (name, ("0x%07X" % derived[name]) if name in derived else "nothing",
              want))
    for name in WANTED:
        ok(name in derived, "%s was not resolved" % name)

    print("\n-- 5. it can fail")
    # A name the cartridge does not contain must resolve to nothing, or
    # "unique minimal superset" is satisfied by anything at all.
    res, why = resolve("AnimTask_NoSuchFunctionAnywhere")
    ok(res is None, "an invented function name resolved to an address")
    # ...and two different names must not collapse onto one address.
    seen = {}
    clash = []
    for name, addr in derived.items():
        if addr in seen:
            clash.append("%s and %s both -> 0x%07X" % (seen[addr], name, addr))
        seen[addr] = name
    ok(not clash, "; ".join(clash))

    # NOT WRITTEN INTO THE REPO BY DEFAULT. These are addresses read out of a
    # cartridge, and the licence keeps cartridge data out of the tree; they
    # belong in RomExtractorGen3.lua as named constants beside MON_SWAY and
    # MON_LUNGE, put there by a person who has read them, not dropped into a
    # file by a tool run.
    if "--json" in sys.argv:
        out = sys.argv[sys.argv.index("--json") + 1]
        with open(out, "w") as fh:
            json.dump({k: "0x%07X" % v for k, v in sorted(derived.items())}, fh,
                      indent=2, sort_keys=True)
        print("   wrote %s" % out)

    print("\n%d checks, %d failed" % (checks[0], len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
