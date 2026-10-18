-- BLACK AND WHITE'S ITEM ICONS (/a/0/2/5), as `gen4_graphics.screens`'
-- `items/icon_NNN` -- the key every bag and shop screen already reads.
--
-- WHICH PICTURE AN ITEM WEARS is a table in the ARM9: one (picture member,
-- palette member) pair of u16 per item, item 0 first -- (1001, 1002), the
-- "?" -- then the Master Ball's (2, 3), the Ultra Ball's (4, 5) and on;
-- items share pictures and palettes freely (Black: ARM9 0x9AB6C). It is
-- found by that opening run rather than by an address, so White's (and any
-- revision's) is found the same way.

local I = {}

I.PATH = "/a/0/2/5"
I.ITEMS = 639
I.SIGNATURE = string.char(0xE9, 0x03, 0xEA, 0x03, 2, 0, 3, 0, 4, 0, 5, 0)

function I.table(rom)
  local arm9 = rom.arm9 and rom:arm9()
  if type(arm9) ~= "string" then return nil end
  local at = arm9:find(I.SIGNATURE, 1, true)
  if not at then return nil end
  local out = {}
  for item = 0, I.ITEMS - 1 do
    local o = at + item * 4
    local a, b, c, d = arm9:byte(o, o + 3)
    if not d then break end
    out[item] = { a + b * 256, c + d * 256 }
  end
  return out
end

function I.build(x)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(I.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  local map = I.table(x.rom)
  if not (arc and map) then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local screens = {}
  local made = {}
  for item = 0, I.ITEMS - 1 do
    local pair = map[item]
    if pair then
      local key = pair[1] .. ":" .. pair[2]
      if made[key] == nil then
        made[key] = false
        local sheet, pal = G.tiles(m(pair[1])), G.palette(m(pair[2]))
        if sheet and pal then
          local cells = {}
          for t = 0, 15 do cells[t + 1] = { tile = t, palette = 0 } end
          local img = G.compose({ width = 32, height = 32, cells = cells }, sheet, pal)
          made[key] = img and x:saveImage(("items/icon_%03d"):format(item), img) or false
        end
      end
      if made[key] then screens[("items/icon_%03d"):format(item)] = made[key] end
    end
  end
  return screens
end

return I
