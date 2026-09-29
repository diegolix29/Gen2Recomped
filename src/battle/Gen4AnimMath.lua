-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- src/battle/Gen4AnimMath.lua -- the fixed-point primitives every Gen 4 battle
-- animation is built out of, ported from pret's `battle_anim_helpers.c` with the
-- integer arithmetic kept exactly as the cartridge does it.
--
-- WHY THIS IS A FILE OF ITS OWN AND NOT A HANDFUL OF HELPERS IN THE PLAYER.
-- Twenty-six per-move sprite callbacks occur in Platinum's move programs and
-- they share almost no vocabulary -- Constrict squeezes, Bonemerang arcs,
-- FollowMe oscillates -- but the handful of things they DO share are these five
-- contexts. `PosLerpContext` alone is used by nine of them. Porting the contexts
-- once, exactly, is the difference between twenty-six readings of C and
-- twenty-six guesses.
--
-- EXACTLY MEANS THE ROUNDING TOO, and that is most of the work here. The
-- cartridge runs three different truncations and they do not agree:
--
--   * `FX_Div(a, b)` is the DS's hardware divider: `(a << 12) / b` as a SIGNED
--     integer division, which truncates TOWARD ZERO. -7/2 is -3.
--   * `>> FX32_SHIFT` is an arithmetic shift, which floors toward MINUS
--     INFINITY. -7/2 is -4.
--   * `(ex - sx) / steps` in `RevolutionContext_Init` is plain C integer
--     division on angle indices, truncating toward zero again.
--
-- A port that used one rule for all three would drift by a pixel per frame on
-- anything moving up or left, which is exactly the half of the screen the enemy
-- occupies. `idiv` and `shr12` below are named after the distinction so the call
-- sites cannot blur it.
--
-- THE SINE TABLE IS THE CARTRIDGE'S OWN, and that is checkable rather than
-- assumed: NitroSystem's interleaved sin/cos table sits in Platinum's ARM9 at
-- file offset 0xF983C as 4096 (sin, cos) pairs of s16, and every one of the 4096
-- entries equals `floor(sin(2*pi*i/4096) * 4096 + 0.5)` -- not approximately,
-- all 4096 exactly. So computing the value is the same as reading the table, and
-- `gen4_moveanim_check.lua` proves it by doing both and comparing.
--
-- pret does NOT ship NitroSystem, so `FX_SinIdx` itself is not in the
-- decompilation; what is in the decompilation is every CALLER, and they all pass
-- a u16 angle index where 0x10000 is a full turn. The table's 4096 entries mean
-- the bottom four bits of that index are thrown away before the lookup, which is
-- a real quantisation this port reproduces rather than smooths over.

local floor = math.floor
local sin, cos, pi = math.sin, math.cos, math.pi

local Gen4AnimMath = {}

-- The Nitro fixed-point format: 20.12, so one is 4096.
Gen4AnimMath.FX32_ONE = 4096
Gen4AnimMath.FX32_SHIFT = 12

-- The affine scale unit: `MON_AFFINE_SHIFT` is 8 in include/constants/graphics.h,
-- so `MON_AFFINE_SCALE(1)` is 256 and a scale context's `x` of 256 is 1.0x.
Gen4AnimMath.AFFINE_ONE = 256

-- A full turn of the angle index. `DEG_TO_IDX(degrees)` is
-- `((degrees) * 0xFFFF) / 360` in include/constants/battle/battle_anim.h -- note
-- 0xFFFF and not 0x10000, so the cartridge's own degree conversion is a hair
-- short of a full turn and 360 degrees is 65535, not 65536. The index ARITHMETIC
-- however wraps at 0x10000 (`&= 0xFFFF` in `RevolutionContext_Update`), so both
-- numbers are needed and neither is a typo for the other.
Gen4AnimMath.ANGLE_TURN = 65536
Gen4AnimMath.ANGLE_DEG_MAX = 65535

-- The sine table's resolution: 4096 entries over a turn, so an index is shifted
-- right by 4 before the lookup.
Gen4AnimMath.SIN_TABLE_SIZE = 4096
Gen4AnimMath.SIN_TABLE_SHIFT = 4

-- The ARM9 file offset of NitroSystem's interleaved sin/cos table in Platinum
-- (USA, Rev 1). Nothing in the engine reads the cartridge for this -- the values
-- are computed -- but the check reads it, so the address belongs next to the
-- formula rather than buried in the check.
Gen4AnimMath.SIN_TABLE_ARM9_OFFSET = 0xF983C

-- ---------------------------------------------------------------------------
-- The three roundings
-- ---------------------------------------------------------------------------

-- C signed integer division: truncate TOWARD ZERO.
local function idiv(a, b)
  if b == 0 then return 0 end
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end
Gen4AnimMath.idiv = idiv

-- `>> FX32_SHIFT` on a signed value: floor toward MINUS INFINITY.
local function shr12(v)
  return floor(v / 4096)
end
Gen4AnimMath.shr12 = shr12

-- `FX_Div(a, b)`: the hardware divider, `(a << 12) / b` truncated toward zero.
function Gen4AnimMath.fxDiv(a, b)
  return idiv(a * 4096, b)
end

-- `FX_Mul(a, b)`: `(a * b) >> 12`, and the shift floors.
function Gen4AnimMath.fxMul(a, b)
  return shr12(a * b)
end

-- `BattleAnimMath_GetStepSize(start, end, steps)` -- `FX_Div(end - start,
-- steps << FX32_SHIFT)`. Both arguments are already fx32.
function Gen4AnimMath.stepSize(startFx, endFx, steps)
  if not steps or steps == 0 then return 0 end
  return Gen4AnimMath.fxDiv(endFx - startFx, steps * 4096)
end

-- `DEG_TO_IDX(degrees)`.
function Gen4AnimMath.degToIdx(degrees)
  return idiv(degrees * Gen4AnimMath.ANGLE_DEG_MAX, 360)
end

-- ---------------------------------------------------------------------------
-- The sine table
-- ---------------------------------------------------------------------------

local sinTable, cosTable

local function buildTables()
  sinTable, cosTable = {}, {}
  local n = Gen4AnimMath.SIN_TABLE_SIZE
  for i = 0, n - 1 do
    -- floor(x + 0.5), which is what the cartridge's table holds for all 4096
    -- entries -- verified against the ARM9, not assumed.
    sinTable[i] = floor(sin(2 * pi * i / n) * 4096 + 0.5)
    cosTable[i] = floor(cos(2 * pi * i / n) * 4096 + 0.5)
  end
end

-- The table index a 16-bit angle index resolves to: the bottom four bits are
-- discarded, which is the quantisation the DS actually has.
function Gen4AnimMath.tableIndex(idx)
  return floor((idx % Gen4AnimMath.ANGLE_TURN) / 16) % Gen4AnimMath.SIN_TABLE_SIZE
end

-- `FX_SinIdx(idx)` / `FX_CosIdx(idx)` -> fx32.
function Gen4AnimMath.sinIdx(idx)
  if not sinTable then buildTables() end
  return sinTable[Gen4AnimMath.tableIndex(idx)]
end

function Gen4AnimMath.cosIdx(idx)
  if not cosTable then buildTables() end
  return cosTable[Gen4AnimMath.tableIndex(idx)]
end

-- The whole table, for a caller that wants to compare it with the cartridge's.
function Gen4AnimMath.sinCosTable()
  if not sinTable then buildTables() end
  return sinTable, cosTable
end

-- ---------------------------------------------------------------------------
-- PosLerpContext -- the one primitive nine callbacks build on
--
-- `PosLerpContext_Init(ctx, sx, ex, sy, ey, steps)` then `_Update` per frame:
-- the accumulator moves by a fixed fx32 step and `x`/`y` are the floor of it.
-- The update STEPS FIRST and decrements after, so `x` is still `sx` until the
-- first update and reaches `ex` on the last; the (steps+1)th update returns
-- false and changes nothing.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.posLerp(sx, ex, sy, ey, steps)
  sx, ex, sy, ey = sx or 0, ex or 0, sy or 0, ey or 0
  return {
    x = sx, y = sy,
    steps = steps or 0,
    stepX = Gen4AnimMath.stepSize(sx * 4096, ex * 4096, steps),
    stepY = Gen4AnimMath.stepSize(sy * 4096, ey * 4096, steps),
    curX = sx * 4096, curY = sy * 4096,
  }
end

function Gen4AnimMath.posLerpUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.curX = c.curX + c.stepX
    c.curY = c.curY + c.stepY
    c.x = shr12(c.curX)
    c.y = shr12(c.curY)
    c.steps = c.steps - 1
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- ScaleLerpContext
--
-- `RELATIVE_SCALE(scale, reference)` is `(scale * 256) / reference` -- a C
-- integer division, so Swagger's 14 against a reference of 10 is 358 and not
-- 358.4. The update DECREMENTS FIRST and steps after, which is the opposite
-- order from PosLerp; the visible effect is the same count of updates, and the
-- order is kept because a port that "tidies" it invites the next reader to
-- assume the two contexts are interchangeable elsewhere.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.relativeScale(scale, reference)
  if not reference or reference == 0 then return Gen4AnimMath.AFFINE_ONE end
  return idiv(scale * Gen4AnimMath.AFFINE_ONE, reference)
end

function Gen4AnimMath.scaleLerp(startScale, refScale, endScale, steps)
  local s0 = Gen4AnimMath.relativeScale(startScale, refScale)
  local s1 = Gen4AnimMath.relativeScale(endScale, refScale)
  return {
    x = s0, y = s0,
    steps = steps or 0,
    step = Gen4AnimMath.stepSize(s0 * 4096, s1 * 4096, steps),
    curX = s0 * 4096, curY = s0 * 4096,
  }
end

function Gen4AnimMath.scaleLerpUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.steps = c.steps - 1
    c.curX = c.curX + c.step
    c.curY = c.curY + c.step
    c.x = shr12(c.curX)
    c.y = shr12(c.curY)
    return true
  end
  return false
end

-- The affine scale a scale context is asking for: `ScaleLerpContext_GetAffineScale`
-- divides by `MON_AFFINE_SCALE(1)`, so 256 is 1.0x.
function Gen4AnimMath.affineScale(c)
  return (c.x or 256) / Gen4AnimMath.AFFINE_ONE, (c.y or 256) / Gen4AnimMath.AFFINE_ONE
end

-- ---------------------------------------------------------------------------
-- ValueLerpContext -- one number, and an INTEGER step
--
-- `ValueLerpContext_Init` is the odd one out: it takes the fx32 step size and
-- then shifts it down by 12 immediately, so the step is a whole number and the
-- lerp DOES NOT ARRIVE at its end value unless the distance divides evenly.
-- IcicleSpear's reversed rotation is exactly that case -- 7282 index units over
-- 10 frames steps by 728 and finishes two short -- and the drift is the
-- cartridge's, so it is reproduced rather than corrected.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.valueLerp(startV, endV, steps)
  return {
    value = startV or 0,
    steps = steps or 0,
    step = shr12(Gen4AnimMath.stepSize((startV or 0) * 4096, (endV or 0) * 4096, steps)),
  }
end

function Gen4AnimMath.valueLerpUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.value = c.value + c.step
    c.steps = c.steps - 1
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- RevolutionContext -- a point going round an ellipse
--
-- Two angle indices walk independently (X off the sine, Y off the cosine), each
-- wrapped to 16 bits, and the radii are fx32. The offsets come out as
-- `FX_Mul(sin, radius) >> 12`, which is two floors, not one.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.revolution(sx, ex, sy, ey, rx, ry, steps)
  return {
    x = 0, y = 0,
    steps = steps or 0,
    curX = sx or 0, curY = sy or 0,
    rx = rx or 0, ry = ry or 0,
    stepX = idiv((ex or 0) - (sx or 0), steps or 1),
    stepY = idiv((ey or 0) - (sy or 0), steps or 1),
  }
end

function Gen4AnimMath.revolutionUpdate(c)
  if c.steps and c.steps ~= 0 then
    c.curX = (c.curX + c.stepX) % Gen4AnimMath.ANGLE_TURN
    c.curY = (c.curY + c.stepY) % Gen4AnimMath.ANGLE_TURN
    c.steps = c.steps - 1
    c.x = shr12(Gen4AnimMath.fxMul(Gen4AnimMath.sinIdx(c.curX), c.rx))
    c.y = shr12(Gen4AnimMath.fxMul(Gen4AnimMath.cosIdx(c.curY), c.ry))
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The OVAL revolution, which is a revolution with the cartridge's own radii
-- ---------------------------------------------------------------------------

-- `RevolutionContext_InitOvalRevolutions(ctx, revs, stepsPerRev)` is one turn on
-- each axis with two constants out of battle_anim_helpers.h, and then its step
-- count multiplied by `revs` -- so each revolution takes `stepsPerRev` frames and
-- there are `revs` of them. The STEP SIZE is computed from `stepsPerRev` alone,
-- which is what makes that true: multiplying the count afterwards adds turns, it
-- does not slow them down.
Gen4AnimMath.OVAL_RADIUS_X = 32 * 4096
Gen4AnimMath.OVAL_RADIUS_Y = -8 * 4096
Gen4AnimMath.OVAL_RADIUS_Y_INT = -8

-- `halved` is RevolveBattler's own extra step: it divides both radii by two after
-- the init, which is why a battler's wobble is 16 by 4 pixels and not 32 by 8.
-- Passed in rather than folded in, because nothing says the next caller halves.
function Gen4AnimMath.ovalRevolution(revs, stepsPerRev, halved)
  local steps = stepsPerRev or 0
  local full = Gen4AnimMath.degToIdx(360)
  local c = Gen4AnimMath.revolution(0, full, 0, full,
                                    Gen4AnimMath.OVAL_RADIUS_X,
                                    Gen4AnimMath.OVAL_RADIUS_Y, steps)
  if halved then
    -- C integer division on a negative even number is exact, so -32768/2 is
    -- -16384 and there is no rounding rule to get wrong here.
    c.rx = idiv(c.rx, 2)
    c.ry = idiv(c.ry, 2)
  end
  c.steps = steps * (revs or 0)
  return c
end

-- ---------------------------------------------------------------------------
-- The parabolic arc: a straight line plus half a revolution
--
-- `XYTransformContext_InitParabolic` is a PosLerp from start to end plus a
-- revolution from 90 to 270 degrees on the Y index with the arc radius, and the
-- two are added. Half a cosine turn from +1 through 0 to -1 is the arc; the
-- X half of the revolution has a zero radius and contributes nothing, which is
-- why the same context can serve both.
--
-- IT STAYS ALIVE WHILE EITHER HALF DOES: the C is
-- `if (linearActive == revsActive && linearActive == FALSE) return FALSE`, so a
-- mismatch in the two step counts keeps the sprite going. Both are initialised
-- with the same frame count in every caller, so the mismatch never happens --
-- but the rule is the rule.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.parabolic(sx, ex, sy, ey, frames, arcRadiusFx)
  return {
    linear = Gen4AnimMath.posLerp(sx, ex, sy, ey, frames),
    revs = Gen4AnimMath.revolution(0, 0, Gen4AnimMath.degToIdx(90),
                                   Gen4AnimMath.degToIdx(270), 0,
                                   arcRadiusFx or 0, frames),
  }
end

-- Returns still-running, and the point, which is the linear part AFTER the
-- revolution has been added into it -- the C adds into `linear->x` itself, so a
-- second update reads a position that already carries the previous arc. That is
-- load-bearing: the accumulator `curX` is untouched, so the arc does not
-- compound, but `ctx->x` between updates is the sum and any caller reading it
-- sees the sum.
function Gen4AnimMath.parabolicUpdate(p)
  local linearActive = Gen4AnimMath.posLerpUpdate(p.linear)
  local revsActive = Gen4AnimMath.revolutionUpdate(p.revs)
  p.linear.x = p.linear.x + p.revs.x
  p.linear.y = p.linear.y + p.revs.y
  if linearActive == revsActive and linearActive == false then
    return false, p.linear.x, p.linear.y
  end
  return true, p.linear.x, p.linear.y
end

-- ---------------------------------------------------------------------------
-- AlphaFadeContext -- a PosLerp on the two blend coefficients
--
-- THE FRAME COUNT IS NOT `steps`, AND THE REASON IS THE SCHEDULER.
-- `AlphaFadeContext_Init` starts its own SysTask at priority 0 while the sprite
-- callback that started it runs at 1100, and `SysTaskManager_ExecuteTasks` walks
-- the list in ascending priority. Two consequences, both from
-- `SysTaskManager_InternalAddTask`:
--
--   * The frame it is created, the fade does NOT run. The new task is inserted
--     ahead of the running one (0 < 1100) and the walk has already passed that
--     position. (It is not marked inactive -- `currentTask->priority <= priority`
--     is 1100 <= 0, false -- it is simply behind the cursor.)
--   * Every frame after, it runs BEFORE the callback that reads it. So the frame
--     the fade finishes, the callback sees `done` the same frame.
--
-- So a `steps`-frame fade holds the state machine for steps + 1 frames: the
-- frame it is created is free, then `steps` frames stepping, and the frame after
-- the last step is the frame `done` is read. For FakeOut's two eight-frame fades
-- that is the difference between the sprite lasting its animation plus 20 frames
-- and its animation plus 18.
--
-- THERE IS NO `pending` FLAG HERE and that is deliberate. The free first frame
-- falls out of the caller's own order: a callback pumps its fade at the TOP of
-- its frame (priority 0 before 1100) and creates it further down, so the frame
-- of creation cannot step it. A flag as well would skip two frames, not one.
--
-- The clamp is pret's: a coefficient is never drawn negative. It clamps the
-- VISIBLE value only -- the accumulator keeps the negative, so a fade that dips
-- below zero and comes back resumes where the arithmetic says.
-- ---------------------------------------------------------------------------

Gen4AnimMath.BLEND_MAX = 16

function Gen4AnimMath.alphaFade(ev1Start, ev1End, ev2Start, ev2End, steps)
  local c = Gen4AnimMath.posLerp(ev1Start, ev1End, ev2Start, ev2End, steps)
  c.done = false
  return c
end

function Gen4AnimMath.alphaFadeUpdate(c)
  if c.done then return false end
  if Gen4AnimMath.posLerpUpdate(c) then
    if c.x < 0 then c.x = 0 end
    if c.y < 0 then c.y = 0 end
    return true
  end
  c.done = true
  return false
end

function Gen4AnimMath.alphaFadeDone(c)
  return c and c.done == true
end

-- The 0..1 alpha a blend coefficient means for a drawn sprite: the DS mixes
-- `src * ev1/16 + dst * ev2/16`, so the sprite's own share is ev1/16.
function Gen4AnimMath.blendAlpha(c)
  local ev1 = c and c.x or Gen4AnimMath.BLEND_MAX
  if ev1 < 0 then ev1 = 0 end
  if ev1 > Gen4AnimMath.BLEND_MAX then ev1 = Gen4AnimMath.BLEND_MAX end
  return ev1 / Gen4AnimMath.BLEND_MAX
end

-- ---------------------------------------------------------------------------
-- PokemonSprite_StartFade -- a BATTLER's palette blended toward a colour
--
-- Not one of the sprite contexts: this one belongs to the Pokemon sprite
-- manager, and two sprite callbacks drive it (Foresight flashes the defender
-- white, Ingrain fades one green). It is a one-step-per-frame walk rather than a
-- lerp, and the shape matters:
--
--   * The blend is applied FIRST with the current alpha, and only then does the
--     alpha step toward its target -- so the target value IS applied, on the
--     frame the fade ends.
--   * `fadeDelayLength` is frames BETWEEN steps, and the counter is reloaded on
--     the frame a step happens. Both callers pass 0, so it steps every frame.
--   * `fadeActive` goes false on the frame `init == target`, which is the frame
--     that value is applied. `IsFadeActive` is therefore false from the frame
--     AFTER the last blend.
--
-- The alpha is out of 16, like `BlendPalette`'s `fraction` everywhere else in the
-- cartridge -- `fadebattlersprite` in this port already divides by 16.
--
-- ONE FRAME IS ASSUMED, AND SAID SO: the Pokemon sprite manager is ticked by the
-- battle system rather than by a SysTask, so whether its blend lands before or
-- after the callback that reads it is not determinable from pret. This port pumps
-- it from the callback's own step, which makes it behave like the priority-0
-- tasks: nothing on the frame it is created, then one step per frame.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.monFade(initAlpha, targetAlpha, delay, r, g, b)
  return {
    alpha = initAlpha or 0, target = targetAlpha or 0,
    delay = delay or 0, counter = 0, active = true,
    applied = nil,
    r = r, g = g, b = b,
  }
end

function Gen4AnimMath.monFadeUpdate(c)
  if not c.active then return false end
  if c.counter == 0 then
    c.counter = c.delay
    c.applied = c.alpha
    if c.alpha == c.target then
      c.active = false
    elseif c.alpha > c.target then
      c.alpha = c.alpha - 1
    else
      c.alpha = c.alpha + 1
    end
  else
    c.counter = c.counter - 1
  end
  return c.active
end

function Gen4AnimMath.monFadeActive(c)
  return c ~= nil and c.active == true
end

-- ---------------------------------------------------------------------------
-- Which way round a battler faces
--
-- `BattleAnimUtil_GetTransformDirectionX` is 1 unless the battler is on the
-- enemy side, when it is -1 (and the two swap in a contest, which this port does
-- not have). Every callback that mirrors an offset runs it through this.
-- ---------------------------------------------------------------------------

function Gen4AnimMath.directionX(isPlayerSide)
  if isPlayerSide then return 1 end
  return -1
end

-- The rotation an angle index asks for, in radians.
--
-- THE MAGNITUDE IS DERIVED, THE SIGN IS ASSUMED, and the two are worth
-- separating. 0x10000 is a full turn -- that is in every caller in pret and in
-- the `&= 0xFFFF` wrap. The handedness is not: `Sprite_SetAffineZRotation` only
-- stores the index and the matrix is built by `NNS_G2dRotZ(FX_SinIdx(a),
-- FX_CosIdx(a))` inside NitroSystem, which pret does not ship. This port takes a
-- positive index to be clockwise on screen, which is what LOVE's own positive
-- rotation means in the same y-down space. If an icicle ever points the wrong
-- way, this constant is the one line to flip.
Gen4AnimMath.ROTATION_SIGN = 1

function Gen4AnimMath.radians(angleIdx)
  return Gen4AnimMath.ROTATION_SIGN * (angleIdx or 0) * 2 * pi / Gen4AnimMath.ANGLE_TURN
end

-- ---------------------------------------------------------------------------
-- check(): the arithmetic identities a caller can assert cheaply
-- ---------------------------------------------------------------------------

function Gen4AnimMath.check()
  local why = {}
  if idiv(-7, 2) ~= -3 then why[#why + 1] = "idiv does not truncate toward zero" end
  if shr12(-4097) ~= -2 then why[#why + 1] = "shr12 does not floor" end
  if Gen4AnimMath.relativeScale(14, 10) ~= 358 then
    why[#why + 1] = "relativeScale(14,10) is not 358"
  end
  if Gen4AnimMath.degToIdx(90) ~= 16383 then
    why[#why + 1] = "degToIdx(90) is not 16383"
  end
  if Gen4AnimMath.sinIdx(0) ~= 0 or Gen4AnimMath.cosIdx(0) ~= 4096 then
    why[#why + 1] = "sin/cos of index 0 are wrong"
  end
  do
    -- A 0 -> 2 mon fade applies 0, 1 and 2 and is over after the third, because
    -- the blend happens before the step and the target is applied.
    local f = Gen4AnimMath.monFade(0, 2, 0, 1, 1, 1)
    local seen = {}
    while Gen4AnimMath.monFadeActive(f) and #seen < 8 do
      Gen4AnimMath.monFadeUpdate(f)
      seen[#seen + 1] = f.applied
    end
    if #seen ~= 3 or seen[1] ~= 0 or seen[3] ~= 2 then
      why[#why + 1] = "a mon fade does not apply its target value"
    end
  end
  if #why > 0 then return false, table.concat(why, "; ") end
  return true
end

return Gen4AnimMath
