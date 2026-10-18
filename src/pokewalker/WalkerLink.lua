-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE POKEWALKER'S LINK TO A GAME'S SAVE, from the launcher (no game running).
--
--   SEND: the Pokemon leaves its PC box -- the save's own table, untouched,
--   rides in the walker -- as the original takes it out of the box.
--   RETURN / RECEIVE PRESENT: what the walk brought (the Pokemon with its steps
--   and friendship, the catches, the items) is written into the save as
--   `save.walkerInbox`; the game itself unpacks it on its next load
--   (src/pokewalker/WalkerInbox.lua), where it has the data to level the
--   Pokemon and to build the catches in that generation's own shape.
--
-- Every save this touches is copied first to pokewalker_backups/.

local SaveData = require("src.core.SaveData")
local Ser = require("src.core.SaveSerializer")
local Courses = require("src.pokewalker.WalkerCourses")

local L = {}

local function readSave(version, slotId)
  local path = SaveData.slotDiskPath(version, slotId)
  local f = path and io.open(path, "rb")
  if not f then return nil, "no save in that slot" end
  local bytes = f:read("*a"); f:close()
  local ok, t = pcall(Ser.decode, bytes)
  if not (ok and type(t) == "table") then return nil, "the save does not read" end
  return t, bytes
end

local function backup(version, slotId, bytes, why)
  if not (bytes and love and love.filesystem) then return end
  local dir = ("pokewalker_backups/%s"):format(version)
  love.filesystem.createDirectory(dir)
  love.filesystem.write(("%s/%s_%s_%s.lua"):format(dir, slotId, os.date("%Y%m%d_%H%M%S"), why or "walk"), bytes)
end

local function norm(s) return (tostring(s or ""):upper():gsub("[^%w]", "")) end

-- the national dex number of a save's species field ("SPECIES_155", "ABSOL", 6)
function L.dexOf(version, species)
  local GameVersion = require("src.core.GameVersion")
  local info = GameVersion.info(version)
  local gen = info and tonumber(info.generation) or 2
  local n = tonumber(species)
  if n and gen >= 4 then return n end
  local m = type(species) == "string" and tonumber(species:match("^SPECIES_(%d+)$"))
  if m and gen == 2 then return m end
  if n and gen == 2 then return n end
  local want = norm(type(species) == "string" and species:gsub("^SPECIES_", "") or species)
  if want == "" then return nil end
  for dex, sp in pairs(Courses.species()) do
    if norm(sp.name) == want then return dex end
  end
  return nil
end

-- a box Pokemon as the walker shows it
local function describe(version, mon, where)
  local dex = L.dexOf(version, mon.species)
  local sp = dex and Courses.species()[dex]
  return {
    raw = mon, species = dex, name = mon.nickname or (sp and sp.name) or tostring(mon.species),
    level = tonumber(mon.level) or 1, types = sp and sp.types or {},
    friendship = tonumber(mon.happiness or mon.friendship) or 70,
    isEgg = mon.isEgg, source = where,
  }
end

-- every Pokemon in a slot's PC boxes (eggs left out: the walker never took one)
function L.boxMons(version, slotId)
  local save, why = readSave(version, slotId)
  if not save then return nil, why end
  local out = {}
  local boxes = save.boxes
  if type(boxes) ~= "table" and type(save.box) == "table" then boxes = save.box.boxes or { save.box } end
  for b, box in ipairs(boxes or {}) do
    local list = box.mons or box
    for i, mon in ipairs(type(list) == "table" and list or {}) do
      if type(mon) == "table" and mon.species and not mon.isEgg then
        out[#out + 1] = describe(version, mon, { version = version, slot = slotId, box = b, index = i })
      end
    end
  end
  return out
end

-- does the save have the National Dex (a few spellings across the generations)
function L.hasNatDex(version, slotId)
  local save = readSave(version, slotId)
  if not save then return false end
  local GameVersion = require("src.core.GameVersion")
  local info = GameVersion.info(version)
  if info and tonumber(info.generation) and tonumber(info.generation) <= 2 then return true end
  return save.nationalDex == true or (save.pokedex and save.pokedex.national == true)
    or (save.flags and (save.flags.FLAG_SYS_NATIONAL_DEX or save.flags.nationalDex)) and true or false
end

-- take a box Pokemon out of its save and onto the walker
function L.send(st, entry, courseId)
  local W = require("src.pokewalker.Walker")
  if st.walking then return false, "a Pokemon is already walking -- bring it home first" end
  local src = entry.source
  local save, bytes = readSave(src.version, src.slot)
  if not save then return false, bytes end
  local boxes = save.boxes
  if type(boxes) ~= "table" and type(save.box) == "table" then boxes = save.box.boxes or { save.box } end
  local box = boxes and boxes[src.box]
  local list = box and (box.mons or box)
  if not (list and list[src.index] == entry.raw or (list and list[src.index]
          and list[src.index].species == entry.raw.species and list[src.index].level == entry.raw.level)) then
    return false, "that Pokemon has moved -- reopen the list"
  end
  backup(src.version, src.slot, bytes, "send")
  local mon = table.remove(list, src.index)
  local ok, err = SaveData.writeSlot(src.version, src.slot, save)
  if not ok then return false, err end
  local entries, route = Courses.forGame(courseId, src.version)
  entry.raw = mon
  W.send(st, courseId, entry, entries, route)
  W.save(st)
  return true
end

-- the PC's slot count, by the save's own generation: the launcher has no game
-- loaded, so the engine's Boxes (which asks the running game) cannot answer
local function boxCapacity(version)
  local okV, V = pcall(require, "src.core.GameVersion")
  local gen = okV and V.generation and V.generation(version) or 1
  return gen <= 2 and 20 or 30
end

-- Put a Pokemon back in a save's PC: its own slot if free, else the first free
-- slot of its own box, else of any box. Returns { box = b, index = i } or nil.
local function placeInBox(save, version, source, mon)
  if type(mon) ~= "table" then return nil end
  local boxes = save.boxes
  if type(boxes) ~= "table" and type(save.box) == "table" then boxes = save.box.boxes or { save.box } end
  if type(boxes) ~= "table" then return nil end
  local cap = boxCapacity(version)
  local function freeIn(b)
    local list = boxes[b]
    if type(list) ~= "table" then return nil end
    list = list.mons or list
    for i = 1, cap do if list[i] == nil then return list, i end end
    return nil
  end
  local order = {}
  if source and source.box then order[1] = source.box end
  for b = 1, #boxes do if b ~= (source and source.box) then order[#order + 1] = b end end
  for _, b in ipairs(order) do
    local list, i = freeIn(b)
    if list then
      -- the very slot it left, when that is the first gap (send closed the gap)
      if b == (source and source.box) and source.index and source.index <= i then
        table.insert(list, source.index, mon)
        return { box = b, index = source.index }
      end
      list[i] = mon
      return { box = b, index = i }
    end
  end
  return nil
end

-- write what came home into the source save's inbox
local function deliver(version, slotId, parcel)
  local save, bytes = readSave(version, slotId)
  if not save then return false, bytes end
  backup(version, slotId, bytes, "home")
  save.walkerInbox = save.walkerInbox or { mons = {}, items = {}, returning = {} }
  local box = save.walkerInbox
  box.mons, box.items, box.returning = box.mons or {}, box.items or {}, box.returning or {}
  if parcel.mon then
    -- STRAIGHT BACK INTO THE PC. Reported from play: "when sending a pokemon
    -- home from the pokewalker they dont go back to their box". The walked
    -- Pokemon only reached the inbox, and the inbox is unpacked when the game
    -- next loads THIS save -- so the PC on disk, and the walker's own box list,
    -- went on without it until the game was played and saved. It is put back
    -- where it came from (or the first free slot) now; the inbox keeps only
    -- what needs the game's data -- its steps as EXP and its friendship --
    -- and says where the Pokemon is, so the load finds it in place.
    local at = placeInBox(save, version, parcel.mon.source, parcel.mon.raw)
    box.returning[#box.returning + 1] = {
      raw = (not at) and parcel.mon.raw or nil, placed = at,
      species = parcel.mon.raw and parcel.mon.raw.species,
      steps = parcel.mon.steps or 0,
      friendship = parcel.mon.friendship, course = parcel.course,
    }
  end
  for _, c in ipairs(parcel.caught or {}) do box.mons[#box.mons + 1] = c end
  for _, it in ipairs(parcel.items or {}) do box.items[#box.items + 1] = it end
  return SaveData.writeSlot(version, slotId, save)
end

-- RETURN FROM WALK (keep = false) or RECEIVE PRESENT (keep = true)
function L.bringHome(st, keep)
  local W = require("src.pokewalker.Walker")
  local w = st.walking
  if not w then return false, "no Pokemon is walking" end
  local src = w.source
  local parcel = { mon = (not keep) and w or nil, caught = st.caught, items = st.items, course = st.course }
  local ok, err = deliver(src.version, src.slot, parcel)
  if not ok then return false, err end
  W.takeHome(st, keep)
  W.note(st, keep and "Presents sent to your game." or ("%s came home."):format(w.name or "Your Pokemon"))
  W.save(st)
  return true
end

return L
