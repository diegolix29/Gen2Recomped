-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GEN 4 MOVE ANIMATION: THE LONG TAIL OF SCRIPT FUNCTIONS AND SPRITE CALLBACKS.
--
-- `Gen4MoveAnimPlayer` implements the shared machinery of pret's battle
-- animation system (the VM, shakes, fades, background switches, particles,
-- the 2D sprite layer) and the script functions most programs use. What it
-- did not have was the long tail: `sBattleAnimScriptFuncs` in pret's
-- src/battle_anim/script_func_tables.c holds 84 functions, and about fifty of
-- them belong to ONE move each -- Strength's red pulse, Double Team's
-- after-images, Surf's wave, Psychic's wobble. The coverage audit
-- (`tools/gen4_move_anim_audit.lua`) found 98 of Platinum's 467 moves calling
-- at least one of them, each of which played with that part missing.
--
-- This module is the registry those ports live in, plus the helpers they
-- share. The ports themselves are in the batch modules listed in `BATCHES`,
-- each a straight reading of the pret function it names.
--
-- THE CONTRACT WITH THE PLAYER (Gen4MoveAnimPlayer):
--   * `callFunc` copies the call's operands into `player.vars[0..9]` (signed)
--     and then asks `Extras.callFunc(player, id, args)`; a registered
--     function returns nothing and the call counts as handled.
--   * `addspritewithfunc` asks `Extras.SPRITES[funcId]` for a motion when the
--     player has none of its own: { name, count, start(ctx), step(ctx) } with
--     `step` returning false when the callback ends (same shape as the
--     player's SPRITE_MOTION table).
--   * A function that takes time starts a task through `H.task`; tasks are
--     what `waitforanimtasks` waits on.
--   * Per-side battler channels live on `player.state[isPlayerSide]`:
--       dx, dy        offset from the battler's rest position (DS pixels, +y down)
--       sx, sy        scale (1 = normal; the draw pivots on the picture's foot)
--       rot, rise     rotation in radians about the picture centre, and a lift
--       hidden        not drawn
--       tint          { r, g, b, a } wash over the picture (0-1)
--       alpha         0-1 translucency
--       mosaic        block size (1 = off)
--       brightness    0-1 multiplier (black fades)
--       white         0-1 towards white
--       ghosts        list of { dx, dy, alpha, sx, sy } copies drawn beneath
--   * `player.screenFlash = { r, g, b, a }` washes the whole field.
--   * `player.bgScroll = { x, y }` scrolls the effect background layer.
--   * `player:startPaletteFade(bgType, delay, from, to, colour)` is fadebg.
--   All of these are cleared when the program and its tail end.

local Gen4AnimMath = require("src.battle.Gen4AnimMath")

local Extras = {}
Extras.FUNCS = {}
Extras.SPRITES = {}

local floor, max, min = math.floor, math.max, math.min

-- ---------------------------------------------------------------------------
-- Helpers shared by every batch
-- ---------------------------------------------------------------------------

local H = {}
Extras.H = H

local TWO31, TWO32 = 2147483648, 4294967296
function H.signed(v)
  v = tonumber(v) or 0
  if v >= TWO31 then return v - TWO32 end
  return v
end
function H.hi16(v) return floor((tonumber(v) or 0) / 65536) % 65536 end
function H.lo16(v) return (tonumber(v) or 0) % 65536 end
-- signed 16-bit halves
function H.shi16(v) local x = H.hi16(H.signed(v) % TWO32); if x >= 32768 then x = x - 65536 end; return x end
function H.slo16(v) local x = H.lo16(H.signed(v) % TWO32); if x >= 32768 then x = x - 65536 end; return x end

-- `BattleAnimSystem_GetScriptVar(system, i)`.
function H.var(player, i)
  return H.signed((player.vars or {})[i] or 0)
end

-- Which side a role is on, as the `isPlayer` key of `player.state`.
function H.attacker(player) return player.attackerIsPlayer and true or false end
function H.defender(player) return not player.attackerIsPlayer end
function H.state(player, side) return player.state[side and true or false] end

-- `BattleAnimUtil_GetTransformDirectionX`: 1 on the player's side, -1 on the
-- enemy's.
function H.dirX(side) return side and 1 or -1 end
-- `..._GetTransformDirectionY`: -1 on the enemy side.
function H.dirY(side) return side and 1 or -1 end

-- The solo battler centres (BATTLER_POS_SOLO_*), DS pixels.
H.CENTRE = {
  [true] = { x = 64, y = 112 },
  [false] = { x = 192, y = 48 },
}
function H.centre(side)
  local c = H.CENTRE[side and true or false]
  return c.x, c.y
end

-- `BattleAnimSystem_GetBattlerSpriteOffset`: the species' y offset (rows of
-- empty frame under the Pokemon). Not known to this layer; 0 keeps every
-- anchored scale pivoting on the frame's foot, which is what the draw does.
function H.spriteOffset(player, side)
  local f = player.spriteOffsetFor
  if f then
    local ok, v = pcall(f, side)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return 0
end

-- BGR555 colour -> r, g, b (0-1)
function H.rgb(colour)
  colour = tonumber(colour) or 0
  return (colour % 32) / 31, (floor(colour / 32) % 32) / 31,
         (floor(colour / 1024) % 32) / 31
end
H.WHITE = 0x7FFF
H.BLACK = 0
H.RED = 0x001F

-- Start a task the program's `waitforanimtasks` waits on. `step(player, t)`
-- runs once a frame (from the frame AFTER the call, like a SysTask) and sets
-- `t.done = true` to end. `opts` is merged into the task.
function H.task(player, step, opts)
  local t = opts or {}
  t.kind = "fn"
  t.step = step
  t.state = t.state or 0
  return player:addTask(t)
end

-- A task that is NOT counted by waitforanimtasks (a plain SysTask).
function H.sysTask(player, step, opts)
  local t = H.task(player, step, opts)
  t.uncounted = true
  return t
end

-- ShakeContext, exactly (battle_anim_helpers.c): the counter starts AT the
-- interval so the first flip lands on the first update; a flip moves
-- prev -> cur -> -prev; `amount` counts cycles of four flips.
function H.shake(extentX, extentY, interval, amount)
  return {
    x = 0, y = 0,
    counter = interval or 0, interval = interval or 0,
    remaining = amount or 0, cycle = 0,
    prevX = -(extentX or 0), prevY = -(extentY or 0),
  }
end
local function flip(cur, prev)
  local prevVal = prev
  prev = cur
  if prevVal == 0 then cur = 0 else cur = -prevVal end
  return cur, prev
end
function H.shakeUpdate(c)
  if c.remaining and c.remaining ~= 0 then
    c.counter = c.counter + 1
    if c.counter >= c.interval then
      c.counter = 0
      c.x, c.prevX = flip(c.x, c.prevX)
      c.y, c.prevY = flip(c.y, c.prevY)
      c.cycle = c.cycle + 1
      if c.cycle >= 4 then
        c.cycle = 0
        c.remaining = c.remaining - 1
      end
    end
    return true
  end
  return false
end

-- ScaleLerpContext_InitXY / UpdateXY (the XY pair the shared math lacks).
function H.scaleXY(sx, ex, sy, ey, ref, steps)
  local R = Gen4AnimMath.relativeScale
  local x0, x1 = R(sx, ref), R(ex, ref)
  local y0, y1 = R(sy, ref), R(ey, ref)
  return {
    x = x0, y = y0, steps = steps or 0,
    stepX = Gen4AnimMath.stepSize(x0 * 4096, x1 * 4096, steps),
    stepY = Gen4AnimMath.stepSize(y0 * 4096, y1 * 4096, steps),
    curX = x0 * 4096, curY = y0 * 4096,
  }
end
function H.scaleXYUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.steps = c.steps - 1
    c.curX = c.curX + c.stepX
    c.curY = c.curY + c.stepY
    c.x = floor(c.curX / 4096)
    c.y = floor(c.curY / 4096)
    return true
  end
  return false
end

-- Affine scale value (256 = 1.0) -> multiplier.
function H.affine(v) return (v or 256) / 256 end

-- ValueLerpContext_InitSinusoidal / UpdateSinusoidal.
function H.sinLerp(startIdx, endIdx, amplitudeFx, steps)
  local stepSize = 0
  if steps and steps ~= 0 then
    local d = (endIdx or 0) - (startIdx or 0)
    stepSize = d >= 0 and floor(d / steps) or -floor(-d / steps)
  end
  return { value = 0, steps = steps or 0, angle = startIdx or 0,
           amplitude = amplitudeFx or 0, step = stepSize }
end
function H.sinLerpUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.angle = (c.angle + c.step) % 65536
    c.steps = c.steps - 1
    c.value = floor(Gen4AnimMath.fxMul(Gen4AnimMath.cosIdx(c.angle), c.amplitude) / 4096)
    return true
  end
  return false
end

-- An angle index (0x10000 per turn) -> radians.
function H.radians(idx) return Gen4AnimMath.radians(idx or 0) end
function H.degToIdx(deg) return Gen4AnimMath.degToIdx(deg) end

-- `PokemonSprite_StartFade(sprite, from, to, delay, colour)`: the battler's
-- own palette blended toward a colour, one step of 1/16 every `delay + 1`
-- frames. Returns a context the caller pumps with `H.monFadeUpdate`, which
-- writes the side's tint.
function H.monFade(player, side, from, to, delay, colour)
  local r, g, b = H.rgb(colour)
  local c = Gen4AnimMath.monFade(from, to, delay, r, g, b)
  c.side = side and true or false
  H.state(player, side).tint = { r, g, b, (from or 0) / 16 }
  return c
end
function H.monFadeUpdate(player, c)
  local live = Gen4AnimMath.monFadeUpdate(c)
  local a = (c.applied or c.alpha or 0) / 16
  if a <= 0 then
    H.state(player, c.side).tint = nil
  else
    H.state(player, c.side).tint = { c.r, c.g, c.b, a }
  end
  return live
end

-- A whole-field wash.
function H.wash(player, r, g, b, a)
  if not a or a <= 0 then player.screenFlash = nil return end
  player.screenFlash = { r, g, b, min(1, a) }
end

-- The fadebg palette fade (bgType 0 backdrop, 1 Pokemon, 2 effect).
function H.fadeBg(player, bgType, delay, from, to, colour)
  if player.startPaletteFade then
    return player:startPaletteFade(bgType, delay, from, to, colour)
  end
end

-- Count something this port does not draw, by name.
function H.note(player, what)
  if player.note then player:note(what) end
end

-- ---------------------------------------------------------------------------
-- Registry
-- ---------------------------------------------------------------------------

-- Batch modules: each returns function(Extras) that fills FUNCS / SPRITES.
Extras.BATCHES = {
  "src.battle.Gen4MoveAnimFuncsA",
  "src.battle.Gen4MoveAnimFuncsB",
  "src.battle.Gen4MoveAnimFuncsC",
  "src.battle.Gen4MoveAnimFuncsD",
}

local loaded = false
local function loadBatches()
  if loaded then return end
  loaded = true
  for _, name in ipairs(Extras.BATCHES) do
    local ok, batch = pcall(require, name)
    if ok and type(batch) == "function" then
      local okRun, err = pcall(batch, Extras)
      if not okRun then print(("Gen4MoveAnimExtras: %s: %s"):format(name, tostring(err))) end
    elseif ok == false and not tostring(batch):find("not found", 1, true) then
      print(("Gen4MoveAnimExtras: %s: %s"):format(name, tostring(batch)))
    end
  end
end

-- callFunc(player, id, args) -> true when a port handled it.
function Extras.callFunc(player, id, args)
  loadBatches()
  local fn = Extras.FUNCS[id]
  if not fn then return false end
  fn(player, args)
  return true
end

setmetatable(Extras.SPRITES, { __index = function(_, k)
  if loaded then return nil end
  loadBatches()
  return rawget(Extras.SPRITES, k)
end })

function Extras.load() loadBatches() return Extras end

return Extras
