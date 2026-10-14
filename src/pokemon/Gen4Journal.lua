-- PLATINUM'S JOURNAL (pokeplatinum src/journal.c, the journal_display app's
-- journal_printer.c, and the hooks in field_map_change*.c, encounter.c,
-- shop_menu.c, scrcmd.c, contest.c and field_move_tasks.c).
--
-- Once `givejournal` has run, every real-world day the player plays gets a
-- page: newest first, ten kept (Journal_GetSavedPage moves the pages down
-- when the page in hand is dated another day). A page holds
--
--   title      the date and the map the day started on
--   events     up to four location events, the oldest dropped for a fifth
--              (JournalEntry_GetEmptyLocationEvent), each kind with its own
--              rule against repeating the one before it
--   mon        the last Pokemon caught, or the fifth-or-later wild one beaten
--              since the last map load
--   trainer    the last ordinary trainer beaten
--   online     up to two link events (link battles, trades, link contests,
--              group Poffins...) -- none of which a single player makes;
--              contest.c writes "Placed no. N" only for a LINK contest
--
-- Continuing a save opens the Journal when the newest page is two or more
-- days old (Journal_CheckOpenOnContinue). The words are bank 366's.
--
-- Stored in save.gen4Journal = { acquired = bool, pages = { [1..10] } }.

local J = {}

J.BANK = 366
J.LOCATION_NAMES, J.TRAINER_NAMES, J.GYM_NAMES = 433, 618, 378
J.MONTHS, J.TIMES_OF_DAY = 414, 608
J.PAGES, J.EVENTS, J.ONLINE = 10, 4, 2

-- generated/journal_location_events.txt, in order
local E = {}
for i, name in ipairs({ "NONE", "RESTED_AT_HOME", "LEFT_RESEARCH_LAB", "USED_PC_BOX", "SHOPPED_AT_MART",
  "LOTS_OF_SHOPPING", "SOLD_A_LITTLE", "SOLD_A_LOT", "BUSINESS_AT_MART", "GYM_WAS_TOO_TOUGH",
  "BEAT_GYM_LEADER", "BEAT_ELITE_FOUR_MEMBER", "BEAT_CHAMPION", "ARRIVED_IN_LOCATION", "LEFT_CAVE",
  "LEFT_BUILDING", "GAME_CORNER", "SAFARI_GAME", "ITEM_WAS_OBTAINED", "USED_CUT", "FLEW_TO_LOCATION",
  "USED_SURF", "USED_STRENGTH", "USED_DEFOG", "USED_ROCK_SMASH", "USED_WATERFALL", "USED_ROCK_CLIMB",
  "USED_FLASH", "WARPED_TO_LOCATION", "USED_DIG", "LURED_POKEMON", "UNUSED", "USED_MILK_DRINK",
  "USED_SOFTBOILED", "DUG_UNDERGROUND", "BUILT_SECRET_BASE", "BATTLE_TOWER", "BATTLE_FACTORY",
  "BATTLE_CASTLE", "BATTLE_HALL", "BATTLE_ARCADE" }) do E[name] = i - 1 end
J.EVENT = E
J.ONLINE_PLACED_IN_CONTEST = 17    -- generated/journal_online_events.txt

-- the map header ids and text ids the rules name (generated/map_headers.txt,
-- res/text/location_names.json, generated/trainers.txt)
J.HOME_1F, J.RESEARCH_LAB = 414, 422
J.GYMS = {                         -- sGymsInfo: leader, gym map, badge index
  { trainer = 246, map = 47 }, { trainer = 315, map = 67 }, { trainer = 316, map = 122 },
  { trainer = 317, map = 133 }, { trainer = 318, map = 88 }, { trainer = 319, map = 167 },
  { trainer = 250, map = 35 }, { trainer = 320, map = 154 },
}
J.ELITE_FOUR = { [261] = true, [866] = true, [262] = true, [867] = true, [263] = true, [868] = true,
                 [264] = true, [869] = true }
J.CHAMPION = { [267] = true, [870] = true }
-- sMapsInfo: the buildings whose leaving is written down, and which say
-- "Exited from" rather than "Departed from"
J.BUILDINGS = {
  [90] = true, [91] = false, [92] = true, [93] = true, [94] = false, [95] = true, [96] = true,
  [97] = true, [98] = true, [99] = false, [100] = true, [101] = false, [102] = true, [71] = false,
  [103] = false, [64] = false, [104] = false, [105] = true, [80] = true, [106] = false, [107] = true,
  [108] = false, [109] = false, [110] = false, [47] = false, [49] = false, [70] = false,
}
J.DEPARTED_CAVES = { [47] = true, [64] = true, [49] = true }  -- Windworks, Snowpoint Temple, Ironworks
J.TOWN, J.OUTDOORS, J.CAVE, J.INDOORS, J.POKECENTER = 1, 2, 3, 4, 5

-- ------------------------------------------------------------- the date --

-- RTCDate: year 0..99, month 1..12, day, week 0 = Sunday
function J.today(clock)
  local t = clock or os.date("*t")
  return { year = (t.year or 2000) % 100, month = t.month, day = t.day, week = (t.wday or 1) - 1 }
end

-- DayNumberForDate: days since 2000-01-01
local function dayNumber(d)
  local y = 2000 + (d.year or 0)
  local t = os.time({ year = y, month = d.month or 1, day = d.day or 1, hour = 12 })
  return math.floor(t / 86400)
end

local function state(save)
  if type(save) ~= "table" then return nil end
  save.gen4Journal = save.gen4Journal or { acquired = false, pages = {} }
  save.gen4Journal.pages = save.gen4Journal.pages or {}
  return save.gen4Journal
end
J.state = state

local function blank() return { title = nil, events = {}, mon = nil, trainer = nil, online = {} } end

local function sameDay(a, b)
  return a and b and a.year == b.year and a.month == b.month and a.day == b.day and a.week == b.week
end

-- Journal_GetSavedPage: today's page, moving the others down when the page
-- in hand is dated another day. nil until the Journal is acquired.
function J.page(save, today)
  local s = state(save)
  if not (s and s.acquired) then return nil end
  today = today or J.today()
  local first = s.pages[1]
  if not first then s.pages[1] = blank(); return s.pages[1] end
  if first.title and first.title.month ~= 0 and not sameDay(first.title, today) then
    table.insert(s.pages, 1, blank())
    while #s.pages > J.PAGES do table.remove(s.pages) end
  end
  return s.pages[1]
end

-- Journal_CheckOpenOnContinue
function J.openOnContinue(save, today)
  local s = state(save)
  if not (s and s.acquired) then return false end
  local first = s.pages[1]
  local title = first and first.title
  if not title then return false end
  today = today or J.today()
  local diff = dayNumber(today) - dayNumber(title)
  if (today.month == 12 and today.day == 31 and title.month == 1 and title.day == 1)
      or (today.month == 1 and today.day == 1 and title.month == 12 and title.day == 31) then
    local years = today.year - title.year
    return years >= 2 or years <= -2
  elseif diff <= -2 or diff >= 2 then
    return true
  end
  return today.year ~= title.year
end

-- JournalEntry_SaveTitle: once a day
function J.title(save, header, today)
  local p = J.page(save, today)
  if not p then return end
  today = today or J.today()
  if p.title and sameDay(p.title, today) then return end
  p.title = { year = today.year, month = today.month, day = today.day, week = today.week, map = tonumber(header) or 0 }
end

-- ----------------------------------------------------- location events --

local function pushEvent(events, ev)
  if #events >= J.EVENTS then table.remove(events, 1) end
  events[#events + 1] = ev
end

local MISC = {}
for _, n in ipairs({ "RESTED_AT_HOME", "LEFT_RESEARCH_LAB", "USED_PC_BOX", "SHOPPED_AT_MART", "LOTS_OF_SHOPPING",
  "SOLD_A_LITTLE", "SOLD_A_LOT", "BUSINESS_AT_MART", "GAME_CORNER", "SAFARI_GAME", "DUG_UNDERGROUND",
  "BUILT_SECRET_BASE", "BATTLE_TOWER", "BATTLE_FACTORY", "BATTLE_CASTLE", "BATTLE_HALL", "BATTLE_ARCADE" }) do
  MISC[E[n]] = true
end
local TRAVEL = { [E.ARRIVED_IN_LOCATION] = true, [E.LEFT_CAVE] = true, [E.LEFT_BUILDING] = true }
local MOVE = {}
for k = E.USED_CUT, E.USED_SOFTBOILED do MOVE[k] = true end

-- JournalEntry_SaveLocationEvent: ev = { type, location, trainer, item }
function J.location(save, ev, today)
  local p = J.page(save, today)
  if not (p and ev and ev.type) then return end
  local events, last = p.events, p.events[#p.events]
  local t = ev.type
  if MISC[t] then
    if last and last.type == t then return end
    pushEvent(events, { type = t })
  elseif t == E.GYM_WAS_TOO_TOUGH or t == E.BEAT_GYM_LEADER then
    -- a gym beaten (or tried again) replaces that gym's "too tough"
    for i, e in ipairs(events) do
      if e.type == E.GYM_WAS_TOO_TOUGH and e.location == ev.location then table.remove(events, i); break end
    end
    pushEvent(events, { type = t, location = ev.location, trainer = ev.trainer })
  elseif t == E.BEAT_ELITE_FOUR_MEMBER then
    for i, e in ipairs(events) do
      if e.type == E.BEAT_ELITE_FOUR_MEMBER then table.remove(events, i); break end
    end
    pushEvent(events, { type = t, trainer = ev.trainer })
  elseif t == E.BEAT_CHAMPION then
    pushEvent(events, { type = t, trainer = ev.trainer })
  elseif TRAVEL[t] or MOVE[t] then
    if last and last.type == t and last.location == ev.location then return end
    pushEvent(events, { type = t, location = ev.location })
  elseif t == E.ITEM_WAS_OBTAINED then
    if last and last.type == t and last.item == ev.item then return end
    pushEvent(events, { type = t, item = ev.item })
  end
end

-- JournalEntry_CreateEventMonCaught / ...Defeated: the wording is picked by
-- the play time's minutes when it happened
function J.mon(save, result, species, gender, timeOfDay, minutes, today)
  local p = J.page(save, today)
  if not p then return end
  local tens = math.floor((tonumber(minutes) or 0) / 10) % 6
  local variant
  if result == "caught" then
    variant = (tens == 0 or tens == 2 or tens == 4) and 0 or ((tens == 1 or tens == 3) and 1 or 2)
  else
    variant = (tens == 1 or tens == 3 or tens == 5) and 0 or ((tens == 2 or tens == 4) and 1 or 2)
  end
  p.mon = { result = result, species = species, gender = gender, time = timeOfDay, variant = variant }
end

-- JournalEntry_CreateAndSaveEventTrainer
function J.trainer(save, header, trainerId, today)
  trainerId = tonumber(trainerId)
  if not trainerId then return end
  for gym, g in ipairs(J.GYMS) do
    if g.trainer == trainerId then
      return J.location(save, { type = E.BEAT_GYM_LEADER, location = gym - 1, trainer = trainerId }, today)
    end
  end
  if J.ELITE_FOUR[trainerId] then return J.location(save, { type = E.BEAT_ELITE_FOUR_MEMBER, trainer = trainerId }, today) end
  if J.CHAMPION[trainerId] then return J.location(save, { type = E.BEAT_CHAMPION, trainer = trainerId }, today) end
  local p = J.page(save, today)
  if p then p.trainer = { trainer = trainerId, map = tonumber(header) } end
end

function J.online(save, ev, today)
  local p = J.page(save, today)
  if not p then return end
  if #p.online >= J.ONLINE then table.remove(p.online, 1) end
  p.online[#p.online + 1] = ev
end

-- ------------------------------------------------------- the map hooks --

local function headerRow(data, header)
  local rec = data and data.gen4_area_popup
  return rec and rec.headers and rec.headers[tonumber(header) or -1]
end
local function isType(data, header, ...)
  local row = headerRow(data, header)
  local t = row and row.mapType
  for _, want in ipairs({ ... }) do if t == want then return true end end
  return false
end
local function label(data, header) local row = headerRow(data, header) return row and row.text end

-- FieldSystem_InitFlagsWarp / _InitFlagsOnMapChange, BEFORE the map's fly
-- destination is unlocked: the first arrival at a town, or else (on a warp)
-- what leaving the last map means. `hasBadge(index)` answers for badge 0..7.
function J.onMapChange(save, data, fromHeader, toHeader, warp, hasBadge)
  if not J.page(save) then return end
  toHeader = tonumber(toHeader)
  -- CreateFlyLocationJournalEvent: a fly spot not yet opened
  local Fly = require("src.world.Gen4Fly")
  for _, row in ipairs((data.field and data.field.healLocations) or {}) do
    if row.fly and tonumber(row.fly.header) == toHeader then
      if row.unlockOnMapEntry and not Fly.unlocked(save, row) then
        J.location(save, { type = E.ARRIVED_IN_LOCATION, location = toHeader })
        return
      end
      break
    end
  end
  if not warp then return end
  fromHeader = tonumber(fromHeader)
  if not fromHeader or fromHeader == toHeader then return end
  -- JournalEntry_CreateAndSaveEventMapTransition
  if isType(data, fromHeader, J.CAVE) then
    if isType(data, toHeader, J.TOWN, J.OUTDOORS) then
      J.location(save, { type = E.LEFT_CAVE, location = label(data, fromHeader) })
    end
  elseif isType(data, fromHeader, J.INDOORS, J.POKECENTER) then
    if isType(data, toHeader, J.TOWN, J.OUTDOORS) then
      if fromHeader == J.HOME_1F then J.location(save, { type = E.RESTED_AT_HOME })
      elseif fromHeader == J.RESEARCH_LAB then J.location(save, { type = E.LEFT_RESEARCH_LAB })
      else
        local text = label(data, fromHeader)
        if text and J.BUILDINGS[text] ~= nil then J.location(save, { type = E.LEFT_BUILDING, location = text }) end
      end
    end
  elseif isType(data, fromHeader, J.TOWN, J.OUTDOORS) then
    if isType(data, toHeader, J.INDOORS, J.POKECENTER) then
      for gym, g in ipairs(J.GYMS) do
        if g.map == toHeader then
          if not (hasBadge and hasBadge(gym - 1)) then
            J.location(save, { type = E.GYM_WAS_TOO_TOUGH, location = gym - 1 })
          end
          break
        end
      end
    end
  end
end

-- shop_menu.c, on closing an ordinary mart (not the Veilstone Store, the
-- Herb Shop or Celestic's house)
function J.onShopClosed(save, bought, sold)
  bought, sold = tonumber(bought) or 0, tonumber(sold) or 0
  local t
  if bought ~= 0 and sold ~= 0 then t = E.BUSINESS_AT_MART
  elseif bought > 1 then t = E.LOTS_OF_SHOPPING
  elseif sold > 1 then t = E.SOLD_A_LOT
  elseif bought ~= 0 then t = E.SHOPPED_AT_MART
  elseif sold ~= 0 then t = E.SOLD_A_LITTLE end
  if t then J.location(save, { type = t }) end
end
J.SHOP_EXCLUDED_LABEL = 101          -- the Veilstone Store
-- MAP_HEADER_ETERNA_CITY_HERB_SHOP, MAP_HEADER_CELESTIC_TOWN_NORTHWEST_HOUSE
J.SHOP_EXCLUDED_HEADERS = { [81] = true, [446] = true }
J.RIVAL_CLASS = 63                   -- TRAINER_CLASS_RIVAL

-- JournalEntry_CreateEventUsedMove: a field move (enum FieldMoveList: CUT 0,
-- FLY 1 ... TELEPORT 9, DIG 10, SWEET_SCENT 11, MILK_DRINK 13, SOFTBOILED 14)
-- is the location event USED_CUT + its index, at the map it names
J.MOVE = { CUT = 0, FLY = 1, SURF = 2, STRENGTH = 3, DEFOG = 4, ROCK_SMASH = 5, WATERFALL = 6,
           ROCK_CLIMB = 7, FLASH = 8, TELEPORT = 9, DIG = 10, SWEET_SCENT = 11, MILK_DRINK = 13,
           SOFTBOILED = 14 }
function J.usedMove(save, index, header)
  J.location(save, { type = E.USED_CUT + index, location = tonumber(header) or 0 })
end

-- ScrCmd_CreateJournalEvent: eventType, eventParam
function J.fromScript(save, eventType, param)
  eventType = tonumber(eventType)
  if eventType == E.GAME_CORNER or eventType == E.SAFARI_GAME then
    J.location(save, { type = eventType })
  elseif eventType == E.ITEM_WAS_OBTAINED then
    J.location(save, { type = eventType, item = tonumber(param) })
  elseif eventType and eventType >= E.USED_CUT and eventType <= E.USED_ROCK_CLIMB and eventType ~= E.FLEW_TO_LOCATION then
    J.location(save, { type = eventType, location = tonumber(param) })
  elseif eventType and eventType >= E.BATTLE_TOWER and eventType <= E.BATTLE_ARCADE then
    J.location(save, { type = eventType })
  end
end

-- ------------------------------------------------------------- printing --

local T = require("src.import.Gen4Text")

local function line(game, bank, index, slots)
  local values = {}
  for s = 0, 4 do values[s + 1] = slots and slots[s] or "" end
  T.buffer(game, (table.unpack or unpack)(values))
  return T.resolve(game.data, bank, index, game)
end
local function text(game, bank, index) return T.resolve(game.data, bank, index, game) or "" end
local function place(game, header)
  local l = label(game.data, header)
  return l and text(game, J.LOCATION_NAMES, l) or ""
end
local function itemName(game, id)
  local def = game.data.items and game.data.items[tonumber(id) or -1]
  return def and def.name or ""
end
local function speciesName(game, id)
  local def = game.data.pokemon and game.data.pokemon[tonumber(id) or -1]
  return def and def.name or ""
end
local function trainerName(game, id) return text(game, J.TRAINER_NAMES, tonumber(id) or 0) end

local LOC_LINE = {
  [E.RESTED_AT_HOME] = 9, [E.LEFT_RESEARCH_LAB] = 10, [E.USED_PC_BOX] = 11, [E.SHOPPED_AT_MART] = 12,
  [E.LOTS_OF_SHOPPING] = 13, [E.SOLD_A_LITTLE] = 14, [E.SOLD_A_LOT] = 15, [E.BUSINESS_AT_MART] = 16,
  [E.BATTLE_TOWER] = 25, [E.BATTLE_FACTORY] = 26, [E.BATTLE_CASTLE] = 27, [E.BATTLE_HALL] = 28,
  [E.BATTLE_ARCADE] = 29, [E.GAME_CORNER] = 30, [E.SAFARI_GAME] = 31, [E.DUG_UNDERGROUND] = 32,
  [E.BUILT_SECRET_BASE] = 33, [E.LURED_POKEMON] = 45, [E.USED_SOFTBOILED] = 47, [E.USED_MILK_DRINK] = 48,
}
local MOVE_LINE = {
  [E.USED_CUT] = 35, [E.FLEW_TO_LOCATION] = 36, [E.USED_SURF] = 37, [E.USED_STRENGTH] = 38,
  [E.USED_FLASH] = 39, [E.USED_ROCK_SMASH] = 40, [E.USED_WATERFALL] = 41, [E.USED_ROCK_CLIMB] = 42,
  [E.USED_DEFOG] = 43, [E.USED_DIG] = 44, [E.WARPED_TO_LOCATION] = 46,
}

-- journal_printer.c's lines for one event
function J.eventLine(game, ev)
  local t = ev.type
  if LOC_LINE[t] then return text(game, J.BANK, LOC_LINE[t]) end
  if MOVE_LINE[t] then return line(game, J.BANK, MOVE_LINE[t], { [0] = place(game, ev.location) }) end
  if t == E.GYM_WAS_TOO_TOUGH then return line(game, J.BANK, 17, { [0] = text(game, J.GYM_NAMES, ev.location) }) end
  if t == E.BEAT_GYM_LEADER then
    return line(game, J.BANK, 18, { [0] = text(game, J.GYM_NAMES, ev.location), trainerName(game, ev.trainer) })
  end
  if t == E.BEAT_ELITE_FOUR_MEMBER then return line(game, J.BANK, 19, { [0] = trainerName(game, ev.trainer) }) end
  if t == E.BEAT_CHAMPION then return line(game, J.BANK, 20, { [0] = trainerName(game, ev.trainer) }) end
  if t == E.ARRIVED_IN_LOCATION then return line(game, J.BANK, 21, { [0] = place(game, ev.location) }) end
  if t == E.LEFT_CAVE then
    return line(game, J.BANK, J.DEPARTED_CAVES[ev.location] and 23 or 22, { [0] = text(game, J.LOCATION_NAMES, ev.location) })
  end
  if t == E.LEFT_BUILDING then
    return line(game, J.BANK, J.BUILDINGS[ev.location] and 24 or 23, { [0] = text(game, J.LOCATION_NAMES, ev.location) })
  end
  if t == E.ITEM_WAS_OBTAINED then return line(game, J.BANK, 34, { [0] = itemName(game, ev.item) }) end
  return nil
end

function J.monLine(game, m)
  local idx
  if m.result == "caught" then
    if m.variant == 0 then idx = 49 elseif m.variant == 1 then idx = 50
    else idx = (m.gender == 0 and 51) or (m.gender == 1 and 52) or 49 end
  else
    if m.variant == 0 then idx = 53 elseif m.variant == 1 then idx = 54
    else idx = (m.gender == 0 and 55) or (m.gender == 1 and 56) or 53 end
  end
  return line(game, J.BANK, idx, { [0] = speciesName(game, m.species), text(game, J.TIMES_OF_DAY, m.time or 0) })
end

-- JournalPrinter_PrintTrainerEvent: the wording by the combined length of
-- the place and the trainer's name
function J.trainerLine(game, tr, rivalName)
  local where = place(game, tr.map)
  local who = rivalName or trainerName(game, tr.trainer)
  local n = #where + #who
  local idx = (n <= 14 and 57) or (n <= 16 and 58) or (n <= 19 and 59) or 60
  return line(game, J.BANK, idx, { [0] = where, who })
end

-- The page as the printer lays it out: { title = {date, weekday}, lines = {...} }
function J.render(game, page)
  if not (page and page.title) then return nil end
  local t = page.title
  local out = { lines = {} }
  out.date = line(game, J.BANK, 1, { [0] = text(game, J.MONTHS, math.max(1, math.min(12, t.month or 1)) - 1), tostring(t.day or 1) })
  out.weekday = text(game, J.BANK, 2 + (t.week or 0))
  out.lines[1] = line(game, J.BANK, 0, { [0] = place(game, t.map) })
  for i = 1, J.EVENTS do
    local ev = page.events[i]
    out.lines[1 + i] = ev and J.eventLine(game, ev) or ""
  end
  out.lines[6] = page.mon and J.monLine(game, page.mon) or ""
  if page.trainer then
    -- the rival is written down by the name the player gave him
    local def = game.data.trainers and game.data.trainers[page.trainer.trainer]
    local rival = def and tonumber(def.class) == J.RIVAL_CLASS
      and game.save and game.save.player and (game.save.player.rival or game.save.player.rivalName) or nil
    out.lines[7] = J.trainerLine(game, page.trainer, rival)
  else
    out.lines[7] = ""
  end
  for i = 1, J.ONLINE do
    local o = page.online[i]
    out.lines[7 + i] = (o and o.type == J.ONLINE_PLACED_IN_CONTEST)
      and line(game, J.BANK, 87, { [0] = tostring(o.result or 1) }) or ""
  end
  return out
end

return J
