-- BLACK AND WHITE'S SPECIAL-TRAINER AND LEGEND CUT-INS (ov73 / ov74 / ov21).
--
-- Effects 10-30 and 32-34 are ov73 stubs into one program (0x021F5398): the
-- two white flashes, then ov21 0x021C1DCC with ov74's record for the effect
-- -- (scene, a, b, c, flag), 20 bytes each at 0x021F54F0:
--
--   effects 10-22  rival_ci  (/a/1/1/7 scene 13)  Cheren .. Drayden
--   effects 23-27  shiten    (scene 14)           the Elite Four, Alder
--   effect  28-29             (scene 16)          N, Ghetsis
--   effect  30     plasma_ci01 (scene 15)         Team Plasma
--   effect  32     ci_smr    (scene 25)           Reshiram / Zekrom / Kyurem
--   effect  33     ci_kami   (scene 23)           Tornadus / Thundurus / Landorus
--   effect  34     san_ci    (scene 24)           the Musketeers, Keldeo
--
-- A scene (/a/1/1/7, 36 bytes): u16 SPA (particles, 0xFFFF none), three u16,
-- then two models (/a/1/1/5 members, 0xFFFF none) and four animations for
-- each (BCA / BMA / BTA / BVA, by magic).
--
-- THE PICTURES SWAPPED IN (ov21 0x021C2D68): the face texture "trwb_face001"
-- gets /a/1/8/0 member a (a 128 x 128 RGCN) in palette member b; the
-- player's "trwb_hero_ine" gets member 0 or 1 (by gender) in 22 or 23;
-- "name_up" is message c of text bank 176 (Cheren .. Ghetsis), "name_down"
-- the player's name, both in font 23 at x = 60 - width (0x021C2F84).
--
-- THE VIEW: one unit two pixels at z = 0 -- +-64 x +-48 -- through the
-- field's 19.96-degree half-FOV. The scenes' own full-screen planes say so:
-- rival_ci's "white" is +-80 x +-48 at z = 32 and shiten's "black" +-83 x
-- +-61 at z = -10, each just covering the screen at its depth.
--
-- THE PARTICLES: a scene's SPA (src/import/Gen5Particles.lua) runs its
-- emitter 0 after record word 2 frames and, when the file has two, emitter 1
-- after word 3 (ov21 0x021C21B8, from +92 / +94); each sits 64 units in front
-- of the scene's origin (the callback 0x021C24BC). Words 6 and 7 hold back
-- the two models' animations the same way (+96 / +98).

local M = {}

M.SCENE_PATH = "/a/1/1/5"
M.RECORD_PATH = "/a/1/1/7"
M.FACE_PATH = "/a/1/8/0"
M.NAME_BANK = 176
M.FACES = 22

-- ov74 0x021F54F0: per effect, {scene, a, b, c, flag}
M.RECORDS = {}
do
  local t = {
    { 13, 2, 24, 1, 1 }, { 13, 3, 25, 2, 1 }, { 13, 4, 26, 3, 1 }, { 13, 5, 27, 4, 1 },
    { 13, 6, 28, 5, 1 }, { 13, 7, 29, 6, 1 }, { 13, 8, 30, 7, 1 }, { 13, 9, 31, 8, 1 },
    { 13, 10, 32, 9, 1 }, { 13, 11, 33, 10, 1 }, { 13, 12, 34, 11, 1 }, { 13, 13, 35, 12, 1 },
    { 13, 14, 36, 13, 1 }, { 14, 15, 37, 14, 1 }, { 14, 16, 38, 15, 1 }, { 14, 17, 39, 16, 1 },
    { 14, 18, 40, 17, 1 }, { 14, 19, 41, 18, 1 }, { 16, 20, 42, 19, 2 }, { 16, 21, 43, 20, 2 },
    { 15, 0, 0, 0, 0 },
  }
  for i, r in ipairs(t) do M.RECORDS[9 + i] = r end
  M.RECORDS[32] = { 25, 0, 0, 0, 0 }
  M.RECORDS[33] = { 23, 0, 0, 0, 0 }
  M.RECORDS[34] = { 24, 0, 0, 0, 0 }
end

-- arm9 0x0209FEE4 (class in bits 0-6) with ov21 0x021DB7F6 (the effect by
-- its row): the trainer classes that bring their own cut-in
M.CLASS_EFFECT = { [37] = 10, [38] = 11, [10] = 12, [12] = 13, [11] = 14, [19] = 15, [20] = 16,
                   [21] = 17, [22] = 18, [23] = 19, [54] = 20, [55] = 21, [56] = 22,
                   [78] = 23, [80] = 24, [79] = 25, [81] = 26, [89] = 27, [40] = 5,
                   [47] = 28, [101] = 28, [82] = 29, [39] = 30, [77] = 30, [100] = 5 }

M.ROLE = { trwb_face001 = "face", trwb_hero_ine = "hero", name_up = "name", name_down = "heroName" }

local function u16(s, at) return s:byte(at + 1) + s:byte(at + 2) * 256 end

-- one model of a scene: its frames baked flat, its shapes with what they wear
local function bakeModel(x, member, modelIndex, anims, tag, saved)
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Anim = require("src.import.Gen4Anim")
  local Models = require("src.import.Gen4Models")
  local E = require("src.import.Gen5EncounterEffects")
  local bytes = member(modelIndex)
  local md = Nsbmd.parse(bytes).models[1]
  local at = bytes:find("TEX0", 1, true)
  local tex = at and Models.parse(bytes, at - 1)
  local bca, bma, bta, bva
  for _, a in ipairs(anims) do
    local data = member(a)
    local magic = data and data:sub(1, 4)
    if magic == "BCA0" then bca = data elseif magic == "BMA0" then bma = data
    elseif magic == "BTA0" then bta = data elseif magic == "BVA0" then bva = data end
  end
  local function textureOf(shape)
    local mat = md.materials[(shape.material or 0) + 1]
    for k, t in ipairs(tex and tex.textures or {}) do
      if mat and t.name == mat.texture then return k, t, mat end
    end
    return nil, nil, mat
  end
  local baked = E.bake(bytes, bca, { flat = true, sizeOf = function(shape)
    local _, t = textureOf(shape)
    return t and t.width or 1, t and t.height or 1
  end, bindPose = bca == nil })
  if not baked then return nil end
  local nodeOf = {}
  for _, d in ipairs(md.draws or {}) do if d.shape then nodeOf[d.shape] = d.node end end
  local shapes = {}
  for si, sh in ipairs(baked.shapes) do
    local k, t, mat = textureOf(sh.shape)
    local entry = { first = sh.first, count = sh.count, node = nodeOf[si - 1],
                    material = mat and mat.name, texture = t and t.name,
                    alpha = mat and mat.alpha or 31,
                    role = t and M.ROLE[t.name] or nil }
    -- the material's own colour, when its vertex colour is its diffuse
    local da = mat and mat.diffAmb or 0
    if math.floor(da / 32768) % 2 == 1 then entry.diffuse = da % 32768 end
    if k and not entry.role then
      local key = tag .. "_" .. t.name
      if saved[key] == nil then
        local pal = 1
        for pk, pl in ipairs(tex.palettes or {}) do if mat and pl.name == mat.palette then pal = pk end end
        local image = Models.decode(tex, bytes, k, pal)
        local s = image and x:saveImage(("battle5/encounter/%s"):format(key:gsub("[^%w_%-]", "_")), image)
        saved[key] = s and s.path or false
      end
      entry.image = saved[key] or nil
    end
    shapes[si] = entry
  end
  local out = { name = md.name, frames = baked.frames, shapes = shapes,
                uvHex = E.pack(baked.uv, E.UV_SCALE), trisHex = E.pack(baked.tris, 1), posHex = {} }
  for f, list in ipairs(baked.pos) do out.posHex[f] = E.pack(list, E.POS_SCALE) end
  -- material colour / alpha, by material name
  if bma then
    local info = Anim.parse(bma)
    local list = info and info.animations[1] and Anim.materialColour(bma, info.animations[1])
    out.materialAnim = {}
    for _, m in ipairs(list or {}) do out.materialAnim[m.name] = { diffuse = m.diffuse, alpha = m.alpha } end
    out.materialFrames = info and info.animations[1] and info.animations[1].frames
  end
  -- texture scrolling, by material name
  if bta then
    local info = Anim.parse(bta)
    local list = info and info.animations[1] and Anim.textureSrt(bta, info.animations[1])
    out.textureAnim = {}
    for _, m in ipairs(list or {}) do
      out.textureAnim[m.name] = { translateS = m.translateS, translateT = m.translateT,
                                  scaleS = m.scaleS, scaleT = m.scaleT }
    end
  end
  -- node visibility, frame-major bits as hex
  if bva then
    local info = Anim.parse(bva)
    local v = info and info.animations[1] and Anim.visibility(bva, info.animations[1])
    if v then
      local hex = {}
      for i = 1, #v.bits do hex[i] = ("%02x"):format(v.bits:byte(i)) end
      out.visibility = { frames = v.frames, targets = v.targets, bits = table.concat(hex) }
    end
  end
  return out
end

-- the faces of /a/1/8/0: member n in palette n + 22, a 16 x 16 grid of tiles
function M.face(arc, n)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local function member(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local sheet = member(n) and G.tiles(member(n))
  local pal = member(n + M.FACES) and G.palette(member(n + M.FACES))
  if not (sheet and pal) then return nil end
  local grid = {}
  for t = 0, 255 do grid[t + 1] = { tile = t, palette = 0 } end
  return G.compose({ width = 128, height = 128, cells = grid }, sheet, pal)
end

function M.build(x)
  local Narc = require("src.import.NarcArchive")
  local Lz = require("src.import.Gen5Lz")
  local arc = Narc.parse(x.rom:read(M.SCENE_PATH))
  local recs = Narc.parse(x.rom:read(M.RECORD_PATH))
  local faces = Narc.parse(x.rom:read(M.FACE_PATH))
  if not (arc and recs) then return nil end
  local function member(i)
    if not i or i == 0xFFFF then return nil end
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local out = { scenes = {}, effects = {}, faces = {}, names = {}, classEffect = M.CLASS_EFFECT,
                source = "ROM:/a/1/1/7 + /a/1/1/5 (ov74 0x021F54F0), faces /a/1/8/0, names bank 176" }
  for n = 0, M.FACES - 1 do
    local img = faces and M.face(faces, n)
    local s = img and x:saveImage(("battle5/encounter/face_%02d"):format(n), img)
    out.faces[n] = s and s.path or nil
  end
  local bank = x:bank(M.NAME_BANK) or {}
  for i = 1, 20 do out.names[i] = bank[i] end
  local saved = {}
  for effect, r in pairs(M.RECORDS) do
    local sceneId = r[1]
    if not out.scenes[sceneId] then
      local rec = recs:get(sceneId)
      local models = {}
      for slot = 0, 1 do
        local mi = u16(rec, 8 + slot * 2)
        if mi ~= 0xFFFF then
          local anims = {}
          for k = 0, 3 do
            local a = u16(rec, 16 + slot * 8 + k * 2)
            if a ~= 0xFFFF then anims[#anims + 1] = a end
          end
          local ok, m = pcall(bakeModel, x, member, mi, anims, ("scene%d_%d"):format(sceneId, slot), saved)
          if ok and m then models[#models + 1] = m
          else print(("Gen5EncounterCutIns: scene %d model %d: %s"):format(sceneId, mi, tostring(m))) end
        end
      end
      local frames = 0
      for _, m in ipairs(models) do frames = math.max(frames, m.frames or 0, m.materialFrames or 0) end
      local scene = { id = sceneId, models = models, frames = frames,
                      modelDelays = { u16(rec, 12), u16(rec, 14) } }
      local spaIndex = u16(rec, 0)
      if spaIndex ~= 0xFFFF then
        local ok, spa = pcall(require("src.import.Gen5Particles").parse, member(spaIndex))
        if ok and spa then
          local textures = {}
          for k, t in ipairs(spa.textures) do
            local sv = t.image and x:saveImage(("battle5/encounter/spa%d_%d"):format(spaIndex, k - 1), t.image)
            textures[k - 1] = sv and sv.path or nil
            t.image = nil
          end
          scene.particles = { member = spaIndex, emitters = spa.emitters, textures = textures,
                              delays = { u16(rec, 4), u16(rec, 6) }, z = 64 }
        else
          print(("Gen5EncounterCutIns: SPA %d: %s"):format(spaIndex, tostring(spa)))
        end
      end
      out.scenes[sceneId] = scene
    end
    out.effects[effect] = { scene = sceneId, face = r[2], name = r[4] }
  end
  return out
end

return M
