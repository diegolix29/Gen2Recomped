-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- WHAT A HOENN MAP AND A HOENN FLAG ARE CALLED, for the save editor's lists.
--
-- Reported from play: "ensure the save manager lists emerald maps by in game
-- map name and same with flags/events".  Both lists were raw STORAGE keys --
-- MAP_G01_N03 and FLAG_G3_0867 -- and neither is a name anybody has ever seen
-- in the game.  They are this port's own spellings: a map is keyed by the
-- cartridge's map group and number, a flag by its hex id, because those are
-- the only two things the cartridge actually stores.
--
-- MAPS.  Emerald has no per-map name.  What the sign says when you walk into
-- a place is the map header's REGION MAP SECTION -- one name shared by a town
-- and every room inside it -- and that is the name used here, read exactly
-- the way OverworldState:updateMapNameSignGen3 reads it.  Where a section
-- covers more than one map the map's own TYPE is appended (also from the
-- header) so two rows of "PETALBURG CITY" can still be told apart; the raw id
-- stays on the row beside the name, because for indoor maps it is the only
-- thing that separates one house from the next.
--
-- FLAGS.  The cartridge has no flag names either: pokeemerald's FLAG_* are
-- source constants that were compiled away long before the ROM.  So nothing
-- here is a name looked up in a table -- every label is DERIVED FROM WHAT THE
-- FLAG IS USED FOR, from data this port already extracted, in this order:
--
--   badge     constants.badges / gen3BadgeFlags     "STONEBADGE earned"
--   named     any constant that IS a flag           "gen3StrengthFlag"
--   trainer   gen3TrainerFlagBase + gTrainers index "beaten: CAMPER LIAM"
--   object    a map object's eventFlag              "hides object 3 on ROUTE 110"
--   hidden    a hidden item's flag                  "hidden RARE CANDY on ROUTE 104"
--   script    reachable from a map's own scripts    "used by MAUVILLE CITY scripts"
--
-- and a flag that NONE of those explain keeps its storage key, which is the
-- honest answer rather than an invented one.
--
-- Everything is built once per data table and memoised: the script pass walks
-- the whole pool, which is cheap once and not cheap per frame.

local Gen3Names = {}

local cache = setmetatable({}, { __mode = "k" })

-- THE CACHE IS KEYED ON A TABLE THAT GETS REFILLED UNDER IT.
--
-- `Data` is a singleton: App.unload drops the editor's state and the next
-- App.load re-runs Data:load against whatever cache is mounted by then --
-- possibly the OTHER game's.  The table identity never changes, so a cache
-- keyed on it alone would hand a Crystal save Hoenn's map names.  The
-- generation is bumped by forget(), which App.unload calls, and anything else
-- holding a derived list can watch it for the same reason.
Gen3Names.generation = 1

function Gen3Names.forget()
  cache = setmetatable({}, { __mode = "k" })
  Gen3Names.generation = Gen3Names.generation + 1
end

local FLAG_KEY = "^FLAG_G3_%x%x%x%x$"

-- HOW HIGH A FLAG NUMBER CAN GO, which is not "as high as a halfword".
--
-- A Gen 3 save carries the flags as a flat bit array and the extracted save
-- layout says how long it is (300 bytes in Emerald -- 2400 flags), so
-- anything above that is not a flag at all.  The numbers that turn up there
-- are VARIABLES: `checkflag VAR_TEMP_0` means "the flag whose id is in this
-- var", and the operand is $4000-odd, which would otherwise have been listed
-- as four flags nobody can ever set.
--
-- The literal is only the fallback for a dataset with no save layout, and it
-- sits well above the array and well below var space either way.
local FLAG_CEILING = 0x1000

local function flagCeiling(data)
  local layout = data and data.save_layout
  local bytes = layout and tonumber(layout.flagBytes)
  if bytes and bytes > 0 then return bytes * 8 end
  local fields = layout and layout.fields
  bytes = fields and tonumber(fields.flagBytes)
  if bytes and bytes > 0 then return bytes * 8 end
  return FLAG_CEILING
end

local function flagKey(n)
  return ("FLAG_G3_%04X"):format(n)
end
Gen3Names.flagKey = flagKey

-- --------------------------------------------------------------------- maps

-- Title-case a header's MAP TYPE so it reads as a qualifier next to a
-- shouted place name ("PETALBURG CITY - Indoor") instead of a second shout.
local function prettyType(mapType)
  if type(mapType) ~= "string" or mapType == "" then return nil end
  local words = {}
  for word in mapType:gmatch("[^_]+") do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
  end
  return table.concat(words, " ")
end

local function buildMaps(data)
  local maps = data and data.maps or {}
  local sections = (data and data.constants or {}).gen3MapSections or {}
  -- how many maps each section covers, so the type qualifier is only spent
  -- where it buys something
  local share = {}
  for id, def in pairs(maps) do
    if type(id) == "string" and type(def) == "table" then
      local name = sections[def.regionMapSection]
      if type(name) == "string" and name ~= "" then
        share[name] = (share[name] or 0) + 1
      end
    end
  end
  local out = {}
  for id, def in pairs(maps) do
    if type(id) == "string" and type(def) == "table" then
      local name = sections[def.regionMapSection]
      if type(name) == "string" and name ~= "" then
        -- the ROM's own names carry line breaks for the two-line sign
        name = name:gsub("[\n\f\v]", " ")
        local qualifier = (share[name] or 0) > 1 and prettyType(def.mapType) or nil
        out[id] = qualifier and (name .. "  -  " .. qualifier) or name
      end
    end
  end
  return out
end

-- -------------------------------------------------------------------- flags

-- A flag value as this port spells it, from either shape a constant holds it
-- in: the number the cartridge uses, or the "FLAG_G3_xxxx" string the save
-- walk uses.
local function asFlagKey(value, ceiling)
  if type(value) == "number" then
    if value >= 0 and value < (ceiling or FLAG_CEILING)
       and value == math.floor(value) then
      return flagKey(value)
    end
    return nil
  end
  if type(value) == "string" and value:match(FLAG_KEY) then return value end
  return nil
end

-- Constants that ARE flags, labelled by where they sit in the constants
-- table.  Only two shapes count as evidence: a value already spelled
-- FLAG_G3_xxxx (unambiguous), and a NUMBER under a key that says "flag"
-- (gen3StrengthFlag, badgeFlag, hallFlag).  A bare number under any other
-- key is not evidence of anything -- half this table is numbers.
local NOT_A_FLAG_KEY = { base = true, start = true, count = true, first = true,
                         last = true, size = true, offset = true, index = true }

-- A constants path as a reader's phrase: "gen3StartMenu.pokedexFlag" is where
-- the value lives, "start menu > pokedex flag" is what it says.  The path is
-- kept (it is the evidence) and only respelled -- the `gen3` prefix every
-- Hoenn constant carries says nothing inside a Hoenn save, and camelCase is
-- not a thing anybody reads down a list of three hundred rows.
function Gen3Names.prettyPath(path)
  local parts = {}
  for segment in tostring(path):gmatch("[^.]+") do
    segment = segment:gsub("^gen3", "")
    if segment ~= "" then
      local words = segment:gsub("(%l)(%u)", "%1 %2"):gsub("_", " ")
      parts[#parts + 1] = words:lower()
    end
  end
  if #parts == 0 then return tostring(path) end
  return table.concat(parts, " > ")
end

local function namedFromConstants(constants, out, ceiling)
  local seen = {}
  local function walk(node, path, depth)
    if type(node) ~= "table" or depth > 4 or seen[node] then return end
    seen[node] = true
    for key, value in pairs(node) do
      local label = (type(key) == "string") and key or nil
      local here = label and (path == "" and label or (path .. "." .. label))
                   or (path .. "[" .. tostring(key) .. "]")
      if type(value) == "table" then
        walk(value, here, depth + 1)
      else
        local flagish = false
        if type(value) == "string" then
          flagish = value:match(FLAG_KEY) ~= nil
        elseif type(value) == "number" and label then
          local tail = label:match("[Ff]lags?([A-Za-z]*)$")
          flagish = tail ~= nil and not NOT_A_FLAG_KEY[tail:lower()]
        end
        if flagish then
          local k = asFlagKey(value, ceiling)
          if k and not out[k] then out[k] = Gen3Names.prettyPath(here) end
        end
      end
    end
  end
  walk(constants or {}, "", 1)
end

local function badgeLabels(data, out, ceiling)
  local constants = data and data.constants or {}
  for i, entry in ipairs(constants.badges or {}) do
    local k = asFlagKey(entry.flag, ceiling) or asFlagKey(entry.item, ceiling)
    if k then
      out[k] = ("badge %d: %s"):format(i, tostring(entry.id or "?"))
    end
  end
  for i, flag in ipairs(constants.gen3BadgeFlags or {}) do
    local k = asFlagKey(flag, ceiling)
    if k and not out[k] then out[k] = ("badge %d earned"):format(i) end
  end
end

local function trainerLabels(data, out)
  local constants = data and data.constants or {}
  local base = tonumber(constants.gen3TrainerFlagBase)
  if not base then return end
  for _, entry in pairs(data.trainers or {}) do
    if type(entry) == "table" and tonumber(entry.index) then
      local k = flagKey(base + entry.index)
      if not out[k] then
        -- gTrainers[0] is the unused placeholder and has NO name; several
        -- of the Frontier's records are blank the same way.  A label of
        -- "beaten: HIKER " with nothing after it is worse than saying which
        -- record it is, so an empty name falls back to the index.
        local who = entry.name
        if type(who) ~= "string" or who:match("^%s*$") then
          who = ("#%d"):format(entry.index)
        end
        local class = entry.className
        out[k] = ("beaten: %s"):format(
          (type(class) == "string" and class ~= "") and (class .. " " .. who) or who)
      end
    end
  end
end

local function mapEventLabels(data, mapNames, out)
  for id, def in pairs(data.maps or {}) do
    if type(id) == "string" and type(def) == "table" then
      local where = mapNames[id] or id
      for i, obj in ipairs(def.objects or {}) do
        local k = type(obj) == "table" and asFlagKey(obj.eventFlag)
        if k and not out[k] then
          out[k] = ("hides object %d on %s"):format(i, where)
        end
      end
      for _, sign in ipairs(def.signs or {}) do
        local k = type(sign) == "table" and asFlagKey(sign.eventFlag)
        if k and not out[k] then
          local item = sign.item
          out[k] = ("hidden %s on %s"):format(
            (type(item) == "string" and item ~= "") and item or "item", where)
        end
      end
    end
  end
end

-- WHICH MAP'S SCRIPTS TOUCH A FLAG.
--
-- The last resort, and the one that covers the story: a flag a cutscene sets
-- has no other trace in the data at all.  A map's index names the scripts its
-- objects, signs, coord events, callbacks and var tables start; a scene is
-- rarely one script, so each is followed through its own branch targets the
-- same way the extractor's addobject pass follows them -- any argument that
-- is a ROM pointer into the script pool is another script in the same scene.
local SCRIPT_BASE, SCRIPT_TOP = 0x8000000, 0x9000000

local function scriptLabels(data, mapNames, out, ceiling)
  local pool = data and data.map_scripts
  local scripts = pool and pool.scripts
  local index = pool and pool.maps
  if type(scripts) ~= "table" or type(index) ~= "table" then return end
  -- flag -> the maps that reach it; a flag reached from one map names that
  -- map, a flag reached from several says so rather than picking one
  local owners = {}
  for mapId, entry in pairs(index) do
    local roots, seen = {}, {}
    local function add(key) if type(key) == "string" then roots[#roots + 1] = key end end
    for _, key in pairs(entry.objects or {}) do add(key) end
    for _, key in pairs(entry.signs or {}) do add(key) end
    for _, rec in ipairs(entry.coords or {}) do add(type(rec) == "table" and (rec.script or rec[2])) end
    for _, rec in ipairs(entry.callbacks or {}) do add(type(rec) == "table" and (rec.script or rec[2])) end
    for _, rec in ipairs(entry.tables or {}) do
      if type(rec) == "table" then
        add(rec.script or rec[2])
        for _, row in ipairs(rec.rows or {}) do
          add(type(row) == "table" and (row.script or row[2]))
        end
      end
    end
    local at = 1
    while roots[at] do
      local key = roots[at]
      at = at + 1
      if not seen[key] then
        seen[key] = true
        for _, row in ipairs(scripts[key] or {}) do
          local op = row[1]
          if op == "setflag" or op == "clearflag" or op == "checkflag" then
            local f = tonumber(row[2])
            if f and f < (ceiling or FLAG_CEILING) then
              local fk = flagKey(f)
              local owner = owners[fk]
              if owner == nil then owners[fk] = mapId
              elseif owner ~= mapId then owners[fk] = false end
            end
          end
          for k = 2, #row do
            local v = row[k]
            if type(v) == "number" and v > SCRIPT_BASE and v < SCRIPT_TOP then
              roots[#roots + 1] = ("S%07X"):format(v - SCRIPT_BASE)
            end
          end
        end
      end
    end
  end
  for fk, mapId in pairs(owners) do
    if not out[fk] then
      out[fk] = mapId and ("used by %s scripts"):format(mapNames[mapId] or mapId)
        or "used by scripts in several places"
    end
  end
end

-- ------------------------------------------------------------------ the API

-- Built once per data table.  Nothing here mutates `data`.
function Gen3Names.index(data)
  if type(data) ~= "table" then return { maps = {}, flags = {} } end
  local hit = cache[data]
  if hit then return hit end
  local maps = buildMaps(data)
  local flags = {}
  local ceiling = flagCeiling(data)
  badgeLabels(data, flags, ceiling)
  namedFromConstants(data.constants, flags, ceiling)
  trainerLabels(data, flags)
  mapEventLabels(data, maps, flags)
  scriptLabels(data, maps, flags, ceiling)
  hit = { maps = maps, flags = flags }
  cache[data] = hit
  return hit
end

-- The in-game name of a map, or nil when this dataset has none (every
-- non-Gen3 game, and the handful of Hoenn maps whose header points at no
-- named section).
function Gen3Names.map(data, id)
  if type(id) ~= "string" then return nil end
  return Gen3Names.index(data).maps[id]
end

-- What a flag is for, or nil when nothing in the data explains it.
function Gen3Names.flag(data, key)
  if type(key) ~= "string" then return nil end
  return Gen3Names.index(data).flags[key]
end

return Gen3Names
