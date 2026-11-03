-- ORAS sound effects: the move sounds of the player's own Omega Ruby / Alpha
-- Sapphire dump, rendered to plain PCM so battles only have to play them.
--
-- sound/sango_sound.bcsar (Nintendo's 3DS sound archive, "CSAR"):
--   STRG  names (SEQ_SE_W001, BANK_SE_..., GROUP_...)
--   INFO  tables: sounds, banks, wave archives, files
--   FILE  the files themselves (sequences CSEQ, banks CBNK, wave archives CWAR)
--
-- Move timelines (lib/ORASWazaSeq.lua, ops 0x64 / 0x5D) name a sound as
-- 0x000D0000 + k: category 13 is the battle block of the sound table, which
-- runs from SEQ_SE_BT_001 (sound 769) for 617 sounds -- k = 0..615 in every
-- timeline -- so the sound is BATTLE_BASE + k.
--
-- A move sound is a SEQUENCE: a small note script (CSEQ) playing instruments
-- of a bank (CBNK) whose samples are DSP-ADPCM waves (CWAV in a CWAR).
-- render() plays the script into a mono PCM buffer; lib/ORASEffects.lua bakes
-- the ones the timelines use into WAV files.

local S = {}

S.PATH = "sound/sango_sound.bcsar"
S.BATTLE_CATEGORY = 13
S.BATTLE_BASE = 769          -- SEQ_SE_BT_001, checked by name in open()

local function u8(s, p) return s:byte(p + 1) end
local function u16(s, p) local a, b = s:byte(p + 1, p + 2); return a + b * 256 end
local function s16(s, p) local v = u16(s, p); return v >= 0x8000 and v - 0x10000 or v end
local function u32(s, p)
  local a, b, c, d = s:byte(p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function s32(s, p) local v = u32(s, p); return v >= 0x80000000 and v - 0x100000000 or v end
local function f32(s, p)
  local v = u32(s, p)
  local sign = v >= 0x80000000 and -1 or 1
  local exp = math.floor(v / 0x800000) % 256
  local man = v % 0x800000
  if exp == 0 then return man == 0 and 0 or sign * man * 2 ^ -149 end
  if exp == 255 then return 0 end
  return sign * (1 + man / 0x800000) * 2 ^ (exp - 127)
end
S.u8, S.u16, S.s16, S.u32, S.s32, S.f32 = u8, u16, s16, u32, s32, f32

-- block table of a 3DS sound file ("CSAR", "CSEQ", "CBNK", "CWAR", "CWAV"):
-- { [type] = { off, size } } (offsets from the file start)
local function blocks(d)
  local out = {}
  local n = u16(d, 0x10)
  for i = 0, n - 1 do
    out[u16(d, 0x14 + i * 12)] = { off = u32(d, 0x18 + i * 12), size = u32(d, 0x1C + i * 12) }
  end
  return out
end
S.blocks = blocks

-- ------------------------------------------------------------------ archive

-- read(offset, length) -> bytes of the .bcsar
function S.open(read)
  local head = read(0, 0x40)
  if head:sub(1, 4) ~= "CSAR" then return nil, "not a CSAR sound archive" end
  local b = blocks(head)
  assert(b[0x2000] and b[0x2001] and b[0x2002], "CSAR without STRG / INFO / FILE")
  local self = { read = read, fileBase = b[0x2002].off + 8 }

  -- names (string table: count, then { u16 type, u16 pad, u32 offset, u32 size })
  local strg = read(b[0x2000].off, b[0x2000].size)
  local st = u32(strg, 0x0C) + 8
  local names = {}
  for i = 0, u32(strg, st) - 1 do
    local e = st + 4 + i * 12
    local off, size = u32(strg, e + 4), u32(strg, e + 8)
    names[i] = strg:sub(st + off + 1, st + off + size - 1)
  end
  self.names = names

  -- tables: reference i of INFO = { u16 type, u16 pad, u32 offset from +8 }
  local info = read(b[0x2001].off, b[0x2001].size)
  self.info = info
  local function tableAt(ref)
    local tab = u32(info, 12 + ref * 8) + 8
    local list = {}
    for i = 0, u32(info, tab) - 1 do list[i] = tab + u32(info, tab + 4 + i * 8 + 4) end
    return list
  end

  -- sounds: u32 file, u32 player, u8 volume, ..., ref detail (+0x0C type,
  -- +0x10 offset from the entry), u32 option flags (+0x14) then one u32 per
  -- set bit: bit 0 = string id
  self.sounds = {}
  for i, at in pairs(tableAt(0)) do
    local flags = u32(info, at + 0x14)
    local snd = { index = i, file = u32(info, at), volume = u8(info, at + 8),
                  kind = u16(info, at + 0x0C), detail = at + u32(info, at + 0x10) }
    if flags % 2 == 1 then snd.name = names[u32(info, at + 0x18)] end
    if snd.kind == 0x2203 then
      -- sequence: ref bank id table (+0), u32 track mask (+8), u32 flags (+12)
      -- with bit 0 = start offset
      local d = snd.detail
      local bt = d + u32(info, d + 4)
      snd.banks = {}
      for k = 0, u32(info, bt) - 1 do snd.banks[#snd.banks + 1] = u32(info, bt + 4 + k * 4) % 0x1000000 end
      snd.tracks = u32(info, d + 8)
      local sf = u32(info, d + 12)
      snd.start = (sf % 2 == 1) and u32(info, d + 16) or 0
    end
    self.sounds[i] = snd
  end

  -- banks and wave archives: first u32 = file id
  self.banks, self.warcs = {}, {}
  for i, at in pairs(tableAt(2)) do self.banks[i] = { file = u32(info, at) } end
  for i, at in pairs(tableAt(3)) do self.warcs[i] = { file = u32(info, at) } end

  -- files: ref (+0 type, +4 offset from the entry) to 0x220C internal
  -- { ref into FILE (u16 type, u16 pad, u32 offset from FILE data), u32 size }
  -- or 0x220D external (a path: the music streams)
  self.files = {}
  for i, at in pairs(tableAt(6)) do
    local kind = u16(info, at)
    local f = { kind = kind }
    if kind == 0x220C then
      local q = at + u32(info, at + 4)
      local off = u32(info, q + 4)
      if off ~= 0xFFFFFFFF then f.offset, f.size = off, u32(info, q + 8) end
    end
    self.files[i] = f
  end

  local check = self.sounds[S.BATTLE_BASE]
  self.battleChecked = check and check.name == "SEQ_SE_BT_001"
  return setmetatable(self, { __index = S })
end

-- bytes of file id `id`, or nil (external / not stored in this archive)
function S:file(id)
  local f = self.files[id]
  if not (f and f.offset and f.size and f.size > 0) then return nil end
  return self.read(self.fileBase + f.offset, f.size)
end

-- the archive's sound for a timeline id (0x000D0000 + k), or nil
function S:battleSound(id)
  id = tonumber(id)
  if not id then return nil end
  local cat, k = math.floor(id / 65536), id % 65536
  if cat ~= S.BATTLE_CATEGORY then return nil end
  return self.sounds[S.BATTLE_BASE + k], S.BATTLE_BASE + k
end

-- -------------------------------------------------------------------- waves
--
-- CWAR: INFO (+8 count, then { u16 type, pad, u32 offset from FILE data,
-- u32 size }) and FILE.  CWAV: INFO +8 encoding (0 PCM8, 1 PCM16, 2 DSP-ADPCM),
-- +9 loop, +0xC rate, +0x10 loop start, +0x14 end (sample count), +0x1C
-- channel table (count, refs from the table): channel = ref samples (offset
-- from DATA data), ref ADPCM info (offset from the channel): 16 coefficients,
-- predictor/scale, history.  Channel 0 only (the move sounds are mono).

local function decodeWave(w)
  local b = blocks(w)
  local inf, dat = b[0x7000], b[0x7001]
  if not (inf and dat) then return nil end
  local i0 = inf.off
  local enc, loop = u8(w, i0 + 8), u8(w, i0 + 9) == 1
  local rate = u32(w, i0 + 0x0C)
  local loopStart, count = u32(w, i0 + 0x10), u32(w, i0 + 0x14)
  local ct = i0 + 0x1C
  if u32(w, ct) < 1 then return nil end
  local ch = ct + u32(w, ct + 8)
  local base = dat.off + 8 + u32(w, ch + 4)
  local out = {}
  if enc == 2 then
    local ai = ch + u32(w, ch + 12)
    local coef = {}
    for k = 0, 15 do coef[k] = s16(w, ai + k * 2) end
    local h1, h2 = s16(w, ai + 0x22), s16(w, ai + 0x24)
    local n, p = 0, base
    while n < count do
      local hdr = u8(w, p)
      if not hdr then break end
      local scale = 2 ^ (hdr % 16)
      local ci = math.floor(hdr / 16) * 2
      local c1, c2 = coef[ci] or 0, coef[ci + 1] or 0
      for k = 1, 14 do
        if n >= count then break end
        local byte = u8(w, p + math.floor((k + 1) / 2)) or 0
        local nib = (k % 2 == 1) and math.floor(byte / 16) or (byte % 16)
        if nib >= 8 then nib = nib - 16 end
        local s = math.floor((nib * scale * 2048 + 1024 + c1 * h1 + c2 * h2) / 2048)
        if s > 32767 then s = 32767 elseif s < -32768 then s = -32768 end
        h2, h1 = h1, s
        n = n + 1
        out[n] = s / 32768
      end
      p = p + 8
    end
  elseif enc == 1 then
    for n = 1, count do out[n] = s16(w, base + (n - 1) * 2) / 32768 end
  elseif enc == 0 then
    for n = 1, count do local v = u8(w, base + n - 1); out[n] = (v >= 128 and v - 256 or v) / 128 end
  else
    return nil
  end
  return { samples = out, rate = rate, loop = loop, loopStart = loopStart, count = #out }
end

function S:wave(warcIndex, waveIndex)
  self.waveMemo = self.waveMemo or {}
  local key = warcIndex * 65536 + waveIndex
  local m = self.waveMemo[key]
  if m ~= nil then return m or nil end
  m = false
  local wa = self.warcs[warcIndex]
  local war = wa and self:file(wa.file)
  if war and war:sub(1, 4) == "CWAR" then
    local b = blocks(war)
    local inf, fil = b[0x6800], b[0x6801]
    if inf and fil and waveIndex < u32(war, inf.off + 8) then
      local e = inf.off + 12 + waveIndex * 12
      local off, size = u32(war, e + 4), u32(war, e + 8)
      local w = war:sub(fil.off + 8 + off + 1, fil.off + 8 + off + size)
      if w:sub(1, 4) == "CWAV" then m = decodeWave(w) or false end
    end
  end
  self.waveMemo[key] = m
  return m or nil
end

-- -------------------------------------------------------------------- banks
--
-- CBNK INFO (+8 data): ref wave id table (+8: count, { u32 warc item id,
-- u32 wave index }), ref instrument table (+0x10: count, refs 0x5900).
-- Instrument -> key region table, key region -> velocity region table; a
-- table is 0x6000 direct (one ref), 0x6001 ranges (count, upper keys padded
-- to 4, refs), 0x6002 index (min, max, refs).  Region: u32 wave id index,
-- u32 flags, then one u32 per set bit: 0 original key, 1 volume, 2 pan,
-- 3 pitch (f32), 4 note-off / key group, 9 offset to the envelope
-- (ref -> attack, decay, sustain, hold, release bytes).

local function pickTable(d, at, value)
  local kind, off = u16(d, at), u32(d, at + 4)
  if off == 0xFFFFFFFF then return nil end
  local t = at + off
  if kind == 0x6000 then
    local rk, ro = u16(d, t), u32(d, t + 4)
    if ro == 0xFFFFFFFF then return nil end
    return t + ro, rk
  elseif kind == 0x6001 then
    local n = u32(d, t)
    local refs = t + 4 + math.ceil(n / 4) * 4
    for i = 0, n - 1 do
      if value <= u8(d, t + 4 + i) then
        local rk, ro = u16(d, refs + i * 8), u32(d, refs + i * 8 + 4)
        if ro == 0xFFFFFFFF then return nil end
        return t + ro, rk
      end
    end
  elseif kind == 0x6002 then
    local lo, hi = u8(d, t), u8(d, t + 1)
    if value < lo or value > hi then return nil end
    local refs = t + 4
    local i = value - lo
    local rk, ro = u16(d, refs + i * 8), u32(d, refs + i * 8 + 4)
    if ro == 0xFFFFFFFF then return nil end
    return t + ro, rk
  end
  return nil
end

local function readRegion(d, r)
  local reg = { wave = u32(d, r), key = 60, volume = 127, pan = 64, pitch = 1,
                attack = 127, decay = 127, sustain = 127, hold = 0, release = 127 }
  local flags = u32(d, r + 4)
  local p = r + 8
  for bit = 0, 31 do
    if math.floor(flags / 2 ^ bit) % 2 == 1 then
      if bit == 0 then reg.key = u32(d, p)
      elseif bit == 1 then reg.volume = u32(d, p)
      elseif bit == 2 then reg.pan = u8(d, p)
      elseif bit == 3 then reg.pitch = f32(d, p)
      elseif bit == 9 then
        local e = r + u32(d, p)
        local eo = u32(d, e + 4)
        if eo ~= 0xFFFFFFFF then
          local q = e + eo
          reg.attack, reg.decay, reg.sustain = u8(d, q), u8(d, q + 1), u8(d, q + 2)
          reg.hold, reg.release = u8(d, q + 3), u8(d, q + 4)
        end
      end
      p = p + 4
    end
  end
  return reg
end

function S:bank(index)
  self.bankMemo = self.bankMemo or {}
  local m = self.bankMemo[index]
  if m ~= nil then return m or nil end
  m = false
  local bk = self.banks[index]
  local d = bk and self:file(bk.file)
  if d and d:sub(1, 4) == "CBNK" then
    local b = blocks(d)
    local inf = b[0x5800]
    if inf then
      local base = inf.off + 8
      local wt = base + u32(d, base + 4)
      local waves = {}
      for i = 0, u32(d, wt) - 1 do
        waves[i] = { warc = u32(d, wt + 4 + i * 8) % 0x1000000, wave = u32(d, wt + 8 + i * 8) }
      end
      local it = base + u32(d, base + 12)
      m = { data = d, waves = waves, instruments = it, count = u32(d, it), regionMemo = {} }
    end
  end
  self.bankMemo[index] = m
  return m or nil
end

-- the region bank `b` plays for program `prg`, key, velocity
function S:region(b, prg, key, vel)
  if not b or prg < 0 or prg >= b.count then return nil end
  local memoKey = prg * 65536 + key * 256 + vel
  local r = b.regionMemo[memoKey]
  if r ~= nil then return r or nil end
  r = false
  local d = b.data
  local ref = b.instruments + 4 + prg * 8
  local ro = u32(d, ref + 4)
  if u16(d, ref) == 0x5900 and ro ~= 0xFFFFFFFF then
    local ins = b.instruments + ro
    local kr = pickTable(d, ins, key)
    local vr = kr and pickTable(d, kr, vel)
    if vr then r = readRegion(d, vr) end
  end
  b.regionMemo[memoKey] = r
  return r or nil
end

-- ---------------------------------------------------------------- sequences
--
-- CSEQ DATA (+8) is a note script, one or more tracks, ticks of 1/timebase of
-- a quarter at `tempo` BPM (48 and 120 unless set):
--   00-7F note (key; u8 velocity, varlen length)   80 wait varlen
--   81 program varlen   88 open track (u8 n, u24 offset)   89 jump / 8A call u24
--   A0 random / A1 variable / A2 if / A3-A5 time prefixes for the next command
--   B0-DF one u8: B0 timebase, C0 pan, C1 track volume, C2 main volume,
--         C3 transpose, C4 pitch bend, C5 bend range, C7 note wait,
--         D0-D3 attack/decay/sustain/release, D4 loop start, D5 expression
--   E0-E4 one s16: E1 tempo, E3 sweep   F0 extended   FC loop end
--   FD return   FE alloc tracks u16   FF end of track
-- Played in one pass into a mono buffer; pitch is fixed at each note's start
-- (sweeps and portamento are not played), a loop forever is cut at MAX_SECONDS.

S.OUT_RATE = 16000
S.MAX_SECONDS = 4
S.GAIN = 0.7

local function varlen(d, p)
  local v = 0
  for _ = 1, 4 do
    local b = u8(d, p) or 0
    p = p + 1
    v = v * 128 + (b % 128)
    if b < 128 then break end
  end
  return v, p
end

-- sequence command arguments are BIG-endian (the file tables are little):
-- `88 01 00 00 49` opens track 1 at 0x000049, `A0 C1 00 75 00 7F` is a
-- random volume 117..127
local function u24(d, p) return u8(d, p) * 65536 + u8(d, p + 1) * 256 + u8(d, p + 2) end
local function bs16(d, p)
  local v = u8(d, p) * 256 + u8(d, p + 1)
  return v >= 0x8000 and v - 0x10000 or v
end

-- seconds an envelope byte (0..127) of the given stage lasts (approximate)
local function envTime(v, slow)
  if v >= 127 then return 0 end
  local x = (127 - v) / 127
  return x * x * slow
end

-- sound -> PCM floats (mono, OUT_RATE), or nil, why
function S:render(snd)
  if not (snd and snd.kind == 0x2203) then return nil, "not a sequence sound" end
  local seq = self:file(snd.file)
  if not (seq and seq:sub(1, 4) == "CSEQ") then return nil, "sequence file missing" end
  local b = blocks(seq)
  local dat = b[0x5000]
  if not dat then return nil, "sequence has no DATA" end
  local base = dat.off + 8
  local bank = snd.banks and snd.banks[1] and self:bank(snd.banks[1])
  if not bank then return nil, "bank missing" end

  local OUT = S.OUT_RATE
  local timebase, tempo = 48, 120
  local vars = {}
  local voices = {}
  local rng = 12345
  local function rand(lo, hi)
    rng = (rng * 1103515245 + 12345) % 2147483648
    return lo + rng % math.max(1, hi - lo + 1)
  end

  local function newTrack(pc)
    return { pc = pc, wait = 0, prg = 0, vol = 127, expr = 127, transpose = 0, bend = 0,
             range = 2, noteWait = true, stack = {}, loops = {}, cmp = true, done = false,
             attack = nil, decay = nil, sustain = nil, release = nil }
  end
  local tracks = { newTrack(base + (snd.start or 0)) }
  local mainVol = 127
  local now = 0               -- seconds
  local steps = 0

  local function noteOn(tr, key, vel, len)
    local k = key + tr.transpose
    if k < 0 or k > 127 then return end
    local reg = self:region(bank, tr.prg, k, vel)
    if not reg then return end
    local wv = bank.waves[reg.wave]
    local wave = wv and self:wave(wv.warc, wv.wave)
    if not wave then return end
    local semis = k - reg.key + tr.bend / 127 * tr.range
    local amp = (vel / 127) ^ 2 * (reg.volume / 127) ^ 2 * (tr.vol / 127) ^ 2
      * (tr.expr / 127) ^ 2 * (mainVol / 127) ^ 2 * ((snd.volume or 127) / 127) ^ 2
    -- length 0: a one-shot plays its whole sample (most move sounds are
    -- `note, 0` plus waits); a looping one holds until its track ends
    local length = len > 0 and len * 60 / (tempo * timebase) or (wave.loop and -1 or math.huge)
    voices[#voices + 1] = {
      wave = wave, start = now, length = length, track = tr,
      step = 2 ^ (semis / 12) * (reg.pitch or 1) * wave.rate / OUT, amp = amp,
      attack = envTime(tr.attack or reg.attack, 0.6), hold = (reg.hold or 0) / 127 * 0.5,
      decay = envTime(tr.decay or reg.decay, 3),
      sustain = ((tr.sustain or reg.sustain) / 127) ^ 2,
      release = envTime(tr.release or reg.release, 3),
    }
  end

  -- one command of track tr; returns false when the track stops this tick
  local function exec(tr)
    local d, p = seq, tr.pc
    local c = u8(d, p)
    if not c then tr.done = true; return false end
    p = p + 1
    -- prefixes
    local mode, cond = nil, true
    if c == 0xA2 then cond = tr.cmp; c = u8(d, p); p = p + 1 end
    if c == 0xA0 or c == 0xA1 or (c >= 0xA3 and c <= 0xA5) then mode = c; c = u8(d, p); p = p + 1 end
    local function lastArg(readNormal)
      if mode == 0xA0 then
        local lo, hi = bs16(d, p), bs16(d, p + 2); p = p + 4
        return rand(lo, hi)
      elseif mode == 0xA1 then
        local v = u8(d, p); p = p + 1
        return vars[v] or 0
      end
      local v; v, p = readNormal()
      return v
    end
    local function rdU8() return u8(d, p), p + 1 end
    local function rdS16() return bs16(d, p), p + 2 end
    local function rdVar() return varlen(d, p) end

    local stop = false
    if c < 0x80 then
      local vel = u8(d, p); p = p + 1
      local len = lastArg(rdVar)
      if cond then
        noteOn(tr, c, vel, len)
        if tr.noteWait then tr.wait = len; stop = len > 0 end
      end
    elseif c == 0x80 then
      local w = lastArg(rdVar)
      if cond then tr.wait = w; stop = w > 0 end
    elseif c == 0x81 then
      local v = lastArg(rdVar)
      if cond then tr.prg = v end
    elseif c == 0x88 then
      local n = u8(d, p); local off = u24(d, p + 1); p = p + 4
      if cond and #tracks < 16 then tracks[#tracks + 1] = newTrack(base + off); tracks[#tracks].id = n end
    elseif c == 0x89 then
      local off = u24(d, p); p = p + 3
      if cond then p = base + off end
    elseif c == 0x8A then
      local off = u24(d, p); p = p + 3
      if cond and #tr.stack < 8 then tr.stack[#tr.stack + 1] = p; p = base + off end
    elseif c >= 0xB0 and c <= 0xDF then
      local v = lastArg(rdU8)
      if mode == 0xA3 or mode == 0xA4 then p = p + (mode == 0xA3 and 2 or 4) elseif mode == 0xA5 then p = p + 1 end
      if cond then
        if c == 0xB0 then timebase = math.max(1, v)
        elseif c == 0xC1 then tr.vol = v
        elseif c == 0xC2 then mainVol = v
        elseif c == 0xC3 then tr.transpose = v >= 128 and v - 256 or v
        elseif c == 0xC4 then tr.bend = v >= 128 and v - 256 or v
        elseif c == 0xC5 then tr.range = v
        elseif c == 0xC7 then tr.noteWait = v ~= 0
        elseif c == 0xD0 then tr.attack = v
        elseif c == 0xD1 then tr.decay = v
        elseif c == 0xD2 then tr.sustain = v
        elseif c == 0xD3 then tr.release = v
        elseif c == 0xD4 then tr.loops[#tr.loops + 1] = { pc = p, count = v }
        elseif c == 0xD5 then tr.expr = v
        end
      end
    elseif c >= 0xE0 and c <= 0xE4 then
      local v = lastArg(rdS16)
      if mode == 0xA3 or mode == 0xA4 then p = p + (mode == 0xA3 and 2 or 4) elseif mode == 0xA5 then p = p + 1 end
      if cond and c == 0xE1 and v > 0 then tempo = v end
    elseif c == 0xF0 then
      local sub = u8(d, p); p = p + 1
      if sub and sub >= 0x80 and sub <= 0x95 then
        local var = u8(d, p); local val = bs16(d, p + 1); p = p + 3
        if cond then
          local cur = vars[var] or 0
          if sub == 0x80 then vars[var] = val
          elseif sub == 0x81 then vars[var] = cur + val
          elseif sub == 0x82 then vars[var] = cur - val
          elseif sub == 0x83 then vars[var] = cur * val
          elseif sub == 0x84 then vars[var] = val ~= 0 and math.floor(cur / val) or cur
          elseif sub == 0x86 then vars[var] = rand(0, math.max(0, val))
          elseif sub == 0x90 then tr.cmp = cur == val
          elseif sub == 0x91 then tr.cmp = cur >= val
          elseif sub == 0x92 then tr.cmp = cur > val
          elseif sub == 0x93 then tr.cmp = cur <= val
          elseif sub == 0x94 then tr.cmp = cur < val
          elseif sub == 0x95 then tr.cmp = cur ~= val
          end
        end
      elseif sub == 0xE0 then p = p + 2
      else p = p + 3 end
    elseif c == 0xFB then
      -- envelope reset
      if cond then tr.attack, tr.decay, tr.sustain, tr.release = nil, nil, nil, nil end
    elseif c == 0xFC then
      local l = tr.loops[#tr.loops]
      if cond and l then
        if l.count == 0 then p = l.pc
        else
          l.count = l.count - 1
          if l.count > 0 then p = l.pc else tr.loops[#tr.loops] = nil end
        end
      end
    elseif c == 0xFD then
      if cond then
        local r = table.remove(tr.stack)
        if r then p = r else tr.done = true; stop = true end
      end
    elseif c == 0xFE then
      p = p + 2
    elseif c == 0xFF then
      if cond then tr.done = true; stop = true end
    else
      tr.done = true; stop = true   -- unknown command: stop this track safely
    end
    tr.pc = p
    return not stop
  end

  -- tick loop
  local maxTicks = 200000
  while now < S.MAX_SECONDS do
    local alive = false
    for _, tr in ipairs(tracks) do
      if not tr.done then
        alive = true
        if tr.wait > 0 then tr.wait = tr.wait - 1 end
        local guard = 0
        while tr.wait <= 0 and not tr.done and guard < 256 do
          guard = guard + 1
          if not exec(tr) then break end
        end
        if guard >= 256 then tr.done = true end
      end
    end
    -- a held looping note ends with its track
    for _, v in ipairs(voices) do
      if v.length == -1 and v.track.done then v.length = math.max(0.05, now - v.start) end
    end
    if not alive then break end
    now = now + 60 / (tempo * timebase)
    steps = steps + 1
    if steps > maxTicks then break end
  end

  -- mix
  local endAt = 0
  for _, v in ipairs(voices) do
    if v.length == -1 then v.length = S.MAX_SECONDS end
    local lenS = math.min(v.length, S.MAX_SECONDS)
    local natural = v.wave.loop and math.huge or (v.wave.count / (v.step * OUT))
    v.offAt = math.min(lenS, natural)
    v.stopAt = math.min(v.offAt + v.release, natural, S.MAX_SECONDS)
    endAt = math.max(endAt, v.start + v.stopAt)
  end
  local n = math.max(1, math.floor(math.min(endAt, S.MAX_SECONDS) * OUT))
  local buf = {}
  for i = 1, n do buf[i] = 0 end
  for _, v in ipairs(voices) do
    local w = v.wave
    local smp, cnt = w.samples, w.count
    local ls = w.loopStart or 0
    local i0 = math.floor(v.start * OUT) + 1
    local pos = 0
    local total = math.floor(v.stopAt * OUT)
    for k = 0, total - 1 do
      local i = i0 + k
      if i > n then break end
      local t = k / OUT
      -- envelope
      local e
      if t < v.attack then e = t / v.attack
      elseif t < v.attack + v.hold then e = 1
      elseif t < v.offAt then
        local dt = t - v.attack - v.hold
        e = (v.decay > 0 and dt < v.decay) and (1 - (1 - v.sustain) * dt / v.decay) or v.sustain
      else
        local s0 = v.sustain
        e = v.release > 0 and s0 * math.max(0, 1 - (t - v.offAt) / v.release) or 0
      end
      if e <= 0 and t >= v.offAt then break end
      local ip = math.floor(pos)
      if ip >= cnt - 1 then
        if w.loop and cnt - 1 > ls then pos = ls + (pos - ip); ip = math.floor(pos) else break end
      end
      local fr = pos - ip
      local a, b2 = smp[ip + 1] or 0, smp[ip + 2] or 0
      buf[i] = buf[i] + (a + (b2 - a) * fr) * v.amp * e
      pos = pos + v.step
    end
  end
  -- louder than full scale after GAIN: scale this sound down to fit
  local peak = 0
  for i = 1, n do local a = math.abs(buf[i]); if a > peak then peak = a end end
  if peak * S.GAIN > 0.98 then
    local k = 0.98 / (peak * S.GAIN)
    for i = 1, n do buf[i] = buf[i] * k end
  end
  -- release tails below -54 dB are dropped (smaller cache, same sound)
  local last = n
  while last > 1 and math.abs(buf[last]) < 0.002 do buf[last] = nil; last = last - 1 end
  n = last
  -- a forever-loop cut at MAX_SECONDS fades out over its last 0.3 s
  if endAt >= S.MAX_SECONDS then
    local f = math.floor(0.3 * OUT)
    for k = 0, f - 1 do local i = n - k; if i >= 1 then buf[i] = buf[i] * k / f end end
  end
  return buf, #voices
end

-- PCM floats -> 16-bit mono RIFF WAV bytes
function S.wav(buf, rate)
  rate = rate or S.OUT_RATE
  local n = #buf
  local parts = {}
  local function le(v, bytes)
    local t = {}
    for _ = 1, bytes do t[#t + 1] = string.char(v % 256); v = math.floor(v / 256) end
    return table.concat(t)
  end
  local chunk = {}
  for i = 1, n do
    local s = math.floor(buf[i] * S.GAIN * 32767 + 0.5)
    if s > 32767 then s = 32767 elseif s < -32768 then s = -32768 end
    if s < 0 then s = s + 65536 end
    chunk[#chunk + 1] = string.char(s % 256, math.floor(s / 256))
    if #chunk >= 4096 then parts[#parts + 1] = table.concat(chunk); chunk = {} end
  end
  parts[#parts + 1] = table.concat(chunk)
  local data = table.concat(parts)
  return "RIFF" .. le(36 + #data, 4) .. "WAVEfmt " .. le(16, 4) .. le(1, 2) .. le(1, 2)
    .. le(rate, 4) .. le(rate * 2, 4) .. le(2, 2) .. le(16, 2) .. "data" .. le(#data, 4) .. data
end

return S
