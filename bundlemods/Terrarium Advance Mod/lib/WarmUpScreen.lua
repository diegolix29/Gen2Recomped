-- WARM-UP: the loading screen after CONTINUE.
--
-- Everything this mod builds lazily -- the voxel terrain of the current map
-- and its neighbours, Gen 4/5's water / sand / trees / grass meshes, the
-- battle arena, trainer and party models ResidentPrewarm trickles in one row
-- every quarter second -- used to be paid in the first minute of play, as
-- hitches. This screen pays it up front, behind an animated loader, and hands
-- the game over once the work is actually done.
--
-- Pushed from the mod's own save.loaded handler (main.lua), so it is on the
-- stack before the first frame of the loaded world is drawn. The engine is
-- not touched: this is an ordinary pushed state, like StadiumScreen.
--
-- THE WORLD STILL DRAWS UNDER IT. `isOpaque` stays false and the screen
-- paints its own plate over the frame, because half of the lazy work happens
-- in the DRAW path (Gen4Bridge's effect meshes, shader first-use, the voxel
-- scene's aux meshes) and an opaque state would starve exactly that.
-- `coversWorld` tells the builders the world is hidden all the same:
-- ChunkMesher's covered slice (sized by `ChunkMesher.coveredSlice`) and
-- Gen4Bridge's covered budget both read it.
--
-- Two phases. WARM runs every load (the area around the player, seconds).
-- BAKE is one-time disk work (every map's voxel body baked to the disk cache;
-- an ORAS bake already in progress) -- B there means "play now", and the bake
-- carries on in the background exactly as it does from the options rows.
--
-- FINISHED BY FRAMES as well as time: a builder counts as done only after
-- several consecutive quiet frames, and the warm phase's give-up needs both
-- 25 seconds and 900 frames, so a phone stutter can neither end it early nor
-- hold it forever.

local V = ...

local W = {}

local clock = (love and love.timer and love.timer.getTime) or os.clock

-- Set POKEPORT_NO_WARMUP (or W.enabled = false) to skip the screen.
W.enabled = not os.getenv("POKEPORT_NO_WARMUP")

local WARM_TIMEOUT_S = 25
local WARM_TIMEOUT_FRAMES = 900
local FADE_FRAMES = 12
local QUIET_FRAMES = 3

local function log(fmt, ...)
  local m = V.mod and V.mod.log
  if m and m.info then pcall(m.info, m, "warm-up: " .. fmt, ...) end
end

local function engineGame()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game or nil
end

local function vreq(name)
  local ok, m = pcall(V.require, name)
  if ok and type(m) == "table" then return m end
  return nil
end

-- --------------------------------------------------------------- tasks

-- Gen 1-3 voxel terrain: the current map and its rendered neighbours. The
-- pipeline's update hook already prefetches and pumps the mesher every frame
-- (with the covered slice while this is on top); this waits for it to drain.
local function terrainTask()
  local st
  return {
    id = "terrain", label = "BUILDING TERRAIN", phase = "warm", order = 10,
    applies = function()
      local Voxel = vreq("VoxelState")
      if not (Voxel and Voxel.active and Voxel.active()) then return false end
      local Host = vreq("Gen4WorldHost")
      if Host and Host.isNativeWorld and Host.isNativeWorld() then return false end
      return true
    end,
    begin = function(game)
      st = { frames = 0, quiet = 0, peak = 0, pending = 0 }
      local ow = game and game.overworld
      local VoxelScene = vreq("VoxelScene")
      if VoxelScene and ow and ow.map and ow.camera then pcall(VoxelScene.prefetch, ow) end
    end,
    pump = function()
      local CM = vreq("ChunkMesher")
      if not (st and CM) then return true end
      st.frames = st.frames + 1
      local pending = CM.pending and CM.pending() or 0
      if pending > st.peak then st.peak = pending end
      st.pending = pending
      if pending == 0 then st.quiet = st.quiet + 1 else st.quiet = 0 end
      return st.frames >= 4 and st.quiet >= QUIET_FRAMES
    end,
    progress = function()
      if not st or st.peak == 0 then return nil end
      return st.peak - st.pending, st.peak
    end,
  }
end

-- Gen 4/5: the mod's own effect meshes over the native world. They build in
-- the draw path under Gen4Budget, which counts frames without a build in
-- `idle`; ten quiet drawn frames means the window around the player is full.
local function gen4Task()
  local st
  return {
    id = "gen4fx", label = "BUILDING EFFECTS", phase = "warm", order = 20,
    applies = function()
      local Host = vreq("Gen4WorldHost")
      return Host ~= nil and Host.isNativeWorld and Host.isNativeWorld()
        and Host.effectsOn and Host.effectsOn() and Host.groundOf and Host.groundOf() ~= nil
        or false
    end,
    begin = function()
      local B = vreq("Gen4Budget")
      st = { frames = 0, start = B and B.total or 0 }
    end,
    pump = function()
      local B = vreq("Gen4Budget")
      if not (st and B) then return true end
      st.frames = st.frames + 1
      st.built = (B.total or 0) - st.start
      return st.frames >= 6 and (B.idle or 0) >= 10
    end,
    progress = function() return nil end,
  }
end

-- Battle models: ResidentPrewarm's startup queue (arena, player trainer,
-- likely enemy trainers, the party's bodies, move FX, shaders), drained back
-- to back instead of one row per quarter second.
local function battleTask()
  local st
  -- the Colosseum runtime's own instance (main.lua publishes it on V); never
  -- V.require'd here, which would load a second copy without its namespace
  local function RP() return V.ResidentPrewarm end
  return {
    id = "battle", label = "BATTLE MODELS", phase = "warm", order = 30,
    applies = function()
      local R = RP()
      return R ~= nil and type(R.pumpNow) == "function" and type(R.status) == "function"
    end,
    begin = function(game)
      local R = RP()
      st = { peak = 0, pending = 0 }
      -- game.ready queued this BEFORE the save was read (CONTINUE emits it
      -- first), so its party is the title's. Queue again for the real one --
      -- unless an explicit disk bake owns the queue.
      local busy = R.hardCacheRunning and R.hardCacheRunning()
      if not busy and R.queueStartup then pcall(R.queueStartup, game) end
    end,
    pump = function(seconds, game)
      local R = RP()
      if not (st and R) then return true end
      local okP, left = pcall(R.pumpNow, game, seconds)
      if not okP then return true end
      left = tonumber(left) or 0
      if left > st.peak then st.peak = left end
      st.pending = left
      return left == 0
    end,
    progress = function()
      if not st or st.peak == 0 then return nil end
      return st.peak - st.pending, st.peak
    end,
  }
end

-- Every map in the game, stable order (the prebake's queue).
local function allMapIds()
  local Game = engineGame()
  local maps = Game and Game.data and Game.data.maps
  if type(maps) ~= "table" then return {} end
  local ids = {}
  for id, def in pairs(maps) do
    if type(def) == "table" then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  return ids
end

-- A throwaway Map per id (the resident one when it is loaded): geometry reads
-- the def, the tileset and the tile pins and nothing else.
local function bakeMapFor(id)
  local Game = engineGame()
  local okMap, Map = pcall(require, "src.world.Map")
  if not (Game and Game.data and okMap) then return nil, "engine map data unavailable" end
  local okLoader, MapLoader = pcall(require, "src.world.MapLoader")
  if not okLoader then MapLoader = nil end
  if MapLoader and type(MapLoader.cached) == "function" then
    local okHit, hit = pcall(MapLoader.cached, id)
    if okHit and type(hit) == "table" then return hit end
  end
  local def = Game.data.maps and Game.data.maps[id]
  if not def then return nil, "no map def" end
  local ts
  if MapLoader and type(MapLoader.tilesetFor) == "function" then
    ts = MapLoader.tilesetFor(Game.data, def)
  else
    ts = Game.data.tilesets and Game.data.tilesets[def.tileset]
  end
  if not ts then return nil, "no tileset for " .. tostring(def.tileset) end
  local built, mapOrErr = pcall(Map.new, def, ts)
  if not built or type(mapOrErr) ~= "table" then
    return nil, "Map.new failed: " .. tostring(mapOrErr)
  end
  return mapOrErr
end

local MARKER_DIR = "terrarium_warmup"

local function markerPath()
  local okV, GV = pcall(require, "src.core.GameVersion")
  local ver = okV and GV and GV.get and tostring(GV.get() or "unknown") or "unknown"
  return MARKER_DIR .. "/voxel_prebake_" .. ver:gsub("[^%w_%-]", "_") .. ".txt"
end

local function signature(count)
  local CM = vreq("ChunkMesher")
  local DC = vreq("VoxelDiskCache")
  local status = CM and CM.cacheStatus and CM.cacheStatus() or {}
  return table.concat({
    tostring(status.revision or "?"),
    tostring(DC and DC.rulesTag or ""),
    tostring(count or #allMapIds()),
  }, "|")
end

local function markerCurrent()
  local fs = love and love.filesystem
  if not (fs and fs.getInfo) then return false end
  local path = markerPath()
  if not fs.getInfo(path) then return false end
  local ok, text = pcall(fs.read, path)
  return ok and type(text) == "string" and text == signature()
end

local markerWritten = false
function W.noteBakeFinished()
  if markerWritten then return end
  local P = vreq("VoxelPrebake")
  local s = P and P.summary and P.summary()
  if not (s and (s.total or 0) > 0 and (s.done or 0) >= s.total) then return end
  markerWritten = true
  local fs = love and love.filesystem
  if fs and fs.write then
    pcall(fs.createDirectory, MARKER_DIR)
    pcall(fs.write, markerPath(), signature(s.total))
  end
  log("voxel prebake complete: %d maps (%d baked, %d cached, %d failed)",
      s.total or 0, s.baked or 0, s.cached or 0, s.failed or 0)
end

-- Behind play, after a skip: the bake keeps draining in quiet frames.
local backgroundBake = false
function W.pumpBackground()
  if not backgroundBake then return end
  local P = vreq("VoxelPrebake")
  local CM = vreq("ChunkMesher")
  if not P then backgroundBake = false return end
  if not P.running() then backgroundBake = false; W.noteBakeFinished() return end
  local Game = engineGame()
  if not (Game and Game.stack and Game.stack:top() == Game.overworld) then return end
  if CM and CM.pending and CM.pending() > 0 then return end
  local dt = (love and love.timer and love.timer.getDelta and love.timer.getDelta()) or (1 / 60)
  local spent = CM and CM.lastSlice and CM.lastSlice() or 0
  local headroom = (1 / 60) - math.max(0, dt - spent)
  if headroom <= 0 then headroom = 0.0015 end
  pcall(P.pump, math.min(0.004, headroom * 0.5))
  if not P.running() then backgroundBake = false; W.noteBakeFinished() end
end

-- One-time: every map's voxel body baked to the disk cache.
local function prebakeTask()
  return {
    id = "prebake", label = "FIRST-TIME WORLD BAKE", phase = "bake", order = 10,
    applies = function()
      local P = vreq("VoxelPrebake")
      local CM = vreq("ChunkMesher")
      local Voxel = vreq("VoxelState")
      if not (P and CM and Voxel and Voxel.active and Voxel.active()) then return false end
      local Host = vreq("Gen4WorldHost")
      if Host and Host.isNativeWorld and Host.isNativeWorld() then return false end
      if CM.diskCacheEnabled and not CM.diskCacheEnabled() then return false end
      if P.running() then return true end
      return not markerCurrent()
    end,
    begin = function()
      local P = vreq("VoxelPrebake")
      if P.running() then return end
      local ids = allMapIds()
      if #ids > 0 then
        markerWritten = false
        P.begin(ids, bakeMapFor)
      end
    end,
    pump = function(seconds)
      local P = vreq("VoxelPrebake")
      local CM = vreq("ChunkMesher")
      if not (P and P.running()) then W.noteBakeFinished() return true end
      if CM and CM.pending and CM.pending() > 0 then return false end
      pcall(P.pump, seconds or 0.006)
      if not P.running() then W.noteBakeFinished() return true end
      return false
    end,
    progress = function()
      local P = vreq("VoxelPrebake")
      local ok, p = pcall(P.progress)
      if ok and type(p) == "table" and (p.total or 0) > 0 then return p.done, p.total end
      return nil
    end,
    onSkip = function() backgroundBake = true end,
  }
end

-- An ORAS bake the player already started (its own OPTIONS rows) is shown
-- while it finishes; its pump is the update hook's, which keeps running.
-- Its own task, never folded into anything Colosseum's.
local ORAS_MODULES = { "ORASModels", "ORASEffects", "ORASArenas", "ORASTrainers" }
local function orasRunning()
  for _, name in ipairs(ORAS_MODULES) do
    local m = vreq(name)
    if m and m.running then
      local ok, on = pcall(m.running)
      if ok and on then return true end
    end
  end
  return false
end

local function orasTask()
  local st
  return {
    id = "oras", label = "ORAS BAKE", phase = "bake", order = 20,
    applies = orasRunning,
    begin = function() st = { quiet = 0 } end,
    pump = function()
      if orasRunning() then st.quiet = 0 return false end
      st.quiet = st.quiet + 1
      return st.quiet >= QUIET_FRAMES
    end,
    progress = function() return nil end,
  }
end

local function collect(game)
  local list = {}
  for _, make in ipairs({ terrainTask, gen4Task, battleTask, prebakeTask, orasTask }) do
    local task = make()
    local ok, yes = pcall(task.applies, game)
    if ok and yes then list[#list + 1] = task
    elseif not ok then log("%s: applies raised (%s); skipped", task.id, tostring(yes)) end
  end
  table.sort(list, function(a, b)
    local pa, pb = a.phase == "bake" and 1 or 0, b.phase == "bake" and 1 or 0
    if pa ~= pb then return pa < pb end
    return (a.order or 50) < (b.order or 50)
  end)
  return list
end
W._collect = collect

-- --------------------------------------------------------------- the state

local Screen = {}
Screen.__index = Screen
W.Screen = Screen

local function frameBudget()
  local ok, FC = pcall(require, "src.core.FrameCap")
  local cap = ok and FC and tonumber(FC.current) or 60
  if not cap or cap <= 0 then cap = 60 end
  return math.max(0.004, (1 / cap) * 0.45)
end

function Screen.new(game, tasks)
  local self = setmetatable({
    game = game, tasks = tasks or {}, at = 1, begun = {},
    t = 0, phaseFrames = 0, phaseStarted = clock(),
    fade = nil, finished = false, drawn = false, shown = nil,
  }, Screen)
  -- see the header: the world keeps drawing under the plate
  self.isOpaque = false
  self.coversWorld = true
  self.buildSlice = frameBudget()
  return self
end

function Screen:current() return self.tasks[self.at] end

local function call(task, name, ...)
  local fn = task and task[name]
  if type(fn) ~= "function" then return true end
  return pcall(fn, ...)
end

function Screen:advance()
  local prev = self:current()
  self.at = self.at + 1
  local nxt = self:current()
  if nxt and prev and nxt.phase ~= prev.phase then
    self.phaseFrames, self.phaseStarted = 0, clock()
  end
end

function Screen:handOver(reason)
  for i = self.at, #self.tasks do
    local task = self.tasks[i]
    if self.begun[task] then
      local ok, err = call(task, "onSkip", self.game)
      if not ok then log("%s: onSkip raised (%s)", task.id, tostring(err)) end
    end
  end
  if reason then log("handed over (%s)", reason) end
  self.at = #self.tasks + 1
end

local function setCovered(slice)
  local CM = vreq("ChunkMesher")
  if CM then CM.coveredSlice = slice end
end

function Screen:finish()
  if self.finished then return end
  self.finished = true
  self.coversWorld = false
  setCovered(nil)
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

function Screen:exit() setCovered(nil) end

function Screen:work()
  local budget = frameBudget()
  self.buildSlice = budget
  setCovered(budget)
  local deadline = clock() + budget
  local pumped = false
  while self:current() and (not pumped or clock() < deadline) do
    local task = self:current()
    local skip = false
    if not self.begun[task] then
      self.begun[task] = true
      local ok, err = call(task, "begin", self.game)
      if not ok then
        log("%s: begin raised (%s); skipped", task.id, tostring(err))
        skip = true
      end
    end
    if skip then
      self:advance()
    else
      local ok, done = pcall(task.pump, math.max(0.001, deadline - clock()), self.game)
      pumped = true
      if not ok then
        log("%s: pump raised (%s); skipped", task.id, tostring(done))
        self:advance()
      elseif done then
        self:advance()
      else
        break
      end
    end
  end
end

function Screen:update(dt)
  dt = tonumber(dt) or (1 / 60)
  self.t = self.t + dt
  if self.fade then
    self.fade = self.fade + 1
    if self.fade >= FADE_FRAMES then self:finish() end
    return
  end
  local input = self.game and self.game.input
  if input and input.wasPressed and (input:wasPressed("b") or input:wasPressed("start")) then
    self:handOver("skipped by the player")
  end
  if self:current() then
    self:work()
    self.phaseFrames = self.phaseFrames + 1
    local task = self:current()
    if task and task.phase ~= "bake"
       and self.phaseFrames >= WARM_TIMEOUT_FRAMES
       and clock() - self.phaseStarted >= WARM_TIMEOUT_S then
      self:handOver("timed out; the rest builds in the background")
    end
  end
  if not self:current() then
    if not self.drawn then return self:finish() end
    self.fade = 0
    self.coversWorld = false
    setCovered(nil)
  end
end

function Screen:progress()
  local n = #self.tasks
  if n == 0 then return 1 end
  local whole = math.min(n, self.at - 1)
  local part = 0
  local task = self:current()
  if task and task.progress then
    local ok, d, tot = pcall(task.progress)
    if ok and tonumber(d) and tonumber(tot) and tot > 0 then
      part = math.max(0, math.min(1, d / tot))
    end
  end
  return (whole + part) / n
end

-- ------------------------------------------------------------- drawing

local Font
local function font()
  if Font == nil then
    local ok, F = pcall(require, "src.render.Font")
    Font = ok and F or false
  end
  return Font or nil
end

-- the cartridge fonts are black on transparent: everything is dark on light
local function text(str, x, y, a)
  local F = font()
  if not F then return end
  love.graphics.setColor(0, 0, 0, a or 1)
  pcall(F.draw, str, math.floor(x), math.floor(y))
end

local function width(str)
  local F = font()
  local ok, w = pcall(function() return F and F.width(str) end)
  return (ok and tonumber(w)) or #str * 8
end

local iconCache = {}
local function image(path)
  if not path then return nil end
  if iconCache[path] == nil then
    local ok, img = pcall(require("src.render.Assets").image, path)
    iconCache[path] = ok and img or false
  end
  return iconCache[path] or nil
end

-- the lead Pokemon's party icon, resolved the way the party menus do
local function leadIcon(game)
  local save, data = game and game.save, game and game.data
  local party = save and save.party
  if not (data and type(party) == "table") then return nil end
  local mon
  for _, m in ipairs(party) do
    if type(m) == "table" and m.species and not m.isEgg then mon = m break end
  end
  if not mon then return nil end
  local icons = data.icons
  local def = data.pokemon and data.pokemon[mon.species]
  local entry = (icons and icons.bySpecies and icons.bySpecies[mon.species]) or (def and def.icon)
  local path, fh
  if type(entry) == "table" then path, fh = entry.image, tonumber(entry.frameHeight)
  elseif type(entry) == "string" then path = entry end
  local okHook, hooked = pcall(function()
    return require("src.pokemon.Sprites").iconPath(data, nil, path, {})
  end)
  if okHook and type(hooked) == "string" then path = hooked end
  local img = image(path)
  if not img then return nil end
  local iw, ih = img:getDimensions()
  fh = math.min(fh or tonumber(icons and icons.frameHeight) or 32, ih)
  if fh <= 0 then return nil end
  return img, iw, fh, math.max(1, math.floor(ih / fh))
end

local DARK = { 0.06, 0.05, 0.09 }
local PLATE = { 0.93, 0.94, 0.90 }

local function drawBall(cx, cy, r, angle, a)
  local g = love.graphics
  g.push()
  g.translate(cx, cy)
  g.rotate(angle)
  g.setColor(DARK[1], DARK[2], DARK[3], a)
  g.arc("fill", 0, 0, r, math.pi, 2 * math.pi)
  g.setColor(PLATE[1], PLATE[2], PLATE[3], a)
  g.arc("fill", 0, 0, r, 0, math.pi)
  g.setColor(DARK[1], DARK[2], DARK[3], a)
  g.setLineWidth(1)
  g.circle("line", 0, 0, r)
  g.line(-r, 0, r, 0)
  g.setColor(PLATE[1], PLATE[2], PLATE[3], a)
  g.circle("fill", 0, 0, math.max(1.5, r * 0.32))
  g.setColor(DARK[1], DARK[2], DARK[3], a)
  g.circle("line", 0, 0, math.max(1.5, r * 0.32))
  g.pop()
end

function Screen:draw()
  self.drawn = true
  local g = love.graphics
  local okR, Renderer = pcall(require, "src.render.Renderer")
  local SW, SH = 160, 144
  if okR and Renderer and Renderer.uiSize then
    local ok, w, h = pcall(Renderer.uiSize, Renderer)
    if ok and w and h then SW, SH = w, h end
  end
  local a = 1
  if self.fade then a = 1 - self.fade / FADE_FRAMES end
  local t = self.t

  g.push("all")
  -- the plate, a little past every edge, and slow bands drifting across it
  g.setColor(PLATE[1], PLATE[2], PLATE[3], a)
  g.rectangle("fill", -SW, -SH, SW * 3, SH * 3)
  g.setColor(0.86, 0.88, 0.82, a)
  local band = 24
  local shift = (t * 10) % (band * 2)
  for x = -SH - band * 2, SW + band * 2, band * 2 do
    local x0 = x + shift
    g.polygon("fill", x0, 0, x0 + band, 0, x0 + band - SH, SH, x0 - SH, SH)
  end

  -- the bar: a dark frame, a plate-coloured track and a dark fill (a grey
  -- track lands one Game Boy shade down and reads backwards -- StadiumScreen)
  local p = self:progress()
  self.shown = self.shown and (self.shown + (p - self.shown) * 0.15) or p
  local bw = math.floor(SW * 0.7)
  local bh = 7
  local bx = math.floor((SW - bw) / 2)
  local by = math.floor(SH * 0.58)
  g.setColor(DARK[1], DARK[2], DARK[3], a)
  g.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
  g.setColor(PLATE[1], PLATE[2], PLATE[3], a)
  g.rectangle("fill", bx, by, bw, bh)
  g.setColor(DARK[1], DARK[2], DARK[3], a)
  g.rectangle("fill", bx, by, math.floor(bw * self.shown + 0.5), bh)

  -- the lead Pokemon trots along the bar; a rolling Poke Ball without icons
  local rx = bx + bw * self.shown
  local img, iw, fh, frames = leadIcon(self.game)
  if img then
    local frame = math.floor(t / 0.16) % frames
    local hop = math.abs(math.sin(t * 7)) * 3
    self.quad = self.quad or g.newQuad(0, 0, iw, fh, img:getDimensions())
    self.quad:setViewport(0, frame * fh, iw, fh, img:getDimensions())
    g.setColor(1, 1, 1, a)
    g.draw(img, self.quad, math.floor(rx - iw / 2), math.floor(by - fh - hop + 3))
  else
    local r = 6
    drawBall(rx, by - r - 2 - math.abs(math.sin(t * 6)) * 2, r, t * 6, a)
  end

  local dots = string.rep(".", math.floor(t * 3) % 4)
  text("LOADING" .. dots, (SW - width("LOADING...")) / 2, math.floor(SH * 0.22), a)
  local task = self:current()
  if task then
    local label = task.label or task.id
    local ok, d, tot = pcall(task.progress or function() end)
    if ok and tonumber(d) and tonumber(tot) and tot > 0 then
      label = ("%s %d/%d"):format(label, d, tot)
    end
    text(label, (SW - width(label)) / 2, by + bh + 7, a)
    local hint = task.phase == "bake" and "B: PLAY NOW" or "B: SKIP"
    text(hint, (SW - width(hint)) / 2, SH - 14, a * (0.45 + 0.55 * math.abs(math.sin(t * 2))))
  end
  g.pop()
end

-- --------------------------------------------------------------- entry

-- From the mod's save.loaded handler: push the screen if this load has work.
function W.onSaveLoaded()
  if not W.enabled then return false end
  local Game = engineGame()
  if not (Game and Game.stack and Game.overworld) then return false end
  local list = collect(Game)
  if #list == 0 then return false end
  Game.stack:push(Screen.new(Game, list))
  log("%d task(s) after continue", #list)
  return true
end

return W
