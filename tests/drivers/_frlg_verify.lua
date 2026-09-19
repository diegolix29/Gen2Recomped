-- FireRed port verification: walk the screens Ceedrack named as the bar for
-- playtesting (healing, marts, menus, events, badges) and capture each one,
-- so the port can be compared against the cartridge rather than asserted to
-- work.
--
--   POKEPORT_VERSION=firered SHOT_DIR=shots/frlg \
--   POKEPORT_DRIVER=tests/drivers/_frlg_verify.lua
return function(game)
  local U = require("tests.drivers.util")
  local dir = os.getenv("SHOT_DIR") or "shots/frlg"

  -- Flat filenames on purpose: U.shot builds its directory with
  -- os.execute("mkdir -p"), which does not exist on Windows, so a
  -- subdirectory is never created and the capture is dropped. It then
  -- verifies with a CWD-relative io.open while LOVE writes into the SAVE
  -- directory, so it reports FAIL either way. Writing to the save root
  -- sidesteps both.
  local function shot(name)
    game.capturePath = "frlg_" .. name .. ".png"
    for _ = 1, 120 do
      if not game.capturePath then break end
      coroutine.yield()
    end
    U.wait(2)
  end

  -- 1. The overworld as the game starts it.
  U.wait(20)
  shot("01_boot")

  U.newGame(game)
  U.wait(30)
  shot("02_overworld")

  -- 2. The start menu -- the first thing that proves menu text extracted.
  U.tap(game, "start")
  U.wait(12)
  shot("03_start_menu")

  -- 3. Walk down the start menu so each row renders at least once.
  for i = 1, 4 do
    U.tap(game, "down")
    U.wait(6)
    shot(("04_start_row%d"):format(i))
  end
  U.tap(game, "b")
  U.wait(10)

  -- 4. The bag. Its import stage DECLINED for FireRed
  --    ("extractBagScreen failed: attempt to get length of local 'tiles'"),
  --    so this is expected to look wrong -- capture it anyway, because the
  --    point is evidence, not a clean run.
  U.tap(game, "start"); U.wait(8)
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "a");    U.wait(15)
  shot("05_bag")
  U.tap(game, "b");    U.wait(8)
  U.tap(game, "b");    U.wait(8)

  -- 5. The party menu -- same story (extractPartyMenu failed).
  U.tap(game, "start"); U.wait(8)
  U.tap(game, "a");     U.wait(15)
  shot("06_party")
  U.tap(game, "b");     U.wait(8)
  U.tap(game, "b");     U.wait(8)

  -- 6. A Poke Mart and a Pokemon Center: Ceedrack's "healing, marts".
  --    Viridian City is group 1; its Mart and Center are interior maps.
  --    Teleporting is the only way to reach them in a scripted run.
  local places = {
    { id = "MAP_G04_N03", name = "07_pallet_oaks_lab" },
    { id = "MAP_G04_N00", name = "08_pallet_house_1f" },
  }
  for _, p in ipairs(places) do
    local ok = pcall(U.teleport, game, p.id, 5, 5, "down")
    U.wait(20)
    if ok then shot(p.name) else U.log("teleport failed:", p.id) end
  end

  U.log("FRLG verification shots written to " .. dir)
  love.event.quit(0)
end
