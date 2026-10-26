-- PLATINUM'S SCRATCH-OFF CARDS, the script side (pokeplatinum scrcmd.c):
--
--   OpenScratchOffCardsApp            the app (src/ui/Gen4ScratchOffCards.lua),
--                                     the script paused until it exits
--   GetScratchOffCardsWonItem i, item, count
--                                     card i's prize: wonItems[i] /
--                                     wonItemsCount[i] (0 / 0 for a loss)
--   FreeScratchOffCardsArgs           the results let go
--
-- The results live on the game between the three (the cartridge keeps them
-- in SCRIPT_MANAGER_PARTY_MANAGEMENT_DATA). A cache without the app's art
-- (an import from before platinum-scratch-off-v1) gets three empty cards.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end

function Commands.g4_scratch_off_open(ctx)
  local game = ctx.game
  if not game then return end
  game.scratchOffResults = { { 0, 0 }, { 0, 0 }, { 0, 0 } }
  local Cards = require("src.ui.Gen4ScratchOffCards")
  if not (game.stack and Cards.available(game)) then
    require("src.core.Logger").warn("scratch-off: no gen4_scratch_off_art in this cache (re-import)")
    return
  end
  local runner = ctx.runner
  game.stack:push(Cards.new(game, function(won)
    game.scratchOffResults = won
    if runner then runner:resume() end
  end))
  if runner then runner:yield() end
end
if Commands.meta then Commands.meta.g4_scratch_off_open = { foreground = true, blocking = true } end

function Commands.g4_scratch_off_won(ctx, index, itemVar, countVar)
  local g = G4()
  local i = math.floor(tonumber(g.valueOf(ctx, index)) or 0)
  local won = ((ctx.game or {}).scratchOffResults or {})[i + 1] or { 0, 0 }
  g.setVar(ctx.save, itemVar, won[1] or 0)
  g.setVar(ctx.save, countVar, won[2] or 0)
end

function Commands.g4_scratch_off_free(ctx)
  if ctx.game then ctx.game.scratchOffResults = nil end
end

function M.install(L)
  L.openscratchoffcardsapp = L.openscratchoffcardsapp or function(_, s)
    s.out[#s.out + 1] = { "g4_scratch_off_open" }
  end
  L.getscratchoffcardswonitem = L.getscratchoffcardswonitem or function(ins, s)
    s.out[#s.out + 1] = { "g4_scratch_off_won", ins.args[1], ins.args[2], ins.args[3] }
  end
  L.freescratchoffcardsargs = L.freescratchoffcardsargs or function(_, s)
    s.out[#s.out + 1] = { "g4_scratch_off_free" }
  end
  -- HGSS's names for the same three (ScratchOffCard / GetScratchOffPrize /
  -- ScratchOffCardEnd; the app is Platinum's, its narc /a/2/0/5)
  L.scratchoffcard = L.scratchoffcard or L.openscratchoffcardsapp
  L.getscratchoffprize = L.getscratchoffprize or L.getscratchoffcardswonitem
  L.scratchoffcardend = L.scratchoffcardend or L.freescratchoffcardsargs
end

return M
