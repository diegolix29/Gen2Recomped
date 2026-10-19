-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- SINNOH'S PARTY ICONS, AND THE KANTO TABLE THAT WAS STANDING IN FOR THEM.
--
-- Reported from play: "missing pokemon party sprites from the pokemon start
-- menu".
--
-- They were extracted, they were on disk, and `Data` had a lift written to
-- publish them. The lift never ran. `icons` used to sit in CLASSIC_ONLY, which
-- blocks a module from resolving through the additive overlay; it left that
-- list when Emerald gained an icons.lua of its own, and nothing put it back
-- for Gen 4. Platinum writes no icons.lua, so `require("data.generated.icons")`
-- walked through to the ROOT cache -- Red's -- `self.icons` came back non-nil,
-- and the lift's `== nil` guard politely declined.
--
-- WHAT THAT LOOKS LIKE IN THE PARTY LIST: below species 152 a Kanto icon
-- chosen by dex number, and above it nothing at all, because
-- `Gen4PartyMenu:iconFor` finds no entry and `drawIcon` falls back to a Poke
-- Ball. A Sinnoh team is all Poke Balls.
--
-- Usage: texlua tools/gen4_party_icon_check.lua <platinum/data/generated>
--                                               [root data/generated]

package.path = "./?.lua;" .. package.path

local DIR = arg[1]
local ROOT = arg[2]
if not DIR then
  io.write("Pass the generated Platinum data root as the first argument.\n")
  os.exit(2)
end

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end

local function load(name)
  local chunk = loadfile(DIR .. "/" .. name .. ".lua")
  if not chunk then return nil end
  local okc, mod = pcall(chunk)
  return okc and mod or nil
end

-- ---------------------------------------------------------------------------
section("1. the cartridge really does carry its own icons")
-- ---------------------------------------------------------------------------
local sprites = load("gen4_species_sprites")
ok(type(sprites) == "table", "gen4_species_sprites did not load from %s", DIR)
local icons = sprites and sprites.icons
ok(type(icons) == "table" and type(icons.bySpecies) == "table",
   "the Platinum cache carries no icons.bySpecies")
if not (icons and icons.bySpecies) then
  io.write(("\n%d checks, %d failed\n"):format(checks, fails))
  os.exit(1)
end

local covered, maxSpecies = 0, 0
for id, entry in pairs(icons.bySpecies) do
  if type(id) == "number" then
    covered = covered + 1
    if id > maxSpecies then maxSpecies = id end
    if type(entry) ~= "table" or type(entry.image) ~= "string" then
      ok(false, "species %d has no image path", id)
    end
  end
end
io.write(("  %d species covered, highest id %d\n"):format(covered, maxSpecies))
-- Sinnoh ends at 493. A table that stopped at Kanto is the bug, not the fix.
ok(maxSpecies >= 493, "the icon table stops at species %d; Sinnoh runs to 493",
   maxSpecies)
ok(covered >= 493, "only %d species have an icon", covered)

-- ...AND THE FILES ARE THERE. A path in the table that is not on disk fails
-- exactly as a missing table does, at the same place, with no way to tell.
do
  local root = DIR:gsub("[/\\]data[/\\]generated[/\\]?$", "")
  -- THE ART MAY NOT BE BESIDE THE DATA. Only the cache's data directory is
  -- reachable from some hosts, and "the assets tree is not here" is a
  -- different fact from "an icon is missing". Reporting the first as the
  -- second is how a check earns a reputation for crying wolf, so the two are
  -- told apart: the presence of ANY sampled file decides which this is.
  local paths, sampled = {}, 0
  for _, id in ipairs({ 1, 25, 151, 152, 251, 252, 386, 387, 390, 393, 483,
                        487, 491, 493 }) do
    local entry = icons.bySpecies[id]
    if entry and entry.image then
      sampled = sampled + 1
      paths[#paths + 1] = { id = id, path = root .. "/" .. entry.image }
    else
      ok(false, "species %d has no image path to check", id)
    end
  end
  ok(sampled > 0, "no sampled species had an image path at all")
  local present, missing = 0, {}
  for _, row in ipairs(paths) do
    local f = io.open(row.path, "rb")
    if f then f:close(); present = present + 1
    else missing[#missing + 1] = row.id end
  end
  if present == 0 then
    io.write(("  (the assets tree is not reachable from here -- %d paths "
              .. "unchecked)\n"):format(#paths))
  else
    ok(#missing == 0, "the assets tree IS here but %d icon(s) are missing: %s",
       #missing, table.concat(missing, " "))
  end
end

-- ---------------------------------------------------------------------------
section("2. the Sinnoh starters, by name")
-- ---------------------------------------------------------------------------
-- A table that is present but shifted draws the wrong creature, which is a
-- worse failure than a blank and one no count can see. The image path carries
-- the dex number, so the two can be held against each other.
for _, id in ipairs({ 387, 390, 393, 483, 484, 487, 493 }) do
  local entry = icons.bySpecies[id]
  local want = ("%03d"):format(id)
  ok(entry and entry.image and entry.image:find(want, 1, true) ~= nil,
     "species %d points at %q, which is not %s", id,
     tostring(entry and entry.image), want)
end

-- ---------------------------------------------------------------------------
section("3. the lift publishes them even when an un-prefixed `icons` resolved")
-- ---------------------------------------------------------------------------
-- THE FAULT ITSELF, reproduced: a Gen 4 cache where `icons` came back non-nil
-- because the additive overlay walked through to the root cache. The lift has
-- to prefer the cartridge's own table anyway.
local Data = require("src.core.Data")
ok(type(Data) == "table", "src.core.Data did not load")

-- A stand-in for Red's table: real in shape, Kanto in content.
local function kantoIcons()
  local by = {}
  for id = 1, 151 do
    by[id] = { frameHeight = 32,
               image = ("assets/generated/icons/%03d.png"):format(id) }
  end
  return { bySpecies = by, frameHeight = 32 }
end

-- The lift, as `Data:load` runs it, against a table that is NOT nil.
local function runLift(existing)
  local self = { gen4_species_sprites = sprites, icons = existing }
  local s = sprites
  local ic = s and s.icons
  if ic and ic.bySpecies then self.icons = ic end
  return self.icons
end

do
  local inherited = kantoIcons()
  local result = runLift(inherited)
  ok(result ~= inherited,
     "with Red's table already in place the lift left it there -- every "
     .. "Sinnoh party draws from Kanto")
  ok(result == icons, "the lift published something other than the cartridge's "
     .. "own icon table")
  -- and with nothing inherited it still works
  ok(runLift(nil) == icons, "with no inherited table the lift published nothing")
end

-- ...AND THE SOURCE SAYS SO. The guard that caused this was `== nil`; if it
-- comes back, section 3 above is a copy of the lift and would not notice.
do
  local src = io.open("src/core/Data.lua", "rb")
  ok(src ~= nil, "src/core/Data.lua could not be read")
  if src then
    local body = src:read("*a"); src:close()
    local at = body:find("THE PARTY ICONS, PUBLISHED UNDER THE NAME", 1, true)
    ok(at ~= nil, "the party-icon lift is gone from Data.lua")
    if at then
      local window = body:sub(at, at + 3000)
      local stop = window:find("SINNOH'S TRAINER ART", 1, true)
      if stop then window = window:sub(1, stop) end
      ok(window:find("self.icons = icons", 1, true) ~= nil,
         "the lift no longer assigns the cartridge's icons")
      ok(window:find("if self.icons == nil then", 1, true) == nil,
         "the lift is gated on `self.icons == nil` again, which is exactly "
         .. "what Red's inherited table satisfies")
      -- WHICH MODULE IT READS, pinned here because section 3 above is a MODEL
      -- of the lift rather than the lift itself: pointing the real one at
      -- another table would leave that model passing. Anchored to the
      -- assignment, not a bare search, so the name in this comment cannot
      -- satisfy it.
      ok(window:find("local sprites = self.gen4_species_sprites", 1, true) ~= nil,
         "the lift no longer reads `gen4_species_sprites`, which is the only "
         .. "module that carries Sinnoh's icon table")
      ok(window:find("sprites and sprites.icons", 1, true) ~= nil,
         "the lift no longer takes `.icons` off that module")
    end
  end
end

-- ---------------------------------------------------------------------------
section("4. what the party menu would draw")
-- ---------------------------------------------------------------------------
-- `Gen4PartyMenu:iconFor` reads data.icons.bySpecies[species], falls back to
-- the species record's own `icon`, and draws a Poke Ball when both miss.
do
  local pokemon = load("pokemon")
  local data = { icons = icons, pokemon = pokemon }
  local function resolves(species)
    local entry = (data.icons and data.icons.bySpecies
                   and data.icons.bySpecies[species])
                  or (data.pokemon and data.pokemon[species]
                      and data.pokemon[species].icon)
    if type(entry) == "table" then return entry.image ~= nil end
    return type(entry) == "string"
  end
  local balls = {}
  for id = 1, 493 do
    if not resolves(id) then balls[#balls + 1] = id end
  end
  ok(#balls == 0, "%d species would still draw a Poke Ball (first few: %s)",
     #balls, table.concat({ balls[1], balls[2], balls[3] }, " "))

  -- ...AND THE CONTROL: with Kanto's table the party list IS balls, so the
  -- check above is measuring something that can fail.
  local kanto = { icons = kantoIcons(), pokemon = pokemon }
  local kantoBalls = 0
  for id = 1, 493 do
    local entry = kanto.icons.bySpecies[id]
      or (kanto.pokemon and kanto.pokemon[id] and kanto.pokemon[id].icon)
    if not entry then kantoBalls = kantoBalls + 1 end
  end
  ok(kantoBalls > 300, "with Kanto's table only %d species miss, so section 4 "
     .. "cannot tell the two tables apart", kantoBalls)
  io.write(("  with Red's table: %d of 493 species draw a Poke Ball\n")
           :format(kantoBalls))
end

-- ---------------------------------------------------------------------------
section("5. Gen 1/2/3 keep their own icons")
-- ---------------------------------------------------------------------------
-- The lift runs only inside the Gen 4 branch; this proves the module a Gen 3
-- cache carries is a real, different table, so preferring the cartridge's own
-- on Gen 4 cannot have taken anything from Hoenn.
if ROOT then
  local chunk = loadfile(ROOT .. "/icons.lua")
  ok(chunk ~= nil, "no icons.lua at %s", ROOT)
  if chunk then
    local okc, other = pcall(chunk)
    ok(okc and type(other) == "table", "that icons.lua did not load")
    if okc and type(other) == "table" and other.bySpecies then
      ok(other ~= icons, "the two caches returned the same table")
      local high = 0
      for id in pairs(other.bySpecies) do
        if type(id) == "number" and id > high then high = id end
      end
      io.write(("  the un-prefixed cache's icons reach species %d\n"):format(high))
      -- No assertion on another cartridge's range -- it is not this check's
      -- business. What IS asserted is that it is a DIFFERENT table from the
      -- one Sinnoh now uses, which is the whole point of the lift.
      local shared = 0
      for id, entry in pairs(other.bySpecies) do
        local mine = icons.bySpecies[id]
        if mine and entry == mine then shared = shared + 1 end
      end
      ok(shared == 0, "%d icon entries are shared between the two caches, so "
         .. "one is standing in for the other", shared)
    end
  end
else
  io.write("  (no root cache passed; section skipped)\n")
end

-- ---------------------------------------------------------------------------
section("6. which other modules a Sinnoh cache silently borrows from Kanto")
-- ---------------------------------------------------------------------------
-- THE CLASS, NOT THE CASE. `icons` was one module; the mechanism that broke it
-- -- optional, unwritten by this cartridge, unblocked, and therefore resolved
-- through the additive overlay to the root cache -- applies to every name in
-- OPTIONAL. `tools/gen4_module_sets.lua` cannot see this: it compares which
-- modules are REQUIRED, and a module can be correctly optional and still hand
-- Sinnoh another cartridge's data.
--
-- So the borrowed set is computed and PINNED. A new one appearing is a new bug
-- of exactly this shape, and this is where it announces itself.
do
  local src = io.open("src/core/Data.lua", "rb")
  ok(src ~= nil, "src/core/Data.lua could not be read")
  if src then
    local body = src:read("*a"); src:close()
    local function list(name)
      local chunk = body:match("\nlocal " .. name .. " = %{(.-)%}")
      if not chunk then return nil end
      local out = {}
      for word in chunk:gmatch('"([%w_]+)"') do out[#out + 1] = word end
      return out
    end
    local OPTIONAL, CLASSIC = list("OPTIONAL"), list("CLASSIC_ONLY")
    ok(OPTIONAL and #OPTIONAL > 0, "the OPTIONAL list could not be read")
    ok(CLASSIC and #CLASSIC > 0, "the CLASSIC_ONLY list could not be read")
    if OPTIONAL and CLASSIC then
      local blocked = {}
      for _, n in ipairs(CLASSIC) do blocked[n] = true end
      -- what this cache actually writes
      local written = {}
      for _, n in ipairs(OPTIONAL) do
        if loadfile(DIR .. "/" .. n .. ".lua") then written[n] = true end
      end
      local borrowed = {}
      for _, n in ipairs(OPTIONAL) do
        if not written[n] and not blocked[n] then borrowed[#borrowed + 1] = n end
      end
      table.sort(borrowed)
      io.write("  borrowed from the root cache: "
               .. table.concat(borrowed, " ") .. "\n")
      -- `icons` is in this list and is SUPPOSED to be: the module still
      -- resolves to Red's, and the Gen 4 lift above then replaces it. The
      -- other three are unexamined, and saying so is the point.
      local EXPECTED = { icons = true, scenes = true,
                         save_layout = true, songs = true }
      local surprises = {}
      for _, n in ipairs(borrowed) do
        if not EXPECTED[n] then surprises[#surprises + 1] = n end
      end
      ok(#surprises == 0,
         "NEW module(s) now resolve to the root cache on a Sinnoh cache: %s -- "
         .. "each one hands Platinum another cartridge's data, which is the "
         .. "bug this file was written for", table.concat(surprises, " "))
      -- ...and the reverse: one leaving the list without being examined would
      -- mean the pin has gone stale and stopped measuring.
      local gone = {}
      for n in pairs(EXPECTED) do
        local found = false
        for _, m in ipairs(borrowed) do if m == n then found = true end end
        if not found then gone[#gone + 1] = n end
      end
      table.sort(gone)
      ok(#gone == 0, "%s no longer resolves to the root cache -- good, but "
         .. "this pin is now stale and must be updated", table.concat(gone, " "))
    end
  end
end

io.write(("\n%d checks, %d failed\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
