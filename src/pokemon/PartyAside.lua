-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PLAYER'S PARTY, SET ASIDE FOR ONE BATTLE -- KEPT IN THE SAVE.
--
-- Several battles fight with a team that is not the player's: Platinum and
-- HeartGold / SoulSilver's Battle Tower, Hall, Castle, Arcade and Factory hand
-- the battle COPIES (or rentals), and FireRed / LeafGreen's POKe DUDE demo a
-- borrowed Pokemon. Each put the borrowed team in `save.party` for the battle
-- and held the real one in a Lua local until the battle ended.
--
-- A save written mid-battle (F1 saves anywhere) then stored the borrowed team
-- AS the party and the real one nowhere -- the same loss the Battle Dome had
-- (reported from play: "the other Pokemon were nowhere to be found"). So the
-- real party is also written into the save while it is set aside, and a save
-- loaded with one still set aside gets it back: a reload always means the
-- battle that borrowed the team is over.
--
-- (Emerald's Frontier stash -- SavePlayerParty / LoadPlayerParty, special
-- 40 / 41 -- is a different, challenge-long thing the cartridge itself keeps in
-- the save; it is not this.)

local PartyAside = {}

-- the real party goes aside (in the save) while `temp` stands in for it
function PartyAside.hold(save, real)
  if type(save) ~= "table" then return end
  save.partyAside = { party = real }
end

-- the battle is over and the caller has put the real party back
function PartyAside.release(save)
  if type(save) == "table" then save.partyAside = nil end
end

-- Game:restoreSave: a party still set aside is the real one
function PartyAside.onLoad(save)
  local aside = type(save) == "table" and save.partyAside
  if not (type(aside) == "table" and type(aside.party) == "table") then
    if type(save) == "table" then save.partyAside = nil end
    return false
  end
  save.party = aside.party
  save.partyAside = nil
  require("src.core.Logger").info("party: a save written mid-battle had the player's own party set aside -- restored")
  return true
end

return PartyAside
