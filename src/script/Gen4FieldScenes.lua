-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SCRIPTED FIELD PICTURES that were lowered to `g4_noop` -- the sound played
-- and the picture did not.  Each command blocks exactly as the cartridge's
-- handler does (a TaskManager_Call / FieldTask_InitCall holds the script
-- until the task returns; a handler that returns FALSE does not wait).
--
-- HEARTGOLD / SOULSILVER (pokeheartgold):
--   ScrCmd_708 <n>  the hideout floor trap's flash        waits  (HgssHideoutFx)
--   ScrCmd_709      the Persian statues' alarm           waits  (HgssHideoutFx)
--   ScrCmd_710      the hideout generators' animations   no wait
--                   (src/overlay_03/shop_menu.c: props 149/152/153 get
--                   animation FLAG_UNK_96B+i attached; Gen4PropControl)
-- PLATINUM (pokeplatinum):
--   InitLakeGuardianContainmentUnits         no wait  (lake_guardian_
--   DeactivateLakeGuardianContainmentUnits   waits     containment_units.c)
--   PlayHallOfFameHealingAnimation <count>   waits    (healing_machine_
--                                                      animation/hall_of_fame.c)
--   StartLibraryTV                           waits    (library_tv.c, the app:
--                                                      src/ui/Gen4LibraryTvScreen)
--
-- TIMING: every task below steps once per FIELD frame, two engine ticks,
-- driven from the script runner's own per-tick poll (`waitingCheck`) -- the
-- runner is what the cartridge's task holds, so it is what ticks the task.
-- Prop animation frames are read off the ground's frame clock
-- (Gen4PropControl / Gen4PropClock.fieldFrame), the same clock that draws them.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}
M.TICKS_PER_FRAME = 2

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function flag(ctx, id)
  local flags = ctx.save and ctx.save.flags
  return flags and flags[("FLAG_G4_%04X"):format(id)] and true or false
end
local function groundOf(ctx)
  local ow = ctx.overworld
  return ow and ow.map and ow.map.renderer and ow.map.renderer.gen4Ground or nil
end
local function Control() return require("src.render.Gen4PropControl") end
local function propId(name)
  local okA, A = pcall(require, "src.import.Gen4Archives")
  return okA and A.find and A.find("/fielddata/build_model/build_model.narc", name) or nil
end

-- block the script on `step`, called once per FIELD frame until it says done
local function waitFrames(ctx, step)
  local runner = ctx.runner
  if not runner then
    for _ = 1, 100000 do if step() then return end end
    return
  end
  local tick = 0
  runner.waitingCheck = function()
    tick = tick + 1
    if tick % M.TICKS_PER_FRAME ~= 0 then return false end
    return step() and true or false
  end
  runner:yield()
end

-- ------------------------------------------------- HGSS: Mahogany hideout --
function Commands.g4_hgss_trap_flash(ctx, variant)
  local Fx = require("src.world.HgssHideoutFx")
  if not Fx.startTrap(valueOf(ctx, variant)) then
    Logger.warn("hgss trap flash: no trap art in this cache (re-import: hgss_screens)")
    return
  end
  local runner = ctx.runner
  if not runner then Fx.reset() return end
  runner.waitingCheck = function()
    Fx.tick(ctx.overworld)
    return Fx.trap == nil
  end
  runner:yield()
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_trap_flash = { foreground = true, blocking = true }

function Commands.g4_hgss_statue_alarm(ctx)
  local Fx = require("src.world.HgssHideoutFx")
  Fx.startAlarm()
  local runner = ctx.runner
  if not runner then Fx.reset() return end
  runner.waitingCheck = function()
    Fx.tick(ctx.overworld)
    return Fx.alarm == nil
  end
  runner:yield()
end
Commands.meta.g4_hgss_statue_alarm = { foreground = true, blocking = true }

-- ScrCmd_710: ov03_0225945C { 149, 152, 153 } (room props aji_mech01..03,
-- /a/1/0/8 flags 2: loaded, not attached); each gets its list's animation
-- sub_020669B4(i) = FLAG_UNK_96B + i attached -- the list records read off
-- the ROM give { 86 aji_mech, 87 aji_mech_stop } for all three -- with the
-- loader's loop count -1, so it runs on the clock from then on.
M.HIDEOUT_MACHINES = { 149, 152, 153 }
M.HIDEOUT_MACHINE_ANIMS = { [0] = 86, [1] = 87 }
M.FLAG_MACHINE_STOPPED = 0x96B
function Commands.g4_hgss_hideout_machines(ctx)
  local ground = groundOf(ctx)
  if not ground then return end
  for i, model in ipairs(M.HIDEOUT_MACHINES) do
    local which = flag(ctx, M.FLAG_MACHINE_STOPPED + i - 1) and 1 or 0
    -- the cartridge runs this from OnResume, on a freshly built field with
    -- nothing attached; this port can keep a ground across a battle or a
    -- same-map warp, so the other animation is detached first
    Control().set(ground, model, M.HIDEOUT_MACHINE_ANIMS[1 - which], nil)
    Control().set(ground, model, M.HIDEOUT_MACHINE_ANIMS[which], { attach = true })
  end
end

-- ------------------------------------- Platinum: lake guardian containment --
-- prop 496 lake_guardian_containment_unit, bm_anime_list record { 48, 49 }:
-- 48 the glow (BTA0, 61 frames), 49 the unit (BCA0) -- both attached and
-- looping when the map loads (flags 0)
M.UNIT_PROP = "lake_guardian_containment_unit.nsbmd"
M.UNIT_GLOW, M.UNIT_BODY = 48, 49
M.FLAG_FREED = 0x97D   -- FLAG_FREED_GALACTIC_HQ_POKEMON

function Commands.g4_containment_init(ctx)
  local ground, model = groundOf(ctx), propId(M.UNIT_PROP)
  if not (ground and model) then return end
  if not flag(ctx, M.FLAG_FREED) then
    -- anim 1: loop count 1, paused (at its first frame: it was just loaded)
    Control().set(ground, model, M.UNIT_BODY, { hold = 0 })
  else
    -- anim 0 paused; anim 1 on its last frame, paused
    Control().set(ground, model, M.UNIT_GLOW, { hold = 0 })
    Control().set(ground, model, M.UNIT_BODY, { hold = "last" })
  end
end

function Commands.g4_containment_deactivate(ctx)
  local ground, model = groundOf(ctx), propId(M.UNIT_PROP)
  if not (ground and model and ground.animsByMember) then return end
  local glow = ground.animsByMember[M.UNIT_GLOW]
  local body = ground.animsByMember[M.UNIT_BODY]
  if not (glow and body) then return end
  local Clock = require("src.render.Gen4PropClock")
  local glowFrames = math.max(1, math.floor(tonumber(glow.frames) or 1))
  local bodyFrames = math.max(1, math.floor(tonumber(body.frames) or 1))
  -- state 0: run the glow out to its last frame (from wherever the clock has
  -- it now), then pause it there
  local fixed = Control().frameFor(ground, model, glow)
  local now = fixed or (Clock.fieldFrame(ground.clock or 0) % glowFrames)
  local left = (glowFrames - 1) - now
  local state = 0
  waitFrames(ctx, function()
    if state == 0 then
      if left > 0 then left = left - 1 return false end
      Control().set(ground, model, M.UNIT_GLOW, { hold = "last" })
      state = 1
      return false
    elseif state == 1 then
      -- unpause anim 1: it plays once from its paused first frame
      Control().set(ground, model, M.UNIT_BODY, { from = ground.clock or 0, once = true })
      left = bodyFrames - 1
      state = 2
      return false
    end
    if left > 0 then left = left - 1 return false end
    Control().set(ground, model, M.UNIT_BODY, { hold = "last" })
    return true
  end)
end
Commands.meta.g4_containment_deactivate = { foreground = true, blocking = true }

-- ------------------------------------------- Platinum: the Hall of Fame --
-- FieldTask_PlayHealingAnimation_HallOfFame: START; per ball ADD (a mini
-- ball at the machine + its offset) then WAIT_FOR_POKEBALL (15 frames
-- counted, the 16th moves on); PLAY_FINAL_ANIMATION (the balls' one-shot,
-- bm_anime 31 pc_mb); WAIT until its loop ends, the balls cleared;
-- CLEAN_UP.  No sound: the Pokemon Center's BOWA / ASA are not in this one.
M.HOF_MACHINE = "pokemon_league_hall_of_fame_machine.nsbmd"
M.MINI_BALL = "pokecenter_healing_machine_mini_pokeball.nsbmd"
M.BALL_FLIPBOOK = 31
M.BALL_TICKS = 15

function Commands.g4_hof_heal_animation(ctx, count)
  local ground = groundOf(ctx)
  local balls = math.max(0, math.min(6, valueOf(ctx, count)))
  if not (ground and ground.setHealingBalls) then return end
  local ball = propId(M.MINI_BALL)
  local flip = ground.animsByMember and ground.animsByMember[M.BALL_FLIPBOOK]
  local flipFrames = math.max(1, math.floor(tonumber(flip and flip.frames) or 1))
  local state, lit, ticks, left = "start", 0, 0, 0
  waitFrames(ctx, function()
    if state == "start" then
      state = balls > 0 and "add" or "final"
    elseif state == "add" then
      lit = lit + 1
      ground:setHealingBalls(lit, true, M.HOF_MACHINE)
      state = "wait"
    elseif state == "wait" then
      if ticks < M.BALL_TICKS then ticks = ticks + 1
      else
        ticks = 0
        state = lit < balls and "add" or "final"
      end
    elseif state == "final" then
      if ball and flip then
        Control().set(ground, ball, M.BALL_FLIPBOOK, { attach = true, from = ground.clock or 0, once = true })
      end
      left = flip and flipFrames or 0
      state = "waitFinal"
    elseif state == "waitFinal" then
      if left > 0 then left = left - 1 return false end
      if ball then Control().set(ground, ball, M.BALL_FLIPBOOK, nil) end
      ground:setHealingBalls(0)
      state = "cleanup"
    else
      return true
    end
    return false
  end)
end
Commands.meta.g4_hof_heal_animation = { foreground = true, blocking = true }

-- ------------------------------------------- Platinum: the library TV --
function Commands.g4_library_tv(ctx)
  local game = ctx.game
  local Screen = require("src.ui.Gen4LibraryTvScreen")
  if not (game and game.stack and Screen.available(game)) then
    Logger.warn("library tv: the art is not in this cache (re-import Platinum) -- nothing is shown")
    return
  end
  local runner = ctx.runner
  game.stack:push(Screen.new(game, function() if runner then runner:resume() end end))
  if runner then runner:yield() end
end
Commands.meta.g4_library_tv = { foreground = true, blocking = true }

-- ------------------------------------------------------------ the rows --
function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.scrcmd_708 = function(ins, s) emit(s, { "g4_hgss_trap_flash", ins.args[1] }) end
  L.scrcmd_709 = function(_, s) emit(s, { "g4_hgss_statue_alarm" }) end
  L.scrcmd_710 = function(_, s) emit(s, { "g4_hgss_hideout_machines" }) end
  L.initlakeguardiancontainmentunits = function(_, s) emit(s, { "g4_containment_init" }) end
  L.deactivatelakeguardiancontainmentunits = function(_, s) emit(s, { "g4_containment_deactivate" }) end
  L.playhalloffamehealinganimation = function(ins, s) emit(s, { "g4_hof_heal_animation", ins.args[1] }) end
  L.startlibrarytv = function(_, s) emit(s, { "g4_library_tv" }) end
end

return M
