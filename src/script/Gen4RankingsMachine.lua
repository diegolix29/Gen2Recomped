-- PLATINUM'S RANKINGS MACHINES (Jubilife TV, M0016): StartRankingsMachine
-- <machine> -> RankingsMachine_InitFieldTask (pokeplatinum
-- src/rankings_machine.c, src/rankings.c).
--
-- A machine shows one category (machine % 3): the Battle Tower's six
-- records, four Pokemon records, or three Contest ones. "Which record would
-- you like to see?" (bank 532 #22) over a list of the titles (#0-12) and
-- EXIT (#13); a record shows its explanation (#23-35) and the ranking:
-- "{n}. {name}" (#14) with the value line of sRecordsPrintingData (#15-21).
--
-- THE RANKING IS THE PLAYER'S OWN ENTRY ALONE: the other entries are players
-- met through record mixing (SaveData_GetRankingEntries), which this port
-- has no way to meet -- so the list also has no DEL RECORD, whose only use
-- is deleting those.
--
-- The values (GetRecordValues): the Battle Tower record streaks are frontier
-- stats 0 / 2 / 4 / 6 / 8 (STAT_TOWER_RECORD_STREAK_*), the average streak
-- is victories / challenges; then records FAINTED_IN_BATTLE, CAUGHT_POKEMON,
-- EGGS_HATCHED, CAUGHT_FISH; contest wins are official + link wins, the win
-- percentage those wins x 100 / (super + link participations), ribbons
-- RIBBONS_WON.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

M.BANK = 532
M.CATEGORIES = {
  -- { title entry, explanation entry, value entry, value (save) }
  [0] = {
    { 0, 23, 15, "stat", 0 }, { 1, 24, 15, "stat", 2 }, { 2, 25, 15, "stat", 4 },
    { 3, 26, 15, "stat", 6 }, { 4, 27, 15, "stat", 8 }, { 5, 28, 16, "average" },
  },
  [1] = {
    { 6, 29, 19, "record", 41 }, { 7, 30, 19, "record", 9 },
    { 8, 31, 18, "record", 11 }, { 9, 32, 19, "record", 10 },
  },
  [2] = {
    { 10, 33, 21, "contestWins" }, { 11, 34, 20, "contestPercent" }, { 12, 35, 17, "record", 94 },
  },
}
M.LIMITS = { [15] = 9999, [16] = 7, [17] = 65535, [18] = 999999, [19] = 999999, [20] = 100, [21] = 9999 }

function M.value(save, row)
  local R = require("src.pokemon.Gen4GameRecords")
  local kind = row[4]
  if kind == "stat" then
    local okB, BT = pcall(require, "src.pokemon.Gen4BattleTower")
    local r = okB and BT.record and BT.record(save)
    return r and BT.stat(r, row[5]) or 0
  elseif kind == "average" then
    local challenges = R.get(save, R.ID.BATTLE_TOWER_CHALLENGES)
    return challenges > 0 and math.floor(R.get(save, R.ID.BATTLE_TOWER_VICTORIES) / challenges) or 0
  elseif kind == "contestWins" then
    return R.get(save, 92) + R.get(save, 93)
  elseif kind == "contestPercent" then
    local entries = R.get(save, 90) + R.get(save, 91)
    return entries > 0 and math.floor((R.get(save, 92) + R.get(save, 93)) * 100 / entries) or 0
  end
  return R.get(save, row[5])
end

local function line(game, n, ...)
  local T = require("src.import.Gen4Text")
  T.buffer(game, ...)
  return T.resolve(game.data, M.BANK, n, game) or ""
end

function Commands.g4_rankings_machine(ctx, machine)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local G4 = require("src.script.Gen4Commands")
  local id = math.floor(tonumber(G4.valueOf(ctx, machine)) or 0)
  local rows = M.CATEGORIES[id % 3]
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  local done
  local function finish()
    if done then return end
    done = true
    if runner then runner:resume() end
  end
  local open
  -- a record: its explanation, then "1. NAME" and the value
  local function show(row)
    local save = ctx.save or {}
    local name = (save.player and save.player.name) or ""
    local value = math.min(M.value(save, row), M.LIMITS[row[3]] or 999999)
    local entry = line(game, 14, "1", name)
    local amount = line(game, row[3], tostring(value))
    local explain = line(game, row[2])
    game.stack:push(TextBox.new(game, explain .. "\f" .. entry .. "   " .. amount, open))
  end
  -- "Which record...?" stays up under the list (TextBox stay.onShown, the
  -- list pushed over it); Menu pops itself before a choice runs, so each
  -- choice takes the box down with it
  open = function()
    local box
    local function close() if box and game.stack:top() == box then game.stack:pop() end end
    local items = {}
    for _, row in ipairs(rows) do
      items[#items + 1] = { label = line(game, row[1]), onSelect = function() close(); show(row) end }
    end
    items[#items + 1] = { label = line(game, 13), onSelect = function() close(); finish() end }
    box = TextBox.new(game, line(game, 22), nil, { stay = { onShown = function()
      game.stack:push(Menu.new(game, items, {
        cancelable = true,
        onCancel = function() close(); finish() end,
      }))
    end } })
    game.stack:push(box)
  end
  open()
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_rankings_machine = { foreground = true, blocking = true }

-- THE SHARD TUTORS' COST WINDOW (src/ui/Gen4ShardCostWindow.lua), here
-- beside the other Platinum field windows this module adds:
-- ShowShardCost <x, y, move, dest> -- dest is the field menu's option pointer,
-- which the cost window never writes -- and CloseShardCostWindow
function Commands.g4_shard_cost_window(ctx, x, y, move)
  local ow = ctx.overworld
  if not (ow and ctx.game) then return end
  local G4 = require("src.script.Gen4Commands")
  ow.gen4ShardCostWindow = require("src.ui.Gen4ShardCostWindow").panelFor(ctx.game, x, y,
    math.floor(tonumber(G4.valueOf(ctx, move)) or 0))
end
function Commands.g4_shard_cost_close(ctx)
  if ctx.overworld then ctx.overworld.gen4ShardCostWindow = nil end
end

function M.install(L)
  L.showshardcost = L.showshardcost or function(ins, s)
    s.out[#s.out + 1] = { "g4_shard_cost_window", ins.args[1], ins.args[2], ins.args[3] }
  end
  L.closeshardcostwindow = L.closeshardcostwindow or function(_, s)
    s.out[#s.out + 1] = { "g4_shard_cost_close" }
  end
  L.startrankingsmachine = L.startrankingsmachine or function(ins, s)
    s.out[#s.out + 1] = { "g4_rankings_machine", ins.args[1] }
  end
end

return M
