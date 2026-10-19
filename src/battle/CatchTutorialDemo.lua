-- src/battle/CatchTutorialDemo.lua
--
-- THE DS CATCHING DEMONSTRATIONS' OWN PIECES, for the Gen 4 / Gen 5 commands
-- that build them (Gen4Commands g4_hgss_catching_tutorial,
-- g4_bw_catching_tutorial) and the shared demo flow in BattleState.
--
-- Reported from play: "hgss and black and whites catching tutorials are using
-- the old man and missing the pokeball catching animations showing the old man
-- placeholder back sprite as well".
--
-- WHO STANDS IN THE PLAYER'S PLACE
--
--   HeartGold / SoulSilver  Lyra (a boy's game) or Ethan (a girl's): the two
--                           player forms, which `counterpartBack` already
--                           picks out of field.playerForms by the demo save's
--                           gender (trainer_back 000 / 001).
--   Black / White           Professor Juniper with her Minccino, in both
--                           versions -- the Route 1 routine Gen4Commands reads
--                           its numbers from.  She is no player form: her back
--                           is picture 2 of /a/0/7/3 (trbgra: 0 Hilbert,
--                           1 Hilda, 2 Juniper, 3 Cheren, 4/5 the players'
--                           alternates), which Gen5TrainerPics writes to
--                           `gen4_trainer_sprites.backs`.  Without it the demo
--                           fell through to `playerPics.demoBack`, Gen 1's OLD
--                           MAN, a file a DS cache does not even carry.
--
-- THE BAG
--
-- Neither DS demonstration opens a bag on the TOP screen: the controller picks
-- BAG, the ball pocket and the ball on the touch screen while the battle stays
-- up top.  The engine's scripted tutorial bag (Gen4BagMenu, Platinum's field
-- bag) has no art on these caches and drew an empty white window over the
-- battle, so here the beat is kept -- the same 88 frames -- with the battle
-- left on screen, and the throw follows.

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")

local M = {}

M.BW_JUNIPER_BACK = 2
M.BAG_FRAMES = 88

-- the ROM back pic for Juniper, or nil on a cache without trainer backs
function M.bwThrowerBack(data)
  local sprites = data and data.gen4_trainer_sprites
  local backs = type(sprites) == "table" and sprites.backs or nil
  local row = type(backs) == "table" and backs[M.BW_JUNIPER_BACK] or nil
  return type(row) == "table" and row.path or nil
end

-- true on the DS demonstrations whose bag is a touch-screen beat
function M.touchScreenBag()
  local okF, family = pcall(GameVersion.family)
  if okF and family == "hgss" then return true end
  local ok5, gen5 = pcall(GameVersion.isGen5)
  return ok5 and gen5 and true or false
end

-- THE TEXT is the battle bank's, not the Game Boy's "OLD MAN used POKe BALL!"
-- and "All right! ... was caught!":
--   HeartGold  bank 197 857 "{name} used\none {item}!", 867 "Gotcha!\n{mon}
--              was caught!"
--   Black      bank 15 65 "Gotcha!\n{mon} was caught!".  Its throw line is 35
--              "{class} {name}\nused one {item}!", and Juniper has no class
--              string of her own to put in it, so the throw keeps the
--              HeartGold line's shape with her name alone.
M.HGSS_USED, M.HGSS_GOTCHA = "TEXT_B0197_00857", "TEXT_B0197_00867"
M.BW_GOTCHA = "TEXT_G5S_0015_00065"

-- the control codes a text box would act on ({WAIT n}, the \v page marker)
-- are dropped: the battle's own `say` paces its lines
local function clean(s)
  return (tostring(s):gsub("{WAIT %d+}", ""):gsub("\011", ""))
end

local function ballName(battle)
  local ok, def = pcall(battle.itemDef, battle, 4)
  local name = ok and type(def) == "table" and def.name or nil
  return (type(name) == "string" and name ~= "") and name or "Poké Ball"
end

function M.isDsDemo(battle)
  return battle and battle.dudeDemo and M.touchScreenBag() or false
end

function M.throwText(battle)
  if not M.isDsDemo(battle) then return nil end
  local text = battle.data and battle.data.text or {}
  local name, item = battle.demoName or "", ballName(battle)
  local hg = text[M.HGSS_USED]
  if type(hg) == "string" then
    return clean(hg:gsub("{STRVAR_1 3 0 0}", function() return name end)
                   :gsub("{STRVAR_1 8 1 0}", function() return item end))
  end
  return Strings("%s used\none %s!", name, item)
end

function M.caughtText(battle)
  if not M.isDsDemo(battle) then return nil end
  local text = battle.data and battle.data.text or {}
  local mon = battle.enemy and battle.enemy.name or ""
  local hg, bw = text[M.HGSS_GOTCHA], text[M.BW_GOTCHA]
  if type(hg) == "string" then
    return clean(hg:gsub("{STRVAR_1 1 0 0}", function() return mon end))
  end
  if type(bw) == "string" then
    return clean(bw:gsub("{VAR1}", function() return mon end))
  end
  return nil
end

-- runBag(battle, throw) -> true when it took the bag beat: hold the frames
-- the scripted bag would have been up, then throw
function M.runBag(battle, throw)
  if not M.touchScreenBag() then return false end
  battle.phase, battle.afterQueue = "messages", "menu"
  table.insert(battle.queue, { wait = M.BAG_FRAMES })
  battle:act(throw)
  return true
end

return M
