-- BLACK AND WHITE'S PARTY PLATES (/a/0/7/6; bw_ui_map.md), in the shape
-- Gen4PartyMenu draws (`gen4_party_art`): BW's party screen is Platinum's
-- geometry -- six 128 x 48 plates, two columns, the right one 8 lower -- so
-- the Platinum screen carries BW's own plates.
--
-- Map 18 on tileset 12 and palette 6 is a sampler of every plate state, one
-- plate each at (measured on the composed map):
--   (0, 8)   pink     the plate being moved (Gen4PartyMenu variant 7)
--   (0, 56)  teal     the plate under the cursor (4)
--   (0, 104) navy     a plate at rest (0)
--   (128, 64) red     a fainted Pokemon's plate (2; and 6 under the cursor)
--   (0, 152) striped  an empty slot
-- BY EYE: which state each colour is was read off the screen, not the code
-- (pokeblack has no symbols for the party app); the record says so.

local P = {}

P.PATH = "/a/0/7/6"
P.PLATES = {
  { key = 7, x = 0, y = 8 }, { key = 4, x = 0, y = 56 }, { key = 0, x = 0, y = 104 },
  { key = 2, x = 128, y = 64 }, { key = 6, x = 128, y = 64 },
}
P.EMPTY = { x = 0, y = 152 }

local function crop(img, x, y, w, h)
  local rows = {}
  for r = 0, h - 1 do
    local from = ((y + r) * img.width + x) * 4
    rows[#rows + 1] = img.rgba:sub(from + 1, from + w * 4)
  end
  return { width = w, height = h, rgba = table.concat(rows) }
end

function P.build(x)
  local G = require("src.import.Gen4Graphics")
  local arc = require("src.import.NarcArchive").parse(x.rom:read(P.PATH) or "")
  if not arc then return nil end
  local map, sheet, pal = G.tilemap(arc:get(18)), G.tiles(arc:get(12)), G.palette(arc:get(6))
  local full = map and sheet and pal and G.compose(map, sheet, pal)
  if not full then return nil end
  local index = {}
  local function save(key, image)
    local entry = x:saveImage("party5/" .. key, image)
    if entry then index[key] = entry end
  end
  for _, p in ipairs(P.PLATES) do
    local plate = crop(full, p.x, p.y, 128, 48)
    for _, who in ipairs({ "lead", "back", "lead_egg", "back_egg" }) do
      save(("panel_%s_%d"):format(who, p.key), plate)
    end
  end
  save("panel_none", crop(full, P.EMPTY.x, P.EMPTY.y, 128, 48))
  -- the backdrop behind them: map 20 on tileset 15, palette 2 (the blue grid)
  local bmap, bsheet, bpal = G.tilemap(arc:get(20)), G.tiles(arc:get(15)), G.palette(arc:get(2))
  local back = bmap and bsheet and bpal and G.compose(bmap, bsheet, bpal)
  if back then save("background", crop(back, 0, 0, 256, 192)) end
  index._source = "ROM:/a/0/7/6 map 18 / tileset 12 / palette 6 (plate states by eye), map 20 / 15 / 2"
  return index
end

return P
