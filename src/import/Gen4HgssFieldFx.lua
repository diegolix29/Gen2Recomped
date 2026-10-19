-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S FIELD-MOVE OBSTACLE ANIMATIONS: /a/1/3/4.
--
-- ScrCmd_560 <kind, var> (scrcmd_c.c) starts ov02_0224E074, whose table
-- ov02_02253A1C builds a Field3dObject task out of NARC_a_1_3_4 (narc 0x86)
-- through ov02_0224D0C8(model, firstAnim, animCount) -- the model, then that
-- many consecutive animation members, all advanced one frame a field frame
-- (ov02_0224D178, Field3dModelAnimation_FrameAdvanceAndCheck) until every one
-- has ended:
--
--   kind 0 / 3  Cut          ov02_0224D1E4  model 3,  anims 0..2 (BCA, BMA, BTA)  SEQ_SE_DP_FW015
--   kind 1 / 2  Rock Smash   ov02_0224D310  model 8,  anims 4..7 (BCA, BMA, BTP, BTA)  SEQ_SE_DP_FW088
--   kind 4 / 5  Headbutt     ov02_0224D9C0  model 19, anims 17..18 (BCA, BMA)  SEQ_SE_GS_ZUTUKI
--
-- (3, 2 and 5 are the same objects when the walking Pokemon does the move.)
-- Each is placed on the facing tile's centre at the player's height
-- (ov02_0224D044). Packed the way Gen4HgssLegendArt packs /a/1/7/4: the model
-- through Gen4ModelPack with its own textures, the joint animation as packed
-- tracks, the texture and material animations as Gen4TexAnim records.

local A = { PATH = "/a/1/3/4" }

A.PARTS = {
  cut       = { model = 3,  anims = { 0, 1, 2 } },
  rockSmash = { model = 8,  anims = { 4, 5, 6, 7 } },
  headbutt  = { model = 19, anims = { 17, 18 } },
}

-- opts (Platinum's Gen4PtFieldFx): { path, parts, source } in place of /a/1/3/4's
function A.build(x, opts)
  opts = opts or {}
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local arc = assert(Narc.parse(assert(x.rom:read(opts.path or A.PATH))))
  local function member(i)
    local b = assert(arc:get(i))
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = { source = opts.source or ("ROM:" .. A.PATH .. " (pokeheartgold ov02_0224D0C8 / ScrCmd_560)"), parts = {} }
  local written = {}

  local function textureImage(prefix, tex, bytes, name, paletteName)
    local key = prefix .. name .. "/" .. tostring(paletteName)
    if written[key] ~= nil then return written[key] end
    local ti, pi
    for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
    for k, p in ipairs(tex.palettes) do if p.name == paletteName then pi = k end end
    if not ti then written[key] = false return false end
    local image = Models.decode(tex, bytes, ti, pi or 1)
    local saved = image and x:saveImage(("field_fx/%s%s_%d"):format(prefix, name, pi or 1), image)
    written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
    return written[key]
  end

  for name, spec in pairs(opts.parts or A.PARTS) do
    local bytes = member(spec.model)
    local parsed = assert(Nsbmd.parse(bytes))
    local packed = Pack.pack(assert(parsed.models[1]))
    local texAt = bytes:find("TEX0", 1, true)
    local tex = texAt and Models.parse(bytes, texAt - 1)
    local prefix = ("m%d_"):format(spec.model)
    for _, shape in ipairs(packed.shapes) do
      if shape.texture and tex then
        shape.image = textureImage(prefix, tex, bytes, shape.texture, shape.palette) or nil
      end
    end
    local part = { model = packed, records = {}, frames = 0 }
    for _, m in ipairs(spec.anims) do
      local data = member(m)
      local parsed2 = Anim.parse(data)
      local animation = parsed2 and parsed2.animations and parsed2.animations[1]
      if animation then
        local frames = tonumber(animation.frames) or 0
        if frames > part.frames then part.frames = frames end
        local kind = parsed2.kind
        if kind == "BCA0" then
          local motion = { frames = frames, tracks = {} }
          for _, joint in ipairs(Anim.jointMatrices(data, animation) or {}) do
            motion.tracks[joint.index] = Anim.packTrack(joint.track)
          end
          part.motion = motion
        elseif kind == "BTA0" then
          part.records[#part.records + 1] = { kind = "BTA0", frames = frames, srt = Anim.textureSrt(data, animation) }
        elseif kind == "BTP0" then
          local pattern = Anim.texturePattern(data, animation)
          part.records[#part.records + 1] = { kind = "BTP0", frames = frames, pattern = pattern }
          packed.patternImages = packed.patternImages or {}
          for i, texName in ipairs((pattern and pattern.textures) or {}) do
            if packed.patternImages[texName] == nil and tex then
              local pal = (pattern.palettes or {})[i] or (pattern.palettes or {})[1]
              packed.patternImages[texName] = textureImage(prefix, tex, bytes, texName, pal)
            end
          end
        elseif kind == "BMA0" then
          part.records[#part.records + 1] = { kind = "BMA0", frames = frames, colour = Anim.materialColour(data, animation) }
        end
      end
    end
    out.parts[name] = part
  end
  return out
end

return A
