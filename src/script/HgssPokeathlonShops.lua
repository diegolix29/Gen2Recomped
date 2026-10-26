-- HEARTGOLD / SOULSILVER'S POKeATHLON DOME COUNTERS, the script side
-- (pokeheartgold src/scrcmd_mart.c, field/scrcmd_pokemon_misc.c,
-- pokeathlon/pokeathlon_save.c):
--
--   ScrCmd_771          the Athlete Shop's prize exchange (D49R0101 clerk,
--                       M0123 _03C8): Mart_Init(MART_TYPE_POKEATHLON_DAILY)
--                       with today's list -- sPokeathlonPrizeExchangePrice-
--                       Overrides[weekday], [weekday + 7] once the National
--                       Dex is had (the list is the price table: the item
--                       pointer _0210F9CC[weekday] is the leftover decoration
--                       list and is never read for this type)
--   ScrCmd_772          the Data Card counter (M0123 _0494): the group of the
--                       lowest card not yet received, i / 6 of _0210F9D4
--   ScrCmd_834 <var>    TRUE while today's list has more entries than daily
--                       slots taken (any of 12 bits counts)
--   ScrCmd_835 <var>    the lowest Data Card not yet received (27 = all)
--   ScrCmd_741 <shelf, idx, price, pop>
--                       the Aprijuice stand's label (src/pokemon/HgssAprijuice
--                       .lua): owner / juice name / price / richness /
--                       smoothness into string slots 0-4, the juice index,
--                       its price and its "pop" into the vars
--   ScrCmd_740 <idx, result>
--                       the drinking app (sub_0203ED80 -> overlay 58 mode 3):
--                       the party to choose who drinks; result 1 when one did
--                       (ov58_022379C0 sets the modifiers), 0 cancelled
--   ScrCmd_743 <type>   the Pokeathlon data monitor (src/ui/HgssPokeathlon
--                       DataView.lua) -- the Data Cards are READ there
--
-- THE SAVE (PokeathlonSave +0xB78 / +0xB7C, here `save.hgssPokeathlonShop`):
-- `cards`, the 27 received bits; `daily`, the taken list positions, kept with
-- the day they belong to -- PokeathlonSave_ResetDailyItemReceivedFlags runs
-- from the new-day handler on the cartridge; here a different day reads as
-- none taken, which is the same thing. Athlete Points are
-- `save.hgssAthletePoints` (0..99999).
--
-- STAND-INS, said so: the drinking app's own screens (overlay 59 -- the
-- juice poured, the stats shown) are not drawn; the party menu picks and the
-- juice is drunk. The weekday is the host clock's (GF_RTC_CopyDate).
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
Commands.meta = Commands.meta or {}

local M = {}

local function G4() return require("src.script.Gen4Commands") end

-- items (constants/items.h)
local I = {
  FULL_RESTORE = 23, MOOMOO_MILK = 33, RARE_CANDY = 50, PP_UP = 51,
  SUN_STONE = 80, MOON_STONE = 81, FIRE_STONE = 82, THUNDERSTONE = 83, WATER_STONE = 84,
  LEAF_STONE = 85, NUGGET = 92, HEART_SCALE = 93, SHINY_STONE = 107, DUSK_STONE = 108,
  DAWN_STONE = 109, KINGS_ROCK = 221, METAL_COAT = 233, DRAGON_SCALE = 235,
  RED = 485, YLW = 486, BLU = 487, GRN = 488, PNK = 489, WHT = 490, BLK = 491,
}
M.ITEMS = I

-- sPokeathlonPrizeExchangePriceOverrides[0..13]: Sunday..Saturday, then the
-- same week with the National Dex
M.DAILY = {
  [0] = { { I.RED, 200 }, { I.BLU, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.KINGS_ROCK, 3000 }, { I.HEART_SCALE, 1000 } },
  [1] = { { I.RED, 200 }, { I.BLU, 200 }, { I.GRN, 200 }, { I.MOOMOO_MILK, 100 }, { I.MOON_STONE, 3000 }, { I.RARE_CANDY, 2000 } },
  [2] = { { I.YLW, 200 }, { I.PNK, 200 }, { I.WHT, 200 }, { I.MOOMOO_MILK, 100 }, { I.FIRE_STONE, 2500 }, { I.PP_UP, 1000 } },
  [3] = { { I.BLU, 200 }, { I.PNK, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.WATER_STONE, 2500 }, { I.HEART_SCALE, 1000 } },
  [4] = { { I.YLW, 200 }, { I.PNK, 200 }, { I.WHT, 200 }, { I.MOOMOO_MILK, 100 }, { I.THUNDERSTONE, 2500 }, { I.PP_UP, 1000 } },
  [5] = { { I.RED, 200 }, { I.YLW, 200 }, { I.GRN, 200 }, { I.MOOMOO_MILK, 100 }, { I.METAL_COAT, 2500 }, { I.NUGGET, 500 } },
  [6] = { { I.GRN, 200 }, { I.WHT, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.LEAF_STONE, 2500 }, { I.RARE_CANDY, 2000 } },
  [7] = { { I.RED, 200 }, { I.BLU, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.KINGS_ROCK, 3000 }, { I.HEART_SCALE, 1000 },
    { I.FULL_RESTORE, 500 }, { I.NUGGET, 500 }, { I.SUN_STONE, 3000 }, { I.FIRE_STONE, 2500 }, { I.SHINY_STONE, 3000 }, { I.DAWN_STONE, 3000 } },
  [8] = { { I.RED, 200 }, { I.BLU, 200 }, { I.GRN, 200 }, { I.MOOMOO_MILK, 100 }, { I.MOON_STONE, 3000 }, { I.RARE_CANDY, 2000 },
    { I.FULL_RESTORE, 500 }, { I.KINGS_ROCK, 3000 }, { I.SUN_STONE, 3000 }, { I.WATER_STONE, 2500 }, { I.SHINY_STONE, 3000 }, { I.DUSK_STONE, 3000 } },
  [9] = { { I.YLW, 200 }, { I.PNK, 200 }, { I.WHT, 200 }, { I.MOOMOO_MILK, 100 }, { I.FIRE_STONE, 2500 }, { I.PP_UP, 1000 },
    { I.FULL_RESTORE, 500 }, { I.METAL_COAT, 2500 }, { I.WATER_STONE, 2500 }, { I.LEAF_STONE, 2500 }, { I.DUSK_STONE, 3000 }, { I.DAWN_STONE, 3000 } },
  [10] = { { I.BLU, 200 }, { I.PNK, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.WATER_STONE, 2500 }, { I.HEART_SCALE, 1000 },
    { I.FULL_RESTORE, 500 }, { I.DRAGON_SCALE, 2500 }, { I.THUNDERSTONE, 2500 }, { I.MOON_STONE, 3000 }, { I.SHINY_STONE, 3000 }, { I.DAWN_STONE, 3000 } },
  [11] = { { I.YLW, 200 }, { I.PNK, 200 }, { I.WHT, 200 }, { I.MOOMOO_MILK, 100 }, { I.THUNDERSTONE, 2500 }, { I.PP_UP, 1000 },
    { I.FULL_RESTORE, 500 }, { I.KINGS_ROCK, 3000 }, { I.FIRE_STONE, 2500 }, { I.LEAF_STONE, 2500 }, { I.SHINY_STONE, 3000 }, { I.DUSK_STONE, 3000 } },
  [12] = { { I.RED, 200 }, { I.YLW, 200 }, { I.GRN, 200 }, { I.MOOMOO_MILK, 100 }, { I.METAL_COAT, 2500 }, { I.NUGGET, 500 },
    { I.FULL_RESTORE, 500 }, { I.DRAGON_SCALE, 2500 }, { I.WATER_STONE, 2500 }, { I.SUN_STONE, 3000 }, { I.DUSK_STONE, 3000 }, { I.DAWN_STONE, 3000 } },
  [13] = { { I.GRN, 200 }, { I.WHT, 200 }, { I.BLK, 200 }, { I.MOOMOO_MILK, 100 }, { I.LEAF_STONE, 2500 }, { I.RARE_CANDY, 2000 },
    { I.FULL_RESTORE, 500 }, { I.METAL_COAT, 2500 }, { I.THUNDERSTONE, 2500 }, { I.SHINY_STONE, 3000 }, { I.DUSK_STONE, 3000 }, { I.DAWN_STONE, 3000 } },
}

-- _0210F9D4: the Data Cards (ITEM_DATA_CARD_01 = 505) in five groups
M.DATA_CARD_01 = 505
M.CARD_COUNT = 27
M.CARDS = {
  [0] = { { 505, 500 }, { 506, 500 }, { 507, 1000 }, { 508, 1000 }, { 509, 500 }, { 510, 500 } },
  [1] = { { 511, 1000 }, { 512, 1000 }, { 513, 1000 }, { 514, 1000 }, { 515, 1000 }, { 516, 1000 } },
  [2] = { { 517, 1500 }, { 518, 1500 }, { 519, 1500 }, { 520, 1000 }, { 521, 1000 }, { 522, 1000 } },
  [3] = { { 523, 500 }, { 524, 500 }, { 525, 2000 }, { 526, 2000 }, { 527, 1000 }, { 528, 1000 } },
  [4] = { { 529, 2000 }, { 530, 3000 }, { 531, 9999 } },
}

-- the host clock's weekday, 0 = Sunday (RTCDate.week)
function M.weekday(now) return (os.date("*t", now or os.time()).wday or 1) - 1 end
local function today(now) return require("src.world.HgssApricorns").today(now) end

function M.state(save)
  local s = save.hgssPokeathlonShop
  if not s then
    s = { cards = 0, daily = 0, day = today() }
    save.hgssPokeathlonShop = s
  end
  -- the new day clears the taken prizes (ResetDailyItemReceivedFlags)
  local d = today()
  if s.day ~= d then s.day, s.daily = d, 0 end
  return s
end

local function bit(n, i) return math.floor((tonumber(n) or 0) / 2 ^ i) % 2 == 1 end

function M.hasCard(save, i)
  if not save or i < 0 or i >= M.CARD_COUNT then return false end
  return bit(M.state(save).cards, i)
end
function M.giveCard(save, i)
  if i < 0 or i >= M.CARD_COUNT or M.hasCard(save, i) then return end
  local s = M.state(save)
  s.cards = (s.cards or 0) + 2 ^ i
end
function M.dailyTaken(save, i) return save ~= nil and bit(M.state(save).daily, i) end
function M.takeDaily(save, i)
  if M.dailyTaken(save, i) then return end
  local s = M.state(save)
  s.daily = (s.daily or 0) + 2 ^ i
end

-- ScrCmd_835
function M.firstMissingCard(save)
  for i = 0, M.CARD_COUNT - 1 do
    if not M.hasCard(save, i) then return i end
  end
  return M.CARD_COUNT
end

-- today's list (the National Dex picks the long one)
function M.dailyList(save, week)
  local natDex = save and save.pokedex and save.pokedex.national
  return M.DAILY[(week or M.weekday()) + (natDex and 7 or 0)]
end

-- ScrCmd_834
function M.dailyLeft(save, week)
  local list = M.dailyList(save, week)
  local taken = 0
  for i = 0, 11 do if M.dailyTaken(save, i) then taken = taken + 1 end end
  return #list > taken
end

local function openShop(ctx, kind, list)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local stock, prices = {}, {}
  for i, row in ipairs(list) do stock[i] = row[1]; prices[row[1]] = row[2] end
  require("src.ui.Screens").push(game, "ShopMenu", stock, function()
    if runner then runner:resume() end
  end, nil, { athlon = { kind = kind, prices = prices } })
  if runner then runner:yield() end
end

function Commands.g4_hgss_athlon_prizes(ctx)
  if not ctx.save then return end
  openShop(ctx, "daily", M.dailyList(ctx.save))
end
Commands.meta.g4_hgss_athlon_prizes = { foreground = true, blocking = true }

function Commands.g4_hgss_athlon_data_cards(ctx)
  if not ctx.save then return end
  openShop(ctx, "cards", M.CARDS[math.floor(M.firstMissingCard(ctx.save) / 6)])
end
Commands.meta.g4_hgss_athlon_data_cards = { foreground = true, blocking = true }

function Commands.g4_hgss_athlon_daily_left(ctx, destVar)
  G4().setVar(ctx.save, destVar, (ctx.save and M.dailyLeft(ctx.save)) and 1 or 0)
end
function Commands.g4_hgss_athlon_card_count(ctx, destVar)
  G4().setVar(ctx.save, destVar, ctx.save and M.firstMissingCard(ctx.save) or 0)
end

-- ScrCmd_741
function Commands.g4_hgss_aprijuice_label(ctx, shelfVar, idxVar, priceVar, popVar)
  local g, save, game = G4(), ctx.save, ctx.game
  if not save then return end
  local J = require("src.pokemon.HgssAprijuice")
  local shelf = math.floor(tonumber(g.valueOf(ctx, shelfVar)) or 0)
  local idx, juice = J.shelfJuice(save, shelf, M.weekday())
  local L = J.label(save, idx, juice)
  local T = require("src.import.Gen4Text")
  local data = game and game.data
  local function bankLine(b, n) return (data and T.resolve(data, b, n, game)) or "" end
  if game then
    game.stringBuffers = game.stringBuffers or {}
    local b = game.stringBuffers
    b[1] = L.owner.text or bankLine(L.owner.bank, L.owner.entry)
    b[2] = bankLine(J.NAME_BANK, L.nameEntry)
    b[3] = tostring(L.price)
    b[4] = tostring(L.richness)
    b[5] = tostring(L.smoothness)
  end
  g.setVar(save, idxVar, idx)
  g.setVar(save, priceVar, L.price)
  g.setVar(save, popVar, L.pop)
end

-- ScrCmd_740
function Commands.g4_hgss_aprijuice_drink(ctx, idxVar, resultVar)
  local g, game, save = G4(), ctx.game, ctx.save
  if not (game and game.stack and save) then return end
  local runner = ctx.runner
  local J = require("src.pokemon.HgssAprijuice")
  local juice = J.juice(save, math.floor(tonumber(g.valueOf(ctx, idxVar)) or 0))
  -- ov58_02237B40: the answer starts at 0
  g.setVar(save, resultVar, 0)
  local done = false
  local function finish(mon)
    if done then return end
    done = true
    if mon and juice then
      J.drink(mon, juice)
      g.setVar(save, resultVar, 1)
    end
    if runner then runner:resume() end
  end
  local ok = pcall(require("src.ui.Screens").push, game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon) finish(mon) end,
    onCancel = function() finish(nil) end,
  })
  if not ok then return end
  if runner and not done then runner:yield() end
end
Commands.meta.g4_hgss_aprijuice_drink = { foreground = true, blocking = true }

-- ScrCmd_743
function Commands.g4_hgss_athlon_data(ctx, kind)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local V = require("src.ui.HgssPokeathlonDataView")
  game.stack:push(V.new(game, math.floor(tonumber(G4().valueOf(ctx, kind)) or 0), function()
    if runner then runner:resume() end
  end))
  if runner then runner:yield() end
end
Commands.meta.g4_hgss_athlon_data = { foreground = true, blocking = true }

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.scrcmd_771 = L.scrcmd_771 or function(_, s) emit(s, { "g4_hgss_athlon_prizes" }) end
  L.scrcmd_772 = L.scrcmd_772 or function(_, s) emit(s, { "g4_hgss_athlon_data_cards" }) end
  L.scrcmd_834 = L.scrcmd_834 or function(ins, s) emit(s, { "g4_hgss_athlon_daily_left", ins.args[1] }) end
  L.scrcmd_835 = L.scrcmd_835 or function(ins, s) emit(s, { "g4_hgss_athlon_card_count", ins.args[1] }) end
  L.scrcmd_741 = L.scrcmd_741 or function(ins, s)
    local a = ins.args
    emit(s, { "g4_hgss_aprijuice_label", a[1], a[2], a[3], a[4] })
  end
  L.scrcmd_740 = L.scrcmd_740 or function(ins, s) emit(s, { "g4_hgss_aprijuice_drink", ins.args[1], ins.args[2] }) end
  L.scrcmd_743 = L.scrcmd_743 or function(ins, s) emit(s, { "g4_hgss_athlon_data", ins.args[1] }) end
end

return M
