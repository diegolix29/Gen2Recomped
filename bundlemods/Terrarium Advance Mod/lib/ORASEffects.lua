-- ORAS EFFECTS: move effects baked from the player's own Omega Ruby / Alpha
-- Sapphire dump, and the switch that plays them in battle.
--
-- Independent of the Colosseum disc and its move-FX cache: own OPTIONS rows
-- (under ORAS MODELS / ORAS PACK), own pump, own cache folder.
--
-- BUILD (row "ORAS EFFECTS"), a background job like ORAS MODELS:
--   move timelines   GARC a/0/3/4 (lib/ORASWazaSeq.lua), member = move + 119
--   particle files   GARC a/0/3/1 (lib/ORASParticles.lua), the ones the
--                    timelines spawn (SESD opcode 0x2B)
-- into mod cache oras/movefx/:
--   index.lua        { stamp, moves = { [move] = { frames, fx = { {s, e, t, m, role=, scale=} } } },
--                      members = { [m] = role } }   s/e frames, t effect slot, m member,
--                      role 0 attacker / 1 target (op 0x2F), scale = { {frame, x, y, z} }
--                      (op 0x34, frames from the spawn; ORAS draws most effects at 1.5-3x)
--   fx/<m>.lua       one particle file: sets, emitters, texture keys, role
--   tex/<key>.png    textures, key = name_WxH (shared between files)
--
-- PLAY (row "ORAS EFFECTS IN BATTLE", ON / OFF, stored in
-- oras/movefx/battle.txt): lib/ORASEffectsPlayer.lua runs a move's timeline
-- on the battle's actors (hooked from lib/CurrentSpriteModels.lua).

local V = ...
local mod = V and V.mod

local E = { ID = "oras_fx", LABEL = "ORAS EFFECTS" }

E.ROOT = "oras/movefx"
E.INDEX = E.ROOT .. "/index.lua"
E.STAMP = "oras-fx=9"   -- 2: per-effect scale (0x34) and side (0x2F); 3: body point + offset, hit cue (0x0C);
                        -- 5: stage records (actor moves / scale, stage tint, camera); 6: body motion kind (0x0D);
                        -- 7: move sounds; 8: sound placement (0x68) for pan; 9: effect models (0x3F)
E.SETTING = E.ROOT .. "/battle.txt"
E.IMPORT_ID = "pokemon_oras"

local FRAME_BUDGET = 0.010

local function log(level, fmt, ...)
  local l = mod and mod.log
  if l and type(l[level]) == "function" then pcall(l[level], l, fmt, ...) end
end

local function now()
  return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

-- ---------------------------------------------------------------- literals

local function literal(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if v == math.floor(v) and math.abs(v) < 1e9 then return ("%d"):format(v) end
    return ("%.6g"):format(v)
  elseif t == "string" then return ("%q"):format(v)
  elseif t == "boolean" then return v and "true" or "false"
  elseif t ~= "table" then return "nil" end
  local out, n = { "{" }, #v
  for i = 1, n do out[#out + 1] = literal(v[i]) .. "," end
  local keys = {}
  for k in pairs(v) do
    if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return tostring(a) < tostring(b) end
    return type(a) == "number"
  end)
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. literal(k) .. "]")
      or (k:match("^[%a_][%w_]*$") and k or ("[" .. ("%q"):format(k) .. "]"))
    out[#out + 1] = key .. "=" .. literal(v[k]) .. ","
  end
  out[#out + 1] = "}"
  return table.concat(out)
end
E._literal = literal

local function readLua(path)
  local ok, src = pcall(mod.cache.read, mod.cache, path)
  if not (ok and type(src) == "string") then return nil end
  local chunk = (loadstring or load)(src, "@" .. path)
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local okRun, value = pcall(chunk)
  return okRun and value or nil
end
E.readLua = readLua

-- ----------------------------------------------------------------- setting

local settingValue
function E.battleEnabled()
  if settingValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, E.SETTING)
    settingValue = not (ok and type(s) == "string" and s:find("off", 1, true))
  end
  return settingValue
end

-- particle size in battle: x1 is ORAS's own size against the model; the 3D-BTL
-- camera sits far back, so x2 by default.  Only the quads grow, not the
-- effect's spread, so it still lands on the same body points.
E.SIZE_FILE = E.ROOT .. "/size.txt"
E.SIZES = { 1, 2, 3 }
local sizeValue
function E.particleSize()
  if sizeValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, E.SIZE_FILE)
    sizeValue = ok and tonumber(type(s) == "string" and s:match("%d+")) or 2
  end
  return sizeValue
end
function E.cycleSize()
  local cur, nxt = E.particleSize(), E.SIZES[1]
  for i, v in ipairs(E.SIZES) do if v == cur then nxt = E.SIZES[i % #E.SIZES + 1] end end
  sizeValue = nxt
  pcall(mod.cache.write, mod.cache, E.SIZE_FILE, tostring(nxt))
end

-- move cameras (op 0x17) in 3D-BTL: ON / OFF (oras/movefx/camera.txt, default
-- ON), and their zoom as a percentage of ORAS's own framing
-- (oras/movefx/zoom.txt, default 50: the subject half the size ORAS shows
-- it; 100 = ORAS).  Applied by ORASEffectsScene.camera.
E.CAMERA_FILE = E.ROOT .. "/camera.txt"
E.ZOOM_FILE = E.ROOT .. "/zoom.txt"
E.ZOOM_MIN, E.ZOOM_MAX, E.ZOOM_STEP, E.ZOOM_DEFAULT = 25, 200, 25, 50
local cameraValue, zoomValue
function E.cameraEnabled()
  if cameraValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, E.CAMERA_FILE)
    cameraValue = not (ok and type(s) == "string" and s:find("off", 1, true))
  end
  return cameraValue
end
function E.setCameraEnabled(on)
  cameraValue = on and true or false
  pcall(mod.cache.write, mod.cache, E.CAMERA_FILE, on and "on\n" or "off\n")
end
function E.cameraZoom()
  if zoomValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, E.ZOOM_FILE)
    local v = ok and tonumber(type(s) == "string" and s:match("%d+")) or nil
    zoomValue = (v and v >= E.ZOOM_MIN and v <= E.ZOOM_MAX) and v or E.ZOOM_DEFAULT
  end
  return zoomValue
end
-- dir -1 (left) / +1 (right, A); wraps at the ends so A alone reaches every value
function E.stepZoom(dir)
  local v = E.cameraZoom() + ((tonumber(dir) or 1) < 0 and -E.ZOOM_STEP or E.ZOOM_STEP)
  if v > E.ZOOM_MAX then v = E.ZOOM_MIN elseif v < E.ZOOM_MIN then v = E.ZOOM_MAX end
  zoomValue = v
  pcall(mod.cache.write, mod.cache, E.ZOOM_FILE, tostring(v) .. "\n")
end

-- move sounds (rendered by the bake, played by ORASEffectsPlayer): a level
-- 0 (OFF) / 25 / 50 / 75 / 100 % on top of the game's own SFX volume
-- (oras/movefx/sound.txt, default 100).  While they play, the cartridge's own
-- move sound is not played (lib/ORASEffectsScene.lua).
E.SOUND_FILE = E.ROOT .. "/sound.txt"
E.SOUND_LEVELS = { 0, 25, 50, 75, 100 }
local soundValue
function E.soundLevel()
  if soundValue == nil then
    local ok, s = pcall(mod.cache.read, mod.cache, E.SOUND_FILE)
    local v = ok and tonumber(type(s) == "string" and s:match("%d+")) or nil
    soundValue = (v and v >= 0 and v <= 100) and v or 100
  end
  return soundValue
end
function E.stepSound(dir)
  local cur, list = E.soundLevel(), E.SOUND_LEVELS
  local at = 1
  for i, v in ipairs(list) do if v == cur then at = i end end
  at = at + (((tonumber(dir) or 1) < 0) and -1 or 1)
  if at > #list then at = 1 elseif at < 1 then at = #list end
  soundValue = list[at]
  pcall(mod.cache.write, mod.cache, E.SOUND_FILE, tostring(soundValue) .. "\n")
end
-- sounds were baked and are switched on
function E.soundsActive()
  local idx = E.index()
  return E.active() and idx ~= nil and idx.sounds == true and E.soundLevel() > 0
end

function E.setBattleEnabled(on)
  settingValue = on and true or false
  pcall(mod.cache.write, mod.cache, E.SETTING, on and "on\n" or "off\n")
end

local indexMemo
function E.index()
  if indexMemo == nil then
    local idx = readLua(E.INDEX)
    indexMemo = (type(idx) == "table" and idx.stamp == E.STAMP) and idx or false
  end
  return indexMemo or nil
end

function E.built() return E.index() ~= nil end

-- Which of an ORAS model's attack banks a move plays.  Every ORAS move
-- timeline names the attacker's motion kind (op 0x0D): 1 contact (Scratch,
-- Quick Attack, Lick), 2 at range (Thunderbolt, Hypnosis, Psychic), 32
-- tackle, 33 punch (Pound, Mega Punch, Shadow Punch), 34 kick, 38 beam /
-- breath (Flamethrower, Water Gun, Hyper Beam, Shadow Ball), 39 roar (Growl),
-- 42 Double Team.  Physical kinds take ORAS battle slots 8-11 (physicalA-D),
-- the others 12-14 (specialA-C); PokemonActors falls back to the family's A
-- bank when a species lacks the variant (Haunter has only physicalA and
-- specialA).  nil: not built, or the move names no kind.
E.MOTION_BANK = {
  [1] = "physicalA", [32] = "physicalB", [33] = "physicalC", [34] = "physicalD",
  [35] = "physicalA", [36] = "physicalA", [37] = "physicalA",
  [2] = "specialA", [38] = "specialB", [39] = "specialC",
  [40] = "specialA", [41] = "specialA", [42] = "specialA",
}
function E.motionAction(move)
  local idx = E.index()
  local entry = idx and idx.moves[tonumber(move) or -1]
  local kind = entry and entry.motion
  if not kind then return nil end
  return E.MOTION_BANK[kind] or (kind >= 32 and kind < 38 and "physicalA") or "specialA", kind
end
-- PokemonActors is loaded outside V.require; it finds this on mod.exports
if mod and mod.exports then mod.exports.orasMotionFor = E.motionAction end

-- usable in battle right now: built and switched on
function E.active() return E.battleEnabled() and E.built() end

function E.imported()
  local imports = mod and mod.imports
  if not imports then return false end
  local ok, info = pcall(imports.info, imports, E.IMPORT_ID)
  return ok and type(info) == "table" and info.ready ~= false
end

-- ------------------------------------------------------------------- bake

local job = nil   -- { co, done, total, stage, startedAt, frameStart }

local function checkpoint()
  if job and coroutine.running() == job.co and now() - job.frameStart > FRAME_BUDGET then
    coroutine.yield()
  end
end

-- "_at_" layers play on the attacker, "_df_" on the target
local function roleOf(fx, target)
  for _, list in ipairs({ fx.sets or {}, fx.emitters or {} }) do
    for _, x in ipairs(list) do
      local n = tostring(x.name or "")
      if n:find("_at_", 1, true) then return "attacker" end
      if n:find("_df_", 1, true) then return "defender" end
    end
  end
  return target == 1 and "defender" or "attacker"
end

local function head(list, n)
  local t = {}
  for i = 1, math.min(#(list or {}), n) do t[i] = list[i] end
  return t
end

local function compactFx(P, Sim, fx, role)
  local out = { role = role, textures = {}, sets = {}, emitters = {} }
  for _, s in ipairs(fx.sets) do
    local set = {
      name = s.name, orient = s.orient, pivot = s.pivot,
      material = s.material and { texture = s.material.texture, blend = s.material.blend } or nil,
      attributes = { constant = s.attributes and s.attributes.constant or {} },
      initializers = {}, updaters = {},
    }
    for _, it in ipairs(s.initializers) do
      set.initializers[#set.initializers + 1] = {
        flag = it.flag, attr = it.attr, value = it.value, random = it.random, raw = head(it.raw, 8),
      }
    end
    for _, u in ipairs(s.updaters) do
      local frames = (u.flag == 0x40000 and u.attr == 5) and Sim.patternFrames(u) or nil
      set.updaters[#set.updaters + 1] = {
        flag = u.flag, attr = u.attr, curve = u.curve, frames = frames, raw = head(u.raw, 8),
      }
    end
    out.sets[#out.sets + 1] = set
  end
  for _, e in ipairs(fx.emitters) do
    out.emitters[#out.emitters + 1] = {
      name = e.name, set = e.set, ratio = e.ratio, ratioRandom = e.ratioRandom,
      interval = e.interval, duration = e.duration, delay = e.delay,
      shape = e.shape and { kind = e.shape.kind, raw = e.shape.raw } or nil,
      translate = e.translate, rotate = e.rotate, scale = e.scale,
    }
  end
  return out
end

-- Timeline records that move the battle itself rather than spawn particles
-- (played by lib/ORASStage.lua).  who: 0 attacker, 1 target (2 both, cameras).
--   0x02 (who, dx, dy, dz cm)              move the actor by that much over the span
--   0x03 (who, mode, ?, dx, dy, dz, ease)  the same, eased (1 linear, 2 smooth)
--   0x04 (who)                             back to its own place and size
--   0x08 (who, sx, sy, sz)                 stretch / squash to that size
--   0x76 (r, g, b, a)                      fade the stage (not the actors) to that colour
--   0x17 (who, point, eye xyz, look xyz cm) camera, in that side's frame
-- Double Team is 0x02 hops of +-50 cm every frame: three places at once.
local function stageRecord(S, r)
  local a, n = r.args, #r.args
  local f, u = S.f32, S.u32
  local base = { r.start, r.finish }
  if r.op == 0x02 and n >= 16 then
    base.k, base.w, base.v = "move", u(a, 1), { f(a, 5), f(a, 9), f(a, 13) }
  elseif r.op == 0x03 and n >= 28 then
    base.k, base.w, base.v, base.ease = "move", u(a, 1), { f(a, 13), f(a, 17), f(a, 21) }, u(a, 25)
  elseif r.op == 0x04 and n >= 4 then
    base.k, base.w = "home", u(a, 1)
  elseif r.op == 0x08 and n >= 16 then
    base.k, base.w, base.v = "scale", u(a, 1), { f(a, 5), f(a, 9), f(a, 13) }
  elseif r.op == 0x76 and n >= 16 then
    base.k, base.v = "tint", { f(a, 1), f(a, 5), f(a, 9), f(a, 13) }
  elseif r.op == 0x17 and n >= 32 then
    base.k, base.w, base.point = "cam", u(a, 1), u(a, 5)
    base.eye = { f(a, 9), f(a, 13), f(a, 17) }
    base.look = { f(a, 21), f(a, 25), f(a, 29) }
  else
    return nil
  end
  for _, x in ipairs(base.v or base.eye or {}) do
    if x ~= x or math.abs(x) > 1e5 then return nil end
  end
  return base
end

-- Where a sound cue sits (0x68 on the cue's slot, same layout as 0x2F: u32
-- who 0 attacker / 1 target / 2 between, u32 body point, vec3 offset, u32
-- easing). The last instant 0x68 of that slot up to the cue's frame places
-- it; a timed one starting on the cue's frame flies it there (Ember's
-- fireball 25-35). Adds cue[4] = who, cue[5] = { f0, f1, who } (frames
-- from the cue). Only the side is kept: the player pans by screen side.
local function soundPlace(S, recs, i, cue)
  local slot, s = recs[i].target, recs[i].start
  local who, travel
  for j, q in ipairs(recs) do
    if q.start > s then break end
    if q.op == 0x68 and q.target == slot and #q.args >= 4 then
      local w = S.u32(q.args, 1)
      if w <= 2 then
        if q.finish <= q.start then
          if travel == nil then who = w end
        elseif q.start == s and j > i and travel == nil then
          travel = { 0, q.finish - q.start, w }
        end
      end
    end
  end
  cue[4], cue[5] = who, travel
  return cue
end

local function bake(onProgress)
  local R = V.require("N3DSRom")
  local G = V.require("GARC")
  local S = V.require("ORASWazaSeq")
  local P = V.require("ORASParticles")
  local Sim = V.require("ORASParticleSim")
  local rom = assert(R.open(mod, E.IMPORT_ID))
  local seqG = assert(G.open(rom, assert(rom:file(S.GARC_PATH), "dump has no " .. S.GARC_PATH)))
  local fxG = assert(G.open(rom, assert(rom:file(P.GARC_PATH), "dump has no " .. P.GARC_PATH)))
  local EM = V.require("ORASEffectModels")
  local mf = rom:file(EM.GARC_PATH)
  local mG = mf and G.open(rom, mf)

  -- 1. timelines
  local moves, wanted, firstTarget, wantedSound = {}, {}, {}, {}
  local wantedModel, wantedUV = {}, {}
  for move = 1, S.MAX_MOVE do
    local seq = S.parse(seqG:member(S.memberForMove(move)) or "")
    if seq then
      local list = {}
      local recs = seq.records
      -- attach state per slot from 0x2F (effects) and 0x68 (sounds; side only)
      local attach = {}
      local hit, motion
      local stage, sounds, models = {}, {}, {}
      local function readAttach(q)
        return { role = S.u32(q.args, 1), point = S.u32(q.args, 5),
                 off = { S.f32(q.args, 9), S.f32(q.args, 13), S.f32(q.args, 17) } }
      end
      for i, r in ipairs(recs) do
        if (r.op == 0x2F or r.op == 0x68) and #r.args >= 20 then
          local a = readAttach(r)
          a.sound = r.op == 0x68
          if not (a.sound and attach[r.target] and not attach[r.target].sound) then attach[r.target] = a end
        end
        -- the target's damage cue: 0x0C with u32 1 (Tackle 22, Ember 36, Thunder 90)
        if r.op == 0x0C and hit == nil and #r.args >= 4 and S.u32(r.args, 1) == 1 then hit = r.start end
        -- the attacker's body motion kind (0x0D: who, id), see E.motionAction
        if r.op == 0x0D and motion == nil and #r.args >= 8 and S.u32(r.args, 1) == 0 then motion = S.u32(r.args, 5) end
        local st = stageRecord(S, r)
        if st then stage[#stage + 1] = st end
        -- sound cues (0x64 / 0x5D: u32 id = 0x000D0000 + k, u32 -1, u32
        -- volume 0..127): played by ORASEffectsPlayer, rendered below
        if (r.op == 0x64 or r.op == 0x5D) and #r.args >= 12 then
          local id = S.u32(r.args, 1)
          if math.floor(id / 65536) == 13 then
            local vol = S.u32(r.args, 9)
            if vol > 127 then vol = 127 end
            sounds[#sounds + 1] = soundPlace(S, recs, i, { r.start, id % 65536, vol })
            wantedSound[id % 65536] = true
          end
        end
        -- effect models (lib/ORASEffectModels.lua): 0x3F shows one, the
        -- same slot's 0x43 / 0x49 / 0x47 / 0x52 / 0x89 place, size, turn and
        -- scroll it
        if r.op == 0x3F and #r.args >= 4 and mG and S.u32(r.args, 1) < mG.count then
          local item = { r.start, r.finish, r.target, S.u32(r.args, 1) }
          for j = i + 1, #recs do
            local q = recs[j]
            if q.start > r.finish then break end
            if q.target == r.target then
              if q.op == 0x3F then break end
              local f0, f1 = q.start - r.start, q.finish - r.start
              if q.op == 0x43 and #q.args >= 24 then
                local a = readAttach(q)
                if item.role == nil and f0 == 0 and f1 == 0 then
                  item.role, item.point, item.off = a.role, a.point, a.off
                else
                  item.travel = item.travel or {}
                  item.travel[#item.travel + 1] = { f0, f1, a.role, a.point, a.off, S.u32(q.args, 21) }
                end
              elseif q.op == 0x49 and #q.args >= 12 then
                item.scale = item.scale or {}
                item.scale[#item.scale + 1] = { f0, f1, S.f32(q.args, 1), S.f32(q.args, 5), S.f32(q.args, 9) }
              elseif q.op == 0x47 and #q.args >= 12 then
                item.rot = item.rot or {}
                item.rot[#item.rot + 1] = { f0, f1, S.f32(q.args, 1), S.f32(q.args, 5), S.f32(q.args, 9) }
              elseif (q.op == 0x52 or q.op == 0x89) and #q.args >= 4 and item.uv == nil then
                local um = S.u32(q.args, 1)
                if um < mG.count then item.uv = { f0, um }; wantedUV[um] = true end
              end
            end
          end
          if item.role == nil and attach[r.target] then item.role = attach[r.target].role end
          models[#models + 1] = item
          wantedModel[item[4]] = true
        end
        if r.op == 0x2B and #r.args >= 4 then
          local m = S.u32(r.args, 1)
          if m < fxG.count then
            local item = { r.start, r.finish, r.target, m }
            -- the same effect slot (record target field) carries its side
            -- (0x2F: u32 0 attacker / 1 target, u32 body point, vec3 offset)
            -- and its scale (0x34: vec3), set at the spawn and later
            for j = i + 1, #recs do
              local q = recs[j]
              if q.start > r.finish then break end
              if q.target == r.target then
                if q.op == 0x2B then break end
                if q.op == 0x2F and #q.args >= 20 and item.role == nil and q.start == r.start
                    and q.finish == q.start then
                  local a = readAttach(q)
                  item.role, item.point, item.off = a.role, a.point, a.off
                elseif q.op == 0x2F and #q.args >= 24 then
                  -- a later / timed attach moves the effect there: the flight
                  -- from the attacker into the target (Ember 26-35, Fire Punch
                  -- 21-27); u32 after the offset = easing (1 linear, 2 eased)
                  local a = readAttach(q)
                  item.travel = item.travel or {}
                  item.travel[#item.travel + 1] = { q.start - r.start, q.finish - r.start,
                    a.role, a.point, a.off, S.u32(q.args, 21) }
                elseif q.op == 0x34 and #q.args >= 12 then
                  item.scale = item.scale or {}
                  item.scale[#item.scale + 1] = { q.start - r.start,
                    S.f32(q.args, 1), S.f32(q.args, 5), S.f32(q.args, 9) }
                end
              end
            end
            if item.role == nil and attach[r.target] then
              local a = attach[r.target]
              item.role = a.role
              if not a.sound then item.point, item.off = a.point, a.off end
            end
            list[#list + 1] = item
            wanted[m] = true
            if firstTarget[m] == nil then firstTarget[m] = item.role or r.target end
          end
        end
      end
      if #list > 0 or #stage > 0 or motion or #sounds > 0 or #models > 0 then
        moves[move] = { frames = seq.frames, fx = list, hit = hit, stage = #stage > 0 and stage or nil,
                        motion = motion, sounds = #sounds > 0 and sounds or nil,
                        models = #models > 0 and models or nil }
      end
    end
    if move % 25 == 0 then job.done = move; checkpoint() end
  end

  -- 2. particle files and their textures
  local members = {}
  for m in pairs(wanted) do members[#members + 1] = m end
  table.sort(members)
  job.stage, job.done, job.total = "fx", 0, #members
  local roles, written, failed = {}, {}, 0
  for i, m in ipairs(members) do
    local bytes = fxG:member(m)
    local fx = bytes and P.parse(bytes)
    if fx then
      local role = roleOf(fx, firstTarget[m])
      roles[m] = role
      local c = compactFx(P, Sim, fx, role)
      for _, t in ipairs(fx.textures) do
        local key = ("%s_%dx%d"):format(t.name, t.width, t.height)
        c.textures[t.name] = key
        if not written[key] then
          local okImg, img = pcall(P.texturePixels, bytes, t)
          if okImg and img then
            local png = img:encode("png"):getString()
            mod.cache:write(E.ROOT .. "/tex/" .. key .. ".png", png)
            written[key] = true
          end
        end
      end
      mod.cache:write(("%s/fx/%d.lua"):format(E.ROOT, m), "return " .. literal(c) .. "\n")
    else
      failed = failed + 1
    end
    job.done = i
    if onProgress and i % 100 == 0 then onProgress(i, #members) end
    checkpoint()
  end

  -- 2b. effect models and their texture scrolls (lib/ORASEffectModels.lua)
  local modelList, modelsBaked, modelsFailed = {}, {}, 0
  for m in pairs(wantedModel) do modelList[#modelList + 1] = m end
  table.sort(modelList)
  job.stage, job.done, job.total = "models", 0, #modelList
  local function writeTexture(name, w, h, img)
    local key = ("%s_%dx%d"):format(name, w, h)
    if not written[key] then
      local okP, png = pcall(function() return img:encode("png"):getString() end)
      if not okP then return nil end
      mod.cache:write(E.ROOT .. "/tex/" .. key .. ".png", png)
      written[key] = true
    end
    return key
  end
  for i, m in ipairs(modelList) do
    local okB, data, why = pcall(EM.bakeModel, mG:member(m) or "", writeTexture)
    if okB and data then
      mod.cache:write(("%s/models/%d.lua"):format(E.ROOT, m), "return " .. literal(data) .. "\n")
      modelsBaked[m] = true
    else
      modelsFailed = modelsFailed + 1
      log("warn", "ORAS EFFECTS: model %d skipped (%s)", m, tostring(okB and why or data))
    end
    job.done = i
    checkpoint()
  end
  local uvBaked = {}
  for um in pairs(wantedUV) do
    local okU, uv = pcall(EM.bakeUV, mG:member(um) or "")
    if okU and uv then
      mod.cache:write(("%s/uv/%d.lua"):format(E.ROOT, um), "return " .. literal(uv) .. "\n")
      uvBaked[um] = true
    end
    checkpoint()
  end
  -- drop items whose model did not bake, and scrolls that did not
  for _, entry in pairs(moves) do
    if entry.models then
      local keep = {}
      for _, it in ipairs(entry.models) do
        if modelsBaked[it[4]] then
          if it.uv and not uvBaked[it.uv[2]] then it.uv = nil end
          keep[#keep + 1] = it
        end
      end
      entry.models = #keep > 0 and keep or nil
    end
  end
  local nModels = 0
  for _ in pairs(modelsBaked) do nModels = nModels + 1 end
  log("info", "ORAS EFFECTS: %d effect models baked (%d left out, see warnings)", nModels, modelsFailed)

  -- 3. sounds: each battle sound the timelines use, rendered from the dump's
  -- sound archive (lib/ORASSound.lua) to snd/<k>.wav (16 kHz mono)
  local soundList = {}
  for k in pairs(wantedSound) do soundList[#soundList + 1] = k end
  table.sort(soundList)
  job.stage, job.done, job.total = "snd", 0, #soundList
  local okSnd, Snd = pcall(V.require, "ORASSound")
  local sf = okSnd and rom:file(Snd.PATH)
  local archive = sf and Snd.open(function(off, len) return rom:readFile(sf, off, len) end)
  local soundsBaked, soundsFailed = 0, 0
  if archive and archive.battleChecked then
    for i, k in ipairs(soundList) do
      local snd = archive.sounds[Snd.BATTLE_BASE + k]
      local okR, buf = pcall(Snd.render, archive, snd)
      if okR and buf and #buf > 1 then
        mod.cache:write(("%s/snd/%d.wav"):format(E.ROOT, k), Snd.wav(buf))
        soundsBaked = soundsBaked + 1
      else
        soundsFailed = soundsFailed + 1
      end
      job.done = i
      checkpoint()
    end
  else
    log("warn", "ORAS EFFECTS: sound archive not readable -- move sounds skipped")
  end
  log("info", "ORAS EFFECTS: %d move sounds rendered (%d failed)", soundsBaked, soundsFailed)

  local nMoves, nTex = 0, 0
  for _ in pairs(moves) do nMoves = nMoves + 1 end
  for _ in pairs(written) do nTex = nTex + 1 end
  mod.cache:write(E.INDEX, "return " .. literal({ stamp = E.STAMP, moves = moves, members = roles,
    sounds = soundsBaked > 0 or nil }) .. "\n")
  indexMemo = nil
  return nMoves, #members - failed, nTex, failed
end

function E.running() return job ~= nil end

function E.startBuild()
  if job then return false end
  job = { done = 0, total = 621, stage = "moves", startedAt = now(), frameStart = now() }
  job.co = coroutine.create(function()
    return bake(function(i, n) log("info", "ORAS EFFECTS: %d / %d particle files", i, n) end)
  end)
  E.status = { state = "building" }
  log("info", "ORAS EFFECTS: baking move effects in the background")
  return true
end

-- once a frame (main.lua)
function E.pump()
  -- play: the effect clock, and the 3D-BTL hook (lib/ORASEffectsScene.lua)
  if not E._sceneInstalled then
    E._sceneInstalled = true
    pcall(function() V.require("ORASEffectsScene").install() end)
  end
  local okP, P = pcall(V.require, "ORASEffectsPlayer")
  if okP and P and P.busy() then pcall(P.update) end
  -- F12 report on every battle, not only while 3D models are drawing (the
  -- PokemonActors poll): 2D-3D fights have no actor to poll it
  pcall(function()
    local down = love.keyboard and love.keyboard.isDown and love.keyboard.isDown("f12")
    local RD = V.require("RenderDump")
    if down and not E._f12 then RD.request(V.PokemonActors or {}) end
    E._f12 = down
    RD.frame()
  end)
  if not job then return end
  job.frameStart = now()
  local ok, nMoves, nFx, nTex, failed = coroutine.resume(job.co)
  if not ok then
    log("warn", "ORAS EFFECTS: build failed: %s", tostring(nMoves))
    E.status = { state = "error", error = tostring(nMoves) }
    job = nil
    return
  end
  if coroutine.status(job.co) == "dead" then
    local seconds = now() - job.startedAt
    job = nil
    E.status = { state = "done" }
    log("info", "ORAS EFFECTS: %d moves, %d particle files, %d textures baked in %.1fs (%d unreadable)",
        nMoves or 0, nFx or 0, nTex or 0, seconds, failed or 0)
  end
end

-- ------------------------------------------------------------------- rows

function E.row()
  return {
    id = E.ID,
    label = E.LABEL,
    value = function()
      if job then
        return job.stage == "moves" and ("MOVES %d/%d"):format(job.done, job.total)
          or job.stage == "snd" and ("SOUNDS %d/%d"):format(job.done, job.total)
          or ("BUILDING %d/%d"):format(job.done, job.total)
      end
      if E.status and E.status.state == "error" then return "ERROR" end
      if E.built() then return "BUILT" end
      return E.imported() and "BUILD" or "NO DUMP"
    end,
    step = function()
      if job then return true end
      if not E.imported() then
        log("info", "ORAS EFFECTS: import a decrypted Omega Ruby / Alpha Sapphire .3ds from the MODS panel first")
        return true
      end
      E.startBuild()
      return true
    end,
  }
end

function E.sizeRow()
  return {
    id = "oras_fx_size",
    label = "ORAS FX SIZE",
    value = function() return "X" .. tostring(E.particleSize()) end,
    step = function() E.cycleSize(); return true end,
  }
end

function E.soundRow()
  return {
    id = "oras_fx_sound",
    label = "ORAS FX SOUND",
    value = function()
      local idx = E.index()
      if idx and not idx.sounds then return "BUILD AGAIN" end
      local v = E.soundLevel()
      return v == 0 and "OFF" or (tostring(v) .. "%")
    end,
    step = function(_, dir) E.stepSound(dir); return true end,
  }
end

function E.cameraRow()
  return {
    id = "oras_fx_camera",
    label = "ORAS CAMERA",
    value = function() return E.cameraEnabled() and "ON" or "OFF" end,
    step = function() E.setCameraEnabled(not E.cameraEnabled()); return true end,
  }
end

function E.zoomRow()
  return {
    id = "oras_fx_zoom",
    label = "ORAS CAM ZOOM",
    value = function()
      if not E.cameraEnabled() then return "CAMERA OFF" end
      return tostring(E.cameraZoom()) .. "%"
    end,
    step = function(_, dir) E.stepZoom(dir); return true end,
  }
end

function E.battleRow()
  return {
    id = "oras_fx_battle",
    label = "ORAS FX IN BATTLE",
    value = function()
      if not E.built() then return job and "AFTER BUILD" or "BUILD FIRST" end
      return E.battleEnabled() and "ON" or "OFF"
    end,
    step = function()
      if not E.built() then
        log("info", "ORAS FX IN BATTLE: build the effects first (ORAS EFFECTS)")
        return true
      end
      E.setBattleEnabled(not E.battleEnabled())
      return true
    end,
  }
end

return E
