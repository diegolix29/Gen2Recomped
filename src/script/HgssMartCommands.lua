-- src/script/HgssMartCommands.lua -- HEARTGOLD / SOULSILVER'S MartSell.
--
-- The clerk's script is std_mart (scr_seq_0003 _145E): MenuInitStdGmm with
-- BUY / SELL / SEE YA (msg_0191 321-323), then `MartBuy x8004` or `MartSell`,
-- then "Is there anything else I may do for you?" and the menu again.
-- MartSell (op 0x30E, scrcmd_mart.c ScrCmd_MartSell) is
-- Mart_Init(taskman, fieldSystem, {0xFFFF}, 0, isSell = 1, 0, 0): the Bag in
-- sell mode (bag BAG_MODE_SELL: "How many will you sell?", "I can pay $n.
-- Would that be OK?", "Turned over the ... and received $n.", bank 10 77-79).
--
-- It was unlowered, so the VM emitted g4_unimplemented and the script went
-- straight on to "Is there anything else..." -- SELL did nothing. Lowered
-- here onto the counter (src/ui/Gen4ShopMenu.lua, opts.sell), which opens the
-- Bag in pick mode and asks the three questions with bank 10's lines.
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

function Commands.g4_hgss_mart_sell(ctx)
  local game = ctx.game
  if not game then return end
  local runner = ctx.runner
  local Screens = require("src.ui.Screens")
  Screens.push(game, "ShopMenu", {}, function()
    if runner then runner:resume() end
  end, nil, { sell = true })
  local top = game.stack and game.stack:top()
  if top and top.openBag and top.mode == "sell" then top:openBag() end
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_mart_sell = { foreground = true, blocking = true }

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.martsell = function(_, s) emit(s, { "g4_hgss_mart_sell" }) end
end

return M
