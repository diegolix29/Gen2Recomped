-- PLATINUM'S DRESS-UP ART (pokeplatinum overlay022, /graphic/imageclip.narc):
-- the hundred contest accessories and the dressing room's backdrop.
--
--   members 1..100   accessory k's picture is member k + 1 (ov22_0225B5A8):
--                    an NCGR in BITMAP format (characterFmt 1) -- rows of
--                    4bpp pixels, low nibble first, not 8x8 tiles -- of
--                    16/32/64 a side
--   member 0         the accessories' palette, sixteen rows
--   member 235       a byte per accessory: which row of member 0 it uses
--                    (its software sprite's paletteSlot)
--   224 / 225 / 226  the dressing room's BG: tiles, palette, tilemap
--                    (ov22_0225A6E0)
--
-- Colour 0 is clear. The theme each accessory is worth something to, and how
-- much, is contest_data's (Gen4ContestData, `themes`).

local Gen4DressUp = {}

Gen4DressUp.PATH = "/graphic/imageclip.narc"
Gen4DressUp.ACCESSORIES = 100
Gen4DressUp.PALETTE = 0
Gen4DressUp.SLOTS = 235
Gen4DressUp.BG_TILES, Gen4DressUp.BG_PALETTE, Gen4DressUp.BG_MAP = 224, 225, 226

local function u16(s, o) return s:byte(o) + s:byte(o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

-- An NCGR's pixels as indices: { width, height, px = { [y*w+x+1] = index } }.
function Gen4DressUp.bitmap(data)
  if type(data) ~= "string" or data:sub(1, 4) ~= "RGCN" then return nil end
  local b = 17                                    -- the CHAR block, 1-based
  local h, w = u16(data, b + 8) * 8, u16(data, b + 10) * 8
  local depth, fmt = u32(data, b + 12), u32(data, b + 20)
  local size, offset = u32(data, b + 24), u32(data, b + 28)
  if depth ~= 3 then return nil end              -- 4bpp only
  local at = b + 8 + offset
  local px = {}
  if fmt == 1 then
    for i = 0, w * h - 1 do
      local byte = data:byte(at + math.floor(i / 2)) or 0
      px[i + 1] = (i % 2 == 0) and byte % 16 or math.floor(byte / 16)
    end
  else
    -- tiled: 8x8 tiles row-major across the width
    local tw = w / 8
    for t = 0, (w / 8) * (h / 8) - 1 do
      local tx, ty = (t % tw) * 8, math.floor(t / tw) * 8
      for i = 0, 63 do
        local byte = data:byte(at + t * 32 + math.floor(i / 2)) or 0
        local x, y = tx + i % 8, ty + math.floor(i / 8)
        px[y * w + x + 1] = (i % 2 == 0) and byte % 16 or math.floor(byte / 16)
      end
    end
  end
  return { width = w, height = h, px = px, bytes = size }
end

local function rgba(bmp, colours)
  local out = {}
  for i = 1, bmp.width * bmp.height do
    local idx = bmp.px[i]
    local c = idx ~= 0 and colours[idx + 1]
    out[i] = c and string.char(c[1], c[2], c[3], 255) or "\0\0\0\0"
  end
  return { width = bmp.width, height = bmp.height, rgba = table.concat(out) }
end

function Gen4DressUp.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local bytes = rom and rom:read(Gen4DressUp.PATH)
  if not bytes then return nil, "no imageclip.narc" end
  local a = N.parse(bytes)
  local function member(i)
    local b = a:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local palette = G.palette(member(Gen4DressUp.PALETTE))
  local slots = member(Gen4DressUp.SLOTS)
  if not (palette and slots and #slots >= Gen4DressUp.ACCESSORIES) then
    return nil, "imageclip palette or slot table missing"
  end
  local images, record = {}, { accessories = {} }
  for id = 0, Gen4DressUp.ACCESSORIES - 1 do
    local bmp = Gen4DressUp.bitmap(member(id + 1))
    if bmp then
      local slot = slots:byte(id + 1)
      local row = {}
      for i = 1, 16 do row[i] = palette[slot * 16 + i] end
      images["acc_" .. id] = rgba(bmp, row)
      record.accessories[id] = { width = bmp.width, height = bmp.height, slot = slot, key = "acc_" .. id }
    end
  end
  local tiles, map, bgPal = G.tiles(member(Gen4DressUp.BG_TILES)), G.tilemap(member(Gen4DressUp.BG_MAP)),
                            G.palette(member(Gen4DressUp.BG_PALETTE))
  local bg = tiles and map and bgPal and G.compose(map, tiles, bgPal)
  if bg then
    images.room = require("src.import.Gen4ContestArt").backdrop(bg, bgPal[1])
    record.room = "room"
  end
  return images, record
end

return Gen4DressUp
