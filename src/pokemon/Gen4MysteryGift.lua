-- PLATINUM'S MYSTERY GIFTS, the deliveryman's half (src/scrcmd_mystery_gift.c,
-- res/field/scripts/scripts_mystery_gift_deliveryman.s).
--
-- On a cartridge a gift arrives over Wi-Fi or a distribution and waits in the
-- save as a PGT. Every Poke Mart's OnTransition (common script 10200) then
-- shows the deliveryman -- clearing FLAG_HIDE_MART_MYSTERY_GIFT_DELIVERYMAN
-- -- only while one is waiting, and he hands it over: the greeting for the
-- time of day, CheckCanReceiveMysteryGift, the gift's own line from bank 379
-- (TEXT_BANK_MYSTERY_GIFT_DELIVERYMAN), GiveMysteryGift, which frees the slot.
-- With none waiting he is hidden, which is what the port got wrong: the
-- command was undecodable, the OnTransition never ran, and he stood in every
-- mart.
--
-- WHERE A GIFT COMES FROM IS THIS PORT'S ADDITION, as Hoenn's is
-- (src/ui/Gen3MysteryGift.lua). The distributions that unlocked Platinum's
-- event areas have not run in fifteen years; this port offers ONE per Hall of
-- Fame induction, the player picks it, and it goes into the waiting slot --
-- after which everything is the cartridge's: the deliveryman appears in the
-- next mart, says his lines, gives the item, and sets the event's magic
-- number that Canalave's harbor, Route 224 and Spear Pillar check
-- (SystemVars_SetDistributionEventMagic). A gift taken is gone from the list.
--
-- The gifts are the cartridge's own handlers (giftHandlers):
--
--   MEMBER_CARD   item 454, VAR_DISTRIBUTION_EVENT_DARKRAI (0x4043) = 0x1209
--   OAKS_LETTER   item 452, VAR_DISTRIBUTION_EVENT_SHAYMIN (0x4044) = 0x1112,
--                 and VAR_SHAYMIN_EVENT_STATE (0x4057) 0 -> 1
--   AZURE_FLUTE   item 455, VAR_DISTRIBUTION_EVENT_ARCEUS (0x4045) = 0x1123
--   MANAPHY_EGG   GenerateManaphyEgg: a Manaphy Egg, if the party has room

local MysteryGift = {}

MysteryGift.BANK = 379
-- enum MysteryGiftType (include/mystery_gift.h)
MysteryGift.TYPE = { NONE = 0, POKEMON = 1, EGG = 2, ITEM = 3, MANAPHY_EGG = 7,
  MEMBER_CARD = 8, OAKS_LETTER = 9, AZURE_FLUTE = 10 }
-- MysteryGiftDeliveryman_Text_*
MysteryGift.TEXT = { CANNOT_PARTY_FULL = 4, CANNOT_TOO_MANY = 5, MANAPHY_EGG = 13,
  MEMBER_CARD = 14, OAKS_LETTER = 15, AZURE_FLUTE = 16 }
MysteryGift.DISTRIBUTION_VAR = 0x4043          -- + DISTRIBUTION_EVENT_*
MysteryGift.MAGIC = { [0] = 0x1209, 0x1112, 0x1123, 0x1103 }
MysteryGift.SHAYMIN_STATE_VAR = 0x4057
MysteryGift.MANAPHY = 490

MysteryGift.GIFTS = {
  { key = "member_card", type = 8, item = 454, event = 0, text = 14,
    about = "NEWMOON ISLAND -- DARKRAI" },
  { key = "oaks_letter", type = 9, item = 452, event = 1, text = 15,
    about = "FLOWER PARADISE -- SHAYMIN" },
  { key = "azure_flute", type = 10, item = 455, event = 2, text = 16,
    about = "HALL OF ORIGIN -- ARCEUS" },
  { key = "manaphy_egg", type = 7, text = 13, label = "MANAPHY Egg",
    about = "A MANAPHY EGG -- hatches a MANAPHY" },
}

-- HEARTGOLD / SOULSILVER: their event content opens on a FATEFUL-ENCOUNTER
-- Pokemon or an item (pokeheartgold's own checks), so these are what the
-- deliveryman (scr_seq_0144, text bank 209) brings:
--   FollowerPokeIsEventTrigger EVENT_SPIKY_EARED_PICHU -- a shiny fateful
--     Pichu walking behind you at Ilex Forest's shrine
--   EVENT_CELEBI -- a fateful Celebi there: the time-travel story
--   PlayerHasSpecies SPECIES_ARCEUS (Ruins of Alph) -- Sinjoh Ruins
--   GetPartySlotWithFatefulEncounter 492 (Goldenrod) -- the Gracidea
--   HasItem ITEM_ENIGMA_STONE (Pewter) -- Latias / Latios
-- The Pichu is this port's gift FROM THE START (start = true): it is waiting
-- at the first Poke Mart and does not count against the Hall of Fame picks.
MysteryGift.HGSS = {
  BANK = 209,
  TEXT = { CANNOT_PARTY_FULL = 4, CANNOT_TOO_MANY = 5, POKEMON = 7, ITEM = 9, MANAPHY_EGG = 13 },
  GIFTS = {
    { key = "pichu", type = 1, species = 172, level = 30, shiny = true, fateful = true, text = 7,
      start = true, label = "Shiny PICHU", about = "ILEX FOREST -- the Spiky-eared PICHU" },
    { key = "celebi", type = 1, species = 251, level = 30, fateful = true, text = 7,
      label = "CELEBI", about = "ILEX FOREST -- CELEBI's journey through time" },
    { key = "arceus", type = 1, species = 493, level = 100, fateful = true, text = 7,
      label = "ARCEUS", about = "SINJOH RUINS -- DIALGA, PALKIA or GIRATINA" },
    { key = "shaymin", type = 1, species = 492, level = 30, fateful = true, text = 7,
      label = "SHAYMIN", about = "GOLDENROD -- the GRACIDEA" },
    { key = "enigma_stone", type = 3, item = 536, text = 9,
      about = "PEWTER CITY -- LATIAS or LATIOS" },
    { key = "manaphy_egg", type = 7, text = 13, label = "MANAPHY Egg",
      about = "A MANAPHY EGG -- hatches a MANAPHY" },
  },
}

-- the running game's list, bank and texts
function MysteryGift.hgss()
  local v = require("src.core.GameVersion").get()
  return v == "heartgold" or v == "soulsilver"
end
function MysteryGift.gifts() return MysteryGift.hgss() and MysteryGift.HGSS.GIFTS or MysteryGift.GIFTS end
function MysteryGift.bank() return MysteryGift.hgss() and MysteryGift.HGSS.BANK or MysteryGift.BANK end
function MysteryGift.text() return MysteryGift.hgss() and MysteryGift.HGSS.TEXT or MysteryGift.TEXT end

local function byKey(key)
  for _, g in ipairs(MysteryGift.gifts()) do if g.key == key then return g end end
end
MysteryGift.byKey = byKey

local function state(save)
  save.gen4MysteryGift = save.gen4MysteryGift or { waiting = {}, taken = {} }
  local s = save.gen4MysteryGift
  s.waiting, s.taken = s.waiting or {}, s.taken or {}
  -- the gifts handed out from the start, queued once per save (an existing
  -- save gets them the first time this runs)
  if not s.startSeeded then
    s.startSeeded = true
    for _, g in ipairs(MysteryGift.gifts()) do
      if g.start and not s.taken[g.key] then
        s.taken[g.key] = "start"
        table.insert(s.waiting, 1, g.key)
      end
    end
  end
  return s
end
MysteryGift.state = state

-- the first waiting gift (MysteryGift_TryGetFirstValidPgtSlot), or nil
function MysteryGift.current(save)
  local s = save and state(save)
  return s and s.waiting[1] and byKey(s.waiting[1]) or nil
end

function MysteryGift.currentType(save)
  local g = MysteryGift.current(save)
  return g and g.type or MysteryGift.TYPE.NONE
end

local function partyCount(save)
  local n = 0
  for _ in ipairs((save and save.party) or {}) do n = n + 1 end
  return n
end

-- the handler's checkCanReceive: an item if the bag takes one more, a
-- Pokemon if the party has a slot
function MysteryGift.canReceive(game, save, g)
  g = g or MysteryGift.current(save)
  if not g then return false end
  if g.item then
    local ok, Bag = pcall(require, "src.inventory.Bag")
    if ok and Bag and Bag.canAdd then
      local okC, can = pcall(Bag.canAdd, save, g.item, 1, game and game.data)
      if okC then return can and true or false end
    end
    return (tonumber((save.inventory or {})[g.item]) or 0) < 999
  end
  return partyCount(save) < 6
end

-- the handler's give, then FreeCurrentPgt
function MysteryGift.give(game, save, setVar)
  local s = state(save)
  local g = MysteryGift.current(save)
  if not g then return false end
  if g.item then
    local ok, Bag = pcall(require, "src.inventory.Bag")
    if ok and Bag and Bag.add then pcall(Bag.add, save, g.item, 1, game and game.data) end
    save.inventory = save.inventory or {}
    if (tonumber(save.inventory[g.item]) or 0) < 1 then save.inventory[g.item] = 1 end
    if g.event and setVar then
      setVar(save, MysteryGift.DISTRIBUTION_VAR + g.event, MysteryGift.MAGIC[g.event])
      if g.key == "oaks_letter" then
        local vars = save.gen4Vars or {}
        if (tonumber(vars[MysteryGift.SHAYMIN_STATE_VAR]) or 0) == 0 then setVar(save, MysteryGift.SHAYMIN_STATE_VAR, 1) end
      end
    end
  elseif g.species then
    -- a distributed Pokemon: the met data MonMetadataMatchesEvent accepts is
    -- the fateful-encounter mark, and the Pichu's event wants it shiny
    local Pokemon = require("src.pokemon.Pokemon")
    local okN, mon = pcall(Pokemon.new, game.data, g.species, g.level or 5)
    if okN and mon then
      mon.fatefulEncounter = true
      mon.fateful = true
      if g.shiny then
        mon.shiny = true
        pcall(function() if Pokemon.makeShiny then Pokemon.makeShiny(mon, save) end end)
      end
      save.party = save.party or {}
      if #save.party < 6 then table.insert(save.party, mon) end
    end
  elseif g.key == "manaphy_egg" then
    local Pokemon = require("src.pokemon.Pokemon")
    local okN, mon = pcall(Pokemon.new, game.data, MysteryGift.MANAPHY, 1)
    if okN and mon then
      -- an egg the way Commands.give_pokemon makes one: flagged, counting steps
      mon.isEgg = true
      local okS, steps = pcall(require("src.pokemon.DayCare").eggSteps, game.data, MysteryGift.MANAPHY)
      mon.eggSteps = okS and steps or 2560
      save.party = save.party or {}
      if #save.party < 6 then table.insert(save.party, mon) end
    end
  end
  table.remove(s.waiting, 1)
  return true
end

-- ------------------------------------------------------------ the offer --
-- Inductions minus gifts already taken; never negative.
function MysteryGift.owed(save)
  if not save then return 0 end
  local s = state(save)
  local taken = 0
  for _, how in pairs(s.taken) do if how ~= "start" then taken = taken + 1 end end
  local wins = type(save.hallOfFame) == "table" and #save.hallOfFame or math.floor(tonumber(save.hallOfFame) or 0)
  return math.max(0, wins - taken)
end

-- the gifts not yet taken
function MysteryGift.available(save)
  local s = state(save)
  local out = {}
  for _, g in ipairs(MysteryGift.gifts()) do if not s.taken[g.key] then out[#out + 1] = g end end
  return out
end

-- picking puts the gift in the waiting slot the deliveryman reads
function MysteryGift.choose(save, key)
  local s = state(save)
  local g = byKey(key)
  if not g or s.taken[key] then return false end
  s.taken[key] = true
  s.waiting[#s.waiting + 1] = key
  return true
end

function MysteryGift.label(game, g)
  if g.label then return g.label end
  local def = game and game.data and game.data.items and game.data.items[g.item]
  return def and def.name or g.key
end

-- Offer as many as are owed, one pick at a time; `carryOn` is called exactly
-- once on every way out.
function MysteryGift.offer(game, carryOn)
  carryOn = carryOn or function() end
  local done = false
  local function finish()
    if done then return end
    done = true
    carryOn()
  end
  local save = game and game.save
  if not (save and game.stack) then return finish() end
  local okT, TextBox = pcall(require, "src.render.TextBox")
  local okM, Menu = pcall(require, "src.ui.Menu")
  if not (okT and okM) then return finish() end
  local function pick()
    local rows = MysteryGift.available(save)
    if MysteryGift.owed(save) < 1 or #rows == 0 then return finish() end
    local items = {}
    for _, g in ipairs(rows) do
      items[#items + 1] = { label = MysteryGift.label(game, g), describe = g.about, keepOpen = true,
        onSelect = function()
          game.stack:push(TextBox.new(game, ("Receive the %s?"):format(MysteryGift.label(game, g)), nil, {
            choice = function(yes)
              if not yes then return end
              MysteryGift.choose(save, g.key)
              game.stack:push(TextBox.new(game,
                "The gift is on its way!\nThe deliveryman at any POKé MART\nwill hand it over.", function()
                  if MysteryGift.owed(save) >= 1 and #MysteryGift.available(save) > 0 then return end
                  game.stack:pop()       -- the menu
                  finish()
                end))
            end,
          }))
        end }
    end
    game.stack:push(Menu.new(game, items, { noSound = true, onCancel = finish }))
  end
  if MysteryGift.owed(save) < 1 or #MysteryGift.available(save) == 0 then return finish() end
  game.stack:push(TextBox.new(game, "A MYSTERY GIFT is available!\nChoose one to receive.", pick))
end

return MysteryGift
