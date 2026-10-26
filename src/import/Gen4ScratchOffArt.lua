-- PLATINUM'S SCRATCH-OFF CARDS ART (pokeplatinum
-- src/applications/scratch_off_cards/*.c): /resource/eng/scratch/scratch.narc,
-- 41 members, read the way LoadBackgrounds / the sprite manager read them.
--
-- The app swaps the screens (GX_DISP_SELECT_SUB_MAIN): the MAIN engine is
-- the touch screen at the bottom, the SUB engine the top.
--
--   top     BG3: 35 chars / 37 map (LoadDefaultTopScreenBackground)
--           BG2: 38 chars / 40 map, 512 wide, every cell on palette row
--                card + 1 (UpdateBackgroundPalette) -- `topCard_<k>`
--           palette 34, its first five rows raw (GXS_LoadBGPltt)
--   bottom  BG1: 4 chars / 6 map, 512 wide, row card + 4 -- `bottomCard_<k>`
--           BG0: 7 chars / 9 map, the scratch layer (one tile per screen
--                cell, which is what lets ScratchPixelsAtPosition clear a
--                pixel by its screen position) -- `scratch`
--           palette 0, its first ten rows raw (GX_LoadBGPltt)
--   sprites cards 12 / 13 / 11 / 10 (four rows), boxes 16 / 17 / 15 / 14
--           (the matching-pair box's highlight swaps the whole palette for
--           22 .. 29), win popup 20 / 21 / 19 / 18, Pokemon 32 / 33 / 31 / 30
--           (five rows: the four prizes' Pokemon and Ditto)
--
-- Pictures: the backgrounds above; `card_<k>`, `box_<c>` (cell c of the box
-- bank on its OAM palette), `box_<c>_row<r>` (on row r instead),
-- `box_6_hl<i>` (the matching box on row 3 of palette 22 + i), `popup_<c>`,
-- `mon_<c>`, each with its origin. Data (`gen4_scratch_off`): the NANR
-- sequences of each group as { { cell, duration } }.

local S = {}

S.PATH = "/resource/eng/scratch/scratch.narc"
S.HGSS_PATH = "/a/2/0/5"                          -- HGSS: the same 41 members

local function opener(rom)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom and (rom:read(S.PATH) or rom:read(S.HGSS_PATH))
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

-- the raw first `rows` rows of an NCLR, as GX_LoadBGPltt copies them
local function rawRows(G, data, rows)
  local pal = G.palette(data, true)
  local out = {}
  for i = 1, rows * 16 do out[i] = pal and pal[i] or { 0, 0, 0 } end
  return out
end

-- a map with every cell moved onto one palette row
local function onRow(map, row)
  local out = { width = map.width, height = map.height, affine = map.affine, linear = map.linear, cells = {} }
  for i, c in ipairs(map.cells) do
    out.cells[i] = { tile = c.tile, flipX = c.flipX, flipY = c.flipY, palette = row }
  end
  return out
end

-- every cell of a bank; `rowOf(oam)` picks each OAM entry's palette row
local function cells(G, member, char, cell, colours, rowOf)
  local Cells = require("src.import.Gen4Cells")
  local sheet, bank = G.tiles(member(char)), Cells.parse(member(cell), G)
  local out = {}
  if not (sheet and bank) then return out end
  for i, c in ipairs(bank.cells) do
    local flat = { oam = {} }
    for k, v in pairs(c) do if k ~= "oam" then flat[k] = v end end
    local row = 0
    for j, o in ipairs(c.oam) do
      local copy = {}
      for k, v in pairs(o) do copy[k] = v end
      row = rowOf and rowOf(o) or (o.palette or 0)
      copy.palette = 0
      flat.oam[j] = copy
    end
    local slice = {}
    for k = 1, 16 do slice[k] = colours[row * 16 + k] or { 0, 0, 0 } end
    local pic = Cells.assemble(flat, sheet, slice, bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(flat) end
    out[i - 1] = pic
  end
  return out
end

function S.images(rom)
  local member = opener(rom)
  if not member then return nil, "no scratch.narc" end
  local G = require("src.import.Gen4Graphics")
  local out = {}
  local top = rawRows(G, member(34), 5)
  local bottom = rawRows(G, member(0), 10)
  out.topBase = G.compose(G.tilemap(member(37)), G.tiles(member(35)), top)
  local topMap, bottomMap = G.tilemap(member(40)), G.tilemap(member(6))
  local topTiles, bottomTiles = G.tiles(member(38)), G.tiles(member(4))
  for k = 0, 3 do
    out["topCard_" .. k] = G.compose(onRow(topMap, k + 1), topTiles, top)
    out["bottomCard_" .. k] = G.compose(onRow(bottomMap, k + 4), bottomTiles, bottom)
  end
  out.scratch = G.compose(G.tilemap(member(9)), G.tiles(member(7)), bottom)
  for c, pic in pairs(cells(G, member, 12, 11, rawRows(G, member(13), 4))) do out["card_" .. c] = pic end
  local boxColours = rawRows(G, member(17), 4)
  for c, pic in pairs(cells(G, member, 16, 15, boxColours)) do out["box_" .. c] = pic end
  for r = 0, 3 do
    for c, pic in pairs(cells(G, member, 16, 15, boxColours, function(o) return (o.palette or 0) + r end)) do
      out[("box_%d_row%d"):format(c, r)] = pic
    end
  end
  for i = 0, 7 do
    local hl = rawRows(G, member(22 + i), 4)
    local picked = cells(G, member, 16, 15, hl, function() return 3 end)
    out["box_6_hl" .. i] = picked[6]
  end
  for c, pic in pairs(cells(G, member, 20, 19, rawRows(G, member(21), 1))) do out["popup_" .. c] = pic end
  for c, pic in pairs(cells(G, member, 32, 31, rawRows(G, member(33), 5))) do out["mon_" .. c] = pic end
  return out
end

function S.data(rom)
  local member = opener(rom)
  if not member then return nil end
  local G = require("src.import.Gen4Graphics")
  local CA = require("src.import.Gen4CellAnim")
  local out = { sequences = {} }
  -- the backdrops: colour 0 of each engine's BG palette (34 top, 0 bottom)
  local top, bottom = G.palette(member(34), true), G.palette(member(0), true)
  out.backdropTop = top and top[1] and { top[1][1], top[1][2], top[1][3] } or { 0, 0, 0 }
  out.backdropBottom = bottom and bottom[1] and { bottom[1][1], bottom[1][2], bottom[1][3] } or { 0, 0, 0 }
  for name, m in pairs({ card = 10, box = 14, popup = 18, mon = 30 }) do
    local anim = CA.parse(member(m), G)
    local list = {}
    for s, q in ipairs((anim and anim.sequences) or {}) do
      local frames = {}
      for _, f in ipairs(q.frames) do frames[#frames + 1] = { f.cell, f.duration } end
      list[s - 1] = frames
    end
    out.sequences[name] = list
  end
  return out
end

return S
