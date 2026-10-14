-- GEN 5 TEXT (Black and White): one bank per NARC member of /a/0/0/2 (the
-- system text -- names, menus, descriptions) or /a/0/0/3 (the story text).
--
-- A bank is
--   u16 sections, u16 entries, u32 total size, u32 (zero), u32 sectionOffset[sections]
-- and each section
--   u32 size, then per entry { u32 offset (from the section), u16 chars, u16 (flags) }
-- with the characters after the table. Black and White use one section.
--
-- A STRING IS UTF-16 XOR A ROLLING KEY, decrypted from its LAST character back
-- to its first: the last character is the terminator 0xFFFF, so the key it was
-- encrypted with is `enc[last] ^ 0xFFFF`, and each step back rotates the key
-- right by three -- key = (key >> 3 | key << 13) & 0xFFFF. (The library the
-- cartridge uses, `GFL_STR`, decrypts the same way; pokeblack calls the
-- archive the system / script message banks.)
--
-- Control characters: 0xFFFF ends the string, 0xFFFE breaks the line, and
-- 0xF000 opens a command -- the next u16 is the command, then a count, then
-- that many u16 arguments. 0x0100..0x01FF in a command's place mark the
-- text-variable commands (a name, a number) and are written {VARn}.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local T = {}

local function u16(s, at) local a, b = s:byte(at + 1, at + 2); return (a or 0) + (b or 0) * 256 end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end

-- parse(bytes) -> { count, strings = { [0..count-1] = {u16...} } } or nil
function T.parse(bytes)
  if type(bytes) ~= "string" or #bytes < 16 then return nil end
  local sections, entries = u16(bytes, 0), u16(bytes, 2)
  if sections < 1 or sections > 8 then return nil end
  local base = u32(bytes, 12)                  -- the first section
  if base + 4 > #bytes then return nil end
  local out = { count = entries, codes = {} }
  for i = 0, entries - 1 do
    local rec = base + 4 + i * 8
    if rec + 8 > #bytes then break end
    local offset, chars = u32(bytes, rec), u16(bytes, rec + 4)
    local at = base + offset
    if chars > 0 and at + chars * 2 <= #bytes then
      local enc = {}
      for c = 0, chars - 1 do enc[c] = u16(bytes, at + c * 2) end
      local key = bxor(enc[chars - 1], 0xFFFF)
      local dec = {}
      for c = chars - 1, 0, -1 do
        dec[c] = bxor(enc[c], key)
        key = band(bor(rshift(key, 3), lshift(key, 13)), 0xFFFF)
      end
      out.codes[i] = dec
    else
      out.codes[i] = {}
    end
  end
  return out
end

local function utf8(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + rshift(cp, 6), 0x80 + band(cp, 0x3F)) end
  return string.char(0xE0 + rshift(cp, 12), 0x80 + band(rshift(cp, 6), 0x3F), 0x80 + band(cp, 0x3F))
end

-- The cartridge's private-use glyphs, as the Gen 4 port spells them.
T.GLYPHS = { [0x2486] = "PK", [0x2487] = "MN", [0x246D] = "\u{2642}", [0x246E] = "\u{2640}" }

-- A COMPRESSED STRING (the trainer names among others): 0xF100 first, then
-- the characters as 9-bit values packed least-significant-bit first into the
-- following u16 words, 0x1FF ending it.
function T.unpack9(codes)
  local out, acc, bits, n = {}, 0, 0, 0
  local i = 1
  while codes[i] ~= nil and codes[i] ~= 0xFFFF or (codes[i] == 0xFFFF and bits >= 9) do
    if codes[i] ~= nil and codes[i] ~= 0xFFFF then
      acc = acc + codes[i] * 2 ^ bits
      bits = bits + 16
      i = i + 1
    end
    while bits >= 9 do
      local c = acc % 512
      acc = math.floor(acc / 512)
      bits = bits - 9
      if c == 0x1FF then out[n] = 0xFFFF return out end
      out[n] = c
      n = n + 1
    end
    if codes[i] == nil or codes[i] == 0xFFFF then break end
  end
  out[n] = 0xFFFF
  return out
end

-- render(codes) -> a Lua (UTF-8) string, commands as {CMD xxxx args}
function T.render(codes)
  if not codes then return nil end
  if codes[0] == 0xF100 then codes = T.unpack9(codes) end
  local out, i = {}, 0
  local n = 0
  for k in pairs(codes) do if k + 1 > n then n = k + 1 end end
  while i < n do
    local c = codes[i]
    if c == 0xFFFF then break
    elseif c == 0xFFFE then out[#out + 1] = "\n"; i = i + 1
    elseif c == 0xF000 then
      local cmd, argc = codes[i + 1] or 0, codes[i + 2] or 0
      local args = {}
      for a = 1, argc do args[a] = codes[i + 2 + a] or 0 end
      if cmd >= 0x0100 and cmd <= 0x01FF then
        out[#out + 1] = ("{VAR%d}"):format((args[1] or 0) + 1)
      elseif cmd == 0xBE00 or cmd == 0xBE01 then
        -- the text box's page break (BE01 waits for a press, BE00 scrolls):
        -- the engine's own paragraph break, a blank line
        out[#out + 1] = "\n\n"
      else
        out[#out + 1] = ("{CMD %04X%s}"):format(cmd, #args > 0 and (" " .. table.concat(args, " ")) or "")
      end
      i = i + 3 + argc
    else
      out[#out + 1] = T.GLYPHS[c] or utf8(c)
      i = i + 1
    end
  end
  return table.concat(out)
end

-- every string of a bank, rendered: { [0..count-1] = "..." }
function T.bank(bytes)
  local b = T.parse(bytes)
  if not b then return nil end
  local out = {}
  for i = 0, b.count - 1 do out[i] = T.render(b.codes[i]) or "" end
  return out, b.count
end

-- the cache's label for a string, the Gen 4 spelling with the archive
-- (s: system, t: story/script) in front
function T.label(archive, bank, index)
  return ("TEXT_G5%s_%04d_%05d"):format(archive == "story" and "T" or "S", bank, index)
end

return T
