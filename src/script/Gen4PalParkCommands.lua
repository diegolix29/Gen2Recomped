-- PAL PARK'S FOUR SCRIPT COMMANDS (src/world/Gen4PalPark.lua has the show).
--
--   Platinum (scrcmd_catching_show.c)   HeartGold / SoulSilver (scrcmd_12.c)
--   SetClearInCatchingShowFlag  0x253   PalParkAction   508
--   CheckHasEnoughMonForCatchingShow    ScrCmd_509
--   MoveCatchingShowMonsToPCBoxes       ScrCmd_510
--   CalcCatchingShowPoints      0x256   PalParkScoreGet 511
--
-- The one that differs is the first. Platinum: 0 sets the in-park flag and
-- starts the show, 1 clears it and ends it. HGSS: 2 sets the flag and clears
-- the catch order, 0 starts the show, 1 clears the flag and ends it.

local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")
local PalPark = require("src.world.Gen4PalPark")

local function game(ctx) return ctx.game or package.loaded["src.core.Game"] end

function Commands.g4_catching_show(ctx, mode, family)
  local g = game(ctx)
  local st = PalPark.store(ctx.save)
  mode = Gen4Commands.valueOf(ctx, mode)
  if family == "hgss" then
    if mode == 2 then st.inPark = true; PalPark.clearState(g)
    elseif mode == 0 then PalPark.start(g)
    elseif mode == 1 then st.inPark = nil; PalPark.finish(g) end
  else
    if mode == 0 then st.inPark = true; PalPark.start(g)
    elseif mode == 1 then st.inPark = nil; PalPark.finish(g) end
  end
end

function Commands.g4_catching_show_ready(ctx, destVar)
  local n = PalPark.count(ctx.save) == PalPark.MONS and 1 or 0
  if destVar then Gen4Commands.setVar(ctx.save, destVar, n) end
end

function Commands.g4_catching_show_box(ctx)
  PalPark.moveToBoxes(game(ctx))
end

function Commands.g4_catching_show_points(ctx, category, destVar)
  local n = PalPark.points(ctx.save, Gen4Commands.valueOf(ctx, category))
  if destVar then Gen4Commands.setVar(ctx.save, destVar, n) end
end

return Commands
