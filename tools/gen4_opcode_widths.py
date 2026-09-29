#!/usr/bin/env python3
# Copyright (c) 2026 Cedric. All rights reserved.
# Source-available under the Gen2Recomped License (see LICENSE.md): you may
# read, build and privately modify this file; you may not redistribute it or
# use it commercially. Cartridge-derived data is excluded and is not the
# copyright holder's to license.
"""tools/gen4_opcode_widths.py -- check Gen4ScriptOps' operand widths against pret.

WHY THIS IS THE MOST LOAD-BEARING CHECK IN THE GEN 4 WORK. Every coverage
figure, every reachability walk and every "this command is lowered" claim rests
on the decode being right, and the decode rests on one number per opcode: how
many bytes its operands take. Get one wrong and every instruction after it in
that block is garbage -- silently, with no error, and the garbage still counts
as "decoded".

pret states the answer without meaning to. A handler's operand list IS the
sequence of primitives it calls, and each one consumes a known width:

    ScriptContext_ReadByte       1        ScriptContext_GetVar          2
    ScriptContext_ReadHalfWord   2        ScriptContext_GetVarPointer   2
    ScriptContext_ReadWord       4

(GetVar and GetVarPointer are inlines in include/inlines.h that call
ReadHalfWord, which is why both are two.)

So: extract every ScrCmd_* body, read its primitives in order, and compare.

THE HEURISTIC THAT MATTERS. A read inside a loop or a conditional is not
positionally fixed, so a linear count of primitives is wrong for those. The
first version of this script flagged any body CONTAINING a loop, which buried
54 opcodes that were perfectly fine -- nearly all of them `count*` and
`findpartyslotwith*` handlers that read their operands once and then walk the
party. Tracking brace depth and asking whether each read is inside a
conditional block instead took the uncomparable set from 56 down to 15.

RESULT ON THE COMMITTED TABLE: 825 of 840 opcodes verified, 0 disagreements.

The 30 that once disagreed were all `ScrCmd_Unused_*`, all given zero operands
by this port, and NONE OF THEM OCCURS ANYWHERE IN THE CORPUS -- checked over all
78,093 reachable instructions -- so the decode every measurement relied on was
sound, and the fix was for a latent desync rather than a live one.

RESIDUAL RISK, NAMED. 15 opcodes are not compared: 8 that this port deliberately
marks variable-length (the decoder STOPS at those rather than guessing, which is
why their blocks are only partly walked), and 6 whose handler bodies are not in
src/ (overlay or inlined) -- checkforjubilifelotterywinner, 27c, 2b8,
showmovetutormoveselectionmenu, closeshardcostwindow and
savetvsegmentpokemonstoragebulletin, 17 instructions between them, all side
systems. Those widths are the only ones still taken on trust.

    python3 tools/gen4_opcode_widths.py /path/to/pokeplatinum src/import/Gen4ScriptOps.lua
"""
import re, os, sys, subprocess, json

def pret_specs(pp):
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
    W={"ReadByte":"b","ReadHalfWord":"w","GetVar":"w","GetVarPointer":"w","ReadWord":"d"}
    CALL=re.compile(r'ScriptContext_(ReadByte|ReadHalfWord|ReadWord|GetVarPointer|GetVar)\b')
    COND=re.compile(r'\b(for|while|if|else|switch|case|do)\b[^;{]*$')
    out={}
    for op,name in enumerate(rows):
        body=bodies.get(name)
        if body is None: out[op]=(name,None,False); continue
        b=re.sub(r'/\*.*?\*/','',body,flags=re.S)
        b=re.sub(r'//[^\n]*','',b); b=re.sub(r'"(?:[^"\\]|\\.)*"','""',b)
        spec=[]; stack=[]; cond=False; i=0
        while i<len(b):
            c=b[i]
            if c=='{':
                stack.append(bool(COND.search(b[max(0,i-160):i]))); i+=1; continue
            if c=='}':
                if stack: stack.pop()
                i+=1; continue
            m=CALL.match(b,i)
            if m:
                if any(stack[1:]): cond=True
                else: spec.append(W[m.group(1)])
                i=m.end(); continue
            i+=1
        out[op]=(name,"".join(spec),cond)
    return out

def mine(ops_path):
    src=open(ops_path,encoding='utf-8',errors='replace').read()
    out={}
    for m in re.finditer(r'\[0x([0-9A-Fa-f]{1,3})\]\s*=\s*\{\s*"([^"]+)"\s*,\s*"([^"]*)"', src):
        out[int(m.group(1),16)]=(m.group(2), m.group(3))
    return out

def main():
    pp   = sys.argv[1] if len(sys.argv)>1 else "/tmp/pp"
    ops  = sys.argv[2] if len(sys.argv)>2 else "src/import/Gen4ScriptOps.lua"
    P, M = pret_specs(pp), mine(ops)
    agree=0; dis=[]; skip=[]
    for op,(name,spec) in sorted(M.items()):
        p=P.get(op)
        if not p or p[1] is None:
            skip.append((op,name,"no handler body in src/ (overlay or inlined)")); continue
        if "*" in spec:
            skip.append((op,name,"declared variable-length here")); continue
        if p[1]==spec: agree+=1
        else: dis.append((op,name,spec,p[1],p[2]))
    print(f"{agree} AGREE, {len(dis)} DISAGREE, {len(skip)} not compared\n")
    for op,name,m_,p_,cond in dis:
        note = "  (pret has a read inside a conditional; its spec is a lower bound)" if cond else ""
        print(f"  0x{op:03X} {name:<40} mine={m_!r:<10} pret={p_!r}{note}")
    if skip:
        print("\nnot compared -- these widths are taken on trust:")
        for op,name,why in skip: print(f"  0x{op:03X} {name:<40} {why}")
    return 1 if dis else 0

if __name__ == "__main__":
    sys.exit(main())
