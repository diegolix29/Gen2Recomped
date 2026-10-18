-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHERE THE POKEWALKER'S STEPS COME FROM: the phone's own step counter.
--
-- Android's bridge (love.system.syncHealthSteps -> GameActivity.syncHealthSteps,
-- mobile/ANDROID.md "Step bridge") reads the hardware TYPE_STEP_COUNTER and
-- stages the steps walked since the last read as steps_pending.json in the
-- save directory: { "steps": n, "from": iso, "to": iso }. The counter runs
-- while the app is closed, so a read on opening credits the whole walk.
-- This takes the file, credits the walker and deletes it -- so two readers
-- (the community Pokewalker mod, if installed) would split the steps between
-- them.
--
-- STEP_DEBUG=n credits n steps once (desktop testing; no sensor there).

local S = {}

S.FILE = "steps_pending.json"
S.EVERY = 60          -- seconds between sensor reads while the app is up

local last = -math.huge
local debugDone = false

function S.available()
  return love and love.system and type(love.system.syncHealthSteps) == "function"
end

-- ask the sensor (Android); the reading lands in the file a moment later
function S.request(force)
  local now = love.timer and love.timer.getTime() or os.time()
  if not force and now - last < S.EVERY then return end
  last = now
  if S.available() then pcall(love.system.syncHealthSteps) end
end

-- the staged steps, consumed; 0 when there are none
function S.take()
  local n = 0
  if not debugDone and os.getenv and tonumber(os.getenv("STEP_DEBUG") or "") then
    debugDone = true
    n = n + tonumber(os.getenv("STEP_DEBUG"))
  end
  if love and love.filesystem and love.filesystem.getInfo(S.FILE) then
    local body = love.filesystem.read(S.FILE) or ""
    local ok, Json = pcall(require, "src.link.Json")
    local okD, doc = false, nil
    if ok then okD, doc = pcall(Json.decode, body) end
    local steps = okD and type(doc) == "table" and tonumber(doc.steps) or tonumber(body:match('"steps"%s*:%s*(%d+)'))
    if steps and steps > 0 then n = n + math.floor(steps) end
    love.filesystem.remove(S.FILE)
  end
  return n
end

-- one tick: read when due, credit what arrived; returns the steps credited
function S.pump(st, courses, force)
  S.request(force)
  local n = S.take()
  if n > 0 then
    local W = require("src.pokewalker.Walker")
    W.addSteps(st, n, courses)
    W.save(st)
    -- the phone's background check measures from here now
    pcall(require("src.pokewalker.WalkerNotify").watch, st, courses)
  end
  return n
end

return S
