-- HEARTGOLD / SOULSILVER'S POKeATHLON COURSE (the dome's `Pokeathlon`
-- command; pokeheartgold PokeathlonCourse_* in src/pokeathlon/
-- pokeathlon_course.c over the 39 states of sPokeathlonStateInfoFuncTable in
-- asm/overlay_96.s).
--
-- WHAT IS THE CARTRIDGE'S:
--   * the course's events: gen4_hgss_pokeathlon.courses[course] (ov96_0221A934),
--     event ids 0 Hurdle Dash .. 9 Goal Roll (bank 313 #20-29)
--   * the order the top level runs its parts in: the team (ov96_0221A8BC),
--     the opening (A808), each event's introduction, the event, its results
--     (A8E4 / A86C), and the closing ceremony (A844)
--   * every word: the announcer's bank 309 -- the opening #0-2, an event's
--     title #166+, dome #187+, rules #198+, "Results of the first event!?"
--     #246-248, "Team X! Congratulations on First Place!" #253, the closing's
--     "we'll add up the event points!" #22, "Event N!" #23, the winner #25-26,
--     "You did well on the {course}!" #30
--   * what goes back to the script (sub_02095DF4): 800C 1 when the player
--     quit, 8001 the score, 8002 the Athlete Points, 8003 the final place
--     (0 first: the script then gives the 300-point winning bonus, #22)
--   * at the course's end (021E7718), after the Athlete Points, each event's
--     solo record (the event's res.record = its field_5E0) goes into the
--     save (src/pokemon/HgssPokeathlonRecords.lua, 021E7BA8 / 021E7938),
--     then the rest of 021E7718 (src/pokemon/HgssPokeathlonStats.lua): the
--     Medals, the course best, the record block the Data Monitor reads
--     (021E7D6C), the dome's room flags 0xEF / 0xF0 / 0xF1; the AP are
--     doubled on the Master course (10)
--
-- STAND-INS, said so, until their assembly is read (each a module of its own
-- later): events not yet ported are `Stub`, which scores
-- each team from its Pokemon's stars for the event's stat. The score is the
-- player's event points plus the closing ceremony's bonuses (C:bonuses);
-- the Athlete Points are the score.
-- Pokemon the course's medal (mon.athlonMedals[course]).

local TextBox = require("src.render.TextBox")

local C = {}
C.__index = C
C.isOpaque = true

local BANK = 309
local NAMES = 313
C.EVENT_STAT = { [0] = 4, 4, 0, 0, 3, 3, 1, 1, 2, 2 }   -- the stat each event leans on (stand-in)
C.COURSE_EVENTS = { [0] = { 0, 1, 6 }, { 3, 2, 9 }, { 8, 9, 1 }, { 7, 6, 3 }, { 5, 4, 0 } }

function C.text(game, n, ...)
  local T = require("src.import.Gen4Text")
  local bufs = game.stringBuffers
  local saved = {}
  if bufs then for i = 1, 4 do saved[i] = bufs[i] end end
  if select("#", ...) > 0 then T.buffer(game, ...) end
  local s = T.resolve(game.data, BANK, n, game) or ""
  bufs = game.stringBuffers
  if bufs then for i = 1, 4 do bufs[i] = saved[i] end end
  return s
end

local function name(game, bank, n)
  local s = require("src.import.Gen4Text").resolve(game.data, bank, n, game)
  return s and (s:gsub("{[^}]*}", "")) or tostring(n)
end

local function nick(m, game)
  if m.nickname then return m.nickname end
  local def = game and game.data and game.data.pokemon and game.data.pokemon[m.species]
  return (def and def.name) or m.name or tostring(m.species)
end

-- opts: course (0..9), supreme (the args byte 0xF: the Supreme Cup
-- receptionist's `Pokeathlon 0, 1` -- scr_seq_0167_001, shown once
-- FLAG_HIDE_POKEATHLON_SUPREME_CUP_RECEPTIONIST is cleared), link (args
-- mode, byte 1), onDone({ quit, score, points, bonus })
function C.new(game, opts)
  local self = setmetatable({ game = game, course = opts.course or 0, onDone = opts.onDone, t = 0,
                              supreme = opts.supreme and true or false, link = opts.link and true or false }, C)
  local tables = game.data.gen4_hgss_pokeathlon
  self.events = (tables and tables.courses and tables.courses[self.course]) or C.COURSE_EVENTS[self.course] or { 0, 1, 6 }
  self.player = ((game.save or {}).player or {}).name or "PLAYER"
  self.teams = { { name = self.player, points = {} }, { points = {} }, { points = {} }, { points = {} } }
  self:pickRivals(tables and tables.opponents)
  self.queue = {}
  self.phase = "pick"
  return self
end

function C:uiSize() return 256, 192 end

-- the three computer teams (ov96_021E860C / 021E8484): for a single course c
-- three different opponents of 5c+1..5c+5 (the Master Course 26..50; the
-- Supreme Cup adds 50 to each -- ov96_021E8484 hands ov96_021E860C the args
-- byte 0xF, and _021E86C4 adds 0x32 to every pick), each with its three
-- species and its name (bank 310); their Pokemon perform at their species'
-- base stars
function C:pickRivals(opponents)
  if type(opponents) ~= "table" then return end
  local first, count = self.course * 5 + 1, 5
  if self.course >= 5 then first, count = 26, 25 end
  if self.supreme then first = first + 50 end
  local pool = {}
  for i = 0, count - 1 do pool[#pool + 1] = first + i end
  local rnd = love and love.math and love.math.random or math.random
  for t = 2, 4 do
    local k = rnd(1, #pool)
    local id = table.remove(pool, k)
    local o = opponents[id]
    if o then
      self.teams[t].id = id
      -- the record's last byte (ov96_021E8448): the team's own line in the
      -- opening, bank 311 #group (ov96_021EE908)
      self.teams[t].group = o.group
      self.teams[t].name = name(self.game, 310, o.name)
      self.teams[t].mons = {}
      for j = 1, 3 do self.teams[t].mons[j] = { species = o.species[j], form = 0 } end
    end
  end
end

-- the party's Pokemon that can take part (no Eggs)
function C:entrants()
  local out = {}
  for i, m in ipairs((self.game.save or {}).party or {}) do
    if not m.isEgg then out[#out + 1] = { slot = i, mon = m } end
  end
  return out
end

function C:say(n, ...)
  self.queue[#self.queue + 1] = C.text(self.game, n, ...)
end

function C:start()
  self.started = true
  self.clock0 = require("src.pokemon.HgssPokeathlonStats").now()   -- Time Spent (data+0xD24)
  self:pickTeam()
end

-- THE TEAM: HGSS picks its three on the party menu in its select mode -- the
-- party bank's "Please select the three Pokemon that will participate."
-- (bank 14 #19) -- as the Battle Frontier does; the port's party menu
-- `select` mode (src/ui/Gen4PartyMenu.lua) is that screen
function C:pickTeam()
  local game = self.game
  self.team = {}
  -- THE PARTY AND THE PC BOXES (arm9 sub_020932E0 / 02093440, opened by
  -- overlay 97 on box 0x12 = the party): src/ui/HgssPokeathlonTeamPick.lua
  local menu = require("src.ui.HgssPokeathlonTeamPick").new(game, {
    count = 3, course = self.course, supreme = self.supreme,
    onDone = function(mons)
      if not mons then return self:finish(true) end
      for _, m in ipairs(mons) do self.team[#self.team + 1] = m end
      if #self.team < 3 then return self:finish(true) end
      self:opening()
    end,
  })
  -- overlay 97's panel (the cursor's Pokemon: stars, Medals, "Supreme") on
  -- the other screen: src/ui/HgssPokeathlonTeamInfo.lua
  require("src.ui.HgssPokeathlonTeamInfo").attach(menu, game, { course = self.course, supreme = self.supreme })
  game.stack:push(menu)
end


-- THE TEAMS' LEVEL AND GROUP (ov96_021ED8DC at the opening, solo: the
-- player's team by ov96_021EE0AC, each computer team by ov96_021EE1D8):
-- a computer team's entry is { the opponent record's group byte, level << 24 }
-- with level = clamp((sum over its three Pokemon of (stars + 5)) / 3 - 8,
-- 0, 12), the stars its course record's five (the species' base, 0..4); the
-- player's level is the rank of the record block's B00 + 0x70 (ScrCmd_724's
-- 11) against ov96_0221B058 (ov96_021EDF5C).
--
-- READ, NOT GUESSED: THE LEVEL IS NOT AN EVENT AI'S. Its only reader is
-- ov96_021ED8A4, called once, from the opening's team introduction
-- (ov96_021EB730): the crowd's cheer as a team is named, SE 0x8DC below
-- level 5 and 0x8DD from 5, pitched by ov96_0221B088[level]. The group's
-- readers (ov96_021ED838) are the same introduction: a computer team's own
-- line, bank 311 #group, before its name (state 5, ov96_021EE908). The ten
-- events' copy-area records (+0x28 / +0xF0) are rewritten by each event's
-- own per-frame exchange; none of their rival AIs reads either value.
C.RANK = { 11, 26, 51, 101, 201, 501, 1001, 2001, 5001, 10001, 20001, 50001 }   -- ov96_0221B058
C.CHEER_PITCH = { [0] = -64, -32, 0, 32, 64, 96, -32, -16, 0, 16, 32, 48, 64 }   -- ov96_0221B088
C.CHEER_LOW, C.CHEER_HIGH = 0x8DC, 0x8DD

-- ov96_021EE1D8's level for a computer team's three Pokemon
function C.rivalLevel(game, mons)
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local sum = 0
  for j = 1, 3 do
    local row = mons and mons[j] and P.row(game.data, mons[j])
    local s = 0
    if row then for i = 0, 4 do s = s + (tonumber(row.base[i]) or 0) end end
    sum = sum + s + 5
  end
  local level = math.floor(sum / 3) - 8
  if level > 12 then level = 12 elseif level < 0 then level = 0 end
  return level
end

-- ov96_021EDF5C over B00 + 0x70: the first rank step above it
function C.playerLevel(save)
  local v = require("src.ui.HgssPokeathlonDataView").field(save, 0x70)
  for i, step in ipairs(C.RANK) do
    if step > v then return i - 1 end
  end
  return #C.RANK
end

-- the introduction's cheer: PlaySE_SetPitch(level < 5 and 0x8DC or 0x8DD,
-- ov96_0221B088[level]); the pitch is NitroAudio's 64ths of a semitone
function C:cheer(level)
  level = math.max(0, math.min(12, math.floor(tonumber(level) or 0)))
  local id = level < 5 and C.CHEER_LOW or C.CHEER_HIGH
  local pitch = 2 ^ ((C.CHEER_PITCH[level] or 0) / 768)
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, id, { pitch = pitch }) end
  return id, pitch
end

function C:opening()
  -- #0 prints the course with {STRVAR_4 1 0 0}: slot 0 (it read empty)
  self:say(0, name(self.game, NAMES, self.course))
  self.teams[1].level = C.playerLevel(self.game.save or {})
  self:say(1, self.player, nick(self.team[1], self.game), nick(self.team[2], self.game), nick(self.team[3], self.game))
  self.queue[#self.queue] = { text = self.queue[#self.queue], cheer = self.teams[1].level }
  for t = 2, 4 do
    local tm = self.teams[t]
    if tm.mons then
      tm.level = C.rivalLevel(self.game, tm.mons)
      -- the team's own line (bank 311 #group), then its name to the cheer
      local line = tm.group and require("src.import.Gen4Text").resolve(self.game.data, 311, tm.group, self.game)
      if line and line ~= "" then self.queue[#self.queue + 1] = line end
      self:say(1, tm.name or "", nick(tm.mons[1], self.game), nick(tm.mons[2], self.game), nick(tm.mons[3], self.game))
      self.queue[#self.queue] = { text = self.queue[#self.queue], cheer = tm.level }
    end
  end
  self:say(2)
  self.eventIndex = 0
  self.after = function() self:nextEvent() end
  self.phase = "talk"
end

function C:nextEvent()
  self.eventIndex = self.eventIndex + 1
  local ev = self.events[self.eventIndex]
  if not ev then return self:closing() end
  self.current = ev
  self:say(166 + ev)
  self:say(187 + ev)
  self:say(198 + ev)
  self.after = function() self:playEvent(ev) end
  self.phase = "talk"
end

-- STAND-IN: each team's event points from its Pokemon's stars for the
-- event's stat (the player's) or at random (the rivals')
-- the ported events (each its own module); the rest are Stub below
C.EVENTS = { [0] = "src.ui.HgssHurdleDash", [1] = "src.ui.HgssPennantCapture", [2] = "src.ui.HgssPokeathlonCirclePush", [3] = "src.ui.HgssPokeathlonBlockSmash", [4] = "src.ui.HgssPokeathlonDiscCatch", [5] = "src.ui.HgssPokeathlonLampJump", [6] = "src.ui.HgssPokeathlonRelayRun", [7] = "src.ui.HgssPokeathlonRingDrop", [8] = "src.ui.HgssPokeathlonSnowThrow", [9] = "src.ui.HgssPokeathlonGoalRoll" }

function C:playEvent(ev)
  local modname = C.EVENTS[ev]
  local E = modname and require(modname)
  if E and E.available(self.game) then
    self.phase = "event"
    local rivals = {}
    for t = 2, 4 do rivals[t - 1] = self.teams[t].mons end
    local names = {}
    for t = 1, 4 do names[t] = self:teamName(t) end
    -- HgssPokeathlonStats.watch counts the stylus touches (course counter 0)
    self.game.stack:push(require("src.pokemon.HgssPokeathlonStats").watch(self, E.new(self.game, { team = self.team, rivals = rivals, names = names, course = self.course, onDone = function(res)
      for i = 1, 4 do self.teams[i].points[self.eventIndex] = res.points[i] or 0 end
      -- the player's result score (field_5E0), saved at the course's end
      self.records = self.records or {}
      self.records[self.eventIndex] = res.record
      self:addStats(res.stats)
      self:eventResults()
    end })))
    return
  end
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local stat = C.EVENT_STAT[ev] or 0
  local rand = love and love.math and love.math.random or math.random
  local mine = 0
  for _, m in ipairs(self.team) do
    local stars = P.stars(self.game.data, m)
    mine = mine + ((stars and stars[stat] or 2) + 1) * 8 + rand(0, 12)
  end
  self.teams[1].points[self.eventIndex] = mine
  for i = 2, 4 do self.teams[i].points[self.eventIndex] = rand(30, 120) end
  self:addStats(nil)
  self:eventResults()
end

-- THE EVENT RESULT every event module hands back (onDone(res)):
--   res.points[1..4]      the team's Athlete Points for the event (1 = the player)
--   res.stats[1..4][1..3] (optional) per Pokemon: miss (true when it broke the
--                         event's No-Miss rule), score (its individual score),
--                         jump / dash / hit / fail (the effort counters),
--                         fall / switch / impede (the other course counters,
--                         summed into the save by HgssPokeathlonStats)
-- A Pokemon with no stats for an event counts as no-miss and adds nothing.
function C:addStats(stats)
  for t = 1, 4 do
    local team = self.teams[t]
    team.mstats = team.mstats or { {}, {}, {} }
    for m = 1, 3 do
      local acc = team.mstats[m]
      local st = stats and stats[t] and stats[t][m] or {}
      if st.miss then acc.missed = true end
      for _, k in ipairs({ "score", "jump", "dash", "hit", "fail", "fall", "switch", "impede" }) do
        acc[k] = (acc[k] or 0) + (tonumber(st[k]) or 0)
      end
    end
  end
end

-- the team's three Pokemon (the player's, or a rival's)
function C:teamMons(t)
  if t == 1 then return self.team end
  return self.teams[t].mons or {}
end

function C:teamName(t)
  return t == 1 and self.player or (self.teams[t].name or "")
end

-- THE BONUSES (Bulbapedia "Pokeathlon", Bonus points; the closing ceremony's
-- own lines, bank 309 #3-21): Challenge = 75 - the team's stars at base
-- (no Aprijuice); No-Miss +10 a Pokemon clean in every event; Leading Score
-- +20 the highest individual score; Effort +10 the most of one counter picked
-- at random -- jump, hit, fail, dash (Jump is never picked on the Skill and
-- Power courses: Hit instead); ties all win
function C:bonuses()
  local P = require("src.pokemon.HgssPokeathlonPerformance")
  local rnd = love and love.math and love.math.random or math.random
  local bonus = { 0, 0, 0, 0 }
  self:say(3)
  self:say(4)
  for t = 1, 4 do
    local stars = 0
    for _, m in ipairs(self:teamMons(t)) do
      local row = P.row(self.game.data, m)
      if row then for i = 0, 4 do stars = stars + row.base[i] + 1 end end
    end
    local c = math.max(0, 75 - stars)
    bonus[t] = bonus[t] + c
    self:say(5, self:teamName(t), tostring(c))
  end
  local function award(lineNone, lineDone, amount, pick)
    local any = false
    for t = 1, 4 do
      for m, mon in ipairs(self:teamMons(t)) do
        if pick(t, m) then
          any = true
          bonus[t] = bonus[t] + amount
          if t == 1 then self.bonusCount = (self.bonusCount or 0) + 1 end   -- heap+0xAC (Bonuses Earned)
          self:say(8, self:teamName(t), nick(mon, self.game))
        end
      end
    end
    if not any then self:say(lineNone) end
    self:say(lineDone)
  end
  local function st(t, m) return ((self.teams[t].mstats or {})[m]) or {} end
  self:say(6)
  self:say(7)
  award(9, 10, 10, function(t, m) return not st(t, m).missed end)
  self:say(11)
  local best = 0
  for t = 1, 4 do for m = 1, 3 do best = math.max(best, st(t, m).score or 0) end end
  award(9, 13, 20, function(t, m) return best > 0 and (st(t, m).score or 0) == best end)
  self:say(14)
  local kinds = { "jump", "hit", "fail", "dash" }
  local kind = kinds[rnd(1, 4)]
  if kind == "jump" and (self.course == 1 or self.course == 2) then kind = "hit" end
  self:say(({ jump = 15, hit = 16, fail = 17, dash = 18 })[kind])
  local most = 0
  for t = 1, 4 do for m = 1, 3 do most = math.max(most, st(t, m)[kind] or 0) end end
  award(9, 21, 10, function(t, m) return most > 0 and (st(t, m)[kind] or 0) == most end)
  return bonus
end

function C:eventResults()
  self:say(246 + self.eventIndex - 1)
  local best = 1
  for i = 2, 4 do if self.teams[i].points[self.eventIndex] > self.teams[best].points[self.eventIndex] then best = i end end
  if best == 1 then self:say(253, self.player) else self:say(254) end
  self.after = function() self:nextEvent() end
  self.phase = "talk"
end

function C:closing()
  local bonus = self:bonuses()
  self:say(22)
  local totals = {}
  for i, t in ipairs(self.teams) do
    local s = bonus[i] or 0
    for _, p in pairs(t.points) do s = s + p end
    totals[i] = s
  end
  self.totals = totals
  local best = 1
  for i = 2, 4 do if totals[i] > totals[best] then best = i end end
  self.won = best == 1
  self.place = 0
  for i = 2, 4 do if totals[i] > totals[1] then self.place = self.place + 1 end end
  if self.won then
    self:say(25, tostring(totals[1]))
    self:say(26, self.player)
    for _, m in ipairs(self.team) do
      m.athlonMedals = m.athlonMedals or {}
      m.athlonMedals[self.course] = true
    end
  end
  self:say(30, "", name(self.game, NAMES, self.course))
  self.score = totals[1]
  self.after = function() self:finish(false) end
  self.phase = "talk"
end

function C:finish(quit)
  self.phase = "done"
  -- the points go into the save here (the script only announces them):
  -- PokeathlonSave_AddAthletePoints, capped at 99999
  local Stats = require("src.pokemon.HgssPokeathlonStats")
  if not quit and self.score then
    local save = self.game.save
    -- doubled on the Master course (course 10)
    self.ap = Stats.athletePoints(self.course, self.score)
    save.hgssAthletePoints = math.min(99999, (tonumber(save.hgssAthletePoints) or 0) + self.ap)
    -- then the events' solo records (021E7718 -> 021E7BA8 / 021E7938,
    -- src/pokemon/HgssPokeathlonRecords.lua); a Stub event has no record
    require("src.pokemon.HgssPokeathlonRecords").commit(save, self.events, self.records or {},
      self.teams[1].points, self.team)
    -- then the medals, the course best, the record block (B00) and the
    -- dome's room flags 0xEF / 0xF0 / 0xF1 (021E7718, the rest of it)
    Stats.commit(self)
  end
  self.game.stack:pop()
  if self.onDone then
    self.onDone({ quit = quit, score = self.score or 0, points = self.ap or self.score or 0, bonus = self.place or 3 })
  end
end

function C:update()
  self.t = self.t + 1
  if not self.started then return self:start() end
  if self.phase == "talk" then
    local line = table.remove(self.queue, 1)
    if type(line) == "table" then
      if line.cheer then self:cheer(line.cheer) end
      line = line.text
    end
    if line then
      self.phase = "wait"
      local clean = line:gsub("{[^}]*}", "")
      self.game.stack:push(TextBox.new(self.game, clean, function() self.phase = "talk" end))
    else
      self.phase = "idle"
      local f = self.after
      self.after = nil
      if f then f() end
    end
  end
end

function C:draw()
  local g = love.graphics
  g.setColor(0.09, 0.27, 0.55, 1)
  g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  local Font = require("src.render.Font")
  Font.draw(name(self.game, NAMES, self.course), 8, 8)
  for i, ev in ipairs(self.events) do
    local mark = (i == self.eventIndex) and "> " or "  "
    local pts = self.teams[1].points[i]
    Font.draw(mark .. name(self.game, NAMES, 20 + ev) .. (pts and ("  " .. pts) or ""), 8, 24 + 16 * i)
  end
end

return C
