-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MINIGAMES' PAY DESK: every watt, item, Pokemon, score, achievement and
-- point of friendship a minigame hands out goes through here, so the daily
-- budgets hold whatever game paid it.
--
-- The money itself is src/pokewalker/WalkerEconomy.lua (another module, owned
-- elsewhere), called exactly as its contract says:
--   E.earn(st, watts, source)           E.grantItem(st, name, count, source)
--   E.grantPokemon(st, dex, level, src) E.recordScore(st, gameId, score) -> rank
--   E.achievement(st, event, amount)    E.friendship(st, amount)
--   E.save(st)
-- It is required with pcall; without it the watts go straight onto st.watts,
-- items and Pokemon into the walker's own three-slot bag and catch list, and
-- the state is saved with Walker.save.
--
-- What this module keeps itself, in st.minigames (it survives Walker.load,
-- which only fills in missing top-level keys):
--   day                   the day number the counters below belong to
--   daily                 { watts, items, pokemon, friendship, plays } today
--   games[id]             { best, plays, totalWatts, scores = { {score,
--                           watts, t, rank}, ... best first, TOP_SCORES kept } }

local R = {}

-- THE KNOBS. Everything a minigame may pay in one day, across all five games,
-- and in one run. Past a budget the games still play and still score; they
-- just stop paying that kind of reward until the next day (the day turns at
-- midnight UTC, as the walker's step history does).
R.LIMITS = {
  WATTS_PER_DAY = 300,        -- about ten good runs
  ITEMS_PER_DAY = 8,
  POKEMON_PER_DAY = 3,
  FRIENDSHIP_PER_DAY = 10,
  ITEMS_PER_RUN = 3,
  POKEMON_PER_RUN = 1,
  WATTS_PER_RUN = 40,         -- no single run pays more than this
  FRIENDSHIP_PER_RUN = 2,
  MIN_RUN_SECONDS = 15,       -- a run shorter than this earns no friendship
}
R.TOP_SCORES = 10

R.clock = function() return os.time() end   -- tests replace it

local function today() return math.floor(R.clock() / 86400) end

-- ------------------------------------------------------------ the economy

local econ, econTried
function R.economy()
  if R._economy ~= nil then return R._economy or nil end   -- tests pin it (false = none)
  if econTried then return econ end
  econTried = true
  local ok, E = pcall(require, "src.pokewalker.WalkerEconomy")
  econ = ok and type(E) == "table" and E or nil
  return econ
end
function R.resetEconomy() econ, econTried = nil, nil end

local function call(name, ...)
  local E = R.economy()
  local fn = E and E[name]
  if type(fn) ~= "function" then return false end
  local ok, a = pcall(fn, ...)
  if not ok then
    pcall(function() require("src.core.Logger").info("walker minigames: economy %s failed: %s", name, tostring(a)) end)
    return false
  end
  return true, a
end

local function walker() return require("src.pokewalker.Walker") end

-- ------------------------------------------------------------ the ledger

function R.state(st)
  local m = st.minigames
  if type(m) ~= "table" then m = {}; st.minigames = m end
  m.games = m.games or {}
  local d = today()
  if m.day ~= d or type(m.daily) ~= "table" then
    m.day = d
    m.daily = { watts = 0, items = 0, pokemon = 0, friendship = 0, plays = 0 }
  end
  return m
end

function R.game(st, id)
  local m = R.state(st)
  local g = m.games[id]
  if not g then g = { best = 0, plays = 0, totalWatts = 0, scores = {} }; m.games[id] = g end
  g.scores = g.scores or {}
  return g
end

function R.left(st)
  local d, L = R.state(st).daily, R.LIMITS
  return {
    watts = math.max(0, L.WATTS_PER_DAY - (d.watts or 0)),
    items = math.max(0, L.ITEMS_PER_DAY - (d.items or 0)),
    pokemon = math.max(0, L.POKEMON_PER_DAY - (d.pokemon or 0)),
    friendship = math.max(0, L.FRIENDSHIP_PER_DAY - (d.friendship or 0)),
  }
end

-- ------------------------------------------------------------ a run's purse
--
-- A run collects into a purse while it plays; nothing is paid until it ends
-- (R.settle), so quitting from pause still pays what was won, and a crash
-- mid-run pays nothing twice. The purse checks the day's budget as things
-- are collected, so a game can tell the player "the bag is full for today"
-- at the moment it happens rather than at the end.

function R.newPurse(st, gameId)
  R.state(st)
  return { st = st, game = gameId, items = {}, pokemon = {}, bonusWatts = 0, events = {} }
end

-- can this run still take an item / a Pokemon?
function R.canItem(p)
  return #p.items < R.LIMITS.ITEMS_PER_RUN and #p.items < R.left(p.st).items
end
function R.canPokemon(p)
  return #p.pokemon < R.LIMITS.POKEMON_PER_RUN and #p.pokemon < R.left(p.st).pokemon
end

function R.addItem(p, name)
  if not (name and R.canItem(p)) then return false end
  p.items[#p.items + 1] = name
  return true
end

function R.addPokemon(p, dex, level, name)
  if not (dex and R.canPokemon(p)) then return false end
  p.pokemon[#p.pokemon + 1] = { dex = dex, level = level or 5, name = name }
  return true
end

-- watts found lying around (orbs, caches): on top of the score's watts, still
-- inside the run and day caps
function R.addWatts(p, n) p.bonusWatts = p.bonusWatts + math.max(0, math.floor(n or 0)) end

-- an achievement event to report at the end (summed by name)
function R.event(p, name, amount)
  p.events[name] = (p.events[name] or 0) + (amount or 1)
end

-- fallbacks when there is no economy module
local function fallbackItem(st, name)
  local W = walker()
  st.items = st.items or {}
  if #st.items >= (W.MAX_ITEMS or 3) then return false end
  st.items[#st.items + 1] = { name = name }
  return true
end

local function fallbackPokemon(st, mon)
  local W = walker()
  st.caught = st.caught or {}
  if #st.caught >= (W.MAX_CAUGHT or 3) then return false end
  st.caught[#st.caught + 1] = { species = mon.dex, name = mon.name, level = mon.level }
  return true
end

local function note(st, text)
  local ok = pcall(function() walker().note(st, text) end)
  return ok
end

-- END OF A RUN: pay the purse. `scoreWatts` is what the game's own formula
-- made of the score; `seconds` how long it ran. Returns the summary the
-- results screen shows:
--   { score, rank, best, newBest, watts, wattsCapped, items = {...},
--     pokemon = {...}, friendship, lost = { items = n, pokemon = n } }
function R.settle(p, score, scoreWatts, seconds)
  local st, id, L = p.st, p.game, R.LIMITS
  local m = R.state(st)
  local g = R.game(st, id)
  local source = "minigame:" .. tostring(id)
  score = math.max(0, math.floor(score or 0))
  local out = { score = score, items = {}, pokemon = {}, lost = { items = 0, pokemon = 0 } }

  -- watts: the score's plus anything picked up, inside the run and day caps
  local want = math.max(0, math.floor(scoreWatts or 0)) + p.bonusWatts
  local watts = math.min(want, L.WATTS_PER_RUN, R.left(st).watts)
  out.watts, out.wattsCapped = watts, watts < want
  if watts > 0 then
    m.daily.watts = m.daily.watts + watts
    if not call("earn", st, watts, source) then
      st.watts = (st.watts or 0) + watts
      st.lifetimeWatts = (st.lifetimeWatts or 0) + watts
    end
  end

  -- items and Pokemon (each checked against the day again: two runs could
  -- have been open at once in principle)
  -- With the economy, its answer stands (false = its bag is full); only
  -- without one do the walker's own three slots take them.
  local hasE = R.economy() ~= nil
  local function grant(fn, ...)
    local okCall, res = call(fn, ...)
    return okCall and res ~= false and res ~= nil
  end
  for _, name in ipairs(p.items) do
    if R.left(st).items > 0 then
      local ok
      if hasE then ok = grant("grantItem", st, name, 1, source) else ok = fallbackItem(st, name) end
      if ok then
        m.daily.items = m.daily.items + 1
        out.items[#out.items + 1] = name
        note(st, ("Won %s in a minigame."):format(name))
      else out.lost.items = out.lost.items + 1 end
    else out.lost.items = out.lost.items + 1 end
  end
  for _, mon in ipairs(p.pokemon) do
    if R.left(st).pokemon > 0 then
      local ok
      if hasE then ok = grant("grantPokemon", st, mon.dex, mon.level, source, mon.name) else ok = fallbackPokemon(st, mon) end
      if ok then
        m.daily.pokemon = m.daily.pokemon + 1
        out.pokemon[#out.pokemon + 1] = mon
        note(st, ("Caught %s in a minigame!"):format(mon.name or "a Pokemon"))
      else out.lost.pokemon = out.lost.pokemon + 1 end
    else out.lost.pokemon = out.lost.pokemon + 1 end
  end

  -- friendship: a little, for a real run
  local fr = 0
  if (seconds or 0) >= L.MIN_RUN_SECONDS and st.walking then
    fr = math.min(score > 0 and L.FRIENDSHIP_PER_RUN or 1, R.left(st).friendship)
    if fr > 0 then
      m.daily.friendship = m.daily.friendship + fr
      if not call("friendship", st, fr) then
        st.walking.friendship = math.min(255, (tonumber(st.walking.friendship) or 70) + fr)
      end
    end
  end
  out.friendship = fr

  -- the score: the economy's rank when it keeps one (nil = off its top ten),
  -- else our own table's
  local okRank, rank = call("recordScore", st, id, score)
  local list = g.scores
  local entry = { score = score, watts = watts, t = R.clock() }
  local pos = #list + 1
  for i, e in ipairs(list) do if score > (e.score or 0) then pos = i break end end
  table.insert(list, pos, entry)
  while #list > R.TOP_SCORES do table.remove(list) end
  out.rank = (okRank and tonumber(rank)) or pos
  if okRank then out.placed = rank ~= nil else out.placed = pos <= R.TOP_SCORES end
  entry.rank = out.rank
  out.newBest = score > (g.best or 0)
  g.best = math.max(g.best or 0, score)
  out.best = g.best
  g.plays = (g.plays or 0) + 1
  g.totalWatts = (g.totalWatts or 0) + watts
  m.daily.plays = (m.daily.plays or 0) + 1

  -- achievements: the shared ones, then the game's own
  call("achievement", st, "minigame_played", 1)
  call("achievement", st, "minigame_" .. tostring(id) .. "_played", 1)
  call("achievement", st, "minigame_score_" .. tostring(id), score)
  if watts > 0 then call("achievement", st, "minigame_watts", watts) end
  if #out.items > 0 then call("achievement", st, "minigame_item", #out.items) end
  if #out.pokemon > 0 then
    call("achievement", st, "minigame_catch", #out.pokemon)
    call("achievement", st, "catch", #out.pokemon)       -- the economy's "catch" achievements
  end
  if id == "treasure" and #out.items > 0 then call("achievement", st, "dowse", #out.items) end
  if out.newBest then call("achievement", st, "minigame_new_best", 1) end
  local names = {}
  for name in pairs(p.events) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do call("achievement", st, name, p.events[name]) end

  R.save(st)
  return out
end

-- THE LEADERBOARD a hub shows: the economy's board for the game (what
-- E.recordScore keeps, in its own part of st) when there is one, with the
-- watts each run paid matched in from our list; else our own list.
-- { { score, t, watts }, ... } best first.
function R.board(st, id)
  local mine = R.game(st, id).scores
  local E = R.economy()
  local econBoard
  if E and type(E.econ) == "function" then
    local ok, e = pcall(E.econ, st)
    econBoard = ok and type(e) == "table" and type(e.scores) == "table" and e.scores[tostring(id)] or nil
  end
  if type(econBoard) ~= "table" or #econBoard == 0 then return mine end
  local used, out = {}, {}
  for _, b in ipairs(econBoard) do
    local watts
    for i, m in ipairs(mine) do
      if not used[i] and m.score == b.score then used[i] = true; watts = m.watts break end
    end
    out[#out + 1] = { score = b.score, t = b.t, watts = watts }
  end
  return out
end

function R.save(st)
  if not call("save", st) then pcall(function() walker().save(st) end) end
end

return R
