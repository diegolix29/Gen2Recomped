-- Run:  python tools/run_lua_check.py tools/walker_minigames_check.lua
--
-- THE POKEWALKER MINIGAMES, headless: each game's scoring and its watts, the
-- reward plumbing (economy present and absent), the daily and per-run
-- budgets, the day turning over, and the hub's flow from a card to a result
-- on the leaderboard. Runs without love (no drawing), with seeded randomness,
-- and never touches a save: Walker.save is stubbed.

package.path = './?.lua;./?/init.lua;' .. package.path
local PASS, FAIL = 0, 0
local function check(c, l, extra)
  if c then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. l .. (extra ~= nil and ('  [' .. tostring(extra) .. ']') or '')) end
end
local function info(...) print('  ' .. string.format(...)) end

local Walker = require('src.pokewalker.Walker')
Walker.save = function() end
local Rewards = require('src.pokewalker.minigames.Rewards')
local Context = require('src.pokewalker.minigames.Context')
local Base = require('src.pokewalker.minigames.Base')
local Runner = require('src.pokewalker.minigames.JumpRunner')
local Catch = require('src.pokewalker.minigames.CatchTiming')
local Treasure = require('src.pokewalker.minigames.TreasureHunt')
local Memory = require('src.pokewalker.minigames.MemoryMatch')
local Rhythm = require('src.pokewalker.minigames.RhythmTap')
local Hub = require('src.ui.WalkerMinigames')

local NOW = 20000 * 86400 + 3600
Rewards.clock = function() return NOW end

-- a fake economy that records every call
local calls
local function fakeEconomy()
  calls = {}
  local E = {}
  for _, name in ipairs({ 'earn', 'grantItem', 'grantPokemon', 'achievement', 'friendship', 'save' }) do
    E[name] = function(...) calls[#calls + 1] = { name, ... }; return true end
  end
  E.recordScore = function(st, id, score) calls[#calls + 1] = { 'recordScore', st, id, score }; return 7 end
  E.earn = function(st, w, src) calls[#calls + 1] = { 'earn', st, w, src }; st.watts = (st.watts or 0) + w end
  return E
end
local function count(name)
  local n = 0
  for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
  return n
end
local function find(name, k, v)
  for _, c in ipairs(calls) do if c[1] == name and c[k] == v then return c end end
end

local function newState(walking)
  local st = Walker.newState()
  st.course = 0
  if walking then
    st.walking = { species = 25, name = 'PIKACHU', level = 10, friendship = 100, steps = 0, encounters = {} }
  end
  return st
end

-- =============================================================== Context
do
  local st = newState(true)
  local ctx = Context.build(st, 42)
  check(#ctx.wild == 6, 'the course has its six wild Pokemon', #ctx.wild)
  check(ctx.course.name == 'Refreshing Field', 'course 0 is Refreshing Field', ctx.course.name)
  check(ctx.walker.dex == 25 and not ctx.standIn, 'the walking Pokemon plays')
  check(#ctx.items >= 5, 'items: the course\'s cheap ones and the basics', #ctx.items)
  local ctx2 = Context.build(newState(false), 42)
  check(ctx2.standIn and ctx2.walker.dex == 25, 'nobody walking: Pikachu stands in')
  -- determinism and the group weights
  local a, b = Context.build(st, 9), Context.build(st, 9)
  local same = true
  for _ = 1, 50 do if a.rng(1000) ~= b.rng(1000) then same = false end end
  check(same, 'the same seed plays the same')
  local groups = { A = 0, B = 0, C = 0 }
  for _ = 1, 3000 do local e = Context.pickWild(a); groups[e.group] = groups[e.group] + 1 end
  check(groups.C > groups.B and groups.B > groups.A, 'wild picks: C common, A rare', groups.A .. '/' .. groups.B .. '/' .. groups.C)
end

-- =============================================================== Rewards
do
  Rewards._economy = false   -- no economy module: the fallbacks
  local st = newState(true)
  st.watts = 5
  local p = Rewards.newPurse(st, 'runner')
  Rewards.addWatts(p, 3)
  check(Rewards.addItem(p, 'Potion') and Rewards.addItem(p, 'Oran Berry') and Rewards.addItem(p, 'Poke Ball'), 'three items fit a run')
  check(not Rewards.addItem(p, 'Revive'), 'a fourth item does not (ITEMS_PER_RUN)')
  check(Rewards.addPokemon(p, 16, 5, 'Pidgey'), 'one Pokemon a run')
  check(not Rewards.addPokemon(p, 19, 5, 'Rattata'), 'not two (POKEMON_PER_RUN)')
  local r = Rewards.settle(p, 1234, 12, 60)
  check(r.watts == 15 and st.watts == 20, 'fallback: watts straight onto st.watts (12 + 3 picked up)', st.watts)
  check(#st.items == 3 and st.items[1].name == 'Potion', 'fallback: items into the walker\'s bag', #st.items)
  check(#st.caught == 1 and st.caught[1].species == 16, 'fallback: the catch into the walker\'s catches')
  check(st.walking.friendship == 102, 'fallback: friendship +2 for a real run', st.walking.friendship)
  check(r.rank == 1 and r.newBest and r.best == 1234, 'first score is #1 and a new best')
  local g = Rewards.game(st, 'runner')
  check(#g.scores == 1 and g.plays == 1 and g.totalWatts == 15, 'the run is on the leaderboard')
  -- the bag of three is full now: a further item is lost, and says so
  local p2 = Rewards.newPurse(st, 'runner')
  Rewards.addItem(p2, 'Revive')
  local r2 = Rewards.settle(p2, 50, 0, 5)
  check(r2.lost.items == 1 and #st.items == 3, 'fallback: a full bag keeps what it has')
  check(r2.friendship == 0, 'a 5-second run earns no friendship')
  check(r2.rank == 2 and not r2.newBest, 'a lower score ranks below')

  -- with the economy: every call by the contract
  Rewards._economy = fakeEconomy()
  local st2 = newState(true)
  local p3 = Rewards.newPurse(st2, 'catch')
  Rewards.addItem(p3, 'Great Ball')
  Rewards.addPokemon(p3, 43, 6, 'Oddish')
  Rewards.event(p3, 'catch_perfect', 2)
  local r3 = Rewards.settle(p3, 900, 9, 40)
  check(find('earn', 3, 9) and find('earn', 4, 'minigame:catch'), 'E.earn(st, 9, "minigame:catch")')
  check(find('grantItem', 3, 'Great Ball') and find('grantItem', 4, 1), 'E.grantItem(st, name, 1, source)')
  local gp = find('grantPokemon', 3, 43)
  check(gp and gp[4] == 6 and gp[5] == 'minigame:catch', 'E.grantPokemon(st, 43, 6, source)')
  check(find('recordScore', 3, 'catch') and r3.rank == 7, 'E.recordScore\'s rank is the one shown', r3.rank)
  check(find('friendship', 3, 2), 'E.friendship(st, 2)')
  check(find('achievement', 3, 'minigame_played') and find('achievement', 3, 'catch_perfect'), 'achievements: shared and the game\'s own')
  check(count('save') == 1, 'E.save once per run', count('save'))
  check(#st2.items == 0 and #st2.caught == 0, 'the economy, not the fallback, holds the prizes')
  -- the economy saying no (its bag full): lost, and no sneaking into st.items
  local E2 = fakeEconomy()
  E2.grantItem = function() return false, 'full' end
  E2.grantPokemon = function() return false, 'full' end
  E2.recordScore = function() return nil end
  Rewards._economy = E2
  local p4 = Rewards.newPurse(st2, 'catch')
  Rewards.addItem(p4, 'Potion'); Rewards.addPokemon(p4, 16, 5, 'Pidgey')
  local r4 = Rewards.settle(p4, 10, 0, 20)
  check(r4.lost.items == 1 and r4.lost.pokemon == 1 and #st2.items == 0 and #st2.caught == 0, 'economy full: the prize is reported lost')
  check(r4.placed == false, 'off the economy top ten: no rank shown')
  -- the real WalkerEconomy, when it loads headless
  local okE, RealE = pcall(require, 'src.pokewalker.WalkerEconomy')
  if okE and type(RealE) == 'table' and RealE.econ then
    Rewards._economy = RealE
    local st5 = newState(true)
    local p5 = Rewards.newPurse(st5, 'memory')
    Rewards.addItem(p5, 'Oran Berry')
    local okS, r5 = pcall(Rewards.settle, p5, 777, 12, 60)
    check(okS and r5.watts == 12 and r5.rank == 1 and #r5.items == 1, 'with the real WalkerEconomy: paid and ranked', okS and '' or r5)
    local b = Rewards.board(st5, 'memory')
    check(#b == 1 and b[1].score == 777 and b[1].watts == 12, 'the leaderboard reads the economy board')
  else
    info('WalkerEconomy did not load headless (%s) -- skipped', tostring(RealE))
  end

  -- the daily budgets
  local st3 = newState(true)
  local paid = 0
  for _ = 1, 20 do
    local pp = Rewards.newPurse(st3, 'memory')
    paid = paid + Rewards.settle(pp, 5000, 40, 60).watts
  end
  check(paid == Rewards.LIMITS.WATTS_PER_DAY, 'watts stop at WATTS_PER_DAY', paid)
  local items, mons = 0, 0
  for _ = 1, 10 do
    local pp = Rewards.newPurse(st3, 'treasure')
    for _ = 1, 3 do if Rewards.addItem(pp, 'Potion') then items = items + 1 end end
    if Rewards.addPokemon(pp, 16, 5, 'Pidgey') then mons = mons + 1 end
    Rewards.settle(pp, 10, 0, 30)
  end
  check(items == Rewards.LIMITS.ITEMS_PER_DAY, 'items stop at ITEMS_PER_DAY', items)
  check(mons == Rewards.LIMITS.POKEMON_PER_DAY, 'Pokemon stop at POKEMON_PER_DAY', mons)
  check(st3.minigames.daily.friendship == Rewards.LIMITS.FRIENDSHIP_PER_DAY, 'friendship stops at FRIENDSHIP_PER_DAY', st3.minigames.daily.friendship)
  -- one run never pays more than WATTS_PER_RUN
  NOW = NOW + 86400
  local pp = Rewards.newPurse(st3, 'runner')
  Rewards.addWatts(pp, 30)
  local rr = Rewards.settle(pp, 99999, 999, 100)
  check(rr.watts == Rewards.LIMITS.WATTS_PER_RUN and rr.wattsCapped, 'a run pays at most WATTS_PER_RUN', rr.watts)
  check(Rewards.left(st3).items == Rewards.LIMITS.ITEMS_PER_DAY, 'a new day: fresh budgets')
  check(#Rewards.game(st3, 'memory').scores == Rewards.TOP_SCORES, 'the leaderboard keeps the top ten')
  -- persisted: the counters survive a save / load round trip
  local Ser = require('src.core.SaveSerializer')
  local back = Ser.decode(Ser.encode(st3))
  check(back.minigames and back.minigames.daily.watts == rr.watts and back.minigames.games.memory.best == 5000,
    'best scores and daily counters persist in the walker state')
end

-- =============================================================== Jump Runner
Rewards._economy = false
local function runnerBot(seed, smart, maxT)
  local st = newState(true)
  local ctx = Context.build(st, seed)
  local purse = Rewards.newPurse(st, 'runner')
  local g = Runner.new(ctx, purse)
  local dt = 1 / 60
  while not g.over and g.time < (maxT or 400) do
    if smart then
      local px = g.dist + Runner.PLAYER_X
      for _, e in ipairs(g.ents) do
        local ahead = e.x - px
        local lead = g.speed * 0.16 + 0.6
        if (e.kind == 'block' or (e.kind == 'mon' and not e.flying and not e.dead))
           and ahead > 0 and ahead < lead and g.ground then g:input('a') end
        -- double jump over a tall one when low
        if e.kind == 'block' and ahead > 0 and ahead < 0.8 and not g.ground and g.jumps == 1 and g.py < e.h + 0.1 and g.vy < 2 then g:input('a') end
      end
    end
    g:update(dt)
  end
  return g, purse, st
end
do
  local g = runnerBot(1, false)
  check(g.over == 'crash' and g.time < 6, 'never jumping: crashes early', g.time)
  check(g.score >= math.floor(g.dist) - 1, 'distance scores a point a tile', g.score .. ' / ' .. g.dist)
  -- physics
  local ctx = Context.build(newState(true), 5)
  local r = Runner.new(ctx, Rewards.newPurse(newState(true), 'runner'))
  r.nextSpawn = 1e9
  r:input('a'); r:update(1 / 60)
  check(r.vy > 10 and not r.ground, 'tap: a jump')
  local top = 0
  for _ = 1, 60 do r:update(1 / 60); top = math.max(top, r.py) end
  check(top > 2.5 and top < 3.2, 'a single jump is about 2.9 tiles high', top)
  r:input('a'); r:update(1 / 60); r:input('a'); r:update(1 / 60)
  check(r.jumps == 2, 'a second tap in the air: double jump')
  for _ = 1, 200 do r:update(1 / 60) end
  check(r.ground and r.py == 0, 'lands back on the ground')
  check(r.speed > Runner.SPEED0, 'speed rises over time', r.speed)
  -- a stomp: falling onto a wild Pokemon
  local s2 = newState(true)
  local pr = Rewards.newPurse(s2, 'runner')
  local q = Runner.new(Context.build(s2, 3), pr)
  q.nextSpawn = 1e9
  q.ents = { { kind = 'mon', x = q.dist + Runner.PLAYER_X - 0.45, y = 0, w = 0.9, h = 0.85, vx = 0, dex = 16, name = 'Pidgey', level = 5, group = 'C', phase = 0 } }
  q.py, q.vy, q.ground = 1.2, -5, false
  for _ = 1, 30 do if q.stomps == 0 and not q.over then q:update(1 / 60) end end
  check(q.stomps == 1 and q.score >= Runner.POINTS.stomp and q.vy > 0 and not q.over, 'landing on a wild Pokemon: bounce and points', q.score)
  -- into one from the side
  local q2 = Runner.new(Context.build(s2, 3), Rewards.newPurse(s2, 'runner'))
  q2.nextSpawn = 1e9
  q2.ents = { { kind = 'mon', x = q2.dist + Runner.PLAYER_X + 0.1, y = 0, w = 0.9, h = 0.85, vx = 0, dex = 16, name = 'Pidgey', level = 5, group = 'C', phase = 0 } }
  q2:update(1 / 30)
  check(q2.over == 'crash' and q2.overText:find('Pidgey'), 'running into one from the side ends the run')
  -- a hoop, an orb and an item
  local s3 = newState(true)
  local p3 = Rewards.newPurse(s3, 'runner')
  local q3 = Runner.new(Context.build(s3, 3), p3)
  q3.nextSpawn = 1e9
  local cx = q3.dist + Runner.PLAYER_X
  q3.ents = { { kind = 'hoop', x = cx + 0.05, cy = 0.45, r = 0.85 }, { kind = 'orb', x = cx + 0.1, y = 0.5, r = 0.28 },
              { kind = 'item', x = cx + 0.1, y = 0.5, r = 0.36, name = 'Oran Berry' } }
  q3:update(1 / 30)
  check(q3.hoops == 1 and q3.orbs == 1 and p3.bonusWatts == 1 and p3.items[1] == 'Oran Berry', 'hoop, watt orb and item collected')
  -- a block can be landed on
  local q4 = Runner.new(Context.build(s3, 3), Rewards.newPurse(s3, 'runner'))
  q4.nextSpawn = 1e9
  q4.ents = { { kind = 'block', look = 'rock', x = q4.dist + Runner.PLAYER_X - 1, y = 0, w = 3, h = 0.8 } }
  q4.py, q4.vy, q4.ground = 1.5, 0, false
  for _ = 1, 20 do q4:update(1 / 60) end
  check(not q4.over and q4.ground and math.abs(q4.py - 0.8) < 1e-6, 'a rock can be landed on')

  -- a good run, by a bot that only jumps: how many watts
  local best
  local runs = {}
  for seed = 1, 12 do
    local gg, purse = runnerBot(seed, true, 180)
    gg:beforeSettle()
    runs[#runs + 1] = gg
    if not best or gg.time > best.time then best = gg end
  end
  table.sort(runs, function(a, b) return a.time > b.time end)
  local mid = runs[3]
  local w = mid:wattsFor() + math.min(mid.orbs, Runner.ORB_WATTS_MAX)
  info('runner bot: longest %.0f s %d m score %d; a 3rd-best run %.0f s score %d -> %d W', best.time, best.dist, best.score, mid.time, mid.score, w)
  check(best.time > 40, 'a jumping bot survives a while', best.time)
  -- the tuning target: a 2-3 minute run earns 10-30 W. Simulate one honestly.
  local sim = Runner.new(Context.build(newState(true), 1), Rewards.newPurse(newState(true), 'runner'))
  sim.nextSpawn = 1e9
  for _ = 1, 150 * 60 do sim:update(1 / 60) end   -- 150 s of running, nothing in the way
  local dPts = sim.score
  local est = math.floor((dPts + 15 * Runner.POINTS.stomp + 10 * Runner.POINTS.hoop + 12 * Runner.POINTS.orb) / Runner.WATTS_PER_POINTS) + math.min(12, Runner.ORB_WATTS_MAX)
  info('runner: 150 s = %d tiles; with 15 stomps, 10 hoops, 12 orbs -> about %d W', math.floor(sim.dist), est)
  check(est >= 10 and est <= 30, 'a good 2.5-minute run is worth 10-30 W', est)
end

-- =============================================================== Catch Timing
do
  local st = newState(true)
  local purse = Rewards.newPurse(st, 'catch')
  local g = Catch.new(Context.build(st, 11), purse)
  -- wait for the ring to meet the circle, then throw: always Perfect
  local function aimPerfect()
    local guard = 0
    while g.phase ~= 'aim' and not g.over and guard < 2000 do g:update(1 / 60); guard = guard + 1 end
    if g.over then return end
    while math.abs(g.ring - g.target) > 0.02 or g.pt < 0.2 do g:update(1 / 240) end
    g:input('a')
  end
  aimPerfect()
  check(g.grade == 1 and g.balls == Catch.BALLS - 1, 'a throw on the circle is Perfect and uses a ball')
  for _ = 2, Catch.BALLS do aimPerfect() end
  local guard = 0
  while not g.over and guard < 5000 do g:update(1 / 60); guard = guard + 1 end
  check(g.over == 'done' and g.balls == 0 and g.throws == Catch.BALLS, 'six balls, then the run ends')
  check(g.perfects == Catch.BALLS, 'all six perfect', g.perfects)
  check(#purse.pokemon <= Rewards.LIMITS.POKEMON_PER_RUN, 'catches kept are inside the run\'s limit', #purse.pokemon)
  info('catch: all perfect, %d caught -> score %d = %d W', g.caught, g.score, g:wattsFor())
  check(g:wattsFor() >= 18 and g:wattsFor() <= 40, 'a perfect catch run pays well', g:wattsFor())
  -- grades and chances
  local h = Catch.new(Context.build(st, 12), Rewards.newPurse(st, 'catch'))
  check(h:gradeFor(h.target) == 1 and h:gradeFor(h.target + 0.06) == 2 and h:gradeFor(h.target + 0.12) == 3
        and h:gradeFor(h.target + 0.3) == nil, 'Perfect / Great / Good / miss by distance from the circle')
  check(h:catchChance('A', 1) < h:catchChance('C', 1) and h:catchChance('C', 3) < h:catchChance('C', 1)
        and h:catchChance('C', nil) == 0, 'better timing and commoner Pokemon catch more often')
  -- waiting too long: it wanders off with a ball
  for _ = 1, math.ceil(Catch.TIMEOUT * 60) + 2 do h:update(1 / 60) end
  check(h.balls == Catch.BALLS - 1 and h.log[1].grade == 'Wandered off', 'too slow: it wanders off with a ball')
  -- a mediocre run
  local m = Catch.new(Context.build(st, 13), Rewards.newPurse(st, 'catch'))
  local guard2 = 0
  while not m.over and guard2 < 20000 do
    if m.phase == 'aim' and m.pt > 0.2 and math.abs(m.ring - (m.target + 0.07)) < 0.02 then m:input('a') end
    m:update(1 / 120); guard2 = guard2 + 1
  end
  info('catch: all Great -> %d caught, score %d = %d W in %.0f s', m.caught, m.score, m:wattsFor(), m.time)
end

-- =============================================================== Treasure Hunt
do
  local st = newState(true)
  local purse = Rewards.newPurse(st, 'treasure')
  local g = Treasure.new(Context.build(st, 21), purse)
  check(g.total == Treasure.CACHES + 1 + Treasure.ITEMS, 'five caches, a big one and two items buried', g.total)
  -- the hints
  local empty
  for _, c in ipairs(g.cells) do if not c.hide then empty = c break end end
  local d = g:nearest(empty.c, empty.r)
  local cell = g:dig(empty.c, empty.r)
  check(cell.result == 'empty' and cell.hint == math.min(4, d) and g.digs == Treasure.DIGS - 1, 'an empty dig hints how near the nearest is')
  check(g:dig(empty.c, empty.r) == nil and g.digs == Treasure.DIGS - 1, 'a dug tile cannot be dug again')
  -- dig every treasure: cleared, with the leftover bonus
  for _, c in ipairs(g.cells) do if c.hide then g:dig(c.c, c.r) end end
  check(g.ending and g.ending.why == 'cleared', 'everything found: cleared')
  for _ = 1, 200 do g:update(1 / 60) end
  check(g.over == 'cleared', 'the board stays up a moment, then the run ends')
  local expect = 0
  for _, c in ipairs(g.cells) do
    if c.hide then expect = expect + (c.hide.kind == 'watts' and c.hide.w * Treasure.POINTS_PER_W or Treasure.ITEM_POINTS) end
  end
  expect = expect + g.digs * Treasure.LEFTOVER_DIG
  check(g.score == expect, 'score = caches + items + leftover digs', g.score .. ' vs ' .. expect)
  check(#purse.items == 2, 'the two items go in the purse')
  info('treasure: a perfect board = %d -> %d W', g.score, g:wattsFor())
  -- out of digs
  local h = Treasure.new(Context.build(st, 22), Rewards.newPurse(st, 'treasure'))
  local n = 0
  for _, c in ipairs(h.cells) do if not c.hide and n < Treasure.DIGS then h:dig(c.c, c.r); n = n + 1 end end
  check(h.ending and h.ending.why == 'done' and h.digs == 0 and h.score == 0, 'twelve empty digs: over, nothing found')
  -- the item budget spent: no items buried
  local st2 = newState(true)
  st2.minigames = { day = math.floor(NOW / 86400), daily = { watts = 0, items = Rewards.LIMITS.ITEMS_PER_DAY, pokemon = 0, friendship = 0, plays = 0 }, games = {} }
  local h2 = Treasure.new(Context.build(st2, 23), Rewards.newPurse(st2, 'treasure'))
  check(h2.total == Treasure.CACHES + 1, 'no item budget today: only watts are buried')
  -- a hint-following player: average over seeds
  local sum = 0
  for seed = 1, 20 do
    local t = Treasure.new(Context.build(newState(true), 100 + seed), Rewards.newPurse(newState(true), 'treasure'))
    local c, r = 3, 3
    while not t.ending do
      local res = t:dig(c, r)
      -- next: the undug tile around the hottest hint, else any undug
      local bestCell, bestScore
      for _, x in ipairs(t.cells) do
        if not x.dug then
          local sc = 0
          for _, y in ipairs(t.cells) do
            if y.dug and y.hint then
              local dd = math.max(math.abs(x.c - y.c), math.abs(x.r - y.r))
              sc = sc + ((dd == y.hint) and 3 or (dd < y.hint and -5 or 0))
            end
          end
          if not bestScore or sc > bestScore then bestCell, bestScore = x, sc end
        end
      end
      if not bestCell then break end
      c, r = bestCell.c, bestCell.r
      if not res then break end
    end
    sum = sum + t:wattsFor()
  end
  info('treasure: a hint-following player averages %.1f W', sum / 20)
  check(sum / 20 >= 6 and sum / 20 <= 30, 'treasure pays 6-30 W for a sensible game', sum / 20)
end

-- =============================================================== Memory Match
do
  local st = newState(true)
  local purse = Rewards.newPurse(st, 'memory')
  local ctx = Context.build(st, 31)
  local g = Memory.new(ctx, purse)
  check(#g.cards == 16, 'sixteen cards')
  local ids = {}
  for _, c in ipairs(g.cards) do ids[c.id] = (ids[c.id] or 0) + 1 end
  local pairsOk = true
  for _, n in pairs(ids) do if n ~= 2 then pairsOk = false end end
  check(pairsOk, 'every Pokemon twice')
  check(g.cards[1].dex ~= nil, 'cards carry a species')
  -- a mismatch flips back
  local a, b
  for i = 2, 16 do if g.cards[i].id ~= g.cards[1].id then b = i break end end
  g:flip(1); g:flip(b)
  check(g.turns == 1 and g.pairs == 0 and g.hideIn, 'a mismatch is shown, then hidden')
  for _ = 1, 60 do g:update(1 / 60) end
  check(not g.cards[1].up and not g.cards[b].up, 'it flips back')
  -- perfect memory from here: clear the board
  local seen = {}
  for i, c in ipairs(g.cards) do
    if not c.matched and not seen[i] then
      for j = i + 1, 16 do
        if g.cards[j].id == c.id then g:flip(i); g:flip(j); seen[j] = true break end
      end
      g:update(0.5)
    end
  end
  check(g.ending and g.ending.why == 'cleared' and g.pairs == 8, 'cleared', g.pairs)
  check(g.turns == 9, 'nine turns (one mistake)', g.turns)
  local expect = 8 * Memory.PAIR_POINTS + math.floor(g.left) * Memory.TIME_POINTS + (Memory.TURN_PAR - 9) * Memory.TURN_POINTS
  check(g.score == expect, 'score = pairs + time left + turns under par', g.score .. ' vs ' .. expect)
  info('memory: near-perfect clear = %d -> %d W', g.score, g:wattsFor())
  check(g:wattsFor() >= 15 and g:wattsFor() <= 40, 'a great memory game pays 15-40 W', g:wattsFor())
  -- fewer flips, more watts
  local function play(mistakes, seed)
    local m = Memory.new(Context.build(st, seed), Rewards.newPurse(st, 'memory'))
    for _ = 1, mistakes do
      local x, y
      for i = 1, 16 do if not m.cards[i].matched then x = i break end end
      for j = x + 1, 16 do if m.cards[j].id ~= m.cards[x].id and not m.cards[j].matched then y = j break end end
      m:flip(x); m:flip(y); m:update(1)
    end
    for i = 1, 16 do
      if not m.cards[i].matched then
        for j = i + 1, 16 do if m.cards[j].id == m.cards[i].id then m:flip(i); m:flip(j) break end end
        m:update(2)
      end
    end
    return m
  end
  local few, many = play(2, 40), play(14, 40)
  check(few:wattsFor() > many:wattsFor(), 'fewer flips earn more', few:wattsFor() .. ' > ' .. many:wattsFor())
  -- the timer
  local t = Memory.new(Context.build(st, 41), Rewards.newPurse(st, 'memory'))
  for _ = 1, 92 do t:update(1) end
  for _ = 1, 3 do t:update(1) end
  check(t.over == 'time' and t.left == 0, 'ninety seconds, then time')
  -- only species with art when the art is known
  local ctx2 = Context.build(st, 42)
  ctx2.hasArt = function(dex) return dex == 25 or dex >= 150 end
  local hm = Memory.new(ctx2, Rewards.newPurse(st, 'memory'))
  local ok = true
  for _, c in ipairs(hm.cards) do if not (c.dex == 25 or c.dex >= 150) then ok = false end end
  check(ok, 'cards use species some imported game has a picture of')
end

-- =============================================================== Rhythm Tap
do
  local st = newState(true)
  local purse = Rewards.newPurse(st, 'rhythm')
  local g = Rhythm.new(Context.build(st, 51), purse)
  check(#g.notes > 100 and #g.beats > 100, 'a full chart', #g.notes .. ' notes')
  local sorted = true
  for i = 2, #g.notes do if g.notes[i].t < g.notes[i - 1].t then sorted = false end end
  check(sorted, 'the notes are in order')
  -- tap every note dead on
  local k = 1
  local dt = 1 / 120
  while not g.over do
    g:update(dt)
    local n = g.notes[k]
    if n and g.clock >= n.t then g:tap(n.t); k = k + 1 end
  end
  check(g.hits == #g.notes and g.misses == 0 and g.perfects == #g.notes, 'perfect taps: every note Perfect', g.hits .. '/' .. #g.notes)
  check(g.best == #g.notes and g:mult() == 1, 'one long streak (reset as the song ends)')
  info('rhythm: all perfect = %d -> %d W (run cap %d)', g.score, g:wattsFor(), Rewards.LIMITS.WATTS_PER_RUN)
  -- the multiplier
  local h = Rhythm.new(Context.build(st, 52), Rewards.newPurse(st, 'rhythm'))
  h.clock = 0
  for i = 1, 35 do h:tap(h.notes[i].t) end
  check(h:mult() == 4 and h.streak == 35, 'x4 after thirty in a row')
  -- a stray tap breaks it, and so does a miss
  h.clock = h.notes[36].t - 0.5
  h:tap(h.clock)
  check(h.streak == 0 and h:mult() == 1, 'a tap with no note near breaks the streak')
  h:tap(h.notes[36].t + 0.12)
  check(h.counts[3] == 1, 'off by 0.12 s: Good')
  h.clock = h.notes[38].t + 0.3
  h:update(0)
  check(h.misses >= 1 and h.streak == 0, 'a note let past is a Miss')
  -- a decent player: 70% great, some misses
  local m = Rhythm.new(Context.build(st, 53), Rewards.newPurse(st, 'rhythm'))
  local rng = Context.newRng(7)
  local j = 1
  while not m.over do
    m:update(dt)
    local n = m.notes[j]
    if n and m.clock >= n.t + 0.04 then
      local roll = rng(100)
      if roll <= 90 then m:tap(n.t + (roll <= 60 and 0.03 or 0.08)) end
      j = j + 1
    end
  end
  info('rhythm: a decent player (90%% hit) = %d -> %d W, best streak %d', m.score, m:wattsFor(), m.best)
  check(m:wattsFor() >= 8 and m:wattsFor() <= 40, 'a decent song pays 8-40 W', m:wattsFor())
end

-- =============================================================== the shell and the hub
do
  Rewards._economy = fakeEconomy()
  local st = newState(true)
  local hub = Hub.new(nil, st, { seed = 3 })
  check(#Hub.games() == 5, 'five games in the hub')
  -- keyboard: right twice, A -> the third game's intro
  hub:key('right'); hub:key('right'); hub:key('return')
  check(hub.view == 'game' and hub.session and hub.session.module.id == 'treasure' and hub.session.phase == 'intro', 'arrows + Enter open a game')
  hub:key('space')
  check(hub.session.phase == 'play', 'Space starts it')
  hub:key('escape')
  check(hub.session.phase == 'pause', 'Esc pauses')
  hub:update(5)
  check(hub.session.game.time == 0, 'paused: the game does not run')
  hub:pad('dpdown'); hub:pad('a')   -- "End run"
  check(hub.session.phase == 'results' and hub.session.result, 'pause -> End run -> results')
  check(find('recordScore', 3, 'treasure'), 'the score was recorded')
  hub:pad('dpdown'); hub:pad('a')   -- "Back to games"
  check(hub.view == 'list' and not hub.session, 'results -> back to the games')
  check(Rewards.game(st, 'treasure').plays == 1, 'the play is counted for the card')
  -- gamepad B pauses mid-run and B again resumes
  hub:play(1, true)
  check(hub.session.phase == 'play', 'Play again / skip intro starts at once')
  hub.session:update(0.5)
  hub:pad('b')
  check(hub.session.phase == 'pause', 'B pauses')
  hub:pad('b')
  check(hub.session.phase == 'play', 'B again resumes')
  -- a tap (pointer) jumps
  hub.session:pointer(500, 500)
  hub.session:update(1 / 60)
  check(hub.session.game.vy > 0, 'a tap anywhere jumps')
  -- run until the crash: the results pay once
  for _ = 1, 60 * 60 do hub:update(1 / 60) end
  check(hub.session.phase == 'results', 'the runner crashed into its results')
  local before = Rewards.game(st, 'runner').plays
  hub.session:finish()
  check(Rewards.game(st, 'runner').plays == before, 'finishing twice pays once')
  check(hub.runs == 2, 'the hub counts the runs for its goodbye', hub.runs)
  -- scores view by the alt button
  hub.session = nil; hub.view = 'list'; hub.sel = 1
  hub:pad('y')
  check(hub.view == 'scores' and hub.scoresOf == 1, 'X / Y (Tab) opens the scores')
  hub:key('escape')
  check(hub.view == 'list', 'back from the scores')
  -- open / close against a fake screen: its methods are covered and put back
  local screen = { st = st, said = nil }
  function screen.say(self, t) self.said = t end
  local origDraw = function() return 'orig' end
  screen.draw = origDraw
  local h2 = Hub.open(screen, st)
  check(screen.draw ~= origDraw and Hub.active == h2, 'open covers the screen')
  h2.runs, h2.earned = 1, 12
  h2:key('escape')
  check(screen.draw == origDraw and screen.mousepressed == nil and Hub.active == nil, 'close puts the screen back')
  check(screen.said and screen.said:find('12 W'), 'and leaves a toast', screen.said)
  -- against a launcher-like host with a class
  local Cls = {}; Cls.__index = Cls
  local ticks = 0
  function Cls:update() ticks = ticks + 1 end
  function Cls:draw() end
  local host = setmetatable({ settingsOpen = false }, Cls)
  local h3 = Hub.open({ st = st, host = host }, st)
  host:update(1 / 60)
  check(ticks == 1 and host.settingsOpen == true, 'the launcher keeps updating, its backdrop held')
  host:keypressed('return')
  check(h3.view == 'game', 'launcher keys go to the hub')
  h3:close()
  check(rawget(host, 'update') == nil and rawget(host, 'draw') == nil and host.settingsOpen == false, 'close restores the launcher')
end

print(('%d passed, %d failed'):format(PASS, FAIL))
if FAIL > 0 then error('walker minigames check failed') end
