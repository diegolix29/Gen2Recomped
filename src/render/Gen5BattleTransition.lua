-- BLACK AND WHITE'S INTO-BATTLE TRANSITIONS (ov21 0x021CF498 and overlay 76).
--
-- WHICH ONE: ov21 0x021CF5D8 for a wild battle, 0x021CF748 for a trainer.
--
--   wild    Victini (494) and Volcarona (637)          31  ee_symbol
--           Zoroark (571)                              35  ee_zoroark
--           Reshiram / Zekrom / Kyurem                 32  (3D cut-in, ov73)
--           Tornadus / Thundurus / Landorus            33  (3D cut-in, ov73)
--           the Musketeers and Keldeo (638-640, 647)   34  (3D cut-in, ov73)
--           a scripted "symbol" encounter (kind 1)     31  ee_symbol
--           on water (attribute flag 0x02)              2  (2D, ov78)
--           grass (0x021AB2BC)                         0  ee_yasei1, 1 with the call's flag
--           behaviour 0x1C                             0  ee_yasei1
--           sand (0x0B / 0x0C / 0x23)                  4  sand_ci (3D scene 22)
--           anything else -- a cave floor              3  cave_ci (3D scene 21)
--   trainer the special classes (0x021DB7F6)       10-29  (3D cut-ins, ov73)
--           on water                                   6  ee_trmizu
--           sand                                       8  (2D, ov81)
--           otherwise                                  5  ee_trnor (7 when 0x020140D8 says no)
--
-- PLAYED HERE, exactly: the six ee_* effects (src/import/Gen5EncounterEffects
-- has the model, the camera and the program) and the mesh wipes 2, 7, 8, 9
-- and 36 (src/render/Gen5MeshWipes.lua), and the ov73 scenes cave_ci and
-- sand_ci (effects 3 and 4). The 3D cut-ins are not reproduced yet; each plays the ee_* effect of its side (ee_symbol for the
-- legends, ee_yasei1 wild, ee_trnor trainer) rather than the Game Boy wipe,
-- and says so in `self.stand`.
--
-- Which ordinary trainers take 7 rather than 5 is a byte of the field's
-- location record (0x020140D8 reads +6 of fieldsys+12) not yet identified;
-- they all take 5 here.
--
-- TIME is the field's 30 Hz: one tick every other 60 Hz update, as
-- Gen4BattleTransition counts it. The brightness unit (arm9 0x0204E720) moves
-- K = 2 levels a tick (0x0204E6F4(2) at boot), and with a wait of w it moves
-- once every floor(w / K) + 1 ticks.

local M = {}
M.__index = M

local floor, max, min = math.floor, math.max, math.min

M.WILD_SPECIES = { [494] = 31, [637] = 31, [571] = 35, [643] = 32, [644] = 32, [646] = 32,
                   [641] = 33, [642] = 33, [645] = 33, [638] = 34, [639] = 34, [640] = 34,
                   [647] = 34 }
M.NAMES = { [0] = "ee_yasei1", [1] = "ee_yasei2", [5] = "ee_trnor", [6] = "ee_trmizu",
            [31] = "ee_symbol", [35] = "ee_zoroark" }
M.SAND = { [0x0B] = true, [0x0C] = true, [0x23] = true }
M.K = 2

-- effectFor(ctx) -> the ROM's effect id; ctx: trainer, species, symbol,
-- water, behaviour, grass, darkGrass
function M.effectFor(ctx)
  ctx = ctx or {}
  if ctx.trainer then
    -- the classes that bring their own cut-in come first (0x021CF748)
    local special = ctx.trainerClass and require("src.import.Gen5EncounterCutIns").CLASS_EFFECT[ctx.trainerClass]
    if special then return special end
    if ctx.water then return 6 end
    if ctx.behaviour and M.SAND[ctx.behaviour] then return 8 end
    return 5
  end
  local s = tonumber(ctx.species)
  if s and M.WILD_SPECIES[s] then return M.WILD_SPECIES[s] end
  if ctx.symbol then return 31 end
  if ctx.water then return 2 end
  if ctx.grass then return ctx.darkGrass and 1 or 0 end
  if ctx.behaviour == 0x1C then return 0 end
  if ctx.behaviour and M.SAND[ctx.behaviour] then return 4 end
  return 3
end

-- the effect this build plays for a ROM id
function M.played(id, trainer)
  if M.NAMES[id] then return M.NAMES[id], true end
  if require("src.render.Gen5MeshWipes").handles(id) then return "mesh_" .. id, true end
  if (id >= 10 and id <= 30) or (id >= 32 and id <= 34) then return "cutin_" .. id, true end
  if id == 3 then return "cave_ci", true end
  if id == 4 then return "sand_ci", true end
  if id >= 31 and id <= 34 then return "ee_symbol", false end
  if trainer or (id >= 5 and id <= 29) then return "ee_trnor", false end
  return "ee_yasei1", false
end

-- What the overworld knows that the transition's opts do not carry: the tile
-- under the player and whether they are surfing.
local function fieldContext(game, opts)
  local ctx = { trainer = opts.trainer, species = opts.species, symbol = opts.legendary,
                trainerClass = tonumber(opts.trainerClass), playerGender = opts.playerGender }
  local state = game and game.stack and game.stack.top and game.stack:top()
  local map, p = state and state.map, state and state.player
  if map and p then
    local Rules = require("src.world.Gen5FieldRules")
    local b = Rules.behaviour(map, p.cellX, p.cellY)
    ctx.behaviour = b
    ctx.grass = b ~= nil and Rules.GRASS[b] or false
    ctx.darkGrass = b ~= nil and Rules.DARK_GRASS[b] or false
    ctx.water = p.surfing and true or false
  end
  return ctx
end

-- ---------------------------------------------------------------------------
-- The brightness unit
-- ---------------------------------------------------------------------------

local function fade(F, from, to, wait)
  F.level, F.target, F.dir = from, to, to >= from and 1 or -1
  if wait >= 0 then F.step, F.reload = M.K, floor(wait / M.K) else F.step, F.reload = (-wait + 1) * M.K, 0 end
  F.count = F.reload
end

local function fadeTick(F)
  if F.level == F.target then return end
  if F.count > 0 then F.count = F.count - 1 return end
  F.count = F.reload
  F.level = F.level + F.dir * F.step
  if (F.dir > 0 and F.level > F.target) or (F.dir < 0 and F.level < F.target) then F.level = F.target end
end

local function fadeDone(F) return F.level == F.target end

-- ---------------------------------------------------------------------------
-- The object
-- ---------------------------------------------------------------------------

function M.new(game, onDone, opts)
  local self = setmetatable({}, M)
  self.game, self.onDone, self.opts = game, onDone, opts or {}
  self.ctx = fieldContext(game, self.opts)
  self.effect = M.effectFor(self.ctx)
  self.name, self.exact = M.played(self.effect, self.ctx.trainer)
  if not self.exact then
    self.stand = ("effect %d is not reproduced; %s plays"):format(self.effect, self.name)
  end
  require("src.core.Logger").debug("gen5 transition: effect %d (%s) behaviour %s water %s trainer %s",
    self.effect, self.name, tostring(self.ctx.behaviour), tostring(self.ctx.water), tostring(self.ctx.trainer))
  local rec = game and game.data and game.data.gen5_encounter_effects
  self.camera = rec and rec.camera
  self.model = rec and rec.effects and rec.effects[self.name]
  self.meshWipe = require("src.render.Gen5MeshWipes").handles(self.effect) and self.effect or nil
  self.scene = rec and rec.scenes and rec.scenes[self.name] or nil
  local cut = rec and rec.cutins
  self.cut = cut and cut.effects and cut.effects[self.effect] or nil
  self.cutScene = self.cut and cut.scenes and cut.scenes[self.cut.scene] or nil
  self.cutins = cut
  if self.name:match("^cutin_") and not self.cutScene then
    -- an older cache: the side's ee_* effect stands in
    self.name = self.ctx.trainer and "ee_trnor" or "ee_symbol"
    self.exact = false
    self.model = rec and rec.effects and rec.effects[self.name]
  end
  self.sceneView = rec and rec.scenes and rec.scenes.view
  -- what both screens fade to at the end
  self.endWhite = true
  self.top = { level = 0, target = 0, dir = 1, step = 0, reload = 0, count = 0 }
  self.both = { level = 0, target = 0, dir = 1, step = 0, reload = 0, count = 0 }
  self.state, self.flashes, self.frame, self.tick = 0, 0, 0, 0
  self.finished = false
  return self
end

-- one 30 Hz tick: the brightness unit, then overlay 76's state machine
-- (0x021F5334)
function M:step()
  fadeTick(self.top)
  fadeTick(self.both)
  self.tick = self.tick + 1
  local s = self.state
  if s == 0 then
    fade(self.top, 0, 16, 0)
    self.state = 1
  elseif s == 1 then
    if fadeDone(self.top) then fade(self.top, 16, 0, 0); self.state = 2 end
  elseif s == 2 then
    if fadeDone(self.top) then
      self.flashes = self.flashes + 1
      if self.flashes < 2 then fade(self.top, 0, 16, 0); self.state = 1 else self.state = 3 end
    end
  elseif s == 3 then
    -- the capture, and the model on frame 0
    self.capture = true
    self.frame = 0
    if self.meshWipe then
      self.mesh = require("src.render.Gen5MeshWipes").new(self.meshWipe)
      self.state = 6
    elseif self.cutScene then
      self.cutParticles = require("src.render.Gen5CutIn").particlesNew(self.cutScene, self.effect * 7919)
      self.state = 8
    elseif self.scene then
      -- the scene's last frame is the screen the battle opens from: the
      -- curtain's black, the sandstorm's white
      self.endWhite = self.scene.name == "sand_ci"
      self.state = 7
    elseif not self.model then self.state = 5 else self.state = 4 end
  elseif s == 8 then
    require("src.render.Gen5CutIn").particlesStep(self.cutParticles, self.frame)
    -- the cut-in a frame a tick, then (not yet read from the battle start
    -- that follows it) both screens to white
    if self.frame + 1 >= self.cutScene.frames then
      fade(self.both, 0, 16, 0)
      self.endWhite = true
      self.state = 9
    else
      self.frame = self.frame + 1
    end
  elseif s == 9 then
    if fadeDone(self.both) then self.state = 5 end
  elseif s == 7 then
    if self.frame + 1 >= self.scene.frames then self.state = 5 else self.frame = self.frame + 1 end
  elseif s == 6 then
    -- overlay 75's runner hands each tick to the effect's own task
    local me = self
    local W = require("src.render.Gen5MeshWipes")
    if W.step(self.mesh, function(white) me.endWhite = white; fade(me.both, 0, 16, 0) end,
              function() return fadeDone(me.both) end) then
      self.state = 5
    end
  elseif s == 4 then
    local frames = self.model.frames
    if not self.fading and self.frame >= frames - 20 then
      fade(self.both, 0, 16, 3)
      self.fading = true
    end
    local ended = self.frame + 1 >= frames
    if not ended then self.frame = self.frame + 1 end
    if ended and fadeDone(self.both) and self.fading then self.state = 5 end
  else
    self.finished = true
  end
end

function M:runAll(limit)
  local n = 0
  while not self.finished and n < (limit or 2000) do self:step(); n = n + 1 end
  return n
end

function M:update()
  self.frame60 = (self.frame60 or 0) + 1
  if self.frame60 % 2 == 1 and not self.finished then self:step() end
  if self.finished then
    self.hold = (self.hold or 0) + 1
    if self.hold >= 2 then
      self.game.stack:pop()
      if self.onDone then self.onDone() end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Clip a triangle (camera-space points {x, y, d, u, v}, d the depth in front
-- of the eye) against the near plane; returns a polygon.
local function clipNear(poly, near)
  local out = {}
  for i = 1, #poly do
    local a, b = poly[i], poly[i % #poly + 1]
    local ina, inb = a[3] >= near, b[3] >= near
    if ina then out[#out + 1] = a end
    if ina ~= inb then
      local t = (near - a[3]) / (b[3] - a[3])
      out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, near,
                        a[4] + (b[4] - a[4]) * t, a[5] + (b[5] - a[5]) * t }
    end
  end
  return out
end

local meshFormat = { { "VertexPosition", "float", 2 }, { "VertexTexCoord", "float", 2 } }

-- drawModel(effect, frame, texture, ox, oy, k, camera, uvRect)
-- draws the model's frame (1-based) with `texture` on it: the DS's 256 x 192
-- at (ox, oy), k pixels to the DS pixel. uvRect = {u0, v0, u1, v1} is the part
-- of the texture the model's 0..1 covers (the whole of it by default).
function M.drawModel(eff, frame, texture, ox, oy, k, cam, uvRect)
  local E = require("src.import.Gen5EncounterEffects")
  cam = cam or E.CAMERA
  eff = E.unpack(eff)
  local pos = eff.pos[math.max(1, math.min(#eff.pos, frame))]
  if not pos then return end
  local ty = cam.tanHalfY
  local tx = ty * cam.aspect
  local eye, near = cam.eyeZ, cam.near
  local u0, v0, u1, v1 = 0, 0, 1, 1
  if uvRect then u0, v0, u1, v1 = uvRect[1], uvRect[2], uvRect[3], uvRect[4] end
  local uv, tris = eff.uv, eff.tris
  local polys = {}
  for i = 1, #tris, 3 do
    local poly = {}
    for c = 0, 2 do
      local vi = tris[i + c] - 1   -- the triangles are 1-based
      local p = vi * 3
      poly[c + 1] = { pos[p + 1], pos[p + 2], eye - pos[p + 3],
                      u0 + uv[vi * 2 + 1] * (u1 - u0), v0 + uv[vi * 2 + 2] * (v1 - v0) }
    end
    local far = 0
    for c = 1, 3 do far = far + poly[c][3] end
    if poly[1][3] < near or poly[2][3] < near or poly[3][3] < near then
      poly = clipNear(poly, near)
    end
    if #poly >= 3 then polys[#polys + 1] = { poly = poly, depth = far } end
  end
  -- farthest first: the rings are concentric and never cross
  table.sort(polys, function(a, b) return a.depth > b.depth end)
  local verts = {}
  for _, e in ipairs(polys) do
    local P = e.poly
    local function screen(q)
      local sx = ox + (128 + 128 * q[1] / (q[3] * tx)) * k
      local sy = oy + (96 - 96 * q[2] / (q[3] * ty)) * k
      return { sx, sy, q[4], q[5] }
    end
    local first = screen(P[1])
    for j = 2, #P - 1 do
      verts[#verts + 1] = first
      verts[#verts + 1] = screen(P[j])
      verts[#verts + 1] = screen(P[j + 1])
    end
  end
  if #verts == 0 then return end
  local mesh = love.graphics.newMesh(meshFormat, verts, "triangles", "stream")
  mesh:setTexture(texture)
  love.graphics.draw(mesh)
  mesh:release()
end

-- drawScene(scene, frame, textureOf, ox, oy, k, view): one of the ov73 3D
-- object scenes (Gen5EncounterEffects.buildScenes) over whatever is already
-- drawn; textureOf(shapeIndex) gives a shape's Image, nil for untextured
-- (drawn black, as cave_ci's "black" is). Shapes are drawn farthest first.
function M.drawScene(sc, frame, textureOf, ox, oy, k, view)
  local E = require("src.import.Gen5EncounterEffects")
  sc = E.unpack(sc)
  view = view or E.SCENE_VIEW
  local pos = sc.pos[math.max(1, math.min(#sc.pos, frame))]
  if not pos then return end
  local ty = 1398 / 3850
  local eye = view.halfY / ty
  local tx = ty * view.aspect
  local uv, tris = sc.uv, sc.tris
  local order = {}
  for si, sh in ipairs(sc.shapes) do
    local verts, depth = {}, 0
    for t = sh.first, sh.first + sh.count - 1 do
      local poly = {}
      for c = 0, 2 do
        local vi = tris[t * 3 + c + 1] - 1
        local p = vi * 3
        poly[c + 1] = { pos[p + 1], pos[p + 2], eye - pos[p + 3], uv[vi * 2 + 1], uv[vi * 2 + 2] }
        depth = depth + poly[c + 1][3]
      end
      if poly[1][3] < 1 or poly[2][3] < 1 or poly[3][3] < 1 then poly = clipNear(poly, 1) end
      local function screen(q)
        return { ox + (128 + 128 * q[1] / (q[3] * tx)) * k, oy + (96 - 96 * q[2] / (q[3] * ty)) * k, q[4], q[5] }
      end
      if #poly >= 3 then
        local first = screen(poly[1])
        for j = 2, #poly - 1 do
          verts[#verts + 1] = first; verts[#verts + 1] = screen(poly[j]); verts[#verts + 1] = screen(poly[j + 1])
        end
      end
    end
    order[#order + 1] = { si = si, verts = verts, depth = depth / math.max(1, sh.count * 3) }
  end
  table.sort(order, function(a, b) return a.depth > b.depth end)
  for _, o in ipairs(order) do
    if #o.verts > 0 then
      local mesh = love.graphics.newMesh(meshFormat, o.verts, "triangles", "stream")
      local tex = textureOf and textureOf(o.si)
      if tex then
        mesh:setTexture(tex)
        love.graphics.setColor(1, 1, 1, 1)
      else
        love.graphics.setColor(0, 0, 0, 1)
      end
      love.graphics.draw(mesh)
      mesh:release()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function scratch(self, w, h, name)
  local c = self[name]
  if not c or c:getWidth() ~= w or c:getHeight() ~= h then
    if c and c.release then c:release() end
    c = love.graphics.newCanvas(w, h)
    -- the capture is a texture the DS point-samples
    c:setFilter("nearest", "nearest")
    self[name] = c
  end
  return c
end

-- the renderer's screenDraw: (ox, oy, vpw, vph) is the letterbox holding the
-- DS's 256 x 192. The model's plane is stretched to cover the whole window
-- about the letterbox's centre (at the DS's aspect), and samples the same
-- rectangle of the window's frame, so on a wide window the field round the
-- letterbox breaks apart with the rest rather than vanishing at frame 0.
function M:drawScreen(prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
  local g = love.graphics
  ox, oy = ox or 0, oy or 0
  vpw = vpw or ww
  local k = vpw / 256
  g.setScissor()
  local white = self.both.level
  local endC = self.endWhite and 1 or 0
  if self.state == 5 or self.finished then
    g.setColor(endC, endC, endC, 1)
    g.rectangle("fill", 0, 0, ww, wh)
    return
  end
  if self.capture and source and not self.frozen then
    local c = scratch(self, ww, wh, "frozen")
    g.push("all")
    g.setCanvas(c)
    g.origin()
    g.clear(0, 0, 0, 1)
    g.setColor(1, 1, 1, 1)
    g.draw(source, 0, 0)
    g.pop()
    self.frozenReady = true
  end
  local cx, cy = ox + 128 * k, oy + 96 * k
  local kc = max(k, 2 * max(cx, ww - cx) / 256, 2 * max(cy, wh - cy) / 192)
  local x0, y0 = cx - 128 * kc, cy - 96 * kc
  local rect = { x0 / ww, y0 / wh, (x0 + 256 * kc) / ww, (y0 + 192 * kc) / wh }
  if self.frozenReady and self.cutScene then
    g.setColor(1, 1, 1, 1)
    g.draw(self.frozen, 0, 0)
    local C = require("src.render.Gen5CutIn")
    C.draw(self.cutScene, self.frame + 1, function(_, sh)
      return self:cutInImage(sh)
    end, x0, y0, kc)
    local sp = self.cutScene.particles
    C.particlesDraw(self.cutParticles, function(key)
      return sp and self:cutInImage({ image = sp.textures[key] })
    end, x0, y0, kc)
  elseif self.frozenReady and self.scene then
    g.setColor(1, 1, 1, 1)
    g.draw(self.frozen, 0, 0)
    local me = self
    self.sceneTex = self.sceneTex or {}
    M.drawScene(self.scene, self.frame + 1, function(si)
      local sh = me.scene.shapes[si]
      if not (sh and sh.image) then return nil end
      if me.sceneTex[si] == nil then
        local ok, img = pcall(require("src.render.Assets").image, sh.image)
        if ok and img then img:setFilter("nearest", "nearest"); img:setWrap("repeat", "repeat") end
        me.sceneTex[si] = ok and img or false
      end
      return me.sceneTex[si] or nil
    end, x0, y0, kc, self.sceneView)
  elseif self.frozenReady and self.mesh then
    -- the clear colour (0x0207DD24): white for the white panel wipes
    local W = require("src.render.Gen5MeshWipes")
    local c = W.clearWhite(self.mesh) and 1 or 0
    g.setColor(c, c, c, 1)
    g.rectangle("fill", 0, 0, ww, wh)
    g.setColor(1, 1, 1, 1)
    W.draw(self.mesh, self.frozen, x0, y0, kc, rect)
  elseif self.frozenReady and self.model then
    -- the 3D layer's clear: black behind the pieces
    g.setColor(0, 0, 0, 1)
    g.rectangle("fill", 0, 0, ww, wh)
    g.setColor(1, 1, 1, 1)
    M.drawModel(self.model, self.frame + 1, self.frozen, x0, y0, kc, self.camera, rect)
  elseif source then
    g.setColor(1, 1, 1, 1)
    g.draw(source, 0, 0)
  end
  -- the flashes are white; the closing fade is white or black
  local top = self.top.level
  if top > 0 then
    g.setColor(1, 1, 1, min(1, top / 16))
    g.rectangle("fill", 0, 0, ww, wh)
  end
  if white > 0 then
    g.setColor(endC, endC, endC, min(1, white / 16))
    g.rectangle("fill", 0, 0, ww, wh)
  end
  g.setColor(1, 1, 1, 1)
end

-- the picture a cut-in shape wears: the trainer's face and name, the
-- player's, or the scene's own texture
function M:cutInImage(sh)
  self.cutTex = self.cutTex or {}
  local key = sh.role or sh.image
  if not key then return nil end
  if self.cutTex[key] ~= nil then return self.cutTex[key] or nil end
  local C = require("src.render.Gen5CutIn")
  local img
  local function asset(path)
    if not path then return nil end
    local ok, im = pcall(require("src.render.Assets").image, path)
    if ok and im then im:setFilter("nearest", "nearest"); im:setWrap("repeat", "repeat") end
    return ok and im or nil
  end
  local cut, faces = self.cut, self.cutins and self.cutins.faces or {}
  local save = self.game and self.game.save
  local female = (self.ctx.playerGender or (save and save.player and save.player.gender)) == "female"
    or (self.ctx.playerGender or (save and save.player and save.player.gender)) == 1
  if sh.role == "face" then img = asset(faces[cut.face])
  elseif sh.role == "hero" then img = asset(faces[female and 1 or 0])
  elseif sh.role == "name" then
    local name = self.cutins.names and self.cutins.names[cut.name]
    img = name and C.nameCanvas(name)
  elseif sh.role == "heroName" then
    local name = save and save.player and save.player.name
    img = C.nameCanvas(tostring(name or ""))
  else img = asset(sh.image) end
  self.cutTex[key] = img or false
  return img
end

function M:draw()
  local r = self.game and self.game.renderer
  if r then
    local me = self
    r.battleWipe = { style = "gen5_" .. tostring(self.name), prog = 0.5, t = self.frame60 or 0,
                     game = self.game, needsSource = true, transition = self,
                     screenDraw = function(_, prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
                       me:drawScreen(prog, ww, wh, Sx, Sy, source, ox, oy, vpw, vph)
                     end }
  end
end

return M
