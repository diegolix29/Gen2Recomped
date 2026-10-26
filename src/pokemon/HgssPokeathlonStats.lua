-- HEARTGOLD / SOULSILVER POKeATHLON: THE COURSE-END SAVE UPDATES other than
-- the Athlete Points and the per-event records (those are HgssPokeathlonCourse
-- / HgssPokeathlonRecords): asm/overlay_96.s ov96_021E7718 and what it calls,
-- the record block (pokeheartgold include/pokeathlon/pokeathlon_save.h
-- Pokeathlon_UnkSubStruct_B00, PokeathlonSave+0xB00) that the Data Monitor
-- (src/ui/HgssPokeathlonDataView.lua, ov03_02259070) and ScrCmd_724 read.
--
-- READ FROM CODE:
--   * 021E7718, solo: [won: 021E7FA8 medals, flag 0xF0 if 021E8084] -> AP
--     (x2 on course 10, the Master course) -> 021E7BA8 -> [won: 021E786C
--     course best, flag 0xEF if 021E8060] -> 021E7938 -> 021E7D6C (B00) ->
--     flag 0xF1 if 021E80C4 -> args+0xA total, +8 AP, +0xD place
--   * "won" / "last" = field data (data+0x72C) +0x1D0 bit 0 / bit 1, set by
--     021EDE64 at the closing: bit 0 the course winner is the player, bit 1
--     the player's total is the lowest of the four (bits 2-3 its place)
--   * 021E7D6C (solo; link uses +0x38/+0x3C/+0x40 instead): unk4 Times
--     Joined +1; won -> unk8 1st Places +1 and 021E7F48 (the Friendship
--     room's statues = the team's {species, gender, form}); else last ->
--     unkC Last Places +1. Per course event i (021E7658): the player ranked
--     first (data+0x8F4[i]) -> unk44[event] +1, else ranked with the last
--     (0x8F8[i]) -> unk6C Event Last Place +1. Then the player's per-Pokemon
--     course counters (field data +0x20 mon + 4 (kind-1), ov96_021E8228 /
--     021E8340, each capped at 9999) summed over the three: kind 1 -> unk18
--     Failed, 2 -> unk1C Jumped, 3 -> unk20 Acquired Points, 4 -> unk24
--     Tackled, 5 -> unk28 Fell Down, 6 -> unk2C Dashed, 7 -> unk30 Switched,
--     8 -> unk34 Self-Impeded; data+0x8AC (heap+0xAC[player], the per-Pokemon
--     awards of the three 021EDDA4 bonuses: No-Miss, Leading Score, Effort)
--     -> unk10 Bonuses Earned; data+0x8B0 (kind 0: every System_GetTouchNew
--     in an event's per-frame input, the team's total) -> unk14 Pokemon
--     Instructions. Every add is capped at 9,999,999 (021E7F98)
--   * unk0 Time Spent += data+0xD24 at the overlay's exit: +1 every 1800 of
--     the course's 30-a-second frames = minutes (cap 59999); bank 277 #2
--     prints it as {hours}:{minutes}
--   * 021E786C (won only): PokeathlonSave + 0x2C course = the course best
--     {u16 event points[3] (data+0x8B4, each capped 999), u16 total (0x8FE,
--     capped 999), mons[3] {u32 species 9 | form 5 << 9 | gender 2 << 14 |
--     shiny << 16, u32 personality}}, written only when the total beats the
--     saved one
--   * flag 0xEF (021E8060): all five single courses have a best (total != 0)
--     = "come in first in five of the courses" (D49R0104 "Solidarity" room)
--   * flag 0xF0 (021E8084): one of the team's Pokemon has all five single
--     course Medals (medal byte == 0x1F; 021E8028 ORs the course's bits
--     into PokeathlonSave+0xDC[species - 1], course 0..9 -> 1 2 4 8 10 11 14
--     6 A 9, the link courses two medals each) = D49R0105 "Trust" room
--   * flag 0xF1 (021E80C4, solo only): every event's best solo record is
--     set and beats ov96_0221A894 (021E7D30, strict): HD 3000 (lower),
--     PC 35, CP 40, BS 80, DC 40, LJ 350, RR 0x3000 (12 laps), RD 70,
--     ST 30, GR 3 = D49R0106 "Potential" room ("the best record in every event")
--
-- THE PORT'S SAVE: the B00 fields go where HgssPokeathlonDataView.field
-- reads them (save.hgssPokeathlonRecords[0..17] for ScrCmd_724's, else
-- "b00_<offset>"); the flags are save.flags.FLAG_G4_00EF / 00F0 / 00F1;
-- save.hgssPokeathlonMedals[species] = the medal bits;
-- save.hgssPokeathlonCourseBest[course] = { points = {3}, total, mons = {3 x
-- {species, form, gender, shiny, personality}} };
-- save.hgssPokeathlonStatues = 3 x { species, gender, form }.
--
-- STAND-INS, said so:
--   * the event ranks: the player is first when no team has more of the
--     event's Athlete Points, "with the last" when it is not first and no
--     team has fewer (021E94EC's sort and its tie rule are not read)
--   * Instructions: every touchpressed the event state gets (the wrapper in
--     M.watch), not only those in its input step; the pad fallback adds none
--   * Time Spent: host-clock minutes from the course's start to its end
--     (the cartridge counts frames; a harness run fast-forwards)
--   * the counters are the events' res.stats: fail / jump / score / hit /
--     dash as the modules already gave them, plus fall / switch / impede
--     where the event has them (Circle Push, Disc Catch, Ring Drop fall;
--     Relay Run, Pennant Capture, Block Smash, Ring Drop switch; Circle Push,
--     Disc Catch, Goal Roll, Ring Drop impede); Stub events add nothing
--   * course 10's course best goes to its own key: on the cartridge
--     0x2C x 10 runs past the five entries into the medal bytes (not copied)

local M = {}

M.CAP = 9999999                          -- 0x0098967F (021E7F98)
M.TIME_CAP = 59999
M.FLAG_SOLIDARITY = 0xEF                 -- won all five single courses
M.FLAG_TRUST = 0xF0                      -- one Pokemon with all five Medals
M.FLAG_POTENTIAL = 0xF1                  -- every event record past its mark
M.MEDAL = { [0] = 0x01, 0x02, 0x04, 0x08, 0x10, 0x11, 0x14, 0x06, 0x0A, 0x09 }   -- 021E7FA8
M.TARGET = { [0] = 3000, 35, 40, 80, 40, 350, 0x3000, 70, 30, 3 }                 -- ov96_0221A894
-- res.stats key -> course counter kind (ov96_021E8340) -> B00 offset
M.KINDS = { { "fail", 0x18 }, { "jump", 0x1C }, { "score", 0x20 }, { "hit", 0x24 },
  { "fall", 0x28 }, { "dash", 0x2C }, { "switch", 0x30 }, { "impede", 0x34 } }
M.COUNTER_CAP = 9999                     -- 0x270F (021E8340)

local bit = bit or require("bit")

local function DV() return require("src.ui.HgssPokeathlonDataView") end

-- adds n to the B00 field at `off` (capped), in the Data Monitor's storage
function M.add(save, off, n, cap)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  save.hgssPokeathlonRecords = save.hgssPokeathlonRecords or {}
  local rec = save.hgssPokeathlonRecords
  local key
  if off >= 0x44 and off < 0x44 + 40 then key = (off - 0x44) / 4
  else key = DV().REC_INDEX[off] or ("b00_%02X"):format(off) end
  rec[key] = math.min(cap or M.CAP, (tonumber(rec[key]) or 0) + n)
  return rec[key]
end

local function flagKey(n) return ("FLAG_G4_%04X"):format(n) end
function M.flag(save, n) return type(save.flags) == "table" and save.flags[flagKey(n)] == true end
local function setFlag(save, n)
  save.flags = save.flags or {}
  save.flags[flagKey(n)] = true
end

function M.now()
  local t = love and love.timer and love.timer.getTime
  return t and t() or os.clock()
end

-- the course state's event: counts the stylus touches (counter kind 0)
function M.watch(course, st)
  if type(st) ~= "table" then return st end
  local orig = st.touchpressed
  if orig then
    st.touchpressed = function(s, ...)
      course.touches = (course.touches or 0) + 1
      return orig(s, ...)
    end
  end
  return st
end

-- 021E7718's AP: the total, doubled (as a u16) on the Master course
function M.athletePoints(course, total)
  total = math.floor(tonumber(total) or 0)
  if course == 10 then return (total * 2) % 65536 end
  return total
end

-- 021E8060
function M.allCourses(save)
  local best = save.hgssPokeathlonCourseBest or {}
  for c = 0, 4 do
    if not (best[c] and (tonumber(best[c].total) or 0) ~= 0) then return false end
  end
  return true
end

-- 021E80C4
function M.allRecords(save)
  local R = require("src.pokemon.HgssPokeathlonRecords")
  for ev = 0, 9 do
    local s = R.score(save, ev, 1)
    if s == R.EMPTY or not R.beats(ev, M.TARGET[ev], s) then return false end
  end
  return true
end

local function clamp999(v) return math.min(999, math.floor(tonumber(v) or 0)) end

-- info (all the player's): course, won, last, events = { ev, ... },
-- eventFirst[i] / eventLast[i], counters = { fail = n, ... } (the three
-- summed), bonuses, touches, minutes, team = { mons }, points = { 3 }, total
function M.apply(save, info)
  local course = info.course or 0
  local team = info.team or {}
  -- 021E7FA8 / 021E8084: Medals, flag 0xF0
  if info.won then
    save.hgssPokeathlonMedals = save.hgssPokeathlonMedals or {}
    local medals = save.hgssPokeathlonMedals
    local bits = M.MEDAL[course]
    for _, m in ipairs(team) do
      local sp = m.species
      if bits and sp then medals[sp] = bit.bor(tonumber(medals[sp]) or 0, bits) end
    end
    if not M.flag(save, M.FLAG_TRUST) then
      for _, m in ipairs(team) do
        if m.species and medals[m.species] == 0x1F then setFlag(save, M.FLAG_TRUST); break end
      end
    end
    -- 021E786C / 021E8060: the course best, flag 0xEF
    save.hgssPokeathlonCourseBest = save.hgssPokeathlonCourseBest or {}
    local e = save.hgssPokeathlonCourseBest[course]
    local total = math.floor(tonumber(info.total) or 0)
    if total > ((e and tonumber(e.total)) or 0) then
      e = { total = clamp999(total), points = {}, mons = {} }
      for i = 1, 3 do e.points[i] = clamp999(info.points and info.points[i]) end
      for i = 1, 3 do
        local m = team[i] or {}
        e.mons[i] = { species = m.species or 0, form = m.form or 0, gender = m.gender,
          shiny = (m.shiny or m.isShiny) and true or false, personality = m.personality or 0 }
      end
      save.hgssPokeathlonCourseBest[course] = e
    end
    if not M.flag(save, M.FLAG_SOLIDARITY) and M.allCourses(save) then setFlag(save, M.FLAG_SOLIDARITY) end
  end
  -- 021E7D6C
  M.add(save, 0x4, 1)
  if info.won then
    M.add(save, 0x8, 1)
    local statues = {}
    for i = 1, 3 do
      local m = team[i] or {}
      statues[i] = { species = m.species or 0, gender = m.gender, form = m.form or 0 }
    end
    save.hgssPokeathlonStatues = statues
  elseif info.last then
    M.add(save, 0xC, 1)
  end
  for i, ev in ipairs(info.events or {}) do
    if info.eventFirst and info.eventFirst[i] then M.add(save, 0x44 + 4 * ev, 1)
    elseif info.eventLast and info.eventLast[i] then M.add(save, 0x6C, 1) end
  end
  local c = info.counters or {}
  for _, k in ipairs(M.KINDS) do M.add(save, k[2], c[k[1]]) end
  M.add(save, 0x10, info.bonuses)
  M.add(save, 0x14, math.min(M.COUNTER_CAP, math.floor(tonumber(info.touches) or 0)))
  -- 021E80C4: flag 0xF1
  if not M.flag(save, M.FLAG_POTENTIAL) and M.allRecords(save) then setFlag(save, M.FLAG_POTENTIAL) end
  -- PokeathlonCourse_Exit: the minutes
  M.add(save, 0x0, math.min(M.TIME_CAP, math.floor(tonumber(info.minutes) or 0)))
end

-- what the course state knows -> M.apply's info
function M.info(c)
  local events = c.events or {}
  local first, last = {}, {}
  for i = 1, #events do
    local mine = tonumber(c.teams[1].points[i]) or 0
    local more, fewer = false, false
    for t = 2, 4 do
      local p = tonumber(c.teams[t].points[i]) or 0
      if p > mine then more = true elseif p < mine then fewer = true end
    end
    first[i] = not more
    last[i] = more and not fewer
  end
  local totals = c.totals or {}
  local low = true
  for t = 2, 4 do if (totals[t] or 0) < (totals[1] or c.score or 0) then low = false end end
  local counters = {}
  for m = 1, 3 do
    local s = (c.teams[1].mstats or {})[m] or {}
    for _, k in ipairs(M.KINDS) do
      counters[k[1]] = (counters[k[1]] or 0) + math.min(M.COUNTER_CAP, tonumber(s[k[1]]) or 0)
    end
  end
  local minutes = 0
  if c.clock0 then minutes = math.floor(math.max(0, M.now() - c.clock0) / 60) end
  return { course = c.course, won = c.won == true, last = low, events = events, eventFirst = first,
    eventLast = last, counters = counters, bonuses = c.bonusCount or 0, touches = c.touches or 0,
    minutes = minutes, team = c.team, points = c.teams[1].points, total = c.score or 0 }
end

-- HgssPokeathlonCourse:finish, after the records
function M.commit(c)
  local save = c.game and c.game.save
  if type(save) ~= "table" then return end
  local info = M.info(c)
  M.apply(save, info)
  return info
end

return M
