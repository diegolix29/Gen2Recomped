-- src/script/Gen5TradeCommands.lua -- BLACK AND WHITE'S NPC TRADES, RUN.
--
-- Five houses trade (src/import/Gen5Trades.lua has the table): Nacrene City
-- (Petilil / Cottonee), Driftveil City (Basculin), Route 7 (Emolga), Undella
-- Town (Munchlax) and Route 15 (Rotom). Each script is the same shape:
--
--   bufferspeciesname 0 <asked for>, 1 <offered>; message "Do you have a...";
--   yes/no; 0x107 (the party menu for a trade, Gen5ScriptLink.rewriteCompound);
--   0x1BF <dest, trade, slot>   -> "I'd like to trade for a {VAR1}..." unless 0
--   message "Then, let's trade!"; [0x120 <slot, index>]; 0x1BE <trade, slot>;
--   message "Please take good care of my {VAR2}!"; setflag; var = done
--
-- 0x1BE is the field task at ov21 0x021CC390: state 0 builds their Pokemon
-- (0x021CC098, every field of the record), 1 runs the trade demo (overlay
-- 119, src/ui/Gen5TradeSequence.lua here), 2 puts theirs into YOUR SLOT
-- (0x0201AB48, the party's replace-at-index) and fills the dex, 3 asks for a
-- trade evolution of what arrived. The swap below happens first and the demo
-- plays over it -- the script waits for both, as the cartridge's does.
--
-- Loaded by Gen4ScriptVM (its last lines call `install` with the lowering
-- table), so the three BW names lower wherever map scripts compile.

-- (a tool that compiles scripts without LOVE may not load Commands; the
-- lowering below does not need it)
local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return G4().valueOf(ctx, n) end
local function store(ctx, dest, value)
  dest = tonumber(dest)
  if dest and dest >= 0x4000 then G4().setVar(ctx.save, dest, math.floor(tonumber(value) or 0) % 65536) end
end

function M.rows(data)
  local list = data and data.constants and data.constants.gen5Trades
  return type(list) == "table" and list or nil
end

function M.row(data, id)
  local list = M.rows(data)
  local row = list and list[(tonumber(id) or -1) + 1]
  return type(row) == "table" and row or nil
end

local function isEgg(mon)
  if type(mon) ~= "table" then return false end
  local ok, Party = pcall(require, "src.pokemon.Party")
  if ok and Party.isEgg then return Party.isEgg(mon) and true or false end
  return mon.isEgg and true or false
end

-- 0 male, 1 female, 2 genderless -- the numbering 0x1BF compares (param 0x6E)
function M.genderCode(data, mon)
  local g = require("src.pokemon.Pokemon").genderOf(data, mon)
  if g == "female" then return 1 elseif g == "male" then return 0 end
  return 2
end

-- 0x1BF's answer for the record and the offered Pokemon (ov21 0x021B647C):
-- an Egg first, then the species, then the gender when the record names one
function M.check(data, row, mon)
  if not (row and mon) then return 2 end
  if isEgg(mon) then return 1 end
  if tonumber(mon.species) ~= tonumber(row.request) then return 2 end
  local want = tonumber(row.requestGender) or 2
  if want ~= 2 and M.genderCode(data, mon) ~= want then return 3 end
  return 0
end

-- ov21 0x021CC098: their Pokemon, field for field
function M.build(data, row)
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local mon = Pokemon.new(data, row.species, tonumber(row.level) or 5)
  if (tonumber(row.form) or 0) ~= 0 then mon.form = row.form end
  mon.nickname = row.nickname
  mon.ot, mon.otId, mon.otGender = row.otName, row.otId, row.otGender
  mon.traded = true
  mon.language = row.language
  if row.item and row.item ~= 0 then mon.item = row.item end
  mon.ivs = mon.ivs or {}
  for i, key in ipairs(Stats.ORDER_GEN3) do
    if row.ivs and row.ivs[i] then mon.ivs[key] = row.ivs[i] end
  end
  local def = data.pokemon and data.pokemon[row.species]
  mon.personality = require("src.import.Gen5Trades").pid(row.otId, def and def.genderRatio, row.gender)
  -- Gen 5 keeps the nature apart from the PID (param 0x70), and the ability
  -- by the record's slot (0x021CC17C: personal +0x18/+0x19/+0x1A)
  local order = data.constants and data.constants.natureOrder
  if order and row.nature then mon.nature = order[row.nature + 1] or mon.nature end
  mon.abilitySlot = (tonumber(row.abilitySlot) or 0) + 1
  mon.shiny = false
  local okS, stats = pcall(Stats.calc, require("src.pokemon.Gen4Forms").definition(data, mon) or def,
                           mon.level, mon.ivs, nil, mon.evs, mon.nature)
  if okS and type(stats) == "table" then mon.stats, mon.hp = stats, stats.hp end
  return mon
end

-- 0x1BF <dest, trade, slot>
function Commands.g5_trade_check(ctx, dest, trade, slot)
  local data = ctx.game and ctx.game.data
  local row = M.row(data, valueOf(ctx, trade))
  local party = (ctx.save or {}).party or {}
  local mon = party[(valueOf(ctx, slot) or 0) + 1]
  if not row then
    Logger.warn("bw trade: no record %s (constants.gen5Trades is written by the constants stage)",
                tostring(valueOf(ctx, trade)))
  end
  store(ctx, dest, M.check(data, row, mon))
end

-- 0x120 <slot, index>: the Pokemon about to leave, copied into the save --
-- what the NPC later battles with ("The {VAR1} that I got from you has grown
-- up", script op 0x094, not ported)
function Commands.g5_trade_keep(ctx, slot, index)
  local save = ctx.save
  local mon = save and save.party and save.party[(valueOf(ctx, slot) or 0) + 1]
  if not mon then return end
  local copy = {}
  for k, v in pairs(mon) do copy[k] = v end
  save.gen5TradedAway = save.gen5TradedAway or {}
  save.gen5TradedAway[(valueOf(ctx, index) or 0) + 1] = copy
end

-- 0x1BE <trade, slot>
function Commands.g5_trade_start(ctx, trade, slotArg)
  local data = ctx.game and ctx.game.data
  local id = valueOf(ctx, trade)
  local row = M.row(data, id)
  local slot = (valueOf(ctx, slotArg) or 0) + 1
  local party = (ctx.save or {}).party or {}
  local given = party[slot]
  if not (row and given and data) then
    Logger.warn("bw trade: nothing to swap -- trade %s, slot %d", tostring(id), slot)
    return
  end
  local ok, mon = pcall(M.build, data, row)
  if not (ok and type(mon) == "table") then
    Logger.warn("bw trade: could not build trade %s: %s", tostring(id), tostring(mon))
    return
  end
  -- the received Pokemon takes the given one's SLOT (0x0201AB48)
  party[slot] = mon
  local save = ctx.save
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.owned = save.pokedex.owned or {}
  save.pokedex.seen[mon.species], save.pokedex.owned[mon.species] = true, true
  ctx.g4PartySlot = nil
  M.last = { trade = id, slot = slot, given = given, received = mon }

  local runner, game = ctx.runner, ctx.game
  if game and game.stack and data.gen5_trade_art then
    local okS, err = pcall(function()
      require("src.ui.Screens").push(game, "Gen5TradeSequence", {
        sending = given, receiving = mon, otName = row.otName,
        onDone = function() if runner then runner:resume() end end,
      })
    end)
    if okS then
      if runner then runner:yield() end
    else
      Logger.warn("bw trade: the trade demo would not start: %s", tostring(err))
    end
  end
end

Commands.meta = Commands.meta or {}
Commands.meta.g5_trade_start = { foreground = true, blocking = true }

function M.install(L)
  L.bwnpctradecheck = function(ins, s)
    s.out[#s.out + 1] = { "g5_trade_check", ins.args[1], ins.args[2], ins.args[3] }
  end
  L.bwnpctrade = function(ins, s)
    s.out[#s.out + 1] = { "g5_trade_start", ins.args[1], ins.args[2] }
  end
  L.bwkeeptradedmon = function(ins, s)
    s.out[#s.out + 1] = { "g5_trade_keep", ins.args[1], ins.args[2] }
  end
end

return M
