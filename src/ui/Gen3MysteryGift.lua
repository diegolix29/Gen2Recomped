-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE EVENT DISTRIBUTIONS, HANDED OUT FOR BEATING THE LEAGUE.
--
-- THIS IS AN ADDITION, NOT PARITY, and it should be read as one.  On a retail
-- cartridge the four island events arrive over the link cable from a Nintendo
-- event that has not run in twenty years: `special 504` is one line --
-- `VarGet($403F) != 0` -- and that var is set by a Mystery Gift the machine
-- never received, so the tickets are unobtainable and Latios, Lugia, Ho-Oh,
-- Deoxys and Mew are simply not in the game.  This port cannot receive that
-- broadcast either, so rather than leave four islands permanently dark it
-- hands one out per Hall of Fame induction and lets the player choose which.
--
-- WHAT AN EVENT IS, AND WHY IT IS NOT WRITTEN DOWN HERE.  Each one is a
-- ticket in the bag plus the flag that opens its dock row, and both come off
-- the SS Tidal's own destination table (constants.gen3SSTidal, derived by
-- RomExtractorGen3:extractSSTidal from gSpecials[500]).  Every row that
-- carries an `item` IS a distribution -- that is what separates the four
-- islands from Slateport, the Battle Frontier and the way out -- so the list
-- below is read, not typed, and a dataset without the table simply offers
-- nothing.
--
-- HOW MANY YOU GET.  `save.hallOfFame` is the induction count the ceremony
-- already keeps and prints; what is owed is that count minus what has been
-- taken.  So the first win offers one, the second offers another, and a win
-- whose offer was declined is not lost -- the difference is still there next
-- time.  Nothing new is stored: the entitlement is derived from two numbers
-- that were both already in the save.
local Gen3MysteryGift = {}

-- What is on each island.  The names and the flags are the cartridge's; these
-- one-liners are this port's, so the menu says what a choice is FOR rather
-- than making the player remember which ticket goes where.
local ABOUT = {
  EON_TICKET   = "SOUTHERN ISLAND -- LATIOS or LATIAS",
  MYSTICTICKET = "NAVEL ROCK -- LUGIA and HO-OH",
  AURORATICKET = "BIRTH ISLAND -- DEOXYS",
  OLD_SEA_MAP  = "FARAWAY ISLAND -- MEW",
}

local function commands()
  local ok, mod = pcall(require, "src.script.Gen3Commands")
  return ok and mod or nil
end

-- The four, in the cartridge's own order.  A destination row is an event
-- exactly when it costs a ticket.
function Gen3MysteryGift.events(game)
  local record = game and game.data and game.data.constants
                 and game.data.constants.gen3SSTidal
  local out = {}
  for _, row in ipairs((record and record.destinations) or {}) do
    local flag = row.item and row.flags and row.flags[1]
    if row.item and flag then
      out[#out + 1] = {
        item = row.item, name = row.name or row.item, flag = flag,
        about = ABOUT[row.item],
      }
    end
  end
  return out
end

function Gen3MysteryGift.isUnlocked(game, row)
  local G = commands()
  local save = game and game.save
  if not (G and save and row) then return false end
  return (save.flags or {})[G.flagKey(row.flag)] == true
end

function Gen3MysteryGift.lockedRows(game)
  local out = {}
  for _, row in ipairs(Gen3MysteryGift.events(game)) do
    if not Gen3MysteryGift.isUnlocked(game, row) then out[#out + 1] = row end
  end
  return out
end

-- Inductions minus events already taken.  Never negative: a save that
-- collected a ticket some other way must not go into debt for it.
function Gen3MysteryGift.owed(game)
  local save = game and game.save
  if not save then return 0 end
  local taken = 0
  for _, row in ipairs(Gen3MysteryGift.events(game)) do
    if Gen3MysteryGift.isUnlocked(game, row) then taken = taken + 1 end
  end
  local wins = math.floor(tonumber(save.hallOfFame) or 0)
  return math.max(0, wins - taken)
end

-- The ticket in the bag AND the flag that opens the dock row.  Both, because
-- tidalDestinations wants both and offers the island only when it has them.
function Gen3MysteryGift.unlock(game, row)
  local G = commands()
  local save = game and game.save
  if not (G and save and row and row.flag and row.item) then return false end
  save.flags = save.flags or {}
  save.flags[G.flagKey(row.flag)] = true
  save.inventory = save.inventory or {}
  local okBag, Bag = pcall(require, "src.inventory.Bag")
  if okBag and Bag and Bag.add then
    pcall(Bag.add, save, row.item, 1, game.data)
  end
  -- ...and if the bag refused -- it is five pockets and they do fill -- the
  -- ticket still has to exist, because the flag alone offers a dock row that
  -- tidalHasTicket will then turn down.
  if (tonumber(save.inventory[row.item]) or 0) < 1 then
    save.inventory[row.item] = 1
  end
  -- THE EON TICKET HAS A SECOND HALF.  gSpecials[504] does not read the bag;
  -- it reads $403F, the var the Mystery Gift itself would have set, and the
  -- Lilycove scene that hands the ticket over branches on it.
  if row.item == "EON_TICKET" and G.EON_TICKET_VAR then
    save.gen3Vars = save.gen3Vars or {}
    save.gen3Vars[G.EON_TICKET_VAR] = 1
  end
  local okLog, Logger = pcall(require, "src.core.Logger")
  if okLog then
    Logger.info("mystery gift: unlocked %s (flag %04X, %s in the bag)",
                tostring(row.name), row.flag, tostring(row.item))
  end
  return true
end

-- ---------------------------------------------------------------------------
-- the offer itself
-- ---------------------------------------------------------------------------

local function textBox(game, text, onDone, opts)
  local ok, TextBox = pcall(require, "src.render.TextBox")
  if not (ok and TextBox and game and game.stack) then
    if onDone then onDone() end
    return false
  end
  game.stack:push(TextBox.new(game, text, onDone, opts))
  return true
end

-- Offer as many as are owed, one pick at a time, then hand control back.
--
-- `carryOn` is what the caller was going to do next and it is called EXACTLY
-- ONCE on every way out -- taken, declined, nothing owed, no dataset.  The
-- Hall of Fame's own callback resumes a suspended script through it, so a
-- path that forgot it would park the game on the credits.
function Gen3MysteryGift.offer(game, carryOn)
  carryOn = carryOn or function() end
  local done = false
  local function finish()
    if done then return end
    done = true
    carryOn()
  end
  if not (game and game.stack) then return finish() end

  local function pick()
    local rows = Gen3MysteryGift.lockedRows(game)
    if Gen3MysteryGift.owed(game) < 1 or #rows == 0 then return finish() end
    local ok, Menu = pcall(require, "src.ui.Menu")
    if not (ok and Menu and Menu.new) then return finish() end
    local items = {}
    for _, row in ipairs(rows) do
      items[#items + 1] = {
        label = row.name,
        describe = row.about,
        -- the menu stays up under the confirm, so a NO goes straight back to
        -- the list rather than ending the offer
        keepOpen = true,
        onSelect = function()
          textBox(game, ("Unlock the %s event?"):format(row.name), nil, {
            choice = function(yes)
              if not yes then return end
              Gen3MysteryGift.unlock(game, row)
              textBox(game, ("Received the %s!\n%s is open."):format(
                        row.item:gsub("_", " "), row.name), function()
                -- more owed and more to take: leave the list up for another
                if Gen3MysteryGift.owed(game) >= 1
                   and #Gen3MysteryGift.lockedRows(game) > 0 then
                  return
                end
                game.stack:pop()          -- the menu
                finish()
              end)
            end,
          })
        end,
      }
    end
    game.stack:push(Menu.new(game, items, {
      noSound = true,
      onCancel = finish,               -- Menu pops itself first
    }))
  end

  textBox(game, "A MYSTERY GIFT event is available!\nChoose one to unlock.",
          pick)
end

return Gen3MysteryGift
