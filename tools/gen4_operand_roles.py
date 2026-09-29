#!/usr/bin/env python3
# Copyright (c) 2026 Cedric. All rights reserved.
# Source-available under the Gen2Recomped License (see LICENSE.md): you may
# read, build and privately modify this file; you may not redistribute it or
# use it commercially. Cartridge-derived data is excluded and is not the
# copyright holder's to license.
"""tools/gen4_operand_roles.py -- does the lowering pass every DESTINATION operand?

The other three Gen 4 checks each stop one step short of this one:

  * the chapter walks say an opcode is lowered;
  * gen4_command_audit says the command runs and writes its var;
  * gen4_seam_check says the verb resolves and the operand COUNT matches;
  * none of them knows which operand is WHICH.

An operand's role is in pret, unambiguously. `ScriptContext_GetVarPointer` reads
a DESTINATION -- a var the command writes -- and everything else
(`GetVar`, `ReadByte`, `ReadHalfWord`, `ReadWord`) reads an input. So the order
and roles of a command's operands are the sequence of primitives its handler
calls, and this compares that against the `ins.args[N]` indices the lowering
actually passes.

WHY DESTINATIONS SPECIFICALLY. A dropped input is usually deliberate -- a no-op
ignores everything, `goto` reads its offset from `ins.target` rather than args.
A dropped DESTINATION is never harmless: the var is not written, and the `gotoif`
behind it branches on whatever the previous command happened to leave in the
comparison register. Passing the WRONG operand as the destination is worse still:
the zero lands in a var id taken from an input, clobbering something unrelated.

WHAT IT FOUND. Two, both on commands whose names contain "fatefulencounter":

    0x32B checkpartyhasfatefulencounterregigigas   operand 1 of 1 is a DESTINATION
    0x31C findpartyslotwithfatefulencounterspecies operand 1 of 2 is a DESTINATION

Both lowerings passed `ins.args[2]`. The first handed the command nil, so nothing
was written at any of its 9 sites; the second passed the SPECIES as the
destination, writing into a var id that was never a var. Both are the
"destination comes first" shape that scrcmd_party.c's four party queries already
demonstrate -- documented, and then walked into twice anyway. Reading carefully
is not a substitute for a check.

    python3 tools/gen4_operand_roles.py /path/to/pokeplatinum \\
        src/import/Gen4ScriptOps.lua src/script/Gen4ScriptVM.lua
"""
import re, os, sys

# THE ONE OPERAND THAT IS A POINTER BUT NOT A DESTINATION.
#
# `GetVarPointer` is what this check reads a destination from, and for 335 of
# the 336 lowerings it parses that is exactly what the operand is. The
# exception is the lift's floor indicator:
#
#     ScrCmd_ShowCurrentFloor  ->  FieldMenu_ShowCurrentFloorWindow(..., var, ...)
#     CurrentFloorWindowSystaskCallback:  if (*selectedOptionPtr == 0xffff) close
#
# -- the command takes the pointer so its WINDOW can WATCH the var, and the
# SCRIPT is what writes it (`setvar VAR_ELEVATOR_FLOORS_ABOVE, -1`, three rows
# later in all three panel lifts). So it is an IN operand wearing a pointer, and
# a lowering that "fixed" it by writing a zero would clobber the floor count the
# panel is about to branch on -- the opposite of what this check exists to
# prevent.
#
# Listed here with the reason rather than silently skipped: if a second command
# ever turns up in this shape, it has to be argued for on the same page.
IN_OUT_HANDLES = {
    "showcurrentfloor": "the window watches the var; the script writes it",
}

def pret_roles(pp):
    rows=[]
    for line in open(os.path.join(pp,"include/data/scripts/scrcmd.h")):
        m=re.match(r'\s*ScriptCommand\(\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*\)', line)
        if m: rows.append(m.group(2))
    bodies={}
    for root,_,files in os.walk(os.path.join(pp,"src")):
        for fn in files:
            if not fn.endswith(".c"): continue
            src=open(os.path.join(root,fn),encoding='utf-8',errors='replace').read()
            for m in re.finditer(r'^(?:static\s+)?BOOL\s+(ScrCmd_[A-Za-z0-9_]+)\s*\(\s*ScriptContext\s*\*\s*ctx\s*\)\s*\n\{', src, re.M):
                i=m.end()-1; d=0; j=i
                while j<len(src):
                    if src[j]=='{': d+=1
                    elif src[j]=='}':
                        d-=1
                        if d==0: break
                    j+=1
                bodies.setdefault(m.group(1), src[i:j+1])
    KIND={"ReadByte":"in","ReadHalfWord":"in","GetVar":"in","ReadWord":"in",
          "GetVarPointer":"dest"}
    CALL=re.compile(r'ScriptContext_(ReadByte|ReadHalfWord|ReadWord|GetVarPointer|GetVar)\b')
    COND=re.compile(r'\b(for|while|if|else|switch|case|do)\b[^;{]*$')
    out={}
    for op,name in enumerate(rows):
        body=bodies.get(name)
        if body is None: out[op]=(name,None,False); continue
        b=re.sub(r'/\*.*?\*/','',body,flags=re.S)
        b=re.sub(r'//[^\n]*','',b); b=re.sub(r'"(?:[^"\\]|\\.)*"','""',b)
        kinds=[]; stack=[]; cond=False; i=0
        while i<len(b):
            c=b[i]
            if c=='{': stack.append(bool(COND.search(b[max(0,i-160):i]))); i+=1; continue
            if c=='}':
                if stack: stack.pop()
                i+=1; continue
            m=CALL.match(b,i)
            if m:
                if any(stack[1:]): cond=True
                else: kinds.append(KIND[m.group(1)])
                i=m.end(); continue
            i+=1
        out[op]=(name,kinds,cond)
    return out

def main():
    pp  = sys.argv[1] if len(sys.argv)>1 else "/tmp/pp"
    ops = sys.argv[2] if len(sys.argv)>2 else "src/import/Gen4ScriptOps.lua"
    vm  = sys.argv[3] if len(sys.argv)>3 else "src/script/Gen4ScriptVM.lua"
    roles = pret_roles(pp)
    name2op={}
    for m in re.finditer(r'\[0x([0-9A-Fa-f]{1,3})\]\s*=\s*\{\s*"([^"]+)"',
                         open(ops,encoding='utf-8',errors='replace').read()):
        name2op[m.group(2)]=int(m.group(1),16)

    src=open(vm,encoding='utf-8',errors='replace').read().replace('\r\n','\n')
    marks=[(m.start(), m.group(1) or m.group(2)) for m in
           re.finditer(r'^L(?:\.([a-z0-9_]+)|\["([^"]+)"\])\s*=\s*', src, re.M)]
    marks.append((len(src), None))
    lowered={}
    for i in range(len(marks)-1):
        a,name=marks[i]; b,_=marks[i+1]
        if name is None: continue
        lowered.setdefault(name,set()).update(
            int(n) for n in re.findall(r'ins\.args\[(\d+)\]', src[a:b]))

    bad=[]; ignored={}; handles={}; skipped=0
    for name,used in sorted(lowered.items()):
        op=name2op.get(name)
        if op is None: continue
        entry=roles.get(op)
        if not entry or entry[1] is None or entry[2]: skipped+=1; continue
        for pos,kind in enumerate(entry[1], start=1):
            if pos in used: continue
            if kind=="dest":
                if name in IN_OUT_HANDLES: handles.setdefault(name,[]).append(pos)
                else: bad.append((op,name,pos,len(entry[1]),entry[1]))
            else: ignored.setdefault(name,[]).append(pos)

    print("DROPPED DESTINATIONS -- the var is never written and the branch behind")
    print("it reads the previous command's answer:")
    if not bad: print("  none")
    for op,name,pos,n,ks in bad:
        print(f"  0x{op:03X} {name:<44} operand {pos} of {n} is a DESTINATION {ks}")
    if handles:
        print("\npointer operands that are INPUTS, and why (see IN_OUT_HANDLES):")
        for name,poss in sorted(handles.items()):
            print(f"  {name:<44} operand {','.join(str(p) for p in poss)}"
                  f" -- {IN_OUT_HANDLES[name]}")
    print(f"\nignored input operands (usually deliberate): {len(ignored)} commands")
    print(f"{len(lowered)} lowerings parsed, {skipped} not comparable")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
