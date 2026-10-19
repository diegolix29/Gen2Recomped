-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GEN 4 MOVE ANIMATION SCRIPT FUNCTIONS, BATCH C.
--
-- Straight readings of pret's battle-animation functions, registered by their
-- index in `sBattleAnimScriptFuncs` / `sBattleAnimSpriteFuncs`
-- (src/battle_anim/script_func_tables.c). Contract and channels: see the
-- header of `Gen4MoveAnimExtras`.
--
-- From src/battle_anim/script_funcs_3.c:
--    4 RotateMon               (Peck 64, Skull Bash 130)
--   10 Submission              (Submission 66, Strength 70)
--   35 ScalePokemonSprite      (Disable 50, Extrasensory 326)
--   38 AlphaFadePokemonSprite  (Sky Attack 143, Brave Bird 413)
--   50 BlinkAttacker           (Double Team 104, ExtremeSpeed 245, Shadow Force 467)
--   51 MoveBattlerX            (ExtremeSpeed 245)
--   53 ShakeAndScaleAttacker   (Spit Up 255)
--   54 ShakeAndScaleAttacker2  (no program calls it)
--   56 Superpower              (Superpower 276)
--   61 MoveBattlerOffScreen    (Whirlwind 18, Roar 46)
--   62 MoveBattlerToDefaultPos (Whirlwind 18, Roar 46)
--   63 FadePokemonSprite       (Disable 50, Toxic 92, Lunar Dance 461)
--   64 BattlerPartialDrawTest  (no program calls it)
--   67 BattlerPartialDraw      (Dig 91)
--   69 PixelatePokemonSprite   (Transform 144)
--   76 ScrollSwitchedBg        (Nightmare 171, Whirlpool 250, Water Pulse 352,
--                               HGSS Psychic 94)
--   77 MoveBattlerOnOrOffScreen (no program calls it)
-- From src/battle_anim/script_funcs_2.c:
--   37 Extrasensory            (Extrasensory 326)
--   41 FakeOutCurtain, 43 FakeOut (Fake Out 252)
--   46 Megahorn (unused), 47 MegahornAttacker, 48 MegahornDefender (Megahorn 224)
--   sprite 12 Torment, 13 BatonPass (Baton Pass 226), 15 Grudge (Grudge 288)
--
-- THE MON-SPRITE COPIES. Several of these act on `BattleAnimSystem_GetPokemonSprite`
-- -- the copies `addpokemonsprite` makes (`player.monSprites[slot]`), not the
-- battler. The player draws ONE Pokemon a side: a copy is drawn in the
-- battler's place only while the battler is hidden and a renderer task lives
-- (`Player:monOffset`, `monHidden`). So a function that changes how a copy
-- looks writes it in one of two places, per frame (`copyShow` below):
--   * battler hidden and this copy is the side's drawn copy -> the battler's
--     own channels (sx, sy, alpha, mosaic, tint), restored when the task ends;
--   * otherwise (the battler is on screen too) -> an entry in the side's
--     `ghosts`, which is the cartridge's second picture drawn beside it.
-- Every function that calls `SpriteSystem_DrawSprites(pokemonSpriteManager)`
-- marks its task `renders`, because that call is what puts the copies on screen.
--
-- SCALES PIVOT ON THE FOOT in this port's draw, which is what
-- `BattleAnimUtil_SetPokemonSpriteAnchoredPosition(..., ANCHOR_BOTTOM)` computes
-- for a species with no empty rows under it -- so the anchored ones write only
-- sx/sy. The two that scale about the CENTRE (BatonPass) add the dy that keeps
-- the centre still.

local Gen4AnimMath = require("src.battle.Gen4AnimMath")
local okCellAnim, Gen4CellAnim = pcall(require, "src.import.Gen4CellAnim")
if not okCellAnim then Gen4CellAnim = nil end

local floor, max, min = math.floor, math.max, math.min
local sin, cos = math.sin, math.cos
local idiv, shr12, fxMul = Gen4AnimMath.idiv, Gen4AnimMath.shr12, Gen4AnimMath.fxMul
local sinIdx, cosIdx = Gen4AnimMath.sinIdx, Gen4AnimMath.cosIdx

local FX_ONE = 4096
local AFFINE_ONE = 256
-- MON_SPRITE_FRAME_WIDTH / HEIGHT (10 tiles of 8).
local MON_FRAME_W = 80
local MON_FRAME_H = 80
local MON_HALF = 40
local LCD_W, LCD_H = 256, 192

-- BATTLE_ANIM_* target flags (include/constants/battle/battle_anim.h).
local T_ATTACKER = 2
local T_ATTACKER_PARTNER = 4
local T_DEFENDER = 8
local T_DEFENDER_PARTNER = 16
local T_BATTLER_SPRITES = 256
local T_BATTLER_SPRITE_ATTACKER = T_ATTACKER + T_BATTLER_SPRITES        -- 258
local T_BATTLER_SPRITE_DEFENDER = T_DEFENDER + T_BATTLER_SPRITES        -- 264

local WHITE = 0x7FFF

local function hasBit(v, bit) return floor((tonumber(v) or 0) / bit) % 2 == 1 end

return function(Extras)
  local H = Extras.H

  -- -------------------------------------------------------------------------
  -- Shared helpers
  -- -------------------------------------------------------------------------

  -- `BattleAnimUtil_GetBattlerSprites(system, target, ...)` for ONE exact
  -- target flag, in a single battle: the partner flags add nothing there (the
  -- function only looks at them `if (IsDoubleBattle)`), so they give no side.
  local function sideForTarget(player, target)
    if target == T_ATTACKER then return H.attacker(player) end
    if target == T_DEFENDER then return H.defender(player) end
    return nil
  end

  -- The rest position (`BattleAnimUtil_GetBattlerDefaultPos` + the sprite's
  -- height, which is where dx = dy = 0 is).
  local function restX(side) local x = H.centre(side) return x end
  local function restY(side) local _, y = H.centre(side) return y end

  -- Tints a palette fade has left on a COPY (`FadePokemonSprite` blends the
  -- copy's own OBJ palette and nothing ever un-blends it until the copy goes).
  local copyTint = setmetatable({}, { __mode = "k" })
  local copyMirror = setmetatable({}, { __mode = "k" })

  local COPY_KEYS = { "sx", "sy", "alpha", "mosaic", "tint" }

  -- Undo what `copyShow` wrote for task `t` last frame.
  local function copyClear(player, t)
    local list = t.cfx
    if not list then return end
    for i = #list, 1, -1 do
      local e = list[i]
      local s = H.state(player, e.side)
      if e.ghost then
        local g = s.ghosts
        if g then
          for j = #g, 1, -1 do
            if g[j] == e.ghost then table.remove(g, j) end
          end
          if #g == 0 then s.ghosts = nil end
        end
      else
        for k, old in pairs(e.saved) do s[k] = old.v end
      end
    end
    t.cfx = nil
  end

  -- Draw copy `rec` this frame with channels `ch` = { sx, sy, alpha, mosaic,
  -- tint, dy }. See the header for the two places it can go.
  local function copyShow(player, t, rec, ch)
    if not rec or not rec.visible then return end
    local side = rec.side and true or false
    local s = H.state(player, side)
    local tint = ch.tint or copyTint[rec]
    t.cfx = t.cfx or {}
    local drawn = player.monSpriteFor and player:monSpriteFor(side)
    if s.hidden and drawn == rec then
      local saved = {}
      for _, k in ipairs(COPY_KEYS) do
        local v
        if k == "tint" then v = tint else v = ch[k] end
        if v ~= nil then
          saved[k] = { v = s[k] }
          s[k] = v
        end
      end
      t.cfx[#t.cfx + 1] = { side = side, saved = saved }
    else
      local g = {
        dx = rec.dx or 0, dy = (rec.dy or 0) + (ch.dy or 0),
        alpha = ch.alpha or 1, sx = ch.sx or 1, sy = ch.sy or 1,
        tint = tint, mosaic = ch.mosaic,
      }
      s.ghosts = s.ghosts or {}
      s.ghosts[#s.ghosts + 1] = g
      t.cfx[#t.cfx + 1] = { side = side, ghost = g }
    end
  end

  -- Keeps a copy's persistent palette tint on the battler while that copy is
  -- what is drawn for the side (battler hidden, a renderer alive). A plain
  -- SysTask: nothing waits on it, and it ends when the copy is removed.
  local function ensureTintMirror(player, rec, slot)
    if copyMirror[rec] then return end
    copyMirror[rec] = true
    H.sysTask(player, function(p, t)
      local side = rec.side and true or false
      local s = H.state(p, side)
      if not p.monSprites or p.monSprites[slot] ~= rec then
        if t.wrote and s.tint == t.wrote then s.tint = nil end
        copyMirror[rec] = nil
        t.done = true
        return
      end
      local tint = copyTint[rec]
      local rendered = p.monSpritesRendered and p:monSpritesRendered()
      if tint and s.hidden and rendered and p:monSpriteFor(side) == rec then
        s.tint = tint
        t.wrote = tint
      elseif t.wrote then
        if s.tint == t.wrote then s.tint = nil end
        t.wrote = nil
      end
    end)
  end

  -- A 2D sprite's sequence change (`ManagedSprite_SetAnim`): the record plays
  -- `seq` from its first frame.
  local function setAnim(ctx, s, seq)
    local seqs = s.art and s.art.sequences
    local q = seqs and seqs[seq + 1]
    if q and q.frames and #q.frames > 0 and Gen4CellAnim then
      s.frames = q.frames
      s.length = Gen4CellAnim.length(q.frames)
      s.sequence = seq
      s.animTick = 0
    elseif ctx.player then
      ctx.player:note(("sequence %d of %s (SetAnim)"):format(seq, tostring(s.key)))
    end
  end

  local function animDone(s) return (s.animTick or 0) >= (s.length or 0) end

  -- -------------------------------------------------------------------------
  -- 4 RotateMon (script_funcs_3.c)
  --
  -- A ValueLerp on MON_SPRITE_ROTATION_Z out to var 1 and back to var 0, the
  -- STEP (not the values) multiplied by the battler's direction. The rotation
  -- is about a PIVOT -- (40 * dir, 40), the frame's front foot, unless type 1
  -- names one in vars 4/5 -- and the player rotates about the picture centre,
  -- so the offset that turns one into the other is added to dx/dy (and taken
  -- back out at the end). Type 2 is the defender with the pivot mirrored.
  -- -------------------------------------------------------------------------

  local ROTATE_MON_PIVOT_X = MON_FRAME_W / 2
  local ROTATE_MON_PIVOT_Y = MON_FRAME_H / 2

  local function rotateMonApply(p, t, side, idx)
    local s = H.state(p, side)
    local theta = H.radians(idx)
    s.rot = theta
    -- The centre after a rotation by theta about pivot P is P - R(theta) P.
    local px, py = t.px, t.py
    local c, sn = cos(theta), sin(theta)
    local cx = px - (px * c - py * sn)
    local cy = py - (px * sn + py * c)
    if idx == 0 then cx, cy = 0, 0 end
    s.dx = (s.dx or 0) + cx - (t.cdx or 0)
    s.dy = (s.dy or 0) + cy - (t.cdy or 0)
    t.cdx, t.cdy = cx, cy
    if idx == 0 then
      -- Back on whole pixels: the float residue of taking the pivot back out.
      s.dx = floor(s.dx + 0.5)
      s.dy = floor(s.dy + 0.5)
    end
  end

  Extras.FUNCS[4] = function(player)
    local start = H.var(player, 0)
    local finish = H.var(player, 1)
    local steps = H.var(player, 2)
    local typ = H.var(player, 3)
    local side
    if typ == 0 or typ == 2 then side = H.defender(player) else side = H.attacker(player) end
    local lerp = Gen4AnimMath.valueLerp(start, finish, steps)
    local dir = H.dirX(side)
    lerp.step = lerp.step * dir
    if typ == 2 then dir = -dir end
    local px, py
    if typ == 1 then
      px, py = H.var(player, 4), H.var(player, 5)
    else
      px, py = ROTATE_MON_PIVOT_X * dir, ROTATE_MON_PIVOT_Y
    end
    H.task(player, function(p, t)
      if t.state == 0 or t.state == 1 then
        if Gen4AnimMath.valueLerpUpdate(t.lerp) then
          rotateMonApply(p, t, side, t.lerp.value % 65536)
        else
          -- Re-initialised from wherever it got to, back to the start, with the
          -- plain (un-mirrored) step: the C does not multiply this one.
          t.lerp = Gen4AnimMath.valueLerp(t.lerp.value, start, steps)
          t.state = t.state + 1
        end
      else
        rotateMonApply(p, t, side, 0)
        H.state(p, side).rot = 0
        t.done = true
      end
    end, { lerp = lerp, px = px, py = py, cdx = 0, cdy = 0 })
  end

  -- -------------------------------------------------------------------------
  -- 10 Submission (script_funcs_3.c)
  --
  -- `RevolutionContext_InitOvalRevolutions(revs, framesPerRev)` -- the 32 x -8
  -- oval -- around (x, y + 8), with the X radius negated on the attacker's
  -- side. The C ends by putting the battler at (x, y): the -8 it subtracted
  -- at the start, added back.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[10] = function(player)
    local revs = H.var(player, 0)
    local framesPerRev = H.var(player, 1)
    local target = H.var(player, 2)
    local rev = Gen4AnimMath.ovalRevolution(revs, framesPerRev, false)
    local side
    if target == T_ATTACKER or target == T_ATTACKER_PARTNER then
      -- A partner in a single battle is the battler itself
      -- (`BattleAnimUtil_GetAlliedBattler`'s solo arm).
      side = H.attacker(player)
      rev.rx = -rev.rx
    elseif target == T_DEFENDER or target == T_DEFENDER_PARTNER then
      side = H.defender(player)
    else
      return
    end
    local s0 = H.state(player, side)
    local x0, y0 = s0.dx or 0, s0.dy or 0
    local baseDy = y0 - Gen4AnimMath.OVAL_RADIUS_Y_INT
    H.task(player, function(p, t)
      local s = H.state(p, side)
      if Gen4AnimMath.revolutionUpdate(rev) then
        s.dx = x0 + rev.x
        s.dy = baseDy + rev.y
      else
        s.dx = x0
        s.dy = baseDy + Gen4AnimMath.OVAL_RADIUS_Y_INT
        s.rot = 0
        t.done = true
      end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 35 ScalePokemonSprite (script_funcs_3.c)
  --
  -- A COPY (var 7 names the slot) scaled start -> end over `frames >> 16` and
  -- back over `frames & 0xFFFF`, `cycles` times, translucent at
  -- spriteAlpha/16 (`SetSpriteBgBlending(alpha, 16 - alpha)` on an XLU
  -- sprite), bottom-anchored. Disable grows the defender's copy to 1.2x,
  -- Extrasensory the attacker's to 1.5x, both over a battler still on screen --
  -- so in practice this is a ghost.
  --
  -- THE CLEANUP FRAME DRAWS NOTHING: it returns before `SpriteSystem_DrawSprites`.
  -- The C leaves the copy's scale where the restore put it (the start), and the
  -- flip it applies is the copy's own resource being un-mirrored, which the
  -- battler picture this port draws already is.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[35] = function(player)
    -- var 0 (attacker or defender) only picks the battler whose height anchors
    -- the scale, and the foot pivot does that here.
    local spriteAlpha = H.var(player, 1)
    local startScale = H.var(player, 2)
    local endScale = H.var(player, 3)
    local refScale = H.var(player, 4)
    local cycles = H.var(player, 5)
    local frames = H.var(player, 6)
    local slot = H.var(player, 7)
    local alpha = max(0, min(16, spriteAlpha)) / 16
    local scaleFrames = H.hi16(frames % 4294967296)
    local restoreFrames = H.lo16(frames % 4294967296)

    H.task(player, function(p, t)
      local st = t.state
      if st == 0 then
        t.scale = Gen4AnimMath.scaleLerp(startScale, refScale, endScale, scaleFrames)
        t.showX, t.showY = Gen4AnimMath.affineScale(t.scale)
        t.state = 1
      elseif st == 1 then
        if not Gen4AnimMath.scaleLerpUpdate(t.scale) then t.state = 2 end
        t.showX, t.showY = Gen4AnimMath.affineScale(t.scale)
      elseif st == 2 then
        -- Initialised without an apply: the copy keeps the last scale this frame.
        t.scale = Gen4AnimMath.scaleLerp(endScale, refScale, startScale, restoreFrames)
        t.state = 3
      elseif st == 3 then
        if not Gen4AnimMath.scaleLerpUpdate(t.scale) then
          t.cycles = t.cycles - 1
          if t.cycles <= 0 then t.state = 4 else t.state = 0 end
        end
        t.showX, t.showY = Gen4AnimMath.affineScale(t.scale)
      else
        copyClear(p, t)
        t.done = true
        return
      end
      copyClear(p, t)
      copyShow(p, t, p.monSprites and p.monSprites[slot],
               { sx = t.showX, sy = t.showY, alpha = alpha })
    end, { renders = true, cycles = cycles })
  end

  -- -------------------------------------------------------------------------
  -- 37 Extrasensory (script_funcs_2.c)
  --
  -- The defender, copied into the base BG by `loadpokemonspriteintobg`, is
  -- bent by a per-scanline horizontal scroll: three 17-frame distortions
  -- (amplitude 16, -16, 20; a shear of 5, -5, 10 per 10 rows) with a +-1 jitter
  -- that flips every frame and every other row pair. This port keeps drawing
  -- the battler for a BG copy (see the player's `loadpokemonspriteintobg`), so
  -- the battler is not hidden and the wave is applied to it as ONE horizontal
  -- shift -- the mean of the rows' offsets, which is where the picture's mass
  -- goes. The shape of the wave is not drawn.
  -- -------------------------------------------------------------------------

  local EXTRASENSORY_ANGLE_INCREMENT = idiv(H.degToIdx(180), MON_FRAME_H)
  local EXTRASENSORY_Y_RANGE_OFFSET = -8
  local EXTRASENSORY_JITTER = FX_ONE
  local EXTRASENSORY_DAMPENING = 10
  local EXTRASENSORY_COUNT = 3
  local EXTRASENSORY_PARAMS = {
    [0] = { angle = H.degToIdx(180), step = 5, amplitude = 16 * FX_ONE, frames = 16 },
    [1] = { angle = H.degToIdx(180), step = -5, amplitude = -16 * FX_ONE, frames = 16 },
    [2] = { angle = H.degToIdx(180), step = 10, amplitude = 20 * FX_ONE, frames = 16 },
  }

  local function extrasensoryUpdate(p, t)
    local startY = t.y + EXTRASENSORY_Y_RANGE_OFFSET
    local endY = t.y + MON_FRAME_H - EXTRASENSORY_Y_RANGE_OFFSET
    if startY < 0 then startY = 0 end
    if endY > LCD_H then endY = LCD_H end
    t.dir = -t.dir
    local sum, n = 0, 0
    for y = startY, endY - 1 do
      local amplitude
      if floor(y / 2) % 2 == 1 then
        amplitude = t.baseAmplitude + EXTRASENSORY_JITTER * t.dir
      else
        amplitude = t.baseAmplitude - EXTRASENSORY_JITTER * t.dir
      end
      local angle = (t.baseAngle + EXTRASENSORY_ANGLE_INCREMENT * (y - startY)) % 65536
      local xOffset = shr12(fxMul(sinIdx(angle), amplitude))
      xOffset = xOffset + idiv((y - t.centerY) * t.amplitudeStep, EXTRASENSORY_DAMPENING)
      sum = sum + xOffset
      n = n + 1
    end
    -- A positive BG offset moves the picture LEFT.
    local mean = (n > 0) and floor(sum / n + 0.5) or 0
    H.state(p, t.side).dx = t.x0 - mean
  end

  Extras.FUNCS[37] = function(player)
    local side = H.defender(player)
    local s = H.state(player, side)
    local centerY = restY(side) + (s.dy or 0)
    H.note(player, "Extrasensory: per-scanline wave drawn as a whole-battler shift")
    H.task(player, function(p, t)
      if t.state == 0 then
        local prm = EXTRASENSORY_PARAMS[t.count]
        t.baseAngle, t.amplitudeStep = prm.angle, prm.step
        t.baseAmplitude, t.delay = prm.amplitude, prm.frames
        extrasensoryUpdate(p, t)
        t.state = 1
      elseif t.state == 1 then
        t.delay = t.delay - 1
        extrasensoryUpdate(p, t)
        if t.delay < 0 then
          t.count = t.count + 1
          if t.count < EXTRASENSORY_COUNT then t.state = 0 else t.state = 2 end
        end
      else
        H.state(p, side).dx = t.x0
        t.done = true
      end
    end, {
      side = side, x0 = s.dx or 0, centerY = centerY,
      y = centerY - MON_FRAME_H / 2, dir = 1, count = 0,
    })
  end

  -- -------------------------------------------------------------------------
  -- 38 AlphaFadePokemonSprite (script_funcs_3.c)
  --
  -- The copies named by var 0's bits (BATTLE_ANIM_MON_SPRITE_F(i) -> slot i)
  -- go translucent and the hardware blend walks ev1 start -> end over `frames`.
  -- The AlphaFadeContext's own SysTask is priority 0, so it does not run on the
  -- frame it is created and runs BEFORE this task every frame after: a
  -- `frames`-step fade holds this task for frames + 2 steps, and the step
  -- that sees it done cleans up without drawing.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[38] = function(player)
    local targets = H.var(player, 0)
    local spriteStart = H.var(player, 1)
    local spriteEnd = H.var(player, 2)
    local bgStart = H.var(player, 3)
    local bgEnd = H.var(player, 4)
    local frames = H.var(player, 5)
    local slots = {}
    for i = 0, 3 do
      if hasBit(targets, 2 ^ i) then slots[#slots + 1] = i end
    end
    local fade = Gen4AnimMath.alphaFade(spriteStart, spriteEnd, bgStart, bgEnd, frames)
    H.task(player, function(p, t)
      if t.started then Gen4AnimMath.alphaFadeUpdate(fade) end
      t.started = true
      copyClear(p, t)
      if Gen4AnimMath.alphaFadeDone(fade) then
        t.done = true
        return
      end
      local a = Gen4AnimMath.blendAlpha(fade)
      for _, slot in ipairs(slots) do
        copyShow(p, t, p.monSprites and p.monSprites[slot], { alpha = a })
      end
    end, { renders = true })
  end

  -- -------------------------------------------------------------------------
  -- 41 FakeOutCurtain (script_funcs_2.c)
  --
  -- Window 0 narrows from the full screen to the centre line over 8 frames
  -- (the effect layer shows only inside it) while the base BG palettes fade
  -- to white (0 -> 16, PaletteData_StartFade with delay 0) and, once that
  -- fade and the curtain are done, back. The fades are this port's
  -- `fadebg` arithmetic on the "base" group; the window is `player.effectWindow`
  -- ({ x1, x2 }: the columns the effect layer still shows), which
  -- Gen4Battle.drawEffectBackground scissors to.
  -- -------------------------------------------------------------------------

  local FAKE_OUT_CURTAIN_START_X = 127
  local FAKE_OUT_CURTAIN_END_X = 0
  local FAKE_OUT_CURTAIN_MOVE_FRAMES = 8
  local FAKE_OUT_CURTAIN_DELAY = 7
  local FAKE_OUT_CURTAIN_ALPHA = 16

  local function paletteBusy(p)
    if p.paletteFadeBusy then return p:paletteFadeBusy() ~= nil end
    return false
  end

  Extras.FUNCS[41] = function(player)
    H.task(player, function(p, t)
      local st = t.state
      if t.curtain then
        local x = math.max(0, t.curtain.x or 0)
        p.effectWindow = { 128 - x, 128 + x + 1 }
      end
      if st == 0 then
        t.curtain = Gen4AnimMath.posLerp(FAKE_OUT_CURTAIN_START_X, FAKE_OUT_CURTAIN_END_X,
                                         0, 0, FAKE_OUT_CURTAIN_MOVE_FRAMES)
        t.delay = FAKE_OUT_CURTAIN_DELAY
        t.state = 1
      elseif st == 1 then
        t.delay = t.delay - 1
        if t.delay < 0 then
          H.fadeBg(p, 0, 0, 0, FAKE_OUT_CURTAIN_ALPHA, WHITE)
          t.state = 2
        end
      elseif st == 2 then
        if not Gen4AnimMath.posLerpUpdate(t.curtain) then t.state = 3 end
      elseif st == 3 then
        if not paletteBusy(p) then
          t.state = 4
          H.fadeBg(p, 0, 0, FAKE_OUT_CURTAIN_ALPHA, 0, WHITE)
        end
      elseif st == 4 then
        if not paletteBusy(p) then t.state = 5 end
      else
        p.effectWindow = nil
        t.done = true
      end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 43 FakeOut (script_funcs_2.c)
  --
  -- The defender squashed to 0.7 x 3.0 (ref 10) over 4 frames and back over 3,
  -- bottom-anchored, while a 2-pixel shake (interval 1, amount 2) runs on X.
  -- Each INIT state also takes the first scale step on the same frame.
  -- -------------------------------------------------------------------------

  local FAKE_OUT_SX, FAKE_OUT_EX, FAKE_OUT_SY, FAKE_OUT_EY = 10, 7, 10, 30
  local FAKE_OUT_REF = 10
  local FAKE_OUT_CYCLES = 1
  local FAKE_OUT_SCALE_FRAMES, FAKE_OUT_RESTORE_FRAMES = 4, 3

  local function fakeOutApply(p, t)
    local s = H.state(p, t.side)
    if H.shakeUpdate(t.shake) then
      s.dx = t.x0 + t.shake.x
    end
    local active = H.scaleXYUpdate(t.scale)
    if active then
      s.sx, s.sy = t.scale.x / AFFINE_ONE, t.scale.y / AFFINE_ONE
    end
    -- Anchored to the ground: the foot pivot.
    s.dy = t.y0
    return active
  end

  Extras.FUNCS[43] = function(player)
    local side = H.defender(player)
    local s = H.state(player, side)
    H.task(player, function(p, t)
      local st = t.state
      if st == 0 then
        t.scale = H.scaleXY(FAKE_OUT_SX, FAKE_OUT_EX, FAKE_OUT_SY, FAKE_OUT_EY,
                            FAKE_OUT_REF, FAKE_OUT_SCALE_FRAMES)
        fakeOutApply(p, t)
        t.state = 1
      elseif st == 1 then
        if not fakeOutApply(p, t) then t.state = 2 end
      elseif st == 2 then
        t.scale = H.scaleXY(FAKE_OUT_EX, FAKE_OUT_SX, FAKE_OUT_EY, FAKE_OUT_SY,
                            FAKE_OUT_REF, FAKE_OUT_RESTORE_FRAMES)
        fakeOutApply(p, t)
        t.state = 3
      elseif st == 3 then
        if not fakeOutApply(p, t) then
          t.cycles = t.cycles - 1
          if t.cycles <= 0 then t.state = 4 else t.state = 0 end
        end
      else
        local ss = H.state(p, side)
        ss.dx, ss.dy = t.x0, t.y0
        ss.sx, ss.sy = 1, 1
        t.done = true
      end
    end, {
      side = side, x0 = s.dx or 0, y0 = s.dy or 0, cycles = FAKE_OUT_CYCLES,
      shake = H.shake(2, 0, 1, 2),
    })
  end

  -- -------------------------------------------------------------------------
  -- 46 Megahorn (script_funcs_2.c) -- no program calls it
  --
  -- Moves the system's sprite 0 or 1 (the horn `addsprite` made) 48, -16 over
  -- 6 frames and deletes the other. This port's 2D layer has no index for a
  -- plain `addsprite` sprite, so only the length is kept.
  -- -------------------------------------------------------------------------

  local MEGAHORN_MOVE_FRAMES = 6

  Extras.FUNCS[46] = function(player)
    H.note(player, "Megahorn: horn sprite motion")
    local pos = Gen4AnimMath.posLerp(0, 0, 0, 0, MEGAHORN_MOVE_FRAMES)
    H.task(player, function(p, t)
      if not Gen4AnimMath.posLerpUpdate(pos) then t.done = true end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 47 MegahornAttacker (script_funcs_2.c)
  --
  -- Shake 4 px (interval 1, 4 cycles), lunge 40 forward and 7 up over 4 frames,
  -- hold 9 (delay 8 counted below zero), come back over 4.
  -- -------------------------------------------------------------------------

  local MEGAHORN_ATTACKER_MOVE_X = 40
  local MEGAHORN_ATTACKER_MOVE_Y = -7
  local MEGAHORN_ATTACKER_MOVE_FRAMES = 4
  local MEGAHORN_ATTACKER_DELAY = 8

  Extras.FUNCS[47] = function(player)
    local side = H.attacker(player)
    local s0 = H.state(player, side)
    local x, y = s0.dx or 0, s0.dy or 0
    local dirX, dirY = H.dirX(side), H.dirY(side)
    local tx = x + MEGAHORN_ATTACKER_MOVE_X * dirX
    local ty = y + MEGAHORN_ATTACKER_MOVE_Y * dirY
    H.task(player, function(p, t)
      local s = H.state(p, side)
      local st = t.state
      if st == 0 then
        t.shake = H.shake(4, 0, 1, 4)
        t.state = 1
      elseif st == 1 then
        if H.shakeUpdate(t.shake) then
          s.dx, s.dy = x + t.shake.x, y + t.shake.y
        else
          t.state = 2
          t.pos = Gen4AnimMath.posLerp(x, tx, y, ty, MEGAHORN_ATTACKER_MOVE_FRAMES)
        end
      elseif st == 2 then
        if Gen4AnimMath.posLerpUpdate(t.pos) then
          s.dx, s.dy = t.pos.x, t.pos.y
        else
          t.state = 3
          t.delay = MEGAHORN_ATTACKER_DELAY
        end
      elseif st == 3 then
        t.delay = t.delay - 1
        if t.delay < 0 then
          t.state = 4
          t.pos = Gen4AnimMath.posLerp(tx, x, ty, y, MEGAHORN_ATTACKER_MOVE_FRAMES)
        end
      elseif st == 4 then
        if Gen4AnimMath.posLerpUpdate(t.pos) then
          s.dx, s.dy = t.pos.x, t.pos.y
        else
          t.state = 5
        end
      else
        s.dx, s.dy = x, y
        t.done = true
      end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 48 MegahornDefender (script_funcs_2.c)
  --
  -- Knocked 40 back and 16 down over 4 frames, shaken, brought back over 4.
  -- THE SHAKE ACCUMULATES: its base is re-read from the sprite every frame,
  -- so each flip is added to the last position -- the defender walks
  -- +4, +4, 0, 0, ... rather than +4, 0, -4, 0. Reproduced.
  -- -------------------------------------------------------------------------

  local MEGAHORN_DEFENDER_MOVE_X = -40
  local MEGAHORN_DEFENDER_MOVE_Y = 16
  local MEGAHORN_DEFENDER_MOVE_FRAMES = 4

  Extras.FUNCS[48] = function(player)
    local side = H.defender(player)
    local s0 = H.state(player, side)
    local x, y = s0.dx or 0, s0.dy or 0
    local dirX, dirY = H.dirX(side), H.dirY(side)
    local tx = x + MEGAHORN_DEFENDER_MOVE_X * dirX
    local ty = y + MEGAHORN_DEFENDER_MOVE_Y * dirY
    H.task(player, function(p, t)
      local s = H.state(p, side)
      local st = t.state
      if st == 0 then
        t.pos = Gen4AnimMath.posLerp(x, tx, y, ty, MEGAHORN_DEFENDER_MOVE_FRAMES)
        t.state = 1
      elseif st == 1 then
        if Gen4AnimMath.posLerpUpdate(t.pos) then
          s.dx, s.dy = t.pos.x, t.pos.y
        else
          t.state = 2
          t.shake = H.shake(4, 0, 1, 4)
        end
      elseif st == 2 then
        local baseX, baseY = s.dx or 0, s.dy or 0
        if H.shakeUpdate(t.shake) then
          s.dx, s.dy = baseX + t.shake.x, baseY + t.shake.y
        else
          t.state = 3
          t.pos = Gen4AnimMath.posLerp(tx, x, ty, y, MEGAHORN_DEFENDER_MOVE_FRAMES)
        end
      elseif st == 3 then
        if Gen4AnimMath.posLerpUpdate(t.pos) then
          s.dx, s.dy = t.pos.x, t.pos.y
        else
          t.state = 4
        end
      else
        s.dx, s.dy = x, y
        t.done = true
      end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 50 BlinkAttacker (script_funcs_3.c)
  --
  -- MON_SPRITE_HIDE toggled `count * 2` times, one toggle every `interval + 1`
  -- frames (the timer counts up to the interval and toggles on the frame it
  -- has reached it), then shown.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[50] = function(player)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local s = H.state(p, side)
      if t.timer >= t.interval then
        if t.count == 0 then
          s.hidden = false
          t.done = true
        else
          s.hidden = not s.hidden
          t.count = t.count - 1
          t.timer = 0
        end
      else
        t.timer = t.timer + 1
      end
    end, { count = H.var(player, 0) * 2, interval = H.var(player, 1), timer = 0 })
  end

  -- -------------------------------------------------------------------------
  -- 51 MoveBattlerX (script_funcs_3.c)
  --
  -- PosLerp of MON_SPRITE_X_CENTER by `offset * dir` over `frames`. It does
  -- NOT come back: ExtremeSpeed steps the attacker forward 8 three times and
  -- `MoveBattlerX2` (52) takes it back 24. The partner targets give no battler
  -- in a single battle and start nothing.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[51] = function(player)
    local frames = H.var(player, 0)
    local offset = H.var(player, 1)
    local target = H.var(player, 2)
    local side
    if target == T_BATTLER_SPRITE_ATTACKER then
      side = H.attacker(player)
    elseif target == T_BATTLER_SPRITE_DEFENDER then
      side = H.defender(player)
    else
      return
    end
    if H.dirX(side) <= 0 then offset = -offset end
    local s0 = H.state(player, side)
    local x0, y0 = s0.dx or 0, s0.dy or 0
    H.task(player, function(p, t)
      if t.state == 0 then
        t.pos = Gen4AnimMath.posLerp(x0, x0 + offset, y0, y0, frames)
        t.state = 1
      elseif t.state == 1 then
        if not Gen4AnimMath.posLerpUpdate(t.pos) then t.state = 2 end
        H.state(p, side).dx = t.pos.x
      else
        t.done = true
      end
    end)
  end

  -- -------------------------------------------------------------------------
  -- 53 ShakeAndScaleAttacker (script_funcs_3.c)
  --
  -- Scale 100 -> var0 (percent) over var2 frames while a 2-pixel shake
  -- (interval 0: every frame, 10 cycles) is ADDED to MON_SPRITE_X_CENTER --
  -- `AddAttribute`, so the flips accumulate and the battler oscillates between
  -- x and x + 2 -- hold var4 + 1 frames, scale var0 -> var1 over var3, then one
  -- more frame and back to 1.0. X is never reset: Spit Up's ten shake frames
  -- end two pixels over, as the cartridge's do.
  -- -------------------------------------------------------------------------

  local BASE_SCALE_XY = 100

  Extras.FUNCS[53] = function(player)
    local scale1 = H.var(player, 0)
    local scale2 = H.var(player, 1)
    local frames1 = H.var(player, 2)
    local frames2 = H.var(player, 3)
    local hold = H.var(player, 4)
    local side = H.attacker(player)
    local y0 = H.state(player, side).dy or 0
    H.task(player, function(p, t)
      local s = H.state(p, side)
      local st = t.state
      if st == 0 then
        if Gen4AnimMath.scaleLerpUpdate(t.scale) then
          H.shakeUpdate(t.shake)
          s.sx, s.sy = t.scale.x / AFFINE_ONE, t.scale.y / AFFINE_ONE
          s.dx = (s.dx or 0) + t.shake.x
          s.dy = y0
        else
          t.state = 1
        end
      elseif st == 1 then
        t.timer = t.timer + 1
        if t.timer > hold then
          t.scale = Gen4AnimMath.scaleLerp(scale1, BASE_SCALE_XY, scale2, frames2)
          t.state = 2
        end
      elseif st == 2 or st == 3 then
        if Gen4AnimMath.scaleLerpUpdate(t.scale) then
          s.sx, s.sy = t.scale.x / AFFINE_ONE, t.scale.y / AFFINE_ONE
          s.dy = y0
        elseif st == 2 then
          t.state = 3
        else
          s.sx, s.sy = 1, 1
          s.dy = y0
          t.state = 4
        end
      else
        t.done = true
      end
    end, {
      timer = 0,
      scale = Gen4AnimMath.scaleLerp(BASE_SCALE_XY, BASE_SCALE_XY, scale1, frames1),
      shake = H.shake(2, 0, 0, 10),
    })
  end

  -- -------------------------------------------------------------------------
  -- 54 ShakeAndScaleAttacker2 (script_funcs_3.c) -- no program calls it
  --
  -- The same with separate X/Y scales, each var packing start (high 16) and
  -- end (low 8), anchored at the DEFAULT position rather than the current one.
  -- -------------------------------------------------------------------------

  local function packStart(v) return floor(v / 65536) end   -- `(scale) >> 16`
  local function packEnd(v) return v % 256 end              -- `(scale) & 0xFF`

  Extras.FUNCS[54] = function(player)
    local s1x, s1y = H.var(player, 0), H.var(player, 1)
    local frames1 = H.var(player, 2)
    local s2x, s2y = H.var(player, 3), H.var(player, 4)
    local frames2 = H.var(player, 5)
    local hold = H.var(player, 6)
    local side = H.attacker(player)
    H.task(player, function(p, t)
      local s = H.state(p, side)
      local st = t.state
      if st == 0 then
        if H.scaleXYUpdate(t.scale) then
          H.shakeUpdate(t.shake)
          s.sx, s.sy = t.scale.x / AFFINE_ONE, t.scale.y / AFFINE_ONE
          s.dx = (s.dx or 0) + t.shake.x
          s.dy = 0
        else
          t.state = 1
        end
      elseif st == 1 then
        t.timer = t.timer + 1
        if t.timer > hold then
          t.scale = H.scaleXY(packStart(s2x), packEnd(s2x), packStart(s2y), packEnd(s2y),
                              BASE_SCALE_XY, frames2)
          t.state = 2
        end
      elseif st == 2 or st == 3 then
        if H.scaleXYUpdate(t.scale) then
          s.sx, s.sy = t.scale.x / AFFINE_ONE, t.scale.y / AFFINE_ONE
          s.dy = 0
        elseif st == 2 then
          t.state = 3
        else
          s.sx, s.sy = 1, 1
          s.dy = 0
          t.state = 4
        end
      else
        t.done = true
      end
    end, {
      timer = 0,
      scale = H.scaleXY(packStart(s1x), packEnd(s1x), packStart(s1y), packEnd(s1y),
                        BASE_SCALE_XY, frames1),
      shake = H.shake(2, 0, 0, 10),
    })
  end

  -- -------------------------------------------------------------------------
  -- 56 Superpower (script_funcs_3.c)
  --
  -- Loads the base BG and shows it only through an OBJ window cut by copy 0
  -- at 1.2x -- and the task takes it all down again on its first (and only)
  -- step. One step of time; the window is not drawn.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[56] = function(player)
    H.note(player, "Superpower: base BG through the copy's OBJ window")
    H.task(player, function(p, t) t.done = true end)
  end

  -- -------------------------------------------------------------------------
  -- 61 MoveBattlerOffScreen / 77 MoveBattlerOnOrOffScreen (script_funcs_3.c)
  --
  -- PosLerp from where the battler stands to x = -80 (player side) or 336
  -- (enemy side), or from there back to its default x. It stays where the lerp
  -- leaves it: Whirlwind and Roar hide it and `MoveBattlerToDefaultPos` (62)
  -- puts it back.
  -- -------------------------------------------------------------------------

  local function offScreenX(side)
    if side then return -MON_FRAME_W end
    return LCD_W + MON_FRAME_W
  end

  local function startMoveBattlerOffScreen(player, side, fromX, toX, frames)
    local y = H.state(player, side).dy or 0
    local rx = restX(side)
    -- Absolute screen x, as the C lerps it, then back to an offset.
    local pos = Gen4AnimMath.posLerp(fromX, toX, y, y, frames)
    H.task(player, function(p, t)
      if t.state == 0 then
        if not Gen4AnimMath.posLerpUpdate(pos) then t.state = 1 end
        local s = H.state(p, side)
        s.dx = pos.x - rx
        s.dy = pos.y
      else
        t.done = true
      end
    end)
  end

  Extras.FUNCS[61] = function(player)
    local side = sideForTarget(player, H.var(player, 0))
    if side == nil then return end
    local frames = H.var(player, 1)
    local curX = restX(side) + (H.state(player, side).dx or 0)
    startMoveBattlerOffScreen(player, side, curX, offScreenX(side), frames)
  end

  local MOVE_BATTLER_OFF_SCREEN = 0

  Extras.FUNCS[77] = function(player)
    local mode = H.var(player, 0)
    local side = sideForTarget(player, H.var(player, 1))
    if side == nil then return end
    local frames = H.var(player, 2)
    if mode == MOVE_BATTLER_OFF_SCREEN then
      local curX = restX(side) + (H.state(player, side).dx or 0)
      startMoveBattlerOffScreen(player, side, curX, offScreenX(side), frames)
    else
      startMoveBattlerOffScreen(player, side, offScreenX(side), restX(side), frames)
    end
  end

  -- 62 MoveBattlerToDefaultPos: X = default x, Y = default y + height, which is
  -- exactly the rest position. Immediate, no task.
  Extras.FUNCS[62] = function(player)
    local side = sideForTarget(player, H.var(player, 0))
    if side == nil then return end
    local s = H.state(player, side)
    s.dx, s.dy = 0, 0
  end

  -- -------------------------------------------------------------------------
  -- 63 FadePokemonSprite (script_funcs_3.c)
  --
  -- A PaletteFadeContext on ONE copy's OBJ palette: blend at `fraction` every
  -- `stepFrames` frames, then step toward the end by `step` (clamped); it goes
  -- inactive on the application AT the end value, and the task ends the frame
  -- it sees that. The blend STAYS on the palette -- nothing un-blends it -- so
  -- the tint is kept on the copy until the copy is removed.
  --
  -- !! WHICH COPY: `BattleAnimUtil_GetPokemonSprites` indexes the copies by
  -- the running COUNT, not by the bit, so the first set bit of any target
  -- names copy 0. Toxic passes POKEMON_SPRITE_2 and fades copy 0. Reproduced.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[63] = function(player)
    local target = H.var(player, 0)
    local stepFrames = H.var(player, 1)
    local step = H.var(player, 2)
    local startFrac = H.var(player, 3)
    local endFrac = H.var(player, 4)
    local colour = H.var(player, 5)
    local any = false
    for bit = 1, 4 do
      if hasBit(target, 2 ^ bit) then any = true end
    end
    if not any then return end
    local slot = 0
    local rec = player.monSprites and player.monSprites[slot]
    if startFrac >= endFrac then step = -step end
    local r, g, b = H.rgb(colour)
    local fade = {
      fraction = startFrac, finish = endFrac, step = step,
      stepFrames = stepFrames, timer = stepFrames, active = true,
    }
    local function pump()
      if not fade.active then return end
      fade.timer = fade.timer + 1
      if fade.timer >= fade.stepFrames then
        fade.timer = 0
        if rec then
          if fade.fraction <= 0 then
            copyTint[rec] = nil
          else
            copyTint[rec] = { r, g, b, min(16, fade.fraction) / 16 }
          end
        end
        if fade.fraction == fade.finish then
          fade.active = false
        else
          local newFrac = fade.fraction + fade.step
          if fade.step > 0 then
            if newFrac > fade.finish then fade.fraction = fade.finish else fade.fraction = newFrac end
          else
            if newFrac < fade.finish then fade.fraction = fade.finish else fade.fraction = newFrac end
          end
        end
      end
    end
    H.task(player, function(p, t)
      -- The fade's SysTask was started first at the same priority, so it runs
      -- ahead of this one every frame.
      pump()
      if not fade.active then t.done = true end
    end)
    if rec then ensureTintMirror(player, rec, slot) end
  end

  -- -------------------------------------------------------------------------
  -- 64 BattlerPartialDrawTest (script_funcs_3.c) -- no program calls it
  --
  -- Every `stepFrames` frames: clamp the draw height, write Y, then move Y by
  -- -step and the height by step. From a fully drawn battler both modes reach
  -- their limit on the first tick, so in practice this is a wait. The
  -- partial-draw clip itself is not drawn.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[64] = function(player)
    local side = sideForTarget(player, H.var(player, 0))
    if side == nil then return end
    local mode = H.var(player, 1)
    local step = H.var(player, 3)
    local stepFrames = H.var(player, 4)
    local s0 = H.state(player, side)
    local drawHeight
    if mode == 0 then
      -- MON_FRAME_H - MON_SPRITE_DRAW_HEIGHT, and a battler at rest draws all 80.
      drawHeight = 0
      step = -step
    else
      drawHeight = MON_FRAME_H
    end
    H.note(player, "BattlerPartialDrawTest: partial-draw clip")
    H.task(player, function(p, t)
      local s = H.state(p, side)
      if t.state == 0 then
        t.timer = t.timer + 1
        if t.timer < stepFrames then return end
        t.timer = 0
        if mode == 0 then
          if t.drawHeight < 0 then t.drawHeight = 0 end
          if t.drawHeight == 0 then t.state = 1 end
        else
          if t.drawHeight > MON_FRAME_H then t.drawHeight = MON_FRAME_H end
          if t.drawHeight == MON_FRAME_H then t.state = 1 end
        end
        s.dy = t.y
        t.y = t.y - step
        t.drawHeight = t.drawHeight + step
      else
        s.sx, s.sy = 1, 1
        t.done = true
      end
    end, { timer = 0, y = s0.dy or 0, drawHeight = drawHeight })
  end

  -- -------------------------------------------------------------------------
  -- 67 BattlerPartialDraw (script_funcs_3.c)
  --
  -- Dig's sink and rise. Every `interval` frames the battler moves `step`
  -- pixels down (up for a negative step) while MON_SPRITE_DRAW_HEIGHT shrinks
  -- (grows) by the same amount, so it goes into the ground at its own foot.
  -- Sketch mode instead reveals the picture bottom-up in place.
  --
  -- THE CLIP IS DRAWN AS A FOOT-ANCHORED SQUASH: the visible part of the
  -- cartridge's picture occupies exactly the rows from (top + moved) down to
  -- the foot, which is the rectangle sy = drawn / height covers when the draw
  -- pivots on the foot. Same screen area, squashed content.
  -- -------------------------------------------------------------------------

  Extras.FUNCS[67] = function(player)
    local target = H.var(player, 0)
    local step = H.var(player, 3)
    local interval = H.var(player, 4)
    local sketch = H.var(player, 5) ~= 0
    local side = sideForTarget(player, target)
    if side == nil then return end
    local height = MON_FRAME_H - H.spriteOffset(player, side)
    if height <= 0 then height = MON_FRAME_H end
    local s0 = H.state(player, side)
    local baseDy = s0.dy or 0
    H.note(player, "BattlerPartialDraw: partial-draw clip drawn as a foot-anchored squash")

    if sketch then
      local t0 = { yOffset = height, height = 0, timer = 0 }
      s0.sy = 0
      H.task(player, function(p, t)
        local s = H.state(p, side)
        if t.state == 0 then
          t.timer = t.timer + 1
          if t.timer < interval then return end
          t.timer = 0
          t.yOffset = t.yOffset - step
          t.height = t.height + step
          if t.yOffset < 0 then
            t.yOffset = 0
            t.state = 1
          end
          s.sy = max(0, min(1, t.height / height))
        else
          s.sx, s.sy = 1, 1
          t.done = true
        end
      end, t0)
      return
    end

    local opts = { timer = 0, height = height }
    if step > 0 then
      opts.yOffset = height
      s0.sy = 1
    else
      opts.yOffset = 0
      s0.sy = 0
    end
    H.task(player, function(p, t)
      local s = H.state(p, side)
      if t.state == 0 then
        t.timer = t.timer + 1
        if t.timer < interval then return end
        t.timer = 0
        t.yOffset = t.yOffset - step
        if step > 0 then
          if t.yOffset < 0 then
            t.yOffset = 0
            t.state = 1
          end
        else
          if t.yOffset > t.height then
            t.yOffset = t.height
            t.state = 1
          end
        end
        s.sy = max(0, min(1, t.yOffset / t.height))
        s.dy = baseDy
      else
        s.dy = baseDy
        s.sx, s.sy = 1, 1
        t.done = true
      end
    end, opts)
  end

  -- -------------------------------------------------------------------------
  -- 69 PixelatePokemonSprite (script_funcs_3.c)
  --
  -- The OBJ mosaic on one copy, stepped from (startX, startY) toward 0 or 15
  -- by `step` a frame (the last step snaps to the target); the task ends on
  -- the step that finds the target reached. The function also runs the task
  -- body once itself right after starting it. Mosaic size N is N + 1-pixel
  -- blocks, which is this port's `mosaic`.
  -- -------------------------------------------------------------------------

  local PIXELATE_MIN, PIXELATE_MAX = 0, 15

  Extras.FUNCS[69] = function(player)
    local slot = H.var(player, 0)
    local step = H.var(player, 1)
    local rec = player.monSprites and player.monSprites[slot]
    if rec then rec.visible = true end
    local targetScale = (step < PIXELATE_MIN) and PIXELATE_MIN or PIXELATE_MAX
    local function body(p, t)
      copyClear(p, t)
      if t.x == targetScale or t.y == targetScale then
        t.done = true
        return
      end
      if step < 0 then
        if t.x + step > PIXELATE_MIN then
          t.x, t.y = t.x + step, t.y + step
        else
          t.x, t.y = targetScale, targetScale
        end
      else
        if t.x + step < PIXELATE_MAX then
          t.x, t.y = t.x + step, t.y + step
        else
          t.x, t.y = targetScale, targetScale
        end
      end
      copyShow(p, t, p.monSprites and p.monSprites[slot], { mosaic = t.x + 1 })
    end
    local t = H.task(player, body, {
      renders = true, x = H.var(player, 2), y = H.var(player, 3),
    })
    body(player, t)
  end

  -- -------------------------------------------------------------------------
  -- 76 ScrollSwitchedBg (script_funcs_3.c)
  --
  -- A ScreenScrollManager on the effect layer: rows 0..160 offset by a
  -- 192-entry sine table (1 degree per entry, amplitude 32), its read position
  -- advancing 2 entries a frame (speed 200 / scale 100). The manager is a
  -- priority-0 SysTask, so it first runs the frame after this task creates it,
  -- and then ahead of it. `player.bgScroll.x` is the rows' mean offset (a
  -- whole-layer approximation of the wave) and `.rows` the full per-row table
  -- (BG offset register values: positive moves the picture left).
  -- -------------------------------------------------------------------------

  local SCROLL_START_Y, SCROLL_END_Y = 0, 160
  local SCROLL_TABLE_SIZE = 192
  local SCROLL_SCALE = 100
  local SCROLL_SPEED = 200
  local SCROLL_MAX = SCROLL_TABLE_SIZE * SCROLL_SCALE
  local scrollSine = nil

  local function scrollSineTable()
    if scrollSine then return scrollSine end
    scrollSine = {}
    local inc = H.degToIdx(1)
    local angle = 0
    for i = 0, SCROLL_TABLE_SIZE - 1 do
      scrollSine[i] = shr12(fxMul(sinIdx(angle), 32 * FX_ONE))
      angle = (angle + inc) % 65536
    end
    return scrollSine
  end

  local function scrollSwitchedBgUpdate(p, t)
    local tbl = scrollSineTable()
    local pos = floor(t.scrollPos / SCROLL_SCALE) % 256
    local rows, sum, n = {}, 0, 0
    for i = SCROLL_START_Y, SCROLL_END_Y do
      rows[i] = tbl[pos % SCROLL_TABLE_SIZE]
      sum, n = sum + rows[i], n + 1
      pos = (pos + 1) % SCROLL_TABLE_SIZE
    end
    t.scrollPos = t.scrollPos + SCROLL_SPEED
    if t.scrollPos >= SCROLL_MAX then t.scrollPos = t.scrollPos % SCROLL_MAX end
    -- Whole layer: the rows' mean offset (where the layer's mass goes).
    local mean = (n > 0) and floor(sum / n + 0.5) or 0
    p.bgScroll = { x = mean, y = 0, rows = rows, rowsStart = SCROLL_START_Y }
    t.wrote = p.bgScroll
  end

  Extras.FUNCS[76] = function(player)
    local frames = H.var(player, 0)
    H.task(player, function(p, t)
      if t.state == 0 then
        t.timer = 0
        t.scrollPos = 0
        t.state = 1
        return
      end
      scrollSwitchedBgUpdate(p, t)
      t.timer = t.timer + 1
      if t.timer < frames then return end
      if p.bgScroll == t.wrote then p.bgScroll = nil end
      t.done = true
    end)
  end

  -- -------------------------------------------------------------------------
  -- Sprite 12 Torment (script_funcs_2.c)
  --
  -- Six speech bubbles from one template on an arc of radius 48 over the
  -- attacker (pairs at 0, 30 and 60 degrees, the left one of each pair
  -- mirrored), shown one at a time: each pops while the attacker squashes
  -- (0.9 x 0.8, then 1.1 x 1.5, then 1.0, two frames each, foot-anchored),
  -- switches to its second sequence, waits (8 frames for the first pair, none
  -- after), then all six play again together.
  --
  -- ANIMATION CLOCK: animate flag on, speed 2, so +2 a frame from
  -- `SpriteSystem_DrawSprites` at the end of each task frame; the init also
  -- jumps 55 frames ahead (`TickNFrames(FX32_CONST(55))`, taken here as 55 at
  -- the sprite's speed).
  -- -------------------------------------------------------------------------

  local TORMENT_COUNT = 6
  local TORMENT_SPEED = 2
  local TORMENT_PRETICK = 55
  local TORMENT_DELAY = 8
  local TORMENT_STEPS = 2

  local function tormentInitBubble(ctx, i)
    local s = ctx.sprites[i + 1]
    ctx.bubbleState[i] = 0
    s.visible = true
    ctx.animSpeed[i] = TORMENT_SPEED
    setAnim(ctx, s, 0)
    s.animTick = min(s.length or 0, TORMENT_PRETICK * TORMENT_SPEED)
  end

  local function tormentUpdateBubble(ctx, i)
    if ctx.bubbleState[i] == 0 then
      if animDone(ctx.sprites[i + 1]) then
        ctx.bubbleState[i] = 1
        return true
      end
      return false
    end
    return true
  end

  local function tormentApplyScale(ctx)
    local s = ctx.player.state[ctx.side]
    s.sx, s.sy = ctx.scale.x / AFFINE_ONE, ctx.scale.y / AFFINE_ONE
  end

  local function tormentUpdateScale(ctx)
    local st = ctx.scaleState
    if st == 0 then
      if H.scaleXYUpdate(ctx.scale) then tormentApplyScale(ctx)
      else
        ctx.scaleState = 1
        ctx.scale = H.scaleXY(9, 11, 8, 15, 10, TORMENT_STEPS)
      end
    elseif st == 1 then
      if H.scaleXYUpdate(ctx.scale) then tormentApplyScale(ctx)
      else
        ctx.scaleState = 2
        ctx.scale = H.scaleXY(11, 10, 15, 10, 10, TORMENT_STEPS)
      end
    elseif st == 2 then
      if H.scaleXYUpdate(ctx.scale) then tormentApplyScale(ctx)
      else
        local s = ctx.player.state[ctx.side]
        s.sx, s.sy = 1, 1
        ctx.scaleState = 3
        return true
      end
    else
      return true
    end
    return false
  end

  Extras.SPRITES[12] = {
    name = "Torment",
    count = TORMENT_COUNT,
    start = function(ctx)
      ctx.side = ctx.attackerIsPlayer and true or false
      ctx.bubbleState, ctx.animSpeed, ctx.endDelay = {}, {}, {}
      local arc = idiv(H.degToIdx(90), TORMENT_COUNT / 2)
      for i = 0, TORMENT_COUNT - 1 do
        local s = ctx.sprites[i + 1]
        s.visible = false
        s.origin = "attacker"
        local a = arc * floor(i / 2)
        local offX = shr12(fxMul(cosIdx(a), 48 * FX_ONE))
        local offY = shr12(fxMul(sinIdx(a), 48 * FX_ONE))
        if i % 2 == 0 then
          s.sx = offX
          s.flipX = true
        else
          s.sx = -offX
        end
        s.sy = -offY
        ctx.endDelay[i] = (i < 2) and TORMENT_DELAY or 0
        ctx.bubbleState[i] = 0
      end
      ctx.state = 0
      ctx.cur = 0
      ctx.scaleState = 3
    end,
    step = function(ctx)
      local st = ctx.state
      if st == 0 then
        ctx.scaleState = 0
        ctx.scale = H.scaleXY(10, 9, 10, 8, 10, TORMENT_STEPS)
        tormentInitBubble(ctx, ctx.cur)
        ctx.state = 1
      elseif st == 1 then
        local a = tormentUpdateScale(ctx)
        local b = tormentUpdateBubble(ctx, ctx.cur)
        if a and b then
          setAnim(ctx, ctx.sprites[ctx.cur + 1], 1)
          ctx.state = 2
        end
      elseif st == 2 then
        ctx.endDelay[ctx.cur] = ctx.endDelay[ctx.cur] - 1
        if ctx.endDelay[ctx.cur] < 0 then
          ctx.cur = ctx.cur + 1
          if ctx.cur < TORMENT_COUNT then ctx.state = 0 else ctx.state = 3 end
        end
      elseif st == 3 then
        for i = 0, TORMENT_COUNT - 1 do tormentInitBubble(ctx, i) end
        ctx.state = 4
      elseif st == 4 then
        local last = false
        for i = 0, TORMENT_COUNT - 1 do last = tormentUpdateBubble(ctx, i) end
        if last then ctx.state = 5 end
      else
        return false
      end
      for i = 0, TORMENT_COUNT - 1 do
        local sp = ctx.animSpeed[i]
        local s = ctx.sprites[i + 1]
        if sp and not animDone(s) then s.animTick = min(s.length, s.animTick + sp) end
      end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- Sprite 13 BatonPass (script_funcs_2.c)
  --
  -- The ball plays its first sequence at the attacker; then the attacker
  -- shrinks to nothing over 8 frames (scale 10 -> 0, about its CENTRE) while
  -- sliding back to its default position, is hidden, and the ball plays its
  -- second sequence and flies straight up off the top over 8 frames. The
  -- attacker is left hidden, as the C leaves it.
  -- -------------------------------------------------------------------------

  local BATON_PASS_FRAMES = 8

  Extras.SPRITES[13] = {
    name = "BatonPass",
    count = 1,
    start = function(ctx)
      ctx.side = ctx.attackerIsPlayer and true or false
      local st = ctx.player.state[ctx.side]
      st.hidden = false
      local s = ctx.sprites[1]
      s.origin = "attacker"
      s.sx, s.sy = 0, 0
      ctx.animating = false
      ctx.state = 0
    end,
    step = function(ctx)
      local s = ctx.sprites[1]
      local st = ctx.player.state[ctx.side]
      local state = ctx.state
      if state == 0 then
        ctx.animating = true
        ctx.state = 1
      elseif state == 1 then
        if animDone(s) then
          ctx.animating = false
          ctx.state = 2
          ctx.scale = Gen4AnimMath.scaleLerp(10, 10, 0, BATON_PASS_FRAMES)
          -- From where it stands to its default position.
          ctx.pos = Gen4AnimMath.posLerp(st.dx or 0, 0, st.dy or 0, 0, BATON_PASS_FRAMES)
          ctx.py = st.dy or 0
        end
      elseif state == 2 then
        if Gen4AnimMath.posLerpUpdate(ctx.pos) then
          st.dx = ctx.pos.x
          ctx.py = ctx.pos.y
          st.dy = ctx.py
        end
        if Gen4AnimMath.scaleLerpUpdate(ctx.scale) then
          local k = ctx.scale.x / AFFINE_ONE
          st.sx, st.sy = k, k
          -- The C scales about the centre; this draw pivots on the foot, so the
          -- centre is held still by lifting the foot.
          st.dy = ctx.py - MON_HALF * (1 - k)
        else
          st.hidden = true
          st.sx, st.sy = 1, 1
          st.dy = ctx.py
          setAnim(ctx, s, 1)
          ctx.animating = true
          ctx.state = 3
        end
      elseif state == 3 then
        if animDone(s) then
          ctx.animating = false
          ctx.state = 4
          local _, ay = H.centre(ctx.side)
          ctx.ball = Gen4AnimMath.posLerp(0, 0, ay, 0, BATON_PASS_FRAMES)
        end
      elseif state == 4 then
        if Gen4AnimMath.posLerpUpdate(ctx.ball) then
          s.absoluteY = ctx.ball.y
        else
          ctx.state = 5
        end
      else
        return false
      end
      if ctx.animating and not animDone(s) then s.animTick = s.animTick + 1 end
      return true
    end,
  }

  -- -------------------------------------------------------------------------
  -- Sprite 15 Grudge (script_funcs_2.c)
  --
  -- Six flames revolving half a turn round the attacker over 48 frames
  -- (radius 50 in X, 60 degrees apart, the direction mirrored on the enemy
  -- side) with a vertical bob of sin(5 * angle) * 10, fading in 1 -> 16 over
  -- 10 frames, holding 29, fading out over 10. The fades are AlphaFadeContexts
  -- (priority 0: pumped at the top of the frame, created further down). The
  -- flames behind the Pokemon (angles 90..269) drop to priority 1; this port's
  -- sprite layer has one depth, so they stay in front.
  -- -------------------------------------------------------------------------

  local GRUDGE_COUNT = 6
  local GRUDGE_END_ANGLE = H.degToIdx(180)
  local GRUDGE_RADIUS = 50 * FX_ONE
  local GRUDGE_FRAMES = 48
  local GRUDGE_START_ALPHA = 1
  local GRUDGE_END_ALPHA = 16
  local GRUDGE_MAX_ALPHA = 16
  local GRUDGE_FADE_FRAMES = 10
  local GRUDGE_X_SCALE = 5
  local GRUDGE_Y_SCALE = 10 * FX_ONE

  local function grudgeInitRevs(ctx)
    local angleStep = idiv(H.degToIdx(360), GRUDGE_COUNT)
    ctx.revs = {}
    for i = 0, GRUDGE_COUNT - 1 do
      local r = Gen4AnimMath.revolution(0, GRUDGE_END_ANGLE, 0, 0, GRUDGE_RADIUS, 0, GRUDGE_FRAMES)
      r.curX = r.curX + angleStep * i
      r.stepX = r.stepX * ctx.dir
      ctx.revs[i] = r
    end
  end

  local function grudgeUpdateRevs(ctx)
    for i = 0, GRUDGE_COUNT - 1 do
      local r = ctx.revs[i]
      Gen4AnimMath.revolutionUpdate(r)
      local angle = (r.curX * GRUDGE_X_SCALE) % 65536
      local offY = shr12(fxMul(sinIdx(angle), GRUDGE_Y_SCALE * ctx.dir))
      local s = ctx.sprites[i + 1]
      s.sx, s.sy = r.x, offY
    end
  end

  local function grudgeAlpha(ctx, a)
    for i = 1, GRUDGE_COUNT do ctx.sprites[i].alpha = a end
  end

  Extras.SPRITES[15] = {
    name = "Grudge",
    count = GRUDGE_COUNT,
    start = function(ctx)
      ctx.dir = H.dirX(ctx.attackerIsPlayer)
      for i = 1, GRUDGE_COUNT do
        local s = ctx.sprites[i]
        s.origin = "attacker"
        s.sx, s.sy = 0, 0
      end
      -- XLU before any blend is set: start them at the fade's first value.
      grudgeAlpha(ctx, GRUDGE_START_ALPHA / GRUDGE_MAX_ALPHA)
      ctx.state = 0
    end,
    step = function(ctx)
      if ctx.fade then
        Gen4AnimMath.alphaFadeUpdate(ctx.fade)
        grudgeAlpha(ctx, Gen4AnimMath.blendAlpha(ctx.fade))
      end
      local st = ctx.state
      if st == 0 then
        ctx.fade = Gen4AnimMath.alphaFade(GRUDGE_START_ALPHA, GRUDGE_END_ALPHA,
                                          GRUDGE_MAX_ALPHA - GRUDGE_START_ALPHA,
                                          GRUDGE_MAX_ALPHA - GRUDGE_END_ALPHA,
                                          GRUDGE_FADE_FRAMES)
        grudgeAlpha(ctx, GRUDGE_START_ALPHA / GRUDGE_MAX_ALPHA)
        grudgeInitRevs(ctx)
        grudgeUpdateRevs(ctx)
        ctx.state = 1
      elseif st == 1 then
        grudgeUpdateRevs(ctx)
        if Gen4AnimMath.alphaFadeDone(ctx.fade) then
          ctx.state = 2
          ctx.delay = GRUDGE_FRAMES - 2 * GRUDGE_FADE_FRAMES
        end
      elseif st == 2 then
        grudgeUpdateRevs(ctx)
        ctx.delay = ctx.delay - 1
        if ctx.delay < 0 then
          ctx.state = 3
          ctx.fade = Gen4AnimMath.alphaFade(GRUDGE_END_ALPHA, GRUDGE_START_ALPHA,
                                            GRUDGE_MAX_ALPHA - GRUDGE_END_ALPHA,
                                            GRUDGE_MAX_ALPHA - GRUDGE_START_ALPHA,
                                            GRUDGE_FADE_FRAMES)
        end
      elseif st == 3 then
        grudgeUpdateRevs(ctx)
        if Gen4AnimMath.alphaFadeDone(ctx.fade) then ctx.state = 4 end
      else
        return false
      end
      -- Animate flag on: the sprite system advances each flame every frame.
      for i = 1, GRUDGE_COUNT do
        local s = ctx.sprites[i]
        s.animTick = s.animTick + 1
      end
      return true
    end,
  }
end
