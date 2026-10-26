-- THE POKE TRANSFER LAB'S COMMANDS (Black / White, Route 15's lab, Z381;
-- src/world/Gen5PokeTransfer.lua has the transfer itself).
--
-- The lab worker's script (M0878, band bw_10290) asks 0x13B whether wireless
-- is on (Gen5BattleSubway's g5_subway_wireless answers yes here), then runs 0x1C0 -- the transfer -- and 0x1C1, which leaves the
-- outcome where the script reads it: 0x8024 (0 / 1 caught some and the score
-- in 0x4000 ranks them -- 400 / 550 / 700 / 800 / 900 -- 2 caught none, 3 a
-- communication error, 4 cancelled).

local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")

local function T() return require("src.world.Gen5PokeTransfer") end

-- 0x1C0: the transfer, start to finish (blocking)
function Commands.g4_bw_poke_transfer(ctx)
  local runner = ctx.runner
  local started = T().run(ctx.game or package.loaded["src.core.Game"], ctx.overworld, function()
    if runner then runner:resume() end
  end)
  if started and runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_poke_transfer = { foreground = true, blocking = true }

-- 0x1C1: the outcome, into the vars the script reads
function Commands.g4_bw_poke_transfer_result(ctx)
  local status, score = T().result(ctx.save)
  Gen4Commands.setVar(ctx.save, 0x8024, status)
  Gen4Commands.setVar(ctx.save, 0x4000, score)
end

return Commands
