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

local function image(key)
  local img = images[key]
  if img ~= nil then return img or nil end
  img = false
  local mod = V.mod
  local ok, bytes = pcall(mod.cache.read, mod.cache, Effects().ROOT .. "/tex/" .. key .. ".png")
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
  Player.note("move %d (%s): started, %d particle files, %d stage records, lands at frame %s",
    run.move, run.space, #entry.fx, entry.stage and #entry.stage or 0, tostring(run.hitFrame))
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
  local level = opts and opts.sfxVol
  if level == nil then level = 7 end
  return math.max(0, math.min(7, level)) / 7
end

local function soundFor(k)
  local d = soundData[k]
  if d ~= nil then return d or nil end
  d = false
  local mod = V.mod
  local ok, bytes = pcall(mod.cache.read, mod.cache, ("%s/snd/%d.wav"):format(Effects().ROOT, k))
  if ok and type(bytes) == "string" and love and love.sound then
    local okD, sd = pcall(function()
      return love.sound.newSoundData(love.filesystem.newFileData(bytes, k .. ".wav"))
    end)
    if okD and sd then d = sd end
  end
  soundData[k] = d
  return d or nil
end

function Player.playSound(k, vol)
  if not (love and love.audio) then return false end
  local okL, level = pcall(function() return Effects().soundLevel() end)
  level = okL and tonumber(level) or 100
  local gain = (vol or 127) / 127 * level / 100 * sfxScale() * Player.SOUND_BASE
  if gain <= 0.001 then return false end
  local sd = soundFor(k)
  if not sd then return false end
  local ok, src = pcall(love.audio.newSource, sd, "static")
  if not (ok and src) then return false end
  pcall(src.setVolume, src, math.min(1, gain))
  pcall(src.play, src)
  playing[#playing + 1] = src
  for i = #playing, 1, -1 do
    local okP, live = pcall(playing[i].isPlaying, playing[i])
    if not (okP and live) and playing[i] ~= src then table.remove(playing, i) end
  end
  return true
end

-- an ORAS move with sounds is playing now (the cartridge's own move sound
-- stays quiet meanwhile, lib/ORASEffectsScene.lua)
function Player.soundBusy()
  for _, run in ipairs(active) do
    if run.soundsOn then return true end
  end
  return false
end

local function stepRun(run)
  run.frame = run.frame + 1
  if run.soundsOn then
    local list = run.entry.sounds
    while run.nextSound <= #list and list[run.nextSound][1] <= run.frame do
      local cue = list[run.nextSound]
      pcall(Player.playSound, cue[2], cue[3])
      run.nextSound = run.nextSound + 1
    end
  end
  local list = run.entry.fx
  while run.next <= #list and list[run.next][1] <= run.frame do
    spawn(run, list[run.next])
    run.next = run.next + 1
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
  -- actor moves / camera / stage tint (lib/ORASStage.lua) run to the
  -- timeline's end even when the particles are already gone
  if run.stageEnd and run.frame < run.stageEnd then return true end
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

-- one live particle file of one run
local function drawLive(g, run, l, project)
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
  -- effect basis: X right, Y up, Z forward (toward the target)
  local fx_, fz_ = fwd[1] or 0, fwd[3] or 1
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
  local function toWorld(x, y, z)
    return ax + (rx_ * x + fx_ * z) * unit, ay + y * unit, az + (rz_ * x + fz_ * z) * unit
  end
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
                ex, ey = upx / ppu, upy / ppu           -- screen up
                rx, ry = -ey, ex                        -- screen right
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
      if run.soundsOn then
        out[#out + 1] = ("    sounds: %d cues, %d played"):format(#run.entry.sounds, run.nextSound - 1)
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
      run.drawnBy = Player.drawingVia or space
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
