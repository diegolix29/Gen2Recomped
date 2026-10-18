-- Driver: NPC in-game trade cable animation (InternalClockTradeAnim).
-- Vermilion Trade House: SPEAROW -> FARFETCH'D (DUX).
--
--   SHOT_DIR=/tmp/trade_shots POKEPORT_DRIVER=tests/drivers/trade_anim_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/trade_shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TradeAnim = require("src.ui.TradeAnim")
  local PartyMenu = require("src.ui.PartyMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")

  local function topIs(cls)
    return getmetatable(game.stack:top()) == cls
  end

  game.save.party = { Pokemon.new(game.data, "SPEAROW", 10) }
  U.teleport(game, "VERMILION_TRADE_HOUSE", 3, 6, "up")
  U.wait(5)
  U.shot(game, DIR .. "/trade_00_house.png")

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 200 do
    if topIs(ChoiceBox) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  U.shot(game, DIR .. "/trade_01_offer.png")
  U.tap(game, "a") -- YES
  U.wait(6)

  for _ = 1, 60 do
    if topIs(PartyMenu) then break end
    U.wait(1)
  end
  U.log("party menu:", topIs(PartyMenu))
  U.shot(game, DIR .. "/trade_02_party.png")
  U.tap(game, "a")
  U.wait(6)

  for _ = 1, 200 do
    if topIs(TradeAnim) then break end
    U.tap(game, "a")
    U.wait(2)
  end
  local anim = game.stack:top()
  if getmetatable(anim) ~= TradeAnim then
    U.log("FAIL: TradeAnim never appeared")
    return
  end
  U.log("TradeAnim phase:", anim.phase)

  -- the movie is a fixed program (src/ui/TradeAnim.lua runs
  -- InternalClockTradeFuncSequence one frame per update): let it play and
  -- take a shot a little way into every function of the sequence
  local shots, lastPhase, since = 3, nil, 0
  for _ = 1, 4000 do
    if game.stack:top() ~= anim and anim.finished then break end
    if anim.phase ~= lastPhase then lastPhase, since = anim.phase, 0 end
    since = since + 1
    if since == 30 then
      U.shot(game, ("%s/trade_%02d_%s.png"):format(DIR, shots, tostring(lastPhase)))
      shots = shots + 1
    end
    U.wait(1)
  end
  U.log("TradeAnim finished:", anim.finished)

  for _ = 1, 5000 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(1)
  end
  U.shot(game, DIR .. "/trade_10_done.png")
  local mon = game.save.party[1]
  U.log("party:", mon and mon.species, "nick:", mon and mon.nickname,
        "ot:", mon and mon.ot)
  U.log("done")
end
