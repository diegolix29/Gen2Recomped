-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MONSTER WALKER'S ECONOMY: every watt that does not come from steps, and
-- what watts buy. Rules only -- the pages are src/ui/WalkerEconomyPages.lua,
-- the shelves src/pokewalker/WalkerShop.lua.
--
--   PASSIVE WATTS   5 W an hour while the app is open (launcher, background,
--                   or a game being played), at most 50 W a day from this.
--                   main.lua feeds E.tick(dt) every frame and E.focus(f) on
--                   focus changes; a phone that pauses the app in the
--                   background is credited the wall-clock gap on its return.
--   DAILY LOGIN     the first walker open of a day: 5 W, growing 5 W a day of
--                   streak to 30 W; a missed day starts over. In the Diary.
--   ACHIEVEMENTS    once each, for watts
--   LEADERBOARDS    the top 10 local scores of each minigame, with dates
--   THE REWARDS API for the minigames (src/ui/WalkerMinigames.lua and
--                   src/pokewalker/minigames/*): earn, grantItem,
--                   grantPokemon, recordScore, achievement, friendship, save
--   THE WATT SHOP   items / Pokemon / Mystery Gifts into a game's save (its
--                   walkerInbox, unpacked by the game -- WalkerInbox), and
--                   the walker's own cosmetics and event courses
--
-- Everything lives in the walker state under `st.econ` (created on first use),
-- so pokewalker.lua stays one file.

local W = require("src.pokewalker.Walker")

local E = {}

E.PASSIVE_SECONDS_PER_WATT = 720      -- 5 W an hour
E.PASSIVE_DAILY_CAP = 50
E.MAX_FRAME = 5                        -- a frame longer than this is a stall, not play
E.MAX_GAP = 3 * 86400                  -- a background stretch credited at most (the cap rules anyway)
E.FLUSH_EVERY = 60                     -- seconds of play between credits
E.SAVE_EVERY = 300                     -- partial progress is written at least this often
E.STREAK_STEP, E.STREAK_MAX = 5, 30
E.BOARD_SIZE = 10
E.MAX_BAG_ITEMS = 10                   -- distinct item stacks the walker carries
E.MAX_BAG_MONS = 6                     -- catches + gifted Pokemon the walker carries
E.FRIEND_EXP = 10                      -- E.friendship's default EXP per point

E.clock = os.time                      -- tests replace this

-- the LOCAL calendar day (streaks and the passive cap follow the player's
-- midnight, not UTC's)
function E.day(t)
  local d = os.date("*t", t or E.clock())
  return math.floor(os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

function E.econ(st)
  local e = st.econ
  if type(e) ~= "table" then e = {}; st.econ = e end
  e.counters = e.counters or {}
  e.done = e.done or {}                 -- achievement id -> when
  e.scores = e.scores or {}             -- minigame id -> { { score, t }, ... } best first
  e.login = e.login or { streak = 0, best = 0 }
  e.passive = e.passive or { watts = 0, secs = 0 }
  e.earned = e.earned or {}             -- source -> watts
  e.owned = e.owned or {}
  for _, k in ipairs({ "theme", "shell", "sound" }) do e.owned[k] = e.owned[k] or {} end
  e.use = e.use or {}                   -- kind -> cosmetic id in use
  e.bought = e.bought or {}             -- today's / this week's one-offs
  return e
end

local function norm(s)
  s = tostring(s or ""):gsub("\195\169", "E"):gsub("\195\137", "E")
  return (s:upper():gsub("[^%w]", ""))
end

-- ------------------------------------------------------------- watts

local function unlockNotes(st, before)
  local ok, courses = pcall(function() return require("src.pokewalker.WalkerCourses").routes() end)
  if not ok or type(courses) ~= "table" then return end
  for id = 0, 19 do
    local c = courses[id]
    if c and c.watts and c.watts > before and c.watts <= (st.lifetimeWatts or 0) then
      W.note(st, ("New course unlocked: %s!"):format(c.name))
    end
  end
end

-- every non-step watt goes through here: the balance, the lifetime total
-- (courses unlock on it, as the original's do on all watts earned), the
-- per-source tally
local function addWatts(st, n, source)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return 0 end
  local e = E.econ(st)
  local before = st.lifetimeWatts or 0
  st.watts = (st.watts or 0) + n
  st.lifetimeWatts = before + n
  source = tostring(source or "other")
  e.earned[source] = (e.earned[source] or 0) + n
  -- the walk's progress too, at the pedometer's 20 steps a watt, so a phone
  -- with no step counter still reaches the course's later items and
  -- Pokemon (Walker.walkSteps)
  if type(st.walking) == "table" then
    st.walking.bonusSteps = (tonumber(st.walking.bonusSteps) or 0) + n * 20
  end
  unlockNotes(st, before)
  return n
end

-- ------------------------------------------------------- achievements

E.ACHIEVEMENTS = {
  { id = "steps1k",   name = "First steps",      desc = "Walk 1,000 steps",           stat = "steps",  goal = 1000,   reward = 10 },
  { id = "steps10k",  name = "Out and about",    desc = "Walk 10,000 steps",          stat = "steps",  goal = 10000,  reward = 25 },
  { id = "steps50k",  name = "Trailblazer",      desc = "Walk 50,000 steps",          stat = "steps",  goal = 50000,  reward = 60 },
  { id = "steps100k", name = "Marathoner",       desc = "Walk 100,000 steps",         stat = "steps",  goal = 100000, reward = 100 },
  { id = "steps500k", name = "Globetrotter",     desc = "Walk 500,000 steps",         stat = "steps",  goal = 500000, reward = 300 },
  { id = "watts100",  name = "Spark",            desc = "Earn 100 W",                 stat = "watts",  goal = 100,    reward = 10 },
  { id = "watts1k",   name = "Live wire",        desc = "Earn 1,000 W",               stat = "watts",  goal = 1000,   reward = 25 },
  { id = "watts5k",   name = "Power plant",      desc = "Earn 5,000 W",               stat = "watts",  goal = 5000,   reward = 60 },
  { id = "watts20k",  name = "Thunderstorm",     desc = "Earn 20,000 W",              stat = "watts",  goal = 20000,  reward = 150 },
  { id = "catch1",    name = "First catch",      desc = "Catch a Pokemon on the walker", stat = "catch", goal = 1,    reward = 10 },
  { id = "catch10",   name = "Collector",        desc = "Catch 10 Pokemon",           stat = "catch",  goal = 10,     reward = 40 },
  { id = "catch50",   name = "Walker ranger",    desc = "Catch 50 Pokemon",           stat = "catch",  goal = 50,     reward = 120 },
  { id = "dowse10",   name = "Treasure hunter",  desc = "Dowse up 10 items",          stat = "dowse",  goal = 10,     reward = 30 },
  { id = "play1",     name = "Game on",          desc = "Finish a minigame",          stat = "minigame_plays", goal = 1,   reward = 10 },
  { id = "play25",    name = "Arcade regular",   desc = "Finish 25 minigames",        stat = "minigame_plays", goal = 25,  reward = 40 },
  { id = "play100",   name = "Arcade legend",    desc = "Finish 100 minigames",       stat = "minigame_plays", goal = 100, reward = 100 },
  { id = "best1",     name = "High score!",      desc = "Beat your best in a minigame", stat = "minigame_best", goal = 1,  reward = 15 },
  { id = "best10",    name = "Record breaker",   desc = "Beat your best 10 times",    stat = "minigame_best", goal = 10,  reward = 60 },
  { id = "boards3",   name = "All-rounder",      desc = "Score in 3 different minigames", stat = "boards", goal = 3,     reward = 40 },
  { id = "buy1",      name = "First purchase",   desc = "Buy something in the Watt Shop", stat = "purchases", goal = 1,  reward = 10 },
  { id = "buy10",     name = "Good customer",    desc = "Make 10 purchases",          stat = "purchases", goal = 10,  reward = 40 },
  { id = "buy50",     name = "Big spender",      desc = "Make 50 purchases",          stat = "purchases", goal = 50,  reward = 120 },
  { id = "streak3",   name = "Habit",            desc = "Open the walker 3 days in a row", stat = "streak", goal = 3, reward = 15 },
  { id = "streak7",   name = "Week strong",      desc = "A 7-day streak",             stat = "streak", goal = 7,      reward = 40 },
  { id = "streak30",  name = "Devoted",          desc = "A 30-day streak",            stat = "streak", goal = 30,     reward = 150 },
  { id = "friend255", name = "Best friends",     desc = "A walking Pokemon reaches full friendship", stat = "friend", goal = 255, reward = 50 },
}

local STATS = {
  steps = function(st) return st.lifetimeSteps or 0 end,
  watts = function(st) return st.lifetimeWatts or 0 end,
  streak = function(_, e) return e.login.best or 0 end,
  boards = function(_, e) local n = 0 for _ in pairs(e.scores) do n = n + 1 end return n end,
  friend = function(st, e)
    return math.max(e.counters.friend_max or 0, tonumber(st.walking and st.walking.friendship) or 0)
  end,
}

function E.stat(st, name)
  local e = E.econ(st)
  local fn = STATS[name]
  if fn then return fn(st, e) end
  return tonumber(e.counters[name]) or 0
end

-- award every achievement now reached; returns the newly earned defs
function E.check(st)
  local e = E.econ(st)
  local out = {}
  for _ = 1, 10 do               -- an award can reach a watts goal: go again
    local more = false
    for _, a in ipairs(E.ACHIEVEMENTS) do
      if not e.done[a.id] and E.stat(st, a.stat) >= a.goal then
        e.done[a.id] = E.clock()
        addWatts(st, a.reward, "achievement")
        W.note(st, ("Achievement: %s! +%d W"):format(a.name, a.reward))
        out[#out + 1] = a
        more = true
      end
    end
    if not more then break end
  end
  return out
end

-- for the page: { def, value, done = time or nil }
function E.progress(st)
  local e = E.econ(st)
  local out = {}
  for _, a in ipairs(E.ACHIEVEMENTS) do
    out[#out + 1] = { def = a, value = math.min(a.goal, E.stat(st, a.stat)), done = e.done[a.id] }
  end
  return out
end

-- ------------------------------------------------------ THE REWARDS API

-- Adds watts (minigame earnings have no cap) and records them. Returns the
-- watts actually added.
function E.earn(st, watts, source)
  local n = addWatts(st, watts, source or "minigame")
  if n > 0 then
    local e = E.econ(st)
    e.counters.earned = (e.counters.earned or 0) + n
    E.check(st)
  end
  return n
end

-- An item into the walker's own bag (st.items); it goes home with the
-- presents. Same-named items stack (`count`). Returns true, or false and why.
function E.grantItem(st, itemName, count, source)
  if type(itemName) ~= "string" or itemName == "" then return false, "no item" end
  count = math.max(1, math.floor(tonumber(count) or 1))
  local want = norm(itemName)
  for _, it in ipairs(st.items) do
    if it.granted and norm(it.name) == want then
      it.count = (it.count or 1) + count
      W.note(st, ("Got %s x%d!"):format(itemName, count))
      return true
    end
  end
  if #st.items >= E.MAX_BAG_ITEMS then return false, "the walker's bag is full -- send presents home" end
  st.items[#st.items + 1] = { name = itemName, count = count > 1 and count or nil, granted = true, source = source }
  W.note(st, count > 1 and ("Got %s x%d!"):format(itemName, count) or ("Got %s!"):format(itemName))
  local e = E.econ(st)
  e.counters.items_granted = (e.counters.items_granted or 0) + count
  return true
end

-- A Pokemon onto the walker (st.caught, the Poke Radar's shape); it goes home
-- with the presents into the PC. Returns the entry, or false and why.
function E.grantPokemon(st, dexNumber, level, source, fallbackName)
  local dex = math.floor(tonumber(dexNumber) or 0)
  if dex < 1 or dex > 649 then return false, "no such Pokemon" end
  if #st.caught >= E.MAX_BAG_MONS then return false, "the walker is full -- send presents home" end
  local okC, Courses = pcall(require, "src.pokewalker.WalkerCourses")
  local sp = okC and Courses.species()[dex]
  local entry = { species = dex, name = (sp and sp.name) or fallbackName or ("#" .. dex),
                  level = math.max(1, math.min(100, math.floor(tonumber(level) or 5))),
                  granted = true, source = source }
  st.caught[#st.caught + 1] = entry
  W.note(st, ("%s joined you!"):format(entry.name))
  local e = E.econ(st)
  e.counters.mons_granted = (e.counters.mons_granted or 0) + 1
  return entry
end

-- A minigame's score onto its top-10 board (best first; a tie ranks under
-- the earlier score). Returns the rank 1..10, or nil when it did not place.
function E.recordScore(st, gameId, score)
  gameId = tostring(gameId or "?")
  score = tonumber(score) or 0
  local e = E.econ(st)
  local board = e.scores[gameId] or {}
  e.scores[gameId] = board
  local pos = #board + 1
  for i, s in ipairs(board) do if score > (tonumber(s.score) or 0) then pos = i break end end
  e.counters.minigame_plays = (e.counters.minigame_plays or 0) + 1
  local rank
  if pos <= E.BOARD_SIZE then
    table.insert(board, pos, { score = score, t = E.clock() })
    while #board > E.BOARD_SIZE do table.remove(board) end
    rank = pos
    -- a new best, when there was one to beat
    if pos == 1 and #board > 1 then e.counters.minigame_best = (e.counters.minigame_best or 0) + 1 end
  end
  E.check(st)
  return rank
end

-- Feeds an achievement counter (any name; the ones E.ACHIEVEMENTS reads:
-- catch, dowse, minigame_plays, minigame_best, purchases). Returns the
-- achievements newly earned.
function E.achievement(st, eventName, amount)
  local e = E.econ(st)
  local k = tostring(eventName or "?")
  e.counters[k] = (tonumber(e.counters[k]) or 0) + (tonumber(amount) or 1)
  return E.check(st)
end

-- Friendship (and EXP: `exp`, default amount * 10) for the walking Pokemon,
-- carried home with it: friendship up to 255, the EXP with the walk's steps
-- -- still at most one level a walk (WalkerInbox). Returns the friendship.
function E.friendship(st, amount, exp)
  local w = st.walking
  if not w then return false, "no Pokemon is walking" end
  amount = math.floor(tonumber(amount) or 0)
  w.friendship = math.max(0, math.min(255, (tonumber(w.friendship) or 70) + amount))
  local x = math.floor(tonumber(exp) or amount * E.FRIEND_EXP)
  if x > 0 then w.bonusExp = (w.bonusExp or 0) + x end
  local e = E.econ(st)
  e.counters.friend_max = math.max(e.counters.friend_max or 0, w.friendship)
  E.check(st)
  return w.friendship
end

function E.save(st) W.save(st or W.live) end

-- the walker state everyone in this process shares (the screen, the passive
-- credit, the minigames)
function E.state() return W.load() end

-- --------------------------------------------------------- daily login

-- the first walker open of the day: returns the bonus and the streak, or nil
function E.dailyLogin(st)
  local e = E.econ(st)
  local today = E.day()
  local L = e.login
  if L.day and L.day >= today then return nil end
  if L.day == today - 1 then L.streak = (L.streak or 0) + 1 else L.streak = 1 end
  L.day = today
  L.best = math.max(L.best or 0, L.streak)
  local bonus = math.min(E.STREAK_MAX, E.STREAK_STEP * L.streak)
  addWatts(st, bonus, "login")
  if L.streak > 1 then W.note(st, ("Day %d of your streak! Daily bonus +%d W"):format(L.streak, bonus))
  else W.note(st, ("Welcome back! Daily bonus +%d W"):format(bonus)) end
  E.check(st)
  return bonus, L.streak
end

function E.nextLoginBonus(st)
  local L = E.econ(st).login
  local s = (L.day == E.day()) and (L.streak or 0) + 1 or 1
  return math.min(E.STREAK_MAX, E.STREAK_STEP * s)
end

-- ------------------------------------------------------- passive watts

-- `secs` of the app being open, credited into today's 50 W. Returns watts added.
function E.creditSeconds(st, secs, now)
  local e = E.econ(st)
  local p = e.passive
  local today = E.day(now)
  if p.day ~= today then p.day = today; p.watts = 0 end
  local cap = E.PASSIVE_DAILY_CAP
  if (p.watts or 0) >= cap then p.secs = 0 return 0 end
  p.secs = (p.secs or 0) + math.max(0, tonumber(secs) or 0)
  local per = E.PASSIVE_SECONDS_PER_WATT
  local n = math.min(math.floor(p.secs / per), cap - p.watts)
  if n > 0 then
    p.secs = p.secs - n * per
    p.watts = p.watts + n
    addWatts(st, n, "passive")
    if p.watts >= cap then W.note(st, ("Today's open-app watts are all in: %d W."):format(cap)) end
    E.check(st)
  end
  if p.watts >= cap then p.secs = 0 end
  return n
end

-- the process's running tally (not saved: E.flush moves it into the state)
local run = { pending = 0, ticked = 0, sinceFlush = 0, unsaved = 0, away = nil }
E._run = run

function E.tick(dt)
  dt = tonumber(dt) or 0
  if dt <= 0 then return end
  dt = math.min(dt, E.MAX_FRAME)
  run.pending = run.pending + dt
  run.ticked = run.ticked + dt
  run.sinceFlush = run.sinceFlush + dt
  if run.sinceFlush >= E.FLUSH_EVERY then E.flush() end
end

-- move the tally into the walker state; writes it when a watt came in, every
-- E.SAVE_EVERY seconds of partial progress, or when forced (focus lost, quit)
function E.flush(force)
  run.sinceFlush = 0
  local st = W.live
  if not st then
    -- a player who never opened the walker: nothing is written for them; the
    -- time waits (up to a day's worth) for the first open
    if not (love and love.filesystem and love.filesystem.getInfo(W.FILE)) then
      run.pending = math.min(run.pending, E.PASSIVE_DAILY_CAP * E.PASSIVE_SECONDS_PER_WATT)
      return 0
    end
    st = W.load()
  end
  local n = 0
  if run.pending > 0 then
    run.unsaved = run.unsaved + run.pending
    n = E.creditSeconds(st, run.pending)
    run.pending = 0
  end
  if run.unsaved > 0 and (n > 0 or force or run.unsaved >= E.SAVE_EVERY) then
    run.unsaved = 0
    pcall(W.save, st)
  end
  return n
end

-- focus lost: write now (a phone may kill the app in the background) and note
-- when; focus back: the wall-clock time away that no frame ticked through
-- (LOVE stops updating a backgrounded Android app) is credited
function E.focus(f)
  local now = E.clock()
  if not f then
    run.away = { t = now, ticked = run.ticked }
    E.flush(true)
  elseif run.away then
    local gap = now - run.away.t
    local ticked = run.ticked - run.away.ticked
    run.away = nil
    if gap > 0 and gap <= E.MAX_GAP then run.pending = run.pending + math.max(0, gap - ticked) end
    E.flush(true)
  end
end

function E.quit() E.flush(true) end

-- -------------------------------------------------------- the Watt Shop

local Shop = require("src.pokewalker.WalkerShop")

local function weekOf(day) return math.floor(((day or E.day()) + 3) / 7) end
E.week = weekOf

local function pay(st, price, what)
  st.watts = (st.watts or 0) - price
  local e = E.econ(st)
  e.counters.purchases = (e.counters.purchases or 0) + 1
  e.counters.spent = (e.counters.spent or 0) + price
  W.note(st, ("Bought %s for %d W."):format(what, price))
  E.check(st)
  W.save(st)
end

local function afford(st, price)
  if (st.watts or 0) < (tonumber(price) or 0) then return false, ("you need %d W"):format(price) end
  return true
end

local function destination(st,target)
  local source=st.walking and st.walking.source
  if source and source.version and source.slot then return source end
  return target
end

local function deliver(target, parcel)
  if not (target and target.version and target.slot) then return false, "choose a game and save first" end
  local Link = require("src.pokewalker.WalkerLink")
  return Link.deliverTo(target.version, target.slot, parcel)
end

-- a one-off already taken (today's stock, this week's gift)
function E.taken(st, key) return E.econ(st).bought[key] == true end

-- drop yesterday's stock and last week's gifts
local function pruneBought(st)
  local b = E.econ(st).bought
  local d, wk = E.day(), weekOf()
  for k in pairs(b) do
    local kind, n = k:match("^(%a+):(%-?%d+)")
    n = tonumber(n)
    if (kind == "mon" and n ~= d) or (kind == "gift" and n ~= wk) then b[k] = nil end
  end
end

-- the keys
function E.stockKey(version, dex, day) return ("mon:%d:%s:%d"):format(day or E.day(), tostring(version), dex) end
function E.giftKey(id, week) return ("gift:%d:%s"):format(week or weekOf(), tostring(id)) end

function E.buyItem(st, entry, target)
  target=destination(st,target)
  if not entry then return false, "nothing chosen" end
  if Shop.genOf(target and target.version) < (entry.gen or 1) then return false, "that game does not have it" end
  local ok, why = afford(st, entry.price)
  if not ok then return false, why end
  ok, why = deliver(target, { items = { { name = entry.name, count = entry.count } } })
  if not ok then return false, why end
  pay(st, entry.price, (entry.count or 1) > 1 and ("%s x%d"):format(entry.name, entry.count) or entry.name)
  return true,why
end

function E.buyPokemon(st, offer, target)
  target=destination(st,target)
  if not offer then return false, "nothing chosen" end
  local Courses = require("src.pokewalker.WalkerCourses")
  if offer.dex > Courses.maxDexFor(target and target.version) then return false, "that game does not have it" end
  pruneBought(st)
  local key = E.stockKey(target and target.version, offer.dex)
  if E.taken(st, key) then return false, "sold out until tomorrow" end
  local ok, why = afford(st, offer.price)
  if not ok then return false, why end
  ok, why = deliver(target, { caught = { { species = offer.dex, name = offer.name, level = offer.level } } })
  if not ok then return false, why end
  E.econ(st).bought[key] = true
  pay(st, offer.price, ("%s Lv%d"):format(offer.name, offer.level))
  return true,why
end

function E.buyGift(st, gift, target)
  target=destination(st,target)
  if not gift then return false, "nothing chosen" end
  if Shop.genOf(target and target.version) < (gift.gen or 1) then return false, "that game cannot receive it" end
  pruneBought(st)
  local key = E.giftKey(gift.id)
  if E.taken(st, key) then return false, "already claimed this week" end
  local ok, why = afford(st, gift.price)
  if not ok then return false, why end
  local parcel, what
  if gift.kind == "mon" then
    local sp = require("src.pokewalker.WalkerCourses").species()[gift.dex]
    what = ("%s Lv%d"):format(sp and sp.name or ("#" .. gift.dex), gift.level)
    parcel = { caught = { { species = gift.dex, name = sp and sp.name, level = gift.level, gift = true } } }
  else
    what = (gift.count or 1) > 1 and ("%s x%d"):format(gift.name, gift.count) or gift.name
    parcel = { items = { { name = gift.name, count = gift.count } } }
  end
  ok, why = deliver(target, parcel)
  if not ok then return false, why end
  E.econ(st).bought[key] = true
  pay(st, gift.price, "Mystery Gift: " .. what)
  return true,why
end

-- THE EVENTS SHELF (src/pokewalker/WalkerEvents.lua): a real distribution,
-- once per save, queued into the target save for the game to hand over
function E.buyEvent(st, ev, target)
  target=destination(st,target)
  if not ev then return false, "nothing chosen" end
  if not (target and target.version and target.slot) then return false, "choose a game and save first" end
  local ok, why = afford(st, ev.price)
  if not ok then return false, why end
  ok, why = require("src.pokewalker.WalkerEvents").queue(target.version, target.slot, ev)
  if not ok then return false, why end
  pay(st, ev.price, "Event: " .. tostring(ev.name))
  return true,why
end

-- cosmetics: kind theme / shell / sound, or course (an event course id)
function E.owns(st, kind, id)
  if kind == "course" then return st.events and st.events[id] == true end
  local c = Shop.cosmetic(kind, id)
  if c and (c.price or 0) == 0 then return true end
  return E.econ(st).owned[kind] and E.econ(st).owned[kind][id] == true
end

function E.buyCosmetic(st, kind, id, price)
  if E.owns(st, kind, id) then return false, "already yours" end
  local name
  if kind == "course" then
    local ok, routes = pcall(function() return require("src.pokewalker.WalkerCourses").routes() end)
    local c = ok and routes[id]
    if not (c and c.event) then return false, "no such course" end
    name = c.name
    for _, ec in ipairs(Shop.eventCourses(routes)) do if ec.id == id then price = ec.price end end
  else
    local c = Shop.cosmetic(kind, id)
    if not c then return false, "no such thing" end
    name, price = c.name, c.price
  end
  local ok, why = afford(st, price)
  if not ok then return false, why end
  if kind == "course" then
    st.events = st.events or {}
    st.events[id] = true
  else
    E.econ(st).owned[kind][id] = true
    E.econ(st).use[kind] = id
  end
  pay(st, price, name)
  return true
end

function E.use(st, kind, id)
  if not E.owns(st, kind, id) then return false end
  E.econ(st).use[kind] = id
  W.save(st)
  return true
end

function E.using(st, kind)
  local e = E.econ(st)
  local id = e.use[kind]
  if id and E.owns(st, kind, id) then return id end
  return (Shop.COSMETICS[kind] and Shop.COSMETICS[kind][1] or {}).id
end

return E
