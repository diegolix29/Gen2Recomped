-- BLACK AND WHITE'S MYSTERY GIFTS, offered after the game is cleared.
--
-- THIS IS AN ADDITION, as Hoenn's, Johto's and Sinnoh's are (src/ui/
-- Gen3MysteryGift.lua, src/pokemon/Gen4MysteryGift.lua): the distributions
-- that opened Unova's event content have not run in over a decade. What each
-- gift opens is the cartridge's own check:
--
--   Liberty Pass   checkitem 574 at Castelia's harbor (members 72 / 474):
--                  the boat to Liberty Garden and VICTINI
--   Celebi         0x220 <251> in Castelia (member 94): a fateful Celebi in
--                  the party starts the ZORUA scene
--   Entei / Raikou / Suicune   0x220 <244 / 243 / 245> in Lostlorn Forest
--                  (member 770): any of them, fateful, opens ZOROARK
--
-- One gift per game clear (the ending after N's Castle, then each win over
-- the Champion -- 0x156 kinds 0 and 1); a gift taken is gone from the list.
-- Unova's deliveryman is not decoded, so a gift is handed over at once: an
-- item into the bag, a Pokemon into the party (or the PC when it is full),
-- carrying the fateful-encounter mark 0x220 reads.

local MysteryGift = {}

MysteryGift.GIFTS = {
  { key = "liberty_pass", itemName = "Liberty Pass", about = "LIBERTY GARDEN -- VICTINI" },
  { key = "celebi", species = 251, level = 50, label = "CELEBI", about = "CASTELIA CITY -- ZORUA" },
  { key = "entei", species = 244, level = 40, shiny = true, label = "Shiny ENTEI",
    about = "LOSTLORN FOREST -- ZOROARK" },
  { key = "raikou", species = 243, level = 40, shiny = true, label = "Shiny RAIKOU",
    about = "LOSTLORN FOREST -- ZOROARK" },
  { key = "suicune", species = 245, level = 40, shiny = true, label = "Shiny SUICUNE",
    about = "LOSTLORN FOREST -- ZOROARK" },
}

local function state(save)
  save.gen5MysteryGift = save.gen5MysteryGift or { taken = {}, clears = 0 }
  local s = save.gen5MysteryGift
  s.taken, s.clears = s.taken or {}, tonumber(s.clears) or 0
  return s
end
MysteryGift.state = state

-- a game clear earns one pick (0x156)
function MysteryGift.recordClear(save)
  local s = state(save)
  s.clears = s.clears + 1
end

function MysteryGift.owed(save)
  local s = state(save)
  local taken = 0
  -- "walker": bought on the Monster Walker, not one of the per-clear picks
  for _, how in pairs(s.taken) do if how ~= "walker" then taken = taken + 1 end end
  return math.max(0, s.clears - taken)
end

function MysteryGift.available(save)
  local s, out = state(save), {}
  for _, g in ipairs(MysteryGift.GIFTS) do if not s.taken[g.key] then out[#out + 1] = g end end
  return out
end

local function itemId(game, name)
  for id, def in pairs((game and game.data and game.data.items) or {}) do
    if type(id) == "number" and type(def) == "table" and def.name == name then return id end
  end
end

function MysteryGift.label(game, g)
  if g.label then return g.label end
  return g.itemName or g.key
end

-- hand it over; returns the line to show
function MysteryGift.give(game, g)
  local save = game.save
  local player = (save.player and save.player.name) or "You"
  state(save).taken[g.key] = true
  if g.itemName then
    local id = itemId(game, g.itemName)
    if id then
      local ok, Bag = pcall(require, "src.inventory.Bag")
      if ok and Bag and Bag.add then pcall(Bag.add, save, id, 1, game.data) end
      save.inventory = save.inventory or {}
      if (tonumber(save.inventory[id]) or 0) < 1 then save.inventory[id] = 1 end
    end
    return ("%s received the %s!"):format(player, g.itemName)
  end
  local Pokemon = require("src.pokemon.Pokemon")
  local okN, mon = pcall(Pokemon.new, game.data, g.species, g.level or 5)
  if not (okN and mon) then return ("The gift could not be delivered.") end
  mon.fatefulEncounter, mon.fateful = true, true
  if g.shiny then mon.shiny = true end
  save.party = save.party or {}
  local name = MysteryGift.label(game, g)
  if #save.party < 6 then
    table.insert(save.party, mon)
    return ("%s received %s!"):format(player, name)
  end
  local okB, Boxes = pcall(require, "src.pokemon.Boxes")
  if okB and Boxes and Boxes.deposit then pcall(Boxes.deposit, save, mon) end
  return ("%s received %s!\nIt was sent to the PC."):format(player, name)
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
              local line = MysteryGift.give(game, g)
              game.stack:push(TextBox.new(game, line, function()
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
