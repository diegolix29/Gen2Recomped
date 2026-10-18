-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD AND SOULSILVER'S MOVING WATER: the map texture animation.
--
-- Platinum's sea, lakes and waterfalls are PROPS -- `r04_w`, `l_lake`,
-- `wfall` in build_model.narc, scrolled by `bm_anime` (Gen4TexAnim). HGSS
-- draws its water as TERRAIN: every outdoor land chunk carries the water
-- materials itself, and one texture-SRT animation moves all of them.
--
-- THE CARTRIDGE (pokeheartgold, overlay 1):
--
--   AreaDataManager_Load reads the area record into +0x8B0 and, when the u16
--   at +0x8B4 -- the record's +4, which this port had been calling unused --
--   is not 0xFFFF, calls ov01_0220463C(unkCC, that value):
--
--       MapPropAnimation_Init(anim, -1 /* loop forever */, FALSE, FALSE)
--       res = AllocAndReadWholeNarcMemberByIdPair(NARC_a_1_4_0, id)
--
--   and its allocator (ov01_022046A4 / ov01_022046E8) builds the animation
--   object by hand: `funcAnm = NNS_G3dFuncAnmMatNsBtaDefault` and
--   `mapData[i] = i | 0x100` for i < the BTA's own material count. That map
--   is POSITIONAL -- the model's material i plays the animation's entry i,
--   with no name lookup at all.
--
--   Every land chunk's render object then gets it (ov01_02204678, from
--   overlay_01_021F4704.s at both chunk-load sites), except chunks
--   0xD0, 0xD2 and 0xD3 (sub_02054E20's table). It advances one frame per
--   field frame and wraps (MapPropAnimation_AdvanceFrame).
--
-- WHAT IS IN /a/1/4/0, measured: two BTA0s, 360 frames each.
--
--   0 area00_ani  pond_on swave_p pond_edge sea_line02 sea_un sea_on river river_r
--   1 dun18_ani   river river_r sea_line02 sea_un sea_on
--
-- and the 106 area records name 0 (33 records), 1 (10) or 0xFFFF (63).
--
-- WHY POSITIONAL STILL READS AS NAMES ON THIS CARTRIDGE, measured over all 676
-- land chunks: 289 open with exactly area00_ani's eight materials in that
-- order, 127 with dun18_ani's five, and the other 260 carry none of the
-- thirteen names anywhere. The import keeps the cartridge's rule anyway -- it
-- records each chunk's leading material names and the runtime maps entry i to
-- the chunk's material i -- so a chunk that broke the convention would be
-- animated as the DS animates it, not as its names suggest.
--
-- THE BLUE LINE ON THE BEACH IS THIS ANIMATION'S ABSENCE. `swave_p` is the
-- surf washing up the sand: a 32x32 texture whose top seven rows are water and
-- the rest transparent, and its T translate never leaves 0.60..0.80 on the
-- cartridge. Drawn unanimated the translate is 0, which parks those seven
-- rows of water on the sand along every shoreline -- a still blue stripe the
-- DS never shows.

local Gen4Anim = require("src.import.Gen4Anim")
local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")

local M = {}

M.ARCHIVE = "/a/1/4/0"
M.NONE = 0xFFFF
-- sub_02054E20 (asm/unk_02054648.s, _020FC5FC): land chunks never animated
M.SKIP_LAND = { [0xD0] = true, [0xD2] = true, [0xD3] = true }

local function u16(s, at) local a, b = s:byte(at + 1, at + 2) return a and b and a + b * 256 end
local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  return a and d and a + b * 256 + c * 65536 + d * 16777216
end

-- The area record's +4: the /a/1/4/0 member, or nil for 0xFFFF.
function M.areaAnim(record)
  if type(record) ~= "string" or #record < 6 then return nil end
  local id = u16(record, 4)
  if not id or id == M.NONE then return nil end
  return id
end

-- One /a/1/4/0 member -> the record Gen4TexAnim.materials plays.
function M.parse(bytes)
  local parsed = bytes and Gen4Anim.parse(bytes)
  local anim = parsed and parsed.kind == "BTA0" and parsed.animations[1]
  if not anim then return nil end
  local srt = Gen4Anim.textureSrt(bytes, anim)
  if not (srt and srt[1]) then return nil end
  return { name = anim.name, kind = "BTA0", frames = anim.frames, srt = srt }
end

-- A land chunk's material names in the model's own order, the first `n`.
-- Read straight off the material dictionary: the chunk's packed shapes carry
-- material names but not their index, and the index is what the DS maps by.
function M.materialOrder(landBytes, n)
  local land = landBytes and Gen4Maps.land(landBytes)
  local model = land and land.model
  local sections = model and Gen4Nsbmd.sections(model)
  local mdl = sections and sections.MDL0
  if not mdl then return nil end
  local models = Gen4Nsbmd.dictionary(model, mdl + 8)
  local first = models and models.entries[1]
  if not (first and first.offset) then return nil end
  local at = mdl + first.offset
  local matAt = at + (u32(model, at + 8) or 0)
  -- NNSG3dResMat: two u16 dictionary offsets, then the material dictionary
  local mats = Gen4Nsbmd.dictionary(model, matAt + 4)
  if not mats then return nil end
  local out = {}
  for i = 1, math.min(n, #mats.entries) do out[i] = mats.entries[i].name end
  return out
end

-- extractInto(extractor, terrain) -> report | nil, why
--
-- Adds to the terrain stage's own table, so the cache needs nothing new to
-- find it:
--   terrain.texAnims[id]        the /a/1/4/0 records
--   terrain.texAnimLand[land]   each chunk's leading material names
--   terrain.texAnimSkip         the three chunks the cartridge leaves still
--   terrain.maps[m].texAnim     per map, through its area record
function M.extractInto(X, terrain)
  local arc = X:archiveAt(M.ARCHIVE)
  if not arc then return nil, M.ARCHIVE .. " is missing" end
  terrain.texAnims = {}
  local longest = 0
  for id = 0, arc.count - 1 do
    local record = M.parse(arc:get(id))
    if record then
      terrain.texAnims[id] = record
      if #record.srt > longest then longest = #record.srt end
    end
  end
  local areaArc = X:archive("areaData")
  local maps = 0
  for _, rec in pairs(terrain.maps or {}) do
    local raw = areaArc and rec.area and areaArc:get(rec.area)
    local id = M.areaAnim(raw)
    if id and terrain.texAnims[id] then rec.texAnim = id; maps = maps + 1 end
  end
  local land = X:archive("land")
  local chunks = 0
  terrain.texAnimLand = {}
  for m = 0, (land and land.count or 0) - 1 do
    if terrain.chunks and terrain.chunks[m] then
      local order = M.materialOrder(land:get(m), longest)
      if order and order[1] then terrain.texAnimLand[m] = order; chunks = chunks + 1 end
    end
  end
  terrain.texAnimSkip = {}
  for k in pairs(M.SKIP_LAND) do terrain.texAnimSkip[k] = true end
  local n = 0
  for _ in pairs(terrain.texAnims) do n = n + 1 end
  return { animations = n, maps = maps, chunks = chunks }
end

return M
