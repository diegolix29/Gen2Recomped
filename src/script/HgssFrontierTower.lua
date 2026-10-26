-- HEARTGOLD / SOULSILVER'S BATTLE TOWER BATTLE ROOM, run as the cartridge
-- runs it: in the Battle Frontier's own script engine.
--
-- Platinum's tower battles happen on a field map (Diamond and Pearl's battle
-- room, its script left in -- src/script/Gen4BattleTowerCommands.lua). HGSS
-- has no such map: the elevator's ScrCmd_627 5 launches the frontier scene
-- (overlay 80), whose scripts in /a/1/8/2 -- the corridor (member 6) and the
-- battle room (member 8), Platinum's members and byte code -- pick the
-- opponents, battle, heal, offer Rest / Retire, pay the BP, then exit back
-- to the elevator's field script, which warps to the lobby.
--
-- The tower commands of those scripts, over the field ones' implementation:
--
--   callbattletowerfunction <fn> <arg> <dest>   g4_bt_call (the same enum;
--       the room's script prints its own BP line, so no g4_bt_reward here)
--   battletower_startbattle / _checkwonbattle   g4_bt_battle / the result
--   85 <n>                                      the opponent's intro line
--   freetowerstruct                             g4_bt_free
--   72 <unused>                                 SaveData_Save
--   32 / 33                                     a scene graphics task and
--                                               its wait: nothing to draw

local VM = require("src.script.Gen4FrontierVM")
local Commands = require("src.script.Commands")
local Fr = require("src.script.Gen4FrontierScrCmds")

local F = VM.facility
local emit = VM.emit

F.callbattletowerfunction = function(ins, s)
  emit(s, { "g4_bt_call", ins.args[1], ins.args[2], ins.args[3] })
end
F.battletower_startbattle = function(_, s) emit(s, { "g4_bt_battle" }) end
F.battletower_checkwonbattle = function(ins, s) emit(s, { "fr_bt_won", ins.args[1] }) end
F["85"] = function(ins, s) emit(s, { "g4_bt_intro", ins.args[1] }) end
F.freetowerstruct = function(_, s) emit(s, { "g4_bt_free" }) end
F["72"] = function(_, s) emit(s, { "fr_save" }) end
F["32"] = function() end
F["33"] = function() end
F.bufferrivalname = function(ins, s) emit(s, { "g4_buffer", ins.args[1], "rival" }) end

-- BattleTower_CheckWonBattle: 1 on a win
function Commands.fr_bt_won(ctx, dest)
  Fr.store(ctx, dest, ctx.lastBattleResult == "win" and 1 or 0)
end

return {}
