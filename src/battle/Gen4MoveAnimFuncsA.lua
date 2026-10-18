-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GEN 4 MOVE ANIMATION, BATCH A: the script functions and sprite callbacks of
-- pret's src/battle_anim/script_funcs_0.c (plus ScrollCustomBg and MuddyWater
-- from script_funcs_3.c), registered by their index in sBattleAnimScriptFuncs /
-- sBattleAnimSpriteFuncs (script_func_tables.c).
--
--   FUNCS    5 Strength        (70)          6 BulkUp      (339)
--            7 DoubleTeam      (104)        13 Growth      (74, 353)
--           14 Meditate        (96)         15 Teleport    (100, 245)
--           16 Flash           (148)        19 Splash      (150)
--           21 Harden          (no move)    22 Minimize    (107)
--           24 Earthquake      (89)         26 Nightmare   (171)
--           27 Flail           (165, 175, 218, 313, 343)
--           28 Magnitude       (222)        39 OdorSleuth  (no move)
--           44 ScrollCustomBg  (57)         45 MuddyWater  (330)
--           49 Surf            (57, 330)
--   SPRITES  1 StringShot      (81)          3 Trick       (271, 415)
--
-- HOW THE BATTLER'S Y IS WRITTEN. pret scales a Pokemon about its CENTRE and
-- then moves `MON_SPRITE_Y_CENTER` by `BattleAnimUtil_GetGroundAnchoredScaleOffset`
-- to keep its feet down; this port's draw scales about the FOOT of the 80-pixel
-- frame already. So the `dy` channel carries only what the C's centre does
-- BEYOND a foot pivot: `cCentre - groundOffset(0, scaleY)`. With the species
-- offset at 0 (all `H.spriteOffset` knows today) a ground-anchored scale is
-- dy = 0 exactly, and a centre scale (Growth) is dy = -groundOffset(0, ...).
--
-- MON-SPRITE COPIES (`BattleAnimSystem_GetPokemonSprite`, the Pokemon sprite
-- manager's ManagedSprites) are written to `state.ghosts`; the ones whose
-- palette pret loads through `TintPalette` (a GREYSCALE multiply) carry a
-- darkening `tint` and a `gray` factor (0-1) beside it, since the wash channel
-- cannot express "greyscale".

local Gen4AnimMath = require("src.battle.Gen4AnimMath")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

return function(Extras)
  local H = Extras.H
  local M = Gen4AnimMath
  local floor, min, max = math.floor, math.min, math.max
  local idiv = M.idiv

  -- ---------------------------------------------------------------------------
  -- Shared helpers
  -- ---------------------------------------------------------------------------

  local BASE_SCALE_XY = 100
  local MON_SPRITE_FRAME_HEIGHT = 80
  local FX_ONE = 4096
  local FX_HALF = 2048
  local AFFINE_ONE = 256

  -- `BattleAnimUtil_GetGroundAnchoredScaleOffset(baseY, height, scaleY)`;
  -- `scaleYfx` is `XY_PARAM_CUR_Y` (the affine scale, 256 = 1.0, in fx32).
  -- `FX_Modf` returns the FRACTION (and stores the integer part), so pret's
  -- "integerPart" is the fraction: half a pixel is added when it is non-zero.
  local function groundOffset(height, scaleYfx)
    local avail = (MON_SPRITE_FRAME_HEIGHT - (height or 0) * 2) * FX_ONE
    local scaled = M.fxMul(avail, scaleYfx or AFFINE_ONE * FX_ONE)
    local rel = M.fxDiv(scaled, AFFINE_ONE * FX_ONE)
    local diff = avail - rel
    local whole = idiv(diff, FX_ONE) * FX_ONE
    local frac = diff - whole
    if frac ~= 0 then frac = frac + FX_HALF end
    return idiv(floor((frac + whole) / FX_ONE), 2)
  end

  -- The `dy` that puts the battler's centre `centreRel` pixels from its rest
  -- centre, given that the draw already pivots the scale on the foot.
  local function footDy(centreRel, scaleYfx)
    return centreRel - groundOffset(0, scaleYfx)
  end

  -- `..._GetGroundAnchoredScaleOffset(baseY, spriteHeight, curY)` added to the
  -- rest centre (BATTLE_ANIM_ANCHOR_BOTTOM), as a `dy`.
  local function anchoredDy(player, side, scaleYfx, extraY)
    local h = H.spriteOffset(player, side)
    return footDy((extraY or 0) + groundOffset(h, scaleYfx), scaleYfx)
  end

  local function applyScale(st, c)
    st.sx = (c.x or AFFINE_ONE) / AFFINE_ONE
    st.sy = (c.y or AFFINE_ONE) / AFFINE_ONE
  end

  -- `PokemonSprite_StartFade` is pumped at the TOP of the task, so the frame it
  -- is created does not step it (see Gen4AnimMath.monFade).
  local function pumpFade(player, t)
    if t.fade and t.fade.active then H.monFadeUpdate(player, t.fade) end
  end
  local function fadeActive(t)
    return t.fade ~= nil and t.fade.active == true
  end

  -- `ShakeContext_Update`.
  local shakeUpdate = H.shakeUpdate

  -- `BattleAnimUtil_StepValue`.
  local function stepValue(v, target, step)
    if step < 0 then
      if v + step > target then return v + step, false end
      return target, true
    end
    if v + step < target then return v + step, false end
    return target, true
  end

  -- A blend coefficient (0-31) as a 0-1 share: the hardware clamps at 16.
  local function coeff(v) return max(0, min(16, v or 0)) / 16 end

  -- `TintPalette(r,g,b)` at an equal r=g=b of `k`/256: greyscale times k/256.
  local function grayGhost(dx, dy, alpha, k)
    local f = min(1, (k or 256) / 256)
    return { dx = dx or 0, dy = dy or 0, alpha = alpha or 1, sx = 1, sy = 1,
             tint = (f < 1) and { 0, 0, 0, 1 - f } or nil, gray = f }
  end

  -- The slot record `addpokemonsprite` made, or nil.
  local function monSlot(player, slot)
    return player.monSprites and player.monSprites[slot] or nil
  end

  -- The battler shake/BG shake channel. `bgShakeApply` nils it at zero.
  local function bgShake(player, x, y)
    if player.bgShakeApply then
      player:bgShakeApply({ layer = "effect" }, x or 0, y or 0)
    end
  end

  -- ---------------------------------------------------------------------------
  -- 5 Strength
  -- ---------------------------------------------------------------------------
  local STRENGTH_SHAKE_X, STRENGTH_SHAKE_Y = 2, 0
  local STRENGTH_SHAKE_INTERVAL, STRENGTH_SHAKE_AMOUNT = 0, 10
  local STRENGTH_BLINK_ALPHA, STRENGTH_BLINK_COUNT = 10, 3

  Extras.FUNCS[5] = function(player)
    local side = H.attacker(player)
    local shrinkScale, growScale = H.var(player, 0), H.var(player, 1)
    local shrinkFrames, growFrames = H.var(player, 2), H.var(player, 3)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      pumpFade(p, t)
      if t.state == 0 then        -- SHRINK
        if M.scaleLerpUpdate(t.scale) then
          shakeUpdate(t.shake)
          applyScale(st, t.scale)
          -- `PokemonSprite_AddAttribute(X_CENTER, shake.x)`: ACCUMULATES, so the
          -- battler ends this phase 2px right of rest (10 updates of 2,0,-2,0)
          -- exactly as the cartridge leaves it.
          st.dx = (st.dx or 0) + t.shake.x
          st.dy = anchoredDy(p, side, t.scale.curY)
        else
          t.state = 1
        end
      elseif t.state == 1 then    -- FADE_TO_RED
        t.fade = H.monFade(p, side, 0, STRENGTH_BLINK_ALPHA, 0, H.RED)
        t.state = 2
      elseif t.state == 2 then    -- FADE_TO_NORMAL
        if not fadeActive(t) then
          t.fade = H.monFade(p, side, STRENGTH_BLINK_ALPHA, 0, 0, H.RED)
          t.state = 3
        end
      elseif t.state == 3 then    -- WAIT_FOR_FADE
        if not fadeActive(t) then
          t.blink = t.blink + 1
          if t.blink >= STRENGTH_BLINK_COUNT then
            t.scale = M.scaleLerp(shrinkScale, 100, growScale, growFrames)
            t.state = 4
          else
            t.state = 1
          end
        end
      elseif t.state == 4 or t.state == 5 then  -- GROW / CLEANUP
        if M.scaleLerpUpdate(t.scale) then
          applyScale(st, t.scale)
          st.dy = anchoredDy(p, side, t.scale.curY)
        elseif t.state == 4 then
          t.state = 5
        else
          st.sx, st.sy, st.dy = 1, 1, 0
          t.state = 6
        end
      else
        st.tint = nil
        t.done = true
      end
    end, {
      blink = 0,
      scale = M.scaleLerp(BASE_SCALE_XY, BASE_SCALE_XY, shrinkScale, shrinkFrames),
      shake = H.shake(STRENGTH_SHAKE_X, STRENGTH_SHAKE_Y, STRENGTH_SHAKE_INTERVAL,
                      STRENGTH_SHAKE_AMOUNT),
    })
  end

  -- ---------------------------------------------------------------------------
  -- 6 BulkUp
  -- ---------------------------------------------------------------------------
  local BULK_UP_STRETCH_X, BULK_UP_SQUISH_X = 150, 50
  local BULK_UP_STRETCH_Y, BULK_UP_SQUISH_Y = 150, 50
  local BULK_UP_SQUISH_STRETCH_FRAMES = 10
  local BULK_UP_RETURN_TO_NORMAL_FRAMES = 5
  local BULK_UP_GROW_FRAMES, BULK_UP_SHRINK_FRAMES = 5, 5

  -- The lerp each state starts when the previous one finishes.
  local BULK_UP_NEXT = {
    [0] = { BULK_UP_STRETCH_X, BULK_UP_SQUISH_X, BULK_UP_SQUISH_Y, BULK_UP_STRETCH_Y,
            BULK_UP_SQUISH_STRETCH_FRAMES },
    [1] = { BULK_UP_SQUISH_X, BASE_SCALE_XY, BULK_UP_STRETCH_Y, BASE_SCALE_XY,
            BULK_UP_RETURN_TO_NORMAL_FRAMES },
    [2] = { BASE_SCALE_XY, BULK_UP_STRETCH_X, BASE_SCALE_XY, BULK_UP_STRETCH_Y,
            BULK_UP_GROW_FRAMES },
    [3] = { BULK_UP_STRETCH_X, BASE_SCALE_XY, BULK_UP_STRETCH_Y, BASE_SCALE_XY,
            BULK_UP_SHRINK_FRAMES },
  }

  Extras.FUNCS[6] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state <= 4 then
        if H.scaleXYUpdate(t.scale) then
          applyScale(st, t.scale)
          st.dy = anchoredDy(p, side, t.scale.curY)
        elseif t.state < 4 then
          local n = BULK_UP_NEXT[t.state]
          t.scale = H.scaleXY(n[1], n[2], n[3], n[4], BASE_SCALE_XY, n[5])
          t.state = t.state + 1
        else
          st.sx, st.sy, st.dy = 1, 1, 0
          t.state = 5
        end
      else
        t.done = true
      end
    end, {
      scale = H.scaleXY(BASE_SCALE_XY, BULK_UP_STRETCH_X, BASE_SCALE_XY,
                        BULK_UP_SQUISH_Y, BASE_SCALE_XY, BULK_UP_SQUISH_STRETCH_FRAMES),
    })
  end

  -- ---------------------------------------------------------------------------
  -- 7 DoubleTeam -- four greyscale copies sliding out and in
  -- ---------------------------------------------------------------------------
  local DOUBLE_TEAM_BLEND_A, DOUBLE_TEAM_BLEND_B = 8, 6
  local DOUBLE_TEAM_MON_1_TINT, DOUBLE_TEAM_MON_2_TINT = 128, 196
  local DOUBLE_TEAM_BASEPOS, DOUBLE_TEAM_RANGE_X = 0, 32
  local DOUBLE_TEAM_ITERATION_FRAMES_1, DOUBLE_TEAM_ITERATION_FRAMES_2 = 7, 10
  local DOUBLE_TEAM_MAX_MOVE_ITERATIONS = 8
  -- sDoubleTeamPositions, 1-based rows of { base, range, frames }.
  local DOUBLE_TEAM_POS = {
    { DOUBLE_TEAM_BASEPOS, DOUBLE_TEAM_RANGE_X, DOUBLE_TEAM_ITERATION_FRAMES_1 },
    { DOUBLE_TEAM_BASEPOS, DOUBLE_TEAM_RANGE_X, DOUBLE_TEAM_ITERATION_FRAMES_2 },
    { DOUBLE_TEAM_RANGE_X, DOUBLE_TEAM_BASEPOS, DOUBLE_TEAM_ITERATION_FRAMES_1 },
    { DOUBLE_TEAM_RANGE_X, DOUBLE_TEAM_BASEPOS, DOUBLE_TEAM_ITERATION_FRAMES_2 },
  }

  Extras.FUNCS[7] = function(player)
    local side = H.attacker(player)
    -- R1, L1 take tint MON_1 on the player's side and MON_2 on the foe's.
    local k1, k2 = DOUBLE_TEAM_MON_1_TINT, DOUBLE_TEAM_MON_2_TINT
    if not side then k1, k2 = k2, k1 end
    local function publish(p, t)
      local a = t.blendA / 16
      -- Back to front: the copies sit under the battler; MON_2 priority (20)
      -- draws behind MON_1 (10).
      local g = {}
      local order = side and { 3, 4, 1, 2 } or { 1, 2, 3, 4 }
      for _, i in ipairs(order) do
        g[#g + 1] = grayGhost(t.x[i], 0, a, (i <= 2) and k1 or k2)
      end
      H.state(p, side).ghosts = g
    end
    H.task(player, function(p, t)
      if t.state == 0 then        -- INIT (falls through)
        local posIndex = (t.iteration % 2) * 2
        local red = idiv(t.iteration + 1, 2)
        local r1, r2 = DOUBLE_TEAM_POS[posIndex + 1], DOUBLE_TEAM_POS[posIndex + 2]
        t.pos[1] = M.posLerp(r1[1], r1[2], 0, 0, r1[3] - red)
        t.pos[2] = M.posLerp(-r1[1], -r1[2], 0, 0, r1[3] - red)
        t.pos[3] = M.posLerp(r2[1], r2[2], 0, 0, r2[3] - red)
        t.pos[4] = M.posLerp(-r2[1], -r2[2], 0, 0, r2[3] - red)
        t.iteration = t.iteration + 1
        t.state = 1
      end
      if t.state == 1 then        -- UPDATE_SPRITES
        local complete = 0
        for i = 1, 4 do
          if M.posLerpUpdate(t.pos[i]) then t.x[i] = t.pos[i].x
          else complete = complete + 1 end
        end
        if complete == 4 then
          if t.iteration == DOUBLE_TEAM_MAX_MOVE_ITERATIONS + 1 then t.state = 2
          else t.state = 0 end
        end
        publish(p, t)
      elseif t.state == 2 then    -- FADE_OUT_SPRITES
        if t.blendA > 0 then t.blendA = t.blendA - 1 end
        if t.blendB < 15 then t.blendB = t.blendB + 1 end
        if t.blendA == 0 and t.blendB == 15 then t.state = 3 end
        publish(p, t)
      else
        H.state(p, side).ghosts = nil
        t.done = true
      end
    end, { iteration = 0, blendA = DOUBLE_TEAM_BLEND_A, blendB = DOUBLE_TEAM_BLEND_B,
           pos = {}, x = { 0, 0, 0, 0 } })
  end

  -- ---------------------------------------------------------------------------
  -- 13 Growth (centre scale, no anchoring) -- also Doom Desire
  -- ---------------------------------------------------------------------------
  local GROWTH_SCALE, GROWTH_SCALE_FRAMES, GROWTH_SCALE_CYCLES = 115, 6, 2
  local GROWTH_BLINK_ALPHA = 6
  local GROWTH_TABLE = {
    [0] = { BASE_SCALE_XY, GROWTH_SCALE, GROWTH_SCALE_FRAMES },
    [1] = { GROWTH_SCALE, BASE_SCALE_XY, GROWTH_SCALE_FRAMES },
  }

  Extras.FUNCS[13] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      pumpFade(p, t)
      if t.state == 0 then
        local row = GROWTH_TABLE[t.scaleState]
        t.scale = M.scaleLerp(row[1], BASE_SCALE_XY, row[2], row[3])
        if t.scaleState == 0 then
          t.fade = H.monFade(p, side, 0, GROWTH_BLINK_ALPHA, 0, H.WHITE)
        else
          t.fade = H.monFade(p, side, GROWTH_BLINK_ALPHA, 0, 0, H.WHITE)
        end
        t.scaleState = 1 - t.scaleState
        t.iterations = t.iterations + 1
        t.state = 1
      elseif t.state == 1 then
        -- Both operands are evaluated only while the first is FALSE (&&), and
        -- the lerp update is the first: it runs every frame.
        if not M.scaleLerpUpdate(t.scale) and not fadeActive(t) then
          if t.iterations < GROWTH_SCALE_CYCLES * 2 then t.state = 0
          else t.state = 2 end
        end
        applyScale(st, t.scale)
        -- No Y write in the C: it grows about its centre.
        st.dy = footDy(0, t.scale.curY)
      else
        st.sx, st.sy, st.dy = 1, 1, 0
        t.done = true
      end
    end, { scaleState = 0, iterations = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 14 Meditate
  -- ---------------------------------------------------------------------------
  local MEDITATE_TABLE = {
    { BASE_SCALE_XY, 150, BASE_SCALE_XY, 50, 8 },
    { 150, 50, 50, 150, 8 },
    { 50, BASE_SCALE_XY, 150, BASE_SCALE_XY, 8 },
  }

  Extras.FUNCS[14] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        local r = MEDITATE_TABLE[t.iterations + 1]
        t.scale = H.scaleXY(r[1], r[2], r[3], r[4], BASE_SCALE_XY, r[5])
        t.iterations = t.iterations + 1
        t.state = 1
      elseif t.state == 1 then
        if not H.scaleXYUpdate(t.scale) then
          if t.iterations < #MEDITATE_TABLE then t.state = 0 else t.state = 2 end
        end
        applyScale(st, t.scale)
        st.dy = anchoredDy(p, side, t.scale.curY)
      else
        -- The table's last row lands on 100%; pret writes nothing here.
        st.sx, st.sy, st.dy = 1, 1, 0
        t.done = true
      end
    end, { iterations = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 15 Teleport -- squish, shoot to the top of the screen, shrink, HIDE
  -- (also ExtremeSpeed). The battler is deliberately LEFT HIDDEN, as pret does.
  -- ---------------------------------------------------------------------------
  local TELEPORT_TABLE = {
    [0] = { BASE_SCALE_XY, 10, BASE_SCALE_XY, 180, 10 },
    [1] = { 10, 10, 180, 0, 5 },
  }
  local TELEPORT_REVERT_POS_Y, TELEPORT_REVERT_POS_FRAMES = 0, 5

  Extras.FUNCS[15] = function(player)
    local side = H.attacker(player)
    -- MON_SPRITE_Y_CENTER at rest, in DS pixels (the solo battler centre).
    local _, restY = H.centre(side)
    local h = H.spriteOffset(player, side)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 or t.state == 4 then      -- SETUP_SQUISH / SETUP_SHRINK
        local r = TELEPORT_TABLE[t.scaleType]
        t.scale = H.scaleXY(r[1], r[2], r[3], r[4], BASE_SCALE_XY, r[5])
        t.scaleType = t.scaleType + 1
        if t.state == 4 then t.attackerY = t.centreY end
        t.state = t.state + 1
      elseif t.state == 1 or t.state == 5 then  -- SQUISH / SHRINK
        if not H.scaleXYUpdate(t.scale) then t.state = t.state + 1 end
        applyScale(st, t.scale)
        local off = groundOffset(h, t.scale.curY)
        if t.state <= 2 then
          t.centreY = t.attackerY + off                 -- ANCHOR_BOTTOM
        else
          t.centreY = t.attackerY - h - off             -- ANCHOR_TOP
        end
        st.dy = footDy(t.centreY - restY, t.scale.curY)
      elseif t.state == 2 then                  -- SETUP_MOVE
        t.pos = M.posLerp(0, 0, t.centreY, TELEPORT_REVERT_POS_Y,
                          TELEPORT_REVERT_POS_FRAMES)
        t.state = 3
      elseif t.state == 3 then                  -- MOVE
        if not M.posLerpUpdate(t.pos) then t.state = 4 end
        t.centreY = t.pos.y
        st.dy = footDy(t.centreY - restY, t.scale.curY)
      else
        st.dy, st.sx, st.sy = 0, 1, 1
        st.hidden = true
        t.done = true
      end
    end, { scaleType = 0, attackerY = restY, centreY = restY })
  end

  -- ---------------------------------------------------------------------------
  -- 16 Flash -- backdrop to white, attacker to black, hold, back
  -- ---------------------------------------------------------------------------
  local FLASH_FADE_START, FLASH_FADE_END = 0, 16
  local FLASH_PALETTE_FADE_DELAY, FLASH_POKEMON_FADE_DELAY = -2, 0
  local FLASH_HOLD_FRAMES = 5

  local function baseFade(player, delay, from, to, colour)
    if player.startGroupFade then
      return player:startGroupFade("base", delay, from, to, colour, "Flash")
    end
    return H.fadeBg(player, 0, delay, from, to, colour)
  end

  Extras.FUNCS[16] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      pumpFade(p, t)
      if t.state == 0 or t.state == 3 then
        local a, b = FLASH_FADE_START, FLASH_FADE_END
        if t.state == 3 then a, b = b, a end
        baseFade(p, FLASH_PALETTE_FADE_DELAY, a, b, H.WHITE)
        t.fade = H.monFade(p, side, a, b, FLASH_POKEMON_FADE_DELAY, H.BLACK)
        t.state = t.state + 1
      elseif t.state == 1 or t.state == 4 then
        if not (p.paletteFadeBusy and p:paletteFadeBusy()) and not fadeActive(t) then
          t.state = t.state + 1
        end
      elseif t.state == 2 then
        t.delay = t.delay + 1
        if t.delay > FLASH_HOLD_FRAMES then t.state = 3 end
      else
        H.state(p, side).tint = nil
        t.done = true
      end
    end, { delay = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 19 Splash
  -- ---------------------------------------------------------------------------
  local SPLASH_CYCLES, SPLASH_STRETCH, SPLASH_SQUISH, SPLASH_FRAMES = 3, 120, 80, 5
  local SPLASH_OFFSET_POS_Y = 16
  local SPLASH_SCALE = {
    { BASE_SCALE_XY, SPLASH_STRETCH, BASE_SCALE_XY, SPLASH_SQUISH, SPLASH_FRAMES },
    { SPLASH_STRETCH, BASE_SCALE_XY, SPLASH_SQUISH, SPLASH_STRETCH, SPLASH_FRAMES },
    { BASE_SCALE_XY, BASE_SCALE_XY, SPLASH_STRETCH, BASE_SCALE_XY, SPLASH_FRAMES },
  }
  local SPLASH_POS = {
    { 0, SPLASH_OFFSET_POS_Y, SPLASH_FRAMES },
    { SPLASH_OFFSET_POS_Y, 0, SPLASH_FRAMES },
    { 0, 0, SPLASH_FRAMES },
  }

  Extras.FUNCS[19] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        local r, q = SPLASH_SCALE[t.iteration + 1], SPLASH_POS[t.iteration + 1]
        t.scale = H.scaleXY(r[1], r[2], r[3], r[4], 100, r[5])
        -- relative to the attacker's Y
        t.pos = M.posLerp(0, 0, q[1], q[2], q[3])
        t.iteration = t.iteration + 1
        t.state = 1
      elseif t.state == 1 then
        local done = 0
        if not H.scaleXYUpdate(t.scale) then done = done + 1 end
        if not M.posLerpUpdate(t.pos) then done = done + 1 end
        if done >= 2 then
          if t.iteration >= #SPLASH_SCALE then
            t.cycles = t.cycles + 1
            t.iteration = 0
            if t.cycles >= SPLASH_CYCLES then t.state = 2 end
          else
            t.state = 0
          end
        end
        applyScale(st, t.scale)
        st.dy = anchoredDy(p, side, t.scale.curY, t.pos.y)
      else
        st.sx, st.sy, st.dy = 1, 1, 0
        t.done = true
      end
    end, { iteration = 0, cycles = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 21 Harden -- a greyscale copy through an OBJ window (no move uses it)
  -- ---------------------------------------------------------------------------
  local HARDEN_TINT, HARDEN_START_DELAY = 256, 10

  Extras.FUNCS[21] = function(player)
    local side = H.attacker(player)
    H.note(player, "Harden: OBJ-window masking of the greyscale copy")
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        t.timer = t.timer + 1
        if t.timer >= HARDEN_START_DELAY then t.timer = 0; t.state = 1 end
      elseif t.state == 1 then
        -- Both copies drawn; the second becomes the OBJ window, so what shows is
        -- the greyscale copy over the battler.
        local g = grayGhost(0, 0, 1, HARDEN_TINT)
        g.over = true
        st.ghosts = { g }
        t.state = 2
      elseif t.state == 2 then
        t.timer = t.timer + 1
        if t.timer >= HARDEN_START_DELAY then
          st.ghosts = nil
          t.timer = 0
          t.state = 3
        end
      else
        st.ghosts = nil
        t.done = true
      end
    end, { timer = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 22 Minimize -- three translucent copies shrink in turn, three times
  --
  -- The battler itself is PARTIAL-DRAWN with a 0x0 region (invisible) for the
  -- whole task and the copies stand where it is, so copy 0 is written to the
  -- battler's own channels and copies 1 and 2 to `ghosts`.
  -- ---------------------------------------------------------------------------
  local MINIMIZE_COUNT, MINIMIZE_SPRITE_ALPHA = 3, 12
  local MINIMIZE_SHRINK, MINIMIZE_FRAMES, MINIMIZE_CYCLES = 5, 5, 3
  local MINIMIZE_DELAYS = { 2, 7, 13, 18 }

  Extras.FUNCS[22] = function(player)
    local side = H.attacker(player)
    local function publish(p, t)
      local st = H.state(p, side)
      local c = t.copies
      local a = t.xlu and (MINIMIZE_SPRITE_ALPHA / 16) or 1
      st.sx, st.sy, st.dy, st.alpha = c[1].sx, c[1].sy, c[1].dy, a
      st.ghosts = {
        { dx = 0, dy = c[3].dy, alpha = a, sx = c[3].sx, sy = c[3].sy },
        { dx = 0, dy = c[2].dy, alpha = a, sx = c[2].sx, sy = c[2].sy },
      }
    end
    local function scaleCopy(p, c)
      applyScale(c, c.scale)
      c.dy = anchoredDy(p, side, c.scale.curY)
    end
    local copies = {}
    for i = 1, MINIMIZE_COUNT do
      copies[i] = { state = 0, frames = 0, sx = 1, sy = 1, dy = 0 }
    end
    H.task(player, function(p, t)
      local c = t.copies
      if t.state == 0 then                       -- INIT (partial draw on)
        t.state = 1
      elseif t.state == 1 then                   -- SHRINK
        local done = 0
        for i = 1, MINIMIZE_COUNT do
          local s = c[i]
          if s.state == 0 then
            s.frames = s.frames + 1
            if s.frames >= MINIMIZE_DELAYS[i] then
              s.scale = H.scaleXY(BASE_SCALE_XY, MINIMIZE_SHRINK, BASE_SCALE_XY,
                                  MINIMIZE_SHRINK, BASE_SCALE_XY, MINIMIZE_FRAMES)
              s.state = 1
            end
          elseif s.state == 1 then
            if not H.scaleXYUpdate(s.scale) then s.state = 2
            else scaleCopy(p, s) end
          else
            done = done + 1
          end
        end
        if done >= MINIMIZE_COUNT then
          t.cycles = t.cycles + 1
          if t.cycles < MINIMIZE_CYCLES then
            for i = 1, MINIMIZE_COUNT do
              local s = c[i]
              s.sx, s.sy, s.dy = 1, 1, 0
              s.state, s.frames = 0, 0
            end
            t.state = 0
          else
            t.state = 2
          end
        end
      elseif t.state == 2 then                   -- SETUP_GROW
        t.xlu = false
        for i = 1, MINIMIZE_COUNT do
          c[i].scale = H.scaleXY(MINIMIZE_SHRINK, BASE_SCALE_XY, MINIMIZE_SHRINK,
                                 BASE_SCALE_XY, BASE_SCALE_XY, MINIMIZE_FRAMES)
        end
        t.state = 3
      elseif t.state == 3 then                   -- GROW
        local done = 0
        for i = 1, MINIMIZE_COUNT do
          if not H.scaleXYUpdate(c[i].scale) then done = done + 1
          else scaleCopy(p, c[i]) end
        end
        if done >= MINIMIZE_COUNT then t.state = 4 end
      else
        local st = H.state(p, side)
        st.sx, st.sy, st.dy, st.alpha, st.ghosts = 1, 1, 0, 1, nil
        t.done = true
        return
      end
      publish(p, t)
    end, { cycles = 0, copies = copies, xlu = true })
  end

  -- ---------------------------------------------------------------------------
  -- 24 Earthquake -- shrinking shakes, alternating black/white backdrop flashes
  -- ---------------------------------------------------------------------------
  local EARTHQUAKE_EXTENTS = { 12, 10, 8, 6, 4, 2, 1, 0 }
  local EARTHQUAKE_BG_FADE_DELAY, EARTHQUAKE_BG_FADE_ALPHA = 1, 10
  local EARTHQUAKE_FLASH_FRAMES, EARTHQUAKE_FLASH_ALPHA = 3, 10
  local EARTHQUAKE_SHAKE_AMOUNT = 5

  local function groupBlend(player, level, colour)
    if player.blendGroupNow then player:blendGroupNow("base", level, colour) end
  end

  Extras.FUNCS[24] = function(player)
    H.task(player, function(p, t)
      if t.state == 0 then                         -- INIT
        if p.startGroupFade then
          p:startGroupFade("base", EARTHQUAKE_BG_FADE_DELAY, 0,
                           EARTHQUAKE_BG_FADE_ALPHA, H.BLACK, "Earthquake")
        end
        t.state = 1
        return
      end
      if t.state == 1 then                         -- FADE_BG (falls through)
        if p.paletteFadeBusy and p:paletteFadeBusy() then return end
        t.state = 2
      end
      if t.state == 2 then                         -- FLASH (falls through)
        t.shake = H.shake(EARTHQUAKE_EXTENTS[t.shakeCount + 1], 0, 0,
                          EARTHQUAKE_SHAKE_AMOUNT)
        -- `PaletteData_BlendMulti` over the BG palettes: it overwrites the
        -- faded buffer, so the 0->10 black fade is gone after the first flash.
        groupBlend(p, EARTHQUAKE_FLASH_ALPHA, (t.flashFlag == 0) and H.BLACK or H.WHITE)
        t.flashDuration = EARTHQUAKE_FLASH_FRAMES
        t.flashFlag = 1 - t.flashFlag
        t.shakeCount = t.shakeCount + 1
        t.state = 3
      end
      if t.state == 3 then                         -- SHAKE
        if not shakeUpdate(t.shake) then
          if t.shakeCount >= #EARTHQUAKE_EXTENTS then t.state = 4 else t.state = 2 end
        end
        if t.flashDuration > 0 then
          t.flashDuration = t.flashDuration - 1
          if t.flashDuration == 0 then groupBlend(p, 0, H.BLACK) end
        end
        -- Singles: attacker and defender, i.e. both sides.
        H.state(p, true).dx = t.shake.x
        H.state(p, false).dx = t.shake.x
        bgShake(p, t.shake.x, 0)
        return
      end
      bgShake(p, 0, 0)
      t.done = true
    end, { shakeCount = 0, flashFlag = 0, flashDuration = 0 })
  end

  -- ---------------------------------------------------------------------------
  -- 26 Nightmare -- a copy of the target drifts off and fades
  -- ---------------------------------------------------------------------------
  local NIGHTMARE_OFFSET_X, NIGHTMARE_OFFSET_Y, NIGHTMARE_FRAMES = -20, 20, 20
  local NIGHTMARE_ALPHA_FRAMES = NIGHTMARE_FRAMES - 5

  Extras.FUNCS[26] = function(player)
    local side = (H.var(player, 0) == 0) and H.defender(player) or H.attacker(player)
    local dirX, dirY = H.dirX(side), H.dirY(side)
    H.task(player, function(p, t)
      -- The AlphaFadeContext's own SysTask (priority 0) starts the frame after.
      if t.first then t.first = false else M.alphaFadeUpdate(t.alpha) end
      if t.state == 0 then
        if not M.posLerpUpdate(t.pos) then t.state = 1 end
        H.state(p, side).ghosts = {
          { dx = t.pos.x, dy = t.pos.y, alpha = M.blendAlpha(t.alpha), sx = 1, sy = 1,
            over = true },
        }
      else
        H.state(p, side).ghosts = nil
        t.done = true
      end
    end, {
      first = true,
      pos = M.posLerp(0, NIGHTMARE_OFFSET_X * dirX, 0, NIGHTMARE_OFFSET_Y * dirY,
                      NIGHTMARE_FRAMES),
      alpha = M.alphaFade(31, 0, 0, 31, NIGHTMARE_ALPHA_FRAMES),
    })
  end

  -- ---------------------------------------------------------------------------
  -- 27 Flail (Struggle, Frustration, Fake Tears, Covet)
  -- ---------------------------------------------------------------------------
  local FLAIL_WIGGLES, FLAIL_WIGGLE_PIVOT_Y = 5, 100
  local FLAIL_ANGLES = {
    { H.degToIdx(20), 3 }, { H.degToIdx(15), 3 }, { H.degToIdx(10), 2 },
    { H.degToIdx(5), 2 }, { H.degToIdx(0), 1 },
  }

  Extras.FUNCS[27] = function(player)
    local mode = H.var(player, 0)
    local atk, def = H.attacker(player), H.defender(player)
    if mode == 0 then
      -- ATTACKER: a wiggle about a pivot 100px BELOW the centre
      -- (MON_SPRITE_Y_PIVOT). The rotation channel turns about the centre, so the
      -- centre's travel round the pivot goes into dx/dy.
      H.task(player, function(p, t)
        local st = H.state(p, atk)
        if t.state == 0 then
          local row = FLAIL_ANGLES[t.counter2 + 1]
          local a = (t.counter1 == 0) and -row[1] or row[1]
          t.angle = M.valueLerp(a, -a, row[2])
          if t.counter1 == 1 then t.counter2 = t.counter2 + 1 end
          t.counter1 = 1 - t.counter1
          t.state = 1
        end
        if t.state == 1 then
          if M.valueLerpUpdate(t.angle) then
            local idx = t.angle.value % 65536
            local r = H.radians(idx)
            st.rot = r
            st.dx = FLAIL_WIGGLE_PIVOT_Y * math.sin(r)
            st.dy = FLAIL_WIGGLE_PIVOT_Y * (1 - math.cos(r))
          elseif t.counter2 >= FLAIL_WIGGLES then
            t.state = 2
          else
            t.state = 0
          end
          return
        end
        st.rot, st.dx, st.dy = 0, 0, 0
        t.done = true
      end, { counter1 = 0, counter2 = 0 })
    else
      -- DEFENDER: `ShakeContext_UpdateAndApplyToMon` with the CURRENT centre, so
      -- each frame's offset adds onto the last (it sums to 0 over a cycle).
      local ex, ey = H.var(player, 1), H.var(player, 2)
      local interval, amount = H.var(player, 3), H.var(player, 4)
      H.task(player, function(p, t)
        local st = H.state(p, def)
        if t.state == 0 then
          t.shake = H.shake(ex, ey, interval, amount)
          t.state = 1
        elseif t.state == 1 then
          if shakeUpdate(t.shake) then
            st.dx = (st.dx or 0) + t.shake.x
            st.dy = (st.dy or 0) + t.shake.y
          else
            t.state = 2
          end
        else
          t.done = true
        end
      end)
    end
  end

  -- ---------------------------------------------------------------------------
  -- 28 Magnitude -- the shake grows with the rolled power
  --
  -- `BattleAnimSystem_GetMoveInfo(POWER)` -> `player.movePower`, defaulting to 70
  -- (Magnitude 6, the middle roll) when the battle has not supplied it.
  -- ---------------------------------------------------------------------------
  local MAGNITUDE_EXTENT = { [150] = 6, [110] = 5, [90] = 4, [70] = 3, [50] = 2, [30] = 1 }
  local MAGNITUDE_BASE_EXTENT, MAGNITUDE_SHAKE_AMOUNT = 2, 10

  Extras.FUNCS[28] = function(player)
    local power = MAGNITUDE_EXTENT[tonumber(player.movePower or 70) or 70] or 0
    H.task(player, function(p, t)
      if t.state == 0 then
        t.shake = H.shake(MAGNITUDE_BASE_EXTENT + power, power, 0, MAGNITUDE_SHAKE_AMOUNT)
        t.state = 1
      elseif t.state == 1 then
        if not shakeUpdate(t.shake) then
          t.state = 2
        else
          H.state(p, true).dx = t.shake.x
          H.state(p, false).dx = t.shake.x
          bgShake(p, t.shake.x, t.shake.y)
        end
      else
        -- pret leaves the last shake value applied; a full cycle ends at 0.
        bgShake(p, 0, 0)
        t.done = true
      end
    end)
  end

  -- ---------------------------------------------------------------------------
  -- 39 OdorSleuth -- a copy shaking at the defender (no move uses it)
  -- ---------------------------------------------------------------------------
  local ODOR_SLEUTH_EXTENT_X, ODOR_SLEUTH_AMOUNT = 20, 10

  Extras.FUNCS[39] = function(player)
    local def = H.defender(player)
    local rec = monSlot(player, 0)
    local copySide = rec and rec.side
    if copySide == nil then copySide = H.attacker(player) end
    local dX, dY = H.centre(def)
    local cX, cY = H.centre(copySide)
    H.task(player, function(p, t)
      local st = H.state(p, copySide)
      if t.state == 0 then
        t.shake = H.shake(ODOR_SLEUTH_EXTENT_X, 0, 0, ODOR_SLEUTH_AMOUNT)
        t.state = 1
      elseif t.state == 1 then
        if not shakeUpdate(t.shake) then
          t.state = 2
        else
          -- Copy 0 at the defender's position plus the shake. Copy 1 is put at
          -- -defenderX, off the left edge, and is not drawn.
          st.ghosts = { { dx = dX - cX + t.shake.x, dy = dY - cY + t.shake.y,
                          alpha = 1, sx = 1, sy = 1, over = true } }
        end
      else
        st.ghosts = nil
        t.done = true
      end
    end)
  end

  -- ---------------------------------------------------------------------------
  -- 44 ScrollCustomBg / 45 MuddyWater -- a wave picture on BG2, blended over the
  -- field and scrolled, used together with Surf (49).
  --
  -- Drawn through the player's switched-background layer (`bgLayer` +
  -- `bgAnim.offsetX/Y`): `base` is the other planes' coefficient and `effect`
  -- the wave's, which is exactly G2_SetBlendAlpha(BG2, BD|OBJ|BG0|BG3, ev1, ev2).
  -- APPROXIMATION: the draw dims the whole field by `base`, where the hardware
  -- only blends under the wave's opaque pixels. Whatever layer was up before is
  -- put back at the end.
  -- ---------------------------------------------------------------------------
  local SCROLL_MAX_Y, SCROLL_MIN_Y = 512, -412
  local SCROLL_START_Y_OFFSET = idiv(128, 3) * 2

  local function customBgVariant(player, side)
    if player.contest then return "contest" end
    if not side then return "reversed" end      -- NSCR2 for an enemy attacker
    return "normal"
  end

  -- Shared tail of both tasks: the scroll, the slow-down and the offset write.
  local function scrollStep(p, t)
    if (t.stepY > 0 and t.y >= SCROLL_MAX_Y) or (t.stepY < 0 and t.y <= SCROLL_MIN_Y) then
      t.scrollFinished = true
    end
    t.x = t.x + t.stepX
    t.y = t.y + t.stepY
    if t.slowDownTime < t.timer then
      if t.stepY < 0 then t.stepY = t.stepY + 1 else t.stepY = 0 end
      if t.stepX < 0 then t.stepX = t.stepX + 1 else t.stepX = 0 end
      t.timer = 0
    else
      t.timer = t.timer + 1
    end
    if t.anim then t.anim.offsetX, t.anim.offsetY = t.x, t.y end
  end

  local function layerOn(p, t)
    t.layer = { id = t.bgID, variant = t.variant, blend = true,
                base = coeff(t.otherAlpha), effect = coeff(t.bgAlpha) }
    t.anim = { offsetX = t.x, offsetY = t.y, stepX = 0, stepY = 0, cancel = false }
    p.bgLayer, p.bgAnim = t.layer, t.anim
  end

  local function layerBlend(t)
    if t.layer then
      t.layer.base = coeff(t.otherAlpha)
      t.layer.effect = coeff(t.bgAlpha)
    end
  end

  local function layerOff(p, t)
    if p.bgLayer == t.layer then p.bgLayer = t.prevLayer end
    if p.bgAnim == t.anim then p.bgAnim = t.prevAnim end
  end

  local function customBgTask(player, extra)
    local side = H.attacker(player)
    local t = {
      bgID = H.var(player, 0),
      x = H.var(player, 1), y = H.var(player, 2),
      stepX = H.var(player, 3), stepY = H.var(player, 4),
      reverse = H.var(player, 5) ~= 0,
      var6 = H.var(player, 6),
      slowDownTime = H.var(player, 7) % 65536,
      timer = 0, scrollFinished = false,
      prevLayer = player.bgLayer, prevAnim = player.bgAnim,
    }
    if t.reverse and not side then
      t.x, t.y, t.stepX, t.stepY = -t.x, -t.y, -t.stepX, -t.stepY
      t.y = t.y - SCROLL_START_Y_OFFSET
    else
      t.y = t.y + SCROLL_START_Y_OFFSET
    end
    if player.contest then t.stepX = -t.stepX end
    t.variant = customBgVariant(player, side)
    for k, v in pairs(extra) do t[k] = v end
    return t
  end

  -- 44 ScrollCustomBg
  local SCB_ALPHA_STEP, SCB_OTHER_START, SCB_OTHER_TARGET = 2, 31, 7

  Extras.FUNCS[44] = function(player)
    local opts = customBgTask(player, { bgAlpha = 0, otherAlpha = SCB_OTHER_START })
    opts.targetBgAlpha = opts.var6 % 65536
    H.task(player, function(p, t)
      if t.state == 0 then
        layerOn(p, t)
        t.state = 1
      end
      if t.state == 1 then
        local completed = 0
        if t.bgAlpha < t.targetBgAlpha - SCB_ALPHA_STEP then
          t.bgAlpha = t.bgAlpha + SCB_ALPHA_STEP
        else completed = completed + 1 end
        if t.otherAlpha > SCB_OTHER_TARGET + SCB_ALPHA_STEP then
          t.otherAlpha = t.otherAlpha - SCB_ALPHA_STEP
        else completed = completed + 1 end
        if completed == 2 then
          t.bgAlpha, t.otherAlpha = t.targetBgAlpha, SCB_OTHER_TARGET
          t.state = 2
        end
        layerBlend(t)
      elseif t.state == 2 then
        if t.scrollFinished then t.state = 3 end
      elseif t.state == 3 then
        local completed = 0
        if t.bgAlpha > SCB_ALPHA_STEP then t.bgAlpha = t.bgAlpha - SCB_ALPHA_STEP
        else completed = completed + 1 end
        if t.otherAlpha < SCB_OTHER_START - SCB_ALPHA_STEP then
          t.otherAlpha = t.otherAlpha + SCB_ALPHA_STEP
        else completed = completed + 1 end
        if completed == 2 then
          t.bgAlpha, t.otherAlpha = 0, SCB_OTHER_START
          t.state = 4
        end
        layerBlend(t)
      else
        layerOff(p, t)
        t.done = true
        return
      end
      scrollStep(p, t)
    end, opts)
  end

  -- 45 MuddyWater
  local MW_BG_END, MW_OTHER_START, MW_OTHER_END, MW_ALPHA_STEP = 16, 16, 4, 2

  Extras.FUNCS[45] = function(player)
    -- pret sets bgAlpha to MUDDY_WATER_BG_START_ALPHA (4) and then to 0.
    local opts = customBgTask(player, { bgAlpha = 0, otherAlpha = MW_OTHER_START })
    H.task(player, function(p, t)
      if t.state == 0 then
        layerOn(p, t)
        t.state = 1
      end
      if t.state == 1 then
        local completed = 0
        if t.bgAlpha < MW_BG_END then t.bgAlpha = t.bgAlpha + MW_ALPHA_STEP
        else completed = completed + 1 end
        if t.otherAlpha > MW_OTHER_END then t.otherAlpha = t.otherAlpha - MW_ALPHA_STEP
        else completed = completed + 1 end
        if completed == 2 then
          t.bgAlpha, t.otherAlpha = MW_BG_END, MW_OTHER_END
          t.state = 2
        end
        layerBlend(t)
      elseif t.state == 2 then
        if t.scrollFinished then t.state = 3 end
      elseif t.state == 3 then
        local completed = 0
        if t.bgAlpha > 2 then t.bgAlpha = t.bgAlpha - MW_ALPHA_STEP
        else completed = completed + 1 end
        if t.otherAlpha < MW_OTHER_START then t.otherAlpha = t.otherAlpha + MW_ALPHA_STEP
        else completed = completed + 1 end
        if completed == 2 then
          t.bgAlpha, t.otherAlpha = 0, 31
          t.state = 4
        end
        layerBlend(t)
      else
        layerOff(p, t)
        t.done = true
        return
      end
      scrollStep(p, t)
    end, opts)
  end

  -- ---------------------------------------------------------------------------
  -- 49 Surf -- the wave sprite rears up and collapses
  --
  -- The two sprites are the program's own `addsprite 0 0 ...` / `addsprite 0 1
  -- ...` (BattleAnimSystem_GetSprite 0 and 1): the last two plain sprites alive.
  -- This task takes them over (their lifetime is no longer their animation's)
  -- and deletes both at the end, as pret does.
  -- ---------------------------------------------------------------------------
  local SURF_PLAYER_X, SURF_PLAYER_Y = 76, 120
  local SURF_ENEMY_X, SURF_ENEMY_Y = 144, 64
  local SURF_CONTEST_X, SURF_CONTEST_Y = 255 - 76, 120
  local SURF_INITIAL, SURF_COMPRESSED, SURF_STRETCHED = 100, 60, 150
  local SURF_FRAMES_INITIAL, SURF_FRAMES_STRETCH = 5, 150
  local SURF_FRAMES_COMPRESS, SURF_FRAMES_GROW = 10, 12
  local SURF_HOLD_FRAMES, SURF_ALPHA_OPAQUE, SURF_ALPHA_TARGET = 4, 31, 4
  local SURF_SPRITE_HEIGHT = 16

  local function plainSprites(player, n)
    local out = {}
    local list = player.sprites or {}
    for i = #list, 1, -1 do
      local s = list[i]
      if not s.done and not s.ctx then
        table.insert(out, 1, s)
        if #out == n then break end
      end
    end
    return out
  end

  local function setSequence(s, seq)
    local seqs = s.art and s.art.sequences
    local frames = seqs and seqs[seq + 1] and seqs[seq + 1].frames
    if frames and #frames > 0 then
      s.frames, s.sequence, s.animTick = frames, seq, 0
      s.length = Gen4CellAnim.length(frames)
    end
  end

  Extras.FUNCS[49] = function(player)
    local side = H.attacker(player)
    local owner = { surf = true }
    local got = plainSprites(player, 2)
    local sprites = { got[1], got[2] }
    for _, s in pairs(sprites) do s.ctx = owner end
    local cur, dir, px, py
    if player.contest then
      cur, dir, px, py = 1, -1, SURF_CONTEST_X, SURF_CONTEST_Y
    elseif not side then
      cur, dir, px, py = 2, 1, SURF_ENEMY_X, SURF_ENEMY_Y
    else
      cur, dir, px, py = 1, 1, SURF_PLAYER_X, SURF_PLAYER_Y
    end
    local current = sprites[cur]
    local other = sprites[3 - cur]
    if other then other.visible = false end
    if not current then
      H.note(player, "Surf: wave sprite not loaded")
    else
      setSequence(current, cur - 1)
      current.visible = true
      current.origin = "defender"
      current.sx, current.sy = 0, 0
    end
    local function place(c)
      if not current then return end
      current.scaleX, current.scaleY = M.affineScale(c)
      current.absoluteX = px
      current.absoluteY = py + groundOffset(SURF_SPRITE_HEIGHT, c.curY)
    end
    local scale = H.scaleXY(SURF_INITIAL * dir, SURF_INITIAL * dir, SURF_INITIAL,
                            SURF_FRAMES_INITIAL, SURF_INITIAL, 1)
    H.scaleXYUpdate(scale)
    place(scale)
    if current then current.alpha = 0 end
    H.task(player, function(p, t)
      if t.state == 0 then                  -- COMPRESS
        t.scale = H.scaleXY(SURF_INITIAL * dir, SURF_COMPRESSED * dir,
                            SURF_FRAMES_INITIAL, SURF_STRETCHED, SURF_INITIAL,
                            SURF_FRAMES_GROW)
        t.state = 1
      elseif t.state == 1 or t.state == 3 then
        if not H.scaleXYUpdate(t.scale) then
          if t.state == 1 then
            t.scale = H.scaleXY(SURF_COMPRESSED * dir, SURF_STRETCHED * dir,
                                SURF_FRAMES_STRETCH, SURF_FRAMES_COMPRESS,
                                SURF_INITIAL, SURF_FRAMES_GROW)
          end
          t.state = t.state + 1
        else
          place(t.scale)
          if t.state == 1 then
            if t.alphaStart < SURF_ALPHA_OPAQUE then t.alphaStart = t.alphaStart + 1 end
            if t.alphaBg > SURF_ALPHA_TARGET then t.alphaBg = t.alphaBg - 1 end
          else
            if t.alphaStart > 0 then t.alphaStart = t.alphaStart - 1 end
            if t.alphaBg < SURF_ALPHA_OPAQUE then t.alphaBg = t.alphaBg + 1 end
          end
          if current then current.alpha = coeff(t.alphaStart) end
        end
      elseif t.state == 2 then              -- HOLD
        t.hold = t.hold + 1
        if t.hold >= SURF_HOLD_FRAMES then t.state = 3 end
      else
        for _, s in pairs(sprites) do s.done = true end
        t.done = true
        return
      end
      if current then current.animTick = current.animTick + 1 end
    end, { scale = scale, hold = 0, alphaStart = 0, alphaBg = SURF_ALPHA_OPAQUE })
  end

  -- ---------------------------------------------------------------------------
  -- Sprite callback 1 StringShot -- up to three web strands blinking on the
  -- defender, squeezing, then fading out
  -- ---------------------------------------------------------------------------
  local STRING_SHOT_TIMINGS = { { 8, 2 }, { 13, 1 }, { 18, 3 } }
  local STRING_SHOT_BASE_Y, STRING_SHOT_OFFSET = 32, 4
  local STRING_SHOT_BLINK_FRAMES, STRING_SHOT_WAIT_FRAMES = 45, 45

  Extras.SPRITES[1] = {
    name = "StringShot",
    count = 3,
    start = function(ctx)
      ctx.n = max(1, min(3, tonumber(ctx.vars and ctx.vars[0]) or 1))
      ctx.state, ctx.delay = 0, 0
      ctx.counters = { 0, 0, 0 }
      ctx.spriteAlpha, ctx.bgAlpha = 15, 0
      for i, s in ipairs(ctx.sprites) do
        if i > ctx.n then
          s.done, s.visible = true, false
        else
          -- At the DEFENDER's solo position, 32 - 4i below it.
          s.origin = "defender"
          s.sx, s.sy = 0, STRING_SHOT_BASE_Y - (i - 1) * STRING_SHOT_OFFSET
          s.alpha = ctx.spriteAlpha / 16
        end
      end
    end,
    step = function(ctx)
      local s = ctx.sprites
      if ctx.state == 0 then                -- BLINK
        ctx.delay = ctx.delay + 1
        for i = 1, ctx.n do
          local tm = STRING_SHOT_TIMINGS[i]
          if ctx.delay >= tm[1] then
            ctx.counters[i] = ctx.counters[i] + 1
            if ctx.counters[i] >= tm[2] then
              ctx.counters[i] = 0
              s[i].visible = not s[i].visible
            end
          else
            s[i].visible = false
          end
        end
        if ctx.delay >= STRING_SHOT_BLINK_FRAMES then
          for i = 1, ctx.n do s[i].visible = true end
          ctx.delay = 0
          ctx.state = 1
        end
      elseif ctx.state == 1 then            -- SCALE
        ctx.scale = H.scaleXY(100, 60, BASE_SCALE_XY, BASE_SCALE_XY, BASE_SCALE_XY, 10)
        ctx.state = 2
      elseif ctx.state == 2 then            -- WAIT_FOR_SCALE
        if H.scaleXYUpdate(ctx.scale) then
          local ax, ay = M.affineScale(ctx.scale)
          for i = 1, ctx.n do s[i].scaleX, s[i].scaleY = ax, ay end
        else
          ctx.delay = ctx.delay + 1
          if ctx.delay >= STRING_SHOT_WAIT_FRAMES then ctx.state = 3 end
        end
      elseif ctx.state == 3 then            -- FADE_OUT
        if ctx.spriteAlpha > 0 then ctx.spriteAlpha = ctx.spriteAlpha - 1 end
        if ctx.bgAlpha < 15 then ctx.bgAlpha = ctx.bgAlpha + 1 end
        if ctx.spriteAlpha == 0 and ctx.bgAlpha == 15 then ctx.state = 4 end
        for i = 1, ctx.n do s[i].alpha = ctx.spriteAlpha / 16 end
      else
        return false
      end
      for i = 1, ctx.n do s[i].animTick = s[i].animTick + 1 end
      return true
    end,
  }

  -- ---------------------------------------------------------------------------
  -- Sprite callback 3 Trick (also Switcheroo) -- the attacker bobs, two cups
  -- drop in, swap five times along arcs, and fade
  -- ---------------------------------------------------------------------------
  local TRICK_CUP_1_X, TRICK_CUP_1_Y = 100, 54
  local TRICK_CUP_2_X, TRICK_CUP_2_Y = 180, 39
  local TRICK_SCALES = {
    { 100, 100, 100, 70, 8 },
    { 100, 100, 70, 120, 3 },
    { 100, 100, 120, 100, 3 },
  }
  local TRICK_SCALE_ITERATIONS = 3
  local TRICK_CUP_END_OFFSET_Y, TRICK_CUP_OFFSET_Y_STEP = 50, 2
  local TRICK_DELAY_1, TRICK_DELAY_2 = 1, 0
  local TRICK_CUP_1_OFFSET_DELAY, TRICK_CUP_2_OFFSET_DELAY = 10, 12
  local TRICK_CUP_TARGET_ALPHA, TRICK_BG_TARGET_ALPHA = 16, 0
  local TRICK_CUP_END_ALPHA, TRICK_BG_END_ALPHA = 0, 16
  local TRICK_FADEOUT_STEP = 2
  local TRICK_SWITCH_COUNT, TRICK_SWITCH_FRAMES = 5, 10
  local TRICK_RADIUS = 40 * FX_ONE
  local TRICK_ARC_DIRS = { { 1, -1 }, { -1, 1 }, { 1, -1 }, { 1, -1 }, { 1, -1 } }

  local function cupAlpha(ctx)
    for i = 1, ctx.n do ctx.sprites[i].alpha = coeff(ctx.cupAlpha) end
  end

  Extras.SPRITES[3] = {
    name = "Trick",
    count = 2,
    start = function(ctx)
      ctx.n = max(1, min(2, tonumber(ctx.vars and ctx.vars[0]) or 2))
      ctx.side = ctx.attackerIsPlayer and true or false
      ctx.state, ctx.delay, ctx.iteration = 0, 0, 0
      ctx.cupAlpha, ctx.bgAlpha = 0, 16
      ctx.cups = {}
      local pos
      if ctx.player and ctx.player.contest then
        pos = { { TRICK_CUP_2_X - 20, TRICK_CUP_1_Y }, { TRICK_CUP_1_X - 20, TRICK_CUP_2_Y } }
      else
        pos = { { TRICK_CUP_1_X, TRICK_CUP_1_Y }, { TRICK_CUP_2_X, TRICK_CUP_2_Y } }
      end
      for i, s in ipairs(ctx.sprites) do
        if i > ctx.n then
          s.done, s.visible = true, false
        else
          ctx.cups[i] = { x = pos[i][1], y = pos[i][2] }
          s.absoluteX, s.absoluteY = pos[i][1], pos[i][2]
        end
      end
      cupAlpha(ctx)
    end,
    step = function(ctx)
      local p = ctx.player
      local st = H.state(p, ctx.side)
      local cups = ctx.cups
      local function offsetCups(dy)
        for i = 1, ctx.n do cups[i].y = cups[i].y + dy end
      end
      if ctx.state == 0 then                          -- INIT_SCALE
        local r = TRICK_SCALES[ctx.iteration + 1]
        ctx.scale = H.scaleXY(r[1], r[2], r[3], r[4], BASE_SCALE_XY, r[5])
        ctx.iteration = ctx.iteration + 1
        ctx.state = 1
      elseif ctx.state == 1 then                      -- SCALE
        if H.scaleXYUpdate(ctx.scale) then
          applyScale(st, ctx.scale)
          st.dy = anchoredDy(p, ctx.side, ctx.scale.curY)
        elseif ctx.iteration >= TRICK_SCALE_ITERATIONS then
          ctx.state = 2
        else
          ctx.state = 0
        end
      elseif ctx.state == 2 then                      -- DELAY_1
        ctx.delay = ctx.delay + 1
        if ctx.delay >= TRICK_DELAY_1 then
          ctx.delay, ctx.iteration, ctx.state = 0, 0, 3
        end
      elseif ctx.state == 3 then                      -- CUP_RISE_1
        if cups[1].y <= TRICK_CUP_1_Y + TRICK_CUP_END_OFFSET_Y then
          offsetCups(TRICK_CUP_OFFSET_Y_STEP)
        else
          ctx.state = 4
        end
      elseif ctx.state == 4 then                      -- SET_RISE_2
        if cups[1].y <= TRICK_CUP_1_Y + TRICK_CUP_END_OFFSET_Y then
          offsetCups(TRICK_CUP_OFFSET_Y_STEP)
        else
          ctx.state = 5
        end
        ctx.delay = ctx.delay + 1
        ctx.cupAlpha = stepValue(ctx.cupAlpha, TRICK_CUP_TARGET_ALPHA, 16)
        ctx.bgAlpha = stepValue(ctx.bgAlpha, TRICK_BG_TARGET_ALPHA, -16)
        cupAlpha(ctx)
        if ctx.delay == TRICK_CUP_1_OFFSET_DELAY then cups[1].y = cups[1].y + 16 end
        if ctx.delay == TRICK_CUP_2_OFFSET_DELAY and cups[2] then cups[2].y = cups[2].y + 16 end
      elseif ctx.state == 5 then                      -- CALC_ARC_PARAMS
        ctx.delay = ctx.delay + 1
        if ctx.delay >= TRICK_DELAY_2 + 1 then
          ctx.delay = 0
          ctx.state = 6
        end
      elseif ctx.state == 6 then                      -- INIT_ARC
        local d = TRICK_ARC_DIRS[ctx.iteration + 1]
        local a, b = cups[1], cups[2] or cups[1]
        ctx.arcs = {
          M.parabolic(a.x, b.x, a.y, b.y, TRICK_SWITCH_FRAMES, TRICK_RADIUS * d[1]),
          M.parabolic(b.x, a.x, b.y, a.y, TRICK_SWITCH_FRAMES, TRICK_RADIUS * d[2]),
        }
        ctx.iteration = ctx.iteration + 1
        ctx.state = 7
      elseif ctx.state == 7 then                      -- ARC
        local switched = 0
        for i = 1, 2 do
          local live, x, y = M.parabolicUpdate(ctx.arcs[i])
          if live then
            if cups[i] then cups[i].x, cups[i].y = x, y end
          else
            switched = switched + 1
          end
        end
        if switched == 2 then
          if ctx.iteration == TRICK_SWITCH_COUNT then ctx.state = 8 else ctx.state = 6 end
        end
      elseif ctx.state == 8 then                      -- FADE_OUT
        local done, ok = 0, false
        ctx.cupAlpha, ok = stepValue(ctx.cupAlpha, TRICK_CUP_END_ALPHA, -TRICK_FADEOUT_STEP)
        if ok then done = done + 1 end
        ctx.bgAlpha, ok = stepValue(ctx.bgAlpha, TRICK_BG_END_ALPHA, TRICK_FADEOUT_STEP)
        if ok then done = done + 1 end
        cupAlpha(ctx)
        if done == 2 then ctx.state = 9 end
      else
        st.sx, st.sy, st.dy = 1, 1, 0
        return false
      end
      for i = 1, ctx.n do
        local s = ctx.sprites[i]
        s.absoluteX, s.absoluteY = cups[i].x, cups[i].y
      end
      -- Below SET_RISE_2 the cups are neither ticked nor drawn (alpha 0 anyway).
      if ctx.state >= 4 then
        for i = 1, ctx.n do ctx.sprites[i].animTick = ctx.sprites[i].animTick + 1 end
      end
      return true
    end,
  }
end
