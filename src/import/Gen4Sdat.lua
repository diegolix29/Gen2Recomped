-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the SOUND ARCHIVE, and the one thing in it that can be
-- played today.
--
-- `/data/sound/pl_sound_data.sdat` is 7.9 MB of SDAT: SYMB (names), INFO
-- (records), FAT (where each file is) and FILE (all of them).  Most of it is
-- SSEQ sequences over SBNK banks over SWAR wave archives, which is a
-- synthesiser and not a decoder -- that is the music, and it is not this.
--
-- THE CRIES ARE NOT THAT.  Measured across this cartridge:
--
--     493 of 493 species' banks point at wave archive INDEX == the species id
--     every one of those archives holds EXACTLY ONE sample
--     every one of those samples is PCM8
--     two sample rates: 10512 Hz (388 species) and 13379 Hz (105)
--
-- No ADPCM, no multi-sample instruments, no sequencing.  A cry is one 8-bit
-- recording, and this file turns it into a WAV.
--
-- THE INDEX IS THE SPECIES AND THE NAME IS NOT, which is the trap here and it
-- is a good one.  The wave archives are NAMED `WAVE_ARC_PV001`..`PV518` with
-- 493 present, and reading the numbers out of those names gives 387..411
-- missing and 494..518 spare -- which looks exactly like a block of 25 species
-- relocated by +107, and is not.  The names are shuffled; the INDICES are the
-- species.  Species 387's bank is called `BANK_PV432`, and its wave archive
-- index is 387.
--
-- The cartridge says the same thing in one line:
-- `NNS_SndArcPlayerStartSeqEx(handle, -1, waveID, -1, SEQ_PV001_sseq_1)` with
-- `waveID = species` -- one sequence, and the bank number IS the species.  Two
-- statements that cannot borrow from each other, agreeing.

local Gen4Sdat = {}

Gen4Sdat.PATH = "/data/sound/pl_sound_data.sdat"

-- The eight record kinds a SYMB or INFO block indexes, in their fixed order.
Gen4Sdat.SEQ, Gen4Sdat.SEQARC, Gen4Sdat.BANK, Gen4Sdat.WAVEARC = 0, 1, 2, 3

local byte = string.byte
local char = string.char
local concat = table.concat
local floor = math.floor

local function u8(s, o) return byte(s, o + 1) end
local function u16(s, o)
  local a, b = byte(s, o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function u32(s, o)
  local a, b, c, d = byte(s, o + 1, o + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- open(bytes) -> a handle with the four block offsets resolved, or nil.
function Gen4Sdat.open(data)
  if type(data) ~= "string" or #data < 64 then return nil, "too short for an SDAT header" end
  if data:sub(1, 4) ~= "SDAT" then return nil, "not an SDAT" end
  local self = {
    data = data,
    symb = u32(data, 16), info = u32(data, 24),
    fat = u32(data, 32), file = u32(data, 40),
  }
  if not (self.info and self.fat) then return nil, "SDAT block table is truncated" end
  return self
end

-- The record offsets in a block are RELATIVE TO THAT BLOCK, and both blocks
-- use the same shape -- eight u32 offsets at +8, each to a { count, offsets… }
-- table.  Written once because getting it right twice is how the two drift.
local function records(self, block, kind)
  local at = u32(self.data, block + 8 + kind * 4)
  if not at or at == 0 then return nil end
  local base = block + at
  return base, u32(self.data, base) or 0
end

function Gen4Sdat.name(self, kind, index)
  if not self.symb then return nil end
  local base, count = records(self, self.symb, kind)
  if not (base and index < count) then return nil end
  local at = u32(self.data, base + 4 + index * 4)
  if not at or at == 0 then return nil end
  local stop = self.data:find("\0", self.symb + at + 1, true)
  return self.data:sub(self.symb + at + 1, (stop or #self.data + 1) - 1)
end

function Gen4Sdat.count(self, kind)
  local _, n = records(self, self.info, kind)
  return n or 0
end

-- Where a file lives, by its FAT id.  The FAT's offsets are absolute within
-- the SDAT, which is why nothing here adds `self.file`.
function Gen4Sdat.fileAt(self, id)
  local at = self.fat + 12 + id * 16
  local off, size = u32(self.data, at), u32(self.data, at + 4)
  if not size then return nil end
  return off, size
end

-- A bank's four wave archives, and the file it is itself.
function Gen4Sdat.bank(self, index)
  local base, count = records(self, self.info, Gen4Sdat.BANK)
  if not (base and index < count) then return nil end
  local at = u32(self.data, base + 4 + index * 4)
  if not at or at == 0 then return nil end
  at = self.info + at
  return {
    file = u16(self.data, at),
    waves = { u16(self.data, at + 4), u16(self.data, at + 6),
              u16(self.data, at + 8), u16(self.data, at + 10) },
  }
end

function Gen4Sdat.waveArchiveFile(self, index)
  local base, count = records(self, self.info, Gen4Sdat.WAVEARC)
  if not (base and index < count) then return nil end
  local at = u32(self.data, base + 4 + index * 4)
  if not at or at == 0 then return nil end
  return u16(self.data, self.info + at)
end

-- ---------------------------------------------------------------------------
-- SWAR, and the one sample a cry archive holds
-- ---------------------------------------------------------------------------

Gen4Sdat.PCM8, Gen4Sdat.PCM16, Gen4Sdat.ADPCM = 0, 1, 2

-- samples(self, waveArchiveIndex) -> array of { format, loop, rate, time,
-- loopWords, dataWords, at, bytes }.
--
-- A SWAV's length is in 32-BIT WORDS and counts from the end of its own
-- twelve-byte header: `loopOffset + nonLoopLength` words of data begin at
-- header + 12.  Checked against the archives themselves rather than taken on
-- trust -- WAVE_ARC_PV001 is 8260 bytes and 0x3C + 4 + 12 + 2046 * 4 is 8260
-- exactly, which is the layout and the file agreeing to the byte.
function Gen4Sdat.samples(self, index)
  local id = Gen4Sdat.waveArchiveFile(self, index)
  if not id then return nil, "no such wave archive" end
  local at, size = Gen4Sdat.fileAt(self, id)
  if not at then return nil, "wave archive has no file" end
  if self.data:sub(at + 1, at + 4) ~= "SWAR" then return nil, "not a SWAR" end
  local count = u32(self.data, at + 0x38) or 0
  local out = {}
  for i = 0, count - 1 do
    local off = u32(self.data, at + 0x3C + i * 4)
    if off then
      local head = at + off
      local loopWords = u16(self.data, head + 6) or 0
      local dataWords = u32(self.data, head + 8) or 0
      out[i + 1] = {
        format = u8(self.data, head),
        loop = u8(self.data, head + 1) ~= 0,
        rate = u16(self.data, head + 2) or 0,
        time = u16(self.data, head + 4) or 0,
        loopWords = loopWords,
        dataWords = dataWords,
        at = head + 12,
        bytes = (loopWords + dataWords) * 4,
      }
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- WAV
-- ---------------------------------------------------------------------------

local function le32(v)
  v = floor(v) % 4294967296
  return char(v % 256, floor(v / 256) % 256,
              floor(v / 65536) % 256, floor(v / 16777216) % 256)
end
local function le16(v)
  v = floor(v) % 65536
  return char(v % 256, floor(v / 256) % 256)
end

-- An 8-bit mono WAV of one PCM8 sample.
--
-- SWAV PCM8 IS SIGNED AND WAV PCM8 IS UNSIGNED, which is one addition and is
-- the whole difference between a cry and a burst of noise.  Written at 8 bits
-- rather than widened to 16: the recording IS eight bits, and widening it
-- doubles 6 MB of cache to carry no more sound than it started with.
function Gen4Sdat.wav(self, sample)
  if not (sample and sample.format == Gen4Sdat.PCM8) then
    return nil, "only PCM8 is written, and every cry in this cartridge is PCM8"
  end
  local raw = self.data:sub(sample.at + 1, sample.at + sample.bytes)
  if #raw == 0 then return nil, "sample is empty" end
  local out, n = {}, 0
  for i = 1, #raw do
    n = n + 1
    out[n] = char((byte(raw, i) + 128) % 256)
  end
  local pcm = concat(out)
  local rate = sample.rate > 0 and sample.rate or 8000
  return concat({
    "RIFF", le32(36 + #pcm), "WAVE",
    "fmt ", le32(16), le16(1), le16(1), le32(rate), le32(rate), le16(1), le16(8),
    "data", le32(#pcm), pcm,
  })
end

-- Native sequence metadata and bank note definitions, shared by the importer
-- and the runtime player. All offsets remain relative to their owning file.
function Gen4Sdat.sequence(self, index)
  local base, count = records(self, self.info, Gen4Sdat.SEQ)
  if not base or index < 0 or index >= count then return nil end
  local off = u32(self.data, base + 4 + index * 4)
  if not off or off == 0 then return nil end
  local at = self.info + off
  return { file = u16(self.data, at), bank = u16(self.data, at + 4),
           volume = u8(self.data, at + 6), index = index }
end
function Gen4Sdat.instrument(self, bankIndex, program, note)
  local bank = Gen4Sdat.bank(self, bankIndex)
  if not bank then return nil end
  local base = Gen4Sdat.fileAt(self, bank.file)
  if not base or self.data:sub(base + 1, base + 4) ~= "SBNK" then return nil end
  local count = u32(self.data, base + 0x38) or 0
  if program < 0 or program >= count then return nil end
  local entry = base + 0x3C + program * 4
  local kind, off = u8(self.data, entry), u16(self.data, entry + 1)
  if not kind or kind == 0 or not off then return nil end
  local at = base + off
  if kind == 16 then
    local lo, hi = u8(self.data, at), u8(self.data, at + 1)
    if not hi or note < lo or note > hi then return nil end
    at = at + 2 + (note - lo) * 12
    kind, at = u16(self.data, at), at + 2
  elseif kind == 17 then
    local region
    for n = 0, 7 do local hi = u8(self.data, at + n); if hi and note <= hi then region = n; break end end
    if not region then return nil end
    at = at + 8 + region * 12
    kind, at = u16(self.data, at), at + 2
  end
  return { kind = kind, wave = u16(self.data, at),
    archive = bank.waves[(u16(self.data, at + 2) or 0) + 1],
    root = u8(self.data, at + 4) or 60, attack = u8(self.data, at + 5),
    decay = u8(self.data, at + 6), sustain = u8(self.data, at + 7),
    release = u8(self.data, at + 8), pan = u8(self.data, at + 9) or 64 }
end

-- Convert all three SWAV encodings to normalized PCM for the audio backend.
local IMA_STEP = {7,8,9,10,11,12,13,14,16,17,19,21,23,25,28,31,34,37,41,45,50,55,60,66,73,80,88,97,107,118,130,143,157,173,190,209,230,253,279,307,337,371,408,449,494,544,598,658,724,796,876,963,1060,1166,1282,1411,1552,1707,1878,2066,2272,2499,2749,3024,3327,3660,4026,4428,4871,5358,5894,6484,7132,7845,8630,9493,10442,11487,12635,13899,15289,16818,18500,20350,22385,24623,27086,29794,32767}
local IMA_INDEX = {-1,-1,-1,-1,2,4,6,8}
function Gen4Sdat.pcm(self, sample)
  if not sample then return nil end
  local raw = self.data:sub(sample.at + 1, sample.at + sample.bytes)
  local out = {}
  if sample.format == 0 then
    for i = 1, #raw do local v = byte(raw,i);out[i]=(v>=128 and v-256 or v)/128 end
  elseif sample.format == 1 then
    for i = 0, #raw-2, 2 do local v=u16(raw,i);out[#out+1]=(v>=32768 and v-65536 or v)/32768 end
  elseif sample.format == 2 and #raw >= 4 then
    local value = u16(raw,0);if value>=32768 then value=value-65536 end
    local index=math.min(88,u16(raw,2)%128);out[1]=value/32768
    for i=5,#raw do
      local v=byte(raw,i)
      for half=0,1 do
        local code=half==0 and v%16 or floor(v/16)
        local step=IMA_STEP[index+1];local diff=floor(step/8)
        if code%2==1 then diff=diff+floor(step/4) end
        if floor(code/2)%2==1 then diff=diff+floor(step/2) end
        if floor(code/4)%2==1 then diff=diff+step end
        value=math.max(-32768,math.min(32767,value+(code>=8 and -diff or diff)))
        index=math.max(0,math.min(88,index+IMA_INDEX[code%8+1]))
        out[#out+1]=value/32768
      end
    end
  else return nil end
  local loop = sample.format == 2 and math.max(0,(sample.loopWords*4-4)*2+1)
    or sample.loopWords*4/(sample.format==1 and 2 or 1)
  return out, math.floor(loop)
end

return Gen4Sdat
