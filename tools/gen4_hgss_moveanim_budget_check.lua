-- Run:  python tools/run_lua_check.py tools/gen4_hgss_moveanim_budget_check.lua [<install>]
--
-- NO MOVE ANIMATION CAN HOLD A HEARTGOLD BATTLE. The installed HGSS cache's
-- programs, run through Gen4MoveAnimPlayer from both sides, must all END --
-- inside the player's own FRAME_BUDGET, with neither the frame nor the step
-- budget having to stop them -- and in particular:
--   * Pidgey's three moves (Gust 16, Sand-Attack 28, Tackle 33) and the
--     starters' (Scratch 10, Leer 43, Growl 45, SmokeScreen 108, Ember 52,
--     Razor Leaf 75, PoisonPowder 77, Water Gun 55, Rage 99)
--   * the five programs that use HGSS's own opcodes 85-87 (192 Zap Cannon,
--     224 Megahorn, 226 Baton Pass, 231 Iron Tail, 276 Superpower)
-- BattleState holds the queue for exactly `duration`, so a program that ends
-- is a battle that moves on.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or { math = { random = math.random } }

local install = (arg and arg[1]) or "G:/Gen2Recomped/heartgold"
local dir = install .. "/data/generated/"
local function load(name)
  local ok, t = pcall(dofile, dir .. name .. ".lua")
  return ok and t or nil
end
local anims = load("gen4_move_anims")
if not anims then print("skip: no gen4_move_anims at " .. dir) return end
local data = { gen4_move_anims = anims, gen4_particles = load("gen4_particles"),
               gen4_cellactors = load("gen4_cellactors") }
require("src.core.GameVersion").set("heartgold")
local Play = require("src.battle.Gen4MoveAnimPlayer")
local player = assert(Play.new(data), "the player builds from the HGSS cache")

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print("FAIL: " .. label) end
end

local named = { 16, 28, 33, 10, 43, 45, 108, 52, 75, 77, 55, 99, 192, 224, 226, 231, 276 }
local function run(id, side)
  if not player:start(id, side) then return nil end
  local frames = 0
  while player:update() do
    frames = frames + 1
    if frames > Play.Player.FRAME_BUDGET + 30 then return frames, "ran past the budget" end
  end
  local u = player.unsupported or {}
  if u["frame budget"] or u["frame budget in the tail"] or u["step budget"] then
    return frames, "stopped by a budget"
  end
  return frames
end
for _, id in ipairs(named) do
  for _, side in ipairs({ true, false }) do
    local frames, why = run(id, side)
    check(frames ~= nil and why == nil, ("move %d (%s) plays and ends: %s frames %s"):format(
      id, side and "player" or "foe", tostring(frames), why or ""))
    local d = player:duration(id, side)
    check(d and d > 0 and d <= Play.Player.FRAME_BUDGET + 1,
      ("move %d's duration %s is the queue's hold and is bounded"):format(id, tostring(d)))
  end
end
-- and the whole corpus: nothing runs past the budget
local over, started = {}, 0
for id = 1, (anims.count or 501) - 1 do
  if anims.programs[id] then
    for _, side in ipairs({ true, false }) do
      local frames, why = run(id, side)
      if frames then started = started + 1 end
      if why == "ran past the budget" then over[#over + 1] = id end
    end
  end
end
check(#over == 0, ("no program runs past the frame budget (%d runs; over: %s)"):format(started, table.concat(over, ",")))
print(("%d passed, %d failed"):format(PASS, FAIL))
if FAIL > 0 then error("gen4_hgss_moveanim_budget_check failed") end
