-- Gen4NpcModels: Platinum's NPCs as smooth 3D bodies built from their own art.
--
-- Platinum's overworld people are flat billboards in a real 3D world. This
-- builds, for every walker sheet, a closed smooth mesh out of the sheet's four
-- real sides (see lib/SpriteSolid.lua for the geometry) and draws it in place
-- of the flat card, through the same seam Gen4WorldHost already uses for the
-- player model, Colosseum/Stadium models and `model3d` actors.
--
-- HOW IT HOOKS IN (engine untouched)
--
--   Gen4WorldHost.wantFieldActor  asks `Npc.wants(entity, state)`
--   Gen4WorldHost.drawFieldActors asks `Npc.drawPose(pose, ground)`; when that
--                                 returns true the host records the entity's
--                                 position, and its freeEntity wrapper then
--                                 skips the flat sprite (exactly as for the
--                                 player model). When it returns false -- body
--                                 not built yet, or anything went wrong -- the
--                                 sprite simply keeps drawing, so an NPC never
--                                 vanishes.
--   Gen4WorldHost.overlay3D       calls `Npc.pump()` once a frame: that is the
--                                 only place meshes are built.
--
-- WHAT IS BUILT, AND WHEN
--
--   One body per (sheet, pose): the stand frame and the two step frames, each
--   from that pose's south / north / west / east pictures. The side pictures
--   give the SHAPE only; the colour comes from the south and north pictures
--   alone, baked into the body's own small texture (see SpriteSolid), so a
--   side picture's eye or nose never lands on the body. The body is turned
--   by the NPC's world facing (eased, so a turn is not a snap) and the pose
--   follows the sprite's own walk phase, so the walk is the sheet's real
--   walk. Sheets are shared: fifty youngsters cost one set of bodies.
--
--   Everything expensive is time-sliced through Gen4Budget and happens in
--   `pump`, never in the draw. A body that is still building returns false.
--
-- WHO GETS ONE
--
--   Any entity whose sheet carries the importer's `facings` for all four sides
--   (every Platinum walker: people, and the Pokemon walkers like Pikachu), and
--   the PLAYER (`includePlayer`, on by default) in whatever sheet it is wearing:
--   walking, running (a `fullCycle` sheet), bike, surf. PlayerModel still wins
--   when a character model is loaded, and the player stays a flat sprite in
--   first person and while free-flying. Not followers or wild roamers (they have
--   their own paths), not anything with a fixed frame or a recoloured sprite,
--   not props: a ball, a boulder or a berry tree has no sides.
--
--   THE PLAYER'S POSE HAS SIDE EFFECTS. Player:pose() advances the surf bob,
--   the spinner-tile spin and the acro hop clocks every time it is called, so
--   it is called at most once per frame, and only when a body is really drawn
--   (which also replaces the engine's skipped 2D draw). Which sheet is active is
--   PREDICTED from the player's flags (the same order pose() uses) so that
--   `wants` and a refused sheet never call it.

local V = ...

local Npc = {
  MAX_CELL = 64,        -- px: bigger cells are not people
  PAD = 4,              -- px of colour grown past each silhouette
  MAX_BODIES = 96,      -- cached bodies before the least recently used go (~330 KB each)
  TURN_RATE = 14,       -- rad/s a body turns toward its facing
  STEP_SECONDS = 0.004, -- slice of one build step
  FILTER = "linear",    -- the atlas is baked smooth at 4x, so linear; "nearest" = hard texels
  includePlayer = true,
  solid = {},           -- SpriteSolid option overrides, e.g. { ss = 2 }
  stats = { builds = 0, failed = 0, drawn = 0, sheets = 0 },
}

Npc.KEY = "gen4Npc3d"
Npc.LABEL = "G4 NPC 3D"

local okS, ModSetting = pcall(function() return V.require("ModSetting") end)
if okS and type(ModSetting) == "table" and ModSetting.new then
  -- values[1] is the default
  Npc.setting = ModSetting.new(Npc.KEY, Npc.LABEL, { "on", "off" }, { "ON", "OFF" })
end

local clock = (love and love.timer and love.timer.getTime) or os.clock

local function log(fmt, ...)
  if V.mod and V.mod.log and V.mod.log.warn then
    pcall(V.mod.log.warn, V.mod.log, "Gen4NpcModels: " .. fmt:format(...))
  end
end

local function lazy(name)
  local ok, m = pcall(V.require, name)
  if ok and type(m) == "table" then return m end
  return nil
end

function Npc.enabled()
  if Npc.forced ~= nil then return Npc.forced end
  local s = Npc.setting
  local v = s and s.get and s:get() or nil
  return v ~= "off"
end

function Npc.row() return Npc.setting and Npc.setting:row() or nil end
function Npc.sync(value) if Npc.setting and Npc.setting.sync then Npc.setting:sync(value) end end

-- ------------------------------------------------------------- records --

-- sprite def -> record. STRONG on purpose: it used to be weak-keyed, and when the
-- collector dropped a def its bodies vanished from here but not from the body
-- count, which then stayed over the cap forever and evicted every body the
-- moment it finished (NPCs never appeared again). Defs live as long as the game
-- data does, and the LRU cap below is what bounds memory.
local recs = {}
local queue = {}                                   -- pending sheets and bodies
local frameNo = 0
local reported = {}

local DIRS = { "down", "up", "left", "right" }

-- A def is a candidate only when the importer wrote all four sides.
local function candidate(sprite)
  local def = sprite and sprite.def
  if type(def) ~= "table" or type(def.facings) ~= "table" then return false end
  if def.big or sprite.big or sprite.mirrorHalf then return false end
  local cw, ch = tonumber(sprite.tileW), tonumber(sprite.tileH)
  if not (cw and ch) or cw < 8 or ch < 8 or cw > Npc.MAX_CELL or ch > Npc.MAX_CELL then
    return false
  end
  for _, d in ipairs(DIRS) do
    local c = def.facings[d]
    if type(c) ~= "table" or c[1] == nil then return false end
  end
  return true, cw, ch
end

local function recOf(sprite)
  local def = sprite and sprite.def
  if type(def) ~= "table" then return nil end
  local rec = recs[def]
  if rec == nil then
    local ok, cw, ch = candidate(sprite)
    rec = { ok = ok, cw = cw, ch = ch, def = def, bodies = {}, state = nil }
    recs[def] = rec
  end
  return rec
end

-- The frame each side shows, exactly as SpriteRenderer.facingFrames picks it:
-- a full-cycle sheet (the run cycle) indexes each side's cycle by phase; any
-- other walker stands unless stepping, and takes the second step only when the
-- entity's step flip is set. One entry per side, so a body is keyed by the four.
local function framesFor(def, phase, flip)
  local fr = {}
  for _, d in ipairs(DIRS) do
    local c = def.facings[d]
    if def.fullCycle then
      fr[d] = c[(math.floor(tonumber(phase) or 0) % #c) + 1]
    elseif def.walker and phase == 1 then
      if flip then fr[d] = c[3] or c[2] or c[1] else fr[d] = c[2] or c[1] end
    else
      fr[d] = c[1]
    end
  end
  return fr
end

-- Which sheet the entity is showing, WITHOUT calling pose() (see header). The
-- order is Player:pose()'s; an entity with none of those fields (an NPC) just
-- has its sprite.
local function predictSprite(e)
  if not (e.bikeSprite or e.surfSprite or e.runSprite or e.fieldMoveSprite
          or e.underwaterSprite) then
    return e.sprite
  end
  if e.fieldMove and e.fieldMoveSprite then return e.fieldMoveSprite end
  if e.fishing and e.sprite then return e.sprite end
  if e.underwaterSprite and type(e.isUnderwater) == "function" then
    local ok, under = pcall(e.isUnderwater, e)
    if ok and under then return e.underwaterSprite end
  end
  if e.surfing and e.surfingPikachu and e.surfPikachuSprite then return e.surfPikachuSprite end
  if e.surfing and e.surfSprite then return e.surfSprite end
  if e.onBike and e.bikeSprite then return e.bikeSprite end
  if e.running and e.runSprite then return e.runSprite end
  return e.sprite
end

-- --------------------------------------------------------- sheet / pad --

local function readRGBA(data)
  local w, h = data:getDimensions()
  local okF, fmt = pcall(data.getFormat, data)
  if okF and fmt == "rgba8" then
    local okS2, str = pcall(data.getString, data)
    if okS2 and type(str) == "string" and #str == w * h * 4 then return str, w, h end
  end
  -- slow, format-proof path
  local out = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      out[#out + 1] = string.char(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                  math.floor(b * 255 + 0.5), math.floor(a * 255 + 0.5))
    end
  end
  return table.concat(out), w, h
end

-- Read the sheet and keep two copies of its pixels: the raw one for the
-- silhouettes, and a colour-padded one (colour grown a few px past every
-- silhouette, inside its own cell) for the bodies to sample, because a body is
-- rounder than the pixels. Nothing is uploaded here: each body bakes and
-- uploads its own small texture. Returns true, or false + reason.
local function loadSheet(rec)
  local Solid = lazy("SpriteSolid")
  if not Solid then return false, "SpriteSolid did not load" end
  local okA, Assets = pcall(require, "src.render.Assets")
  if not (okA and Assets and Assets.imageData) then return false, "no Assets.imageData" end
  local okD, data = pcall(Assets.imageData, rec.def.image)
  if not (okD and data) then return false, "could not read " .. tostring(rec.def.image) end
  local rgba, w, h = readRGBA(data)
  if w ~= rec.cw then return false, ("sheet is %d wide, cells are %d"):format(w, rec.cw) end
  local need = 0
  for _, d in ipairs(DIRS) do
    for _, f in ipairs(rec.def.facings[d]) do need = math.max(need, f + 1) end
  end
  if h < need * rec.ch then return false, ("sheet is %d tall, poses need %d"):format(h, need * rec.ch) end
  rec.rgba, rec.imgW, rec.imgH = rgba, w, h
  rec.padded = Solid.padRGBA(rgba, w, h, rec.cw, rec.ch, Npc.PAD)
  Npc.stats.sheets = Npc.stats.sheets + 1
  return true
end

-- --------------------------------------------------------------- bodies --

local function startBody(rec, key, frames)
  local Solid = lazy("SpriteSolid")
  local views, cellY = {}, {}
  local map = { front = "down", back = "up", left = "left", right = "right" }
  for k, d in pairs(map) do
    local y0 = frames[d] * rec.ch
    views[k] = Solid.maskFromRGBA(rec.rgba, rec.imgW, rec.imgH, 0, y0, rec.cw, rec.ch)
    cellY[k] = y0
  end
  local layout = { imgW = rec.imgW, imgH = rec.imgH, cellW = rec.cw, cellH = rec.ch,
                   cellX = 0, cellY = cellY, src = rec.padded }
  local body = { used = frameNo }
  body.job = Solid.newJob(views, layout, Npc.solid, clock)
  rec.bodies[key] = body
  queue[#queue + 1] = { kind = "body", rec = rec, key = key, body = body }
end

local function release(body)
  if body.mesh and body.mesh.release then pcall(body.mesh.release, body.mesh) end
  if body.image and body.image.release then pcall(body.image.release, body.image) end
  body.mesh, body.image = nil, nil
end

-- Drop the least recently used finished bodies past the cap. The count is taken
-- by looking, never kept in a counter that could drift. A body drawn this frame
-- or the last is never dropped: if everything is in use the cache simply runs
-- over the cap rather than thrash (build, evict, rebuild...).
local function evict()
  local pending = {}
  for _, it in ipairs(queue) do if it.body then pending[it.body] = true end end
  local list, live = {}, 0
  for _, rec in pairs(recs) do
    for key, body in pairs(rec.bodies) do
      if body.mesh then
        live = live + 1
        if not pending[body] and body.used < frameNo - 1 then
          list[#list + 1] = { rec, key, body }
        end
      end
    end
  end
  if live <= Npc.MAX_BODIES then return end
  table.sort(list, function(a, b) return a[3].used < b[3].used end)
  local i = 1
  while live > Npc.MAX_BODIES and list[i] do
    release(list[i][3])
    list[i][1].bodies[list[i][2]] = nil
    live = live - 1
    i = i + 1
  end
end

local function finish(item)
  local body = item.body
  local job = body.job
  body.job = nil
  local r = job.result
  if job.failed or not r then
    body.failed = job.failed or job.reason or "no result"
    Npc.stats.failed = Npc.stats.failed + 1
    local id = tostring(item.rec.def.id or item.rec.def.image)
    if not reported[id] then
      reported[id] = true
      log("%s: %s", id, tostring(body.failed))
    end
    return
  end
  local Voxel3D = lazy("Voxel3D")
  local mesh = Voxel3D and Voxel3D.newMesh(r.verts, r.map) or nil
  local okI, image = pcall(function()
    local id = love.image.newImageData(r.atlasW, r.atlasH, "rgba8", r.atlas)
    local img = love.graphics.newImage(id)
    img:setFilter(Npc.FILTER, Npc.FILTER)
    return img
  end)
  if not (mesh and okI and image) then
    if mesh and mesh.release then pcall(mesh.release, mesh) end
    body.failed = "mesh or texture upload failed"
    Npc.stats.failed = Npc.stats.failed + 1
    return
  end
  body.mesh, body.image = mesh, image
  body.height, body.tris = r.height, r.triangleCount
  Npc.stats.builds = Npc.stats.builds + 1
  evict()
end

-- Spend this frame's share of the build budget. Called once per frame.
function Npc.pump()
  frameNo = frameNo + 1
  if #queue == 0 then return end
  local Budget = lazy("Gen4Budget")
  local steps = 0
  while #queue > 0 and steps < 8 do
    if Budget and not Budget.allow(true) then break end
    local item = queue[1]
    local t0 = clock()
    if item.kind == "sheet" then
      table.remove(queue, 1)
      local ok, why = loadSheet(item.rec)
      item.rec.state = ok and "ready" or "failed"
      if not ok then
        item.rec.ok = false
        Npc.stats.failed = Npc.stats.failed + 1
        local id = tostring(item.rec.def.id or item.rec.def.image)
        if not reported[id] then reported[id] = true; log("%s: %s", id, tostring(why)) end
      end
    else
      if item.body.job:step(Npc.STEP_SECONDS) then
        table.remove(queue, 1)
        finish(item)
      end
    end
    if Budget then Budget.charge(t0, "npc") end
    steps = steps + 1
  end
end

-- ----------------------------------------------------------------- API --

-- Cheap enough to ask for every entity every frame, and never calls pose().
function Npc.wants(e, state)
  if not Npc.enabled() then return false end
  if type(e) ~= "table" or e.hidden or e.fixedFrame then return false end
  if e.isFollower or e.wildsFollower or e._wildsFollowerSpecies
     or e.roamer or e.overworldWildSpawn or e.species then
    return false
  end
  if state and e == state.player then
    if not Npc.includePlayer then return false end
    -- free flying carries the player's own mount model at altitude
    if (tonumber(e.freeFlyAlt) or 0) > 0 then return false end
  end
  local sprite = predictSprite(e)
  if sprite and sprite.palColors then return false end   -- recoloured: keep the card
  local rec = recOf(sprite)
  return rec ~= nil and rec.ok == true and rec.state ~= "failed"
end

local TAU = math.pi * 2
local function approach(cur, target, step)
  local d = (target - cur + math.pi) % TAU - math.pi
  if math.abs(d) <= step then return target end
  return cur + (d > 0 and step or -step)
end

local turns = setmetatable({}, { __mode = "k" })   -- entity -> { yaw, t }

local function yawFor(e, facing, isPlayer)
  local Cam = lazy("Gen4ActorCam")
  local target = Cam and Cam.worldYaw(facing) or 0
  -- in third person the walk is camera-relative and the body has a real heading
  -- (the same one PlayerModel turns by); the four compass facings are the grid's
  if isPlayer and Cam and Cam.freeRoam and Cam.freeRoam() and Cam.modelYaw then
    target = Cam.modelYaw() or target
  end
  local now = clock()
  local st = turns[e]
  if not st or now - st.t > 0.5 then
    st = { yaw = target, t = now }
    turns[e] = st
    return target
  end
  local dt = math.min(math.max(now - st.t, 0), 0.1)
  st.yaw = approach(st.yaw, target, Npc.TURN_RATE * dt)
  st.t = now
  return st.yaw
end

-- Draw one posed entity (a Gen4WorldHost `posed` entry). True only when a body
-- was actually drawn; false leaves the flat sprite to draw as before.
function Npc.drawPose(p, ground)
  local e = p and p.entity
  if not e then return false end
  if not Npc.wants(e, p.isPlayer and { player = e } or nil) then return false end
  local predicted = predictSprite(e)
  local rec = recOf(predicted)
  if not (rec and rec.ok) then return false end
  if rec.state == nil then
    rec.state = "loading"
    queue[#queue + 1] = { kind = "sheet", rec = rec }
    return false
  end
  if rec.state ~= "ready" then return false end

  -- Everything the 2D draw would have read from pose(): the sheet, the walk
  -- phase, and any visual offset (hop / spin height, stairs and ship slides).
  -- It is the ONE call this frame (see header).
  local sprite, phase, flip = predicted, p.phase, p.flip
  local offX, offZ, lift = 0, 0, 0
  if type(e.pose) == "function" then
    local ok, s1, x1, y1, _, ph, fl = pcall(e.pose, e)
    if ok and s1 then
      sprite, phase, flip = s1, ph, fl
      if x1 and e.px then offX = x1 - e.px end
      if y1 and e.py then
        local dy = y1 - e.py
        if e.stairExit then offZ = dy elseif dy < 0 then lift = -dy end
      end
    end
  end
  if sprite ~= predicted then               -- the prediction was wrong: check again
    rec = recOf(sprite)
    if not (rec and rec.ok and rec.state == "ready") or sprite.palColors then return false end
  end
  local frames = framesFor(rec.def, phase, flip)
  local key = frames.down .. "," .. frames.up .. "," .. frames.left .. "," .. frames.right
  local body = rec.bodies[key]
  if not body then
    startBody(rec, key, frames)
    return false
  end
  body.used = frameNo
  if not (body.mesh and body.image) then return false end

  local Voxel3D, Mat4 = lazy("Voxel3D"), lazy("Mat4")
  if not (Voxel3D and Mat4) then return false end
  local yaw = yawFor(e, p.facing, p.isPlayer)
  local m = Mat4.translate((p.px or 0) + 8 + offX, (p.gh or 0) + lift, (p.py or 0) + 8 + offZ)
  if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
  local ok = pcall(Voxel3D.draw, body.mesh, body.image, m)
  if ok then Npc.stats.drawn = Npc.stats.drawn + 1 end
  return ok
end

-- Drop every mesh, sheet and queued job (graphics reset, mod reload, cache
-- reset). Bodies rebuild on demand.
function Npc.invalidate()
  for _, rec in pairs(recs) do
    for _, body in pairs(rec.bodies) do release(body) end
  end
  for k in pairs(recs) do recs[k] = nil end
  for i = #queue, 1, -1 do queue[i] = nil end
  reported = {}
end

function Npc.install()
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and type(Assets.register) == "function" then
    pcall(Assets.register, Npc.invalidate)   -- a mod swapping a sheet rebuilds its body
  end
  return true
end

-- test / diagnostics
Npc._recOf, Npc._framesFor, Npc._predictSprite, Npc._queue = recOf, framesFor, predictSprite, queue
function Npc.pending() return #queue end

return Npc
