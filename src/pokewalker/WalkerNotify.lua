-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S PHONE NOTIFICATIONS (Android: love.system.walkerNotify ->
-- GameActivity.walkerNotify -> WalkerNotifications.java).
--
--   post(st, title, text)  one notification now -- a diary event the player is
--                          not looking at (the launcher open on another page)
--   watch(st, courses)     the walk's coming milestones, in steps from NOW,
--                          for the background check that runs every half hour
--                          while the app is closed: a course unlocking (exact:
--                          watts are steps / 20), a wild Pokemon's group coming
--                          within reach on the walk, the day's step goals.
--                          The phone reads its own step counter against the
--                          step bridge's anchor, so it knows how far past
--                          "now" the walk has gone without the app running.
--
-- Settings -> Notifications off (st.settings.notify == false) stops both.
-- Elsewhere than Android this does nothing.

local N = {}

N.GOALS = { 5000, 10000, 15000 }

function N.available()
  return love and love.system and type(love.system.walkerNotify) == "function"
end

local function enabled(st) return st and st.settings and st.settings.notify ~= false end

local function send(cmd)
  if not N.available() then return false end
  local ok, Json = pcall(require, "src.link.Json")
  if not ok then return false end
  local okE, body = pcall(Json.encode, cmd)
  if not okE then return false end
  local okC, res = pcall(love.system.walkerNotify, body)
  return okC and res
end

function N.post(st, title, text)
  if not enabled(st) then return false end
  return send({ post = { title = title or "Pokewalker", text = text or "" } })
end

-- the milestones, nearest first: { at = steps from now, title, text }
function N.milestones(st, courses)
  local W = require("src.pokewalker.Walker")
  local out = {}
  local wk = st.walking
  local name = wk and wk.name or "Your Pokemon"
  -- the next course to open: watts are exact
  local nextC
  for id = 0, 19 do
    local c = courses and courses[id]
    if c and c.watts and c.watts > (st.lifetimeWatts or 0) and (not nextC or c.watts < nextC.watts) then nextC = c end
  end
  if nextC then
    local steps = (nextC.watts - (st.lifetimeWatts or 0)) * W.STEPS_PER_WATT - (st.stepRemainder or 0)
    out[#out + 1] = { at = math.max(1, steps), title = "New course unlocked!",
                      text = ("%s is open on your Pokewalker."):format(nextC.name) }
  end
  -- the walk's wild Pokemon coming within reach
  if wk then
    local c = courses and courses[st.course]
    for _, e in ipairs(wk.encounters or {}) do
      local need = W.stepsNeeded(st, e) - (wk.steps or 0)
      if need > 0 then
        out[#out + 1] = { at = need, title = "Something's rustling...",
          text = ("%s hears something in the grass on %s. Try the Poke Radar!"):format(name, c and c.name or "its course") }
      end
    end
    for k = 1, 3 do
      out[#out + 1] = { at = k * 1000, title = ("%s is having fun!"):format(name),
                        text = ("%d more steps together -- it may have found something."):format(k * 1000) }
    end
  end
  -- today's goals
  local today = (st.history and st.history[1] and st.history[1].day == math.floor(os.time() / 86400)) and st.history[1].steps or 0
  for _, goal in ipairs(N.GOALS) do
    if goal > today then
      out[#out + 1] = { at = goal - today, title = ("%d steps today!"):format(goal),
                        text = "Nice walking! Open the Pokewalker to spend your watts." }
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

function N.watch(st, courses)
  if not N.available() then return false end
  if not enabled(st) then return send({ stop = true }) end
  local dir = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory() or ""
  return send({ watch = {
    id = tostring(os.time()),
    pendingFile = dir .. "/steps_pending.json",
    milestones = N.milestones(st, courses),
  } })
end

return N
