-- Driver: photograph the shiny system, each case beside its own control.
--
--   SHOT_DIR=mods/DramaticShapeVoxelMod/.claude/shiny_update \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_shots.lua \
--   "/c/Program Files/LOVE/lovec.exe" .
--
-- SHOT_DIR must already exist -- the capture writes with io.open.
--
-- EVERY CASE IS SHOT TWICE, the same species on the same tile, once
-- ordinary and once shiny. A single shiny screenshot proves nothing: these
-- are N64 models under a day/night tint on generated ground, and "that
-- looks a bit purple" is not evidence. The pair is.
--
-- The four species are chosen to exercise the four things that can break:
--
--   GYARADOS   one of the five Stadium gives a REAL alternate texture, so
--              it runs the explicit colour table rather than the HSL slide.
--              Blue to red, the least deniable shiny in Gen 1.
--   CHARIZARD  the biggest slide in the set (H -136, S -6). Also the one
--              whose canonical shiny is famously black, which the Stadium
--              values do NOT reproduce -- they give a dusky slate-violet.
--              Shot precisely so that difference is on the record.
--   GOLBAT     L -6, the darkest lightness step there is. If the guard
--              rails are wrong this is where it goes to mud.
--   PONYTA     made of fire. Its flames are GENERATED frames, excluded
--              from the recolour, so the correct result is a recoloured
--              body with an ordinary mane. That exclusion is invisible in
--              every other species.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR")
             or "mods/DramaticShapeVoxelMod/.claude/shiny_update"
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded -- nothing to shoot")
    return
  end
  local Shiny = lib.require("Shiny")
  local ShinyFx = lib.require("ShinyFx")
  local OverworldBattle = lib.require("OverworldBattle")
  local StadiumInstall = lib.require("StadiumInstall")
  local StadiumPack = lib.require("StadiumPack")

  -- ------- the models
  --
  -- REV went to 3 with the shiny variants, so an existing cache is stale and
  -- the game rebuilds all 151 on the loading screen. That is a minute or so
  -- of frames, and it has to be waited out rather than assumed: shooting
  -- before it lands gets flat 2D pics and a very confusing set of images.
  -- Driven from HERE rather than waited on. The build is normally pumped by
  -- the loading screen StadiumScreen.maybePush puts up on the first world
  -- frame, but a driver owns the frame loop and that screen never came up --
  -- a first run sat at "idle 0/151" for twelve thousand frames and shot four
  -- unrecoloured Pokemon. Calling begin/step directly is both faster and
  -- honest about what is being tested, which is the extraction, not the
  -- screen that usually triggers it.
  -- the upgrade question, asked before anything is built: with a stale
  -- marker on disk, does this machine know it has work to do?
  U.log(("upgrade check: ready=%s usable=%s available=%s pending=%s rom=%s")
        :format(tostring(StadiumInstall.ready()),
                tostring(StadiumInstall.usable()),
                tostring(StadiumInstall.available()),
                tostring(StadiumInstall.pending()),
                tostring(StadiumInstall.romPresent())))

  if not StadiumInstall.ready() then
    local ok, err = StadiumInstall.begin()
    U.log(("stadium build: begin=%s %s"):format(tostring(ok), tostring(err or "")))
    local guard = 0
    while not StadiumInstall.ready() and guard < 2000 do
      -- several species per frame: 151 of them at one a frame is a long
      -- wait for no reason, and nothing here needs to be drawn
      for _ = 1, 6 do StadiumInstall.step() end
      U.wait(1)
      guard = guard + 1
      local st = StadiumInstall.status
      if st and st.state == "failed" then
        U.log("stadium build FAILED: " .. tostring(st.error))
        break
      end
      if guard % 10 == 0 then
        U.log(("  building: %s %d/%d"):format(tostring(st and st.state),
              (st and st.done) or 0, (st and st.total) or 0))
      end
    end
  end
  U.log("stadium ready: " .. tostring(StadiumInstall.ready()))

  -- and prove the shiny packs are actually THERE before shooting anything
  for _, dex in ipairs({ 130, 6, 42, 77 }) do
    U.log(("  pack %03d: normal=%s shiny=%s"):format(
      dex, tostring(StadiumPack.available(dex, false)),
      tostring(StadiumPack.available(dex, true))))
  end

  -- STADIUM A: models, staged on the map
  OverworldBattle.setting:setValue("stadium", game)
  U.log("3D-BTL = " .. tostring(OverworldBattle.setting:get()))

  game.save.player.name = "RED"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  local CASES = {
    { "GYARADOS",  40, "ROUTE_1",     5, 8 },
    { "CHARIZARD", 50, "ROUTE_1",     5, 8 },
    { "GOLBAT",    40, "ROUTE_1",     5, 8 },
    { "PONYTA",    40, "ROUTE_1",     5, 8 },
  }

  -- Odds are the real lever, so the shiny half goes through the SAME path a
  -- player's encounter does -- decided inside Pokemon.new by a roll -- rather
  -- than being stamped on afterwards. 1 means every mon; a huge denominator
  -- means none, which is what makes the control a control.
  local function setOdds(shiny)
    Shiny.setOdds(shiny and 1 or 100000000)
  end

  local function toMenu()
    for _ = 1, 16 do U.tap(game, "a") U.wait(8) end
  end

  local function leave()
    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(10)
  end

  for i, c in ipairs(CASES) do
    local species, level, map, cx, cy = c[1], c[2], c[3], c[4], c[5]
    if not game.data.pokemon[species] then
      U.log("no such species in this dataset: " .. species)
    else
      for _, variant in ipairs({ "normal", "shiny" }) do
        local shiny = (variant == "shiny")
        setOdds(shiny)

        U.teleport(game, map, cx, cy, "down")
        U.wait(90)           -- let the neighbourhood's meshes land

        local battle = BattleState.newWild(game, species, level)
        battle.onFinish = function() end
        game.overworld:pushBattle(battle)

        local mon = battle.enemy and battle.enemy.mon
        U.log(("%s %s: isShiny=%s dvs=%s/%s/%s/%s flag=%s"):format(
          species, variant, tostring(Shiny.isShiny(mon)),
          tostring(mon and mon.dvs and mon.dvs.attack),
          tostring(mon and mon.dvs and mon.dvs.defense),
          tostring(mon and mon.dvs and mon.dvs.speed),
          tostring(mon and mon.dvs and mon.dvs.special),
          tostring(mon and mon.shiny)))

        -- THE ARRIVAL. Shot during the send-out rather than after it,
        -- because the sparkle is three quarters of a second long and the
        -- menu is well past it. Three frames close together, so one of them
        -- lands mid-burst whatever the intro's pacing does on this map.
        U.wait(70)
        if shiny then
          for k = 1, 3 do
            U.shot(game, ("%s/%d_%s_arrival_%d.png")
                         :format(DIR, i, species:lower(), k))
            U.wait(10)
          end
        end

        toMenu()
        U.shot(game, ("%s/%d_%s_%s.png")
                     :format(DIR, i, species:lower(), variant))

        -- and the sparkle again, armed deliberately and shot on the next
        -- frame. The arrival shots above catch it in its real moment but
        -- depend on intro timing; this one is the effect itself, on the
        -- record, at a known point in its life.
        if shiny then
          for k, v in pairs(ShinyFx.debug) do ShinyFx.debug[k] = 0 end
          ShinyFx.arm("enemy")
          U.wait(4)
          U.shot(game, ("%s/%d_%s_sparkle.png"):format(DIR, i, species:lower()))
          local d = ShinyFx.debug
          U.log(("  fx: calls=%d noArena=%d noImage=%d noMesh=%d noLive=%d quads=%d")
                :format(d.calls, d.noArena, d.noImage, d.noMesh, d.noLive,
                        d.quads))
        end

        leave()
      end
    end
  end

  -- ------- the FLAT art
  --
  -- Everything above is the STADIUM rung, which draws recoloured 3D models
  -- and never touches a pic. The tint is the other half of the feature and
  -- needs its own rung to be visible at all: 2D-3D stands the game's own
  -- battle pics up as cards, which is the path ShinyUI tints.
  OverworldBattle.setting:setValue(true, game)
  U.log("3D-BTL = " .. tostring(OverworldBattle.setting:get()) .. " (cards)")
  for _, variant in ipairs({ "normal", "shiny" }) do
    setOdds(variant == "shiny")
    U.teleport(game, "ROUTE_1", 5, 8, "down")
    U.wait(90)
    local battle = BattleState.newWild(game, "GYARADOS", 40)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    U.log(("cards %s: isShiny=%s"):format(
      variant, tostring(Shiny.isShiny(battle.enemy and battle.enemy.mon))))
    U.wait(70)
    toMenu()
    U.shot(game, ("%s/6_cards_gyarados_%s.png"):format(DIR, variant))
    leave()
  end

  -- ------- the status page
  --
  -- A shiny and an ordinary mon of the SAME species, so the star is the only
  -- difference between the two images.
  local SummaryMenu = require("src.ui.SummaryMenu")
  for _, variant in ipairs({ "normal", "shiny" }) do
    setOdds(variant == "shiny")
    local mon = Pokemon.new(game.data, "GYARADOS", 40)
    U.log(("summary %s: isShiny=%s flag=%s"):format(
      variant, tostring(Shiny.isShiny(mon)), tostring(mon.shiny)))
    game.save.party = { mon }
    game.stack:push(SummaryMenu.new(game, mon))
    U.wait(20)
    U.shot(game, ("%s/5_status_%s.png"):format(DIR, variant))
    leave()
  end

  -- ------- the odds actually being odds
  --
  -- Not a screenshot, but it belongs in the same run: the rate is the thing
  -- a player experiences, and it is the one claim a picture cannot make.
  Shiny.setOdds(8192)
  local n, hits = 4000, 0
  for _ = 1, n do
    if Shiny.isShiny(Pokemon.new(game.data, "RATTATA", 5)) then
      hits = hits + 1
    end
  end
  U.log(("odds check: %d shinies in %d at 1/8192 (expect ~0-2)")
        :format(hits, n))

  Shiny.setOdds(8192)
  U.log("done -- " .. DIR)
end
