-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE NEXT-GEN POKEWALKER: the device itself, as data and rules. No drawing
-- (src/ui/PokewalkerScreen.lua) and no save files (src/pokewalker/WalkerLink.lua).
--
-- The original HeartGold / SoulSilver accessory, as documented (Serebii's
-- Pokewalker page; pokemondb's route tables), kept where it is known:
--   * 20 steps = 1 W. The walking Pokemon earns 1 EXP a step but at most one
--     level a walk (the cap is applied when it goes home), and friendship as
--     it walks.
--   * Courses unlock by the watts earned over the device's life; past Town
--     Outskirts they need the National Dex; the last seven are event courses.
--   * On sending, one Pokemon from each of the course's groups A (rare), B and
--     C is drawn, and only those three appear until the next send. Each has a
--     step count before it can appear; a Pokemon of one of the course's three
--     types cuts those by 25%.
--   * POKE RADAR (10 W): four bushes; the one that rustles hides the encounter,
--     its "!" count hinting the group (!!! A, !! A or B, ! B or C). Battle: both
--     sides 4 bars. ATTACK hits (1, a critical 2) or is dodged; EVADE dodges and
--     counters (1), stares, or the wild one flees; CATCH succeeds or it flees.
--     The wild one is never knocked out -- it flees at 0. Losing costs up to
--     10 W. Three catches held; a fourth swaps one out.
--   * DOWSING (3 W): six bushes, two tries; a miss hints "close" (the next bush
--     either side) or "far". Items unlock by steps; three held.
--   * Found something: while walking the Pokemon sometimes finds 10 / 20 / 50 W
--     or an item -- likelier the bigger the friendship.
--   * The trainer card: name, course, today and the last seven days' steps.
--
-- What is this port's own (the "next gen" part): every game sends Pokemon,
-- and a course's encounters are drawn from the game the walker will return
-- to (WalkerCourses), so everything found can go home.

local W = {}

W.FILE = "pokewalker.lua"
W.STEPS_PER_WATT = 20
W.RADAR_COST, W.DOWSE_COST = 10, 3
W.MAX_CAUGHT, W.MAX_ITEMS = 3, 3
W.HISTORY_DAYS = 7
W.FIND_EVERY = 100        -- steps between rolls for a find
W.FRIEND_EVERY = 500      -- steps per point of friendship (an estimate)

local function rnd(n)
  local r = love and love.math and love.math.random
  return r and r(1, n) or math.random(1, n)
end
W._rnd = rnd

local function today() return math.floor(os.time() / 86400) end

-- ------------------------------------------------------------- the state

function W.newState()
  return {
    format = 1,
    watts = 0, lifetimeWatts = 0, stepRemainder = 0,
    lifetimeSteps = 0, days = 0,
    history = {},                -- { day = n, steps = n }, newest first
    course = 0,
    walking = nil,               -- see W.send
    caught = {}, items = {},
    finds = {},                  -- a found thing waiting for the button
    events = {},                 -- unlocked event courses, by id
    log = {},                    -- the diary: { t, text }
    settings = { sound = 1, shade = 3 },
    notices = {},                -- for the screen / phone: { t, text }
  }
end

local function serializer() return require("src.core.SaveSerializer") end

function W.load()
  if love and love.filesystem and love.filesystem.getInfo(W.FILE) then
    local ok, t = pcall(serializer().decode, love.filesystem.read(W.FILE) or "")
    if ok and type(t) == "table" then
      local fresh = W.newState()
      for k, v in pairs(fresh) do if t[k] == nil then t[k] = v end end
      return t
    end
  end
  return W.newState()
end

function W.save(st)
  if love and love.filesystem then love.filesystem.write(W.FILE, serializer().encode(st)) end
end

local function note(st, text)
  st.notices[#st.notices + 1] = { t = os.time(), text = text }
  while #st.notices > 20 do table.remove(st.notices, 1) end
  st.log[#st.log + 1] = { t = os.time(), text = text }
  while #st.log > 100 do table.remove(st.log, 1) end
end
W.note = note

-- --------------------------------------------------------------- courses

-- the courses this walker may pick: by lifetime watts, the National Dex, events
function W.unlocked(st, courses, natDex)
  local out = {}
  for id = 0, 26 do
    local c = courses[id]
    if c then
      local ok
      if c.event then ok = st.events[id] == true
      else ok = (st.lifetimeWatts or 0) >= (c.watts or 0) and (natDex or not c.natDex) end
      if ok then out[#out + 1] = id end
    end
  end
  return out
end

-- what a new watt total unlocks, for the notice
local function newlyUnlocked(courses, before, after)
  local names = {}
  for id = 0, 19 do
    local c = courses and courses[id]
    if c and c.watts and c.watts > before and c.watts <= after then names[#names + 1] = c.name end
  end
  return names
end

-- ----------------------------------------------------------------- steps

local function bumpHistory(st, n)
  local d = today()
  local h = st.history
  if not h[1] or h[1].day ~= d then
    table.insert(h, 1, { day = d, steps = 0 })
    st.days = (st.days or 0) + 1
    while #h > W.HISTORY_DAYS + 1 do table.remove(h) end
  end
  h[1].steps = h[1].steps + n
end

-- the walking Pokemon's chance of a find each FIND_EVERY steps, and its size
local function rollFind(st, course)
  local w = st.walking
  if not w or #st.finds >= 1 then return end
  if rnd(100) > 12 then return end
  local friend = tonumber(w.friendship) or 70
  local roll = rnd(255) + math.floor(friend / 4)
  local kind
  if roll > 280 then kind = "w50" elseif roll > 230 then kind = "w20"
  elseif roll > 150 then kind = "item" else kind = "w10" end
  if kind == "item" then
    local list = W.availableItems(st, course)
    if #list == 0 then kind = "w10" else
      st.finds[#st.finds + 1] = { kind = "item", item = list[rnd(#list)].name }
    end
  end
  if kind ~= "item" then st.finds[#st.finds + 1] = { kind = kind, watts = tonumber(kind:sub(2)) } end
  note(st, ("%s found something!"):format(w.name or "Your Pokemon"))
end

-- n steps from any source (the phone's counter). Returns watts earned.
function W.addSteps(st, n, courses)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return 0 end
  bumpHistory(st, n)
  st.lifetimeSteps = (st.lifetimeSteps or 0) + n
  local total = (st.stepRemainder or 0) + n
  local watts = math.floor(total / W.STEPS_PER_WATT)
  st.stepRemainder = total % W.STEPS_PER_WATT
  local before = st.lifetimeWatts or 0
  st.watts = (st.watts or 0) + watts
  st.lifetimeWatts = before + watts
  local w = st.walking
  if w then
    local was = w.steps or 0
    w.steps = was + n
    w.friendSteps = (w.friendSteps or 0) + n
    while w.friendSteps >= W.FRIEND_EVERY do
      w.friendSteps = w.friendSteps - W.FRIEND_EVERY
      w.friendship = math.min(255, (tonumber(w.friendship) or 70) + 1)
    end
    local course = courses and courses[st.course]
    for _ = 1, math.floor(w.steps / W.FIND_EVERY) - math.floor(was / W.FIND_EVERY) do rollFind(st, course) end
    -- a newly reachable encounter group
    for _, g in ipairs(w.encounters or {}) do
      local need = W.stepsNeeded(st, g)
      if was < need and w.steps >= need and need > 0 then
        note(st, ("Something is rustling on %s..."):format(course and course.name or "the course"))
      end
    end
  end
  for _, name in ipairs(newlyUnlocked(courses, before, st.lifetimeWatts)) do
    note(st, ("New course unlocked: %s!"):format(name))
  end
  return watts
end

-- a find's button press: the watts or the item (when there is room)
function W.collectFind(st)
  local f = table.remove(st.finds, 1)
  if not f then return nil end
  if f.watts then
    st.watts = st.watts + f.watts
    st.lifetimeWatts = st.lifetimeWatts + f.watts
    return ("Got %d W!"):format(f.watts)
  end
  if #st.items >= W.MAX_ITEMS then
    table.insert(st.finds, 1, f)
    return nil, "full", f
  end
  st.items[#st.items + 1] = { name = f.item }
  note(st, ("Found %s."):format(f.item))
  return ("Found %s!"):format(f.item)
end

-- ------------------------------------------------------------ the walk

-- does the walker's Pokemon carry one of the course's advantageous types
local function advantaged(st, course)
  local w = st.walking
  if not (w and course and course.types) then return false end
  for _, t in ipairs(w.types or {}) do
    for _, ct in ipairs(course.types) do
      if tostring(t):upper() == tostring(ct):upper() then return true end
    end
  end
  return false
end
W.advantaged = advantaged

function W.stepsNeeded(st, entry)
  local need = tonumber(entry and entry.steps) or 0
  if st.walking and st.walking.advantage then need = math.floor(need * 3 / 4) end
  return need
end

-- send: `mon` is { raw = the save's own table, species = national dex number,
-- name, level, types = { "FIRE", ... }, friendship, source = { version, slot,
-- box, index } }; `entries` is the course's six encounters already resolved
-- for the source game (WalkerCourses.forGame)
function W.send(st, courseId, mon, entries, course)
  if st.walking then return false, "a Pokemon is already walking" end
  st.course = courseId
  local picks = {}
  for _, g in ipairs({ "A", "B", "C" }) do
    local group = {}
    for _, e in ipairs(entries or {}) do if e.group == g then group[#group + 1] = e end end
    if #group > 0 then picks[#picks + 1] = group[rnd(#group)] end
  end
  st.walking = {
    raw = mon.raw, species = mon.species, name = mon.name, level = mon.level,
    types = mon.types, friendship = mon.friendship, source = mon.source,
    steps = 0, friendSteps = 0, sentAt = os.time(), encounters = picks,
  }
  st.walking.advantage = advantaged(st, course)
  st.finds = {}
  note(st, ("%s went on a walk to %s."):format(mon.name or "Your Pokemon", course and course.name or "a course"))
  return true
end

-- what comes home: the Pokemon (with its steps and friendship), the
-- catches and the items; the walker keeps its watts
function W.takeHome(st, keepPokemon)
  local out = { mon = (not keepPokemon) and st.walking or nil, caught = st.caught, items = st.items }
  st.caught, st.items = {}, {}
  if not keepPokemon then st.walking = nil; st.finds = {} end
  return out
end

-- ---------------------------------------------------------- Poke Radar

-- which of the three drawn encounters the bushes can hold now
local function reachable(st)
  local out = {}
  for _, e in ipairs((st.walking and st.walking.encounters) or {}) do
    if (st.walking.steps or 0) >= W.stepsNeeded(st, e) then out[#out + 1] = e end
  end
  return out
end
W.reachable = reachable

-- start a radar search: four bushes, one rustling, its "!" count
function W.radarStart(st)
  if not st.walking then return nil, "no Pokemon is walking" end
  if (st.watts or 0) < W.RADAR_COST then return nil, "not enough watts" end
  local pool = reachable(st)
  if #pool == 0 then return nil, "nothing around yet -- keep walking" end
  st.watts = st.watts - W.RADAR_COST
  -- C is common, A rare
  local weights = { A = 1, B = 3, C = 6 }
  local sum = 0
  for _, e in ipairs(pool) do sum = sum + (weights[e.group] or 1) end
  local roll, pick = rnd(sum), pool[1]
  for _, e in ipairs(pool) do
    roll = roll - (weights[e.group] or 1)
    if roll <= 0 then pick = e break end
  end
  local marks = pick.group == "A" and (rnd(2) == 1 and 3 or 2) or pick.group == "B" and (rnd(2) == 1 and 2 or 1) or 1
  return { bush = rnd(4), marks = marks, encounter = pick, timer = 3.0 }
end

-- the battle: one turn; returns the new battle state and what happened
function W.newBattle(enc) return { me = 4, wild = 4, enc = enc, over = nil } end

function W.battleTurn(st, b, action)
  if b.over then return b, nil end
  local r = rnd(100)
  local text
  if action == "attack" then
    if r <= 15 then text = "It dodged!"
    elseif r <= 30 then b.wild = b.wild - 2; text = "A critical hit!"
    else b.wild = b.wild - 1; text = "It hit!" end
  elseif action == "evade" then
    if r <= 40 then b.wild = b.wild - 1; text = "Dodged and countered!"
    elseif r <= 85 then text = "They stared each other down..."
    else b.over = "fled"; text = "The wild Pokemon fled!" end
  elseif action == "catch" then
    -- likelier the weaker it is
    local chance = ({ [4] = 25, [3] = 40, [2] = 60, [1] = 80 })[math.max(1, b.wild)] or 25
    if r <= chance then b.over = "caught"; text = "Gotcha!"
    else b.over = "fled"; text = "It broke free and fled!" end
  end
  if not b.over and b.wild <= 0 then b.over = "fled"; text = (text or "") .. " The wild Pokemon fled!" end
  -- the wild one hits back when the fight goes on
  if not b.over and action ~= "catch" and rnd(100) <= 35 then
    b.me = b.me - 1
    text = (text or "") .. " It attacked!"
    if b.me <= 0 then
      b.over = "lost"
      local lost = math.min(st.watts or 0, 10)
      st.watts = (st.watts or 0) - lost
      text = text .. (" Your Pokemon fainted... lost %d W."):format(lost)
    end
  end
  if b.over == "caught" then
    local e = b.enc
    local caught = { species = e.species, name = e.name, level = e.level, gender = e.gender, moves = e.moves }
    if #st.caught < W.MAX_CAUGHT then
      st.caught[#st.caught + 1] = caught
      note(st, ("Caught %s!"):format(e.name or "a Pokemon"))
    else
      b.swap = caught
    end
  end
  return b, text
end

function W.swapCaught(st, index, caught)
  if st.caught[index] and caught then st.caught[index] = caught end
end

-- ------------------------------------------------------------ Dowsing

function W.availableItems(st, course)
  local out = {}
  local steps = st.walking and st.walking.steps or 0
  for _, it in ipairs((course and course.items) or {}) do
    if steps >= (tonumber(it.steps) or 0) then out[#out + 1] = it end
  end
  return out
end

function W.dowseStart(st, course)
  if not st.walking then return nil, "no Pokemon is walking" end
  if (st.watts or 0) < W.DOWSE_COST then return nil, "not enough watts" end
  local list = W.availableItems(st, course)
  if #list == 0 then return nil, "nothing to find yet" end
  st.watts = st.watts - W.DOWSE_COST
  return { at = rnd(6), item = list[rnd(#list)].name, tries = 2 }
end

-- try bush i: "found", "close", "far" or "none" (out of tries)
function W.dowseTry(st, d, i)
  if d.tries <= 0 then return "none" end
  d.tries = d.tries - 1
  if i == d.at then
    if #st.items < W.MAX_ITEMS then
      st.items[#st.items + 1] = { name = d.item }
      note(st, ("Dowsed up %s."):format(d.item))
    else
      d.swap = { name = d.item }
    end
    d.done = true
    return "found"
  end
  if d.tries <= 0 then d.done = true return "none" end
  return math.abs(i - d.at) == 1 and "close" or "far"
end

function W.swapItem(st, index, item)
  if st.items[index] and item then st.items[index] = item end
end

-- ----------------------------------------------------------- the card

function W.lastWeek(st)
  local out, sum = {}, 0
  local d = today()
  for i = 0, W.HISTORY_DAYS do
    local steps = 0
    for _, h in ipairs(st.history or {}) do if h.day == d - i then steps = h.steps end end
    out[i + 1] = steps
    if i >= 1 then sum = sum + steps end
  end
  return out, sum
end

return W
