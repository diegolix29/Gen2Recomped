-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FIELD-MOVE PICTURES: the obstacle animations and the HM cut-in.
-- Written as the cache module `gen4_pt_field_fx`.
--
-- 1. THE OBSTACLES (`parts`), /graphic/hiden_effect.narc. ScrCmd_StartDestroy-
--    ObstacleAnimation <kind, var> (pokeplatinum src/scrcmd.c) -> ov6_0224899C,
--    whose table builds a field effect through ov6_02248140(narc, model,
--    firstAnim, animCount):
--
--      kind 0     Cut          ov6_0224825C  model 3, anims 0..2  SEQ_SE_DP_FW015
--      kind 1, 2  Rock Smash   ov6_02248340  model 8, anims 4..7  SEQ_SE_DP_FW088
--
--    The archive's members 0..14 are byte for byte HGSS's /a/1/3/4 0..14, so
--    the parts are packed by Gen4HgssFieldFx.build over this path. (9..14 are
--    the waterfall's: ov6_022485F4, models 14 and 11.)
--
-- 2. THE HM CUT-IN (`cutIn`), /data/field_cutin.narc -- HMCutIn_StartTask
--    (src/overlay006/hm_cut_in.c), as CutIn_InitSpriteResources loads it:
--
--      bg      members 0 / 1 / 2: NCGR, NSCR, NCLR. The NCLR's first sixteen
--              colours go to BG palette 12 and every tile of the 32 x 32 map
--              is set to it (Bg_ChangeTilemapRectPalette ... 12), on BG3.
--      wind    char 10, palette 3, cell 11, anim 12 (sCutInWindParticle*):
--              animations 0 and 1
--      player  male: char 13, cell 14, anim 15, palette 3;
--              female: char 16, cell 17, anim 18, palette 4.
--              Animation 6 ("pull ball out of pocket").
--      mon     cell 6 over the Pokemon's own 80 x 80 front picture; only the
--              cell's placement is needed here, the picture is the species'.

local A = {}

A.PATH = "/graphic/hiden_effect.narc"
A.CUTIN_PATH = "/data/field_cutin.narc"
A.PARTS = {
  cut       = { model = 3, anims = { 0, 1, 2 } },
  rockSmash = { model = 8, anims = { 4, 5, 6, 7 } },
}
A.CUTIN = {
  bg = { tiles = 0, map = 1, palette = 2 },
  wind = { tiles = 10, cell = 11, anim = 12, palette = 3 },
  male = { tiles = 13, cell = 14, anim = 15, palette = 3 },
  female = { tiles = 16, cell = 17, anim = 18, palette = 4 },
  monCell = 6,
}

local function row0(colours)
  local out = {}
  for i = 1, 16 do out[i] = colours[i] or { 0, 0, 0 } end
  return out
end

-- the cut-in's pictures; `save(rel, image, meta)` -> the saved path
function A.cutIn(rom, save)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local Narc = require("src.import.NarcArchive")
  local raw = rom:read(A.CUTIN_PATH)
  if not raw then return nil, "no " .. A.CUTIN_PATH end
  local arc = assert(Narc.parse(raw))
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local C = A.CUTIN
  local out = {}

  -- BG3: every tile on the one palette
  do
    local sheet = G.tiles(member(C.bg.tiles))
    local map = G.tilemap(member(C.bg.map))
    local pal = G.palette(member(C.bg.palette))
    if sheet and map and pal then
      for _, cell in ipairs(map.cells or {}) do cell.palette = 0 end
      local image = G.compose(map, sheet, row0(pal))
      out.bg = image and save("field_cutin/bg", image) or nil
    end
  end

  -- an OBJ: every cell of its bank on one palette row, plus its sequences
  local function obj(key, spec)
    local sheet = G.tiles(member(spec.tiles))
    local bank = Cells.parse(member(spec.cell), G)
    local pal = G.palette(member(spec.palette))
    if not (sheet and bank and pal) then return nil end
    local colours = row0(pal)
    local rec = { cells = {}, anims = {} }
    for i, cell in ipairs(bank.cells) do
      local flat = {}
      for k, v in pairs(cell) do flat[k] = v end
      flat.oam = {}
      for j, o in ipairs(cell.oam or {}) do
        local c = {}
        for k, v in pairs(o) do c[k] = v end
        c.palette = 0
        flat.oam[j] = c
      end
      local image = Cells.assemble(flat, sheet, colours, bank, G)
      if image then
        local ox, oy = Cells.extent(flat)
        rec.cells[i - 1] = { path = save(("field_cutin/%s_%d"):format(key, i - 1), image), x = ox, y = oy,
                             w = image.width, h = image.height }
      end
    end
    local anim = Anim.parse(member(spec.anim), G)
    for s, seq in ipairs((anim and anim.sequences) or {}) do
      local frames = {}
      for f, fr in ipairs(seq.frames or {}) do
        frames[f] = { cell = fr.cell, duration = fr.duration, x = fr.x, y = fr.y }
      end
      rec.anims[s - 1] = { frames = frames, loopStart = seq.loopStart, mode = seq.playbackMode }
    end
    return rec
  end
  out.wind = obj("wind", C.wind)
  out.male = obj("male", C.male)
  out.female = obj("female", C.female)

  -- where the 80 x 80 Pokemon sits about its sprite position
  local bank = Cells.parse(member(C.monCell), G)
  local cell = bank and bank.cells and bank.cells[1]
  if cell then
    local ox, oy, w, h = Cells.extent(cell)
    out.monCell = { x = ox, y = oy, w = w, h = h }
  end
  return out
end

-- 3. FOG (OVERWORLD_WEATHER_FOG, 14: ov5_021DAEC0) -- the layer Defog clears.
--    Its BG set is Unk_ov5_021F8D90[6] of /data/weather_sys.narc: palette 51,
--    char 45, screen 47, loaded on BG2 with every tile on palette 6
--    (ov5_021D6D84 / _6DCC / _6E20), colour 0 clear.
A.WEATHER_PATH = "/data/weather_sys.narc"
A.FOG_BG = { palette = 51, tiles = 45, map = 47 }

function A.fogLayer(rom, save)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local raw = rom:read(A.WEATHER_PATH)
  if not raw then return nil end
  local arc = assert(Narc.parse(raw))
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local sheet = G.tiles(member(A.FOG_BG.tiles))
  local map = G.tilemap(member(A.FOG_BG.map))
  local pal = G.palette(member(A.FOG_BG.palette))
  if not (sheet and map and pal) then return nil end
  for _, cell in ipairs(map.cells or {}) do cell.palette = 0 end
  local image = G.compose(map, sheet, row0(pal))
  return image and save("field_cutin/fog_layer", image) or nil
end

function A.build(x)
  local out = { source = "ROM:" .. A.PATH .. " + " .. A.CUTIN_PATH
                  .. " (pokeplatinum ov6_0224899C / hm_cut_in.c)" }
  local okP, built = pcall(require("src.import.Gen4HgssFieldFx").build, x,
                           { path = A.PATH, parts = A.PARTS, source = "ROM:" .. A.PATH })
  if okP and built then out.parts = built.parts
  else print("gen4_pt_field_fx: obstacle parts not built: " .. tostring(built)) end
  local function save(rel, image)
    local saved = x:saveImage(rel, image)
    return type(saved) == "table" and saved.path or saved
  end
  local okC, cut = pcall(A.cutIn, x.rom, save)
  if okC and cut then out.cutIn = cut
  else print("gen4_pt_field_fx: cut-in not built: " .. tostring(cut)) end
  local okF, fog = pcall(A.fogLayer, x.rom, save)
  if okF then out.fogLayer = fog
  else print("gen4_pt_field_fx: fog layer not built: " .. tostring(fog)) end
  return out
end

return A
