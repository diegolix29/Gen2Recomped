-- Event flags stored in the save table, keyed by pokered event constant
-- names (e.g. "EVENT_FOLLOWED_OAK_INTO_LAB").
--
-- flag.changed fires through the runtime bus only on an actual
-- transition -- a redundant set of an already-true flag is silent -- and
-- the null bus makes the module usable headless.

local Runtime = require("src.mods.Runtime")

local Flags = {}

function Flags.set(save, name)
  local changed = save.flags[name] ~= true
  save.flags[name] = true
  if changed and Runtime.wants("flag.changed") then
    Runtime.emit("flag.changed", { name = name, value = true })
  end
end

-- Cleared flags are stored as `false`, not erased: Gen2 object_events start
-- hidden because the new-game script sets their flag, and objectVisible has to
-- tell "a script cleared this" (show the officer) from "never touched".
function Flags.clear(save, name)
  local changed = save.flags[name] == true
  save.flags[name] = false
  if changed and Runtime.wants("flag.changed") then
    Runtime.emit("flag.changed", { name = name, value = false })
  end
end

-- "Does the player have the Pokedex yet?"
--
-- Not one flag, because the cartridges do not agree on which one they set.
-- Gold and Crystal's Elm's-aide script lowers to `setevent EVENT_GOT_POKEDEX`;
-- PRISM'S PROF ILK LOWERS TO `setflag ENGINE_POKEDEX` and its own event number
-- instead, and ENGINE_POKEDEX is what the ROM's own CheckReceivedDex reads on
-- every Gen 2 cartridge.  Gating the START menu on the event alone meant the
-- Prism player watched Ilk hand the dex over -- text, jingle and all -- and
-- never got a POKeDEX entry in the menu.
-- AND SINNOH SETS NEITHER OF THEM, which is the same story a third time.
-- Both names above are GAME BOY event constants; Platinum's own "dex obtained"
-- flag is not in this port's Gen 4 save at all, so on every Sinnoh save this
-- answered NO and could not answer anything else.  Measured: the Gen 4 START
-- menu had no POKeDEX row with five species already seen, and the trainer card
-- hid its POKeDEX row and drew the no-dex face for the whole game.
--
-- So Gen 4 falls back to the question `Gen4MainMenu` already answers this way
-- on its CONTINUE panel: a dex with anything in it is a dex you were given.
-- It is behind the flag test, not in front of it, and behind an `isGen4`
-- gate -- so Gen 1, Gen 2 and Gen 3 return exactly what they returned before,
-- byte for byte.  Widening it to every cartridge would open Kanto's Pokedex
-- early for anything that marks a species seen before Oak hands it over, and
-- that is a real risk for no gain.
--
-- IT IS ONE ENCOUNTER BEHIND THE TRUTH, which is the same place the continue
-- screen's own count stands, and is the right trade against a menu row that
-- never appears.
function Flags.hasPokedex(save)
  -- tolerant of a save with no flag table: this is asked while menus are
  -- being built, including from headless callers
  local flags = type(save) == "table" and save.flags or nil
  if type(flags) == "table"
      and (flags.EVENT_GOT_POKEDEX == true or flags.ENGINE_POKEDEX == true) then
    return true
  end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if okV and GameVersion and GameVersion.isGen4 and GameVersion.isGen4() then
    local dex = type(save) == "table" and save.pokedex or nil
    if type(dex) ~= "table" then return false end
    return next(dex.seen or {}) ~= nil or next(dex.owned or {}) ~= nil
  end
  return false
end

function Flags.get(save, name)
  return save.flags[name] == true
end

return Flags
