-- The 3D battle: Emerald 3DS's voxel world as a battle's scenery.
--
-- As on the 3DS (voxel_battle.c, ctr_voxel.c BattleCamera), the battle's own
-- picture -- its Pokemon, healthboxes, text box and move animations -- stays
-- the game's.  Only the scenery changes: where the GBA draws its flat battle
-- background, the world is drawn from a camera of its own, lower and closer
-- than the field's (pitch 30, 7 tiles back), looking at a stage searched near
-- the player for open ground of the kind the battle is about (the grass the
-- wild Pokemon came out of, the water of a surfing or fishing battle), level,
-- with nothing tall standing in front of either battler.  The camera glides
-- there from where the field left it: it cranes up, dolly-zooms, lands with
-- a push and a short quake.  Nobody is drawn in the world; the battle draws
-- its own.
--
-- The world reaches the screen the way a render pipeline's does, through
-- Renderer:setWorldOverride, and Gen3Battle.drawField is told to leave out the
-- paper and the background it would paint over it (weather and a move's own
-- background still draw).

local V = ...
local Data = V.require("Data")
local Render = V.require("Render")

local Battle = {}

local floor, rad, sqrt = math.floor, math.rad, math.sqrt

-- voxel_battle.h / 3ds_video.h / ctr_battle_layout.h
local PITCH, DISTANCE, FOV = 30, 7, 35
local GAME_W, GAME_H, ZOOM = 400, 240, 1.4
local DROP, RISE = 2, 8
local FEET = { { 72, 110 + DROP }, { 176, 70 - RISE } }
local RECT = { { 16, 40 + DROP, 128, 112 + DROP }, { 128, 8 - RISE, 224, 76 - RISE } }
-- ctr_voxel.c's glide
local GLIDE_FRAMES, TRAVEL, CRANE, CRANE_MAX = 100, 0.78, 16, 75
local VERTIGO, PUNCH, QUAKE = 0.40, 0.16, 0.07

local PLAIN, GRASS, SAND, WATER, VOID = 0, 1, 2, 3, 4

local WATER_B = { [0x10] = true, [0x11] = true, [0x12] = true, [0x14] = true, [0x15] = true,
                  [0x16] = true, [0x17] = true, [0x19] = true, [0x1A] = true }

local function kindOf(b)
  if b == 0x02 or b == 0x03 or b == 0x09 or b == 0x24 then return GRASS end
  if b == 0x21 or b == 0x06 then return SAND end
  if WATER_B[b] then return WATER end
  return PLAIN
end

local function clamp(t, a, b) return t < a and a or (t > b and b or t) end
local function smoother(t)
  t = clamp(t, 0, 1)
  return t * t * t * (t * (t * 6 - 15) + 10)
end

-- ------------------------------------------------------- the stage search --

local function view()
  local p = rad(PITCH)
  local v = { sinP = math.sin(p), cosP = math.cos(p) }
  v.eyeY, v.eyeZ = DISTANCE * v.sinP, DISTANCE * v.cosP
  v.tanY = math.tan(rad(FOV) / 2)
  v.tanX = v.tanY * GAME_W / GAME_H
  return v
end

local function gbaToScreenX(x) return GAME_W / 2 + (x - 120) * ZOOM end
local function gbaToScreenY(y) return GAME_H - 48 + (y - 112) * ZOOM end

local function screenToGround(v, sx, sy)
  local nx = (sx - GAME_W / 2) / (GAME_W / 2)
  local ny = (GAME_H / 2 - sy) / (GAME_H / 2)
  local dx = nx * v.tanX
  local dy = -v.sinP + ny * v.tanY * v.cosP
  local dz = -v.cosP - ny * v.tanY * v.sinP
  local t = dy < -0.01 and v.eyeY / -dy or 100
  return dx * t, v.eyeZ + dz * t
end

local function project(v, x, h, z)
  local ry, rz = h - v.eyeY, z - v.eyeZ
  local depth = -ry * v.sinP - rz * v.cosP
  local up = ry * v.cosP - rz * v.sinP
  if depth < 0.1 then return nil end
  return GAME_W / 2 + x / (depth * v.tanX) * (GAME_W / 2),
         GAME_H / 2 - up / (depth * v.tanY) * (GAME_H / 2)
end

local function overlap(a, x0, y0, x1, y1)
  local w = math.min(a[3], x1) - math.max(a[1], x0)
  local h = math.min(a[4], y1) - math.max(a[2], y0)
  return (w > 0 and h > 0) and w * h / ((a[3] - a[1]) * (a[4] - a[2])) or 0
end

-- What a world cell is, as the battle sees it (ReadCell).
local function readCell(list, indoor, x, z)
  local R = Render.internal
  local e, lx, lz = R.instanceAt(list, x + 0.5, z + 0.5)
  local cell = { kind = PLAIN, blocked = false, slope = false, top = 0 }
  cell.lift = R.reliefAt(list, x + 0.5, z + 0.5)
  if not e then
    cell.kind = indoor and VOID or PLAIN
    cell.top = indoor and 0 or 2
    cell.blocked = true
    return cell
  end
  local inst, map = e.inst, e.inst.map
  local cx, cz = floor(lx), floor(lz)
  local okB, id = pcall(map.blockAt, map, cx, cz)
  id = okB and id or 0
  local record = inst.atlas and inst.atlas.record
  local beh = 0
  if record and record.tiles and record.tiles.attributes then
    local ok, b = pcall(record.tiles.attributes, record.tiles, id)
    beh = ok and b or 0
  end
  cell.kind = kindOf(beh)
  local okW, walk = pcall(map.isWalkableCell, map, cx, cz)
  cell.blocked = okW and not walk or false
  local _, h = Data.buildingCell(inst.layout, cx, cz, id, function() return true end)
  if h and h > cell.top then cell.top = h end
  local role = Data.roleAt(inst.layout, cx, cz)
  if role == Data.ROLE.TREE then cell.top = math.max(cell.top, 2.4) end
  if role == Data.ROLE.SIGNPOST then cell.top = math.max(cell.top, 1.0) end
  if beh == 0x80 or beh == 0x83 or beh == 0x86 then cell.top = math.max(cell.top, 0.8) end
  local g = Data.reliefCell(inst.layout, cx, cz)
  if g then
    local lo, hi = g[0], g[0]
    for i = 1, 24 do lo, hi = math.min(lo, g[i]), math.max(hi, g[i]) end
    cell.slope = hi - lo > 1
  end
  return cell
end

local function stageFor(state, battle, list)
  local p = state.player
  local v = view()
  local feetX, feetZ, rect = {}, {}, {}
  for side = 1, 2 do
    feetX[side], feetZ[side] = screenToGround(v, gbaToScreenX(FEET[side][1]), gbaToScreenY(FEET[side][2]))
    local r = RECT[side]
    rect[side] = { gbaToScreenX(r[1]), gbaToScreenY(r[2]), gbaToScreenX(r[3]), gbaToScreenY(r[4]) }
  end
  local indoor = not list[1].inst.outdoor
  local cache = {}
  local function cellAt(x, z)
    local cx, cz = floor(x), floor(z)
    local key = cz * 4096 + cx
    local c = cache[key]
    if not c then c = readCell(list, indoor, cx, cz); cache[key] = c end
    return c
  end

  local px, pz = floor((p.px or 0) / 16), floor((p.py or 0) / 16)
  local ahead = ({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } })[p.facing] or { 0, 0 }
  local here = cellAt(px, pz).kind
  local front = cellAt(px + ahead[1], pz + ahead[2]).kind
  local wild = battle.kind == "wild" or battle.isWild == true
  local want = {}
  want[1] = p.surfing and WATER or here
  if p.surfing then want[2] = WATER
  elseif wild then want[2] = (here ~= GRASS and front == WATER) and WATER or here
  else want[2] = front end
  for side = 1, 2 do if want[side] == VOID then want[side] = PLAIN end end

  local function feetScore(side, tx, tz, groundT)
    local fx, fz = tx + feetX[side], tz + feetZ[side]
    local cell = cellAt(fx, fz)
    local w = want[side]
    if cell.kind == VOID then return -60 end
    local score = 0
    if cell.top > 0.4 then score = score - 16 end
    if w == WATER then
      score = score + (cell.kind == WATER and 8 or -8)
    else
      if cell.kind == WATER then score = score - 12
      elseif cell.blocked then score = score - 6 end
      if cell.kind == w then score = score + 4 end
    end
    if cell.slope then score = score - 4 end
    score = score - 3 * math.abs(cell.lift - groundT)
    for dz = -1, 1 do
      for dx = -1, 1 do
        if dx ~= 0 or dz ~= 0 then
          local near = cellAt(fx + dx, fz + dz)
          if near.kind == VOID then score = score - 3
          elseif near.top > 0.4 then score = score - 1 end
          if near.kind == w then score = score + 0.5
          elseif (near.kind == WATER) ~= (w == WATER) then score = score - 0.8 end
          if near.slope then score = score - 0.4 end
        end
      end
    end
    return score
  end

  local function stageScore(tx, tz, distance)
    local groundT = cellAt(tx, tz).lift
    local score = -0.5 * distance
    for side = 1, 2 do score = score + feetScore(side, tx, tz, groundT) end
    for dz = -3, 7 do
      for dx = -6, 6 do
        local cx, cz = floor(tx) + dx, floor(tz) + dz
        local cell = cellAt(cx, cz)
        if cell.top > 0.4 then
          local h = cell.lift - groundT
          local x0, y0 = project(v, cx - tx, h + cell.top, cz + 0.5 - tz)
          local x1, y1 = project(v, cx + 1 - tx, h, cz + 1 - tz)
          if x0 and x1 then
            for side = 1, 2 do
              if cz + 1 - tz > feetZ[side] - 0.5 then
                score = score - 24 * overlap(rect[side], x0, y0, x1, y1)
              end
            end
          end
        end
      end
    end
    for dz = -10, 4 do
      for dx = -10, 10 do
        local cx, cz = floor(tx) + dx + 0.5, floor(tz) + dz + 0.5
        if cellAt(cx, cz).kind == VOID then
          local sx, sy = project(v, cx - tx, 0, cz - tz)
          if sx and sx >= 0 and sx <= GAME_W and sy >= 0 and sy <= GAME_H - 48 then
            score = score - (sy > 90 and 1.2 or 0.5)
          end
        end
      end
    end
    return score
  end

  local baseX, baseZ = px + 0.5 - feetX[1], pz + 0.5 - feetZ[1]
  local bestX, bestZ, best = baseX, baseZ, -1e9
  local REACH = 6
  for dz = -REACH, REACH do
    for dx = -REACH, REACH do
      local tx, tz = baseX + dx, baseZ + dz
      local s = stageScore(tx, tz, sqrt(dx * dx + dz * dz))
      if s > best then best, bestX, bestZ = s, tx, tz end
    end
  end
  return { x = bestX, z = bestZ, ground = (Render.internal.reliefAt(list, bestX, bestZ)) }
end

-- ---------------------------------------------------------------- session --

local session = nil
Battle.viewport = nil

function Battle.active(battle)
  return session ~= nil and session.battle == battle and session.ready
end

function Battle.finish()
  session = nil
end

local function game()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game or nil
end

-- Start a battle's stage: the field camera as it was, and where to go.
local function begin(battle, state)
  local list = Render.internal.instances(state)
  if not list[1] then return nil end
  local cam = Render.cam
  local ok, stage = pcall(stageFor, state, battle, list)
  if not ok then
    V.log("battle stage search failed: %s", tostring(stage))
    return nil
  end
  local field = {
    x = cam.tx or (state.player.px or 0) / 16, z = cam.tz or (state.player.py or 0) / 16,
    ground = cam.ground or 0,
    pitch = cam.pitch and math.deg(cam.pitch) or 40, distance = cam.distance or 13,
  }
  if os.getenv("E3DS_TIMING") then
    V.log("battle stage: %.1f,%.1f ground %.2f (player %d,%d)", stage.x, stage.z, stage.ground,
          floor((state.player.px or 0) / 16), floor((state.player.py or 0) / 16))
  end
  return { battle = battle, state = state, map = state.map, stage = stage, field = field,
           frames = 0, ready = true }
end

-- The camera this frame (BattleCamera): target, ground, pitch, distance, and
-- how far along the glide is (0..1) for the projection's own blend.
local function cameraNow(s)
  local f, st = s.field, s.stage
  local u = math.min(1, s.frames / GLIDE_FRAMES)
  if os.getenv("E3DS_BATTLE_NOGLIDE") then u = 1 end
  local p = clamp(u / TRAVEL, 0, 1)
  local q = clamp((u - TRAVEL) / (1 - TRAVEL), 0, 1)
  local t = smoother(p)
  local arc = (p > 0 and p < 1) and math.sin(p * math.pi) or 0
  local x = f.x + (st.x - f.x) * t
  local z = f.z + (st.z - f.z) * t
  local ground = f.ground + (st.ground - f.ground) * t
  local pitch = f.pitch + (PITCH - f.pitch) * t
  local distance = f.distance + (DISTANCE - f.distance) * t
  pitch = pitch + CRANE * arc
  if pitch > CRANE_MAX and pitch > f.pitch then pitch = f.pitch > CRANE_MAX and f.pitch or CRANE_MAX end
  local fov = FOV * (1 - VERTIGO * arc * arc)
  if arc > 0 then
    distance = distance * math.tan(rad(FOV) / 2) / math.tan(rad(fov) / 2)
  else
    fov = FOV
  end
  local punch = (q > 0 and q < 1) and math.exp(-6 * q) * math.sin(3 * math.pi * q) or 0
  local quake = (q > 0 and q < 1) and QUAKE * math.exp(-7 * q) or 0
  distance = distance * (1 - PUNCH * punch)
  x = x + quake * math.sin(s.frames * 2.7)
  z = z + quake * math.cos(s.frames * 3.9)
  return x, z, ground, pitch, distance, fov, t
end

-- Where the battle's 240x160 picture lies in the window, as fractions of it:
-- left, top, a GBA pixel's width and height.  Read off the last frame's
-- metrics (render.hud); a centred integer letterbox before there are any.
local function pictureRect(battle, w, h)
  local okG, Gen3Battle = pcall(require, "src.battle.Gen3Battle")
  local surface = okG and Gen3Battle.width(battle) or 240
  local offset = okG and Gen3Battle.fieldOffset(battle) or 0
  local vp = Battle.viewport
  if vp and vp.width and vp.width > 0 and vp.gameWidth and vp.gameWidth > 0 then
    local kx = vp.gameWidth / surface / vp.width
    local ky = vp.gameHeight / 160 / vp.height
    return vp.gameX / vp.width + offset * kx, vp.gameY / vp.height, kx, ky
  end
  local s = math.max(1, floor(math.min(w / surface, h / 160)))
  return (w - surface * s) / 2 / w + offset * s / w, (h - 160 * s) / 2 / h, s / w, s / h
end

-- Render the world behind `battle` and hand it to the renderer.
function Battle.draw(battle)
  local s = session
  if not s then return false end
  local sh = Render.internal.getShader()
  if not sh then return false end
  local R = Render.internal
  local list = R.instances(s.state)
  if not list[1] then return false end
  local cur = list[1].inst

  local w, h = love.graphics.getPixelDimensions()
  w, h = math.max(1, floor(w)), math.max(1, floor(h))
  local t = R.targetFor(w, h, "battle")
  s.frames = s.frames + 1
  local x, z, ground, pitch, distance, fov, blend = cameraNow(s)

  -- The 3DS frames its 400x240 screen at FOV 35 and lays the GBA picture on
  -- it at 1.4x, the picture's (120, 112) on the screen's (200, 192).  Here
  -- the picture lies where the engine letterboxes the battle, so the same
  -- framing is a view whose height is the 3DS screen's in GBA pixels, centred
  -- on the GBA point the 3DS screen's centre shows.
  local left, top, kx, ky = pictureRect(battle, w, h)
  local tanField = math.tan(rad(35) / 2)
  local tanBattle = math.tan(rad(fov) / 2) * 1 / ((GAME_H / ZOOM) * ky)
  local cx = left + 120 * kx
  local cy = top + (112 + (GAME_H / 2 - 192) / ZOOM) * ky
  local sx = (2 * cx - 1) * blend
  local sy = (1 - 2 * cy) * blend
  local tanHalf = tanField + (tanBattle - tanField) * blend
  local proj = R.perspective(2 * math.atan(tanHalf), w / h, 0.5, 200.0)
  proj = R.mul({ 1, 0, 0, sx, 0, 1, 0, sy, 0, 0, 1, 0, 0, 0, 0, 1 }, proj)
  proj = R.mul({ 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }, proj)
  local ey = ground + math.tan(rad(pitch)) * distance
  local ez = z + distance
  local viewM = R.lookAt(x, ey, ez, x, ground, z)
  local vp = R.mul(proj, viewM)

  for _, e in ipairs(list) do V.require("Atlas").animate(e.inst.atlas, e.inst.map) end
  R.sceneBegin(t, sh, vp, viewM, distance / math.cos(rad(pitch)), cur.outdoor)
  R.drawTerrain(sh, list, cur)
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.pop()

  local g = game()
  local renderer = g and g.renderer
  if renderer and renderer.setWorldOverride then renderer:setWorldOverride(t.color) end
  return true
end

-- ------------------------------------------------------------ the seams --

local function wanted()
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if not (ok and Pipelines.level("e3ds_voxel") > 0) then return false end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if not (okV and GameVersion.get() == "emerald") then return false end
  return Data.buildings ~= nil
end
Battle.wanted = wanted

-- DRAMATIC_SHAPE stages Emerald battles of its own; with this mode on, these
-- are the battles the player asked for, so its staging stands down.
local function quietDramaticShape()
  local DS = rawget(_G, "__DRAMATIC_SHAPE_V")
  if not (DS and DS.require) then return end
  local ok, OB = pcall(DS.require, "OverworldBattle")
  if not (ok and type(OB) == "table") or OB.__e3dsQuiet then return end
  local innerBegin, innerFront = OB.begin, OB.wantsFront
  if type(innerBegin) == "function" then
    OB.begin = function(...)
      if wanted() then return false end
      return innerBegin(...)
    end
  end
  if type(innerFront) == "function" then
    OB.wantsFront = function(...)
      if wanted() then return false end
      return innerFront(...)
    end
  end
  OB.__e3dsQuiet = true
end
Battle.quietDramaticShape = quietDramaticShape

function Battle.install()
  quietDramaticShape()
  local BattleState = require("src.battle.BattleState")
  if not rawget(BattleState, "__e3dsBattle") then
    local innerDraw = BattleState.draw
    BattleState.draw = function(self, ...)
      local on = false
      if wanted() and not self.blankForAskName and self.gen3Layout and self:gen3Layout() then
        if not (session and session.battle == self) then
          local g = game()
          local ow = g and g.overworld
          session = nil
          if ow and ow.map and ow.player then session = begin(self, ow) end
        end
        if session and session.battle == self then
          local depth = love.graphics.getStackDepth and love.graphics.getStackDepth() or nil
          local canvas = love.graphics.getCanvas()
          local okD, drew = pcall(Battle.draw, self)
          if not okD and depth then
            while love.graphics.getStackDepth() > depth do love.graphics.pop() end
            love.graphics.setShader()
            love.graphics.setCanvas(canvas)
          end
          if okD and drew then
            on = true
            love.graphics.clear(0, 0, 0, 0)
          elseif not okD then
            V.log("battle draw failed: %s", tostring(drew))
            session = nil
          end
        end
      elseif session and session.battle == self then
        session = nil
      end
      self.e3dsWorld = on or nil
      return innerDraw(self, ...)
    end
    BattleState.__e3dsBattle = true
  end
  local Gen3Battle = require("src.battle.Gen3Battle")
  if not rawget(Gen3Battle, "__e3dsBattle") then
    local innerField = Gen3Battle.drawField
    Gen3Battle.drawField = function(battle, ...)
      if not (battle and battle.e3dsWorld) then return innerField(battle, ...) end
      -- a move that replaces the background (BG3) keeps it
      if battle.gen3AnimPlaying and battle.gen3Anim and battle.gen3Anim.backgroundLayer then
        local ok, layer = pcall(battle.gen3Anim.backgroundLayer, battle.gen3Anim)
        if ok and layer and not layer.default then return innerField(battle, ...) end
      end
      return Gen3Battle.drawWeather(battle)
    end
    Gen3Battle.__e3dsBattle = true
  end
end

-- once a frame (the pipeline's update): a battle that has left the stack
-- ends its session
function Battle.update()
  if not session then return end
  local g = game()
  local stack = g and g.stack
  if not stack then return end
  for _, st in ipairs(stack.states or {}) do
    if st == session.battle then return end
  end
  session = nil
end

return Battle
