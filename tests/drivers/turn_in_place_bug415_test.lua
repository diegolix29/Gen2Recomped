-- Driver: a quick directional tap should turn the player in place, not
-- also take a step (#415).  Player:tryMove (src/world/Player.lua) only
-- steps once turnTimer has counted down; TURN_FRAMES/turnFrames set how
-- many fixed steps a facing change blocks movement for before a held
-- direction is allowed to commit to a step.  This is an input-timing feel
-- bug: no assertion here can tell a quick tap from a held one the way a
-- human thumb can, so this hands the pad over rather than scripting taps
-- at a fixed, unrealistic frame count.
--
--   POKEPORT_DRIVER=tests/drivers/turn_in_place_bug415_test.lua \
--     POKEPORT_IDENTITY=bug415 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

return function(game)
  local U = dofile("tests/drivers/util.lua")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- REDS_HOUSE_2F: the player's own bedroom, the default new-game spawn
  -- (src/core/SaveData.lua bedroom fallback).  Small enough that an
  -- accidental step is obvious -- a stray step toward the stairs at
  -- (7,1)/(7,2) or into the desk/bed furniture is immediately visible.
  U.teleport(game, "REDS_HOUSE_2F", 5, 6, "down")
  U.wait(10)
  local ow = game.stack:top()
  check("Red's bedroom is loaded", ow.map.id == "REDS_HOUSE_2F")
  check("player starts facing down", ow.player.facing == "down")

  U.log("Standing in the middle of the bedroom, facing down.")
  U.log("Tap Up once, quickly, then tap Right once, quickly.")
  U.log("Right: each tap only turns you to face that way -- your feet")
  U.log("stay on the same tile both times.  Wrong (#415): a quick tap")
  U.log("still slides you one tile in the new direction, same as holding.")
  U.log("Now hold Up for a beat: turning into a real step, then a walk,")
  U.log("should feel identical to before -- no extra pause was added there.")

  while true do
    coroutine.yield()
  end
end
