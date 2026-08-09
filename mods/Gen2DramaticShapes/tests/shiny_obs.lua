-- Driver: five shiny encounters, five outdoor places, paced for a capture.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_obs.lua \
--   "/c/Program Files/LOVE/lovec.exe" .
--
-- Run from the PROJECT ROOT. Nothing here is a screenshot test -- it is a
-- performance, timed for somebody recording the window.
--
-- Each beat: teleport, let the ground mesh, open a wild battle, let the
-- Pokemon ARRIVE (the wipe, the send-out, the shiny sparkle), then hold
-- three full seconds on it before closing the battle and moving on. The hold
-- is deliberately silent -- no button taps during it -- so the recording is
-- of the Pokemon standing there and not of a text box being clicked through.
--
-- Every encounter is shiny, because the odds are pinned to 1 for the run and
-- the roll still happens where it always does, inside Pokemon.new.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded -- nothing to show")
    return
  end
  local Shiny = lib.require("Shiny")
  local OverworldBattle = lib.require("OverworldBattle")
  local StadiumInstall = lib.require("StadiumInstall")

  -- ------- timing, in frames at 60fps
  local SETTLE   = 110   -- after a teleport, for the neighbourhood to mesh
  local ARRIVE   = 70    -- the wipe, then the Pokemon landing on its tile
  local HOLD     = 180   -- THE THREE SECONDS
  local BETWEEN  = 45    -- back on the map before the next one opens

  -- ------- the models
  if not StadiumInstall.ready() then
    U.log("building stadium models first...")
    StadiumInstall.begin()
    local guard = 0
    while not StadiumInstall.ready() and guard < 2000 do
      for _ = 1, 6 do StadiumInstall.step() end
      U.wait(1)
      guard = guard + 1
    end
  end
  U.log("stadium ready: " .. tostring(StadiumInstall.ready()))

  OverworldBattle.setting:setValue("stadium", game)

  -- party FIRST, at ordinary odds: Pokemon.new is where shininess is
  -- decided, so pinning the odds before this made the player's own Pikachu
  -- shiny -- and that tints the player's side, which during the intro is the
  -- trainer sprite. The foe is what these runs are about.
  game.save.player.name = "RED"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  Shiny.setOdds(1)                       -- from here on: every encounter

  -- Five outdoor places, deliberately unalike -- a coast, an open route, a
  -- water city, a rocky pass and a wooded shore -- so the recording is five
  -- different-looking fights and not the same meadow five times. Each mon is
  -- put somewhere its colour has something to sit against.
  local RUNS = {
    { "CHARIZARD",  50, "ROUTE_4",       10, 5 },
    { "ELECTRODE",  40, "VIRIDIAN_CITY", 20, 20 },
    { "VAPOREON",   42, "ROUTE_25",      12, 5 },
    { "DRATINI",    30, "ROUTE_3",       10, 5 },
  }

  -- a beat before the first one, so a recorder that started with the window
  -- is not already mid-encounter by the time it is rolling
  U.log("starting in 3...")
  U.wait(60)
  U.log("2...")
  U.wait(60)
  U.log("1...")
  U.wait(60)

  for i, r in ipairs(RUNS) do
    local species, level, map, cx, cy = r[1], r[2], r[3], r[4], r[5]
    if not game.data.pokemon[species] then
      U.log(("skip %s -- not in this dataset"):format(species))
    elseif not game.data.maps[map] then
      U.log(("skip %s -- no map %s"):format(species, map))
    else
      U.teleport(game, map, cx, cy, "down")
      U.wait(SETTLE)

      local battle = BattleState.newWild(game, species, level)
      battle.onFinish = function() end
      game.overworld:pushBattle(battle)

      local mon = battle.enemy and battle.enemy.mon
      U.log(("%d/4  %-10s  %-14s  shiny=%s")
            :format(i, species, map, tostring(Shiny.isShiny(mon))))

      -- the arrival, then three seconds of nothing but the Pokemon
      U.wait(ARRIVE)
      U.wait(HOLD)

      -- close the battle and go back to the map
      while game.stack:top() and game.stack:top() ~= game.overworld do
        game.stack:pop()
      end
      U.wait(BETWEEN)
    end
  end

  Shiny.setOdds(8192)
  U.log("done -- five encounters")
end
