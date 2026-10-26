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
-- GEN 1-3 (the voxel diorama) USE THE SAME BODY BUILDER
--
--   Their world is VoxelScene's, and their sheets are the classic six-frame
--   strip (down, up, left standing; the same three mid-step) with NO `facings`:
--   "right" is the left picture mirrored. The four sides are ASSEMBLED from the
--   strip, through the same STAND / WALK tables SpriteRenderer (and
--   VoxelScene.frameFor) use: front = down, back = up, left = left, right =
--   left mirrored. A down/up step the 2D game draws flipped is a body of its
--   own, so the legs still swap.
--
--   VoxelScene.drawCast           asks `Npc.drawClassic(pose, tex, pull)`
--   VoxelScene.castShadows        asks `Npc.castClassic(pose, tex, ShadowMap)`
--   VoxelScene.render             calls `Npc.pump()` once a frame
--
--   `tex` is the image the card would be textured with. The body's colour is
--   read from it: the plain sheet from the asset store when that is what it is,
--   otherwise one read-back of the live (RED++ / SGB palette-baked) picture, so
--   a body is never a different colour from the sprite it replaces. While a
--   pose is still building the sheet's finished stand body stands in, so a
--   walker never flickers back to a flat card. Props (one-frame sheets),
--   followers, roamers, HD Pokemon cards and waterline-cut swimmers keep their
--   cards.
--
-- WHAT IS BUILT, AND WHEN
--
--   One body per (sheet, pose): the stand frame and the two step frames, each
--   from that pose's south / north / west / east pictures. The side pictures
--   give the SHAPE only; the colour comes from the south and north pictures
--   alone, baked into the body's own small texture (see SpriteSolid), so a
--   side picture's eye or nose never lands on the body. The body is turned
--   by facing (eased, so a turn is not a snap). NPCs keep their own world
--   movement direction. The player in 1ST/3RD uses the same camera yaw the
--   flat card and Pokemon Player use. The pose follows the sprite's own
--   walk phase, so the walk is the sheet's real walk. Sheets are shared:
--   fifty youngsters cost one set of bodies.
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
  MAX_QUEUE = 24,       -- Gen 1-3: pending sheets + bodies; past this nothing new is started this frame
  MAX_BODIES = 96,      -- cached bodies before the least recently used go (~330 KB each)
  TURN_RATE = 14,       -- rad/s a body turns toward its facing
  STEP_SECONDS = 0.004, -- slice of one build step
  FILTER = "linear",    -- the atlas is baked smooth at 4x, so linear; "nearest" = hard texels
  includePlayer = true,
  solid = {},           -- SpriteSolid option overrides, e.g. { ss = 2 }
  FRAME_SECONDS = 0.006,-- Gen 1-3: build time per frame (Gen 4 uses Gen4Budget)
  -- Gen 1-3 art is 16 px: sample the field twice per pixel so a 10 px body is
  -- not a blob. Cells bigger than SMALL_CELL use `solid`.
  classicSolid = { ss = 2 },
  SMALL_CELL = 24,
  stats = { builds = 0, failed = 0, drawn = 0, sheets = 0 },
}

-- DETAIL (lib/Gen4Detail, the G4 DETAIL row; FAST by default on every
-- platform). Gen 4/5 cells only: `solid` applies to cells wider than
-- SMALL_CELL, so Gen 1-3 sprites keep classicSolid. Measured on Android, single
-- NPC builds reached 103 ms. FAST bakes a 2x atlas instead of 4x (a quarter of
-- the texels to bake, blur and upload) with one smoothing pass instead of two.
-- Bodies read slightly softer up close.
local npcDetailLevel = nil
local function applyNpcDetail()
  local ok, Detail = pcall(function() return V.require("Gen4Detail") end)
  if not (ok and type(Detail) == "table" and Detail.get) then return end
  local level = Detail.level()
  if level == npcDetailLevel then return end
  local d = Detail.get("npc")
  local solid = {}
  for k, v in pairs(d) do solid[k] = v end
  Npc.solid = solid
  -- the row changed mid-session: rebuild the bodies at the new detail
  if npcDetailLevel and type(Npc.invalidate) == "function" then pcall(Npc.invalidate) end
  npcDetailLevel = level
end

Npc.KEY = "gen4Npc3d"
Npc.LABEL = "NPC 3D"

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

-- ------------------------------------------------------- diagnostics --
--
-- Why a Gen 1-3 pose did or did not become a body, counted by reason, and
-- written to the mod log every DIAG_SECONDS while the Gen 1-3 path is being
-- asked about people. "NPC 3D does nothing on Gen 1-3" has many possible
-- causes (setting off, sheet refused, build failed, read-back failed, a
-- fuse trip...) and each one is a different counter here.
Npc.why = {}
Npc.DIAG_SECONDS = 10
local diagAt, diagDirty = 0, false
local function no(reason)
  local w = Npc.why
  w[reason] = (w[reason] or 0) + 1
  diagDirty = true
  return false
end

function Npc.report()
  local keys = {}
  for k in pairs(Npc.why) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. Npc.why[k] end
  local st = Npc.stats
  return ("enabled=%s sheets=%d builds=%d failed=%d drawn=%d queued=%d | %s"):format(
    tostring(Npc.enabled()), st.sheets, st.builds, st.failed, st.drawn, #(Npc._queue or {}),
    table.concat(parts, " "))
end

local function diagTick()
  if not diagDirty then return end
  local now = clock()
  if now - diagAt < Npc.DIAG_SECONDS then return end
  diagAt, diagDirty = now, false
  local log = V.mod and V.mod.log
  if log and log.info then pcall(log.info, log, "Gen4NpcModels (Gen 1-3 path): %s", Npc.report()) end
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
-- Gen 1-3: live sheet image -> record. Keyed by the IMAGE (not the def) so the
-- same sheet under two palettes (neighbouring maps) is two records, never a
-- thrash. Weak: a record's bodies are counted by looking (see evict), so a
-- dropped one cannot leave the count over the cap.
local crecs = setmetatable({}, { __mode = "k" })
local queue = {}                                   -- pending sheets and bodies
local frameNo = 0
local reported = {}
local revision = 0        -- bumps whenever what a body draws could have changed

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
    rec = { kind = "facings", ok = ok, cw = cw, ch = ch, def = def, bodies = {}, state = nil }
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

-- ------------------------------------------------------ Gen 1-3 frames --

-- The engine's own tables when it has them, the classic strip otherwise.
local STAND_FALLBACK = { down = 0, up = 1, left = 2, right = 2 }
local WALK_FALLBACK = { down = 3, up = 4, left = 5, right = 5 }
local srStand, srWalk

local function strip()
  if not srStand then
    local ok, SR = pcall(require, "src.render.SpriteRenderer")
    if ok and type(SR) == "table" and type(SR.STAND) == "table" and type(SR.WALK) == "table" then
      srStand, srWalk = SR.STAND, SR.WALK
    else
      return STAND_FALLBACK, WALK_FALLBACK
    end
  end
  return srStand, srWalk
end

-- The strip frames a pose shows, and whether the down/up pictures are
-- mirrored: exactly VoxelScene.frameFor (the step frames only for a walker
-- mid-step; the mirror whenever a step is flipped).
local function classicFrames(def, frames, phase, flip)
  local STAND, WALK = strip()
  local walking = def.walker and phase == 1
  local function pick(facing)
    local i = walking and WALK[facing] or STAND[facing]
    if type(i) ~= "number" or i < 0 or i >= frames then i = STAND[facing] end
    if type(i) ~= "number" or i < 0 or i >= frames then i = 0 end
    return i
  end
  return pick("down"), pick("up"), pick("left"), (phase == 1 and flip) and true or false
end

local function classicKey(d, u, l, m)
  return d .. "," .. u .. "," .. l .. (m and "m" or "")
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

-- The pixels of a live picture exactly as it is on the GPU: draw it 1:1 into a
-- scratch canvas with the "replace" blend (a straight copy, alpha included) and
-- read the canvas back. Graphics state is saved and restored around it; the
-- caller is the start of a frame, with no scene canvas bound.
local function readbackRGBA(img)
  local g = love and love.graphics
  if not (g and g.newCanvas and g.push and g.pop) then return nil, "no graphics" end
  local w, h = img:getDimensions()
  local okC, canvas = pcall(g.newCanvas, w, h, { dpiscale = 1 })
  if not (okC and canvas) then okC, canvas = pcall(g.newCanvas, w, h) end
  if not (okC and canvas) then return nil, "no scratch canvas" end
  g.push("all")
  local okD, err = pcall(function()
    pcall(g.reset)
    g.setCanvas(canvas)
    g.clear(0, 0, 0, 0)
    g.setShader()
    g.setBlendMode("replace")
    g.setColor(1, 1, 1, 1)
    g.origin()
    g.draw(img, 0, 0)
  end)
  g.pop()
  if not okD then
    pcall(canvas.release, canvas)
    return nil, tostring(err)
  end
  local okI, data = pcall(canvas.newImageData, canvas)
  pcall(canvas.release, canvas)
  if not (okI and data) then return nil, "read-back failed" end
  local rgba, rw, rh = readRGBA(data)
  if rw ~= w or rh ~= h then return nil, ("read-back is %dx%d, picture is %dx%d"):format(rw, rh, w, h) end
  return rgba, rw, rh
end

-- The pixels behind `tex`: the asset store's own copy when `tex` IS the plain
-- sheet (no GPU work), a read-back of the live picture otherwise (a palette bake).
local function imageRGBA(tex, def)
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.image and Assets.imageData and type(def.image) == "string" then
    local okI, plain = pcall(Assets.image, def.image)
    if okI and plain == tex then
      local okD, data = pcall(Assets.imageData, def.image)
      if okD and data then return readRGBA(data) end
    end
  end
  return readbackRGBA(tex)
end

-- Read the sheet and keep two copies of its pixels: the raw one for the
-- silhouettes, and a colour-padded one (colour grown a few px past every
-- silhouette, inside its own cell) for the bodies to sample, because a body is
-- rounder than the pixels. Nothing is uploaded here: each body bakes and
-- uploads its own small texture. Returns true, or false + reason.
local function loadSheet(rec)
  local Solid = lazy("SpriteSolid")
  if not Solid then return false, "SpriteSolid did not load" end
  local rgba, w, h
  if rec.kind == "classic" then
    rgba, w, h = imageRGBA(rec.img, rec.def)
    if not rgba then return false, tostring(w or "could not read the sheet") end
    if w ~= rec.cw or h ~= rec.ch * rec.frames then
      return false, ("sheet is %dx%d, expected %dx%d"):format(w, h, rec.cw, rec.ch * rec.frames)
    end
  else
    local okA, Assets = pcall(require, "src.render.Assets")
    if not (okA and Assets and Assets.imageData) then return false, "no Assets.imageData" end
    local okD, data = pcall(Assets.imageData, rec.def.image)
    if not (okD and data) then return false, "could not read " .. tostring(rec.def.image) end
    rgba, w, h = readRGBA(data)
    if w ~= rec.cw then return false, ("sheet is %d wide, cells are %d"):format(w, rec.cw) end
    local need = 0
    for _, d in ipairs(DIRS) do
      for _, f in ipairs(rec.def.facings[d]) do need = math.max(need, f + 1) end
    end
    if h < need * rec.ch then return false, ("sheet is %d tall, poses need %d"):format(h, need * rec.ch) end
  end
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

-- One cell of a sheet (frame `frame`), as raw RGBA rows, optionally mirrored.
local function cellBytes(str, imgW, cw, ch, frame, mirror)
  local rows = {}
  local y0 = frame * ch
  for y = 0, ch - 1 do
    local at = (y0 + y) * imgW * 4 + 1
    local row = str:sub(at, at + cw * 4 - 1)
    if mirror then
      local px = {}
      for x = cw - 1, 0, -1 do px[#px + 1] = row:sub(x * 4 + 1, x * 4 + 4) end
      row = table.concat(px)
    end
    rows[#rows + 1] = row
  end
  return table.concat(rows)
end

-- Gen 1-3: a four-cell sheet of our own (front, back, left, right = left
-- mirrored) for SpriteSolid to build from. Run by the pump, not in a draw.
local function makeClassicJob(rec, spec)
  local Solid = lazy("SpriteSolid")
  local W, H = rec.cw, rec.ch
  local order = {
    { "front", spec.d, spec.m }, { "back", spec.u, spec.m },
    { "left", spec.l, false },   { "right", spec.l, true },
  }
  local raw, pad, views, cellY = {}, {}, {}, {}
  for i, o in ipairs(order) do
    raw[i] = cellBytes(rec.rgba, W, W, H, o[2], o[3])
    pad[i] = cellBytes(rec.padded, W, W, H, o[2], o[3])
  end
  local rawAll, padAll = table.concat(raw), table.concat(pad)
  for i, o in ipairs(order) do
    views[o[1]] = Solid.maskFromRGBA(rawAll, W, 4 * H, 0, (i - 1) * H, W, H)
    cellY[o[1]] = (i - 1) * H
  end
  local layout = { imgW = W, imgH = 4 * H, cellW = W, cellH = H,
                   cellX = 0, cellY = cellY, src = padAll }
  local solid = rec.cw <= Npc.SMALL_CELL and Npc.classicSolid or Npc.solid
  return Solid.newJob(views, layout, solid, clock)
end

local function startClassicBody(rec, key, spec)
  local body = { used = frameNo, spec = spec }     -- the job is made by the pump
  rec.bodies[key] = body
  queue[#queue + 1] = { kind = "body", rec = rec, key = key, body = body }
  return body
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
  local function scan(rec)
    for key, body in pairs(rec.bodies) do
      if body.mesh then
        live = live + 1
        if not pending[body] and body.used < frameNo - 1 then
          list[#list + 1] = { rec, key, body }
        end
      end
    end
  end
  for _, rec in pairs(recs) do scan(rec) end
  for _, rec in pairs(crecs) do scan(rec) end
  if live <= Npc.MAX_BODIES then return end
  table.sort(list, function(a, b) return a[3].used < b[3].used end)
  local i = 1
  while live > Npc.MAX_BODIES and list[i] do
    release(list[i][3])
    list[i][1].bodies[list[i][2]] = nil
    live = live - 1
    revision = revision + 1
    i = i + 1
  end
end

local function finish(item)
  local body = item.body
  local job = body.job
  body.job, body.spec = nil, nil
  local r = job.result
  if job.failed or not r then
    body.failed = job.failed or job.reason or "no result"
    no("build-failed: " .. tostring(body.failed))
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
    no("upload-failed")
    Npc.stats.failed = Npc.stats.failed + 1
    return
  end
  body.mesh, body.image = mesh, image
  body.height, body.tris = r.height, r.triangleCount
  Npc.stats.builds = Npc.stats.builds + 1
  revision = revision + 1
  evict()
end

-- Spend this frame's share of the build budget. Called once per frame.
-- A sheet has just loaded (Gen 1-3): queue the three poses a walker can show,
-- the stand pose first, so a person is a body at rest before one in motion.
local function preloadClassic(rec)
  -- ONLY THE STAND BODY. The two step poses used to be queued here as well,
  -- three bodies per sheet per palette, and the diorama poses every person on
  -- every resident map (a town keeps four neighbours, ~150 people): the queue
  -- never drained. A step pose is built when somebody ON SCREEN is mid-step
  -- (classicBody), and the stand body stands in until then.
  for _, ph in ipairs({ { 0, false } }) do
    local d, u, l, m = classicFrames(rec.def, rec.frames, ph[1], ph[2])
    local key = classicKey(d, u, l, m)
    if not rec.bodies[key] then startClassicBody(rec, key, { d = d, u = u, l = l, m = m }) end
    if ph[1] == 0 then rec.standKey = key end
  end
end

local function isGen4()
  local B = lazy("Gen4Bridge")
  if B and B.isNativeWorld then return B.isNativeWorld() end
  return B and B.isGen4 and B.isGen4() or false
end

function Npc.pump()
  applyNpcDetail()
  frameNo = frameNo + 1
  if #queue == 0 then return end
  -- Gen 4 shares Gen4Budget with its other effects (the bridge closes each
  -- frame's budget). Nothing closes it on Gen 1-3, so those keep their own.
  local Budget = isGen4() and lazy("Gen4Budget") or nil
  local frameStart = clock()
  local steps = 0
  while #queue > 0 and steps < 8 do
    if Budget then
      if not Budget.allow(true) then break end
    elseif steps > 0 and clock() - frameStart > Npc.FRAME_SECONDS then
      break
    end
    local item = queue[1]
    local t0 = clock()
    if item.kind == "sheet" then
      table.remove(queue, 1)
      local ok, why = loadSheet(item.rec)
      item.rec.img = nil          -- the picture is not kept: its pixels are
      item.rec.state = ok and "ready" or "failed"
      if not ok then
        item.rec.ok = false
        no("sheet-failed: " .. tostring(why))
        Npc.stats.failed = Npc.stats.failed + 1
        local id = tostring(item.rec.def.id or item.rec.def.image)
        if not reported[id] then reported[id] = true; log("%s: %s", id, tostring(why)) end
      elseif item.rec.kind == "classic" then
        preloadClassic(item.rec)
      end
    else
      local body = item.body
      if not body.job and not body.failed then
        local okJ, job = pcall(makeClassicJob, item.rec, body.spec)
        if okJ then
          body.job = job
        else
          body.failed = tostring(job)
          no("job-error: " .. tostring(job))
          Npc.stats.failed = Npc.stats.failed + 1
          local id = tostring(item.rec.def.id or item.rec.def.image)
          if not reported[id] then reported[id] = true; log("%s: %s", id, body.failed) end
        end
      end
      if body.failed then
        table.remove(queue, 1)
      elseif body.job:step(Npc.STEP_SECONDS) then
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

-- Compass facing as a rotateY offset from "toward the eye" (sprite-solid
-- identity faces south / "down", same as PlayerModel.yawForDraw towardCam).
local function facingOffset(facing)
  facing = type(facing) == "string" and string.lower(facing) or facing
  if facing == "up" then return math.pi end
  if facing == "left" then return math.pi / 2 end
  if facing == "right" then return -math.pi / 2 end
  return 0
end

-- Continuous target yaw. Only the PLAYER follows the camera; NPCs keep
-- the facing they are actually walking. Gen 4 third/first: modelYaw.
-- Voxel 1ST/3RD: FirstPerson body/card yaw (same as PlayerModel).
-- Everyone else, and tilt / field cameras: world compass.
local function yawTarget(e, facing, isPlayer, px, py)
  local Cam = lazy("Gen4ActorCam")
  if isPlayer then
    if Cam and Cam.freeRoam and Cam.freeRoam() and Cam.modelYaw then
      return Cam.modelYaw() or 0
    end
    local FirstPerson = lazy("FirstPerson")
    local b = 0
    if FirstPerson and FirstPerson.cardBlend then
      local ok, v = pcall(FirstPerson.cardBlend)
      if ok then b = tonumber(v) or 0 end
    end
    if b > 0 then
      if FirstPerson.bodyYaw ~= nil then
        return FirstPerson.bodyYaw
      end
      if FirstPerson.cardYaw then
        local ok, cameraYaw = pcall(FirstPerson.cardYaw, (px or 0) + 8, (py or 0) + 8)
        if ok and type(cameraYaw) == "number" then
          return (cameraYaw + facingOffset(facing)) * b
        end
      end
    end
  end
  if Cam and Cam.worldYaw then return Cam.worldYaw(facing) end
  return facingOffset(facing)
end

local function yawFor(e, facing, isPlayer, px, py)
  local target = yawTarget(e, facing, isPlayer, px, py)
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
  local yaw = yawFor(e, p.facing, p.isPlayer, p.px, p.py)
  local m = Mat4.translate((p.px or 0) + 8 + offX, (p.gh or 0) + lift, (p.py or 0) + 8 + offZ)
  if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
  -- X: 20% narrower, Y: 20% taller, Z: 20% thinner
  m = Mat4.mul(m, Mat4.scale(0.8, 1.15, 0.8))
  local ok = pcall(Voxel3D.draw, body.mesh, body.image, m)
  if ok then Npc.stats.drawn = Npc.stats.drawn + 1 end
  return ok
end

-- ------------------------------------------------------------ Gen 1-3 API --

-- Runaway guard: records are keyed by the live picture, so a sheet handed back
-- as a NEW image every frame would be a new record (and new builds) every
-- frame. Past FUSE_LIMIT new records in FUSE_WINDOW seconds the Gen 1-3 path
-- rests for FUSE_REST seconds and the cards draw.
local FUSE_WINDOW, FUSE_LIMIT, FUSE_REST = 2.0, 60, 30.0
local fuseStart, fuseCount, offUntil = 0, 0, 0

local function fuseTrips(now)
  if now - fuseStart > FUSE_WINDOW then fuseStart, fuseCount = now, 0 end
  fuseCount = fuseCount + 1
  if fuseCount > FUSE_LIMIT then
    offUntil = now + FUSE_REST
    fuseStart, fuseCount = now, 0
    log("sheets keep changing under the bodies; NPC 3D rests for %d s", FUSE_REST)
    return true
  end
  return false
end

local function classicRec(def, tex)
  local rec = crecs[tex]
  if rec then return rec end
  if fuseTrips(clock()) then return nil end
  rec = { kind = "classic", def = def, img = tex, bodies = {}, ok = false, state = nil }
  local frames = tonumber(def.frames) or 1
  local okD, iw, ih = pcall(tex.getDimensions, tex)
  if okD and frames > 1 and iw and ih and ih % frames == 0 then
    local cw, ch = iw, ih / frames
    if cw >= 8 and ch >= 8 and cw <= Npc.MAX_CELL and ch <= Npc.MAX_CELL then
      rec.ok, rec.cw, rec.ch, rec.frames = true, cw, ch, frames
    end
  end
  if not rec.ok then rec.img = nil end
  crecs[tex] = rec
  return rec
end

-- Is this posed entity one for a Gen 1-3 body? Cheap enough for every card
-- every frame; the setting is the first thing it looks at.
function Npc.classicWants(p)
  diagTick()
  if not Npc.enabled() then return no("want:setting-off") end
  if clock() < offUntil then return no("want:fuse-resting") end
  if type(p) ~= "table" then return no("want:no-pose") end
  local sprite, e = p.sprite, p.entity
  if type(sprite) ~= "table" then return no("want:no-sprite") end
  if type(e) ~= "table" then return no("want:no-entity") end
  local def = sprite.def
  if type(def) ~= "table" then return no("want:no-def") end
  if def.facings then return no("want:def-has-facings") end         -- Gen 4 has its own path
  if (tonumber(def.frames) or 1) <= 1 then return no("want:prop-1-frame") end
  if def.hdImage or def.hdDex or def.dsSpecies or def.hdFrameW or def.hdFrameH then return no("want:hd-or-pokemon") end
  if e.hidden or e.fixedFrame then return no("want:hidden-or-fixed") end
  if p.isFollower or e.isFollower or e.wildsFollower or e._wildsFollowerSpecies
     or e.roamer or e.overworldWildSpawn or e.species or e.stadiumModel then
    return no("want:follower-or-wild")
  end
  if p.isPlayer and not Npc.includePlayer then return no("want:player-off") end
  if (p.waterline or 0) > 0 then return no("want:waterline") end
  return true
end

-- The body this pose wears, or nil. While the exact pose is still building the
-- sheet's finished stand body stands in.
-- `build` is false for the sun pass: a shadow never starts a body (the eye pass
-- is what asks for one), so a caster outside the view costs nothing.
local function classicBody(p, tex, build)
  local def = p.sprite.def
  local rec = classicRec(def, tex)
  if not rec then return no("body:fuse-or-no-record") end
  if not rec.ok then return no("body:sheet-not-a-person-sheet") end
  if rec.state == nil then
    if build == false then return no("body:sheet-not-started-by-shadow") end
    if #queue >= Npc.MAX_QUEUE then return no("body:queue-full") end   -- never let a crowd flood the queue
    rec.state = "loading"
    queue[#queue + 1] = { kind = "sheet", rec = rec }
    return no("body:sheet-queued")
  end
  if rec.state == "failed" then return no("body:sheet-failed") end
  if rec.state ~= "ready" then return no("body:sheet-loading") end

  local d, u, l, m = classicFrames(def, rec.frames, p.phase, p.flip)
  local key = classicKey(d, u, l, m)
  local body = rec.bodies[key]
  if not body and build ~= false and #queue < Npc.MAX_QUEUE then
    body = startClassicBody(rec, key, { d = d, u = u, l = l, m = m })
  end
  if body then
    body.used = frameNo
    if body.mesh and body.image then return body, rec end
  end
  local stand = rec.standKey and rec.bodies[rec.standKey]
  if stand and stand.mesh and stand.image then
    stand.used = frameNo
    return stand, rec
  end
  for _, b in pairs(rec.bodies) do
    if b.mesh and b.image then b.used = frameNo; return b, rec end
  end
  return no("body:building")
end

-- Where the body stands: the middle of the cell the card is centred on, at the
-- entity's ground height (plus any hop), turned to its facing and scaled the
-- way the card is (def.scale / def.heightScale).
local function classicMatrix(p, rec, yaw)
  local Mat4 = lazy("Mat4")
  if not Mat4 then return nil end
  local def = rec.def
  local sc = tonumber(def.scale) or 1
  local hs = tonumber(def.heightScale) or sc
  local half = rec.cw * sc / 2
  local m = Mat4.translate((p.px or 0) + half, (p.gh or 0) + (p.lift or 0), (p.py or 0) + half)
  if yaw ~= 0 then m = Mat4.mul(m, Mat4.rotateY(yaw)) end
  -- X: 20% narrower, Y: 20% taller, Z: 20% thinner
  local xScale = sc * 0.8
  local yScale = hs * 1
  local zScale = sc * 0.7
  m = Mat4.mul(m, Mat4.scale(xScale, yScale, zScale))
  return m
end

-- Draw one posed entity as a body. `tex` is the image its card would wear
-- (palette bake and all), `pull` the camera-ward depth bias the card gets.
-- True only when a body was drawn; false leaves the card.
function Npc.drawClassic(p, tex, pull)
  diagTick()
  if not tex then return no("draw:no-texture") end
  local body, rec = classicBody(p, tex)
  if not body then return false end
  local Voxel3D = lazy("Voxel3D")
  if not Voxel3D then return no("draw:no-Voxel3D") end
  local m = classicMatrix(p, rec, yawFor(p.entity, p.facing, p.isPlayer, p.px, p.py))
  if not m then return no("draw:no-matrix") end
  local ok, err = pcall(Voxel3D.draw, body.mesh, body.image, m, pull or 0)
  if ok then
    Npc.stats.drawn = Npc.stats.drawn + 1
    Npc.why["draw:ok"] = (Npc.why["draw:ok"] or 0) + 1
    diagDirty = true
  else
    no("draw:error " .. tostring(err))
  end
  return ok
end

-- The same body into the sun's map, at the yaw it is GOING to (not the eased
-- one), so a turn leaves no stale shadow: the shadow map is only redrawn when
-- a pose changes.
function Npc.castClassic(p, tex, ShadowMap)
  if not (tex and ShadowMap and ShadowMap.draw) then return false end
  local body, rec = classicBody(p, tex, false)
  if not body then return false end
  local m = classicMatrix(p, rec, yawTarget(p.entity, p.facing, p.isPlayer, p.px, p.py))
  if not m then return false end
  return pcall(ShadowMap.draw, body.mesh, body.image, m)
end

-- Changes whenever what a body draws could differ (a body finished, was
-- evicted, the sheets were dropped, the setting flipped): part of the sun
-- pass's stamp, so a shadow is redrawn from the body the moment there is one.
function Npc.revision()
  return revision * 2 + (Npc.enabled() and 1 or 0)
end

-- Drop every mesh, sheet and queued job (graphics reset, mod reload, cache
-- reset). Bodies rebuild on demand.
function Npc.invalidate()
  for _, rec in pairs(recs) do
    for _, body in pairs(rec.bodies) do release(body) end
  end
  for _, rec in pairs(crecs) do
    for _, body in pairs(rec.bodies) do release(body) end
  end
  for k in pairs(recs) do recs[k] = nil end
  for k in pairs(crecs) do crecs[k] = nil end
  for i = #queue, 1, -1 do queue[i] = nil end
  reported = {}
  revision = revision + 1
end

function Npc.install()
  if Npc.installed then return true end
  Npc.installed = true
  do
    local log = V.mod and V.mod.log
    if log and log.info then
      pcall(log.info, log, "Gen4NpcModels installed (NPC 3D setting: %s)",
            tostring(Npc.setting and Npc.setting:get() or "no setting object"))
    end
  end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and type(Assets.register) == "function" then
    pcall(Assets.register, Npc.invalidate)   -- a mod swapping a sheet rebuilds its body
  end
  return true
end

-- test / diagnostics
Npc._recOf, Npc._framesFor, Npc._predictSprite, Npc._queue = recOf, framesFor, predictSprite, queue
Npc._classicFrames, Npc._classicKey, Npc._cellBytes = classicFrames, classicKey, cellBytes
Npc._makeClassicJob = makeClassicJob
function Npc.pending() return #queue end

return Npc