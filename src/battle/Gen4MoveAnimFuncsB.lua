-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GEN 4 MOVE ANIMATION, BATCH B: thirteen script functions and six sprite
-- callbacks out of pret's src/battle_anim/script_funcs_2.c, registered by their
-- index in `sBattleAnimScriptFuncs` / `sBattleAnimSpriteFuncs`
-- (src/battle_anim/script_func_tables.c). Each is a straight reading of the C
-- state machine: same constants, same frame counts, same lerp contexts (via
-- Gen4AnimMath / Extras.H so the integer stepping matches).
--
--   FUNCS     8 QuickAttack       Quick Attack 98, Agility 97, Rolling Kick 27,
--                                 Aerial Ace 332
--             9 DrillPeck         Drill Peck 65
--            11 Confusion         Confusion 93, Psychic 94 (and 248 Future Sight)
--            12 AcidArmor         Acid Armor 151
--            17 NightShadeAttacker / 18 NightShadeDefender   Night Shade 101
--            20 Spite             Spite 180
--            23 FaintAttack       Faint Attack 185
--            25 PlayfulHops       Charm 204, Attract 213, Tickle 321, Captivate 445
--            29 Return            Return 216
--            30 VitalThrow        Vital Throw 233
--            31 Swagger           Swagger 207 (the ATTACKER's swell; the vein is
--                                 sprite callback 10, in the player)
--            32 Memento           Memento 262
--   SPRITES   2 Kinesis 134, 4 Metronome 118, 5 Constrict 132, 6 Bonemerang 155,
--             9 LockOn 199, 11 MeanLook 212
--
-- CONVENTIONS THIS FILE ASSUMES (stated once rather than at every use):
--   * A battler's channels are offsets from its rest position. Where the C
--     reads `MON_SPRITE_X_CENTER` at call time as its base, this port reads the
--     side's current `dx`/`dy` as the base, so a function started on a battler
--     that is already displaced behaves like the cartridge's.
--   * A copy of a Pokemon (`BattleAnimSystem_GetPokemonSprite` slot) that the C
--     positions, scales or fades is an entry of `state[side].ghosts`, on the side
--     whose coordinates the C positions it at. Ghost `dx`/`dy` are offsets from
--     that side's REST position, and ghost `sx`/`sy` are ASSUMED to pivot on the
--     picture's foot like the battler's own; where the C scales a copy about its
--     centre (AFFINE_OVERWRITE_MODE_DOUBLE) the ghost carries the compensating
--     `dy = 40 * (sy - 1)` so the picture lands where the cartridge's does.
--   * An XLU sprite or copy is drawn at `alpha = min(ev1, 16) / 16`, the share
--     the hardware gives the first blend target. The second target's share
--     (ev2) is not representable; where ev1 + ev2 > 16 the cartridge brightens
--     additively and this draws it opaque.
--   * An AlphaFadeContext is a priority-0 SysTask: it does not step on the frame
--     it is created and then steps BEFORE the task that reads it, so the task
--     pumps it at the TOP of its step and a fade created by the callfunc itself
--     (before the task's first step, which runs the same frame) is flagged
--     `fresh` and skipped once. Same for `PokemonSprite_StartFade` and the
--     brightness controller.

local Gen4AnimMath = require("src.battle.Gen4AnimMath")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

local floor, abs, min, max = math.floor, math.abs, math.min, math.max

return function(Extras)
  local H = Extras.H
  local idiv, shr12 = Gen4AnimMath.idiv, Gen4AnimMath.shr12
  local posLerp, posLerpUpdate = Gen4AnimMath.posLerp, Gen4AnimMath.posLerpUpdate
  local scaleLerp, scaleLerpUpdate = Gen4AnimMath.scaleLerp, Gen4AnimMath.scaleLerpUpdate
  local valueLerp, valueLerpUpdate = Gen4AnimMath.valueLerp, Gen4AnimMath.valueLerpUpdate
  local revUpdate = Gen4AnimMath.revolutionUpdate
  local alphaFade, alphaFadeUpdate = Gen4AnimMath.alphaFade, Gen4AnimMath.alphaFadeUpdate
  local alphaFadeDone = Gen4AnimMath.alphaFadeDone
  local DEG = Gen4AnimMath.degToIdx
  local FX_ONE = Gen4AnimMath.FX32_ONE
  local AFFINE_ONE = Gen4AnimMath.AFFINE_ONE

  -- MON_SPRITE_FRAME_WIDTH / HEIGHT (10 tiles of 8 pixels, include/constants/graphics.h)
  local MON_FRAME_W, MON_FRAME_H = 80, 80
  local HALF_FRAME = MON_FRAME_H / 2
  -- REVOLUTION_CONTEXT_OVAL_RADIUS_Y_INT
  local OVAL_RY_INT = Gen4AnimMath.OVAL_RADIUS_Y_INT

  -- -------------------------------------------------------------------------
  -- Small shared pieces
  -- -------------------------------------------------------------------------

  local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
  end

  -- An ev coefficient -> drawn alpha (the hardware clamps at 16).
  local function evAlpha(ev)
    ev = tonumber(ev) or 0
    return max(0, min(16, ev)) / 16
  end

  -- `ValueLerpContext_InitFX32` / `UpdateFX32`: the fx32 accumulator variant,
  -- whose value is the floor of the accumulator (it does arrive).
  local function valueLerpFX(startV, endV, steps)
    return { value = startV, steps = steps,
             step = Gen4AnimMath.stepSize(startV * FX_ONE, endV * FX_ONE, steps),
             cur = startV * FX_ONE }
  end
  local function valueLerpFXUpdate(c)
    if c.steps ~= 0 then
      c.cur = c.cur + c.step
      c.value = shr12(c.cur)
      c.steps = c.steps - 1
      return true
    end
    return false
  end

  -- `BattleAnimUtil_GetRequiredSteps(a, b, stepSize)`, including FX_Modf's
  -- toward-zero split and the +1 on any fraction.
  local function requiredSteps(a, b, step)
    local q = Gen4AnimMath.fxDiv(b - a, step)
    local ip = (q >= 0) and floor(q / FX_ONE) * FX_ONE or -(floor(-q / FX_ONE) * FX_ONE)
    if q - ip ~= 0 then ip = ip + FX_ONE end
    return floor(abs(ip) / FX_ONE)
  end

  -- `RevolutionContext_InitWithStepSize` (u16 angles, u16 step negated when
  -- sx > ex and then read as s16).
  local function revolutionWithStep(sx, ex, sy, ey, rx, ry, stepU16)
    sx, ex, sy, ey = sx % 65536, ex % 65536, sy % 65536, ey % 65536
    local s = stepU16 % 65536
    if sx > ex then s = (-s) % 65536 end
    if s >= 32768 then s = s - 65536 end
    local steps = requiredSteps(sx * FX_ONE, ex * FX_ONE, s * FX_ONE)
    return { x = 0, y = 0, steps = steps, curX = sx, curY = sy, rx = rx, ry = ry,
             stepX = s, stepY = idiv(ey - sy, steps) }
  end

  -- `BattleAnimUtil_GetGroundAnchoredScaleOffset(baseY, height, scaleY)` --
  -- scaleY is the context's fx32 CUR_Y (256 * 4096 is 1.0). FX_Modf's two
  -- outputs are named the wrong way round in pret; the arithmetic is: the
  -- fraction, if any, gets +0.5, then `>> 12` and C `/ 2`.
  local function anchorOffset(height, scaleYFx)
    local avail = (MON_FRAME_H - height * 2) * FX_ONE
    local scaled = Gen4AnimMath.fxMul(avail, scaleYFx)
    local rel = Gen4AnimMath.fxDiv(scaled, AFFINE_ONE * FX_ONE)
    local diff = avail - rel
    local ip = (diff >= 0) and floor(diff / FX_ONE) * FX_ONE or -(floor(-diff / FX_ONE) * FX_ONE)
    local frac = diff - ip
    if frac ~= 0 then frac = frac + FX_ONE / 2 end
    return idiv(shr12(ip + frac), 2)
  end

  -- A bottom-anchored scale (`SetPokemonSpriteAnchoredPosition(..., ANCHOR_BOTTOM)`)
  -- as a dy on top of a draw that already pivots on the foot: the C's offset
  -- for this species' empty rows, less the offset a sprite with none would get
  -- (which is the foot pivot itself). 0 when the species offset is unknown.
  local function anchoredDy(height, scaleYFx)
    return anchorOffset(height, scaleYFx) - anchorOffset(0, scaleYFx)
  end

  -- A copy scaled about its centre, drawn by a foot-pivoting ghost.
  local function centreDy(sy) return HALF_FRAME * (sy - 1) end

  -- Which side a Pokemon-sprite copy slot shows, falling back when the program
  -- did not add one.
  local function copySide(player, slot, fallback)
    local rec = player.monSprites and player.monSprites[slot]
    if rec and rec.side ~= nil then return rec.side end
    return fallback
  end

  -- Sprite-record helpers (same meaning as the player's own locals).
  local function tick(s) s.animTick = (s.animTick or 0) + 1 end
  local function animDone(s) return (s.animTick or 0) >= (s.length or 0) end
  -- `ManagedSprite_SetAnim(sprite, n)`: switch sequence and restart it.
  local function setAnim(s, n)
    local seqs = s.art and s.art.sequences
    local seq = seqs and seqs[n + 1]
    if seq and seq.frames and #seq.frames > 0 then
      s.frames = seq.frames
      s.sequence = n
      s.length = Gen4CellAnim.length(seq.frames)
    end
    s.animTick = 0
  end
  -- `ManagedSprite_SetAnimationFrame(sprite, n)`: jump to frame n of the sequence.
  local function setAnimFrame(s, n)
    local t = 0
    for i = 1, min(n, #(s.frames or {})) do t = t + (s.frames[i].duration or 0) end
    s.animTick = t
  end

  -- =========================================================================
  -- 8 QuickAttack (BattleAnimScriptFunc_QuickAttack)
  --
  -- The attacker runs one oval revolution of 8 frames about a point 8 pixels
  -- below its centre (so the oval starts and ends at rest), and two copies
  -- trail it through a 10-frame oval, started 2 frames apart by the
  -- Afterimage context. The task lasts until the LAST after-image's
  -- revolution reports finished: 15 frames.
  -- =========================================================================
  local QA_REV_FRAMES, QA_AFTER_FRAMES = 8, 10
  local QA_AFTER_DELAY, QA_AFTER_COUNT = 2, 2
  -- SetSpriteBgBlending(-1, -1): the default sprite alpha, 26 -> clamped 16.
  local QA_GHOST_ALPHA = evAlpha(26)

  -- Afterimage_Init / Afterimage_Update with a revolution transform.
  local function afterimageInit(transform, delay, count)
    local a = { delay = delay, counter = 0, count = count, activeCount = 0,
                transforms = {}, drawn = {} }
    for i = 1, count do a.transforms[i] = copy(transform); a.drawn[i] = false end
    return a
  end
  local function afterimageUpdate(a)
    local active = { true, true, true, true }
    if a.delay <= a.counter then
      a.activeCount = a.activeCount + 1
      a.drawn[a.activeCount] = true
      a.counter = 0
    end
    if a.activeCount < a.count then a.counter = a.counter + 1 end
    for i = 1, a.activeCount do
      active[i] = revUpdate(a.transforms[i])
      if not active[i] then a.drawn[i] = false end
    end
    for i = 1, a.count do if active[i] then return true end end
    return false
  end

  Extras.FUNCS[8] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local dir = H.dirX(side)
    -- attackerY -= RADIUS_Y >> 12, i.e. the oval's centre is 8 pixels lower.
    local cy = baseY - OVAL_RY_INT
    local rev = Gen4AnimMath.ovalRevolution(1, QA_REV_FRAMES)
    local after = Gen4AnimMath.ovalRevolution(1, QA_AFTER_FRAMES)
    rev.rx = rev.rx * dir
    after.rx = after.rx * dir
    local ai = afterimageInit(after, QA_AFTER_DELAY, QA_AFTER_COUNT)
    H.task(player, function(p, t)
      local a0 = revUpdate(rev)
      if a0 then st.dx, st.dy = baseX + rev.x, cy + rev.y end
      local a1 = afterimageUpdate(ai)
      local ghosts = {}
      for i = 1, ai.count do
        if ai.drawn[i] then
          local tr = ai.transforms[i]
          ghosts[#ghosts + 1] = { dx = baseX + tr.x, dy = cy + tr.y,
                                  alpha = QA_GHOST_ALPHA, sx = 1, sy = 1 }
        end
      end
      st.ghosts = (#ghosts > 0) and ghosts or nil
      if a0 or a1 then return end
      st.dx, st.dy = baseX, cy + OVAL_RY_INT
      st.ghosts = nil
      t.done = true
    end)
  end

  -- =========================================================================
  -- 9 DrillPeck (BattleAnimScriptFunc_DrillPeck)
  --
  -- Back 32 over 3 frames, tilt 20 degrees over 8, hold 3, lunge back to rest
  -- over 2, hold 33, untilt over 4, cleanup: 3+1 / 8+1 / 3 / 2+1 / 33 / 4+1 / 1.
  -- The C pivots the rotation on the frame's front edge (x +-40, y +40); the
  -- port's `rot` turns about the centre, which is noted.
  -- =========================================================================
  local DP_MOVE_BWD_X, DP_MOVE_BWD_FRAMES = -32, 3
  local DP_ROT_FWD_FRAMES, DP_ROT_BWD_FRAMES = 8, 4
  local DP_MOVE_FWD_FRAMES = 2
  local DP_POST_ROT_DELAY, DP_POST_MOVE_DELAY = 2, 32

  Extras.FUNCS[9] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local dir = H.dirX(side)
    local pos = posLerp(0, DP_MOVE_BWD_X, 0, 0, DP_MOVE_BWD_FRAMES)
    local angle = valueLerp(0, DEG(20), DP_ROT_FWD_FRAMES)
    pos.stepX = pos.stepX * dir
    angle.step = angle.step * dir
    H.note(player, "DrillPeck: rotation pivot on the front edge drawn about the centre")
    H.task(player, function(p, t)
      local s = t.state
      if s == 0 then
        if posLerpUpdate(pos) then
          st.dx, st.dy = baseX + pos.x, baseY + pos.y
        else
          pos = posLerp(pos.x, 0, 0, 0, DP_MOVE_FWD_FRAMES)
          t.state = 1
        end
      elseif s == 1 then
        if valueLerpUpdate(angle) then
          st.rot = H.radians(angle.value)
        else
          angle = valueLerp(angle.value, 0, DP_ROT_BWD_FRAMES)
          t.state = 2
          t.delay = DP_POST_ROT_DELAY
        end
      elseif s == 2 then
        t.delay = t.delay - 1
        if t.delay < 0 then t.state = 3 end
      elseif s == 3 then
        if posLerpUpdate(pos) then
          st.dx, st.dy = baseX + pos.x, baseY + pos.y
        else
          t.state = 4
          t.delay = DP_POST_MOVE_DELAY
        end
      elseif s == 4 then
        t.delay = t.delay - 1
        if t.delay < 0 then t.state = 5 end
      elseif s == 5 then
        if valueLerpUpdate(angle) then
          st.rot = H.radians(angle.value)
        else
          t.state = 6
        end
      else
        st.dx, st.dy, st.rot = baseX, baseY, 0
        t.done = true
      end
    end, { state = 0, delay = 0 })
  end

  -- =========================================================================
  -- 11 Confusion (BattleAnimScriptFunc_Confusion)
  --
  -- The defender shakes (2 px, every frame, 6 cycles) while a translucent copy
  -- of it swells to 1.2 x 1.5 over 7 frames and back over 4, its X scale
  -- jittering +-0.1 every frame. GROW is 7 + 1 frames, SHRINK 4 + 1, cleanup 1.
  -- The copy is scaled about its centre (AFFINE DOUBLE).
  -- =========================================================================
  local CONF_SCALE_FRAMES, CONF_SCALE_BACK_FRAMES = 7, 4
  local CONF_JITTER = 0.1
  local CONF_ALPHA = evAlpha(28)     -- SetSpriteBgBlending(28, 15)

  Extras.FUNCS[11] = function(player)
    local side = H.defender(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local shake = H.shake(2, 0, 1, 6)
    local scale = H.scaleXY(10, 12, 10, 15, 10, CONF_SCALE_FRAMES)
    local jitter = 1
    local function apply()
      st.dx, st.dy = baseX + shake.x, baseY + shake.y
      local sx = scale.x / AFFINE_ONE + jitter * CONF_JITTER
      local sy = scale.y / AFFINE_ONE
      st.ghosts = { { dx = baseX + shake.x, dy = baseY + shake.y + centreDy(sy),
                      alpha = CONF_ALPHA, sx = sx, sy = sy } }
      jitter = -jitter
    end
    H.task(player, function(p, t)
      if t.state == 0 then
        H.shakeUpdate(shake)
        local active = H.scaleXYUpdate(scale)
        apply()
        if not active then
          scale = H.scaleXY(12, 10, 15, 10, 10, CONF_SCALE_BACK_FRAMES)
          t.state = 1
        end
      elseif t.state == 1 then
        H.shakeUpdate(shake)
        local active = H.scaleXYUpdate(scale)
        apply()
        if not active then
          st.dx, st.dy = baseX, baseY
          t.state = 2
        end
      else
        st.ghosts = nil
        t.done = true
      end
    end, { state = 0 })
  end

  -- =========================================================================
  -- 12 AcidArmor (BattleAnimScriptFunc_AcidArmor)
  --
  -- The C hides the attacker and melts its copy in BG_BASE (loaded by the
  -- program's `loadpokemonspriteintobg`) with a per-scanline offset table:
  -- rows are pulled down toward the frame's bottom by pos.y/100 (pos 0 -> 40
  -- over 24 frames) and sheared by pos.x/100 (0 -> 80*dir), on top of a sine
  -- wave (amplitude 8*dir, 5 degrees per line). Then the copy fades out (BG
  -- blend ev1 31 -> 0 over 16), the plain offsets come back, 9 frames, it fades
  -- in (16) and the attacker is shown.
  --
  -- REPRESENTED ON THE BATTLER ITSELF (not hidden): the vertical pull as a
  -- squash `sy = 1 / (1 + pos.y/100)` pivoting on the foot, the fades as
  -- `alpha`. The shear and the wave are not drawn (noted).
  --
  -- The C runs the task body once inline from the callfunc AND starts the
  -- task, so the first frame steps twice -- reproduced.
  -- =========================================================================
  local AA_MOVE_X, AA_MOVE_Y, AA_MOVE_FRAMES = 80, 40, 24
  local AA_FADE_FRAMES, AA_FADE_DELAY = 16, 8

  Extras.FUNCS[12] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local dir = H.dirX(side)
    local pos = posLerp(0, AA_MOVE_X, 0, AA_MOVE_Y, AA_MOVE_FRAMES)
    pos.stepX = pos.stepX * dir
    H.note(player, "AcidArmor: BG copy's scanline shear and sine wave not drawn (squash + fade on the battler)")
    local function scroll()
      local active = posLerpUpdate(pos)
      st.sy = 1 / (1 + pos.y / 100)
      return active
    end
    local function step(p, t)
      if t.fade then alphaFadeUpdate(t.fade) end
      if t.state == 0 then
        if not scroll() then
          t.state = 1
          -- SetEffectBaseBgBlending(31, 0): the copy fully up.
          st.alpha = evAlpha(31)
          t.fade = alphaFade(31, 0, 0, 31, AA_FADE_FRAMES)
        end
      elseif t.state == 1 then
        scroll()
        if t.fade then st.alpha = Gen4AnimMath.blendAlpha(t.fade) end
        if alphaFadeDone(t.fade) then
          t.state = 2
          t.delay = 0
          -- BgScrollContext_Stop, then WAIT writes the plain offsets.
          st.sy = 1
        end
      elseif t.state == 2 then
        st.sy = 1
        t.delay = t.delay + 1
        if t.delay > AA_FADE_DELAY then
          t.fade = alphaFade(0, 31, 31, 0, AA_FADE_FRAMES)
          t.state = 3
        end
      elseif t.state == 3 then
        st.alpha = Gen4AnimMath.blendAlpha(t.fade)
        if alphaFadeDone(t.fade) then
          -- MON_SPRITE_HIDE FALSE: the real attacker is back.
          st.alpha = 1
          t.state = 4
        end
      else
        st.sy, st.alpha = 1, 1
        t.done = true
      end
    end
    local t = H.task(player, step, { state = 0, delay = 0 })
    step(player, t)
  end

  -- =========================================================================
  -- 17 NightShadeAttacker (BattleAnimScriptFunc_NightShadeAttacker)
  --
  -- Copy slot 0 (the attacker's copy in move 101) is drawn at 1.4x, fading in
  -- (ev1 0 -> 16 over 8), holds 33 frames, shrinks to 1.0x over 8 and is
  -- hidden: 9 + 33 + 9 + 1 frames. Scaled about its centre.
  -- =========================================================================
  local NSA_ALPHA_FRAMES, NSA_SCALE_FRAMES, NSA_SCALE_DELAY = 8, 8, 32
  local NSA_START_SCALE_F = 14 / 10

  Extras.FUNCS[17] = function(player)
    local side = copySide(player, 0, H.attacker(player))
    local st = H.state(player, side)
    local scale = scaleLerp(14, 10, 10, NSA_SCALE_FRAMES)
    local alpha = valueLerpFX(0, 16, NSA_ALPHA_FRAMES)
    local ghost = { dx = 0, dy = centreDy(NSA_START_SCALE_F), alpha = evAlpha(0),
                    sx = NSA_START_SCALE_F, sy = NSA_START_SCALE_F }
    st.ghosts = { ghost }
    H.task(player, function(p, t)
      if t.state == 0 then
        local active = valueLerpFXUpdate(alpha)
        ghost.alpha = evAlpha(alpha.value)
        if not active then t.state = 1; t.delay = 0 end
      elseif t.state == 1 then
        t.delay = t.delay + 1
        if t.delay > NSA_SCALE_DELAY then t.state = 2 end
      elseif t.state == 2 then
        local active = scaleLerpUpdate(scale)
        ghost.sx, ghost.sy = scale.x / AFFINE_ONE, scale.y / AFFINE_ONE
        ghost.dy = centreDy(ghost.sy)
        if not active then
          st.ghosts = nil
          t.state = 3
        end
      else
        st.ghosts = nil
        t.done = true
      end
    end, { state = 0, delay = 0 })
  end

  -- =========================================================================
  -- 18 NightShadeDefender (BattleAnimScriptFunc_NightShadeDefender)
  --
  -- The defender shakes (4 px, every frame) while its palette fades to black
  -- (0 -> 16, one step a frame) and back; the task ends the frame after the
  -- fade back is over. pret's BUG is kept: `shake.x += dir` instead of scaling
  -- the extent, so the shake starts one pixel off and its waveform is
  -- (dir, 4, -dir, -4, ...). The doubles-only copy branch is unreachable in
  -- a single battle.
  -- =========================================================================
  Extras.FUNCS[18] = function(player)
    local side = H.defender(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local shake = H.shake(4, 0, 1, 4)
    shake.x = shake.x + H.dirX(side)
    local fade = H.monFade(player, side, 0, 16, 0, H.BLACK)
    local fresh = true
    H.task(player, function(p, t)
      if not fresh then H.monFadeUpdate(p, fade) end
      fresh = false
      if t.state == 0 then
        H.shakeUpdate(shake)
        st.dx, st.dy = baseX + shake.x, baseY + shake.y
        if not Gen4AnimMath.monFadeActive(fade) then
          -- Started from inside the task: pumped from the next step on.
          fade = H.monFade(p, side, 16, 0, 0, H.BLACK)
          t.state = 1
        end
      elseif t.state == 1 then
        H.shakeUpdate(shake)
        st.dx, st.dy = baseX + shake.x, baseY + shake.y
        if not Gen4AnimMath.monFadeActive(fade) then
          st.dx, st.dy = baseX, baseY
          t.state = 2
        end
      else
        st.tint = nil
        t.done = true
      end
    end, { state = 0 })
  end

  -- =========================================================================
  -- 20 Spite (BattleAnimScriptFunc_Spite)
  --
  -- The defender's copy (in BG_BASE via `loadpokemonspriteintobg`, its palette
  -- blended 8/16 toward black) fades in over the defender (ev1 0 -> 8, ev2 16 ->
  -- 8 over 24 frames), wobbles on a scanline sine wave (amplitude 5, 5 degrees a
  -- line) for 33 frames, and fades out the same way. In a single battle the
  -- real defender stays visible underneath.
  --
  -- REPRESENTED as the defender's `brightness`: a half-black copy at ev1/16 over
  -- the defender at (16 - ev1)/16 is the defender at 1 - ev1/32. The scanline
  -- wave is not drawn (noted).
  -- =========================================================================
  local SPITE_FADE_FRAMES, SPITE_SCROLL_DURATION = 24, 32

  Extras.FUNCS[20] = function(player)
    local side = H.defender(player)
    local st = H.state(player, side)
    local fade = alphaFade(0, 8, 16, 8, SPITE_FADE_FRAMES)
    local fresh = true
    H.note(player, "Spite: BG copy's scanline sine wave not drawn (darkening only)")
    local function apply() st.brightness = 1 - max(0, min(16, fade.x)) / 32 end
    -- Returns true when the fade sequence has finished (SpiteContext_UpdateFade).
    local function updateFade(t)
      if t.sub == 0 then
        if alphaFadeDone(fade) then
          t.sub = 1
          t.delay = SPITE_SCROLL_DURATION
        end
      elseif t.sub == 1 then
        t.delay = t.delay - 1
        if t.delay < 0 then
          t.sub = 2
          fade = alphaFade(8, 0, 8, 16, SPITE_FADE_FRAMES)
        end
      elseif t.sub == 2 then
        if alphaFadeDone(fade) then t.sub = 3 end
      else
        return true
      end
      return false
    end
    H.task(player, function(p, t)
      if not fresh then alphaFadeUpdate(fade) end
      fresh = false
      apply()
      if t.state == 0 then
        updateFade(t)
        t.state = 1
      elseif t.state == 1 then
        if updateFade(t) then t.state = 2 end
      else
        st.brightness = 1
        t.done = true
      end
    end, { state = 0, sub = 0, delay = 0 })
  end

  -- =========================================================================
  -- 23 FaintAttack (BattleAnimScriptFunc_FaintAttack)
  --
  -- The attacker is hidden; its copy (slot 0) runs two 16-frame oval
  -- revolutions about a point 8 px below centre while fading out (16 -> 0 over
  -- 32), waits 17 frames, fades back in (32) and the attacker is shown.
  -- =========================================================================
  local FA_REV_COUNT, FA_REV_FRAMES = 2, 16
  local FA_FADE_FRAMES, FA_FADE_IN_DELAY = 32, 16

  Extras.FUNCS[23] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local dir = H.dirX(side)
    local cy = -OVAL_RY_INT
    local revs = Gen4AnimMath.ovalRevolution(FA_REV_COUNT, FA_REV_FRAMES)
    revs.rx = revs.rx * dir
    local fade = alphaFade(16, 0, 0, 16, FA_FADE_FRAMES)
    local fresh = true
    local ghost = { dx = 0, dy = 0, alpha = evAlpha(16), sx = 1, sy = 1 }
    st.hidden = true
    st.ghosts = { ghost }
    H.task(player, function(p, t)
      if not fresh then alphaFadeUpdate(fade) end
      fresh = false
      ghost.alpha = Gen4AnimMath.blendAlpha(fade)
      if t.state == 0 then
        if revUpdate(revs) then
          ghost.dx, ghost.dy = revs.x, cy + revs.y
        else
          t.state = 1
          t.delay = FA_FADE_IN_DELAY
        end
      elseif t.state == 1 then
        t.delay = t.delay - 1
        if t.delay < 0 then
          t.state = 2
          fade = alphaFade(0, 16, 16, 0, FA_FADE_FRAMES)
        end
      elseif t.state == 2 then
        if alphaFadeDone(fade) then
          st.hidden = false
          t.state = 3
        end
      else
        st.ghosts = nil
        t.done = true
      end
    end, { state = 0, delay = 0 })
  end

  -- =========================================================================
  -- 25 PlayfulHops (BattleAnimScriptFunc_PlayfulHops)
  --
  -- Four hops: tilt 15 degrees (fx32 lerp over 3, alternating sign), dip 2 px
  -- over 2 frames while the tilt finishes, come back up over 2 while untilting
  -- over 3. var 0 picks the battler (0 = attacker). The C pivots the tilt at
  -- (+-16, 50) from the centre; `rot` turns about the centre (noted).
  -- =========================================================================
  local PH_TILT_FRAMES, PH_HOP_Y, PH_HOP_FRAMES, PH_HOP_COUNT = 3, 2, 2, 4

  Extras.FUNCS[25] = function(player)
    local target = H.var(player, 0)
    local side = (target == 0) and H.attacker(player) or H.defender(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local c = { hopCount = 0, flip = H.dirX(H.attacker(player)) ~= 1 }
    H.note(player, "PlayfulHops: tilt pivot (+-16, 50) drawn about the centre")
    local function initTilt(flip)
      c.angle = valueLerpFX(0, DEG(15), PH_TILT_FRAMES)
      if flip then c.angle.step = -c.angle.step end
      c.hopState = 0
      c.hopDelay = 0
    end
    local function updateHop()
      if c.hopState == 0 then
        valueLerpFXUpdate(c.angle)
        st.rot = H.radians(c.angle.value)
        c.hopDelay = c.hopDelay - 1
        if c.hopDelay < 0 then
          c.hopState = 1
          c.pos = posLerp(0, 0, 0, PH_HOP_Y, PH_HOP_FRAMES)
        end
      elseif c.hopState == 1 then
        if valueLerpFXUpdate(c.angle) then st.rot = H.radians(c.angle.value) end
        if posLerpUpdate(c.pos) then
          st.dx, st.dy = baseX + c.pos.x, baseY + c.pos.y
        else
          c.hopState = 2
          c.angle = valueLerpFX(c.angle.value, 0, PH_TILT_FRAMES)
          c.pos = posLerp(0, 0, PH_HOP_Y, 0, PH_HOP_FRAMES)
        end
      elseif c.hopState == 2 then
        if posLerpUpdate(c.pos) then st.dx, st.dy = baseX + c.pos.x, baseY + c.pos.y end
        if valueLerpFXUpdate(c.angle) then
          st.rot = H.radians(c.angle.value)
        else
          st.dx, st.dy, st.rot = baseX, baseY, 0
          c.hopState = 3
        end
      else
        return true
      end
      return false
    end
    initTilt(c.flip)
    H.task(player, function(p, t)
      if t.state == 0 then
        if updateHop() then
          c.hopCount = c.hopCount + 1
          if c.hopCount < PH_HOP_COUNT then
            c.flip = not c.flip
            initTilt(c.flip)
            updateHop()
          else
            t.state = 1
          end
        end
      else
        t.done = true
      end
    end, { state = 0 })
  end

  -- =========================================================================
  -- 29 Return (BattleAnimScriptFunc_Return)
  --
  -- Four 6-frame moves of the attacker, down 32 and back twice (each move is
  -- one init frame, 6 steps and one finishing frame): 33 frames.
  --
  -- FRIENDSHIP: pret's function does NOT read it -- the program chooses
  -- between its versions with a script-level branch on
  -- BattleAnimSystem_GetMoveInfo(FRIENDSHIP). Should a caller want it, it is
  -- `player.moveInfo and player.moveInfo.friendship or 255` (255 = the full
  -- version); this function ignores it, as the cartridge's does.
  -- =========================================================================
  local RET_END_Y, RET_FRAMES, RET_COUNT = 32, 6, 4

  Extras.FUNCS[29] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local baseX, baseY = st.dx or 0, st.dy or 0
    local pos
    H.task(player, function(p, t)
      if t.state == 0 then
        if t.count % 2 == 0 then
          pos = posLerp(0, 0, 0, RET_END_Y, RET_FRAMES)
        else
          pos = posLerp(0, 0, RET_END_Y, 0, RET_FRAMES)
        end
        t.state = 1
      elseif t.state == 1 then
        if posLerpUpdate(pos) then
          st.dx, st.dy = baseX + pos.x, baseY + pos.y
        else
          t.count = t.count + 1
          t.state = (t.count < RET_COUNT) and 0 or 2
        end
      else
        t.done = true
      end
    end, { state = 0, count = 0 })
  end

  -- =========================================================================
  -- 30 VitalThrow (BattleAnimScriptFunc_VitalThrow)
  --
  -- Init frame, one 64-frame oval revolution of the attacker (centre 8 px
  -- lower), a 2-frame lunge of 32 px (the first step taken inline), the
  -- defender knocked 32 px over 2, attacker back over 8, defender back over 8.
  -- pret's `attackerPos.data[XY_PARAM_REV_CUR_X] *= dir` lands on the PosLerp's
  -- STEP_SIZE_X (same index), which is what makes the lunge go the right way.
  -- =========================================================================
  local VT_REV_FRAMES, VT_MOVE_X, VT_MOVE_FRAMES, VT_BACK_FRAMES = 64, 32, 2, 8

  Extras.FUNCS[30] = function(player)
    local aSide, dSide = H.attacker(player), H.defender(player)
    local a, d = H.state(player, aSide), H.state(player, dSide)
    local aX, aY = a.dx or 0, a.dy or 0
    local dX = d.dx or 0
    local dir = H.dirX(aSide)
    local apos, dpos
    H.task(player, function(p, t)
      local s = t.state
      if s == 0 then
        apos = Gen4AnimMath.ovalRevolution(1, VT_REV_FRAMES)
        apos.rx = apos.rx * dir
        t.state = 1
      elseif s == 1 then
        if revUpdate(apos) then
          a.dx, a.dy = aX + apos.x, aY - OVAL_RY_INT + apos.y
        else
          a.dx, a.dy = aX, aY
          apos = posLerp(0, VT_MOVE_X, 0, 0, VT_MOVE_FRAMES)
          apos.stepX = apos.stepX * dir
          t.state = 2
          posLerpUpdate(apos)
          a.dx = aX + apos.x
        end
      elseif s == 2 then
        if posLerpUpdate(apos) then
          a.dx = aX + apos.x
        else
          dpos = posLerp(0, VT_MOVE_X * dir, 0, 0, VT_MOVE_FRAMES)
          t.state = 3
        end
      elseif s == 3 then
        if posLerpUpdate(dpos) then
          d.dx = dX + dpos.x
        else
          apos = posLerp(apos.x, 0, 0, 0, VT_BACK_FRAMES)
          t.state = 4
        end
      elseif s == 4 then
        if posLerpUpdate(apos) then
          a.dx = aX + apos.x
        else
          a.dx = aX
          dpos = posLerp(dpos.x, 0, 0, 0, VT_BACK_FRAMES)
          t.state = 5
        end
      elseif s == 5 then
        if posLerpUpdate(dpos) then
          d.dx = dX + dpos.x
        else
          d.dx = dX
          t.state = 6
        end
      else
        t.done = true
      end
    end, { state = 0 })
  end

  -- =========================================================================
  -- 31 Swagger (BattleAnimScriptFunc_Swagger)
  --
  -- The attacker swells 1.0 -> 1.5 over 8 frames, holds 5, shrinks over 8,
  -- the scale is written back to exactly 1.0, then 17 frames of wait:
  -- 9 + 5 + 9 + 1 + 17 + 1 frames. Bottom-anchored with the species' sprite
  -- offset (`H.spriteOffset`), expressed as the residue over the foot pivot.
  -- =========================================================================
  local SW_FRAMES, SW_SCALE_DELAY, SW_END_DELAY = 8, 4, 16

  Extras.FUNCS[31] = function(player)
    local side = H.attacker(player)
    local st = H.state(player, side)
    local baseY = st.dy or 0
    local height = H.spriteOffset(player, side)
    local scale = scaleLerp(10, 10, 15, SW_FRAMES)
    local function apply()
      st.sx, st.sy = scale.x / AFFINE_ONE, scale.y / AFFINE_ONE
      st.dy = baseY + anchoredDy(height, scale.curY)
    end
    local function updateScale(t)
      if t.sub == 0 then
        if scaleLerpUpdate(scale) then apply() else t.sub = 1 end
      elseif t.sub == 1 then
        t.scaleDelay = t.scaleDelay - 1
        if t.scaleDelay < 0 then
          t.sub = 2
          scale = scaleLerp(15, 10, 10, SW_FRAMES)
        end
      elseif t.sub == 2 then
        if scaleLerpUpdate(scale) then apply() else t.sub = 3 end
      else
        st.sx, st.sy = 1, 1
        return true
      end
      return false
    end
    H.task(player, function(p, t)
      if t.state == 0 then
        if updateScale(t) then
          t.state = 1
          t.delay = SW_END_DELAY
        end
      elseif t.state == 1 then
        t.delay = t.delay - 1
        if t.delay < 0 then t.state = 2 end
      else
        t.done = true
      end
    end, { state = 0, sub = 0, scaleDelay = SW_SCALE_DELAY, delay = 0 })
  end

  -- =========================================================================
  -- 32 Memento (BattleAnimScriptFunc_Memento)
  --
  -- Two half-black (palette blend 8/16) translucent copies: the ATTACKER's
  -- (slot 0) stretches to 2x tall over 7 frames and squashes to 0.1x wide over
  -- 4 and vanishes; 3 frames later the DEFENDER's (slot 1, pivoting on its
  -- foot via the affine translation) drops in from 64 px above, 0.2 x 2.0 ->
  -- 1.0 x 1.0, over 8. The copies' blend fades ev1 0 -> 8 before and 8 -> 0
  -- after (8 frames each).
  -- =========================================================================
  local MEM_FADE_FRAMES = 8
  local MEM_STRETCH_FRAMES, MEM_SQUISH_FRAMES, MEM_SQUISH_DELAY = 8, 4, 6
  local MEM_DEF_Y_OFFSET, MEM_DEF_FRAMES, MEM_DEF_SCALE_DELAY = 64, 8, 6
  local MEM_DEF_DELAY = 2
  local MEM_TINT = { 0, 0, 0, 8 / 16 }

  Extras.FUNCS[32] = function(player)
    local aSide, dSide = H.attacker(player), H.defender(player)
    local a, d = H.state(player, aSide), H.state(player, dSide)
    local height = H.spriteOffset(player, aSide)
    local fade, scale, scaleX, dpos
    local aGhost, dGhost
    local function alpha() return fade and Gen4AnimMath.blendAlpha(fade) or 0 end
    local function applyAttacker()
      local sx, sy = scale.x / AFFINE_ONE, scale.y / AFFINE_ONE
      aGhost.sx, aGhost.sy = sx, sy
      -- SetSpriteAnchoredPosition(BOTTOM) on a centre-scaled copy, as an
      -- offset for a foot-pivoting ghost.
      aGhost.dy = anchorOffset(height, scale.curY) + centreDy(sy)
    end
    local function applyDefender()
      dGhost.sx, dGhost.sy = scale.x / AFFINE_ONE, scale.y / AFFINE_ONE
    end
    H.task(player, function(p, t)
      if fade then alphaFadeUpdate(fade) end
      if aGhost then aGhost.alpha = alpha() end
      if dGhost then dGhost.alpha = alpha() end
      local s = t.state
      if s == 0 then
        fade = alphaFade(0, 8, 16, 8, MEM_FADE_FRAMES)
        t.state = 1
      elseif s == 1 then
        if alphaFadeDone(fade) then
          t.state = 2
          -- MementoContext_InitAttacker
          scale = H.scaleXY(10, 10, 10, 20, 10, MEM_STRETCH_FRAMES)
          scaleX = scaleLerp(10, 10, 1, MEM_SQUISH_FRAMES)
          t.sub = 0
          t.subDelay = MEM_SQUISH_DELAY
          aGhost = { dx = 0, dy = 0, alpha = alpha(), sx = 1, sy = 1, tint = MEM_TINT }
          a.ghosts = { aGhost }
          aGhost.sx, aGhost.sy = scale.x / AFFINE_ONE, scale.y / AFFINE_ONE
        end
      elseif s == 2 then
        local done = false
        if t.sub == 0 then
          H.scaleXYUpdate(scale)
          applyAttacker()
          t.subDelay = t.subDelay - 1
          if t.subDelay < 0 then
            t.sub = 1
            scale = H.scaleXY(10, 1, 20, 20, 10, MEM_SQUISH_FRAMES)
          end
        elseif t.sub == 1 then
          H.scaleXYUpdate(scale)
          if scaleLerpUpdate(scaleX) then
            scale.x = scaleX.x
            applyAttacker()
          else
            t.sub = 2
            a.ghosts = nil
            aGhost = nil
            done = true
          end
        else
          done = true
        end
        if done then
          t.state = 3
          t.delay = MEM_DEF_DELAY
        end
      elseif s == 3 then
        t.delay = t.delay - 1
        if t.delay < 0 then
          -- MementoContext_InitDefender
          dpos = posLerp(0, 0, -MEM_DEF_Y_OFFSET, 0, MEM_DEF_FRAMES)
          scale = H.scaleXY(2, 10, 20, 10, 10, MEM_DEF_FRAMES)
          dGhost = { dx = 0, dy = 0, alpha = alpha(), sx = 1, sy = 1, tint = MEM_TINT }
          applyDefender()
          posLerpUpdate(dpos)
          dGhost.dx, dGhost.dy = dpos.x, dpos.y
          d.ghosts = { dGhost }
          t.sub = 0
          t.subDelay = MEM_DEF_SCALE_DELAY
          t.state = 4
        end
      elseif s == 4 then
        if t.sub == 0 then
          t.subDelay = t.subDelay - 1
          if posLerpUpdate(dpos) then dGhost.dx, dGhost.dy = dpos.x, dpos.y end
          if t.subDelay < 0 then t.sub = 1 end
        elseif t.sub == 1 then
          if posLerpUpdate(dpos) then dGhost.dx, dGhost.dy = dpos.x, dpos.y end
          local active = H.scaleXYUpdate(scale)
          applyDefender()
          if not active then
            t.sub = 2
            t.state = 5
            fade = alphaFade(8, 0, 8, 16, MEM_FADE_FRAMES)
          end
        else
          t.state = 5
          fade = alphaFade(8, 0, 8, 16, MEM_FADE_FRAMES)
        end
      elseif s == 5 then
        if alphaFadeDone(fade) then t.state = 6 end
      else
        a.ghosts, d.ghosts = nil, nil
        t.done = true
      end
    end, { state = 0, sub = 0, subDelay = 0, delay = 0 })
  end

  -- =========================================================================
  -- SPRITE CALLBACKS
  -- =========================================================================

  -- -------------------------------------------------------------------------
  -- 2 Kinesis (BattleAnimSpriteFunc_Kinesis) -- three spoons from one template
  --
  -- The spoon fades in at the attacker (31 frames, ev1 = alpha/10), then it
  -- and two copies started 8 frames apart sweep half an ellipse (90 -> 270
  -- degrees, 10 degrees a step wobbled +-1 by a cosine), then back to 180;
  -- the copies vanish as they finish, the spoon plays its bend animation and
  -- fades out (31 frames).
  -- -------------------------------------------------------------------------
  local KIN_REV_STEP = DEG(10)
  local KIN_ALPHA_SCALE, KIN_SPOON_END_ALPHA = 10, 31
  local KIN_STAGGER = 8
  local KIN_EXTRA = 2

  local function kinesisSpoonUpdate(sp)
    if not sp.active then return true end
    if sp.state == 0 or sp.state == 1 then
      if revUpdate(sp.revs) then
        H.sinLerpUpdate(sp.cos)
        sp.revs.stepX = sp.revStepSizeX + sp.cos.value
        sp.rec.absoluteX = sp.posX + sp.revs.x
        sp.rec.absoluteY = sp.posY + sp.revs.y
      else
        if sp.state < 1 then
          local r = sp.revs
          sp.revs = revolutionWithStep(r.curX, DEG(180), r.curX, DEG(180), r.rx, r.ry, KIN_REV_STEP)
          sp.cos = H.sinLerp(0, DEG(360), -FX_ONE, sp.revs.steps)
        end
        sp.state = sp.state + 1
      end
      return true
    end
    return false
  end

  Extras.SPRITES[2] = {
    name = "Kinesis",
    count = 1 + KIN_EXTRA,
    start = function(ctx)
      local dir = H.dirX(ctx.attackerIsPlayer)
      local ax, ay = ctx.pos.attacker.x, ctx.pos.attacker.y
      local revs = revolutionWithStep(DEG(90), DEG(270), DEG(90), DEG(270),
                                      dir * (-32 * FX_ONE), -8 * FX_ONE, KIN_REV_STEP)
      local main = { rec = ctx.sprites[1], revs = revs,
                     cos = H.sinLerp(0, DEG(360), -FX_ONE, revs.steps),
                     revStepSizeX = revs.stepX, posX = ax, posY = ay,
                     state = 0, active = true }
      main.rec.absoluteX, main.rec.absoluteY = ax, ay
      main.rec.alpha = evAlpha(0)
      ctx.spoon = main
      ctx.extras = {}
      for i = 1, KIN_EXTRA do
        local rec = ctx.sprites[1 + i]
        rec.absoluteX, rec.absoluteY = ax, ay
        rec.visible = false
        rec.alpha = evAlpha(0)
        ctx.extras[i] = { rec = rec, revs = copy(main.revs), cos = copy(main.cos),
                          revStepSizeX = main.revStepSizeX, posX = ax, posY = ay,
                          state = main.state, active = false }
      end
      ctx.state, ctx.delay, ctx.activeSpoon, ctx.spoonAlpha = 0, KIN_STAGGER, 0, 0
    end,
    step = function(ctx)
      local main = ctx.spoon
      local function blend()
        local a = evAlpha(floor(ctx.spoonAlpha / KIN_ALPHA_SCALE))
        main.rec.alpha = a
        for _, e in ipairs(ctx.extras) do e.rec.alpha = a end
      end
      local s = ctx.state
      if s == 0 then
        kinesisSpoonUpdate(main)
        ctx.state = 1
      elseif s == 1 then
        ctx.spoonAlpha = ctx.spoonAlpha + KIN_ALPHA_SCALE
        blend()
        if ctx.spoonAlpha >= KIN_SPOON_END_ALPHA * KIN_ALPHA_SCALE then
          main.rec.alpha = 1        -- OAM mode NORMAL
          ctx.state = 2
        end
      elseif s == 2 then
        -- G2_ChangeBlendAlpha(-1, -1): 31, clamped -> opaque.
        for _, e in ipairs(ctx.extras) do e.rec.alpha = 1 end
        ctx.state = 3
      elseif s == 3 then
        if ctx.delay <= 0 then
          local e = ctx.extras[ctx.activeSpoon + 1]
          if e then
            e.active = true
            e.rec.visible = true
          end
          ctx.activeSpoon = ctx.activeSpoon + 1
          ctx.delay = KIN_STAGGER
        end
        if ctx.activeSpoon < KIN_EXTRA then ctx.delay = ctx.delay - 1 end
        local any = kinesisSpoonUpdate(main)
        for _, e in ipairs(ctx.extras) do
          local active = kinesisSpoonUpdate(e)
          if not active then e.rec.visible = false end
          any = any or active
        end
        if not any then ctx.state = 4 end
      elseif s == 4 then
        tick(main.rec)
        if animDone(main.rec) then ctx.state = 5 end
      elseif s == 5 then
        ctx.spoonAlpha = ctx.spoonAlpha - KIN_ALPHA_SCALE
        blend()
        if ctx.spoonAlpha <= 0 then ctx.state = 6 end
      else
        return false
      end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- 4 Metronome (BattleAnimSpriteFunc_Metronome)
  --
  -- The finger appears 40 px in front of the attacker, grows 0.1 -> 1.0 over
  -- 8, wags (359 -> 320 degrees, or 0 -> 40 facing left) over 4 frames, then
  -- back and forth five more times, shrinks over 8 and is deleted. Its
  -- animation is never ticked. The affine translation (-12*dir, 12) moves the
  -- rotation/scale pivot, which this sprite layer cannot express.
  -- -------------------------------------------------------------------------
  local MET_OFFSET_X, MET_SCALE_FRAMES, MET_ROT_FRAMES, MET_WAGGLES = 40, 8, 4, 5

  Extras.SPRITES[4] = {
    name = "Metronome",
    count = 1,
    start = function(ctx)
      local dir = H.dirX(ctx.attackerIsPlayer)
      local s = ctx.sprites[1]
      ctx.tdir = dir
      s.origin = "attacker"
      s.sx, s.sy = MET_OFFSET_X * dir, 0
      s.scaleX, s.scaleY = 1, 1
      ctx.scale = scaleLerp(1, 10, 10, MET_SCALE_FRAMES)
      if dir >= 0 then
        ctx.angle = valueLerp(DEG(359), DEG(320), MET_ROT_FRAMES)
        ctx.nextEnd = DEG(359)
      else
        ctx.angle = valueLerp(DEG(0), DEG(40), MET_ROT_FRAMES)
        ctx.nextEnd = DEG(0)
      end
      ctx.state, ctx.counter = 0, 0
      H.note(ctx.player, "Metronome: affine pivot offset (-12*dir, 12) not applied")
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      if ctx.state == 0 then
        if scaleLerpUpdate(ctx.scale) then
          s.scaleX, s.scaleY = ctx.scale.x / AFFINE_ONE, ctx.scale.y / AFFINE_ONE
        else
          ctx.state = 1
          ctx.counter = MET_WAGGLES
          ctx.scale = scaleLerp(10, 10, 1, MET_SCALE_FRAMES)
        end
      elseif ctx.state == 1 then
        local active = valueLerpUpdate(ctx.angle)
        s.rotation = H.radians(ctx.angle.value)
        if not active then
          if ctx.counter > 0 then
            ctx.counter = ctx.counter - 1
            local startA, endA = ctx.angle.value, ctx.nextEnd
            ctx.nextEnd = ctx.angle.value
            ctx.angle = valueLerp(startA, endA, MET_ROT_FRAMES)
          else
            ctx.state = 2
          end
        end
      elseif ctx.state == 2 then
        if scaleLerpUpdate(ctx.scale) then
          s.scaleX, s.scaleY = ctx.scale.x / AFFINE_ONE, ctx.scale.y / AFFINE_ONE
        else
          ctx.state = 3
        end
      else
        return false
      end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- 5 Constrict (BattleAnimSpriteFunc_Constrict) -- four vines from one template
  --
  -- Four vines stacked up the defender (16, 6, -4, -14 px from its centre,
  -- alternately mirrored) appear 4 frames apart and animate; the defender
  -- shakes once (4 px, 4 flips); then all four squeeze their width 1.0 -> 0.8
  -- -> 1.0 -> 0.8 -> 1.0 (8 frames each). pret's `active =` (not `|=`) bug
  -- means only the last vine decides, harmless as they run in lockstep.
  -- -------------------------------------------------------------------------
  local CON_COUNT, CON_BASE_Y, CON_STEP_Y = 4, 16, 10
  local CON_STAGGER, CON_SCALE_FRAMES, CON_SCALE_COUNT = 4, 8, 3

  local function constrictVineUpdate(v)
    if scaleLerpUpdate(v.scale) then
      v.rec.scaleX = v.scale.x / AFFINE_ONE
      v.rec.scaleY = 1
    else
      if v.counter > 0 then
        v.counter = v.counter - 1
        v.scale = scaleLerp(v.nextStart, 10, v.nextEnd, CON_SCALE_FRAMES)
        v.nextStart, v.nextEnd = v.nextEnd, v.nextStart
      else
        return false
      end
    end
    return true
  end

  Extras.SPRITES[5] = {
    name = "Constrict",
    count = CON_COUNT,
    start = function(ctx)
      ctx.vines = {}
      local y, flip = CON_BASE_Y, false
      for i = 1, CON_COUNT do
        local rec = ctx.sprites[i]
        rec.origin = "defender"
        rec.sx, rec.sy = 0, y
        rec.flipX = flip
        rec.visible = false
        ctx.vines[i] = { rec = rec, scale = scaleLerp(10, 10, 8, CON_SCALE_FRAMES),
                         counter = CON_SCALE_COUNT, nextStart = 8, nextEnd = 10,
                         animate = false }
        y = y - CON_STEP_Y
        flip = not flip
      end
      local side = not ctx.attackerIsPlayer
      local st = ctx.player.state[side]
      ctx.side, ctx.baseX, ctx.baseY = side, st.dx or 0, st.dy or 0
      ctx.shake = H.shake(4, 0, 1, 1)
      ctx.state, ctx.counter, ctx.vineIdx = 0, 0, 1
    end,
    step = function(ctx)
      local st = ctx.player.state[ctx.side]
      if ctx.state == 0 then
        if ctx.counter >= CON_STAGGER then
          ctx.counter = 0
          local v = ctx.vines[ctx.vineIdx]
          v.rec.visible, v.animate = true, true
          ctx.vineIdx = ctx.vineIdx + 1
          if ctx.vineIdx > CON_COUNT then ctx.state = 1 end
        end
        ctx.counter = ctx.counter + 1
      elseif ctx.state == 1 then
        if H.shakeUpdate(ctx.shake) then
          st.dx, st.dy = ctx.baseX + ctx.shake.x, ctx.baseY + ctx.shake.y
        else
          ctx.state = 2
        end
      elseif ctx.state == 2 then
        local active
        for i = 1, CON_COUNT do active = constrictVineUpdate(ctx.vines[i]) end
        if not active then ctx.state = 3 end
      else
        st.dx, st.dy = ctx.baseX, ctx.baseY
        return false
      end
      -- SetAnimateFlag(TRUE) on each enabled vine: SpriteSystem_DrawSprites
      -- advances it every frame the task draws.
      for _, v in ipairs(ctx.vines) do
        if v.animate and not animDone(v.rec) then tick(v.rec) end
      end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- 6 Bonemerang (BattleAnimSpriteFunc_Bonemerang)
  --
  -- The attacker leans back 16 px (4 frames) and returns (2); the bone flies
  -- on a 32-px arc to the defender (10) and back on the mirrored arc (10) and
  -- is hidden; the attacker is pushed back 32 px catching it (4) and returns
  -- (4). The two THROW states return before `SpriteSystem_DrawSprites`, so the
  -- bone's animation does not advance there.
  -- -------------------------------------------------------------------------
  local BON_THROW_X, BON_CATCH_X = -16, -32
  local BON_THROW_A, BON_THROW_B, BON_CATCH_A, BON_CATCH_B = 4, 2, 4, 4
  local BON_ARC_RADIUS, BON_ARC_FRAMES = 32 * FX_ONE, 10

  Extras.SPRITES[6] = {
    name = "Bonemerang",
    count = 1,
    start = function(ctx)
      local side = ctx.attackerIsPlayer and true or false
      local st = ctx.player.state[side]
      ctx.side, ctx.baseX, ctx.baseY = side, st.dx or 0, st.dy or 0
      ctx.dir = H.dirX(side)
      ctx.apos = posLerp(0, BON_THROW_X * ctx.dir, 0, 0, BON_THROW_A)
      local A, D = ctx.pos.attacker, ctx.pos.defender
      ctx.arc = Gen4AnimMath.parabolic(A.x, D.x, A.y, D.y, BON_ARC_FRAMES, BON_ARC_RADIUS)
      ctx.state = 0
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      local st = ctx.player.state[ctx.side]
      local A, D = ctx.pos.attacker, ctx.pos.defender
      local state = ctx.state
      if state == 0 then
        if posLerpUpdate(ctx.apos) then
          st.dx, st.dy = ctx.baseX + ctx.apos.x, ctx.baseY + ctx.apos.y
        else
          ctx.apos = posLerp(ctx.apos.x, 0, 0, 0, BON_THROW_B)
          ctx.state = 1
        end
        return true
      elseif state == 1 then
        if posLerpUpdate(ctx.apos) then
          st.dx, st.dy = ctx.baseX + ctx.apos.x, ctx.baseY + ctx.apos.y
        else
          st.dx, st.dy = ctx.baseX, ctx.baseY
          ctx.apos = posLerp(0, BON_CATCH_X * ctx.dir, 0, 0, BON_CATCH_A)
          ctx.state = 2
        end
        return true
      elseif state == 2 or state == 3 then
        local live, x, y = Gen4AnimMath.parabolicUpdate(ctx.arc)
        if live then
          s.absoluteX, s.absoluteY = x, y
        elseif state == 2 then
          ctx.arc = Gen4AnimMath.parabolic(D.x, A.x, D.y, A.y, BON_ARC_FRAMES, -BON_ARC_RADIUS)
          ctx.state = 3
        else
          s.visible = false
          ctx.state = 4
        end
      elseif state == 4 then
        if posLerpUpdate(ctx.apos) then
          st.dx, st.dy = ctx.baseX + ctx.apos.x, ctx.baseY + ctx.apos.y
        else
          ctx.apos = posLerp(ctx.apos.x, 0, 0, 0, BON_CATCH_B)
          ctx.state = 5
        end
      elseif state == 5 then
        if posLerpUpdate(ctx.apos) then
          st.dx, st.dy = ctx.baseX + ctx.apos.x, ctx.baseY + ctx.apos.y
        else
          st.dx, st.dy = ctx.baseX, ctx.baseY
          ctx.state = 6
        end
      else
        return false
      end
      -- SetAnimateFlag(TRUE): advanced by DrawSprites.
      if not animDone(s) then tick(s) end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- 9 LockOn (BattleAnimSpriteFunc_LockOn)
  --
  -- The reticle starts 40 px up-left of the defender, waits 18 frames, then
  -- walks four 4-frame segments (3 frames apart), switches to its "locked"
  -- sequence and animates, and 9 frames later the backdrop palettes flash
  -- white (fadebg-style, wait -8: steps of 10) while every battler's palette
  -- goes 14 -> 16 white; when the backdrop is done both come back (16 -> 0,
  -- 2 -> 0); then it blinks four times, 5 frames apart.
  -- -------------------------------------------------------------------------
  local LO_EXTENT, LO_MOVE_FRAMES, LO_SEGMENTS = 80, 4, 4
  local LO_START_DELAY, LO_MOVE_DELAY, LO_FLASH_DELAY = -16, 1, 8
  local LO_FADE_WAIT = -8
  local LO_BLINKS, LO_BLINK_INTERVAL = 4, 4
  local LO_SEGMENT = {
    { LO_EXTENT, LO_EXTENT },
    { 0, -LO_EXTENT },
    { -LO_EXTENT, LO_EXTENT },
    { LO_EXTENT / 2, -LO_EXTENT / 2 },
  }

  local function lockOnFades(ctx, from, to)
    ctx.monFades = {}
    for _, side in ipairs({ true, false }) do
      ctx.monFades[#ctx.monFades + 1] = H.monFade(ctx.player, side, from, to, 0, H.WHITE)
    end
  end

  Extras.SPRITES[9] = {
    name = "LockOn",
    count = 1,
    start = function(ctx)
      local s = ctx.sprites[1]
      ctx.baseX, ctx.baseY = (s.sx or 0) - LO_EXTENT / 2, (s.sy or 0) - LO_EXTENT / 2
      s.sx, s.sy = ctx.baseX, ctx.baseY
      -- XLU with G2_SetBlendAlpha(.., 31, 26): ev1 clamps to 16.
      s.alpha = evAlpha(31)
      ctx.delay, ctx.segment, ctx.state, ctx.animate = LO_START_DELAY, 1, 0, false
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      local p = ctx.player
      -- Started inside this step on an earlier frame, so pumped at the top.
      if ctx.monFades then
        for _, f in ipairs(ctx.monFades) do
          if Gen4AnimMath.monFadeActive(f) then H.monFadeUpdate(p, f) end
        end
      end
      local state = ctx.state
      if state == 0 then
        ctx.delay = ctx.delay + 1
        if ctx.delay > LO_MOVE_DELAY then
          local seg = LO_SEGMENT[ctx.segment]
          ctx.pos = posLerp(0, seg[1], 0, seg[2], LO_MOVE_FRAMES)
          ctx.state = 1
          ctx.delay = 0
        end
      elseif state == 1 then
        if posLerpUpdate(ctx.pos) then
          s.sx, s.sy = ctx.baseX + ctx.pos.x, ctx.baseY + ctx.pos.y
        else
          ctx.segment = ctx.segment + 1
          if ctx.segment <= LO_SEGMENTS then
            ctx.state = 0
            ctx.baseX, ctx.baseY = ctx.baseX + ctx.pos.x, ctx.baseY + ctx.pos.y
          else
            ctx.state = 2
            ctx.delay = LO_FLASH_DELAY
            setAnim(s, 1)
            ctx.animate = true
          end
        end
      elseif state == 2 then
        ctx.delay = ctx.delay - 1
        if ctx.delay < 0 then
          ctx.state = 3
          H.fadeBg(p, 0, LO_FADE_WAIT, 0, 16, H.WHITE)
          lockOnFades(ctx, 14, 16)
        end
      elseif state == 3 then
        if not (p.paletteFadeBusy and p:paletteFadeBusy()) then
          ctx.state = 4
          H.fadeBg(p, 0, LO_FADE_WAIT, 16, 0, H.WHITE)
          lockOnFades(ctx, 2, 0)
        end
      elseif state == 4 then
        if not (p.paletteFadeBusy and p:paletteFadeBusy()) then
          ctx.state = 5
          ctx.delay = LO_BLINK_INTERVAL
          ctx.segment = LO_BLINKS
          ctx.blinkVisible = false
        end
      elseif state == 5 then
        ctx.delay = ctx.delay - 1
        if ctx.delay < 0 then
          ctx.delay = LO_BLINK_INTERVAL
          ctx.segment = ctx.segment - 1
          if ctx.segment < 0 then
            ctx.state = 6
          else
            s.visible = ctx.blinkVisible
            ctx.blinkVisible = not ctx.blinkVisible
          end
        end
      else
        return false
      end
      if ctx.animate and not animDone(s) then tick(s) end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- 11 MeanLook (BattleAnimSpriteFunc_MeanLook)
  --
  -- The eye, held on animation frame 4, pulses four times (each pulse is two
  -- shrink/grow pairs; scale, frames and both ends decay by a third, integer,
  -- after each: 15->10 /4, 10->6 /2, 6->4 /1, 4->2 /1) while its alpha fades
  -- 16 -> 10 per pulse. Then it plays sequence 0; 30 frames later the field
  -- (BG0/2/3, i.e. Pokemon and backdrop, not sprites) brightens to white over
  -- 8 frames and back -- only if the animation has not ended first -- and the
  -- eye fades out over 8 and is deleted.
  -- -------------------------------------------------------------------------
  local ML_REPEAT, ML_PULSES, ML_DECAY, ML_PRECISION = 3, 2, 3, 100
  local ML_FLASH_DELAY, ML_FLASH_FADE_FRAMES, ML_FADE_OUT_FRAMES = 30, 4, 8
  local ML_BRIGHT_FRAMES = 8

  -- BrightnessController transition: one step a frame.
  local function brightnessStart(stepCount, target, startB)
    local delta = startB - target
    local dirB = -1
    if delta <= 0 then dirB = 1; delta = -delta end
    return { active = true, brightness = startB, target = target,
             stepCount = stepCount, direction = dirB,
             stepDelta = floor(delta / stepCount), remainder = delta % stepCount,
             acc = 0 }
  end
  local function brightnessStep(b)
    local finished = false
    if b.brightness + b.direction * b.stepDelta ~= b.target and b.brightness ~= b.target then
      b.brightness = b.brightness + b.direction * b.stepDelta
      b.acc = b.acc + b.remainder
      if b.acc >= b.stepCount then
        b.brightness = b.brightness + b.direction
        if b.brightness ~= b.target then b.acc = b.acc - b.stepCount else finished = true end
      end
    else
      b.brightness = b.target
      finished = true
    end
    if finished then b.active = false end
  end

  local function meanLookInitPulse(ctx)
    ctx.scale = scaleLerp(floor(ctx.startScale / ML_PRECISION), 10,
                          floor(ctx.endScale / ML_PRECISION),
                          floor(ctx.scaleFrames / ML_PRECISION))
    ctx.sprites[1].alpha = evAlpha(16)       -- SetSpriteBgBlending(16, 0)
    ctx.fade = alphaFade(16, 10, 0, 6, floor(ctx.scaleFrames / ML_PRECISION) * 2)
    ctx.pulseState, ctx.pulseCount = 0, 0
  end

  local function meanLookUpdatePulse(ctx)
    local s = ctx.sprites[1]
    local function applyScale()
      local active = scaleLerpUpdate(ctx.scale)
      if active then s.scaleX, s.scaleY = ctx.scale.x / AFFINE_ONE, ctx.scale.y / AFFINE_ONE end
      return active
    end
    local ps = ctx.pulseState
    if ps == 0 then
      if not applyScale() then
        ctx.scale = scaleLerp(floor(ctx.endScale / ML_PRECISION), 10,
                              floor(ctx.startScale / ML_PRECISION),
                              floor(ctx.scaleFrames / ML_PRECISION))
        ctx.pulseState = 1
      end
    elseif ps == 1 then
      if not applyScale() then
        ctx.pulseCount = ctx.pulseCount + 1
        if ctx.pulseCount < ML_PULSES then
          ctx.pulseState = 0
          ctx.scale = scaleLerp(floor(ctx.startScale / ML_PRECISION), 10,
                                floor(ctx.endScale / ML_PRECISION),
                                floor(ctx.scaleFrames / ML_PRECISION))
        else
          ctx.pulseState = 2
        end
      end
    elseif ps == 2 then
      if alphaFadeDone(ctx.fade) then
        ctx.pulseState = 3
        return true
      end
    else
      return true
    end
    return false
  end

  local function meanLookUpdatePulses(ctx)
    if ctx.seqState == 0 then
      meanLookInitPulse(ctx)
      meanLookUpdatePulse(ctx)
      ctx.seqState = 1
    elseif ctx.seqState == 1 then
      if meanLookUpdatePulse(ctx) then
        ctx.repeatCount = ctx.repeatCount - 1
        if ctx.repeatCount >= 0 then
          ctx.scaleFrames = ctx.scaleFrames - idiv(ctx.scaleFrames, ML_DECAY)
          ctx.startScale = ctx.startScale - idiv(ctx.startScale, ML_DECAY)
          ctx.endScale = ctx.endScale - idiv(ctx.endScale, ML_DECAY)
          ctx.seqState = 0
        else
          ctx.seqState = 2
          return true
        end
      end
    else
      return true
    end
    return false
  end

  Extras.SPRITES[11] = {
    name = "MeanLook",
    count = 1,
    start = function(ctx)
      local s = ctx.sprites[1]
      setAnimFrame(s, 4)
      ctx.repeatCount = ML_REPEAT
      ctx.scaleFrames = 4 * ML_PRECISION
      ctx.startScale = 15 * ML_PRECISION
      ctx.endScale = 10 * ML_PRECISION
      ctx.state, ctx.seqState, ctx.animate = 0, 0, false
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      local p = ctx.player
      if ctx.fade then
        alphaFadeUpdate(ctx.fade)
        s.alpha = Gen4AnimMath.blendAlpha(ctx.fade)
      end
      -- G2_SetBlendBrightness on BG0/2/3 (the Pokemon and the backdrop, not
      -- the OBJ layer) drawn as a white wash over the field. Written only when
      -- it changes, so the wash channel is not held once the flash is over.
      if ctx.bright then
        if ctx.bright.active then brightnessStep(ctx.bright) end
        if ctx.bright.brightness ~= ctx.washed then
          ctx.washed = ctx.bright.brightness
          H.wash(p, 1, 1, 1, ctx.washed / 16)
        end
      end
      local function brightDone() return not (ctx.bright and ctx.bright.active) end
      local state = ctx.state
      if state == 0 then
        if meanLookUpdatePulses(ctx) then
          ctx.state = 1
          ctx.timer = ML_FLASH_DELAY
          setAnim(s, 0)
          ctx.animate = true
          s.scaleX, s.scaleY = 1, 1
          ctx.fade = alphaFade(0, 16, 16, 0, ML_FLASH_FADE_FRAMES)
        end
      elseif state == 1 then
        if ctx.timer == 0 then
          ctx.bright = brightnessStart(ML_BRIGHT_FRAMES, 16, 0)
          ctx.washed = 0
          H.wash(p, 1, 1, 1, 0)
          ctx.timer = -1
        elseif ctx.timer > 0 then
          ctx.timer = ctx.timer - 1
        end
        if ctx.timer == -1 and brightDone() then
          ctx.bright = brightnessStart(ML_BRIGHT_FRAMES, 0, 16)
          ctx.washed = 16
          H.wash(p, 1, 1, 1, 1)
          ctx.timer = -2
        end
        if animDone(s) then ctx.state = 2 end
      elseif state == 2 then
        if brightDone() then
          ctx.state = 3
          s.alpha = evAlpha(16)
          ctx.fade = alphaFade(16, 0, 0, 16, ML_FADE_OUT_FRAMES)
        end
      elseif state == 3 then
        if alphaFadeDone(ctx.fade) then
          s.visible = false
          ctx.state = 4
        end
      else
        if ctx.bright then H.wash(p, 1, 1, 1, 0) end
        return false
      end
      if ctx.animate and not animDone(s) then tick(s) end
      return true
    end,
  }
end
