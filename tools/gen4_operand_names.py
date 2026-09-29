#!/usr/bin/env python3
# Copyright (c) 2026 Cedric. All rights reserved.
# Source-available under the Gen2Recomped License (see LICENSE.md): you may
# read, build and privately modify this file; you may not redistribute it or
# use it commercially. Cartridge-derived data is excluded and is not the
# copyright holder's to license.
"""tools/gen4_operand_names.py -- INPUT operand order, checked by name.

The other checks stop at "every destination is passed". None can see whether two
INPUTS are the right way round: `getpartymontype <type1Var> <type2Var> <slot>`
would satisfy all of them with its two destinations swapped.

I wrote that gap down as unfixable -- "the only defence is reading the handler
operand by operand". That was wrong. THE NAMES ARE A SHARED VOCABULARY. pret's
handler assigns every read to a named local:

    u16 *destVar = ScriptContext_GetVarPointer(ctx);
    u16 species  = ScriptContext_GetVar(ctx);

and this port's commands have named parameters. Compose the two through the
lowering's emit row -- which args[N] lands in which parameter slot -- and the
names either correspond or they do not. 1,037 of pret's 1,129 operands (91.9%)
carry a usable name.

THE REFINEMENT THAT MADE IT USABLE. The first run reported 52 disagreements and
every one was correct code: `g4_buffer(ctx, slot, kind, value)` serves about
twenty opcodes, so its parameters are deliberately non-specific, and comparing
"value" against pret's "item", "move" and "number" is noise. Generic parameter
names are excluded and counted instead -- 52 complaints down to 6, all synonyms.
Same lesson as the width checker's loop heuristic: a check that cries wolf on a
list nobody will read is not a check.

RESULT ON THE COMMITTED TREE: 61 specifically-named pairs compared, 0 real
disagreements. 77 skipped because this port's parameter is generic (a design
choice -- there the per-opcode `kind` string in the emit row is the
discriminator), 43 lowerings not comparable.

A difference is REVIEW, not failure: this exits 0 and prints what to read.

    python3 tools/gen4_operand_names.py . /path/to/pokeplatinum
"""
import re, os, sys

DECL = re.compile(r'(?:^|[;{]\s*)(?:const\s+)?(?:u8|u16|u32|s8|s16|s32|int|BOOL|enum\s+\w+)'
                  r'\s*\**\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(?[A-Za-z0-9_]*\)?\s*'
                  r'ScriptContext_(?:ReadByte|ReadHalfWord|ReadWord|GetVarPointer|GetVar)'
                  r'\s*\(\s*ctx\s*\)', re.M)
BARE = re.compile(r'ScriptContext_(ReadByte|ReadHalfWord|ReadWord|GetVarPointer|GetVar)'
                  r'\s*\(\s*ctx\s*\)')
COND = re.compile(r'\b(for|while|if|else|switch|case|do)\b[^;{]*$')

# A GENERIC PARAMETER NAME CANNOT DISAGREE WITH ANYTHING.
GENERIC = {"slot","value","kind","id","n","a","b","x","y","z","arg","args","index",
           "which","what","mode","target","amount","count","frames","steps",
           "colour","color","feature","destvar","dest"}

def extract_pret(pp):
    order=[]
    for line in open(os.path.join(pp,"include/data/scripts/scrcmd.h")):
        m=re.match(r'\s*ScriptCommand\(\s*([A-Za-z0-9_]+)\s*,\s*([A-Za-z0-9_]+)\s*\)', line)
        if m: order.append(m.group(2))
    bodies={}
    for root,_,files in os.walk(os.path.join(pp,"src")):
        for fn in files:
            if not fn.endswith(".c"): continue
            src=open(os.path.join(root,fn),encoding='utf-8',errors='replace').read()
            for m in re.finditer(r'^(?:static\s+)?BOOL\s+(ScrCmd_[A-Za-z0-9_]+)\s*'
                                 r'\(\s*ScriptContext\s*\*\s*ctx\s*\)\s*\n\{', src, re.M):
                i=m.end()-1; d=0; j=i
                while j<len(src):
                    if src[j]=='{': d+=1
                    elif src[j]=='}':
                        d-=1
                        if d==0: break
                    j+=1
                bodies.setdefault(m.group(1), src[i:j+1])
    out={}
    for op,handler in enumerate(order):
        body=bodies.get(handler)
        if body is None: out[op]=(handler,None,False); continue
        b=re.sub(r'/\*.*?\*/','',body,flags=re.S)
        b=re.sub(r'//[^\n]*','',b); b=re.sub(r'"(?:[^"\\]|\\.)*"','""',b)
        ops=[]; stack=[]; cond=False; i=0
        while i<len(b):
            c=b[i]
            if c=='{': stack.append(bool(COND.search(b[max(0,i-160):i]))); i+=1; continue
            if c=='}':
                if stack: stack.pop()
                i+=1; continue
            m=BARE.match(b,i)
            if m:
                if any(stack[1:]): cond=True
                else:
                    head=b[max(0,i-200):i+len(m.group(0))]
                    dm=None
                    for d2 in DECL.finditer(head): dm=d2
                    ops.append(((dm.group(1) if dm else None),
                                "dest" if m.group(1)=="GetVarPointer" else "in"))
                i=m.end(); continue
            i+=1
        out[op]=(handler,ops,cond)
    return out

def norm(s):
    if not s: return ""
    s=re.sub(r'(?i)(var|id|ptr|dest)$','',s)
    s=re.sub(r'(?i)^(dest|out)','',s)
    return re.sub(r'[^a-z0-9]','',s.lower())

def main():
    root = sys.argv[1] if len(sys.argv)>1 else "."
    pp   = sys.argv[2] if len(sys.argv)>2 else "/tmp/pp"
    pret = extract_pret(pp)

    name2op={}
    for m in re.finditer(r'\[0x([0-9A-Fa-f]{1,3})\]\s*=\s*\{\s*"([^"]+)"',
        open(os.path.join(root,"src/import/Gen4ScriptOps.lua"),
             encoding='utf-8',errors='replace').read()):
        name2op[m.group(2)]=int(m.group(1),16)

    params={}
    for m in re.finditer(r'^function Commands\.([A-Za-z0-9_]+)\(([^)]*)\)',
        open(os.path.join(root,"src/script/Gen4Commands.lua"),
             encoding='utf-8',errors='replace').read().replace('\r\n','\n'), re.M):
        ps=[p.strip() for p in m.group(2).split(',') if p.strip()]
        if ps and ps[0]=="ctx": ps=ps[1:]
        params[m.group(1)]=ps

    src=open(os.path.join(root,"src/script/Gen4ScriptVM.lua"),
             encoding='utf-8',errors='replace').read().replace('\r\n','\n')
    marks=[(m.start(), m.group(1) or m.group(2)) for m in
           re.finditer(r'^L(?:\.([a-z0-9_]+)|\["([^"]+)"\])\s*=\s*', src, re.M)]
    marks.append((len(src),None))
    rows={}
    for i in range(len(marks)-1):
        a,name=marks[i]; b,_=marks[i+1]
        if name is None: continue
        em=re.search(r'emit\(\s*s\s*,\s*\{(.*?)\}\s*\)', src[a:b], re.S)
        if not em: continue
        parts=[p.strip() for p in re.split(r',(?![^\[]*\])', em.group(1))]
        if not parts: continue
        slots=[]
        for p in parts[1:]:
            am=re.fullmatch(r'ins\.args\[(\d+)\]', p)
            slots.append(int(am.group(1)) if am else None)
        rows.setdefault(name,(parts[0].strip('"'), slots))

    diff=[]; checked=generic=skipped=0
    for lname,(verb,slots) in sorted(rows.items()):
        op=name2op.get(lname)
        entry=pret.get(op) if op is not None else None
        pnames=params.get(verb)
        if op is None or not entry or entry[1] is None or entry[2] or not pnames:
            skipped+=1; continue
        pops=entry[1]
        for slot,argidx in enumerate(slots):
            if argidx is None or slot>=len(pnames) or argidx-1>=len(pops): continue
            cname,kind=pops[argidx-1]
            a_,b_=norm(cname), norm(pnames[slot])
            if not a_ or not b_: continue
            if pnames[slot].lower() in GENERIC: generic+=1; continue
            checked+=1
            if a_==b_ or a_ in b_ or b_ in a_: continue
            diff.append((op,lname,verb,slot+1,pnames[slot],argidx,cname,kind))

    print(f"{checked} operand pairs compared by name; {len(diff)} differ")
    print(f"({generic} skipped: this port's parameter is generically named)")
    print(f"({skipped} lowerings not comparable)\n")
    if diff:
        print("A NAME DIFFERENCE IS EVIDENCE TO READ, NOT PROOF OF A BUG -- synonyms")
        print("are common (on/rideBike, enemy1/enemyTrainer1, height for Gen 4's y).")
        print("Read each against the handler:\n")
        for op,l,v,slot,pn,ai,cn,k in diff:
            print(f"  0x{op:03X} {l}")
            print(f"        {v} parameter {slot} is named {pn!r}")
            print(f"        but receives args[{ai}], which pret calls {cn!r} ({k})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
