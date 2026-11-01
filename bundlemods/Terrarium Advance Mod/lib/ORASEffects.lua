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
E.STAMP = "oras-fx=4"   -- 2: per-effect scale (0x34) and side (0x2F); 3: body point + offset, hit cue (0x0C)
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

local function bake(onProgress)
  local R = V.require("N3DSRom")
  local G = V.require("GARC")
  local S = V.require("ORASWazaSeq")
  local P = V.require("ORASParticles")
  local Sim = V.require("ORASParticleSim")
  local rom = assert(R.open(mod, E.IMPORT_ID))
  local seqG = assert(G.open(rom, assert(rom:file(S.GARC_PATH), "dump has no " .. S.GARC_PATH)))
  local fxG = assert(G.open(rom, assert(rom:file(P.GARC_PATH), "dump has no " .. P.GARC_PATH)))

  -- 1. timelines
  local moves, wanted, firstTarget = {}, {}, {}
  for move = 1, S.MAX_MOVE do
    local seq = S.parse(seqG:member(S.memberForMove(move)) or "")
    if seq then
      local list = {}
      local recs = seq.records
      -- attach state per slot from 0x2F (effects) and 0x68 (sounds; side only)
      local attach = {}
      local hit
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
      if #list > 0 then moves[move] = { frames = seq.frames, fx = list, hit = hit } end
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

  local nMoves, nTex = 0, 0
  for _ in pairs(moves) do nMoves = nMoves + 1 end
  for _ in pairs(written) do nTex = nTex + 1 end
  mod.cache:write(E.INDEX, "return " .. literal({ stamp = E.STAMP, moves = moves, members = roles }) .. "\n")
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
