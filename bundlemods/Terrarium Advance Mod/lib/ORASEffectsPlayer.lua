-- Plays baked ORAS move effects (lib/ORASEffects.lua) in a battle.
--
--   local id = Player.start(moveId, host, space) -- false when the move has none
--   Player.update()                               -- any number of times a frame
--   Player.draw(project, space)                   -- after the actors
--
-- space: which projection the run's host positions belong to -- "csm" (the
-- Colosseum battle screen, lib/CurrentSpriteModels.lua) or "scene" (3D-BTL,
-- lib/ORASEffectsScene.lua).  Each draw call draws only its own space.
-- Time is the wall clock, so it does not matter who calls update or how often
-- (main.lua's always-on tick does, through ORASEffects.pump).
--
-- host (supplied by the battle compositor):
--   point(role, slot)  world position of "attacker" / "defender" body slot
--                      ("mouth", "center", ...), or nil
--   forward()          unit vector from attacker toward defender (world)
--   unit()             world units per ORAS unit (centimetre), from an ORAS
--                      actor's scale; effects are authored at real size
-- project(x, y, z) -> screen x, y (the battle's actor projection)
--
-- Timeline: each particle file starts at its record's start frame and stops
-- emitting at its end frame; the move is over when all have spawned and died.
-- Effect space: +Y up, +Z toward the target, origin at the anchor slot.

local V = ...

local Player = {}

local FPS = 30
local MAX_ACTIVE = 4

local active = {}          -- running moves
local fxMemo = {}          -- member -> compact fx (or false)
local images = {}          -- texture key -> love Image (or false)
local serial = 0
Player.lastError = nil

-- what happened lately, for the F12 report (lib/RenderDump.lua)
local events = {}
local function clockNow()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
function Player.note(fmt, ...)
  local ok, line = pcall(string.format, fmt, ...)
  events[#events + 1] = { t = clockNow(), text = ok and line or tostring(fmt) }
  while #events > 40 do table.remove(events, 1) end
end

local function Effects() return V.require("ORASEffects") end
local function Sim() return V.require("ORASParticleSim") end

local function loadFx(m)
  local f = fxMemo[m]
  if f == nil then
    f = Effects().readLua(("%s/fx/%d.lua"):format(Effects().ROOT, m)) or false
    fxMemo[m] = f
  end
  return f or nil
end

local modelMemo, uvMemo = {}, {}
local function loadModel(m)
  local d = modelMemo[m]
  if d == nil then
    d = Effects().readLua(("%s/models/%d.lua"):format(Effects().ROOT, m)) or false
    modelMemo[m] = d
  end
  return d or nil
end
local function loadUV(m)
  local d = uvMemo[m]
  if d == nil then
    d = Effects().readLua(("%s/uv/%d.lua"):format(Effects().ROOT, m)) or false
    uvMemo[m] = d
  end
  return d or nil
end
local motionMemo = {}
local function loadMotion(key)
  local d = motionMemo[key]
  if d == nil then
    d = Effects().readLua(("%s/motions/%s.lua"):format(Effects().ROOT, key)) or false
    motionMemo[key] = d
  end
  return d or nil
end
local function Models() return V.require("ORASEffectModels") end

local function image(key)
  local img = images[key]
  if img ~= nil then return img or nil end
  img = false
  local ok, bytes = pcall(Effects().readFile, Effects().ROOT .. "/tex/" .. key .. ".png")
  if ok and type(bytes) == "string" and love and love.graphics then
    local okI, data = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, key .. ".png"))
    end)
    if okI and data then
      local okG, gi = pcall(love.graphics.newImage, data)
      if okG and gi then gi:setFilter("linear", "linear"); img = gi end
    end
  end
  images[key] = img
  return img or nil
end

function Player.has(moveId)
  local idx = Effects().index()
  return idx ~= nil and idx.moves[tonumber(moveId) or -1] ~= nil
end

function Player.start(moveId, host, space)
  local E = Effects()
  if not E.active() then
    Player.note("move %s (%s): not started -- %s", tostring(moveId), tostring(space),
      E.built() and "ORAS FX IN BATTLE is OFF" or "effects not built")
    return false
  end
  local idx = E.index()
  local entry = idx and idx.moves[tonumber(moveId) or -1]
  if not entry then
    Player.note("move %s (%s): no ORAS effect for this move", tostring(moveId), tostring(space))
    return false
  end
  serial = serial + 1
  local run = { id = serial, move = tonumber(moveId), host = host, entry = entry, space = space or "csm",
                frame = -1, acc = 0, next = 1, live = {} }
  table.sort(entry.fx, function(a, b) return a[1] < b[1] end)
  if entry.models then
    table.sort(entry.models, function(a, b) return a[1] < b[1] end)
    run.models, run.nextModel = {}, 1
  end
  if entry.sprays then
    table.sort(entry.sprays, function(a, b) return a[1] < b[1] end)
    run.sprays, run.nextSpray = {}, 1
  end
  local Stage = V.require("ORASStage")
  if Stage.has(entry) then run.stageEnd = Stage.length(entry) end
  -- sound cues, in frame order; the run lives until the last one has played
  if entry.sounds and E.soundsActive and E.soundsActive() then
    table.sort(entry.sounds, function(a, b) return a[1] < b[1] end)
    run.soundsOn, run.nextSound = true, 1
    local last = entry.sounds[#entry.sounds][1]
    run.stageEnd = math.max(run.stageEnd or 0, last + 1)
  end
  -- the move lands at the timeline's damage cue (0x0C), else when its first
  -- target-side effect starts
  run.hitFrame = entry.hit
  for _, r in ipairs(run.hitFrame and {} or entry.fx) do
    local role = idx.members and idx.members[r[4]]
    if role == "defender" or (role == nil and r[3] == 1) then run.hitFrame = r[1]; break end
  end
  active[#active + 1] = run
  while #active > MAX_ACTIVE do table.remove(active, 1) end
  local sounds = entry.sounds and #entry.sounds or 0
  local soundNote = run.soundsOn and ("%d sound cues"):format(sounds)
    or (sounds > 0 and ("%d sound cues OFF (%s)"):format(sounds,
      (E.index() or {}).sounds ~= true and "not baked" or "ORAS FX SOUND is OFF"))
    or "no sounds"
  Player.note("move %d (%s): started, %d particle files, %d models, %d sprays, %d stage records, %s, lands at frame %s",
    run.move, run.space, #entry.fx, entry.models and #entry.models or 0, entry.sprays and #entry.sprays or 0,
    entry.stage and #entry.stage or 0, soundNote, tostring(run.hitFrame))
  return run.id
end

function Player.busy(space)
  if not space then return #active > 0 end
  for _, run in ipairs(active) do if run.space == space then return true end end
  return false
end

-- Seconds until the newest move's first target-side effect starts (its
-- impact), for holding the target's hit reaction; nil when the move has no
-- target-side effect or it has already started.
Player.HIT_WAIT_MAX = 4
function Player.hitWait()
  local run = active[#active]
  if not (run and run.hitFrame) then return nil end
  local left = (run.hitFrame - (run.frame + run.acc)) / FPS
  if left <= 0 then return nil end
  return math.min(left, Player.HIT_WAIT_MAX)
end
function Player.stopAll() active = {} end

-- ORAS body points (0x2F) -> our body-map slots.  0 feet (Thunder's sky
-- bolt: feet + 300 up), 2 mouth (Water Gun), 5 body centre (Tackle and
-- Thunder hits); the rest are best guesses.
local POINT_SLOT = { [0] = "origin", [2] = "mouth", [3] = "center", [4] = "chest",
  [5] = "center", [6] = "chest", [8] = "center", [15] = "eye_left", [16] = "eye_left" }

local function spawn(run, rec)
  local s, e, target, m = rec[1], rec[2], rec[3], rec[4]
  local fx = loadFx(m)
  if not fx then return end
  local role = (rec.role == 0 and "attacker") or (rec.role == 1 and "defender")
    or fx.role or (target == 1 and "defender" or "attacker")
  local slot = POINT_SLOT[rec.point or -1] or (role == "attacker" and "mouth" or "center")
  run.live[#run.live + 1] = {
    fx = fx, role = role, slot = slot,
    sim = Sim().new(fx, { seed = run.id * 977 + m }),
    stopAt = math.max(1, e - s + 1), age = 0,
    scales = rec.scale, off = rec.off, travel = rec.travel, point = rec.point,
    aim = rec.aim, rots = rec.rot,
  }
end

-- -------------------------------------------------------------------- sound
--
-- A move's sound cues (entry.sounds = { {frame, k, volume 0..127} }) play the
-- WAVs the bake rendered (oras/movefx/snd/<k>.wav).  Volume: the cue's own,
-- times OPTIONS -> ORAS FX SOUND, times the game's SFX row (save.options.sfxVol
-- 0..7, read every play, as the engine's own sounds do) and the engine's 0.8
-- base.

local soundData = {}       -- k -> love SoundData (or false)
local playing = {}         -- live sources, so they are not collected mid-play
Player.SOUND_BASE = 0.8

local function sfxScale()
  local okG, Game = pcall(require, "src.core.Game")
  local opts = okG and Game and Game.save and Game.save.options
  local level = tonumber(opts and opts.sfxVol) or 7
  return math.max(0, math.min(7, level)) / 7
end

local function soundFor(k)
  local d = soundData[k]
  if d ~= nil then return d or nil end
  d = false
  local ok, bytes = pcall(Effects().readFile, ("%s/snd/%d.wav"):format(Effects().ROOT, k))
  if ok and type(bytes) == "string" and love and love.sound then
    local okD, sd = pcall(function()
      return love.sound.newSoundData(love.filesystem.newFileData(bytes, k .. ".wav"))
    end)
    if okD and sd then d = sd end
  end
  soundData[k] = d
  return d or nil
end

-- Pan: -1 left .. 1 right; a mono source sits on a circle around the
-- listener (distance 1, so the engine's distance model leaves it at full
-- volume), PAN_ANGLE degrees off centre at the screen's edge.
Player.PAN_ANGLE = 70
local function placeSource(src, pan)
  local a = math.rad(math.max(-1, math.min(1, pan or 0)) * Player.PAN_ANGLE)
  pcall(src.setPosition, src, math.sin(a), 0, -math.cos(a))
end

function Player.playSound(k, vol, pan)
  if not (love and love.audio) then return false end
  local okL, level = pcall(function() return Effects().soundLevel() end)
  level = okL and tonumber(level) or 100
  local gain = (vol or 127) / 127 * level / 100 * sfxScale() * Player.SOUND_BASE
  if gain <= 0.001 then return false end
  local sd = soundFor(k)
  if not sd then Player.note("sound %s: snd/%s.wav could not be loaded", tostring(k), tostring(k)); return false end
  local ok, src = pcall(love.audio.newSource, sd, "static")
  if not (ok and src) then Player.note("sound %s: no audio source (%s)", tostring(k), tostring(src)); return false end
  pcall(src.setVolume, src, math.min(1, gain))
  -- Mono sources are placed in 3D, and lib/SpatialAudio.lua moves the
  -- listener to the player's map cell (world pixels, silent past 160): a
  -- source left at the origin was never heard. Glue it to the listener.
  -- Relative positions are in the listener's own frame (+x right, -z ahead).
  pcall(src.setRelative, src, true)
  pcall(src.setAttenuationDistances, src, 1, 1000)
  placeSource(src, pan)
  pcall(src.play, src)
  playing[#playing + 1] = src
  for i = #playing, 1, -1 do
    local okP, live = pcall(playing[i].isPlaying, playing[i])
    if not (okP and live) and playing[i] ~= src then table.remove(playing, i) end
  end
  return src
end

-- Screen side of a cue's owner (0x68 who: 0 attacker, 1 target, 2 between):
-- where the last draw saw that Pokemon (run.screenX), else the player's
-- Pokemon on the left and the foe on the right.
Player.DEFAULT_PAN = 0.5
local function panOf(run, who)
  if who == nil or who == 2 then
    local a, d = run.screenX and run.screenX.attacker, run.screenX and run.screenX.defender
    if who == 2 and a and d then return (a + d) / 2 end
    return 0
  end
  local role = who == 0 and "attacker" or "defender"
  local x = run.screenX and run.screenX[role]
  if x then return x end
  local side = run.host and run.host.attackerSide
  if side ~= "player" and side ~= "enemy" then return 0 end
  local attackerLeft = side == "player"
  local left = (role == "attacker") == attackerLeft
  return left and -Player.DEFAULT_PAN or Player.DEFAULT_PAN
end

-- an ORAS move with sounds is playing now (the cartridge's own move sound
-- stays quiet meanwhile, lib/ORASEffectsScene.lua)
-- Stays on for a short grace after the run, so late sound rows of the same
-- move (Colosseum's own timeline can run a little longer) stay quiet too.
Player.SOUND_GRACE = 1.5
local soundHoldUntil = 0
local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
function Player.soundBusy()
  for _, run in ipairs(active) do
    if run.soundsOn then return true end
  end
  return clock() < soundHoldUntil
end
-- Colosseum's move sound player (lib/WazaAudioRuntime.lua) asks this through
-- mod.exports, so ORAS never needs the Colosseum runtime to be loaded
if V and V.mod and V.mod.exports then V.mod.exports.orasSoundBusy = Player.soundBusy end

local function stepRun(run)
  run.frame = run.frame + 1
  if run.soundsOn then
    soundHoldUntil = clock() + Player.SOUND_GRACE
    local list = run.entry.sounds
    while run.nextSound <= #list and list[run.nextSound][1] <= run.frame do
      local cue = list[run.nextSound]
      local ok, src = pcall(Player.playSound, cue[2], cue[3], panOf(run, cue[4]))
      -- a timed 0x68: the sound flies to the other side over that span
      local tr = cue[5]
      if ok and src and type(tr) == "table" and (tonumber(tr[2]) or 0) > 0 then
        run.slides = run.slides or {}
        run.slides[#run.slides + 1] = { src = src, f0 = run.frame + tr[1], f1 = run.frame + tr[2],
                                         from = cue[4], to = tr[3] }
      end
      run.nextSound = run.nextSound + 1
    end
    for i = #(run.slides or {}), 1, -1 do
      local sl = run.slides[i]
      local t = (run.frame - sl.f0) / math.max(1, sl.f1 - sl.f0)
      t = math.max(0, math.min(1, t))
      local p0, p1 = panOf(run, sl.from), panOf(run, sl.to)
      placeSource(sl.src, p0 + (p1 - p0) * t)
      if t >= 1 then table.remove(run.slides, i) end
    end
  end
  local list = run.entry.fx
  while run.next <= #list and list[run.next][1] <= run.frame do
    spawn(run, list[run.next])
    run.next = run.next + 1
  end
  -- effect models: shown from their record's start to its end
  local mlist = run.entry.models
  if mlist then
    while run.nextModel <= #mlist and mlist[run.nextModel][1] <= run.frame do
      local it = mlist[run.nextModel]
      local data = loadModel(it[4])
      if data then
        local role = (it.role == 0 and "attacker") or (it.role == 1 and "defender")
          or (tostring(data.name):find("_at_") and "attacker") or "defender"
        run.models[#run.models + 1] = {
          item = it, data = data, uv = it.uv and loadUV(it.uv[2]) or nil, age = 0,
          motion = it.motion and loadMotion(it.motion[2] .. "_" .. it[4]) or nil,
          stopAt = math.max(1, it[2] - it[1] + 1), role = role,
          slot = POINT_SLOT[it.point or -1] or (role == "attacker" and "mouth" or "center"),
          off = it.off, travel = it.travel, aim = it.aim,
        }
      else
        Player.note("move %d: effect model %d not baked", run.move, it[4])
      end
      run.nextModel = run.nextModel + 1
    end
    for i = #run.models, 1, -1 do
      local lm = run.models[i]
      lm.age = lm.age + 1
      if lm.age >= lm.stopAt then table.remove(run.models, i) end
    end
  end
  local S = Sim()
  for i = #run.live, 1, -1 do
    local l = run.live[i]
    S.step(l.sim)
    l.age = l.age + 1
    -- the timeline's own scale for this effect (op 0x34), latest that applies
    if l.scales then
      for _, sc in ipairs(l.scales) do
        if sc[1] <= l.age then l.sx, l.sy, l.sz = sc[2], sc[3], sc[4] end
      end
    end
    if l.age >= l.stopAt then S.stopEmitting(l.sim) end
    if S.done(l.sim) or l.age > 600 then table.remove(run.live, i) end
  end
  -- model sprays (0x7B): copies launched, falling and bouncing
  local slist = run.entry.sprays
  if slist then
    local EM = Models()
    while run.nextSpray <= #slist and slist[run.nextSpray][1] <= run.frame do
      local it = slist[run.nextSpray]
      local data = loadModel(it[4])
      if data then
        local sp = EM.newSpray(it, data, it.uv and loadUV(it.uv[2]) or nil, run.id * 7919 + run.nextSpray)
        sp.role = (it.role == 0 and "attacker") or (it.role == 1 and "defender")
          or (tostring(data.name):find("_at_") and "attacker") or "defender"
        sp.slot = POINT_SLOT[it.point or -1] or "center"
        sp.off = it.off
        run.sprays[#run.sprays + 1] = sp
      else
        Player.note("move %d: spray model %d not baked", run.move, it[4])
      end
      run.nextSpray = run.nextSpray + 1
    end
    for i = #run.sprays, 1, -1 do
      local sp = run.sprays[i]
      if not EM.stepSpray(sp, sp.floorY) then table.remove(run.sprays, i) end
    end
  end
  -- actor moves / camera / stage tint (lib/ORASStage.lua) run to the
  -- timeline's end even when the particles are already gone
  if run.stageEnd and run.frame < run.stageEnd then return true end
  if mlist and (run.nextModel <= #mlist or #run.models > 0) then return true end
  if slist and (run.nextSpray <= #slist or #run.sprays > 0) then return true end
  return run.next <= #list or #run.live > 0
end

-- The newest run in `space` whose timeline moves the stage, and its frame
-- (fractional, for smooth moves at 60 Hz).
function Player.stageRun(space)
  for i = #active, 1, -1 do
    local run = active[i]
    if run.space == space and run.stageEnd and run.frame >= 0 then
      return run, run.frame + math.min(run.acc or 0, 0.999)
    end
  end
end

local lastTick
local function clock()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end
function Player.update(dt)
  local t = clock()
  if dt == "test" then dt = 1 / 60 else
    dt = lastTick and (t - lastTick) or 0
    lastTick = t
  end
  if dt > 0 then Player.tick = (Player.tick or 0) + 1 end
  if #active == 0 then return end
  dt = math.max(0, math.min(0.25, dt))
  for i = #active, 1, -1 do
    local run = active[i]
    run.acc = run.acc + dt * FPS
    local alive = true
    while run.acc >= 1 and alive do
      run.acc = run.acc - 1
      local ok, more = pcall(stepRun, run)
      if not ok then Player.lastError = tostring(more); alive = false
      else alive = more end
    end
    if not alive then table.remove(active, i) end
  end
end

-- ------------------------------------------------------------------ drawing

local function rotate(rx, ry, rz, x, y, z)
  -- R = Rz * Ry * Rx
  local cx, sx = math.cos(rx), math.sin(rx)
  y, z = y * cx - z * sx, y * sx + z * cx
  local cy, sy = math.cos(ry), math.sin(ry)
  x, z = x * cy + z * sy, -x * sy + z * cy
  local cz, sz = math.cos(rz), math.sin(rz)
  x, y = x * cz - y * sz, x * sz + y * cz
  return x, y, z
end

local mesh
local verts = { {}, {}, {}, {} }
local function quadMesh()
  if mesh == nil then
    local ok, m = pcall(love.graphics.newMesh, 4, "fan", "stream")
    mesh = ok and m or false
  end
  return mesh or nil
end

local function setBlend(g, blend)
  if blend == "add" then g.setBlendMode("add", "alphamultiply")
  elseif blend == "multiply" then g.setBlendMode("multiply", "premultiplied")
  else g.setBlendMode("alpha", "alphamultiply") end
end

-- a body point of a side, falling back to its centre
local function bodyPoint(host, role, slot)
  local ok, p = pcall(host.point, role, slot)
  if ok and type(p) == "table" then return p end
  ok, p = pcall(host.point, role, "center")
  if ok and type(p) == "table" then return p end
end

local function roleName(r) return r == 0 and "attacker" or (r == 1 and "defender" or nil) end

-- Where a live effect (particle file or model) sits now: its anchor (body
-- point + offset, moved along its flights), the world units per cm and the
-- effect basis (X right, Y up, Z toward the target). Returns toWorld(x, y, z)
-- for effect-space cm, and the unit; nil when the side has no position.
Player.AIM_AXIS = "+z"
local function placement(run, l)
  local host = run.host
  local anchor = bodyPoint(host, l.role, l.slot)
  if not anchor then
    if not l.warned then l.warned = true; Player.note("move %d: no position for the %s", run.move, l.role) end
    return
  end
  local okU, unit = pcall(host.unit)
  unit = okU and tonumber(unit) or nil
  if not unit or unit <= 0 then
    if not l.warned then l.warned = true; Player.note("move %d: no size (no ORAS model scale)", run.move) end
    return
  end
  l.lastAnchor, l.lastUnit = anchor, unit
  local okF, fwd = pcall(host.forward)
  fwd = okF and type(fwd) == "table" and fwd or { 0, 0, 1 }
  -- effect basis: X right, Y up, Z forward -- toward the OTHER side, as ORAS
  -- attaches effects to that Pokemon's own body (and as its cameras' side
  -- frames): an effect on the target faces the attacker
  local fx_, fz_ = fwd[1] or 0, fwd[3] or 1
  if l.role == "defender" then fx_, fz_ = -fx_, -fz_ end
  local fl = math.sqrt(fx_ * fx_ + fz_ * fz_)
  if fl < 1e-6 then fx_, fz_, fl = 0, 1, 1 end
  fx_, fz_ = fx_ / fl, fz_ / fl
  local rx_, rz_ = fz_, -fx_          -- right = up x forward
  local function withOffset(p, off)
    if not off then return p[1], p[2], p[3] end
    local ox, oy, oz = off[1] or 0, off[2] or 0, off[3] or 0
    return p[1] + (rx_ * ox + fx_ * oz) * unit, p[2] + oy * unit, p[3] + (rz_ * ox + fz_ * oz) * unit
  end
  -- the timeline's offset from the body point, in effect units
  local ax, ay, az = withOffset(anchor, l.off)
  -- flights: each timed attach moves the effect from where it is to the new
  -- body point (the attacker's fire into the target)
  if l.travel then
    local age = l.age + (run.acc or 0)
    for _, tr in ipairs(l.travel) do
      if age < tr[1] then break end
      local slot = POINT_SLOT[tr[4] or -1] or "center"
      local dest = bodyPoint(host, roleName(tr[3]) or l.role, slot)
      if dest then
        local bx, by, bz = withOffset(dest, tr[5])
        local span = math.max(1e-3, tr[2] - tr[1])
        local u = math.max(0, math.min(1, (age - tr[1]) / span))
        if tr[6] == 2 then u = u * u * (3 - 2 * u) end
        ax, ay, az = ax + (bx - ax) * u, ay + (by - ay) * u, az + (bz - az) * u
      end
    end
  end
  -- basis: right R, up U, forward F (default: level, toward the target)
  local Rx, Ry, Rz, Ux, Uy, Uz, Fx, Fy, Fz = rx_, 0, rz_, 0, 1, 0, fx_, 0, fz_
  -- aimed (0x32 / 0x46): forward from the anchor at another body point,
  -- tilted too -- a beam from the attacker's mouth into the target
  if l.aim then
    local dest = bodyPoint(host, roleName(l.aim[1]) or l.role, POINT_SLOT[l.aim[2] or -1] or "center")
    if dest then
      local dx, dy, dz = dest[1] - ax, dest[2] - ay, dest[3] - az
      local dl = math.sqrt(dx * dx + dy * dy + dz * dz)
      if dl > 1e-6 then
        local ax_, ay_, az_ = dx / dl, dy / dl, dz / dl
        -- which local axis ORAS points at the aim point (Player.AIM_AXIS)
        local mode = Player.AIM_AXIS
        local sgn = (mode == "-z" or mode == "-y") and -1 or 1
        local d1, d2, d3 = ax_ * sgn, ay_ * sgn, az_ * sgn
        if mode == "+y" or mode == "-y" then
          -- local up along the aim; forward stays level, turned to fit
          Ux, Uy, Uz = d1, d2, d3
          local hl = math.sqrt(d1 * d1 + d3 * d3)
          if hl > 1e-6 then
            Rx, Ry, Rz = d3 / hl, 0, -d1 / hl
            Fx, Fy, Fz = Ry * Uz - Rz * Uy, Rz * Ux - Rx * Uz, Rx * Uy - Ry * Ux
          end
        else
          Fx, Fy, Fz = d1, d2, d3
          local hl = math.sqrt(Fx * Fx + Fz * Fz)
          if hl > 1e-6 then
            Rx, Ry, Rz = Fz / hl, 0, -Fx / hl            -- right = up x forward
            Ux, Uy, Uz = Fy * Rz - Fz * Ry, Fz * Rx - Fx * Rz, Fx * Ry - Fy * Rx   -- up = forward x right
          end
        end
      end
    end
  end
  -- the slot's own turn (0x35, degrees), keyed like the scale
  local qx, qy, qz
  if l.rots then
    local age = l.age + (run.acc or 0)
    local x, y, z = 0, 0, 0
    for _, k in ipairs(l.rots) do
      if age < k[1] then break end
      local span = k[2] - k[1]
      if span <= 0 or age >= k[2] then x, y, z = k[3], k[4], k[5]
      else
        local u = (age - k[1]) / span
        x, y, z = x + (k[3] - x) * u, y + (k[4] - y) * u, z + (k[5] - z) * u
      end
    end
    if x ~= 0 or y ~= 0 or z ~= 0 then qx, qy, qz = math.rad(x), math.rad(y), math.rad(z) end
  end
  local function toWorld(x, y, z)
    if qx then x, y, z = rotate(qx, qy, qz, x, y, z) end
    return ax + (Rx * x + Ux * y + Fx * z) * unit, ay + (Ry * x + Uy * y + Fy * z) * unit,
           az + (Rz * x + Uz * y + Fz * z) * unit
  end
  return toWorld, unit, ay
end

-- one live particle file of one run
local function drawLive(g, run, l, project)
  local toWorld, unit = placement(run, l)
  if not toWorld then return end
  local function scr(x, y, z)
    local ok, sx, sy = pcall(project, x, y, z)
    if ok and sx and sy then return sx, sy end
  end

  local m = quadMesh()
  if not m then return end
  local textures = l.fx.textures or {}
  local ksx, ksy, ksz = l.sx or 1, l.sy or 1, l.sz or 1
  local okZ, grow = pcall(Effects().particleSize)
  grow = okZ and tonumber(grow) or 1
  for _, q0 in ipairs(Sim().quads(l.sim)) do
    -- effect scale: positions and quad sizes alike
    local q = q0
    q.x, q.y, q.z = q.x * ksx, q.y * ksy, q.z * ksz
    q.w, q.h = q.w * ksx * grow, q.h * ksy * grow
    local key = q.texture and textures[q.texture]
    local img = key and image(key)
    if img and q.a > 0.004 then
      local wx, wy, wz = toWorld(q.x, q.y, q.z)
      local cx, cy = scr(wx, wy, wz)
      if cx then
        local hw, hh = q.w * 0.5, q.h * 0.5
        local px, py = q.pivot and q.pivot[1] or 0, q.pivot and q.pivot[2] or 0
        local p = {}
        if q.orient == "oriented" then
          -- flat quad: local width along X, height along Z, turned by rot
          local r = q.rot
          local ux, uy, uz = rotate(r[1], r[2], r[3], hw, 0, 0)
          local vx, vy, vz = rotate(r[1], r[2], r[3], 0, 0, hh)
          local ox, oy, oz = q.x - px * ux - py * vx, q.y - px * uy - py * vy, q.z - px * uz - py * vz
          local corners = {
            { ox - ux - vx, oy - uy - vy, oz - uz - vz, 0, 1 },
            { ox + ux - vx, oy + uy - vy, oz + uz - vz, 1, 1 },
            { ox + ux + vx, oy + uy + vy, oz + uz + vz, 1, 0 },
            { ox - ux + vx, oy - uy + vy, oz - uz + vz, 0, 0 },
          }
          for i, c in ipairs(corners) do
            local sx, sy = scr(toWorld(c[1], c[2], c[3]))
            if not sx then p = nil; break end
            p[i] = { sx, sy, c[4], c[5] }
          end
        else
          -- screen-facing: pixels per world unit from a vertical step
          local ux, uy = scr(wx, wy + unit, wz)
          if not ux then p = nil else
            local upx, upy = ux - cx, uy - cy
            local ppu = math.sqrt(upx * upx + upy * upy)
            if ppu < 1e-6 then p = nil else
              local ex, ey, rx, ry
              local vlen = q.vx and math.sqrt(q.vx * q.vx + q.vy * q.vy + q.vz * q.vz) or 0
              if q.orient == "upright" and vlen > 1e-4 then
                -- a moving streak (bolts, lines, splashes): along its motion
                local vx, vy, vz = toWorld(q.x + q.vx / vlen, q.y + q.vy / vlen, q.z + q.vz / vlen)
                local tx, ty = scr(vx, vy, vz)
                local dx, dy = (tx or cx) - cx, (ty or cy) - cy
                local dl = math.sqrt(dx * dx + dy * dy)
                if dl > 1e-6 then ex, ey = dx / dl, dy / dl else ex, ey = upx / ppu, upy / ppu end
                rx, ry = -ey, ex
              elseif q.orient == "upright" then
                -- still: along the emitter's own up (screen up when that
                -- points at the camera)
                ex, ey = upx / ppu, upy / ppu
                local a = q.axis
                if a and (math.abs(a[1]) > 1e-3 or math.abs(a[3]) > 1e-3) then
                  local tx, ty = scr(toWorld(q.x + a[1], q.y + a[2], q.z + a[3]))
                  local dx, dy = (tx or cx) - cx, (ty or cy) - cy
                  local dl = math.sqrt(dx * dx + dy * dy)
                  if dl > 1e-6 then ex, ey = dx / dl, dy / dl end
                end
                rx, ry = -ey, ex
              else
                local c, s = math.cos(q.rot[3]), math.sin(q.rot[3])
                rx, ry = c, s                           -- screen right, rotated
                ex, ey = s, -c                          -- screen up (y down)
              end
              local W, Hh = hw * ppu, hh * ppu
              local ox, oy = cx - px * rx * W - py * ex * Hh, cy - px * ry * W - py * ey * Hh
              p = {
                { ox - rx * W - ex * Hh, oy - ry * W - ey * Hh, 0, 1 },
                { ox + rx * W - ex * Hh, oy + ry * W - ey * Hh, 1, 1 },
                { ox + rx * W + ex * Hh, oy + ry * W + ey * Hh, 1, 0 },
                { ox - rx * W + ex * Hh, oy - ry * W + ey * Hh, 0, 0 },
              }
            end
          end
        end
        if p then
          local du, dv = q.u1 - q.u0, q.v1 - q.v0
          for i = 1, 4 do
            local v = verts[i]
            v[1], v[2] = p[i][1], p[i][2]
            v[3], v[4] = q.u0 + p[i][3] * du, q.v0 + p[i][4] * dv
            v[5], v[6], v[7], v[8] = q.r, q.g, q.b, q.a
          end
          m:setVertices(verts)
          m:setTexture(img)
          setBlend(g, q.blend)
          g.draw(m)
        end
      end
    end
  end
end

-- F12 report lines
function Player.report(out)
  local E = Effects()
  out[#out + 1] = ("ORAS FX: built %s, in battle %s, running %d, last error %s"):format(
    tostring(E.built()), E.battleEnabled() and "ON" or "OFF", #active, tostring(Player.lastError))
  local now = clockNow()
  for _, run in ipairs(active) do
    out[#out + 1] = ("  run move %d (%s): frame %d, lands at %s, live files %d, drawn %d by %s"):format(
      run.move, run.space, run.frame, tostring(run.hitFrame), #run.live, run.drawn or 0, tostring(run.drawnBy))
    if run.stageEnd then
      out[#out + 1] = ("    stage: %d records, runs to frame %d, last pose %s"):format(
        #(run.entry.stage or {}), run.stageEnd, tostring(run.stageNote))
      out[#out + 1] = ("    camera: %s"):format(tostring(run.camNote or "none (battle camera)"))
      if run.entry.models then
        local parts = {}
        for _, lm in ipairs(run.models or {}) do
          parts[#parts + 1] = ("%d %s age %d tris %s%s"):format(lm.item[4], lm.role, lm.age, tostring(lm.tris or "-"),
            lm.item.motion and (" motion %d%s"):format(lm.item.motion[2], lm.motion and "" or " (not loaded)") or "")
        end
        out[#out + 1] = ("    models: %d in timeline, %d shown, live: %s"):format(#run.entry.models,
          (run.nextModel or 1) - 1, #parts > 0 and table.concat(parts, "; ") or "none")
      end
      if run.entry.sprays then
        local parts = {}
        for _, sp in ipairs(run.sprays or {}) do
          parts[#parts + 1] = ("%d %s age %d copies %d tris %s floor %s"):format(sp.item[4], sp.role, sp.age,
            #sp.copies, tostring(sp.tris or "-"), sp.floorY and ("%.0f"):format(sp.floorY) or "-")
        end
        out[#out + 1] = ("    sprays: %d in timeline, %d started, live: %s"):format(#run.entry.sprays,
          (run.nextSpray or 1) - 1, #parts > 0 and table.concat(parts, "; ") or "none")
      end
      if run.soundsOn then
        local sx = run.screenX or {}
        out[#out + 1] = ("    sounds: %d cues, %d played; pan attacker %s target %s (%s)"):format(
          #run.entry.sounds, run.nextSound - 1, tostring(sx.attacker and ("%.2f"):format(sx.attacker) or "-"),
          tostring(sx.defender and ("%.2f"):format(sx.defender) or "-"),
          run.screenX and "seen on screen" or ("by side, attacker " .. tostring(run.host and run.host.attackerSide)))
      end
    end
    for _, l in ipairs(run.live) do
      local a = l.lastAnchor
      out[#out + 1] = ("    %s at %s: anchor %s, unit %s, scale %s, particles %d"):format(l.role, l.slot,
        a and ("(%.1f, %.1f, %.1f)"):format(a[1], a[2], a[3]) or "none", tostring(l.lastUnit),
        tostring(l.sx or 1), #l.sim.particles)
    end
  end
  out[#out + 1] = "  recent events (seconds ago):"
  for i = #events, math.max(1, #events - 24), -1 do
    out[#out + 1] = ("    %6.2f  %s"):format(now - events[i].t, events[i].text)
  end
end

-- returns true when something was drawn
-- where each side stands on screen (-1 left .. 1 right), for sound pan
local function noteScreenX(g, run, project)
  local w
  local cv = g.getCanvas and g.getCanvas()
  if type(cv) == "table" and cv[1] then cv = cv[1] end
  if cv and cv.getWidth then w = cv:getWidth() else w = g.getWidth() end
  if not (w and w > 0) then return end
  for _, role in ipairs({ "attacker", "defender" }) do
    local p = bodyPoint(run.host, role, "center")
    if p then
      local sx = project(p[1], p[2], p[3])
      if tonumber(sx) then
        run.screenX = run.screenX or {}
        run.screenX[role] = math.max(-1, math.min(1, sx / w * 2 - 1))
      end
    end
  end
end

function Player.draw(project, space)
  space = space or "csm"
  if not Player.busy(space) then return false end
  local g = love and love.graphics
  if not g then return false end
  g.push("all")
  g.origin()
  g.setScissor()
  g.setShader()
  g.setDepthMode()
  g.setColor(1, 1, 1, 1)
  local drew = false
  local tick = Player.tick or 0
  for _, run in ipairs(active) do
    -- one draw per frame: the battle screen and the 3D-BTL scene may both
    -- offer to draw the same run
    if run.space == space and run.drawTick ~= tick then
      run.drawTick = tick
      if run.soundsOn then pcall(noteScreenX, g, run, project) end
      run.drawnBy = Player.drawingVia or space
      for _, lm in ipairs(run.models or {}) do
        local toWorld = placement(run, lm)
        if toWorld then
          local ok, n = pcall(Models().draw, g, lm, lm.age + (run.acc or 0), toWorld, project, image)
          if not ok then Player.lastError = tostring(n)
          else drew = true; lm.tris = n end
        end
      end
      for _, sp in ipairs(run.sprays or {}) do
        local toWorld, unit, ay = placement(run, sp)
        if toWorld then
          -- the ground under that side, in the spray's cm (for bounces)
          local feet = bodyPoint(run.host, sp.role, "origin")
          if feet and unit and unit > 0 then sp.floorY = (feet[2] - ay) / unit end
          local ok, n = pcall(Models().drawSpray, g, sp, toWorld, project, image)
          if not ok then Player.lastError = tostring(n)
          else drew = true; sp.tris = n end
        end
      end
      for _, l in ipairs(run.live) do
      local ok, err = pcall(drawLive, g, run, l, project)
      if not ok then Player.lastError = tostring(err) else drew = true end
      run.drawn = (run.drawn or 0) + 1
    end end
  end
  g.pop()
  return drew
end

return Player
