-- src/script/Gen5XtransceiverCommands.lua -- BLACK / WHITE'S XTRANSCEIVER.
--
-- 0x155 <call>: the story call (ov10 0x0215CAB4 starts overlay 174 with the
-- call number). The scripts bracket it -- "The Xtransceiver is ringing." /
-- "{VAR1} picked up the Xtransceiver.", 0x1AE / 0x1B1 / 0x14B before and
-- 0x14A / 0x1AD / 0x1B1 after -- and the conversation itself is the app's,
-- so lowered to nothing every call was skipped: Juniper's on Route 1, Mom's
-- on Route 2 and Route 7, Bianca's, Cheren's. It is the screen in
-- src/ui/Gen5XtransceiverCall.lua now; the script waits for it.
--
-- Installed through Gen5MartCommands.install.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end

function Commands.g4_bw_xtcall(ctx, callArg)
  local game = ctx.game
  if not game then return end
  local call = tonumber(G4().valueOf(ctx, callArg)) or 0
  local Call = require("src.ui.Gen5XtransceiverCall")
  if not Call.available(game, call) then
    require("src.core.Logger").warn("bw xtransceiver: no call %d -- re-import the ROM", call)
    return
  end
  local runner = ctx.runner
  game.stack:push(Call.new(game, call, function() if runner then runner:resume() end end))
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_bw_xtcall = { foreground = true, blocking = true }

function M.install(L)
  L.bwxtcall = function(ins, s) s.out[#s.out + 1] = { "g4_bw_xtcall", ins.args[1] } end
end

return M
