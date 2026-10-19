-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S FIELD EFFECTS, out of /a/0/7/5 (arc id 75).
--
-- The archive is Black / White's fldeff: 151 members, read by looking and by
-- the names the models carry (scratch_claude/bw_field/tex.txt, sheets s_*.png):
--
--    0-10  BTX0 kusaeff        the grass a step rustles, per grass and season
--   11-18  BTX0 lgrass_ani1    tall grass
--   19-44  BTX0 *_mark_*       footprints / bike tracks
--   45-46  BTX0 ripple         a puddle's ring
--   47  kage                   48  hero_kemu (dust behind a running step)
--   49  sea_ride               the surf mount (a 3D model, turned per facing)
--   50-53  sisen_ef            the "!", "?", note and "..." bubbles
--   54  shibuki01   55  taki_land   56-59  taki_loop (waterfall)
--   60-67  short_grass_sp..wi2  68-71 long_grass_sp..wi (seasons)
--   72-74  freshwater_in/out (a surfer's ripples)   75 bird_shadow
--   76  soil_smoke  77 iwakudaki (Rock Smash)       84 fishing_lure
--   93  mv_hide_tsuchi (DUST CLOUD)  94 mv_hide_kusa (SHAKING GRASS)
--   95  shibuki (RIPPLING WATER)
--   96-150 the animations: 96 hero_kemu, 103 fishing_lure, 104 / 105 / 106
--          the three phenomena (BTP0), 107.. BCA0 / BTA0 / BMA0
--
-- THE EMOTE (ov21 0x21BB4BC loads members {50, 51, 52, 53} from the table at
-- 0x21D9A6C, one per kind). Its update (0x21BB808) is Platinum's bounce --
-- y += v, v from 6 down by 2 until y is back to 0, then 0x1E frames held --
-- but the anchor is the owner's drawn position plus (0, 22 + y, 0) turned by
-- the CAMERA's rotation (0x21BB7B4 builds the look-at and multiplies), so the
-- lift is straight up the screen, not up the world. The bubble model spans
-- 0..16 up and -8..8 across (posScale 4, bounds 0..4 / -2..2). Sound per kind
-- (0x21BB778): 0x678, 0x730, 0x731, none.
--
-- What is written:
--   gen4_emotes          exclamation / question / note / ellipsis, raw RGBA
--                        (the same record shape Gen4Emotes writes, so the
--                        renderer's bubble path reads it unchanged)
--   gen5_field_effects   every billboard picture the field draws, raw RGBA by
--                        "<member>/<texture>", and the BTP0 frame tables
--   gen4_models.sets.fldeff  the 3D models (sea_ride), packed as Platinum's
--                        fldeff set is, when an image writer is handed in

local Narc = require("src.import.NarcArchive")
local Nsbmd = require("src.import.Gen4Nsbmd")
local Models = require("src.import.Gen4Models")

local E = {}

E.ARCHIVE = "/a/0/7/5"
E.EMOTES = { exclamation = 50, question = 51, note = 52, ellipsis = 53 }
E.EMOTE_SOUND = { exclamation = 0x678, question = 0x730, note = 0x731 }
-- the emote's lift in world units, straight up the screen (0x21BB862: 0x16)
E.EMOTE_LIFT = 22

-- members whose pictures the field draws as billboards
E.BILLBOARDS = { 47, 48, 50, 51, 52, 53, 54, 72, 73, 74, 75, 76, 77, 84, 93, 94, 95,
                 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 45, 46 }
-- members packed as 3D models
E.MODELS = { 49 }
-- the texture-pattern animations by member
E.PATTERNS = { 96, 103, 104, 105, 106 }

local function bytesOf(arc, m)
  local b = arc and m >= 0 and m < arc.count and arc:get(m)
  if not b then return nil end
  local ok, Lz = pcall(require, "src.import.Gen5Lz")
  if ok and Lz.isCompressed(b) then
    local okD, d = pcall(Lz.decompress, b)
    if okD and d then b = d end
  end
  return b
end

-- the TEX0 of a BMD0 or BTX0 member
local function texturesOf(b)
  if not b then return nil end
  local magic = b:sub(1, 4)
  if magic == "BTX0" then return Models.parse(b) end
  if magic ~= "BMD0" then return nil end
  local sections = Nsbmd.sections(b)
  return sections and sections.TEX0 and Models.parse(b, sections.TEX0) or nil
end

-- the palette a texture wears: the one named after it ("<name>_pl" or its
-- own name, the archive's habit), else the only one
local function paletteFor(parsed, texName)
  local base = texName:gsub("%.%d+$", "")
  local want = { texName .. "_pl", texName, base .. "_pl", base }
  for _, w in ipairs(want) do
    for i, p in ipairs(parsed.palettes or {}) do if p.name == w then return i end end
  end
  return 1
end

function E.emotes(arc)
  local out = {}
  for key, member in pairs(E.EMOTES) do
    local b = bytesOf(arc, member)
    local parsed = texturesOf(b)
    local t = parsed and parsed.textures and parsed.textures[1]
    if t and t.name == "sisen_ef" then
      local ok, image = pcall(Models.decode, parsed, b, 1, paletteFor(parsed, t.name))
      if ok and image then
        out[key] = { width = image.width, height = image.height, rgba = image.rgba,
                     member = member, texture = t.name, sound = E.EMOTE_SOUND[key] }
      end
    end
  end
  if not out.exclamation then return nil, "member 50 (sisen_ef) would not decode" end
  out.source = "ROM:/a/0/7/5 (Black / White)"
  out.lift = E.EMOTE_LIFT
  return out
end

-- texture pictures as raw RGBA: { ["94/mv_kusa.1"] = { width, height, rgba } }
function E.billboards(arc)
  local out, n = {}, 0
  for _, member in ipairs(E.BILLBOARDS) do
    local b = bytesOf(arc, member)
    local parsed = texturesOf(b)
    for i, t in ipairs(parsed and parsed.textures or {}) do
      local ok, image = pcall(Models.decode, parsed, b, i, paletteFor(parsed, t.name))
      if ok and image then
        out[member .. "/" .. t.name] = { width = image.width, height = image.height, rgba = image.rgba }
        n = n + 1
      end
    end
  end
  return out, n
end

-- the BTP0 tables: { [animName] = { frames, targets = { [material] = { {frame, texture}, ... } } } }
function E.patterns(arc)
  local Anim = require("src.import.Gen4Anim")
  local out = {}
  for _, member in ipairs(E.PATTERNS) do
    local b = bytesOf(arc, member)
    local okP, parsed = pcall(Anim.parse, b)
    for _, an in ipairs(okP and parsed and parsed.animations or {}) do
      local okT, pat = pcall(Anim.texturePattern, b, an)
      if okT and pat then
        local rec = { frames = an.frames, member = member, targets = {} }
        for _, tg in ipairs(pat.targets or {}) do
          local keys = {}
          for _, k in ipairs(tg.keys or {}) do
            keys[#keys + 1] = { frame = k.frame, texture = pat.textures[(k.texture or 0) + 1] }
          end
          rec.targets[tg.name] = keys
        end
        out[an.name] = rec
      end
    end
  end
  return out
end

-- the 3D models, packed as RomExtractorGen4:extractModels packs its fldeff
-- set (byMember, own TEX0 pictures). `saveImage(rel, image, extra)` -> entry.
function E.modelSet(arc, saveImage)
  local Pack = require("src.import.Gen4ModelPack")
  local set = { label = "field-effect models", path = E.ARCHIVE, models = {}, animations = {}, byMember = {} }
  for _, member in ipairs(E.MODELS) do
    local b = bytesOf(arc, member)
    local parsed = b and b:sub(1, 4) == "BMD0" and Nsbmd.parse(b)
    local textures = texturesOf(b)
    for _, model in ipairs(parsed and parsed.models or {}) do
      local packed = Pack.pack(model)
      packed.member, packed.animations = member, {}
      local written = {}
      for _, shape in ipairs(packed.shapes) do
        local name = shape.texture
        if name and textures and saveImage then
          if written[name] == nil then
            written[name] = false
            local index, palette
            for i, t in ipairs(textures.textures) do if t.name == name then index = i end end
            for i, p in ipairs(textures.palettes or {}) do if p.name == shape.palette then palette = i end end
            local ok, image = pcall(Models.decode, textures, b, index or 1, palette or 1)
            local saved = ok and image and index and saveImage(
              ("models/bw_fldeff/%s/%s"):format(model.name, name:gsub("[^%w_%-]", "_")),
              image, { texture = name, palette = shape.palette })
            written[name] = saved and saved.path or false
          end
          shape.image = written[name] or nil
        end
      end
      set.models[#set.models + 1] = packed
      if set.byMember[member] == nil then set.byMember[member] = #set.models end
    end
  end
  return set
end

-- build(rom, saveImage) -> { emotes, effects, modelSet } (any may be nil)
function E.build(rom, saveImage)
  local bytes = rom and rom:read(E.ARCHIVE)
  local arc = bytes and Narc.parse(bytes)
  if not arc then return nil, "no " .. E.ARCHIVE end
  local emotes = E.emotes(arc)
  local pictures, n = E.billboards(arc)
  local effects = { source = "ROM:/a/0/7/5", textures = pictures, count = n, patterns = E.patterns(arc) }
  local okM, set = pcall(E.modelSet, arc, saveImage)
  return { emotes = emotes, effects = effects, modelSet = okM and set or nil }
end

return E
