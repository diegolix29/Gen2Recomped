-- HEARTGOLD / SOULSILVER'S POKeATHLON DOME, the script side (pokeheartgold
-- scrcmd_c.c ScrCmd_Pokeathlon -> sub_02095DF4, field/scrcmd_pokemon_misc.c
-- ScrCmd_BufferPokeathlonCourseName):
--
--   Pokeathlon <b1, b2> course, quit, score, points, bonus
--                       the course app (src/ui/HgssPokeathlonCourse.lua), the
--                       script held until it ends; then its four answers --
--                       quit (args byte 0xE), score (u16 0xA), Athlete Points
--                       (u16 8), the win bonus (byte 0xD) -- into the vars
--   BufferPokeathlonCourseName <slot> course
--                       bank 313's course name (0-4 single, 5-9 link, 10 Master)
--   CreatePokeathlonFriendshipRoomStatues (744)
--                       the Friendship room's (D49R0107) three statues, the
--                       last won course's team (src/world/HgssFriendshipStatues.lua)
--   ScrCmd_712 <app>    the side rooms' screens (overlay 99): 0 course records
--                       (src/ui/HgssPokeathlonCourseRecord.lua), 1 the Medals
--                       list (HgssPokeathlonMedalList.lua), 2 event records
--                       (HgssPokeathlonEventRecord.lua), 3 the trophies behind
--                       "It's your statue!" (HgssPokeathlonTrophies.lua)

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end

function Commands.g4_hgss_pokeathlon(ctx, b1, b2, course, quitVar, scoreVar, pointsVar, bonusVar)
  local game = ctx.game
  if not (game and game.stack) then return end
  local g = G4()
  local runner = ctx.runner
  local function answer(r)
    g.setVar(ctx.save, quitVar, r.quit and 1 or 0)
    g.setVar(ctx.save, scoreVar, r.score or 0)
    g.setVar(ctx.save, pointsVar, r.points or 0)
    g.setVar(ctx.save, bonusVar, r.bonus or 0)
    if runner then runner:resume() end
  end
  local id = math.floor(tonumber(g.valueOf(ctx, course)) or 0)
  -- b1 = the args mode (link), b2 = the args byte 0xF, the Supreme Cup
  -- (literal bytes: ScriptReadByte, not vars)
  game.stack:push(require("src.ui.HgssPokeathlonCourse").new(game, {
    course = id, link = (tonumber(b1) or 0) ~= 0, supreme = (tonumber(b2) or 0) ~= 0, onDone = answer }))
  if runner then runner:yield() end
end
if Commands.meta then Commands.meta.g4_hgss_pokeathlon = { foreground = true, blocking = true } end

-- CreatePokeathlonFriendshipRoomStatues (744): the Friendship room's three
-- statues from the save (src/world/HgssFriendshipStatues.lua)
function Commands.g4_hgss_athlon_statues(ctx)
  if not ctx.overworld then return end
  require("src.world.HgssFriendshipStatues").create(ctx.game or require("src.core.Game"), ctx.overworld)
end

-- ScrCmd_712 <app> (scrcmd_c.c -> launch_application.c, all overlay 99): the
-- side rooms' screens, the script held until each closes
M.ROOM_APPS = { [0] = "src.ui.HgssPokeathlonCourseRecord", "src.ui.HgssPokeathlonMedalList",
  "src.ui.HgssPokeathlonEventRecord", "src.ui.HgssPokeathlonTrophies" }
function Commands.g4_hgss_athlon_room_app(ctx, app)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local n = math.floor(tonumber(G4().valueOf(ctx, app)) or 0)
  local App = require(M.ROOM_APPS[n] or M.ROOM_APPS[0])   -- default: case 0
  game.stack:push(App.new(game, function() if runner then runner:resume() end end))
  if runner then runner:yield() end
end
if Commands.meta then Commands.meta.g4_hgss_athlon_room_app = { foreground = true, blocking = true } end

function M.install(L)
  -- Gen4ScriptVM lowers ScrCmd_712 to a no-op first; this replaces it
  L.scrcmd_712 = function(ins, s)
    s.out[#s.out + 1] = { "g4_hgss_athlon_room_app", ins.args[1] }
  end
  L.pokeathlon = L.pokeathlon or function(ins, s)
    local a = ins.args
    s.out[#s.out + 1] = { "g4_hgss_pokeathlon", a[1], a[2], a[3], a[4], a[5], a[6], a[7] }
  end
  L.bufferpokeathloncoursename = L.bufferpokeathloncoursename or function(ins, s)
    s.out[#s.out + 1] = { "g4_buffer_bank_line", ins.args[1], 313, ins.args[2] }
  end
  L.createpokeathlonfriendshiproomstatues = L.createpokeathlonfriendshiproomstatues or function(_, s)
    s.out[#s.out + 1] = { "g4_hgss_athlon_statues" }
  end
end

return M
