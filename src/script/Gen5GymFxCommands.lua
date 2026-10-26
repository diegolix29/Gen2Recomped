-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S GYM ANIMATION COMMANDS (src/world/Gen5GymFx.lua draws
-- them). Gen5ScriptLink names these `bwgymop` with their one operand; the
-- handlers (ov10's table at +0x1B4CC, READ FROM CODE) hand the operand to
-- the loaded gym overlay, which starts a task and -- for 0x185 / 0x187 /
-- 0x188 / 0x189 -- parks the script on it (0x215897C) until it ends:
--   0x185 <n>       Nacrene's bookcase (ov40 0x21F37EC)
--   0x187 <switch>  Striaton's switch down (ov42 0x21F3834, mode 1)
--   0x189 <switch>  ...and back up (the same, mode 0)
--   0x188 <row>     Striaton's curtain (ov42 0x21F3888)
-- Nothing else changes: the scripts' own vars and movements carry the gyms'
-- rules as before.

local okCommands, Commands = pcall(require, "src.script.Commands")

local M = {}

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwgymop = L.bwgymop or function(ins, s) emit(s, { "g5_gym_fx_op", ins.op, ins.args[1] }) end
  -- Driftveil's 0x190 <lift>: the lift is drawn moving (Gen5GymFx) and the
  -- script waits for it; the rule (Gen5DriftveilGym.move) runs unchanged as
  -- it arrives
  pcall(require, "src.script.Gen4Commands")
  local move = okCommands and Commands and Commands.g4_bw_lift_move
  if move and not M.wrappedLift then
    M.wrappedLift = true
    Commands.g4_bw_lift_move = function(ctx, n, ...)
      local frames = 0
      local ow = ctx and ctx.overworld
      if ow then
        local okV, G4 = pcall(require, "src.script.Gen4Commands")
        local v = math.floor((okV and G4.valueOf and G4.valueOf(ctx, n)) or tonumber(n) or 0)
        local okF, f = pcall(require("src.world.Gen5GymFx").liftMoving, ow, ctx.save, v)
        if okF then frames = f or 0 end
      end
      -- the ride first, then the rule's level change, as the lift arrives
      if frames > 0 and ctx and ctx.runner and ctx.runner.yield then
        Commands.wait(ctx, frames * require("src.world.Gen5GymFx").TICKS_PER_FRAME)
      end
      move(ctx, n, ...)
      if ow then pcall(require("src.world.Gen5GymFx").liftLanded, ow) end
    end
  end
end

if okCommands and Commands then
  function Commands.g5_gym_fx_op(ctx, op, n)
    local value = n
    local okV, G4 = pcall(require, "src.script.Gen4Commands")
    if okV and G4 and G4.valueOf then value = G4.valueOf(ctx, n) end
    local frames = require("src.world.Gen5GymFx").op(ctx, tonumber(op), value)
    -- the script waits the task out, a field frame being two ticks
    if frames and frames > 0 and ctx and ctx.runner and ctx.runner.yield then
      Commands.wait(ctx, frames * require("src.world.Gen5GymFx").TICKS_PER_FRAME)
    end
  end
  Commands.meta = Commands.meta or {}
  Commands.meta.g5_gym_fx_op = { blocking = true }
end

return M
