-- ORAS move timelines ("SESD" files, GARC a/0/3/4 in the player's dump).
--
-- Each move's visual sequence is one SESD file: member = move number + 119
-- (members 0-119 are send-outs, status, weather...; 741+ are mega evolution,
-- trainer and gym intros).
--
--   header   "SESD", u32 version (2), u32 0, u32 frame count
--   records  u32 start frame, u32 end frame, u16 target, u16 group,
--            u16 opcode, then the opcode's arguments (no length field;
--            sizes are in OPLEN, learned from all 976 files)
--   end      u32 0xFFFFFFFF, sometimes followed by 0xFFFF padding
--
-- Records are sorted by start frame.  target: 0 attacker, 1 defender, other
-- values for cameras / both sides (still being mapped).
--
-- Opcodes understood so far (see context.md "ORAS move effects"):
--   0x2B  spawn particle set: u32 member of GARC a/0/3/1 (CGFX emitters,
--         named ewNNN_at_* / ewNNN_df_* for move NNN), alive start..end
--   0x64 / 0x5D  load effect resource: u16 id, u16 group (13 seen)
--
-- Every move timeline (621/621) parses with OPLEN; 925/976 files overall.
-- The rest are trainer / gym intros whose opcodes carry file-name strings
-- of varying size; parse() resyncs on those and lists them in .warnings.

local S = {}

S.GARC_PATH = "a/0/3/4"
S.PARTICLE_GARC = "a/0/3/1"
S.MODEL_GARC = "a/0/3/2"
S.MOVE_OFFSET = 119
S.MAX_MOVE = 621

S.OPLEN = {
  [0x00]=0, [0x01]=20, [0x02]=16, [0x03]=32, [0x04]=4, [0x05]=24, [0x06]=20, [0x07]=12,
  [0x08]=16, [0x09]=8, [0x0A]=4, [0x0B]=8, [0x0C]=8, [0x0D]=8, [0x0E]=8, [0x0F]=8,
  [0x10]=36, [0x11]=52, [0x13]=24, [0x14]=0, [0x15]=36, [0x16]=36, [0x17]=48, [0x19]=56,
  [0x1A]=12, [0x1B]=4, [0x1C]=16, [0x1D]=8, [0x1E]=16, [0x1F]=24, [0x20]=20, [0x21]=28,
  [0x22]=4, [0x23]=8, [0x24]=8, [0x25]=4, [0x26]=4, [0x27]=4, [0x28]=12, [0x29]=8,
  [0x2A]=0, [0x2B]=12, [0x2C]=0, [0x2D]=16, [0x2E]=12, [0x2F]=24, [0x30]=28, [0x31]=16,
  [0x32]=36, [0x33]=8, [0x34]=12, [0x35]=16, [0x36]=16, [0x38]=48, [0x39]=24, [0x3A]=12,
  [0x3B]=4, [0x3D]=20, [0x3E]=0, [0x3F]=24, [0x40]=4, [0x41]=16, [0x42]=12, [0x43]=24,
  [0x44]=28, [0x45]=16, [0x46]=36, [0x47]=16, [0x48]=16, [0x49]=12, [0x4A]=4, [0x4C]=48,
  [0x4D]=24, [0x4F]=52, [0x50]=12, [0x51]=8, [0x52]=8, [0x53]=8, [0x55]=4, [0x56]=16,
  [0x57]=4, [0x59]=20, [0x5A]=8, [0x5B]=0, [0x5C]=0, [0x5D]=28, [0x5E]=8, [0x5F]=8,
  [0x60]=8, [0x62]=4, [0x63]=24, [0x64]=24, [0x65]=4, [0x66]=16, [0x67]=16, [0x68]=24,
  [0x69]=20, [0x6A]=20, [0x6B]=16, [0x6C]=12, [0x6E]=8, [0x6F]=4, [0x70]=8, [0x71]=4,
  [0x72]=8, [0x73]=8, [0x74]=0, [0x75]=20, [0x76]=16, [0x77]=4, [0x78]=8, [0x79]=8,
  [0x7A]=0, [0x7B]=76, [0x7C]=16, [0x7D]=12, [0x7E]=24, [0x7F]=16, [0x80]=16, [0x81]=12,
  [0x82]=24, [0x83]=24, [0x84]=24, [0x85]=24, [0x86]=24, [0x87]=80, [0x88]=80, [0x89]=8,
  [0x8B]=20, [0x8D]=48, [0x8E]=4, [0x8F]=8, [0x90]=8, [0x91]=4, [0x92]=4, [0x93]=4,
  [0x94]=0, [0x96]=0, [0x97]=16, [0x98]=16, [0x99]=8, [0x9A]=8, [0x9B]=12, [0x9C]=8,
  [0x9D]=4, [0x9E]=12, [0x9F]=0, [0xA0]=20, [0xA1]=0, [0xA2]=4, [0xA3]=4, [0xA4]=8,
  [0xA6]=28, [0xA7]=20, [0xA8]=24, [0xA9]=40, [0xAA]=8, [0xAC]=28, [0xAD]=4, [0xAE]=20,
  [0xAF]=36, [0xB0]=20, [0xB1]=28, [0xB2]=44, [0xB3]=24, [0xB4]=24, [0xB5]=4, [0xB6]=52,
  [0xB7]=8, [0xB8]=8, [0xB9]=8, [0xBA]=0, [0xBB]=48, [0xBF]=28, [0xC0]=8, [0xC1]=0,
  [0xC2]=4, [0xC3]=0, [0xC4]=0, [0xC5]=16, [0xC7]=4, [0xC9]=4, [0xCD]=36, [0xD0]=12,
  [0xD1]=0, [0xD2]=4, [0xD3]=0, [0xD4]=0,
}

S.OPNAME = {
  [0x2B] = "particle",
  [0x64] = "resource",
  [0x5D] = "resource",
}

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function f32(s, p)
  local v = u32(s, p)
  local sign = v >= 0x80000000 and -1 or 1
  local exp = math.floor(v / 0x800000) % 256
  local man = v % 0x800000
  if exp == 0 then
    if man == 0 then return 0 end
    return sign * man * 2 ^ -149
  elseif exp == 255 then
    return man == 0 and sign * math.huge or 0 / 0
  end
  return sign * (1 + man / 0x800000) * 2 ^ (exp - 127)
end
S.u16, S.u32, S.f32 = u16, u32, f32

-- p is 1-based.  A record header is plausible when its frames are sorted and
-- inside the timeline and its small fields are small.
local function header(s, p, prev, frames)
  if p + 13 > #s then return nil end
  local st, en = u32(s, p), u32(s, p + 4)
  local target, group, op = u16(s, p + 8), u16(s, p + 10), u16(s, p + 12)
  if st < prev or en < st or en > frames + 120 then return nil end
  if target >= 16 or group >= 64 or op >= 0xE0 then return nil end
  if st == 0 and en == 0 and target == 0 and group == 0 and op == 0 then return nil end
  return st, en, target, group, op
end

local function isEnd(s, p)
  if p + 3 > #s or u32(s, p) ~= 0xFFFFFFFF then return false end
  for i = p + 4, #s do if s:byte(i) ~= 0xFF then return false end end
  return true
end

-- Size of a record whose opcode is unknown or variable: the first even size
-- after which the next record (or the end marker) is plausible.
local function resync(s, q, prev, frames)
  for len = 0, 300, 2 do
    local p = q + len
    if p > #s then break end
    if isEnd(s, p) or header(s, p, prev, frames) then return len end
  end
end

-- bytes -> { frames, records = { {start, finish, target, group, op, args} },
--            warnings = { ... } }  or nil, why
function S.parse(bytes)
  if type(bytes) ~= "string" or #bytes < 20 or bytes:sub(1, 4) ~= "SESD" then
    return nil, "not an SESD timeline"
  end
  local frames = u32(bytes, 13)
  local out = { frames = frames, version = u32(bytes, 5), records = {}, warnings = {} }
  local p, prev = 17, 0
  while true do
    if isEnd(bytes, p) then return out end
    local st, en, target, group, op = header(bytes, p, prev, frames)
    if not st then
      return nil, ("bad record at byte %d"):format(p - 1)
    end
    local q = p + 14
    local len = S.OPLEN[op]
    if len then
      local nx = q + len
      if not (isEnd(bytes, nx) or header(bytes, nx, st, frames)) then len = nil end
    end
    if not len then
      len = resync(bytes, q, st, frames)
      if not len then return nil, ("lost sync after opcode 0x%02X"):format(op) end
      out.warnings[#out.warnings + 1] = ("op 0x%02X size %d (table %s)")
        :format(op, len, tostring(S.OPLEN[op]))
    end
    out.records[#out.records + 1] = {
      start = st, finish = en, target = target, group = group, op = op,
      args = bytes:sub(q, q + len - 1),
    }
    prev, p = st, q + len
  end
end

-- Readable fields for the opcodes understood so far.
function S.describe(rec)
  local a = rec.args
  if rec.op == 0x2B and #a >= 4 then
    return { kind = "particle", member = u32(a, 1) }
  elseif (rec.op == 0x64 or rec.op == 0x5D) and #a >= 4 then
    return { kind = "resource", id = u16(a, 1), group = u16(a, 3) }
  end
  return { kind = S.OPNAME[rec.op] or ("op%02X"):format(rec.op) }
end

-- Particle members (GARC a/0/3/1) a timeline uses, in first-use order.
function S.particles(seq)
  local seen, list = {}, {}
  for _, r in ipairs(seq.records) do
    if r.op == 0x2B and #r.args >= 4 then
      local m = u32(r.args, 1)
      if not seen[m] then seen[m] = true; list[#list + 1] = m end
    end
  end
  return list
end

function S.memberForMove(move)
  move = tonumber(move)
  if not move or move < 1 or move > S.MAX_MOVE then return nil end
  return move + S.MOVE_OFFSET
end

-- rom: an N3DSRom, G: the GARC module.  Returns the parsed timeline.
function S.loadMove(rom, G, move)
  local member = S.memberForMove(move)
  if not member then return nil, "no ORAS timeline for move " .. tostring(move) end
  local file = rom:file(S.GARC_PATH)
  if not file then return nil, "dump has no " .. S.GARC_PATH end
  local g, err = G.open(rom, file)
  if not g then return nil, err end
  local bytes, why = g:member(member)
  if not bytes then return nil, why end
  return S.parse(bytes)
end

return S
