-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S GYM GIMMICK MODELS, the art the gym overlays load into the
-- field's 3D object system (ov21 0x21BE760 / 0x21BE310: a resource list of
-- <arc, member> pairs, then units of <model, animations...>). Written as the
-- cache module `gen5_gym_fx`; drawn by src/world/Gen5GymFx.lua.
--
-- READ FROM CODE (Black's overlays; each overlay's resource table, 12 bytes
-- an entry <u32 arc, u32 member, u32 0>, and unit table, 16 bytes a unit
-- <u16 model res, u16, u32, u32 anim list, u32 anim count>):
--
--   arc 122  Striaton  ov42  9 switches (m0/m3/m6 + BCA, BTA) and 3 curtains
--                            (m9/m11/m13 + BCA m10/m12/m14)
--   arc 110  Nacrene   ov40  the bookcase (m0 + BCA m1), via 0x21BE310
--   arc 135  Castelia  ov38  the honey walls (m3 + m12/m13), the switches
--                            (m0, m1 + BCA/BTA), the wax (m26, m27), ...
--   arc 107  Nimbasa   ov39  the coaster car (m0: BTA m1, eight ride BCAs
--                            m11..m18), the track switches (m2 + BTAs
--                            m3..m10), the four tracks (m19..m22 + BTAs)
--   arc 138  Driftveil ov43  the lifts (m0 + BTA m3/m4), m1, m2
--   arc 121  Mistralton ov41 the cannons (m0 + BCA/BMA m1..m8, one pair a
--                            firing direction)
--   arc 162  Opelucid  ov46  the dragons (m0 + eight BCAs m4..m11), their
--                            switches (m1, m2 + BCAs), lamps (m16 + BTP m17),
--                            the room's glow (m3 + BTA m18)
--
-- Every BMD0 member of those archives is packed (Gen4ModelPack, textures
-- from its own TEX0), every BCA0 / BTA0 / BTP0 / BMA0 member read as the
-- record Gen4TexAnim / Gen4Anim play. Out:
--   { arcs = { [arc] = { models = { [member] = packed },
--                        anims  = { [member] = record } } } }
-- A record: { kind, frames, tracks (BCA0, by joint) | srt | pattern | colour }.

local A = {}

A.ARCS = { 122, 110, 135, 107, 138, 121, 162 }

local function arcPath(n)
  return ("/a/%d/%d/%d"):format(math.floor(n / 100), math.floor(n / 10) % 10, n % 10)
end
A.arcPath = arcPath

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Models = require("src.import.Gen4Models")
  local Anim = require("src.import.Gen4Anim")
  local Pack = require("src.import.Gen4ModelPack")
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local out = { source = "ROM: Black/White gym overlays' 3D object resources (ov38-ov46 tables)", arcs = {} }
  for _, n in ipairs(A.ARCS) do
    local okA, err = pcall(function()
      local raw = x.rom:read(arcPath(n))
      local arc = raw and Narc.parse(raw)
      if not arc then return end
      local rec = { models = {}, anims = {}, path = arcPath(n) }
      local textures = {}   -- member -> { tex, bytes }
      local function member(i)
        local b = arc:get(i)
        if b and G.isCompressed(b) then b = G.decompress(b) end
        return b
      end
      local written = {}
      local function image(m, tex, bytes, name, pal)
        local key = m .. "/" .. name .. "/" .. tostring(pal)
        if written[key] ~= nil then return written[key] end
        local ti, pi
        for k, t in ipairs(tex.textures) do if t.name == name then ti = k end end
        for k, p in ipairs(tex.palettes or {}) do if p.name == pal then pi = k end end
        if not ti then written[key] = false return false end
        local pic = Models.decode(tex, bytes, ti, pi or 1)
        local saved = pic and x:saveImage(("gym5/a%d/m%d_%s_%d"):format(n, m, name:gsub("[^%w_%-]", "_"), pi or 1), pic,
                                          { texture = name, palette = pal })
        written[key] = saved and (type(saved) == "table" and saved.path or saved) or false
        return written[key]
      end
      -- the models
      for i = 0, arc.count - 1 do
        local bytes = member(i)
        if bytes and bytes:sub(1, 4) == "BMD0" then
          local okM, errM = pcall(function()
            local parsed = Nsbmd.parse(bytes)
            local model = parsed and parsed.models and parsed.models[1]
            local packed = model and Pack.pack(model)
            if not packed then return end
            local at = bytes:find("TEX0", 1, true)
            local tex = at and Models.parse(bytes, at - 1)
            if tex then textures[i] = { tex = tex, bytes = bytes } end
            for _, shape in ipairs(packed.shapes) do
              if shape.texture and tex then shape.image = image(i, tex, bytes, shape.texture, shape.palette) or nil end
            end
            packed.member, packed.name = i, model.name
            rec.models[i] = packed
          end)
          if not okM then rec.failed = rec.failed or {}; rec.failed[i] = tostring(errM) end
        end
      end
      -- the animations
      for i = 0, arc.count - 1 do
        local bytes = member(i)
        local magic = bytes and bytes:sub(1, 4)
        if magic == "BCA0" or magic == "BTA0" or magic == "BTP0" or magic == "BMA0" then
          local okN, errN = pcall(function()
            local parsed = Anim.parse(bytes)
            local animation = parsed and parsed.animations and parsed.animations[1]
            if not animation then return end
            local frames = tonumber(animation.frames) or 0
            local r = { kind = parsed.kind or magic, frames = frames, member = i }
            if r.kind == "BCA0" then
              r.tracks = {}
              for _, joint in ipairs(Anim.jointMatrices(bytes, animation) or {}) do
                r.tracks[joint.index] = Anim.packTrack(joint.track)
              end
            elseif r.kind == "BTA0" then
              r.srt = Anim.textureSrt(bytes, animation)
            elseif r.kind == "BTP0" then
              r.pattern = Anim.texturePattern(bytes, animation)
              -- its pictures, from whichever model of the archive holds them
              r.images = {}
              for k, texName in ipairs((r.pattern and r.pattern.textures) or {}) do
                if r.images[texName] == nil then
                  local pal = (r.pattern.palettes or {})[k] or (r.pattern.palettes or {})[1]
                  for m, t in pairs(textures) do
                    local got = image(m, t.tex, t.bytes, texName, pal)
                    if got then r.images[texName] = got break end
                  end
                end
              end
            elseif r.kind == "BMA0" then
              r.colour = Anim.materialColour(bytes, animation)
            end
            rec.anims[i] = r
          end)
          if not okN then rec.failed = rec.failed or {}; rec.failed[i] = tostring(errN) end
        end
      end
      out.arcs[n] = rec
    end)
    if not okA then out.failed = out.failed or {}; out.failed[n] = tostring(err) end
  end
  return out
end

return A
