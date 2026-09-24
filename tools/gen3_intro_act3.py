"""Emerald's intro, act three -- addresses and MOTION, out of the cartridge.

The intro's task chain does not stop at the bike ride: 016D7E8 arms 016DBAC and
the chain runs on for 893 more frames.  Three of those beats are AFFINE
backgrounds, which is why the port's scene pass -- which looks for a 4bpp sheet
under a 16-bit tilemap -- could never see them.

Reading the state machines by hand was tried and abandoned: there are ten states
in the Groudon handler alone.  So this RUNS them.  It is a THUMB interpreter big
enough for the intro's code and nothing else, with every call stubbed except the
four that matter -- the SetBgAffine wrapper at 016F2A8, SetGpuReg, the
decompressors, and the BIOS divide the ball's scale is built from.  What it
records per frame is exactly what the hardware is handed, so nothing about the
film's movement is anybody's judgement.

    python3 tools/gen3_intro_act3.py "Pokemon - Emerald Version (USA, Europe).gba"

prints the graphics loads (which give the beats and the frame each lands on) and
writes the track as the rows RomExtractorGen3.INTRO_FINALE.TRACK carries:

    firstFrame lastFrame isAffine x y scale angle flashIndex dx dy dScale dAngle

one row per run in which every channel steps by a constant.  893 frames come out
as 285 rows.

IT ALSO PRINTS THE THREE THINGS THE FIRST PASS MISSED, each of them the reason
some part of the act came out black:

  * PALETTE, every LoadPalette and every CpuSet into the palette buffers.  The
    act does not run on one bank: the LoadPalette at 016DBD4 is the ball's, and
    at frame 46 Groudon's handler copies 512 bytes from D85CD0 over it.
  * REGS, a snapshot of DISPCNT, the four BGxCNT and the window registers on
    the frame each beat lands.  They say which backgrounds are on, which char
    and screen block each one reads, whether it is 64 cells wide -- and that
    WIN0V pins everything after the ball into rows 32..127 with WINOUT 0000.
  * FADE, every BeginNormalPaletteFade -- the white flashes between the beats
    and the dark the clouds close into -- with its selectedPalettes mask, which
    is what says a fade does NOT reach the bolts.
  * OBJECTS, one row a frame per OAM sprite the act puts on screen.  This needs
    a sprite engine, because the two that matter -- Kyogre's BUBBLES and
    Rayquaza's BOLTS -- move from their own callbacks rather than from the
    task, so CreateSprite, DestroySprite, StartSpriteAnim, the animation
    walker and Sin/Cos are modelled here and every live sprite's callback is
    run once a frame.  Groudon's rocks are left out: theirs hands itself to
    the battle-anim machinery, which is a subsystem rather than a callback.
  * FLICKER, the CpuSets the bolt makes into the sky's own palette slot.
"""
import sys

BASE = 0x08000000

class Cpu:
    def __init__(self, rom):
        self.rom = rom
        self.ram = {}                 # byte-addressed, for IWRAM/EWRAM
        self.r = [0]*16
        self.n=self.z=self.c=self.v=False
        self.calls = []
        self.stubs = {}
        self.stop = False

    # ---- memory -------------------------------------------------------
    def rd8(self, a):
        a &= 0xFFFFFFFF
        if BASE <= a < BASE+len(self.rom): return self.rom[a-BASE]
        return self.ram.get(a, 0)
    def rd16(self, a): return self.rd8(a) | (self.rd8(a+1)<<8)
    def rd32(self, a): return self.rd16(a) | (self.rd16(a+2)<<16)
    def wr8(self, a, v): self.ram[a & 0xFFFFFFFF] = v & 0xFF
    def wr16(self, a, v): self.wr8(a, v); self.wr8(a+1, v>>8)
    def wr32(self, a, v): self.wr16(a, v); self.wr16(a+2, v>>16)

    def flags_nz(self, v):
        v &= 0xFFFFFFFF
        self.z = (v == 0); self.n = bool(v & 0x80000000)
        return v
    def sub_flags(self, a, b):
        a &= 0xFFFFFFFF; b &= 0xFFFFFFFF
        r = (a - b) & 0xFFFFFFFF
        self.c = a >= b
        self.v = bool(((a ^ b) & (a ^ r)) & 0x80000000)
        self.flags_nz(r)
        return r
    def add_flags(self, a, b):
        a &= 0xFFFFFFFF; b &= 0xFFFFFFFF
        r = a + b
        self.c = r > 0xFFFFFFFF
        r &= 0xFFFFFFFF
        self.v = bool((~(a ^ b) & (a ^ r)) & 0x80000000)
        self.flags_nz(r)
        return r

    def cond(self, c):
        n,z,cf,v = self.n, self.z, self.c, self.v
        return [z, not z, cf, not cf, n, not n, v, not v,
                cf and not z, (not cf) or z, n==v, n!=v,
                (not z) and n==v, z or n!=v, True, True][c]

    # ---- one instruction ----------------------------------------------
    def step(self):
        pc = self.r[15] & ~1
        h = self.rd16(pc)
        self.r[15] = pc + 2
        top = h >> 13
        if top == 0:
            op = (h >> 11) & 3
            if op != 3:                                   # lsl/lsr/asr imm
                rd, rs, imm = h & 7, (h>>3)&7, (h>>6)&0x1F
                v = self.r[rs]
                if op == 0:
                    if imm: self.c = bool(v & (1 << (32-imm)))
                    v = (v << imm) & 0xFFFFFFFF
                elif op == 1:
                    if imm == 0: imm = 32
                    self.c = bool(v & (1 << (imm-1)))
                    v = (v >> imm) & 0xFFFFFFFF if imm < 32 else 0
                else:
                    if imm == 0: imm = 32
                    s = v - (1<<32) if v & 0x80000000 else v
                    v = (s >> min(imm,31)) & 0xFFFFFFFF
                self.r[rd] = self.flags_nz(v)
            else:                                          # add/sub reg/imm3
                rd, rs = h & 7, (h>>3)&7
                sub = bool(h & 0x200)
                if h & 0x400: b = (h>>6)&7
                else: b = self.r[(h>>6)&7]
                self.r[rd] = self.sub_flags(self.r[rs], b) if sub else self.add_flags(self.r[rs], b)
        elif top == 1:                                     # mov/cmp/add/sub imm8
            op = (h>>11)&3; rd = (h>>8)&7; imm = h & 0xFF
            if op == 0:   self.r[rd] = self.flags_nz(imm)
            elif op == 1: self.sub_flags(self.r[rd], imm)
            elif op == 2: self.r[rd] = self.add_flags(self.r[rd], imm)
            else:         self.r[rd] = self.sub_flags(self.r[rd], imm)
        elif (h & 0xFC00) == 0x4000:                       # alu
            op = (h>>6)&0xF; rd, rs = h & 7, (h>>3)&7
            a, b = self.r[rd], self.r[rs]
            if op == 0:  self.r[rd] = self.flags_nz(a & b)
            elif op==1:  self.r[rd] = self.flags_nz(a ^ b)
            elif op==2:
                s=b&0xFF; self.r[rd] = self.flags_nz((a<<s)&0xFFFFFFFF if s<32 else 0)
            elif op==3:
                s=b&0xFF; self.r[rd] = self.flags_nz((a>>s) if s<32 else 0)
            elif op==4:
                s=min(b&0xFF,31); sv=a-(1<<32) if a&0x80000000 else a
                self.r[rd]=self.flags_nz((sv>>s)&0xFFFFFFFF)
            elif op==5:  self.r[rd] = self.add_flags(a, b + (1 if self.c else 0))
            elif op==6:  self.r[rd] = self.sub_flags(a, b + (0 if self.c else 1))
            elif op==7:
                s=b&0x1F; self.r[rd]=self.flags_nz(((a>>s)|(a<<(32-s)))&0xFFFFFFFF if s else a)
            elif op==8:  self.flags_nz(a & b)
            elif op==9:  self.r[rd] = self.sub_flags(0, b)
            elif op==10: self.sub_flags(a, b)
            elif op==11: self.add_flags(a, b)
            elif op==12: self.r[rd] = self.flags_nz(a | b)
            elif op==13: self.r[rd] = self.flags_nz((a * b) & 0xFFFFFFFF)
            elif op==14: self.r[rd] = self.flags_nz(a & ~b & 0xFFFFFFFF)
            else:        self.r[rd] = self.flags_nz(~b & 0xFFFFFFFF)
        elif (h & 0xFC00) == 0x4400:                       # hi-reg / bx
            op = (h>>8)&3
            rd = (h&7) | ((h>>4)&8); rs = (h>>3)&0xF
            a = self.r[rd] + (4 if rd==15 else 0)
            b = self.r[rs] + (4 if rs==15 else 0)
            if op == 0:   self.r[rd] = (a + b) & 0xFFFFFFFF
            elif op == 1: self.sub_flags(a, b)
            elif op == 2: self.r[rd] = b
            else:         self.r[15] = b & ~1
        elif (h & 0xF800) == 0x4800:                       # ldr rd,[pc,#imm]
            rd = (h>>8)&7
            self.r[rd] = self.rd32((((pc+4) & ~3) + (h & 0xFF)*4))
        elif (h & 0xF000) == 0x5000:                       # load/store reg offset
            ro, rb, rd = (h>>6)&7, (h>>3)&7, h & 7
            a = (self.r[rb] + self.r[ro]) & 0xFFFFFFFF
            code = (h>>9)&7
            if code==0: self.wr32(a, self.r[rd])
            elif code==1: self.wr16(a, self.r[rd])
            elif code==2: self.wr8(a, self.r[rd])
            elif code==3:
                v=self.rd8(a); self.r[rd]= v-256 if v&0x80 else v
                self.r[rd]&=0xFFFFFFFF
            elif code==4: self.r[rd]=self.rd32(a)
            elif code==5: self.r[rd]=self.rd16(a)
            elif code==6: self.r[rd]=self.rd8(a)
            else:
                v=self.rd16(a); self.r[rd]=(v-65536 if v&0x8000 else v)&0xFFFFFFFF
        elif (h & 0xE000) == 0x6000:                       # ldr/str imm5
            bl = (h>>11)&3; imm=(h>>6)&0x1F; rb=(h>>3)&7; rd=h&7
            if bl==0: self.wr32(self.r[rb]+imm*4, self.r[rd])
            elif bl==1: self.r[rd]=self.rd32(self.r[rb]+imm*4)
            elif bl==2: self.wr8(self.r[rb]+imm, self.r[rd])
            else: self.r[rd]=self.rd8(self.r[rb]+imm)
        elif (h & 0xF000) == 0x8000:                       # ldrh/strh imm5
            imm=(h>>6)&0x1F; rb=(h>>3)&7; rd=h&7
            if h & 0x800: self.r[rd]=self.rd16(self.r[rb]+imm*2)
            else: self.wr16(self.r[rb]+imm*2, self.r[rd])
        elif (h & 0xF000) == 0x9000:                       # sp-relative
            rd=(h>>8)&7; imm=h&0xFF
            if h & 0x800: self.r[rd]=self.rd32(self.r[13]+imm*4)
            else: self.wr32(self.r[13]+imm*4, self.r[rd])
        elif (h & 0xF000) == 0xA000:                       # add rd, pc/sp, imm
            rd=(h>>8)&7; imm=(h&0xFF)*4
            self.r[rd] = (self.r[13]+imm) if (h & 0x800) else (((pc+4)&~3)+imm)
        elif (h & 0xFF00) == 0xB000:                       # add sp, #imm
            imm=(h&0x7F)*4
            self.r[13] = (self.r[13] - imm) if (h & 0x80) else (self.r[13] + imm)
        elif (h & 0xF600) == 0xB400:                       # push/pop
            rlist=h&0xFF; load=bool(h&0x800); extra=bool(h&0x100)
            if load:
                for i in range(8):
                    if rlist & (1<<i):
                        self.r[i]=self.rd32(self.r[13]); self.r[13]+=4
                if extra:
                    self.r[15]=self.rd32(self.r[13]) & ~1; self.r[13]+=4
            else:
                if extra:
                    self.r[13]-=4; self.wr32(self.r[13], self.r[14])
                for i in range(7,-1,-1):
                    if rlist & (1<<i):
                        self.r[13]-=4; self.wr32(self.r[13], self.r[i])
        elif (h & 0xF000) == 0xC000:                       # ldmia/stmia
            rb=(h>>8)&7; rlist=h&0xFF; load=bool(h&0x800)
            a=self.r[rb]
            for i in range(8):
                if rlist & (1<<i):
                    if load: self.r[i]=self.rd32(a)
                    else: self.wr32(a, self.r[i])
                    a+=4
            self.r[rb]=a
        elif (h & 0xFF00) == 0xDF00:                       # swi
            pass
        elif (h & 0xF000) == 0xD000:                       # b<cond>
            c=(h>>8)&0xF
            off=h&0xFF
            if off & 0x80: off -= 0x100
            if self.cond(c): self.r[15] = pc + 4 + off*2
        elif (h & 0xF800) == 0xE000:                       # b
            off=h&0x7FF
            if off & 0x400: off -= 0x800
            self.r[15] = pc + 4 + off*2
        elif (h & 0xF800) == 0xF000:                       # bl high
            lo = self.rd16(pc+2)
            off = h & 0x7FF
            if off & 0x400: off -= 0x800
            tgt = (pc + 4 + (off<<12) + ((lo & 0x7FF)<<1)) & 0xFFFFFFFF
            self.r[15] = pc + 4
            self.r[14] = (pc + 4) | 1
            self.call(tgt)
        else:
            raise NotImplementedError("thumb %04X at %07X" % (h, pc))

    def call(self, tgt):
        key = tgt & ~1
        fn = self.stubs.get(key)
        if fn is not None:
            fn(self)
            self.r[15] = self.r[14] & ~1
            return
        self.r[15] = key            # step into it

    def run(self, entry, r0=0, limit=400000):
        self.r[15] = entry & ~1
        self.r[13] = 0x03007F00
        self.r[14] = 0xFFFFFFF0
        self.r[0] = r0
        steps = 0
        while steps < limit:
            if (self.r[15] & ~1) == 0xFFFFFFF0: return True
            self.step()
            steps += 1
        return False


# ---------------------------------------------------------------------------
# the intro's own addresses

GTASKS        = 0x03005E00      # gTasks; a task is 40 bytes, data[] at +8
FUNC          = GTASKS
DATA          = GTASKS + 8
FRAME_COUNTER = 0x030062A0      # ++ once a frame at 016CC48
ACT3_ENTRY    = 0x16DBAC        # what the ride's handler arms
ACT3_LAST     = 0x16EE90        # where the act settles and the title takes over

SET_BG_AFFINE = 0x16F2A8        # SetBgAffine(scrX, scrY, scale, angle)
LOAD_PALETTE  = 0x00A1938       # LoadPalette(src, offset, size)
CREATE_SPRITE = 0x00006DF4      # CreateSprite(template, x, y, subpriority)
DESTROY_SPRITE = 0x000070E8     # DestroySprite(sprite)
START_ANIM    = 0x00081A8       # StartSpriteAnim(sprite, animNum)
SIN           = 0x006F534       # Sin(index, amplitude)
COS           = 0x006F550       # Cos(index, amplitude)
SINE_TABLE    = 0x0329F40       # gSineTable, 256 entries of s16
SPRITES       = 0x02020630      # gSprites; a sprite is 68 bytes
SPRITE_SIZE   = 68
SPRITE_SLOTS  = 64
# the two the act owns; the rocks' template hands itself to the battle anims
# the three the act puts in OAM.  The rocks are a BATTLE ANIMATION's sprite --
# gBattleAnimSpriteTemplate for tag 274A, whose graphics live in
# gBattleAnimPicTable[58] (0524B44 + 58*8) rather than anywhere in the intro's
# own data, which is why the first pass could not find them.  Their callback is
# swapped to the intro's own 016E1F9 after creation, so running them is all it
# takes; the note that used to sit here said they hand themselves to the
# battle-anim machinery and could not be run, and that was wrong.
OBJECT_KINDS  = (0x5E4D14, 0x5E4C4C, 0x596C10)   # bubble, bolt, rock
OBJECT_TILES  = (8, 16, 16)                      # tiles a frame of each
CPU_SET       = 0x02E7084       # SWI 0x0B, which is how the act swaps banks
FADE          = 0x00A1AD4       # BeginNormalPaletteFade(sel, delay, y0, y1, c)
PLTT_UNFADED  = 0x02037714      # gPlttBufferUnfaded; +0x400 is the faded copy
SET_GPU_REG   = 0x0010B4
LZ_VRAM       = 0x0034524
SWI_LZ77      = 0x02E708C
DIVIDE        = 0x02E7540
INTRO_CODE    = ((0x16C000, 0x170000), (0x17A000, 0x17D000))


def s16(v):
    return v - 65536 if v & 0x8000 else v


def run(path, frames=1200):
    rom = open(path, 'rb').read()
    cpu = Cpu(rom)
    state = {'affine': None, 'regs': {}, 'loads': [], 'f': 0,
             'pals': [], 'fades': [], 'snaps': {}, 'objects': [],
             'flicker': [], 'kinds': {}}

    def bg_affine(c):
        state['affine'] = (c.r[0] & 0xFFFF, c.r[1] & 0xFFFF,
                           c.r[2] & 0xFFFF, c.r[3] & 0xFFFF)

    def gpu(c):
        state['regs'][c.r[0] & 0xFFFF] = c.r[1] & 0xFFFF

    def decompress(c):
        src = c.r[0]
        state['loads'].append((state['f'],
                               src - BASE if src >= BASE else src, c.r[1]))

    def divide(c):
        a, b = c.r[0], c.r[1]
        a = a - (1 << 32) if a & 0x80000000 else a
        b = b - (1 << 32) if b & 0x80000000 else b
        if b == 0:
            c.r[0] = 0xFFFF
        else:
            q = abs(a) // abs(b)
            c.r[0] = (-q if (a < 0) != (b < 0) else q) & 0xFFFFFFFF

    def load_palette(c):
        src = c.r[0]
        state['pals'].append(('LoadPalette', state['f'],
                              src - BASE if src >= BASE else src,
                              c.r[1] & 0xFFFF, c.r[2] & 0xFFFF))

    def cpu_set(c):
        src, dst = c.r[0], c.r[1]
        # only the copies that land in a palette buffer say anything here
        if PLTT_UNFADED <= dst < PLTT_UNFADED + 0x800:
            state['pals'].append(('CpuSet', state['f'],
                                  src - BASE if src >= BASE else src,
                                  dst - PLTT_UNFADED, (c.r[2] & 0x1FFFFF) * 2))
            # a single colour written straight into the FADED half is the
            # bolt driving the sky
            faded = dst - (PLTT_UNFADED + 0x400)
            if 0 <= faded < 0x400 and (c.r[2] & 0x1FFFFF) == 1:
                state['flicker'].append((state['f'], faded // 2,
                                         (src - BASE) if src >= BASE else src))

    def fade(c):
        # the fifth argument is on the stack
        state['fades'].append((state['f'], c.r[0] & 0xFFFFFFFF, c.r[1],
                               c.r[2], c.r[3], c.rd32(c.r[13]) & 0xFFFF))

    # ---- the sprite engine ------------------------------------------------
    def slot_at(i): return SPRITES + i * SPRITE_SIZE

    def sine(i): return s16(cpu.rd16(BASE + SINE_TABLE + (i & 0xFF) * 2))

    def create_sprite(c):
        t = c.r[0]
        for i in range(SPRITE_SLOTS):
            a = slot_at(i)
            if cpu.rd8(a + 0x3E) & 1: continue
            oam = cpu.rd32(t + 4)
            for k in range(8): cpu.wr8(a + k, cpu.rd8(oam + k))
            cpu.wr32(a + 0x08, cpu.rd32(t + 8))     # anims
            cpu.wr32(a + 0x0C, cpu.rd32(t + 12))    # images
            cpu.wr32(a + 0x10, cpu.rd32(t + 16))    # affine anims
            cpu.wr32(a + 0x14, t)                   # template
            cpu.wr32(a + 0x18, 0)
            cpu.wr32(a + 0x1C, cpu.rd32(t + 20))    # callback
            cpu.wr16(a + 0x20, c.r[1] & 0xFFFF)
            cpu.wr16(a + 0x22, c.r[2] & 0xFFFF)
            for k in range(0x24, 0x3E): cpu.wr8(a + k, 0)
            cpu.wr8(a + 0x3E, 1)
            cpu.wr8(a + 0x3F, 0)
            cpu.wr8(a + 0x43, c.r[3] & 0xFF)
            state['kinds'][i] = t - BASE
            c.r[0] = i
            return
        c.r[0] = SPRITE_SLOTS

    def destroy_sprite(c):
        cpu.wr8(slot_at((c.r[0] - SPRITES) // SPRITE_SIZE) + 0x3E, 0)

    def start_anim(c):
        a = c.r[0]
        cpu.wr8(a + 0x2A, c.r[1] & 0xFF)
        cpu.wr8(a + 0x2B, 0)
        cpu.wr8(a + 0x2C, 0)
        cpu.wr8(a + 0x3F, cpu.rd8(a + 0x3F) & ~0x10)

    def sin_fn(c):
        c.r[0] = ((sine(c.r[0] & 0xFF) * s16(c.r[1] & 0xFFFF)) >> 8) & 0xFFFFFFFF

    def cos_fn(c):
        c.r[0] = ((sine((c.r[0] & 0xFF) + 64) * s16(c.r[1] & 0xFFFF)) >> 8) \
                 & 0xFFFFFFFF

    def anim_step(i):
        """One frame of AnimateSprite: -1 ends, -2 jumps, -3 loops."""
        a = slot_at(i)
        anims = cpu.rd32(a + 0x08)
        if not anims: return
        cmds = cpu.rd32(anims + cpu.rd8(a + 0x2A) * 4)
        if not cmds: return
        for _ in range(8):
            cmd = cmds + cpu.rd8(a + 0x2B) * 4
            kind = s16(cpu.rd16(cmd))
            if kind == -1:
                cpu.wr8(a + 0x3F, cpu.rd8(a + 0x3F) | 0x10); return
            if kind == -2:
                cpu.wr8(a + 0x2B, cpu.rd16(cmd + 2) & 0xFF); continue
            if kind == -3:
                cpu.wr8(a + 0x2B, cpu.rd8(a + 0x2B) + 1); continue
            left = cpu.rd8(a + 0x2C)
            if left > 0:
                cpu.wr8(a + 0x2C, left - 1); return
            cpu.wr8(a + 0x2C, cpu.rd16(cmd + 2) & 0x3F)
            cpu.wr8(a + 0x2B, cpu.rd8(a + 0x2B) + 1)
            return

    def anim_image(i):
        a = slot_at(i)
        anims = cpu.rd32(a + 0x08)
        if not anims: return 0
        cmds = cpu.rd32(anims + cpu.rd8(a + 0x2A) * 4)
        value = s16(cpu.rd16(cmds + max(0, cpu.rd8(a + 0x2B) - 1) * 4))
        return value if value >= 0 else 0

    state['sprite_step'] = (slot_at, anim_step, anim_image)

    for addr, fn in ((SET_BG_AFFINE, bg_affine), (SET_GPU_REG, gpu),
                     (LZ_VRAM, decompress), (SWI_LZ77, decompress),
                     (DIVIDE, divide), (LOAD_PALETTE, load_palette),
                     (CPU_SET, cpu_set), (FADE, fade),
                     (CREATE_SPRITE, create_sprite),
                     (DESTROY_SPRITE, destroy_sprite),
                     (START_ANIM, start_anim), (SIN, sin_fn), (COS, cos_fn)):
        cpu.stubs[BASE + addr] = fn

    def call(target):
        key = target & ~1
        if key in cpu.stubs:
            cpu.stubs[key](cpu)
            cpu.r[15] = cpu.r[14] & ~1
            return
        for lo, hi in INTRO_CODE:
            if BASE + lo <= key < BASE + hi:
                cpu.r[15] = key
                return
        # anything else is a library call the film's shape does not depend on
        cpu.r[0] = 0
        cpu.r[15] = cpu.r[14] & ~1
    cpu.call = call

    cpu.wr32(FUNC, (BASE + ACT3_ENTRY) | 1)
    rows = []
    for f in range(frames):
        state['f'] = f
        cpu.wr32(FRAME_COUNTER, f)
        func = cpu.rd32(FUNC) & ~1
        if func == 0:
            break
        state['affine'] = None
        if not cpu.run(func, r0=0):
            raise SystemExit('runaway at frame %d in %07X' % (f, func - BASE))
        if func - BASE == ACT3_LAST:
            break
        # every live sprite animates and then runs its own callback
        slot_at, anim_step, anim_image = state['sprite_step']
        for i in range(SPRITE_SLOTS):
            a = slot_at(i)
            if not (cpu.rd8(a + 0x3E) & 1): continue
            anim_step(i)
            cb = cpu.rd32(a + 0x1C) & ~1
            if cb:
                cpu.run(cb, r0=a)
        for i in range(SPRITE_SLOTS):
            a = slot_at(i)
            if not (cpu.rd8(a + 0x3E) & 1): continue
            if cpu.rd8(a + 0x3E) & 4: continue          # invisible
            kind = state['kinds'].get(i)
            if kind not in OBJECT_KINDS: continue
            n = OBJECT_KINDS.index(kind)
            x = s16(cpu.rd16(a + 0x20)) + s16(cpu.rd16(a + 0x24))
            y = s16(cpu.rd16(a + 0x22)) + s16(cpu.rd16(a + 0x26))
            # OFF THE SCREEN IS NOT ON IT.  The rocks are never destroyed --
            # they keep flying for the rest of the act -- so without this the
            # table carries four thousand rows of nothing.
            if not (-64 <= x <= 304 and -64 <= y <= 224):
                continue
            state['objects'].append((f, n + 1, x, y,
                                     anim_image(i) // OBJECT_TILES[n]))
        state['snaps'][f] = dict(state['regs'])
        a, g = state['affine'], state['regs']
        rows.append(dict(f=f, fn=func - BASE,
                         x=s16(a[0]) if a else s16(g.get(0x10, 0)),
                         y=s16(a[1]) if a else s16(g.get(0x14, 0)),
                         s=a[2] if a else 0,
                         a=a[3] if a else 0,
                         pal=s16(cpu.rd16(DATA + 7 * 2)),
                         aff=1 if a else 0))
    return rows, state


def segments(rows):
    """One row per run in which every channel steps by a constant."""
    keys = ('x', 'y', 's', 'a')
    out, i, n = [], 0, len(rows)
    while i < n:
        if i + 1 >= n:
            out.append((i, i))
            break
        step = {k: rows[i + 1][k] - rows[i][k] for k in keys}
        j = i + 1
        while (j + 1 < n and rows[j + 1]['aff'] == rows[j]['aff']
               and rows[j + 1]['pal'] == rows[j]['pal']
               and all(rows[j + 1][k] - rows[j][k] == step[k] for k in keys)):
            j += 1
        out.append((i, j))
        i = j + 1
    return out


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'emerald.gba'
    rows, state = run(path)
    print('frames: %d' % len(rows))
    print('graphics loads (each one starts a beat):')
    for f, src, dst in state['loads']:
        print('   frame %4d  %07X -> %08X' % (f, src, dst))
    print('palette (the act does NOT run on one bank):')
    for how, f, src, off, size in state['pals']:
        print('   frame %4d  %-11s %07X -> +%04X, %d bytes'
              % (f, how, src, off, size))
    print('fades (BeginNormalPaletteFade):')
    for f, sel, delay, y0, y1, colour in state['fades']:
        print('   frame %4d  sel %08X  delay %d  %2d -> %2d  colour %04X'
              % (f, sel, delay, y0, y1, colour))
    print('registers where each beat lands:')
    names = {0x00: 'DISPCNT', 0x08: 'BG0CNT', 0x0A: 'BG1CNT', 0x0C: 'BG2CNT',
             0x0E: 'BG3CNT', 0x40: 'WIN0H', 0x44: 'WIN0V', 0x48: 'WININ',
             0x4A: 'WINOUT'}
    for f, _, _ in state['loads']:
        at = f + 2 if (f + 2) in state['snaps'] else f
        snap = state['snaps'].get(at, {})
        cells = ['%s=%04X' % (names[k], snap[k])
                 for k in sorted(names) if k in snap]
        print('   frame %4d  %s' % (f, ' '.join(cells)))
    print('OBJECTS = [[   (frame kind x y frameIndex)')
    for row in state['objects']:
        print(' '.join(str(v) for v in row))
    print(']]')
    print('flicker (frame, palette index, source):')
    seen = None
    for f, index, src in state['flicker']:
        if seen == (f, index, src): continue
        seen = (f, index, src)
        print('   frame %4d  index %3d  %07X (+%d)'
              % (f, index, src, src - 0xD85CD0))
    print('TRACK = [[')
    for s, e in segments(rows):
        a, b = rows[s], rows[e]
        span = max(1, e - s)
        print(' '.join(str(v) for v in (
            a['f'], b['f'], a['aff'], a['x'], a['y'], a['s'], a['a'], a['pal'],
            (b['x'] - a['x']) // span if e > s else 0,
            (b['y'] - a['y']) // span if e > s else 0,
            (b['s'] - a['s']) // span if e > s else 0,
            (b['a'] - a['a']) // span if e > s else 0)))
    print(']]')


if __name__ == '__main__':
    main()
