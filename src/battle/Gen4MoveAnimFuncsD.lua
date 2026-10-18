-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GEN 4 MOVE ANIMATION, BATCH D: ten script functions and eight sprite callbacks.
--
-- Script functions (`sBattleAnimScriptFuncs`, src/battle_anim/script_func_tables.c):
--   55 Camouflage       script_funcs_4.c         Camouflage 293
--   58 Mimic            script_func_mimic.c      Mimic 102
--   59 ShadowPunch      script_funcs_1.c         Shadow Punch 325
--   70 RolePlay         script_funcs_1.c         Role Play 272
--   71 Snatch           script_funcs_1.c         Snatch 289
--   79 Sketch           script_funcs_1.c         Sketch 166
--   80 StatChangeUp     script_funcs_stat_change.c   stat_boost common anim
--   81 StatChangeDown   script_funcs_stat_change.c   stat_drop common anim
--   82 StatChangeHeal   script_funcs_stat_change.c   restore_hp common anim, Present 217
--   83 StatChangeMetal  script_funcs_stat_change.c   Harden 106, Iron Tail 231,
--                                                    Metal Claw 232, Iron Defense 334
-- Sprite callbacks (`sBattleAnimSpriteFuncs`):
--   16 GrassWhistle (script_funcs_2.c; no program in the corpus adds it)
--   19 Taunt 269, 20 HelpingHand 270, 21 Assist 274, 23 Ingrain 275,
--   24 FrenzyPlant 338 (script_funcs_4.c / script_funcs_1.c)
--   26 FollowMe 266, 27 Fissure 90 (script_funcs_3.c)
--
-- Each state machine is a straight reading of the C: same constants, same frame
-- counts, same order. What the battler channels cannot show (an OBJ window, a
-- scrolling BG pattern inside a silhouette, a palette fade on a cell sprite, a
-- copy drawn ABOVE its battler, z-order changes) keeps its timing and is
-- reported once per call through `H.note`.

local Gen4AnimMath = require("src.battle.Gen4AnimMath")
local Gen4CellAnim = require("src.import.Gen4CellAnim")

local floor = math.floor

return function(Extras)
  local H = Extras.H

  -- -------------------------------------------------------------------------
  -- Shared helpers
  -- -------------------------------------------------------------------------

  local BLEND_MAX = Gen4AnimMath.BLEND_MAX     -- 16

  -- `ManagedSprite_SetAnim(sprite, n)`: a different sequence of the same bank.
  local function setSequence(s, n)
    local seqs = s.art and s.art.sequences
    local seq = seqs and seqs[n + 1]
    if not (seq and seq.frames and #seq.frames > 0) then return false end
    s.sequence = n
    s.frames = seq.frames
    s.length = Gen4CellAnim.length(seq.frames)
    s.animTick = 0
    return true
  end

  local function tick(s) s.animTick = s.animTick + 1 end
  -- `BattleAnimUtil_TickSpriteIfVisible`
  local function tickIfVisible(s) if s.visible then s.animTick = s.animTick + 1 end end
  -- `ManagedSprite_IsAnimated`
  local function animDone(s) return s.animTick >= s.length end

  -- `PaletteFadeContext_New` / `_FadeTask` (battle_anim_helpers.c): a SysTask
  -- that blends a palette toward `color` by `fraction`/16, applying FIRST and
  -- stepping after, `active` dropping on the frame the end fraction is applied.
  -- `timer` starts AT `stepFrames`, so the first application is the first run.
  local function palFade(stepFrames, step, startFrac, endFrac)
    return {
      fraction = startFrac, endFrac = endFrac,
      step = (startFrac < endFrac) and step or -step,
      stepFrames = stepFrames, timer = stepFrames,
      active = true, applied = nil,
    }
  end
  local function palFadeUpdate(c)
    if not c or not c.active then return end
    c.timer = c.timer + 1
    if c.timer >= c.stepFrames then
      c.timer = 0
      c.applied = c.fraction
      if c.fraction == c.endFrac then
        c.active = false
      else
        local nf = c.fraction + c.step
        if c.step > 0 then
          c.fraction = (nf > c.endFrac) and c.endFrac or nf
        else
          c.fraction = (nf < c.endFrac) and c.endFrac or nf
        end
      end
    end
  end

  local function whiteTint(frac)
    if not frac or frac <= 0 then return nil end
    return { 1, 1, 1, frac / BLEND_MAX }
  end

  -- =========================================================================
  -- 55 Camouflage (script_funcs_4.c BattleAnimScriptFunc_Camouflage)
  --
  -- The cartridge hides the attacker, puts an OBJ-WINDOW copy of it over the
  -- battle background (so the BATTLE TERRAIN'S OWN BACKGROUND shows through the
  -- silhouette, wobbling under a scanline sine scroll) and a translucent copy on
  -- top whose blend goes 16 -> 2 over 16 frames, holds 120 frames, then 2 -> 16.
  --
  -- PORT: the battler stays drawn and is tinted toward the terrain's background
  -- colour by (16 - ev1)/16 -- the share of the silhouette the copy no longer
  -- covers. The colour is `player.terrain or 0` (pret `enum BattleTerrain`,
  -- generated/battle_terrains.txt) through the table below. The table is THIS
  -- PORT's reading of each background's dominant colour, not a cartridge
  -- constant -- the cartridge draws the real background tiles. The wobble of
  -- the pattern is not drawn.
  -- =========================================================================

  local CAMOUFLAGE_SPRITE_START_ALPHA = 16
  local CAMOUFLAGE_SPRITE_END_ALPHA = 2
  local CAMOUFLAGE_OTHER_START_ALPHA = 2
  local CAMOUFLAGE_OTHER_END_ALPHA = 16
  local CAMOUFLAGE_ALPHA_FADE_FRAMES = 16
  local CAMOUFLAGE_BG_SCROLL_FRAMES = 120

  -- index = enum BattleTerrain
  local CAMOUFLAGE_TERRAIN_COLOUR = {
    [0]  = { 0.56, 0.75, 0.38 },  -- PLAIN            grass field
    [1]  = { 0.86, 0.76, 0.50 },  -- SAND
    [2]  = { 0.35, 0.65, 0.30 },  -- GRASS            tall grass
    [3]  = { 0.45, 0.60, 0.70 },  -- PUDDLE
    [4]  = { 0.62, 0.52, 0.40 },  -- MOUNTAIN
    [5]  = { 0.45, 0.38, 0.32 },  -- CAVE
    [6]  = { 0.90, 0.93, 0.98 },  -- SNOW
    [7]  = { 0.35, 0.55, 0.85 },  -- WATER
    [8]  = { 0.70, 0.85, 0.95 },  -- ICE
    [9]  = { 0.70, 0.68, 0.62 },  -- BUILDING
    [10] = { 0.48, 0.42, 0.30 },  -- GREAT_MARSH
    [11] = { 0.60, 0.48, 0.36 },  -- BRIDGE
    [12] = { 0.55, 0.70, 0.35 },  -- AARON
    [13] = { 0.65, 0.50, 0.35 },  -- BERTHA
    [14] = { 0.85, 0.40, 0.25 },  -- FLINT
    [15] = { 0.60, 0.45, 0.70 },  -- LUCIAN
    [16] = { 0.80, 0.80, 0.85 },  -- CYNTHIA
    [17] = { 0.35, 0.30, 0.45 },  -- DISTORTION_WORLD
    [18] = { 0.55, 0.55, 0.65 },  -- BATTLE_TOWER
    [19] = { 0.55, 0.55, 0.65 },  -- BATTLE_FACTORY
    [20] = { 0.55, 0.55, 0.65 },  -- BATTLE_ARCADE
    [21] = { 0.55, 0.55, 0.65 },  -- BATTLE_CASTLE
    [22] = { 0.55, 0.55, 0.65 },  -- BATTLE_HALL
    [23] = { 0.30, 0.25, 0.40 },  -- GIRATINA
  }

  Extras.FUNCS[55] = function(player)
    local side = H.attacker(player)
    local colour = CAMOUFLAGE_TERRAIN_COLOUR[tonumber(player.terrain) or 0]
                   or CAMOUFLAGE_TERRAIN_COLOUR[0]
    H.note(player, "Camouflage: terrain background inside the silhouette (flat tint) and its scanline wobble")
    -- AlphaFadeContext_Init at call time: its own task, first step next frame.
    local fade = Gen4AnimMath.alphaFade(CAMOUFLAGE_SPRITE_START_ALPHA, CAMOUFLAGE_SPRITE_END_ALPHA,
                                        CAMOUFLAGE_OTHER_START_ALPHA, CAMOUFLAGE_OTHER_END_ALPHA,
                                        CAMOUFLAGE_ALPHA_FADE_FRAMES)
    local function apply(p, f)
      local a = 1 - Gen4AnimMath.blendAlpha(f)
      H.state(p, side).tint = (a > 0) and { colour[1], colour[2], colour[3], a } or nil
    end
    H.task(player, function(p, t)
      if t.started then Gen4AnimMath.alphaFadeUpdate(t.fade) end
      t.started = true
      if t.state == 0 then
        -- MON_SPRITE_HIDE on the real battler; the two copies stand in for it,
        -- so the port keeps the battler drawn and paints the copies' look on it.
        t.state = 1
      elseif t.state == 1 then
        if Gen4AnimMath.alphaFadeDone(t.fade) then
          t.timer = 0
          t.state = 2
        end
      elseif t.state == 2 then
        t.timer = t.timer + 1
        if t.timer >= CAMOUFLAGE_BG_SCROLL_FRAMES then
          t.fade = Gen4AnimMath.alphaFade(CAMOUFLAGE_SPRITE_END_ALPHA, CAMOUFLAGE_SPRITE_START_ALPHA,
                                          CAMOUFLAGE_OTHER_END_ALPHA, CAMOUFLAGE_OTHER_START_ALPHA,
                                          CAMOUFLAGE_ALPHA_FADE_FRAMES)
          -- the new fade is pumped from the next frame by the check at the top
          t.state = 3
        end
      elseif t.state == 3 then
        if Gen4AnimMath.alphaFadeDone(t.fade) then t.state = 4 end
      else
        H.state(p, side).tint = nil
        t.done = true
        return
      end
      apply(p, t.fade)
    end, { fade = fade })
  end

  -- =========================================================================
  -- 58 Mimic (script_func_mimic.c)
  --
  -- A copy of the defender (MON_SPRITE_0) shrinks 1.0 -> 0.2 over ten frames,
  -- anchored at its foot, and is hidden on the eleventh. The copy sits ABOVE an
  -- unscaled copy of the same defender in the cartridge; the port's ghost list is
  -- drawn beneath the battler, so the shrinking picture is behind it (noted).
  -- =========================================================================

  local BASE_SCALE_XY = 100
  local MIMIC_SCALE_X = 20
  local MIMIC_SCALE_Y = 20
  local MIMIC_SCALE_FRAMES = 10

  Extras.FUNCS[58] = function(player)
    local side = H.defender(player)
    H.note(player, "Mimic: shrinking defender copy is drawn above the defender on the cartridge (ghosts draw beneath)")
    local scale = H.scaleXY(BASE_SCALE_XY, MIMIC_SCALE_X, BASE_SCALE_XY, MIMIC_SCALE_Y,
                            BASE_SCALE_XY, MIMIC_SCALE_FRAMES)
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if not H.scaleXYUpdate(t.scale) then
        st.ghosts = nil
        t.done = true
        return
      end
      st.ghosts = { { dx = 0, dy = 0, alpha = 1,
                      sx = H.affine(t.scale.x), sy = H.affine(t.scale.y) } }
    end, { scale = scale })
  end

  -- =========================================================================
  -- 59 ShadowPunch (script_funcs_1.c)
  --
  -- The attacker darts +48 px (NOT mirrored by side -- the C adds a bare +48)
  -- over 3 frames and back over 3, trailed by two after-images (greyscale x
  -- 196/256, blended 8/8, one priority behind the Pokemon) taking 6 and 8 frames
  -- out, 6 and 9 back. The task ends when all three have arrived each way.
  -- =========================================================================

  local SHADOW_PUNCH_OFFSET_X = 48
  local SHADOW_PUNCH_FRAMES = {
    [1] = { main = 3, a1 = 6, a2 = 8 },     -- out (iteration 0)
    [2] = { main = 3, a1 = 6, a2 = 9 },     -- back
  }
  local SHADOW_PUNCH_ALPHA = 8 / BLEND_MAX
  -- TintPalette(196,196,196): greyscale times 196/256. Shown as a grey wash.
  local SHADOW_PUNCH_TINT = { 0.45, 0.45, 0.45, 0.85 }

  Extras.FUNCS[59] = function(player)
    local side = H.attacker(player)
    H.note(player, "ShadowPunch: after-images are a grey wash, not the exact greyscale palette")
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        local f = SHADOW_PUNCH_FRAMES[t.iteration + 1]
        local from, to = 0, SHADOW_PUNCH_OFFSET_X
        if t.iteration ~= 0 then from, to = SHADOW_PUNCH_OFFSET_X, 0 end
        t.main = Gen4AnimMath.posLerp(from, to, 0, 0, f.main)
        t.a1 = Gen4AnimMath.posLerp(from, to, 0, 0, f.a1)
        t.a2 = Gen4AnimMath.posLerp(from, to, 0, 0, f.a2)
        t.iteration = t.iteration + 1
        t.state = 1
      elseif t.state == 1 then
        local done = 0
        if Gen4AnimMath.posLerpUpdate(t.a1) then t.g1 = t.a1.x else done = done + 1 end
        if Gen4AnimMath.posLerpUpdate(t.main) then st.dx = t.main.x else done = done + 1 end
        if Gen4AnimMath.posLerpUpdate(t.a2) then t.g2 = t.a2.x else done = done + 1 end
        if done >= 3 then
          if t.iteration == 1 then t.state = 0 else t.state = 2 end
        end
      else
        st.dx = 0
        st.ghosts = nil
        t.done = true
        return
      end
      st.ghosts = {
        { dx = t.g1, dy = 0, alpha = SHADOW_PUNCH_ALPHA, sx = 1, sy = 1, tint = SHADOW_PUNCH_TINT },
        { dx = t.g2, dy = 0, alpha = SHADOW_PUNCH_ALPHA, sx = 1, sy = 1, tint = SHADOW_PUNCH_TINT },
      }
    end, { iteration = 0, g1 = 0, g2 = 0 })
  end

  -- =========================================================================
  -- 70 RolePlay (script_funcs_1.c)
  --
  -- The program hides the attacker and adds MON_SPRITE_0 as a look-alike of the
  -- defender; this function puts it 32 px behind the attacker (-32 * dir), fades
  -- it in (blend 0 -> 15, one step a frame), whitens it and the defender's copy
  -- (palette fade 0 -> 15), then squashes it (scaleY -= 0.2, scaleX += 0.2 a
  -- frame, f32 against a double 0.2: four applied frames, hidden on the fifth),
  -- waits for the defender's whitening to finish and fades the defender back
  -- 15 -> 0. The task is also called once directly by the C, which is the
  -- port's same-frame first step.
  --
  -- PORT: the look-alike is a ghost of the ATTACKER's picture (a ghost can only
  -- show its own battler); the defender's whitening is its white tint. The task
  -- renders the Pokemon sprite manager, so `renders = true` keeps the hidden
  -- attacker's copy on screen as the cartridge does.
  -- =========================================================================

  local ROLE_PLAY_ATTACKER_X_OFFSET = -32
  local ROLE_PLAY_MIN_ALPHA = 0
  local ROLE_PLAY_MAX_ALPHA = 15
  local ROLE_PLAY_BLEND_STEPS = 14
  local ROLE_PLAY_PAL_FADE_INTERVAL = 0
  local ROLE_PLAY_PAL_FADE_STEP_SIZE = 1
  local ROLE_PLAY_PAL_FADE_START_FRAC = 0
  local ROLE_PLAY_PAL_FADE_END_FRAC = 15
  -- The f32 walk of 1.0f - n * 0.2f compared with the double 0.2: 0.2f is
  -- 0.2000000029..., which is NOT <= 0.2, so the squash takes one more frame
  -- than the decimal arithmetic suggests. Written out rather than emulated.
  local ROLE_PLAY_SQUASH = {
    { 1.2, 0.8 }, { 1.4, 0.6 }, { 1.6, 0.4 }, { 1.8, 0.2 },
  }

  Extras.FUNCS[70] = function(player)
    local att, def = H.attacker(player), H.defender(player)
    local dx = ROLE_PLAY_ATTACKER_X_OFFSET * H.dirX(att)
    H.note(player, "RolePlay: the defender look-alike is drawn with the attacker's own picture")
    H.task(player, function(p, t)
      -- The two palette fades are SysTasks created before this one, at the same
      -- priority, so they step first -- from the frame after the call.
      if t.started then
        palFadeUpdate(t.attFade)
        palFadeUpdate(t.defFade)
      end
      t.started = true
      local dst = H.state(p, def)
      if t.state == 0 then
        if t.blendStep > ROLE_PLAY_BLEND_STEPS then
          t.squash = t.squash + 1
          local sq = ROLE_PLAY_SQUASH[t.squash]
          if not sq then
            t.state = 1
            t.ghost = nil              -- SetDrawFlag(FALSE)
          else
            t.scaleX, t.scaleY = sq[1], sq[2]
          end
        else
          t.spriteAlpha = t.spriteAlpha + 1
          t.blendStep = t.blendStep + 1
        end
      elseif t.state == 1 then
        if not t.defFade.active then
          t.attFade = nil
          t.defFade = palFade(ROLE_PLAY_PAL_FADE_INTERVAL, ROLE_PLAY_PAL_FADE_STEP_SIZE,
                              ROLE_PLAY_PAL_FADE_END_FRAC, ROLE_PLAY_PAL_FADE_START_FRAC)
          -- The palette still holds the last blend until the new fade writes.
          t.defFade.applied = ROLE_PLAY_PAL_FADE_END_FRAC
          -- created inside this task: the pump at the top reaches it next frame
          t.state = 2
        end
      else
        if not t.defFade.active then
          dst.tint = nil
          H.state(p, att).ghosts = nil
          t.done = true
          return
        end
      end
      dst.tint = whiteTint(t.defFade.applied)
      if t.ghost then
        H.state(p, att).ghosts = { {
          dx = dx, dy = 0, alpha = t.spriteAlpha / BLEND_MAX,
          sx = t.scaleX, sy = t.scaleY,
          tint = whiteTint(t.attFade and t.attFade.applied),
        } }
      else
        H.state(p, att).ghosts = nil
      end
    end, {
      renders = true, blendStep = 0, squash = 0, ghost = true,
      scaleX = 1, scaleY = 1, spriteAlpha = ROLE_PLAY_MIN_ALPHA,
      bgAlpha = ROLE_PLAY_MAX_ALPHA,
      attFade = palFade(ROLE_PLAY_PAL_FADE_INTERVAL, ROLE_PLAY_PAL_FADE_STEP_SIZE,
                        ROLE_PLAY_PAL_FADE_START_FRAC, ROLE_PLAY_PAL_FADE_END_FRAC),
      defFade = palFade(ROLE_PLAY_PAL_FADE_INTERVAL, ROLE_PLAY_PAL_FADE_STEP_SIZE,
                        ROLE_PLAY_PAL_FADE_START_FRAC, ROLE_PLAY_PAL_FADE_END_FRAC),
    })
  end

  -- =========================================================================
  -- 71 Snatch (script_funcs_1.c)
  --
  -- Three 15-frame dashes: off the far edge of the screen (in front), across
  -- the screen at the DEFENDER's height in the other direction (behind it), and
  -- back home. The Y of each leg is set immediately (the lerp's start and end Y
  -- are the same). Between legs the cartridge swaps the battler's picture to the
  -- other facing and back (ov12_022380CC / ov12_022382BC) and moves it in Z;
  -- neither is drawn here.
  -- =========================================================================

  local SNATCH_MOVE_FRAMES = 15
  local SNATCH_ITERATIONS = 3
  local HW_LCD_WIDTH = 256
  local MON_SPRITE_FRAME_WIDTH = 80
  local DEFENDER_MASK = 0x008 + 0x010

  Extras.FUNCS[71] = function(player)
    local target = H.var(player, 0)
    local side = H.attacker(player)
    if target % (DEFENDER_MASK * 2) >= 0x008 then side = H.defender(player) end
    H.note(player, "Snatch: picture facing swap and front/behind Z order between legs")
    local ax, ay = H.centre(H.attacker(player))
    local _, dy = H.centre(H.defender(player))
    local restX, restY = H.centre(side)
    local height = restY - ay
    local xpos, ypos = {}, {}
    if H.attacker(player) then
      xpos[0], xpos[1] = HW_LCD_WIDTH + MON_SPRITE_FRAME_WIDTH - 1, -MON_SPRITE_FRAME_WIDTH
    else
      xpos[0], xpos[1] = -MON_SPRITE_FRAME_WIDTH, HW_LCD_WIDTH + MON_SPRITE_FRAME_WIDTH - 1
    end
    xpos[2] = ax
    ypos[0], ypos[1], ypos[2] = ay + height, dy + height, ay + height
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        t.pos = Gen4AnimMath.posLerp(t.x, xpos[t.iteration], ypos[t.iteration],
                                     ypos[t.iteration], SNATCH_MOVE_FRAMES)
        t.state = 1
        -- falls through into MOVE, as the C does
      end
      if t.state == 1 then
        if not Gen4AnimMath.posLerpUpdate(t.pos) then
          t.iteration = t.iteration + 1
          if t.iteration > SNATCH_ITERATIONS - 1 then t.state = 2 else t.state = 0 end
          t.x = restX + (st.dx or 0)
        end
        st.dx = t.pos.x - restX
        st.dy = t.pos.y - restY
      else
        st.dx, st.dy = 0, 0
        t.done = true
      end
    end, { iteration = 0, x = restX })
  end

  -- =========================================================================
  -- 79 Sketch (script_funcs_1.c)
  --
  -- The defender is copied into a BG and revealed through a window that grows
  -- up from its feet one pixel a frame on two of every four frames, while the
  -- real sprite shows only a two-row "pencil" strip sweeping across. 39 rows of
  -- four frames, one to drop the partial draw, one to clean up: 158 frames.
  --
  -- PORT: no clip channel, so the reveal is the defender's alpha rising with
  -- the window's height (0 -> 78/80), restored to 1 at the end.
  -- =========================================================================

  local SKETCH_STEP_SIZE_Y = 2
  local MON_SPRITE_FRAME_HEIGHT = 80

  Extras.FUNCS[79] = function(player)
    local side = H.defender(player)
    H.note(player, "Sketch: bottom-up window reveal and pencil strip shown as an alpha ramp")
    H.task(player, function(p, t)
      local st = H.state(p, side)
      if t.state == 0 then
        t.viewWidth = t.viewWidth + MON_SPRITE_FRAME_WIDTH - 1
        if t.viewWidth >= MON_SPRITE_FRAME_WIDTH then
          t.state = 1
          t.viewWidth = 0
        end
      elseif t.state == 1 then
        t.revealed = t.revealed + SKETCH_STEP_SIZE_Y / 2
        t.state = 2
      elseif t.state == 2 then
        t.revealed = t.revealed + SKETCH_STEP_SIZE_Y / 2
        t.viewHeight = t.viewHeight + 1
        if t.viewHeight > (MON_SPRITE_FRAME_HEIGHT / SKETCH_STEP_SIZE_Y) - SKETCH_STEP_SIZE_Y then
          t.state = 3
        else
          t.state = 0
        end
      elseif t.state == 3 then
        t.state = 4
      else
        st.alpha = 1
        t.done = true
        return
      end
      st.alpha = math.min(1, t.revealed / MON_SPRITE_FRAME_HEIGHT)
    end, { viewWidth = 0, viewHeight = 0, revealed = 0 })
  end

  -- =========================================================================
  -- 80-83 StatChange{Up,Down,Heal,Metal} (script_funcs_stat_change.c)
  --
  -- A patterned BG (pl_batt_bg members 0x3C/0x36/0x38/0x3A) is shown only
  -- inside the battler's silhouette (OBJ window), blended 12:4 over it and
  -- scrolled 3 px a frame (up / down / up / 6 px down for Metal). Load (1),
  -- blend (1), hold while `timer` counts to 21 (22), fade 12 -> 0 (12), clean up
  -- (1): 37 frames.
  --
  -- PORT: a tint on the target (var 1: 0 attacker, 1 defender) whose strength is
  -- the overlay coefficient times the pattern's coverage. The colours are this
  -- port's reading of palettes 0x122/0x11F/0x120/0x121 (red-orange rise, blue
  -- fall, green heal, steel), not loaded from the ROM; the scrolling stripes are
  -- not drawn.
  -- =========================================================================

  local STAT_CHANGE_OVERLAY_MOVE_FRAMES = 20
  local STAT_CHANGE_OVERLAY_TARGET_ALPHA = 0
  local STAT_CHANGE_OTHER_TARGET_ALPHA = 16
  local STAT_CHANGE_OVERLAY_START_ALPHA = 12
  local STAT_CHANGE_OTHER_START_ALPHA = 4
  local STAT_CHANGE_PATTERN_COVERAGE = 0.6
  local STAT_CHANGE_COLOUR = {
    [0] = { 1.00, 0.45, 0.25 },   -- up
    [1] = { 0.30, 0.45, 1.00 },   -- down
    [2] = { 0.45, 0.95, 0.45 },   -- heal
    [3] = { 0.85, 0.88, 0.95 },   -- metal
  }
  local STAT_CHANGE_NAME = { [80] = "StatChangeUp", [81] = "StatChangeDown",
                             [82] = "StatChangeHeal", [83] = "StatChangeMetal" }

  local function statChange(id)
    return function(player)
      local index = H.var(player, 0)
      local mode = H.var(player, 1)
      local side = (mode == 0) and H.attacker(player) or H.defender(player)
      local colour = STAT_CHANGE_COLOUR[index] or STAT_CHANGE_COLOUR[0]
      H.note(player, STAT_CHANGE_NAME[id] .. ": scrolling pattern inside the silhouette shown as a flat tint")
      H.task(player, function(p, t)
        local st = H.state(p, side)
        if t.state == 0 then
          t.state = 1                              -- load the BG
        elseif t.state == 1 then
          t.blend = true                           -- G2_SetBlendAlpha(12, 4)
          t.state = 2
        elseif t.state == 2 then
          if t.timer > STAT_CHANGE_OVERLAY_MOVE_FRAMES then t.state = 3 else t.timer = t.timer + 1 end
        elseif t.state == 3 then
          if t.overlay > STAT_CHANGE_OVERLAY_TARGET_ALPHA then t.overlay = t.overlay - 1 end
          if t.other < STAT_CHANGE_OTHER_TARGET_ALPHA then t.other = t.other + 1 end
          if t.overlay == STAT_CHANGE_OVERLAY_TARGET_ALPHA
             and t.other == STAT_CHANGE_OTHER_TARGET_ALPHA then
            t.state = 4
          end
        else
          st.tint = nil
          t.done = true
          return
        end
        if t.blend and t.overlay > 0 then
          st.tint = { colour[1], colour[2], colour[3],
                      t.overlay / BLEND_MAX * STAT_CHANGE_PATTERN_COVERAGE }
        else
          st.tint = nil
        end
      end, { timer = 0, overlay = STAT_CHANGE_OVERLAY_START_ALPHA,
             other = STAT_CHANGE_OTHER_START_ALPHA })
    end
  end
  for id = 80, 83 do Extras.FUNCS[id] = statChange(id) end

  -- =========================================================================
  -- SPRITE CALLBACKS
  -- =========================================================================

  -- 19 Taunt (script_funcs_4.c) -------------------------------------------
  -- One hand (var 0 = 1 in the only program) at the screen point (128, 80),
  -- sequence 1 when the defender is on the player's side and 0 otherwise
  -- (singles reading of the C's four-way test), translucent: blend 0 -> 15 one
  -- step a frame while a 45-frame counter runs, then 15 -> 0; deleted on the
  -- frame after both coefficients arrive. Ticked every frame.
  local TAUNT_SPRITE_HAND_0_POS_X = 128
  local TAUNT_SPRITE_HAND_0_POS_Y = 80
  local TAUNT_SPRITE_MIN_ALPHA = 0
  local TAUNT_SPRITE_MAX_ALPHA = 15
  local TAUNT_SPRITE_FADE_IN_FRAMES = 45

  Extras.SPRITES[19] = {
    name = "Taunt",
    -- The C clones var 0 hands; the player sizes the clone list statically, and
    -- the only program passes 1.
    count = 1,
    start = function(ctx)
      local s = ctx.sprites[1]
      local handCount = tonumber(ctx.vars[0]) or 1
      if handCount > #ctx.sprites then
        H.note(ctx.player, "Taunt: more than one hand requested")
      end
      setSequence(s, ctx.attackerIsPlayer and 0 or 1)
      s.absoluteX, s.absoluteY = TAUNT_SPRITE_HAND_0_POS_X, TAUNT_SPRITE_HAND_0_POS_Y
      ctx.spriteAlpha = TAUNT_SPRITE_MIN_ALPHA
      ctx.bgAlpha = TAUNT_SPRITE_MAX_ALPHA
      ctx.fadeInFrames = 0
      ctx.state = 0
      s.alpha = ctx.spriteAlpha / BLEND_MAX
    end,
    step = function(ctx)
      if ctx.state == 0 then
        if ctx.spriteAlpha < TAUNT_SPRITE_MAX_ALPHA then ctx.spriteAlpha = ctx.spriteAlpha + 1 end
        if ctx.bgAlpha > TAUNT_SPRITE_MIN_ALPHA then ctx.bgAlpha = ctx.bgAlpha - 1 end
        ctx.fadeInFrames = ctx.fadeInFrames + 1
        if ctx.fadeInFrames >= TAUNT_SPRITE_FADE_IN_FRAMES then ctx.state = 1 end
      elseif ctx.state == 1 then
        if ctx.spriteAlpha > TAUNT_SPRITE_MIN_ALPHA then ctx.spriteAlpha = ctx.spriteAlpha - 1 end
        if ctx.bgAlpha < TAUNT_SPRITE_MAX_ALPHA then ctx.bgAlpha = ctx.bgAlpha + 1 end
        if ctx.spriteAlpha == TAUNT_SPRITE_MIN_ALPHA and ctx.bgAlpha == TAUNT_SPRITE_MAX_ALPHA then
          ctx.state = 2
        end
      else
        return false
      end
      for _, s in ipairs(ctx.sprites) do
        s.alpha = ctx.spriteAlpha / BLEND_MAX
        tick(s)
      end
      return true
    end,
  }

  -- 20 HelpingHand (script_funcs_4.c) -------------------------------------
  -- Six hands at fixed screen points; four pairs clap toward the middle (5, 5,
  -- 5 and 3 frames), each pair hidden again once it lands except the last. A
  -- 15-step fade in and out of the blend around it. The hands carry the animate
  -- flag AND are ticked by the task outside the fade-out, so they advance two
  -- cells a frame there and one during the fade-out.
  local HELPING_HAND_SPRITE_MIN_ALPHA = 0
  local HELPING_HAND_SPRITE_MAX_ALPHA = 15
  local HELPING_HAND_POSITIONS = {
    { 80, 50 }, { 180, 50 }, { 80, 100 }, { 180, 100 }, { 80, 75 }, { 180, 75 },
  }
  local HELPING_HAND_SEQUENCES = { 0, 0, 1, 1, 2, 3 }
  -- pair -> Lua indices of hand1, hand2
  local HELPING_HAND_PAIRS = { [0] = { 1, 4 }, [1] = { 2, 3 }, [2] = { 5, 6 }, [3] = { 5, 6 } }
  local HELPING_HAND_DESTS = {
    [0] = { { 0x78, 0x50 }, { 0x88, 0x50 } },
    [1] = { { 0x78, 0x50 }, { 0x88, 0x50 } },
    [2] = { { 0x78, 0x50 }, { 0x88, 0x50 } },
    [3] = { { 0x58, 0x50 }, { 0xA8, 0x50 } },
  }
  local HELPING_HAND_FRAMES = { [0] = 5, [1] = 5, [2] = 5, [3] = 3 }
  local HELPING_HAND_LAST_PAIR = 3

  Extras.SPRITES[20] = {
    name = "HelpingHand",
    count = 6,
    start = function(ctx)
      for i, s in ipairs(ctx.sprites) do
        setSequence(s, HELPING_HAND_SEQUENCES[i] or 0)
        local pos = HELPING_HAND_POSITIONS[i]
        s.absoluteX, s.absoluteY = pos[1], pos[2]
        s.alpha = HELPING_HAND_SPRITE_MIN_ALPHA / BLEND_MAX
      end
      ctx.sprites[1].flipX = true
      ctx.sprites[4].flipX = true
      ctx.sprites[2].visible = false
      ctx.sprites[3].visible = false
      ctx.sprites[5].visible = false
      ctx.sprites[6].visible = false
      ctx.spriteAlpha = HELPING_HAND_SPRITE_MIN_ALPHA
      ctx.bgAlpha = HELPING_HAND_SPRITE_MAX_ALPHA
      ctx.currentPair = 0
      ctx.state = 0
    end,
    step = function(ctx)
      local sp = ctx.sprites
      local animsDone = false
      if ctx.state == 0 then
        if ctx.spriteAlpha < HELPING_HAND_SPRITE_MAX_ALPHA then ctx.spriteAlpha = ctx.spriteAlpha + 1 end
        if ctx.bgAlpha > HELPING_HAND_SPRITE_MIN_ALPHA then ctx.bgAlpha = ctx.bgAlpha - 1 end
        if ctx.spriteAlpha == HELPING_HAND_SPRITE_MAX_ALPHA
           and ctx.bgAlpha == HELPING_HAND_SPRITE_MIN_ALPHA then
          ctx.state = 1
        end
      elseif ctx.state == 1 then
        local pair = HELPING_HAND_PAIRS[ctx.currentPair]
        ctx.h1, ctx.h2 = sp[pair[1]], sp[pair[2]]
        ctx.h1.visible, ctx.h2.visible = true, true
        local d = HELPING_HAND_DESTS[ctx.currentPair]
        local n = HELPING_HAND_FRAMES[ctx.currentPair]
        ctx.l1 = Gen4AnimMath.posLerp(ctx.h1.absoluteX, d[1][1], ctx.h1.absoluteY, d[1][2], n)
        ctx.l2 = Gen4AnimMath.posLerp(ctx.h2.absoluteX, d[2][1], ctx.h2.absoluteY, d[2][2], n)
        ctx.currentPair = ctx.currentPair + 1
        ctx.state = 2
      elseif ctx.state == 2 then
        local doneCount = 0
        if Gen4AnimMath.posLerpUpdate(ctx.l1) then
          ctx.h1.absoluteX, ctx.h1.absoluteY = ctx.l1.x, ctx.l1.y
        else
          doneCount = doneCount + 1
        end
        if Gen4AnimMath.posLerpUpdate(ctx.l2) then
          ctx.h2.absoluteX, ctx.h2.absoluteY = ctx.l2.x, ctx.l2.y
        else
          doneCount = doneCount + 1
        end
        if doneCount >= 2 then
          if ctx.currentPair <= HELPING_HAND_LAST_PAIR then
            ctx.h1.visible, ctx.h2.visible = false, false
            ctx.state = 1
          else
            ctx.state = 3
          end
        end
      elseif ctx.state == 3 then
        if ctx.spriteAlpha > HELPING_HAND_SPRITE_MIN_ALPHA then ctx.spriteAlpha = ctx.spriteAlpha - 1 end
        if ctx.bgAlpha < HELPING_HAND_SPRITE_MAX_ALPHA then ctx.bgAlpha = ctx.bgAlpha + 1 end
        if ctx.bgAlpha >= floor(HELPING_HAND_SPRITE_MAX_ALPHA / 2) then animsDone = true end
        if ctx.spriteAlpha == HELPING_HAND_SPRITE_MIN_ALPHA
           and ctx.bgAlpha == HELPING_HAND_SPRITE_MAX_ALPHA then
          ctx.state = 4
        end
      else
        return false
      end
      local taskTick = ctx.state < 3 and not animsDone
      for _, s in ipairs(sp) do
        s.alpha = ctx.spriteAlpha / BLEND_MAX
        if taskTick then tick(s) end
        tick(s)                     -- the animate flag, through DrawSprites
      end
      return true
    end,
  }

  -- 21 Assist (script_funcs_4.c) ------------------------------------------
  -- Twelve paws (var 0 is read and then overwritten with 12) scattered over six
  -- screen regions by the cartridge LCRNG, each with its own task: wait, appear,
  -- grow 3 x 0.1 and shrink back, report, wait up to 30 frames or until every
  -- paw has reported, then fly to one of six screen corners/edges in 10-19
  -- frames and vanish. The outer task waits on all of them and cleans up.
  -- Paw tasks run at priority 1099 and the outer at 1101: paws first.
  local ASSIST_SPRITE_DEFAULT_PAW_COUNT = 12
  local ASSIST_SPRITE_CONFIG_COUNT = 6
  local ASSIST_SPRITE_PAW_SCALE = 1.0
  local ASSIST_SPRITE_PAW_SCALE_STEP = 0.1
  local ASSIST_SPRITE_PAW_SCALE_STEPS = 3
  local ASSIST_SPRITE_PAW_BASE_DELAY = 10
  local ASSIST_SPRITE_PAW_RANDOM_DELAY = 10
  local ASSIST_SPRITE_PAW_MOVE_DELAY = 30
  local ASSIST_SPRITE_PAW_MOVE_BASE_FRAMES = 10
  local ASSIST_SPRITE_PAW_MOVE_RANDOM_FRAMES = 10
  local ASSIST_OUTER_SCALE_DONE, ASSIST_OUTER_MOVE, ASSIST_OUTER_DONE = 1, 2, 3
  local ASSIST_DESTS = {
    [0] = { 0, 0 }, [1] = { 128, 0 }, [2] = { 256, 0 },
    [3] = { 0, 170 }, [4] = { 128, 170 }, [5] = { 256, 170 },
  }
  -- { offsetX, offsetY, randomX, randomY }
  local ASSIST_OFFSETS = {
    [0] = { 40, 30, 53, 50 }, [1] = { 93, 30, 53, 50 }, [2] = { 146, 30, 53, 50 },
    [3] = { 40, 80, 53, 50 }, [4] = { 93, 80, 53, 50 }, [5] = { 146, 80, 53, 50 },
  }

  local function assistPawStep(ctx, paw)
    local s = paw.sprite
    local st = paw.state
    if st == 0 then
      paw.delay = paw.delay - 1
      if paw.delay <= ASSIST_SPRITE_PAW_BASE_DELAY then paw.state = 1 end
    elseif st == 1 then
      paw.step = paw.step + 1
      if paw.step >= 3 then
        s.visible = true
        paw.step = 0
        paw.state = 2
      end
    elseif st == 2 or st == 3 then
      paw.step = paw.step + 1
      if paw.step <= ASSIST_SPRITE_PAW_SCALE_STEPS then
        local d = (st == 2) and ASSIST_SPRITE_PAW_SCALE_STEP or -ASSIST_SPRITE_PAW_SCALE_STEP
        paw.scale = paw.scale + d
        s.scaleX, s.scaleY = paw.scale, paw.scale
      else
        paw.step = 0
        paw.state = st + 1
      end
    elseif st == 4 then
      paw.delay = paw.delay - 1
      if paw.delay <= ASSIST_SPRITE_PAW_BASE_DELAY then
        ctx.outer[paw.index] = ASSIST_OUTER_SCALE_DONE
        paw.step = 0
        paw.state = 5
      end
    elseif st == 5 then
      paw.step = paw.step + 1
      if paw.step > ASSIST_SPRITE_PAW_MOVE_DELAY then
        paw.step = 0
        paw.state = 6
      elseif ctx.outer[paw.index] == ASSIST_OUTER_MOVE then
        paw.state = 6
      end
    elseif st == 6 then
      local frames = ASSIST_SPRITE_PAW_MOVE_BASE_FRAMES
                     + (ctx.player:lcrng() % ASSIST_SPRITE_PAW_MOVE_RANDOM_FRAMES)
      local dest = ASSIST_DESTS[paw.destIndex]
      paw.pos = Gen4AnimMath.posLerp(s.absoluteX, dest[1], s.absoluteY, dest[2], frames)
      paw.state = 7
    elseif st == 7 then
      if Gen4AnimMath.posLerpUpdate(paw.pos) then
        s.absoluteX, s.absoluteY = paw.pos.x, paw.pos.y
      else
        s.visible = false
        ctx.outer[paw.index] = ASSIST_OUTER_DONE
        paw.ended = true
      end
    end
    tick(s)                         -- ManagedSprite_TickFrame, every run
  end

  Extras.SPRITES[21] = {
    name = "Assist",
    count = ASSIST_SPRITE_DEFAULT_PAW_COUNT,
    start = function(ctx)
      local rng = function() return ctx.player:lcrng() end
      ctx.paws, ctx.outer = {}, {}
      local offsetIdx = 0
      for i = 0, ASSIST_SPRITE_DEFAULT_PAW_COUNT - 1 do
        local s = ctx.sprites[i + 1]
        local paw = { index = i, sprite = s, state = 0, step = 0,
                      scale = ASSIST_SPRITE_PAW_SCALE }
        paw.delay = ASSIST_SPRITE_PAW_BASE_DELAY + (rng() % ASSIST_SPRITE_PAW_RANDOM_DELAY) + i
        paw.destIndex = rng() % ASSIST_SPRITE_CONFIG_COUNT
        local o = ASSIST_OFFSETS[offsetIdx]
        local x = o[1] + (rng() % o[3])
        local y = o[2] + (rng() % o[4])
        s.absoluteX, s.absoluteY = x, y
        s.scaleX, s.scaleY = paw.scale, paw.scale
        s.visible = false
        ctx.paws[i + 1] = paw
        ctx.outer[i] = 0
        offsetIdx = (offsetIdx + 1) % ASSIST_SPRITE_CONFIG_COUNT
      end
      ctx.state = 0
    end,
    step = function(ctx)
      for _, paw in ipairs(ctx.paws) do
        if not paw.ended then assistPawStep(ctx, paw) end
      end
      local n = ASSIST_SPRITE_DEFAULT_PAW_COUNT
      if ctx.state == 0 then
        local all = true
        for i = 0, n - 1 do if ctx.outer[i] ~= ASSIST_OUTER_SCALE_DONE then all = false break end end
        if all then ctx.state = 1 end
      elseif ctx.state == 1 then
        for i = 0, n - 1 do ctx.outer[i] = ASSIST_OUTER_MOVE end
        ctx.state = 2
      elseif ctx.state == 2 then
        local all = true
        for i = 0, n - 1 do if ctx.outer[i] ~= ASSIST_OUTER_DONE then all = false break end end
        if all then ctx.state = 3 end
      elseif ctx.state == 3 then
        for _, s in ipairs(ctx.sprites) do s.visible = false end   -- deleted
        ctx.state = 4
      else
        return false
      end
      return true
    end,
  }

  -- 23 Ingrain (script_funcs_4.c) -----------------------------------------
  -- Four vines at fixed heights under the attacker (y 140 player / 84 enemy,
  -- x from the attacker), the lower pair 32 px out, the upper pair 40 px out and
  -- 4 px down; vine 0 starts at once, the others 5/10/15 frames plus 0-3 later
  -- (LCRNG); each animates from counter 20. From counter 110 the vines are
  -- translucent and fade out one step a frame (ev1 15 -> 0); deleted at 124.
  -- Six white palette flashes on the vines (counters 50..100) need a cell-sprite
  -- tint channel and are not drawn; their priorities (in front of / behind the
  -- Pokemon) are not represented either.
  local INGRAIN_SPRITE_VINE_COUNT = 4
  local INGRAIN_SPRITE_UPPER_VINE_OFFSET_X = 40
  local INGRAIN_SPRITE_UPPER_VINE_OFFSET_Y = 4
  local INGRAIN_SPRITE_LOWER_VINE_OFFSET_X = 32
  local INGRAIN_SPRITE_LOWER_VINE_OFFSET_Y = 0
  local INGRAIN_SPRITE_VINE_Y_PLAYER = 140
  local INGRAIN_SPRITE_VINE_Y_ENEMY = 84
  local INGRAIN_SPRITE_VINE_MAX_DELAY = 20
  local INGRAIN_SPRITE_VINE_MIN_ALPHA = 0
  local INGRAIN_SPRITE_VINE_MAX_ALPHA = 15
  local INGRAIN_SPRITE_VINE_ALPHA_FADE_DELAY = 110

  Extras.SPRITES[23] = {
    name = "Ingrain",
    count = INGRAIN_SPRITE_VINE_COUNT,
    start = function(ctx)
      local sp = ctx.sprites
      H.note(ctx.player, "Ingrain: vine palette flashes and front/behind priorities")
      ctx.counters = { 0 }
      for i = 2, INGRAIN_SPRITE_VINE_COUNT do
        ctx.counters[i] = (ctx.player:lcrng() % INGRAIN_SPRITE_VINE_COUNT)
                          + (i - 1) * floor(INGRAIN_SPRITE_VINE_MAX_DELAY / INGRAIN_SPRITE_VINE_COUNT)
      end
      sp[2].flipX, sp[3].flipX = true, true
      local vineY = ctx.attackerIsPlayer and INGRAIN_SPRITE_VINE_Y_PLAYER or INGRAIN_SPRITE_VINE_Y_ENEMY
      -- C indices: 0 LL, 1 UR, 2 LR, 3 UL
      local offsets = {
        { -INGRAIN_SPRITE_LOWER_VINE_OFFSET_X, INGRAIN_SPRITE_LOWER_VINE_OFFSET_Y },
        { INGRAIN_SPRITE_UPPER_VINE_OFFSET_X, INGRAIN_SPRITE_UPPER_VINE_OFFSET_Y },
        { INGRAIN_SPRITE_LOWER_VINE_OFFSET_X, INGRAIN_SPRITE_LOWER_VINE_OFFSET_Y },
        { -INGRAIN_SPRITE_UPPER_VINE_OFFSET_X, INGRAIN_SPRITE_UPPER_VINE_OFFSET_Y },
      }
      for i, s in ipairs(sp) do
        s.origin = "attacker"
        s.sx = offsets[i][1]
        s.sy = 0
        s.absoluteY = vineY + offsets[i][2]
      end
      ctx.fading = false
    end,
    step = function(ctx)
      local sp, c = ctx.sprites, ctx.counters
      for i = 1, INGRAIN_SPRITE_VINE_COUNT do
        c[i] = c[i] + 1
        if c[i] >= INGRAIN_SPRITE_VINE_MAX_DELAY then tickIfVisible(sp[i]) end
      end
      if c[1] == INGRAIN_SPRITE_VINE_ALPHA_FADE_DELAY then
        ctx.fading = true
        ctx.bgAlpha = INGRAIN_SPRITE_VINE_MAX_ALPHA
        ctx.spriteAlpha = INGRAIN_SPRITE_VINE_MIN_ALPHA
      end
      if c[1] >= INGRAIN_SPRITE_VINE_ALPHA_FADE_DELAY then
        if ctx.bgAlpha > INGRAIN_SPRITE_VINE_MIN_ALPHA then ctx.bgAlpha = ctx.bgAlpha - 1 end
        if ctx.spriteAlpha < INGRAIN_SPRITE_VINE_MAX_ALPHA then ctx.spriteAlpha = ctx.spriteAlpha + 1 end
        -- G2_ChangeBlendAlpha(bgAlpha, spriteAlpha): the FIRST coefficient is
        -- the sprite's own share, so it is `bgAlpha` that the vines show.
        for _, s in ipairs(sp) do s.alpha = ctx.bgAlpha / BLEND_MAX end
        if ctx.bgAlpha == INGRAIN_SPRITE_VINE_MIN_ALPHA
           and ctx.spriteAlpha == INGRAIN_SPRITE_VINE_MAX_ALPHA then
          return false
        end
      end
      return true
    end,
  }

  -- 24 FrenzyPlant (script_funcs_1.c) -------------------------------------
  -- Eight roots spread along the line from the attacker to the defender: a
  -- 20-step PosLerp whose odd updates place the next root (the enemy-side
  -- attacker skips the first). Odd roots are flipped. Root i starts at lifetime
  -- (8 - i) * 4, animates from 32 and vanishes at 160; the callback ends when
  -- all eight have (frame 156). Their BG priorities are not represented.
  local FRENZY_PLANT_ROOT_COUNT = 8
  local FRENZY_PLANT_ROOT_MOVE_DELAY = 32
  local FRENZY_PLANT_ROOT_LIFETIME = 160

  Extras.SPRITES[24] = {
    name = "FrenzyPlant",
    count = FRENZY_PLANT_ROOT_COUNT,
    start = function(ctx)
      local sp = ctx.sprites
      for i = 1, FRENZY_PLANT_ROOT_COUNT do
        if (i - 1) % 2 == 1 then sp[i].flipX = true end
      end
      local a, d = ctx.pos.attacker, ctx.pos.defender
      local pos = Gen4AnimMath.posLerp(a.x, d.x, a.y, d.y, (FRENZY_PLANT_ROOT_COUNT + 2) * 2)
      local frame, idx = 0, 1
      local skip = not ctx.attackerIsPlayer
      local active
      repeat
        active = Gen4AnimMath.posLerpUpdate(pos)
        if frame % 2 == 1 then
          if not skip then
            if idx <= FRENZY_PLANT_ROOT_COUNT then
              sp[idx].absoluteX, sp[idx].absoluteY = pos.x, pos.y
              idx = idx + 1
            end
          else
            skip = false
          end
        end
        frame = frame + 1
      until not active
      ctx.lifetime = {}
      for i = 1, FRENZY_PLANT_ROOT_COUNT do
        ctx.lifetime[i] = (FRENZY_PLANT_ROOT_COUNT - (i - 1)) * 4
      end
    end,
    step = function(ctx)
      local sp = ctx.sprites
      local invisible = 0
      for i = 1, FRENZY_PLANT_ROOT_COUNT do
        ctx.lifetime[i] = ctx.lifetime[i] + 1
        if ctx.lifetime[i] >= FRENZY_PLANT_ROOT_MOVE_DELAY then
          tickIfVisible(sp[i])
          if ctx.lifetime[i] >= FRENZY_PLANT_ROOT_LIFETIME then
            sp[i].visible = false
            invisible = invisible + 1
          end
        end
      end
      if invisible == FRENZY_PLANT_ROOT_COUNT then return false end
      return true
    end,
  }

  -- 26 FollowMe (script_funcs_3.c) ----------------------------------------
  -- The hand starts 12 px below the defender's centre (sequence chosen by the
  -- player's SPRITE_SEQUENCE), swings left-right-back by a table of per-frame
  -- offsets (switching between in front of and behind the Pokemon at the
  -- zero entries -- not represented), then wags: rotation 0 -> +20 -> -20 ->
  -- +20 -> -20 -> +20 -> 0 degrees, 4 frames a leg (2 for the last). The C
  -- rotates about the centre offset by (-8, 16); the draw rotates about the
  -- centre.
  local FOLLOW_ME_SPRITE_OFFSET_END = 255
  local FOLLOW_ME_SPRITE_OFFSET_Y = 12
  local FOLLOW_ME_SPRITE_TILT_FRAMES = 4
  local FOLLOW_ME_OFFSETS = {
    5, 5, 5, 5, 4, 4, 4, 3, 3, 3, 0,
    -3, -3, -3, -4, -4, -4, -5, -5, -5, -5, -5, -5, -5, -5, -4, -4, -4, -3, -3, -3, 0,
    3, 3, 3, 4, 4, 4, 5, 5, 5, 5,
    FOLLOW_ME_SPRITE_OFFSET_END,
  }

  Extras.SPRITES[26] = {
    name = "FollowMe",
    count = 1,
    start = function(ctx)
      local s = ctx.sprites[1]
      s.sx, s.sy = 0, FOLLOW_ME_SPRITE_OFFSET_Y
      ctx.common = 0
      ctx.idx = 1
      ctx.sub = 0
      ctx.tiltAngle = Gen4AnimMath.degToIdx(20)
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      local A = ctx.tiltAngle
      if ctx.common == 0 then
        local off = FOLLOW_ME_OFFSETS[ctx.idx]
        ctx.idx = ctx.idx + 1
        if off ~= FOLLOW_ME_SPRITE_OFFSET_END then
          s.sx = s.sx + off
        else
          ctx.tilt = Gen4AnimMath.valueLerp(0, A, FOLLOW_ME_SPRITE_TILT_FRAMES)
          ctx.sub = 0
          ctx.common = 1
        end
      elseif ctx.common == 1 then
        if Gen4AnimMath.valueLerpUpdate(ctx.tilt) then
          s.rotation = Gen4AnimMath.radians(ctx.tilt.value)
        elseif ctx.sub > 5 then
          ctx.common = 2
        else
          ctx.sub = ctx.sub + 1
          local n = FOLLOW_ME_SPRITE_TILT_FRAMES
          if ctx.sub == 1 or ctx.sub == 3 then
            ctx.tilt = Gen4AnimMath.valueLerp(A, -A, n)
          elseif ctx.sub == 2 or ctx.sub == 4 then
            ctx.tilt = Gen4AnimMath.valueLerp(-A, A, n)
          elseif ctx.sub == 5 then
            ctx.tilt = Gen4AnimMath.valueLerp(A, 0, floor(n / 2))
          end
        end
      else
        return false
      end
      tick(s)
      return true
    end,
  }

  -- 27 Fissure (script_funcs_3.c) -----------------------------------------
  -- The player already places the crack (defender X, absolute Y 126/32) and
  -- picks its sequence; the callback only plays the animation through and
  -- deletes the sprite when it stops: check first, tick second.
  Extras.SPRITES[27] = {
    name = "Fissure",
    count = 1,
    start = function(ctx) end,
    step = function(ctx)
      local s = ctx.sprites[1]
      if animDone(s) then return false end
      tick(s)
      return true
    end,
  }

  -- 16 GrassWhistle (script_funcs_2.c) ------------------------------------
  -- Fifteen notes (sequence i % 3, never ticked) launched from the attacker's
  -- centre every seventh frame, each lerping (+256 * dirX, -128 * dirY) over
  -- 59 frames with a sine bob of 14 px and a +-0.17 scale on the screen X.
  -- Landed notes stay where they stopped; the callback ends when the last one
  -- lands (frame 165). No program in the Platinum corpus adds this callback.
  local GRASS_WHISTLE_SPRITE_NOTE_COUNT = 15
  local GRASS_WHISTLE_SPRITE_NOTE_DELAY = 6
  local GRASS_WHISTLE_SPRITE_NOTE_MOVE_X = 256
  local GRASS_WHISTLE_SPRITE_NOTE_MOVE_Y = -128
  local GRASS_WHISTLE_SPRITE_NOTE_MOVE_FRAMES = 59
  local GRASS_WHISTLE_CURVE_AMPLITUDE = 14 * 4096
  local GRASS_WHISTLE_SCALE_AMPLITUDE = 696          -- FX32_CONST(0.17f)
  local GRASS_WHISTLE_DEG2 = Gen4AnimMath.degToIdx(2)

  local function grassWhistleUpdateNote(s, pos)
    if Gen4AnimMath.posLerpUpdate(pos) then
      local x, y = pos.x, pos.y
      local degX = (x * GRASS_WHISTLE_DEG2) % 65536
      local sinv = Gen4AnimMath.sinIdx(degX)
      local offsetY = floor(Gen4AnimMath.fxMul(sinv, GRASS_WHISTLE_CURVE_AMPLITUDE) / 4096)
      s.absoluteX, s.absoluteY = x, y + offsetY
      local delta = -Gen4AnimMath.fxMul(sinv, GRASS_WHISTLE_SCALE_AMPLITUDE)
      local scale = 1 + delta / 4096
      s.scaleX, s.scaleY = scale, scale
      return false
    end
    return true
  end

  Extras.SPRITES[16] = {
    name = "GrassWhistle",
    count = GRASS_WHISTLE_SPRITE_NOTE_COUNT,
    start = function(ctx)
      local a = ctx.pos.attacker
      for i, s in ipairs(ctx.sprites) do
        s.visible = false
        s.absoluteX, s.absoluteY = a.x, a.y
        setSequence(s, (i - 1) % 3)
      end
      ctx.dirX = H.dirX(ctx.attackerIsPlayer)
      ctx.dirY = H.dirY(ctx.attackerIsPlayer)
      ctx.noteDelay = 0
      ctx.noteIndex = 0
      ctx.notePos = {}
    end,
    step = function(ctx)
      local sp = ctx.sprites
      if ctx.noteIndex < GRASS_WHISTLE_SPRITE_NOTE_COUNT then
        ctx.noteDelay = ctx.noteDelay + 1
        if ctx.noteDelay > GRASS_WHISTLE_SPRITE_NOTE_DELAY then
          ctx.noteDelay = 0
          local i = ctx.noteIndex + 1
          local s = sp[i]
          ctx.notePos[i] = Gen4AnimMath.posLerp(
            s.absoluteX, s.absoluteX + GRASS_WHISTLE_SPRITE_NOTE_MOVE_X * ctx.dirX,
            s.absoluteY, s.absoluteY + GRASS_WHISTLE_SPRITE_NOTE_MOVE_Y * ctx.dirY,
            GRASS_WHISTLE_SPRITE_NOTE_MOVE_FRAMES)
          s.visible = true
          ctx.noteIndex = i
        end
      end
      local done
      for i = 1, ctx.noteIndex do
        done = grassWhistleUpdateNote(sp[i], ctx.notePos[i])
      end
      if ctx.noteIndex >= GRASS_WHISTLE_SPRITE_NOTE_COUNT and done == true then
        return false
      end
      return true
    end,
  }
end
