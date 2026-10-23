-- BCH (H3D): the 3DS's own binary model / texture / animation container, which
-- every Pokemon model member of Omega Ruby / Alpha Sapphire's a/0/0/8 is
-- (see lib/ORASProbe.lua).  This module reads the parts that need no
-- relocation: the header, the per-kind counts in the content header, and the
-- string table -- enough to say what a member holds before decoding any of it.
--
-- Header (backward compatibility 0x21, as ORAS ships):
--   0x00 "BCH\0"   0x04 backward u8   0x05 forward u8   0x06 version u16
--   0x08 content   0x0C strings   0x10 GPU commands   0x14 data
--   0x18 data ext  0x1C relocation
--   0x20.. the same six as lengths, then two uninitialized-section lengths,
--   0x40 flags u16, 0x42 address count u16 (header ends at 0x44)
--
-- Content header: fifteen {pointer table, count, name tree} triples, in the
-- order KINDS lists.  Counts are plain numbers; the two offsets are relocated
-- at load time and are not touched here.

local B = {}

B.KINDS = {
  "models", "materials", "shaders", "textures", "lookupTables",
  "lights", "cameras", "fogs", "skeletalAnimations", "materialAnimations",
  "visibilityAnimations", "lightAnimations", "cameraAnimations",
  "fogAnimations", "scenes",
}

local function u16(s, p) local a, b = s:byte(p, p + 1); return a + b * 256 end
local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

function B.is(data)
  return type(data) == "string" and #data >= 0x44 and data:sub(1, 4) == "BCH\0"
end

function B.header(data)
  if not B.is(data) then return nil, "not a BCH" end
  local h = {
    backward = data:byte(5), forward = data:byte(6), version = u16(data, 7),
    content = u32(data, 0x09), strings = u32(data, 0x0D), commands = u32(data, 0x11),
    data = u32(data, 0x15), dataExt = u32(data, 0x19), relocation = u32(data, 0x1D),
    contentLen = u32(data, 0x21), stringsLen = u32(data, 0x25),
    commandsLen = u32(data, 0x29), dataLen = u32(data, 0x2D),
    dataExtLen = u32(data, 0x31), relocationLen = u32(data, 0x35),
  }
  if h.backward < 0x21 then
    return nil, string.format("BCH backward compatibility 0x%02X is older than ORAS's", h.backward)
  end
  return h
end

-- { models = n, textures = n, ... } from the content header
function B.counts(data, h)
  h = h or assert(B.header(data))
  local out = {}
  for i, kind in ipairs(B.KINDS) do
    local p = h.content + (i - 1) * 12 + 4 + 1
    out[kind] = (p + 3 <= #data) and u32(data, p) or 0
  end
  return out
end

-- ------------------------------------------------------------ relocation
--
-- Pointers inside a BCH are stored relative to their target section and
-- fixed up through the relocation table: one u32 per pointer, low 25 bits the
-- pointer's position, top 7 bits a flag naming where it sits and what it
-- points at.  The flag is `target | source << 4` (SPICA's H3DRelocator), with
-- sections numbered as SPICA's H3DSection:
--
--   0 contents   1 strings   2 commands   3 commands (source copy)
--   4 raw data   5 .. texture   6 .. vertex   7 .. index16   8 .. index8
--   9 raw ext   10 .. texture  11 .. vertex  12 .. index16  13 .. index8
--  14 base address (0)
--
-- The pointer's position is in words, except for a string target, where it
-- is in bytes.  The target's base is added to the stored value; an index16
-- target also sets bit 31, which is how the GPU's index-buffer register says
-- "16-bit indices" (lib/PICA.lua reads it back).
--
-- ORAS's flags, confirmed against Ivysaur's model and textures: 0x00 0x01
-- 0x02 0x03 (contents) and 0x25 0x26 0x27 0x28 0x2E (commands).
--
-- Returns the patched bytes and { [flag] = count }.

local function f32(bits)
  if bits == 0 then return 0 end
  local sign = bits >= 0x80000000 and -1 or 1
  local exp = math.floor(bits / 0x800000) % 256
  local man = bits % 0x800000
  if exp == 0 then return sign * man * 2 ^ -149 end
  if exp == 255 then return man == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + man / 0x800000) * 2 ^ (exp - 127)
end
B.f32 = f32
B.u32 = u32
B.u16 = u16

function B.relocate(data, h)
  h = h or assert(B.header(data))
  local patches, tally = {}, {}
  local function patch(pos, fn)
    if pos >= 0 and pos + 4 <= #data then patches[#patches + 1] = { pos = pos, fn = fn } end
  end
  local HI = 0x80000000
  local bases = {
    [0] = h.content, [1] = h.strings, [2] = h.commands, [3] = h.commands,
    [4] = h.data, [5] = h.data, [6] = h.data, [7] = h.data + HI, [8] = h.data,
    [9] = h.dataExt, [10] = h.dataExt, [11] = h.dataExt, [12] = h.dataExt + HI,
    [13] = h.dataExt, [14] = 0,
  }
  local sources = { [0] = h.content, [1] = h.strings, [2] = h.commands, [3] = h.commands,
                    [4] = h.data, [9] = h.dataExt }
  for o = 0, h.relocationLen - 4, 4 do
    local v = u32(data, h.relocation + o + 1)
    if not v then break end
    local off = v % 0x2000000
    local flag = math.floor(v / 0x2000000)
    tally[flag] = (tally[flag] or 0) + 1
    local target, source = flag % 16, math.floor(flag / 16)
    local base, from = bases[target], sources[source]
    if base and from then
      local pos = from + (target == 1 and off or off * 4)
      patch(pos, function(x) return x + base end)
    end
  end
  table.sort(patches, function(a, b) return a.pos < b.pos end)

  local parts, at = {}, 1
  for _, p in ipairs(patches) do
    local first = p.pos + 1
    if first >= at then
      parts[#parts + 1] = data:sub(at, first - 1)
      local x = p.fn(u32(data, first)) % 4294967296
      parts[#parts + 1] = string.char(x % 256, math.floor(x / 256) % 256,
                                      math.floor(x / 65536) % 256, math.floor(x / 16777216))
      at = first + 4
    end
  end
  parts[#parts + 1] = data:sub(at)
  return table.concat(parts), tally
end

-- Which section an absolute offset falls in, for the anatomy dump.
function B.section(h, v)
  local function inside(base, len) return len and len > 0 and v >= base and v < base + len end
  if inside(h.content, h.contentLen) then return "C", v - h.content end
  if inside(h.strings, h.stringsLen) then return "S", v - h.strings end
  if inside(h.commands, h.commandsLen) then return "G", v - h.commands end
  if inside(h.data, h.dataLen) then return "D", v - h.data end
  if inside(h.dataExt, h.dataExtLen) then return "X", v - h.dataExt end
  return nil
end

-- The NUL-terminated string at absolute offset `v`.
function B.cstring(data, v)
  local stop = data:find("\0", v + 1, true)
  return stop and data:sub(v + 1, stop - 1) or nil
end

-- `n` words from absolute offset `at`, each labelled: a pointer into a
-- section (strings resolved), a plausible float, or a plain integer.
function B.annotate(data, h, at, n)
  local out = {}
  for i = 0, n - 1 do
    local p = at + i * 4
    local v = u32(data, p + 1)
    if not v then break end
    local sec, rel = B.section(h, v)
    local label
    if sec == "S" then
      label = string.format("str %q", B.cstring(data, v) or "?")
    elseif sec and v >= 0x40 then
      label = string.format("-> %s+0x%X", sec, rel)
    else
      local f = f32(v)
      local af = math.abs(f)
      if v > 0xFFFF and af > 1e-6 and af < 1e6 then
        label = string.format("f %.5g", f)
      else
        label = string.format("%d", v)
      end
    end
    out[#out + 1] = string.format("+%03X %08X  %s", i * 4, v, label)
  end
  return out
end

-- every NUL-terminated name in the string table, in order
function B.strings(data, h)
  h = h or assert(B.header(data))
  local out = {}
  local first, last = h.strings + 1, math.min(#data, h.strings + h.stringsLen)
  local at = first
  while at <= last do
    local stop = data:find("\0", at, true) or (last + 1)
    if stop > at then out[#out + 1] = data:sub(at, stop - 1) end
    at = stop + 1
  end
  return out
end

return B
