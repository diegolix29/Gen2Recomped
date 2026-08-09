-- Driver: ONE shiny encounter, at real 1x speed, held open until you close
-- the window. Meant to be launched once per Pokemon by tests/shiny_run.sh.
--
--   DS_SPECIES=GYARADOS DS_LEVEL=45 DS_MAP=CERULEAN_CITY DS_CX=10 DS_CY=12 \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_one.lua \
--   "/c/Program Files/LOVE/lovec.exe" .
--
-- ------- why the pacing is done here
--
-- A driver run is deliberately UNPACED: main.lua's pacingEnabled() returns
-- false whenever POKEPORT_DRIVER is set, so love.run spins as fast as the
-- machine will go and the loop takes one logic step (Game:update(1/60)) per
-- turn of it. That is right for a screenshot script and wrong for a capture:
-- the game runs at whatever multiple of real time the hardware manages, so
-- "wait 180 frames" is three seconds only by coincidence.
--
-- The fix does not need an engine change. The loop is blocked while this
-- coroutine is running, so sleeping HERE before each yield paces the whole
-- thing -- one 1/60 logic step per 1/60 of real time, which is 1x by
-- construction. Nothing else in the engine has to know.
--
-- ------- and why it never finishes
--
-- When a driver coroutine goes dead, main.lua calls love.event.quit(). So
-- holding the battle open forever is exactly how the window stays up until
-- somebody closes it, which is the handshake this run wants: one window, one
-- Pokemon, closed by hand, and only then the next.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local SPECIES = os.getenv("DS_SPECIES") or "GYARADOS"
  local LEVEL   = tonumber(os.getenv("DS_LEVEL") or "") or 45
  local MAP     = os.getenv("DS_MAP") or "ROUTE_1"
  local CX      = tonumber(os.getenv("DS_CX") or "") or 5
  local CY      = tonumber(os.getenv("DS_CY") or "") or 8
  local LEAD    = tonumber(os.getenv("DS_LEAD") or "") or 2.0   -- seconds

  -- ------- real-time pacing
  --
  -- Each call is one logic step AND one sixtieth of a second of wall clock.
  -- The target is carried forward rather than measured from "now" so a slow
  -- frame is absorbed by the next one instead of compounding into drift.
  local nextAt = nil
  local function step()
    local now = love.timer.getTime()
    nextAt = (nextAt and (nextAt + 1 / 60)) or (now + 1 / 60)
    local slack = nextAt - now
    if slack > 0 then
      love.timer.sleep(slack)
    else
      nextAt = now                 -- fell behind; do not try to catch up
    end
    coroutine.yield()
  end

  local function hold(seconds)
    for _ = 1, math.floor(seconds * 60) do step() end
  end

  -- Unpaced, on purpose: a model rebuild is a loading screen, not part of
  -- the capture, and there is no reason to watch it at 1x.
  local function fast(n)
    for _ = 1, n do coroutine.yield() end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded")
    return
  end
  local Shiny = lib.require("Shiny")
  local OverworldBattle = lib.require("OverworldBattle")
  local StadiumInstall = lib.require("StadiumInstall")

  if not StadiumInstall.ready() then
    U.log("building stadium models (not part of the capture)...")
    StadiumInstall.begin()
    local guard = 0
    while not StadiumInstall.ready() and guard < 2000 do
      for _ = 1, 6 do StadiumInstall.step() end
      fast(1)
      guard = guard + 1
    end
  end

  -- STADIUM A stages the fight on the MAP, which wants clear ground. A cave
  -- floor often has none, and the mode's answer there is STADIUM B: the two
  -- carried discs, which work anywhere. DS_RUNG picks between them per
  -- encounter rather than forcing one choice on every location.
  OverworldBattle.setting:setValue(os.getenv("DS_RUNG") or "stadium", game)

  -- THE PARTY IS BUILT FIRST, at ordinary odds, and the roll is only pinned
  -- afterwards. Pokemon.new is where shininess is decided, so setting the
  -- odds before this line made the player's own Pikachu shiny too -- and a
  -- shiny on the player's side tints that side's pic, which during the intro
  -- is the TRAINER, so the player sprite came out discoloured for the whole
  -- send-out. The foe is the one this run is about.
  game.save.player.name = "RED"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  Shiny.setOdds(1)                       -- from here on: the encounter

  if not game.data.pokemon[SPECIES] then
    U.log("no such species: " .. SPECIES)
    return
  end
  if not game.data.maps[MAP] then
    U.log("no such map: " .. MAP)
    return
  end

  U.teleport(game, MAP, CX, CY, "down")
  hold(1.6)                              -- let the neighbourhood mesh

  hold(LEAD)                             -- a beat before the fight opens

  local battle = BattleState.newWild(game, SPECIES, LEVEL)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  -- ------- start the shot wider
  --
  -- BattleCam.zoom is a multiple of the rig's own frame height, so ABOVE one
  -- is zoomed OUT -- "the fight in its own landscape", per the note on the
  -- constants. 1.15 is fifteen percent wider, which happens to be exactly
  -- one notch of the player's own wheel (ZOOM_STEP).
  --
  -- Set AFTER the battle is pushed, because OverworldBattle's begin path
  -- calls BattleCam.reset() and that puts zoom and zoomGoal back to 1. Both
  -- are set, not just the goal: leaving the goal alone would make the shot
  -- glide outward over the first fifth of a second, and this wants to OPEN
  -- wide rather than pull back once the recording has started.
  local DS_ZOOM = tonumber(os.getenv("DS_ZOOM") or "") or 1.15
  local okCam, BattleCam = pcall(lib.require, "BattleCam")
  if okCam and BattleCam then
    BattleCam.zoom, BattleCam.zoomGoal = DS_ZOOM, DS_ZOOM
  end

  local mon = battle.enemy and battle.enemy.mon
  U.log(("%s at %s -- shiny=%s zoom=%.2f  (1x; close the window when done)")
        :format(SPECIES, MAP, tostring(Shiny.isShiny(mon)), DS_ZOOM))

  -- The battle stays up, at 1x, until the window is closed by hand. No taps:
  -- the recording should be the Pokemon standing there, not a text box being
  -- clicked through.
  --
  -- DS_AUTOCLOSE is for checking the pacing without a person in the loop: set
  -- it to a number of seconds and the run should take about that long by the
  -- wall clock, which is the only way to prove 1x is actually 1x.
  -- DS_SHOTS: capture the ARRIVAL as a strip, for checking that the sparkle
  -- fires on its own rather than only when a test arms it by hand. This is
  -- the same code path the capture run uses, which is the point -- the last
  -- bug here hid precisely because it was verified through a driver that
  -- armed the effect itself.
  local shots = os.getenv("DS_SHOTS")
  if shots then
    for k = 1, 26 do
      U.shot(game, ("%s/arrive_%02d.png"):format(shots, k))
      hold(0.15)
    end
    local ShinyFx = lib.require("ShinyFx")
    local d = ShinyFx.debug or {}
    U.log(("fx: armed=%s cleared=%s calls=%s noArena=%s noLive=%s quads=%s")
          :format(tostring(d.armed), tostring(d.cleared), tostring(d.calls),
                  tostring(d.noArena), tostring(d.noLive), tostring(d.quads)))
    U.log("arrival strip written to " .. shots)
    return
  end

  local auto = tonumber(os.getenv("DS_AUTOCLOSE") or "") or 0
  if auto > 0 then
    local t0 = love.timer.getTime()
    hold(auto)
    U.log(("autoclose: asked for %.1fs, took %.2fs")
          :format(auto, love.timer.getTime() - t0))
    return
  end
  while true do step() end
end
