-- src/import/Gen5Facilities.lua -- NIMBASA'S SIDE FACILITIES, FROM THE CARTRIDGE.
--
-- What Big Stadium / Small Court and the Musical read, decoded from the ROM
-- (Black and White alike; nothing typed in from a guide). The Battle Subway
-- has its own module (src/import/Gen5Subway.lua).
--
--   /a/2/0/9  member 0: THE ATHLETES (ov10 0x0215F2F0, script 0x1F4, loads
--             archive 0xD1 member 0 whole): 107 rows of 8 bytes,
--             { u16 slot, u16 tier, u16 sprite, u16 trainer }. The field's
--             init scripts (zones 81-83 Big Stadium, 86-87 Small Court) dress
--             their objects from it: 0x1F6 <slot, object, tier> gives the
--             object the trainer's script (3000 + trainer, the single battle),
--             0x1F3 <slot, object, object, tier> a pair (3000 + t and
--             5000 + t, the double), 0x1F7 <obj x3, row x3> rows 55..106 by
--             index (the sprite too) -- the six "visitors" 0x25C draws once a
--             day. 0x1F8 clears every row's trainer flag (0x58C + trainer,
--             ov10 0x0215A500), the lobby's once-a-day reset.
--
-- build(x) -> { gen5Stadium = { rows = { [0..106] = {slot, tier, sprite,
-- trainer} } } }, merged into constants by the importer.

local Narc = require("src.import.NarcArchive")

local M = {}

M.PATH = { stadium = "/a/2/0/9" }

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

function M.stadium(rom)
  local bytes = rom:read(M.PATH.stadium)
  if not bytes then return nil end
  local arc = Narc.parse(bytes)
  local d = arc and arc:get(0)
  if not d or #d < 8 then return nil end
  local rows = {}
  for i = 0, math.floor(#d / 8) - 1 do
    rows[i] = { slot = u16(d, i * 8), tier = u16(d, i * 8 + 2), sprite = u16(d, i * 8 + 4), trainer = u16(d, i * 8 + 6) }
  end
  return {
    source = "ROM:" .. M.PATH.stadium .. " member 0 (ov10 0x0215F2F0 .. 0x0215F608)",
    rows = rows, count = math.floor(#d / 8),
    -- ov10 0x0215F52C: six distinct of 52 (`rand % (52 - k)`, skipping those
    -- taken), each + 0x37
    visitorFirst = 0x37, visitorCount = 0x34,
    -- ov10 0x0215A480 / 0x0215A490: the script ids a trainer gets
    singleBase = 3000, doubleBase = 5000,
  }
end

function M.build(x)
  local rom = x.rom
  local out = {}
  local okS, stadium = pcall(M.stadium, rom)
  if okS and stadium then out.gen5Stadium = stadium end
  local okM, Musical = pcall(require, "src.import.Gen5MusicalData")
  if okM and Musical and Musical.build then
    local okB, musical = pcall(Musical.build, x)
    if okB and musical then out.gen5Musical = musical
    elseif not okB then print("Gen5MusicalData failed: " .. tostring(musical)) end
  end
  return next(out) and out or nil
end

return M
