-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Gen 4 (Platinum) extractor: cartridge in, cache out.
--
-- Eleven modules under src/import read Platinum correctly and none of them
-- writes anything.  This is the stage runner that puts them in order and
-- lands their output in data/generated, which is what CacheFs.mountVersion
-- serves to a running game.
--
-- IT TAKES A PATH, NOT THE ROM'S BYTES, and that is the one place it refuses
-- to look like RomExtractorGen2 and RomExtractorGen3.  Those are handed the
-- whole cartridge as a Lua string because a Game Boy ROM is at most 32 MiB
-- and every stage wants a different part of it.  Platinum is 128 MiB, the
-- engine has to run alongside it on a phone, and almost every stage wants ONE
-- FILE out of a filesystem.  NdsRom reads ranges on demand from an open
-- handle; handing it a 128 MiB string instead would undo that before the
-- first stage ran.
--
-- The consequence is that RomImporter's `startData` path cannot drive this as
-- it drives the others: it reads the file into memory and hashes the string.
-- Verification still needs the bytes, but extraction must not, so an import
-- that reaches this point has to pass the path along.  That is a real seam
-- and it is not built yet -- see the note at the bottom of this file.
--
-- WHAT EACH STAGE WRITES, and why the shape is what it is: every table is
-- keyed the way the engine already expects for Gen 1-3, because
-- Commands.resolve, the party screens and the Pokedex are
-- generation-agnostic and a fourth spelling of "species" would be a fourth
-- set of branches in code that currently has none.

local RomExtractorGen4 = {}
RomExtractorGen4.__index = RomExtractorGen4

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Gen4Text = require("src.import.Gen4Text")
local Gen4Species = require("src.import.Gen4Species")
local Gen4Moves = require("src.import.Gen4Moves")
local Gen4Items = require("src.import.Gen4Items")
local Gen4Encounters = require("src.import.Gen4Encounters")
local Gen4Trainers = require("src.import.Gen4Trainers")
local Gen4Maps = require("src.import.Gen4Maps")
local Gen4Events = require("src.import.Gen4Events")
local Gen4MapHeaders = require("src.import.Gen4MapHeaders")
local Gen4Script = require("src.import.Gen4Script")
local Gen4Graphics = require("src.import.Gen4Graphics")
local Gen4Archives = require("src.import.Gen4Archives")
local Gen4Screens = require("src.import.Gen4Screens")
local Gen4Battle = require("src.import.Gen4Battle")
local Gen4Cells = require("src.import.Gen4Cells")
local Gen4Font = require("src.import.Gen4Font")
local Gen4Tileset = require("src.import.Gen4Tileset")
local Gen4TypeChart = require("src.import.Gen4TypeChart")
local Gen4Models = require("src.import.Gen4Models")
local Gen4Pokegra = require("src.import.Gen4Pokegra")
local Gen4Otherpoke = require("src.import.Gen4Otherpoke")
local Gen4ObjectGfx = require("src.import.Gen4ObjectGfx")
local Gen4ScriptBands = require("src.import.Gen4ScriptBands")
local Gen4Pickups = require("src.import.Gen4Pickups")
local Gen4Bdhc = require("src.import.Gen4Bdhc")
local Gen4Field = require("src.import.Gen4Field")
local Gen4Menus = require("src.import.Gen4Menus")
local Gen4IntroScene = require("src.import.Gen4IntroScene")
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")
local Gen4ModelPack = require("src.import.Gen4ModelPack")
local Gen4Anim = require("src.import.Gen4Anim")
local ImageWriter = require("src.import.ImageWriter")
local Gen4ScriptVM = require("src.script.Gen4ScriptVM")
local LuaWriter = require("src.import.LuaWriter")

local floor = math.floor

-- THE TIMING IS THIS PORT'S, NOT THE CARTRIDGE'S.  Platinum times its two
-- battle-sprite frames from a per-species animation script that is not
-- extracted, so the pattern below is the same two-beats-out-and-back settle
-- Gen 3's stage uses -- deliberately identical, so a Pokemon does not move at
-- one speed in Hoenn and another in Sinnoh for no reason anyone chose.
local GEN4_PIC_ANIM_PLAY = {
  { frame = 1, dur = 8 }, { frame = 2, dur = 8 },
  { frame = 1, dur = 8 }, { frame = 2, dur = 8 },
  { frame = 1, dur = 8 },
}

-- Cartridge paths, in one place.  A stage that spells one itself is a stage
-- that keeps working after the path it wanted stops existing.
local PATH = {
  text = "/msgdata/pl_msg.narc",
  personal = "/poketool/personal/pl_personal.narc",
  learnsets = "/poketool/personal/wotbl.narc",
  evolutions = "/poketool/personal/evo.narc",
  moves = "/poketool/waza/pl_waza_tbl.narc",
  items = "/itemtool/itemdata/pl_item_data.narc",
  encounters = "/fielddata/encountdata/pl_enc_data.narc",
  trainerData = "/poketool/trainer/trdata.narc",
  trainerParty = "/poketool/trainer/trpoke.narc",
  matrices = "/fielddata/mapmatrix/map_matrix.narc",
  land = "/fielddata/land_data/land_data.narc",
  events = "/fielddata/eventdata/zone_event.narc",
  scripts = "/fielddata/script/scr_seq.narc",
  mapNames = "/fielddata/maptable/mapname.bin",
  areaData = "/fielddata/areadata/area_data.narc",
  battleBg = "/battle/graphic/pl_batt_bg.narc",
  battleObj = "/battle/graphic/pl_batt_obj.narc",
  fonts = "/graphic/pl_font.narc",
  overworld = "/data/mmodel/mmodel.narc",
  pokegra = "/poketool/pokegra/pl_pokegra.narc",
  pokeHeight = "/poketool/pokegra/height.narc",
  otherpoke = "/poketool/pokegra/pl_otherpoke.narc",
  winframe = "/graphic/pl_winframe.narc",
  title = "/demo/title/titledemo.narc",
  intro = Gen4IntroScene.PATH,
  introTv = Gen4IntroScene.TV_PATH,
}
RomExtractorGen4.PATH = PATH

-- Message banks, each found by looking rather than assumed -- see the module
-- that uses it for what identified it.
local BANK = {
  species = 412, dexEntry = 706,
  nature = 202, typeName = 624,
  move = 647, moveUpper = 648,
  item = 392, itemDescription = 391,
  moveDescription = 646,
  trainer = 618, mapLabel = 433,
  -- 105 entries, found by looking rather than assumed: bank 619 answers
  -- "Youngster" and "Lass" at 2 and 3, which is exactly where the trainer
  -- class list puts them.  620 is the same list with articles ("a Youngster").
  trainerClass = 619, trainerClassArticle = 620,
  -- 21 entries, read out of the cartridge rather than taken on trust: 0 is
  -- CONTINUE, 1 is NEW GAME and 12 is PLAYER, which is the order
  -- main_menu.c's own sOptions/sContinueOptionStringsIDs tables expect.
  -- 14 is the six-entry alerts bank the NEW GAME warning lives in.
  mainMenu = Gen4Menus.BANK, mainMenuAlert = Gen4Menus.ALERT_BANK,
  -- 53 entries: 0 OPTIONS, 3 TEXT SPEED, 10-12 SLOW/MID/FAST, 22-41 the
  -- twenty frame names, 43-48 the descriptions.
  options = Gen4Menus.OPTIONS_BANK,
  -- 8 entries: the briefcase's lines and the three offers.
  starter = Gen4Menus.STARTER_BANK,
  -- 8 entries, one per pocket, in the order an item's `fieldPocket` numbers
  -- them -- so the index is the pocket rather than a lookup away from it.
  bagPockets = Gen4Menus.BAG_BANK,
  -- 187 entries: the summary screen's six page titles, every field label, and
  -- the twenty-five nature and twenty-five characteristic lines.
  summary = Gen4Menus.SUMMARY_BANK,
  -- The Poketch's twenty-five apps: 29 has them in app order, 213 has their
  -- names picked out in colour.  See Gen4Menus.POKETCH_DESC_BANK.
  poketchDesc = Gen4Menus.POKETCH_DESC_BANK,
  poketchName = Gen4Menus.POKETCH_NAME_BANK,
  -- 45 entries and 1: Rowan's introduction, and the television broadcast
  -- that plays before it.  Both checked entry by entry against the
  -- cartridge rather than taken from the header.
  rowanIntro = Gen4IntroScene.BANK, rowanIntroTv = Gen4IntroScene.TV_BANK,
}
RomExtractorGen4.BANK = BANK

local STAGES = {
  "text", "species", "moves", "items", "encounters",
  "trainers", "maps", "events", "regions", "tilesets", "scripts", "link",
  "graphics", "fonts", "constants", "overworld", "species_sprites",
  "heights", "field", "menus", "intro", "models",
}
RomExtractorGen4.STAGES = STAGES

function RomExtractorGen4.new(romPath, version, manifest, progress)
  local rom, err = NdsRom.open(romPath)
  if not rom then return nil, err end
  return setmetatable({
    rom = rom, version = version, manifest = manifest,
    progress = progress, stage = 0, wrote = {},
  }, RomExtractorGen4)
end

function RomExtractorGen4:close()
  if self.rom then self.rom:close() end
  self.rom = nil
end

function RomExtractorGen4:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, #STAGES, name, 0, 1) end
end

function RomExtractorGen4:tick(name, current, total)
  if self.progress and total > 0 then
    self.progress(self.stage - 1 + current / total, #STAGES, name, current, total)
  end
end

function RomExtractorGen4:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
  self.wrote[#self.wrote + 1] = name
end

-- An archive, parsed once and remembered: land_data alone is 16 MB and three
-- stages want it.
function RomExtractorGen4:archive(key)
  self._archives = self._archives or {}
  if self._archives[key] then return self._archives[key] end
  local path = PATH[key]
  if not path then return nil, ("no cartridge path named %q"):format(tostring(key)) end
  local bytes, readErr = self.rom:read(path)
  if not bytes then return nil, readErr end
  local arc, parseErr = Narc.parse(bytes)
  if not arc then return nil, ("%s: %s"):format(path, tostring(parseErr)) end
  self._archives[key] = arc
  return arc
end

-- The same, for an archive named by its cartridge path rather than by a key
-- in PATH.  The graphics stage walks a table of paths, so keying every one of
-- them in PATH would be a second list to keep in step with the first.
function RomExtractorGen4:archiveAt(path)
  self._archives = self._archives or {}
  if self._archives[path] then return self._archives[path] end
  local bytes = self.rom:read(path)
  if not bytes then return nil end
  local arc = Narc.parse(bytes)
  if not arc then return nil end
  self._archives[path] = arc
  return arc
end

function RomExtractorGen4:bank(n)
  self._banks = self._banks or {}
  if self._banks[n] then return self._banks[n] end
  local arc = self:archive("text")
  if not arc then return nil end
  local b = Gen4Text.bank(arc:get(n))
  self._banks[n] = b
  return b
end

function RomExtractorGen4:string(bankId, index)
  local b = self:bank(bankId)
  if not b or index == nil or index >= b.count then return nil end
  return Gen4Text.render(Gen4Text.codes(b, index))
end

-- ---------------------------------------------------------------------------
-- Stages
-- ---------------------------------------------------------------------------

-- Every bank, flattened.  This is the biggest single table the cache holds --
-- 46,053 strings -- and it is written whole rather than per-consumer, because
-- a script's `message` names a bank and an entry and nothing else knows in
-- advance which of the 724 banks a given map will reach for.
function RomExtractorGen4:extractText()
  self:beginStage("text")
  local arc = assert(self:archive("text"))
  local out = {}
  for i = 0, arc.count - 1 do
    local b = Gen4Text.bank(arc:get(i))
    if b then
      local bank = {}
      for j = 0, b.count - 1 do
        bank[j] = Gen4Text.render(Gen4Text.codes(b, j))
      end
      out[i] = bank
    end
    self:tick("text", i + 1, arc.count)
  end
  self:write("gen4_text", out)

  -- ...and the same strings again, flat, under the names the ENGINE looks them
  -- up by.  `data.text` is a map of label to string in every other generation,
  -- because Gen 1-3 address a string by one id; Gen 4 needs a bank and an
  -- index, so the label carries both.  Gen4Text.label owns the spelling, so
  -- the writer here and whatever lowers a `message` command cannot disagree.
  --
  -- Walked with pairs, NOT with a length operator: a bank is keyed from ZERO,
  -- and `#bank` on a zero-based table is nil-terminated at the first index it
  -- checks -- which for most banks is zero, so a length walk would write an
  -- empty table and report success.
  local flat, strings = {}, 0
  for bank, decoded in pairs(out) do
    for index, value in pairs(decoded) do
      flat[Gen4Text.label(bank, index)] = value
      strings = strings + 1
    end
  end
  self:write("text", flat)

  -- Required by Data.lua and read by nothing.  Gen 1 and Gen 2 keep a pointer
  -- table beside their text; Gen 4 has no equivalent, and an empty table is
  -- the honest answer -- inventing entries to fill it would put names in the
  -- cache that resolve to nothing.
  self:write("text_pointers", {})
  self.textReport = { banks = arc.count, strings = strings }

  return out
end

function RomExtractorGen4:extractSpecies()
  self:beginStage("species")
  local personal = assert(self:archive("personal"))
  local learn = assert(self:archive("learnsets"))
  local evo = assert(self:archive("evolutions"))
  local names = self:bank(BANK.species)
  local out = Gen4Species.all(personal, names, Gen4Text)
  for id, s in pairs(out) do
    s.learnset = Gen4Species.parseLearnset(learn:get(id))
    s.evolutions = Gen4Species.parseEvolutions(evo:get(id))
    s.dexEntry = self:string(BANK.dexEntry, id)
  end
  -- Kept, because the sprite stage stamps picture paths onto these very
  -- rows and rewrites the module.  Only that stage knows which pictures
  -- actually decoded, and a species whose art failed must not be handed a
  -- path to a file that is not there.
  self._pokemon = out
  self:write("pokemon", out)
  return out
end

function RomExtractorGen4:extractMoves()
  self:beginStage("moves")
  local out = Gen4Moves.all(assert(self:archive("moves")), self:bank(BANK.move), Gen4Text)
  for id, m in pairs(out) do m.description = self:string(BANK.moveDescription, id) end
  self:write("moves", out)
  return out
end

function RomExtractorGen4:extractItems()
  self:beginStage("items")
  local out = Gen4Items.all(assert(self:archive("items")), self:bank(BANK.item), Gen4Text)
  for id, it in pairs(out) do it.description = self:string(BANK.itemDescription, id) end
  self:write("items", out)
  return out
end

function RomExtractorGen4:extractEncounters()
  self:beginStage("encounters")
  local out = Gen4Encounters.all(assert(self:archive("encounters")))
  self:write("encounters", out)
  return out
end

-- THE FIELD CALLED `sprite` IS NOT THE CLASS, AND IS NOT ANYTHING.
--
-- A trdata header is { u8 monDataType, u8 trainerType, u8 sprite, u8 partySize,
-- u16 items[4], u32 aiMask, u32 battleType }, and the obvious reading is that
-- `sprite` says which trainer picture to draw.  Measured across all 928
-- trainers: `sprite` is ZERO for every single one, and `trainerType` is what
-- carries the class -- 102 distinct values in 0..102, against a 105-entry class
-- list.  The game agrees: TRDATA_CLASS reads `trainerType`.
--
-- Cross-checked against the overworld art, which is a table this stage does not
-- own: of the 63 classes that appear on a map, 60 are drawn as EXACTLY ONE
-- overworld sprite, and the three that are not -- `belle_and_pa`,
-- `double_team`, `young_couple` -- are pair classes fought by two visible
-- people.  A wrong join would not produce that.
function RomExtractorGen4:extractTrainers()
  self:beginStage("trainers")
  local out = Gen4Trainers.all(assert(self:archive("trainerData")),
                               assert(self:archive("trainerParty")),
                               self:bank(BANK.trainer), Gen4Text)
  local classes = self:bank(BANK.trainerClass)
  local zeroSprites, total = 0, 0
  for _, trainer in pairs(out) do
    total = total + 1
    if (trainer.sprite or 0) == 0 then zeroSprites = zeroSprites + 1 end
    -- Named `class` because that is what it is.  `trainerType` is kept so
    -- nothing that already reads it breaks.
    trainer.class = trainer.trainerType
    if classes and trainer.class and trainer.class < classes.count then
      trainer.className = Gen4Text.render(Gen4Text.codes(classes, trainer.class))
    end
  end
  self._trainers = out
  self.trainerReport = { trainers = total, zeroSprites = zeroSprites }
  self:write("trainers", out)
  return out
end

-- Headers, matrices and the permission grids.  The 3D meshes are NOT written:
-- they are the larger half of land_data and nothing renders them yet, so
-- putting 16 MB of NSBMD in the cache would cost every player disk for
-- something no code reads.
function RomExtractorGen4:extractMaps()
  self:beginStage("maps")
  local matrices = assert(self:archive("matrices"))
  local land = assert(self:archive("land"))
  local names = Gen4Maps.mapNames(assert(self.rom:read(PATH.mapNames)))
  local nameCount = 0
  for _ in pairs(names) do nameCount = nameCount + 1 end

  local limits = {
    areaData = assert(self:archive("areaData")).count,
    matrix = matrices.count,
    scripts = assert(self:archive("scripts")).count,
    messages = assert(self:archive("text")).count,
    encounters = assert(self:archive("encounters")).count,
    events = assert(self:archive("events")).count,
    names = nameCount,
  }
  local arm9 = assert(self.rom:arm9())
  local at, count = Gen4MapHeaders.find(arm9, limits)
  if not at then return nil, "map header table not found in the ARM9" end

  local headers = Gen4MapHeaders.all(arm9, at, count)
  for id, h in pairs(headers) do
    h.internalName = names[id]
    h.label = self:string(BANK.mapLabel, h.labelText)
  end
  -- Kept for the field stage, which has to turn a header id from the ARM9
  -- into the map name this cache uses.
  self._mapHeaders = headers
  local headerCount = 0
  for id in pairs(headers) do
    if id + 1 > headerCount then headerCount = id + 1 end
  end
  self._mapHeaderCount = headerCount
  self:write("gen4_map_headers", headers)

  local outMatrices = {}
  for i = 0, matrices.count - 1 do
    outMatrices[i] = Gen4Maps.matrix(matrices:get(i))
    self:tick("maps", i + 1, matrices.count)
  end
  self:write("gen4_map_matrices", outMatrices)

  -- Permissions as one binary string per chunk rather than 1,024 numbers:
  -- the same choice Gen 3's map grids make, and for the same reason -- a
  -- 666-entry table of thousand-element arrays is slow to load and enormous
  -- on disk, while a string is neither.
  local perms, objects = {}, {}
  for i = 0, land.count - 1 do
    local chunk = Gen4Maps.land(land:get(i))
    if chunk then
      perms[i] = chunk.permissions
      local o = Gen4Maps.objects(chunk)
      if #o > 0 then objects[i] = o end
    end
  end
  self:write("gen4_map_permissions", perms)
  self:write("gen4_map_objects", objects)

  -- GRIDS ARE SHARED, MAPS ARE NOT.  Several headers name the same matrix --
  -- every building in Jubilife sits on the overworld's -- so the grid is
  -- built once per MATRIX and each map id points at it, which is the same
  -- split Gen 3 makes between map_layouts and the map defs that reference
  -- them.
  --
  -- This is not a tidiness argument.  Building a def per header instead took
  -- the whole extraction from 3.9 seconds to 22, because the 30x30 overworld
  -- is 921,600 cells and it was being re-encoded once for every building that
  -- stands on it.
  local chunkCache = {}
  local function chunkFor(id)
    if not id or id >= land.count then return nil end
    if chunkCache[id] == nil then chunkCache[id] = Gen4Maps.land(land:get(id)) or false end
    return chunkCache[id] or nil
  end

  local layouts, layoutCount = {}, 0
  for i = 0, matrices.count - 1 do
    local m = Gen4Maps.matrix(matrices:get(i))
    local def = m and Gen4Maps.mapDef(m, chunkFor)
    if def then
      def.name = m.name
      layouts[i] = def
      layoutCount = layoutCount + 1
    end
    self:tick("maps", i + 1, matrices.count)
  end
  self:write("map_layouts", layouts)

  -- A GEN 4 OVERWORLD MAP IS A REGION OF A SHARED GRID, and that is the
  -- structural break the rest of this has to absorb.  84 headers name matrix
  -- 0 -- the 960x960 Sinnoh overworld -- and each is a piece of it, not a grid
  -- of its own.  The matrix's per-cell header array says which piece, so each
  -- map is cut out of the layout and given a grid it actually owns, which is
  -- the Gen 1-3 shape everything downstream already understands.
  --
  -- Only two matrices carry that array; for the other 287 the matrix IS the
  -- map and the whole layout is the grid.  Cutting is also SMALLER, not
  -- larger: the overworld's regions total 0.34 MB against the layout's 1.76,
  -- because header 0 owns 731 of the 900 chunks -- ocean, border, the space
  -- between routes -- and is not a map.
  local extents = {}
  for i = 0, matrices.count - 1 do
    local m = Gen4Maps.matrix(matrices:get(i))
    local e = m and Gen4Maps.extents(m)
    if e then extents[i] = e end
  end

  -- How many headers each matrix serves, so a shared grid is never inlined
  -- once per header that looks at it.
  local usersOf = {}
  for _, h in pairs(headers) do
    usersOf[h.matrix] = (usersOf[h.matrix] or 0) + 1
  end

  local defs, built, cropped, inlined = {}, 0, 0, 0
  for id, h in pairs(headers) do
    local mapId = names[id]
    local layout = layouts[h.matrix]
    if mapId and layout then
      local grid, region = layout, nil
      local byMatrix = extents[h.matrix]
      if byMatrix and byMatrix[id] then
        region = byMatrix[id]
        local cut = Gen4Maps.crop(layout, region.x, region.y,
                                  region.width, region.height)
        if cut then grid = cut; cropped = cropped + 1 end
      end

      -- ONLY INLINE A GRID THIS MAP OWNS.  A cropped region is its own; a
      -- matrix no other header looks at is its own.  A SHARED matrix is not,
      -- and inlining it puts the same grid in the cache once per header --
      -- the twelve headers that name the overworld without claiming chunks in
      -- it were carrying 1.76 MB each, which is 21 MB of one grid repeated.
      -- Those reference `layout` instead and read gen4_map_layouts.
      local owns = (region ~= nil) or (usersOf[h.matrix] == 1)
      if owns then inlined = inlined + 1 end

      defs[mapId] = {
        id = mapId,
        header = id,
        layout = h.matrix,
        label = self:string(BANK.mapLabel, h.labelText),
        width = grid.width,
        height = grid.height,
        blocks = owns and grid.blocks or nil,
        borderBlock = grid.borderBlock,
        blockPx = 16,
        generation = 4,
        -- Every Gen 4 map names the same stand-in, because Gen 4 has no
        -- tileset in the Gen 1-3 sense and MapLoader will not build a map
        -- without one.  See extractTilesets.
        tileset = Gen4Tileset.ID,
        -- Where this map sits in the layout it was cut from.  Zero for a map
        -- that IS its matrix; the region's corner otherwise.  Event
        -- coordinates below are already map-local, so this is only needed to
        -- put a map back on the shared grid.
        originX = grid.originX or 0,
        originY = grid.originY or 0,
        -- A region is the bounding box of the chunks a header owns, so four
        -- of the sixty-six are not solid rectangles; flagged rather than
        -- silently squared off.
        regionSolid = region and region.solid or nil,
        encounters = h.encounters,
        events = h.events,
        allowBike = h.allowBike,
        allowRunning = h.allowRunning,
        allowEscapeRope = h.allowEscapeRope,
        allowFly = h.allowFly,
        weather = h.weather,
        dayMusic = h.dayMusic,
        nightMusic = h.nightMusic,
      }
      built = built + 1
    end
  end
  self._mapDefs = defs
  self.mapDefReport = { maps = built, layouts = layoutCount, headers = count,
                        cropped = cropped, inlined = inlined }
  return headers, names
end

-- Attach each map's events to its def, in map-local coordinates.
--
-- The events are stored per EVENT ARCHIVE and their coordinates are measured
-- from the MATRIX's corner, not the map's -- which is consistent, because on
-- the overworld the matrix is the only thing all 84 maps share.  Every one of
-- the 5,636 events in the cartridge falls inside its own map's matrix grid,
-- which is what says the coordinates are matrix-global rather than local.
--
-- Subtracting the region origin makes them local, so a Gen 4 map's objects sit
-- at the same kind of coordinates a Gen 1-3 map's do and nothing downstream
-- needs to know the difference.
--
-- GEN 4 IS 3D: X and Z are the two HORIZONTAL axes and Y is height.  So the
-- engine's `y` takes the cartridge's `z`, and the cartridge's `y` becomes
-- elevation.  Reading them in the order they appear puts every object on the
-- map's top edge.
function RomExtractorGen4:extractRegions(events, names)
  self:beginStage("regions")
  local defs = self._mapDefs or {}

  local counts = { objects = 0, warps = 0, signs = 0, coordEvents = 0 }
  local outside, dangling = 0, 0

  local byHeader = {}
  for _, def in pairs(defs) do byHeader[def.header] = def end

  for header, def in pairs(byHeader) do
    local ev = events and events[def.events]
    local ox, oy = def.originX or 0, def.originY or 0
    local objects, warps, signs, coords = {}, {}, {}, {}

    -- An event outside its own map's box is not dropped.  Four regions are
    -- L-shaped and their bounding box does not cover every chunk they own, so
    -- a strict bounds test would silently delete real NPCs; the count is
    -- reported instead.
    local function localX(v) return v - ox end
    local function localY(v) return v - oy end
    local function note(x, y)
      if x < 0 or y < 0 or x >= def.width or y >= def.height then
        outside = outside + 1
      end
    end

    for i, o in ipairs(ev and ev.objectEvents or {}) do
      local x, y = localX(o.x), localY(o.z)
      note(x, y)
      -- The key into `data.sprites`, resolved THROUGH the overlay-5 table and
      -- never straight off the id -- see Gen4ObjectGfx for what that cost.
      -- `noSprite` is a reason, not a failure: a signpost or a VAR_ slot has
      -- no billboard of its own and must not read as a broken lookup.
      local spriteKey, _, noSprite = self:spriteFor(o.graphics)
      local kind, band, entry, member = Gen4ScriptBands.classify(o.script)
      objects[#objects + 1] = {
        index = i, localId = o.localId,
        graphicsId = o.graphics,
        sprite = spriteKey,
        spriteName = Gen4ObjectGfx.name(o.graphics),
        noSprite = noSprite,
        -- What the script id MEANS, rather than only what it is.
        scriptKind = kind,
        -- ...and, for the 417 trainers, WHICH TRAINER.  The id comes from the
        -- band the same way the cartridge derives it, and the class it lands on
        -- agrees with the art this object wears.
        trainer = (function()
          local id, side = Gen4ScriptBands.trainerId(o.script or -1)
          if not id then return nil end
          local record = self._trainers and self._trainers[id]
          return {
            id = id,
            class = record and record.class,
            className = record and record.className,
            name = record and record.name,
            partySize = record and record.partySize,
            -- Which half of a double battle this object is, from the BAND:
            -- 3000 and 5000 reach the same file and only the band tells them
            -- apart.
            battler = side,
          }
        end)(),
        -- ...and, for the 329 item balls, WHICH ITEM.
        pickup = (function()
          local visible, hidden = self:pickupTables()
          return Gen4Pickups.resolve(o.script, visible, hidden)
        end)(),
        scriptBand = band,
        scriptEntry = (kind == "band" or kind == "map") and entry or nil,
        scriptFile = member,
        movementType = o.movementType,
        movementRangeX = o.rangeX, movementRangeY = o.rangeZ,
        trainerType = o.trainerType,
        flag = o.hiddenFlag,
        script = o.script,
        direction = o.direction,
        x = x, y = y,
        elevation = o.y,
      }
      counts.objects = counts.objects + 1
    end

    for i, w in ipairs(ev and ev.warpEvents or {}) do
      local x, y = localX(w.x), localY(w.z)
      note(x, y)
      -- The destination is a HEADER id; the engine keys maps by their internal
      -- name, so it is resolved here rather than left for every consumer to
      -- resolve differently.  Six warps in the cartridge go nowhere.
      local destination = names and names[w.destination]
      if not destination and w.destination ~= Gen4Events.NO_DESTINATION then
        dangling = dangling + 1
      end
      warps[#warps + 1] = {
        index = i, x = x, y = y,
        destMap = destination,
        destHeader = w.destination,
        destWarp = w.anchor,
      }
      counts.warps = counts.warps + 1
    end

    for i, b in ipairs(ev and ev.bgEvents or {}) do
      local x, y = localX(b.x), localY(b.z)
      note(x, y)
      local kind, band, entry, file = Gen4ScriptBands.classify(b.script)
      local visible, hidden = self:pickupTables()
      signs[#signs + 1] = {
        index = i, x = x, y = y,
        script = b.script, kind = b.kind,
        facing = b.playerFacing, elevation = b.y,
        scriptKind = kind, scriptBand = band,
        scriptEntry = (kind == "band" or kind == "map") and entry or nil,
        scriptFile = file,
        -- 262 of these are a hidden item, and `range` is how close you have to
        -- stand for the Itemfinder to sing.
        pickup = Gen4Pickups.resolve(b.script, visible, hidden),
      }
      counts.signs = counts.signs + 1
    end

    for i, c in ipairs(ev and ev.coordEvents or {}) do
      local x, y = localX(c.x), localY(c.z)
      note(x, y)
      coords[#coords + 1] = {
        index = i, x = x, y = y,
        width = c.width, height = c.length,
        script = c.script, value = c.value, var = c.variable,
        elevation = c.y,
      }
      counts.coordEvents = counts.coordEvents + 1
    end

    def.objects = objects
    def.warps = warps
    def.signs = signs
    def.coordEvents = coords
  end

  self:write("maps", defs)
  self.regionReport = {
    objects = counts.objects, warps = counts.warps,
    signs = counts.signs, coordEvents = counts.coordEvents,
    outside = outside, dangling = dangling,
  }
  return defs
end

function RomExtractorGen4:extractEvents()
  self:beginStage("events")
  local out = Gen4Events.all(assert(self:archive("events")))
  self:write("gen4_events", out)
  return out
end

-- The script pool, FLAT and labelled "M<member>/S<offset>" -- the same shape
-- Gen 2 and Gen 3 use, because Gen4ScriptVM.compile resolves a branch by
-- looking its label up in one table and a nested pool would make every branch
-- carry its member separately.  The label spelling comes from
-- Gen4ScriptVM.label so the extractor and the VM cannot drift apart.
--
-- Lowering happens at LOAD time in Gen4ScriptVM, not here, so that a lowering
-- fix does not require re-importing the cartridge.
function RomExtractorGen4:extractScripts()
  self:beginStage("scripts")
  local arc = assert(self:archive("scripts"))
  local scripts, entries = {}, {}
  for m = 0, arc.count - 1 do
    local bytes = arc:get(m)
    if bytes and #bytes >= 6 then
      -- Follow jumps as well as entry points: a block reached only by a
      -- `goto` is still a block the runner will need.
      local ordered = Gen4Script.entries(bytes)
      local queue, seen = {}, {}
      for _, at in ipairs(ordered) do
        if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
      end
      local i = 1
      while i <= #queue do
        local at = queue[i]; i = i + 1
        local instructions, stopped = Gen4Script.decode(bytes, at)
        scripts[Gen4ScriptVM.label(m, at)] =
          { instructions = instructions, stopped = stopped }
        for _, ins in ipairs(instructions) do
          local t = ins.target
          if t and t >= 1 and t <= #bytes and not seen[t] then
            seen[t] = true; queue[#queue + 1] = t
          end
        end
      end
      -- The ENTRY POINTS in order: a script id in an event is an index into
      -- this list, not a byte offset, so the order is the mapping.
      local list = {}
      for k, at in ipairs(ordered) do list[k] = Gen4ScriptVM.label(m, at) end
      entries[m] = list
    end
    self:tick("scripts", m + 1, arc.count)
  end
  self._scripts, self._entries = scripts, entries
  return scripts
end

-- ---------------------------------------------------------------------------

-- The join: which script each map's objects and signs run.
--
-- A map header names a scr_seq member (`scripts`) and an events archive
-- (`events`); an object event carries a SCRIPT ID, which indexes that
-- member's entry-point list.  Nothing else connects the two, which is why
-- this stage exists at all and why it has to run after both.
--
-- MAP IDS ARE THE CARTRIDGE'S OWN INTERNAL NAMES -- "C01", "C05GYM0113",
-- "D25R0106" -- from mapname.bin, keyed by header id.  They are unique, they
-- are stable across revisions, and they are what a log line should say.  The
-- player-facing name is a different table (message bank 433) and several maps
-- share one, so it would not do as a key.
--
-- NOT EVERY SCRIPT ID IS A SCRIPT, and getting this wrong makes a working
-- link look broken.  Counting anything that did not resolve as "missing"
-- reported 2,350 failures against 1,887 successes -- more misses than hits,
-- which should never be believed without checking what the misses are.
-- Classified instead:
--
--   0                       no script
--   1 .. 1999               an entry in THIS MAP's own script member, at
--                           index id - 1
--   >= 2000                 an entry in a SHARED script file, chosen by the
--                           highest threshold the id clears
--   65535                   the "no script" sentinel, which is not a band
--
-- The bands are in Gen4ScriptBands, taken from the cartridge's own dispatcher
-- rather than guessed, and they are no longer recorded as `special`: an id in
-- a band is an ordinary entry point in a shared file, and 1,885 of the 1,920
-- land inside the file their band names.
--
-- TWO BUGS FIXED HERE AT ONCE, and the second hid behind the first.
--
--   * `specials` was keyed by an object's localId AND by a sign's index in the
--     same table, so a sign with index 1 silently replaced the object with
--     localId 1.  228 of 2,148 entries -- better than one in ten -- were being
--     overwritten, and nothing counted them because the count was taken before
--     the write.  Objects and signs now have a table each.
--   * Nothing looked at what the ids meant, so nothing noticed that the events
--     running berry-tree scripts were being drawn as Team Galactic's Mars.
--     Classifying them is what exposed the graphics indirection in
--     Gen4ObjectGfx.
function RomExtractorGen4:linkScripts(headers, events, names)
  self:beginStage("link")
  local maps = {}
  local linked, special, none = 0, 0, 0
  for id, h in pairs(headers or {}) do
    local mapId = names and names[id]
    local ev = events and events[h.events]
    local list = self._entries and self._entries[h.scripts]
    if mapId and ev and list then
      local objects, signs = {}, {}
      -- A TABLE EACH, because a localId and a sign index are both small
      -- integers and sharing one table makes them collide.
      local shared = { objects = {}, signs = {} }
      local function place(into, sharedInto, key, scriptId)
        if not scriptId or scriptId == 0 then none = none + 1; return end
        local kind, band, entry, member = Gen4ScriptBands.classify(scriptId)
        if kind == "sentinel" then none = none + 1; return end
        if kind == "map" then
          local label = list[scriptId]
          if label then into[key] = label; linked = linked + 1; return end
        end
        sharedInto[key] = {
          id = scriptId, band = band, entry = entry, file = member,
          kind = kind,
        }
        special = special + 1
      end
      for _, npc in ipairs(ev.objectEvents or {}) do
        place(objects, shared.objects, npc.localId, npc.script)
      end
      for i, sign in ipairs(ev.bgEvents or {}) do
        place(signs, shared.signs, i, sign.script)
      end
      if next(objects) or next(signs) or next(shared.objects) or next(shared.signs) then
        maps[mapId] = {
          objects = objects, signs = signs, header = id,
          -- Named `shared` rather than `specials`: they are entries in shared
          -- script files, which is a fact about them rather than an admission.
          shared = (next(shared.objects) or next(shared.signs)) and shared or nil,
        }
      end
    end
  end
  self:write("map_scripts", {
    source = "RomExtractorGen4",
    scripts = self._scripts or {},
    maps = maps,
  })
  self.linkReport = { linked = linked, special = special, none = none, maps = 0 }
  for _ in pairs(maps) do self.linkReport.maps = self.linkReport.maps + 1 end
  return maps
end

-- Every stage, in order.  Returns the list of tables written, so the caller
-- can record what a cache contains rather than assuming.
-- ---------------------------------------------------------------------------
-- Graphics
-- ---------------------------------------------------------------------------

-- Compose one picture from members of an open archive.
--
-- `job` names the three parts by member index.  A job with no tilemap is a
-- SHEET rather than a screen -- a set of pieces the game arranges through OAM
-- -- and is laid out at `tilesWide` so it can at least be looked at.  That
-- layout is provisional and is recorded as such in the index; the pixels are
-- right, the arrangement is a placeholder until the NCER cell banks are read.
function RomExtractorGen4:composeJob(arc, job)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end

  local sheet = Gen4Graphics.tiles(member(job.tiles))
  local palette = Gen4Graphics.palette(member(job.palette))
  if not (sheet and palette) then return nil end

  local map
  if job.tilemap then map = Gen4Graphics.tilemap(member(job.tilemap)) end
  if not map then
    local wide = job.tilesWide or 8
    local cells = {}
    for i = 0, sheet.count - 1 do
      cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 }
    end
    map = {
      width = wide * 8,
      height = math.ceil(sheet.count / wide) * 8,
      cells = cells,
    }
  end

  return Gen4Graphics.compose(map, sheet, palette)
end

-- Assemble a sheet through its cell bank, returning one image per cell.
--
-- This is what a cell bank is FOR.  A sprite sheet records no width -- its
-- NCGR says 0xFFFF x 0xFFFF -- because the shape lives in the bank: a list of
-- rectangles at signed offsets from the sprite's centre.  Laying the sheet out
-- at a guessed width produces the right pixels in the wrong order, which looks
-- like a decode bug and is not one.
--
-- Returns nil when there is no bank, so the caller can fall back to the width
-- guess and mark the result provisional.
function RomExtractorGen4:assembleCells(arc, job, sheet, palette)
  if not (job.cell and sheet and palette) then return nil end
  local raw = arc:get(job.cell)
  if not raw then return nil end
  if Gen4Graphics.isCompressed(raw) then raw = Gen4Graphics.decompress(raw) end

  local bank = Gen4Cells.parse(raw, Gen4Graphics)
  if not bank or bank.count == 0 then return nil end

  local out = {}
  for i, cell in ipairs(bank.cells) do
    local image = Gen4Cells.assemble(cell, sheet, palette, bank, Gen4Graphics)
    if image then
      -- A one-cell bank is the sprite itself and keeps the plain name; a bank
      -- with several is a set of frames and each one is numbered.
      out[#out + 1] = {
        suffix = (bank.count > 1) and ("_%02d"):format(i - 1) or "",
        image = image,
        cellIndex = i - 1,
      }
    end
  end
  if #out == 0 then return nil end
  return out, bank
end

-- Decode a job's sheet and palette once, for the callers that need them before
-- deciding between cell assembly and a flat layout.
function RomExtractorGen4:partsFor(arc, job)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end
  return Gen4Graphics.tiles(member(job.tiles)),
         Gen4Graphics.palette(member(job.palette))
end

-- One pixel of a composed picture, as the 0-1 triple LOVE draws with.  A
-- composed image is RGBA8 in row order, so this is arithmetic rather than a
-- decode.
local function pixelAt(image, x, y)
  if not image or x < 0 or y < 0 or x >= image.width or y >= image.height then
    return nil
  end
  local at = (y * image.width + x) * 4
  local r, g, b = image.rgba:byte(at + 1, at + 3)
  if not b then return nil end
  return { r / 255, g / 255, b / 255 }
end

-- WHERE THE ARTWORK IS INSIDE A PICTURE: the tightest box that holds every
-- pixel which is neither transparent nor the sheet's own background.
--
-- Both cases occur in the title archive and only one of them is transparency.
-- The logo is on a transparent sheet, so alpha finds it; the copyright lines
-- are white on an OPAQUE BLACK 256x256 sheet, where alpha finds the whole
-- sheet and says nothing.  Treating "fully transparent OR exactly the
-- top-left pixel's colour" as background covers both without needing to know
-- which kind a given sheet is.
local function contentBox(image)
  if not image or image.width == 0 or image.height == 0 then return nil end
  local rgba = image.rgba
  local br, bg, bb, ba = rgba:byte(1, 4)
  local minX, minY, maxX, maxY = image.width, image.height, -1, -1
  for y = 0, image.height - 1 do
    local row = y * image.width * 4
    for x = 0, image.width - 1 do
      local at = row + x * 4
      local r, g, b, a = rgba:byte(at + 1, at + 4)
      local background = (a == 0) or (a == ba and r == br and g == bg and b == bb)
      if not background then
        if x < minX then minX = x end
        if y < minY then minY = y end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
      end
    end
  end
  if maxX < 0 then return nil end
  return { x = minX, y = minY, w = maxX - minX + 1, h = maxY - minY + 1 }
end

-- Stack same-sized pictures into one column, which is the shape both frame
-- records want: a fixed cell height, one frame per cell, in order.
--
-- Every row is asserted to be the stated size rather than padded to it.  A
-- frame that came out the wrong shape would otherwise be stacked anyway and
-- read back at the wrong offset, which draws SOMETHING for every frame and the
-- right thing for none.
local function stackImages(cells, width, height)
  if #cells == 0 then return nil end
  local rows = {}
  for _, cell in ipairs(cells) do
    local image = cell.image
    if image.width ~= width or image.height ~= height then return nil end
    rows[#rows + 1] = image.rgba
  end
  return {
    width = width, height = height * #cells,
    rgba = table.concat(rows),
  }
end

-- One archive member decoded as a palette, decompressed if it needs to be.
function RomExtractorGen4:paletteMember(arc, index)
  local bytes = arc and index and arc:get(index)
  if not bytes then return nil end
  if Gen4Graphics.isCompressed(bytes) then
    bytes = Gen4Graphics.decompress(bytes)
  end
  return Gen4Graphics.palette(bytes)
end

-- Compose tiles + tilemap against a palette this caller built itself.
--
-- Separate from composeJob because these archives carry no name table and so
-- no job: the indices come from the cartridge's own loader, and the palette is
-- often not one member but two loads merged, or one row replicated.  Handing
-- composeJob a member index for the palette could not express either.
function RomExtractorGen4:composeWith(arc, tilesIndex, tilemapIndex, palette)
  local function member(i)
    if i == nil then return nil end
    local bytes = arc:get(i)
    if not bytes then return nil end
    if Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end
    return bytes
  end
  local sheet = Gen4Graphics.tiles(member(tilesIndex))
  local map = Gen4Graphics.tilemap(member(tilemapIndex))
  if not (sheet and map and palette) then return nil end
  return Gen4Graphics.compose(map, sheet, palette)
end

-- Save a composed picture, and return what the index should record about it.
function RomExtractorGen4:saveImage(relative, image, extra)
  if not image then return nil end
  local data = ImageWriter.fromRGBA8(image.width, image.height, image.rgba)
  if not data then return nil end
  local path = "assets/generated/gen4/" .. relative .. ".png"
  ImageWriter.save(data, path)
  local entry = { path = path, width = image.width, height = image.height }
  if extra then
    for k, v in pairs(extra) do entry[k] = v end
  end
  return entry
end

-- Battles, menus, the summary pages and the title sequence.
--
-- This stage exists because none of the above could previously be SEEN.  The
-- decoders were correct and the archives were readable, but a Gen 4 screen is
-- never one member: it is a tile sheet, a palette and a tilemap that sit at
-- unrelated indices, and until they are paired correctly there is no picture,
-- only three files.
--
-- WHAT PAIRS THEM IS THE NAME, which is why Gen4Archives comes first.  Where
-- the index is arithmetic instead of a name -- the battle backgrounds, whose
-- archive has no name table at all -- Gen4Battle carries the arithmetic and it
-- is checked against the cartridge before it is used: every member this stage
-- reaches for is confirmed to be the kind of file it is supposed to be, and a
-- background whose parts are not all present is skipped and counted rather
-- than composed from whatever happened to be at that index.
function RomExtractorGen4:extractGraphics()
  self:beginStage("graphics")

  local index = {
    backgrounds = {}, terrain = {}, battleObjects = {}, screens = {},
    skipped = {},
  }

  -- Battle backgrounds: 23 backgrounds x 3 times of day over one shared
  -- tilemap.  The tilemap is 512 x 256 because the background scrolls; the
  -- visible screen is the left 256 x 192 of it.
  local bgArc = self:archive("battleBg")
  if bgArc then
    local total = Gen4Battle.BACKGROUND_COUNT * #Gen4Battle.TIMES
    local done = 0
    for i = 0, Gen4Battle.BACKGROUND_COUNT - 1 do
      for t = 0, #Gen4Battle.TIMES - 1 do
        local spec = Gen4Battle.background(i, t)
        local image = spec and self:composeJob(bgArc, {
          tiles = spec.tiles, palette = spec.palette, tilemap = spec.tilemap,
        })
        local name = ("%s_%s"):format(spec.name, spec.time)
        local entry = self:saveImage("battle/background/" .. name, image, {
          background = i, time = spec.time, fadeTo = spec.fadeTo,
        })
        if entry then
          index.backgrounds[name] = entry
        else
          index.skipped[#index.skipped + 1] = "battle/background/" .. name
        end
        done = done + 1
        self:tick("graphics", done, total + 200)
      end
    end
  end

  -- Terrain platforms: the ground each side stands on, chosen from the tile
  -- the player was walking on rather than from the map.  Two sides per
  -- terrain, and three palettes per terrain outdoors -- indoor and special
  -- terrains list one palette three times, so those are written once.
  local objArc = self:archive("battleObj")
  if objArc then
    for i = 0, Gen4Battle.TERRAIN_COUNT - 1 do
      for _, side in ipairs({ "player", "enemy" }) do
        local times = Gen4Battle.terrain(i, side, 0).timeless
          and { 0 } or { 0, 1, 2 }
        for _, t in ipairs(times) do
          local spec = Gen4Battle.terrain(i, side, t)
          local tiles = Gen4Archives.find(PATH.battleObj, spec.tiles)
          local palette = Gen4Archives.find(PATH.battleObj, spec.palette)
          local name = spec.timeless
            and ("%s_%s"):format(spec.name, side)
            or ("%s_%s_%s"):format(spec.name, side, Gen4Battle.TIMES[t + 1])

          -- Every terrain shares one bank per side -- terrain/player_cell and
          -- terrain/enemy_cell -- which is exactly why all 24 platform sheets
          -- are the same 128 tiles.  The bank turns those 128 tiles into the
          -- 256x32 player platform and the 128x64 enemy one.
          local job = {
            tiles = tiles, palette = palette,
            cell = Gen4Archives.find(PATH.battleObj, "terrain/" .. side .. "_cell"),
            tilesWide = Gen4Battle.PLATFORM_TILES_WIDE,
          }
          local sheet, pal = self:partsFor(objArc, job)
          local frames = self:assembleCells(objArc, job, sheet, pal)
          local image = frames and frames[1] and frames[1].image
            or (tiles and palette and self:composeJob(objArc, job))

          local entry = self:saveImage("battle/terrain/" .. name, image, {
            terrain = i, side = side, art = spec.art,
            provisionalLayout = (frames == nil) or nil,
          })
          if entry then
            index.terrain[name] = entry
          else
            index.skipped[#index.skipped + 1] = "battle/terrain/" .. name
          end
        end
      end
    end

    -- Healthboxes, type icons, the interface pieces and the trainer backs.
    -- These are all OAM sheets, so the same caveat applies to their layout.
    local names = Gen4Archives.names(PATH.battleObj)
    local groups = Gen4Archives.groups(PATH.battleObj)
    if names and groups then
      -- One palette per family, taken from the family's own `shared` member
      -- where it has one.
      local familyPalette = {}
      for _, group in ipairs(groups) do
        local family = Gen4Battle.familyFor(group.base)
        if family and group.NCLR and not familyPalette[family.prefix] then
          familyPalette[family.prefix] = group.NCLR
        end
      end
      for _, group in ipairs(groups) do
        local family = Gen4Battle.familyFor(group.base)
        if family and family.prefix ~= "terrain/" and group.NCGR then
          local palette = group.NCLR or familyPalette[family.prefix]
          local bankAt, bankName, bankHow =
            Gen4Archives.cellBank(PATH.battleObj, group.base)
          local job = {
            tiles = group.NCGR, palette = palette,
            cell = bankAt, tilesWide = family.tilesWide,
          }
          local name = group.base:gsub("/", "_")
          -- `local a, b = x and f()` keeps only f()'s FIRST return value, so
          -- this cannot be folded into the guard -- the palette would always
          -- arrive nil and every sheet would silently take the fallback path.
          local sheet, pal
          if palette then sheet, pal = self:partsFor(objArc, job) end
          local frames = sheet and pal and self:assembleCells(objArc, job, sheet, pal)
          if frames then
            for _, frame in ipairs(frames) do
              local entry = self:saveImage(
                "battle/" .. name .. frame.suffix, frame.image, {
                  family = family.label, cellBank = bankName,
                  cellMatch = bankHow, cell = frame.cellIndex,
                })
              if entry then index.battleObjects[name .. frame.suffix] = entry end
            end
          else
            local image = palette and self:composeJob(objArc, job)
            local entry = self:saveImage("battle/" .. name, image, {
              family = family.label, provisionalLayout = true,
            })
            if entry then index.battleObjects[name] = entry end
          end
        end
      end
    end
  end

  -- Everything the player looks at outside a battle: the title sequence, the
  -- start menu's icons and window frames, the summary pages, the party
  -- screen, the bag, the trainer card, the Poketch, the town map, the
  -- Pokedex, mail and the fonts.
  local plans = Gen4Screens.planAll()
  local totalJobs = 0
  for _, plan in ipairs(plans) do totalJobs = totalJobs + #plan.jobs end
  local done = 0
  for _, plan in ipairs(plans) do
    local arc = self:archiveAt(plan.archive.path)
    if arc then
      for _, job in ipairs(plan.jobs) do
        local relative = plan.archive.out .. "/" .. job.name:gsub("/", "_")
        local sheet, palette = self:partsFor(arc, job)
        local frames = self:assembleCells(arc, job, sheet, palette)
        local wrote = false

        if frames then
          -- Assembled from a cell bank: a real sprite, at its real size.
          for _, frame in ipairs(frames) do
            local entry = self:saveImage(relative .. frame.suffix, frame.image, {
              kind = job.kind,
              cellBank = job.cellFrom,
              cellMatch = job.cellMatch,
              cell = frame.cellIndex,
              borrowedPalette = job.borrowedPalette or nil,
            })
            if entry then
              index.screens[relative .. frame.suffix] = entry
              wrote = true
            end
          end
        else
          local entry = self:saveImage(relative, self:composeJob(arc, job), {
            kind = job.kind,
            -- A screen has a tilemap and is final.  A sheet with no cell bank
            -- anywhere in its archive is laid out at a width nothing in the
            -- cartridge states, and says so.
            provisionalLayout = (job.tilemap == nil) or nil,
            borrowedTiles = job.borrowedTiles or nil,
            borrowedPalette = job.borrowedPalette or nil,
          })
          if entry then
            index.screens[relative] = entry
            wrote = true
          end
        end

        if not wrote then index.skipped[#index.skipped + 1] = relative end
        done = done + 1
        self:tick("graphics", done, totalJobs)
      end
    end
  end

  index.frames = self:extractWindowFrames()

  -- Kept for the menus stage, which names the title art by role and would
  -- otherwise have to re-derive the archive member spellings.
  self._graphicsIndex = index

  self:write("gen4_graphics", index)
  return index
end

-- ---------------------------------------------------------------------------
-- The window frames
-- ---------------------------------------------------------------------------

-- pl_winframe, laid out the way the ENGINE reads a frame rather than the way
-- the generic screen planner lays out a sheet.
--
-- The planner above already writes every member of this archive as a picture,
-- at eight tiles across, which is fine for looking at and useless for drawing:
-- `src/render/Font.lua` wants a standard frame as a 24x24 cell (three tiles
-- across, in member order) and a dialogue frame as one row of eighteen.  Both
-- are the same pixels at a different stride, so this costs one more compose per
-- frame and nothing else.
--
-- WHY THIS IS WORTH A STAGE OF ITS OWN.  Font.drawBox is what every menu, every
-- choice box and every message in this engine goes through.  Give it a frames
-- record and all of them are Platinum's in one step; leave it out and each new
-- Gen 4 screen has to draw its own border, which is how twenty screens end up
-- with twenty slightly different rectangles.
function RomExtractorGen4:extractWindowFrames()
  local arc = self:archive("winframe")
  if not arc then return nil end
  local groups = Gen4Archives.groups(PATH.winframe)
  if not groups then return nil end

  local byBase = {}
  for _, group in ipairs(groups) do byBase[group.base] = group end

  local out = {}

  -- THE STANDARD FRAME, three tiles across.  Both variants go on one sheet in
  -- the order LoadStandardWindowTiles chooses between them, so a save (or a
  -- mod) can select the field one; frame 1 is the system one, which is what
  -- every menu uses.
  local cells = {}
  for _, spec in ipairs(Gen4Menus.STANDARD) do
    local group = byBase[spec.name]
    local palette = byBase[spec.palette]
    -- `standard_field` carries no palette of its own.  That is a fact about
    -- the archive, not a failure: it is drawn with the system palette, and
    -- naming the borrow here keeps it out of the generic shared-sheet
    -- guesswork above.
    if group and group.NCGR and palette and palette.NCLR then
      local image = self:composeJob(arc, {
        tiles = group.NCGR, palette = palette.NCLR,
        tilesWide = Gen4Menus.STANDARD_TILES_WIDE,
      })
      if image and image.width == 24 and image.height == 24 then
        cells[#cells + 1] = { name = spec.name, image = image }
      end
    end
  end
  if #cells > 0 then
    local sheet = stackImages(cells, 24, 24)
    local entry = sheet and self:saveImage("windows/frames", sheet, {
      count = #cells, cell = 24, tile = 8,
      order = (function()
        local names = {}
        for i, c in ipairs(cells) do names[i] = c.name end
        return table.concat(names, ",")
      end)(),
    })
    if entry then
      out.standard = {
        image = entry.path, count = #cells, cell = 24, tile = 8,
      }
    end
  end

  -- THE DIALOGUE FRAME: all twenty message boxes, each as one row of eighteen
  -- tiles, stacked.  Eighteen across is the stride Font.lua's dialogue reader
  -- already uses, so the only new thing is the row.
  local strips, fill = {}, nil
  for frame = 0, Gen4Menus.MESSAGE_BOX_COUNT - 1 do
    local group = byBase[Gen4Menus.messageBoxName(frame)]
    if group and group.NCGR and group.NCLR then
      local image = self:composeJob(arc, {
        tiles = group.NCGR, palette = group.NCLR,
        tilesWide = Gen4Menus.MESSAGE_BOX_TILES,
      })
      if image and image.height == 8 then
        strips[#strips + 1] = { name = group.base, image = image }
        -- The interior colour, read off the one tile of the eighteen that
        -- DrawMessageBoxFrame never places -- `tile + 8`, the only solid tile
        -- in the sheet.  Sampling it beats choosing a colour that looks close:
        -- it is the colour the window bitmap would have covered.
        if not fill then fill = pixelAt(image, Gen4Menus.FILL_SAMPLE_X,
                                       Gen4Menus.FILL_SAMPLE_Y) end
      end
    end
  end
  if #strips > 0 then
    local sheet = stackImages(strips, Gen4Menus.MESSAGE_BOX_TILES * 8, 8)
    local entry = sheet and self:saveImage("windows/dialogue", sheet, {
      count = #strips, tiles = Gen4Menus.MESSAGE_BOX_TILES,
    })
    if entry then
      out.dialogue = {
        image = entry.path,
        tiles = Gen4Menus.MESSAGE_BOX_TILES,
        count = #strips,
        -- Which arrangement the eighteen are in.  Font.lua's existing dialogue
        -- reader is FireRed's -- five-tile rows mirrored back down -- and this
        -- one is not, so the record says which rather than letting the reader
        -- assume.
        layout = "gen4",
        fill = fill,
      }
    end
  end

  self._winFrames = out
  return out
end

-- ---------------------------------------------------------------------------
-- Fonts
-- ---------------------------------------------------------------------------

-- The four NFGR fonts, and the per-glyph widths that text layout needs.
--
-- This is a stage of its own rather than a corner of the graphics one because
-- what it produces is not really a picture.  A font sheet is written so the
-- result can be LOOKED AT, but the thing the engine will actually consume is
-- the width table: 509 advances per font, without which every line of Gen 4
-- text is monospaced and wrong.
--
-- Colours are NOT baked in beyond the preview.  A glyph pixel is a ROLE --
-- nothing, foreground, shadow, background -- and the game picks three real
-- colours per text box at draw time.  Writing one colouring into the cache
-- would freeze menu text into battle colours.
function RomExtractorGen4:extractFonts()
  self:beginStage("fonts")

  local index = { fonts = {}, pages = {}, skipped = {} }
  local arc = self:archive("fonts")
  if not arc then
    self:write("gen4_fonts", index)
    return index
  end

  local names = Gen4Archives.names(PATH.fonts)
  for member = 0, arc.count - 1 do
    local name = names and names[member + 1]
    -- NFGR carries no magic, so it is identified by its own arithmetic: the
    -- header's offsets and counts have to account for the member's length
    -- EXACTLY.  That is a far stronger test than a four-byte tag, and it is
    -- the only one available here.
    local raw = arc:get(member)
    local font = raw and Gen4Font.parse(raw)
    if font and font.exact then
      local label = name and Gen4Archives.baseName(name) or ("font_%02d"):format(member)
      local sheet = Gen4Font.sheet(font, { columns = 32 })
      local entry = self:saveImage("font/" .. label .. "_sheet", sheet, {
        glyphs = font.numGlyphs,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        maxWidth = font.maxWidth,
        maxHeight = font.maxHeight,
        columns = 32,
        -- The sheet is a preview in one arbitrary colouring; the roles below
        -- are what a renderer should use.
        preview = true,
      })

      -- Widths as a plain array, one byte per glyph, indexed from zero the way
      -- the cartridge indexes them.  A character code reaches its glyph by
      -- subtracting one -- charcode 1 is glyph 0 -- and that is the game's own
      -- rule, not a convention this extractor invented.
      local widths = {}
      for glyph = 0, font.numGlyphs - 1 do
        widths[glyph + 1] = font.widths[glyph]
      end

      index.fonts[label] = {
        member = member,
        glyphs = font.numGlyphs,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        maxWidth = font.maxWidth,
        maxHeight = font.maxHeight,
        tilesWide = font.tilesWide,
        tilesHigh = font.tilesHigh,
        widths = widths,
        sheet = entry and entry.path or nil,
        roles = Gen4Font.ROLES,
      }

      -- The same font again, in the shape src/render/Font.lua already reads.
      -- BASE IS 1, not 0: the cartridge reaches a glyph by subtracting one
      -- from the character code, so code 1 is glyph 0.  Font.lua indexes its
      -- quads by `code - base` and its widths by `code - base + 1`, which with
      -- base 1 lands on exactly the array written above -- the two agree
      -- without either side adjusting for the other.
      index.pages[label] = {
        image = entry and entry.path or nil,
        base = 1,
        glyphsPerRow = 32,
        glyphWidth = font.pixelWidth,
        glyphHeight = font.pixelHeight,
        -- The fallback for a code the width table does not cover.  The real
        -- advances are in `widths` and Font.advanceOf prefers them.
        advance = font.maxWidth,
        widths = widths,
        -- The sheet carries its own two tones, so it blits as it is rather
        -- than being multiplied by whatever colour a menu last set.
        preTinted = true,
      }
    elseif name and name:upper():match("NFGR") then
      -- A member NAMED as a font that does not parse is worth recording; a
      -- member that is simply something else is not.
      index.skipped[#index.skipped + 1] = name
    end
    self:tick("fonts", member + 1, arc.count)
  end

  self:write("gen4_fonts", index)
  self:writeFontDef(index)
  return index
end

-- Publish the fonts as `data.font`, which is what src/render/Font.lua loads.
--
-- This deliberately does NOT invent a fourth spelling.  Font.lua already takes
-- a page table, named faces beside it, per-glyph widths and a charmap, because
-- Gen 1, Gen 2 and Gen 3 each needed some of that; Gen 4 needs the same things
-- and nothing new.  Writing a gen4-shaped font table instead would mean a
-- generation branch in every screen that draws a word.
--
-- ONE PAGE, THREE FACES.  All four fonts number their glyphs from the same
-- base, so registering them as four pages would leave the code-to-page lookup
-- answering with whichever sorted first -- the exact problem Font.lua's own
-- comment describes for Emerald's five Latin faces.  The message font is the
-- page because it is the one dialogue is set in; the other three are faces,
-- chosen by name.
function RomExtractorGen4:writeFontDef(index)
  local PRIMARY = "font_message"
  -- Written by the graphics stage, which runs first.  Absent only when
  -- pl_winframe did not read, and then both records below are simply nil and
  -- Font.lua falls back to the drawn rectangle.
  local winFrames = self._winFrames or {}
  local page = index.pages[PRIMARY]
  if not page then
    -- Rather than pick an arbitrary survivor: without the dialogue font there
    -- is no sensible primary, and a font table with the wrong primary is worse
    -- than none, which merely falls back to the built-in raster.
    return
  end

  local faces = {}
  for label, other in pairs(index.pages) do
    if label ~= PRIMARY then
      faces[label:gsub("^font_", "")] = other
    end
  end

  -- The charmap, inverted from the text decoder so the two cannot disagree
  -- about what a character is.
  --
  -- Only codes the font actually HAS are included.  Gen4Text knows 2,876
  -- characters and this cartridge's font holds 509 glyphs, so the rest are
  -- Japanese codes with nothing to draw; mapping them would put a character on
  -- screen as whatever happened to sit at that quad. 484 of the 509 are
  -- spoken for, and none of them is a ligature -- no entry in range covers
  -- more than one character -- so there is no multi-letter sequence here to
  -- mis-match ordinary text the way Gen 3's PK/MN pair does.
  local charmap = {}
  for code, text in pairs(Gen4Text.CHARS) do
    if type(code) == "number" and type(text) == "string"
        and code >= 1 and text ~= "" then
      local entry = index.fonts[PRIMARY]
      if entry and code <= entry.glyphs then
        charmap[#charmap + 1] = { code = code, seq = text }
      end
    end
  end
  table.sort(charmap, function(a, b) return a.code < b.code end)

  self:write("font", {
    pages = { message = page },
    faces = next(faces) and faces or nil,
    charmap = charmap,
    -- Gen 4 draws its own window frames; they come out of pl_winframe in the
    -- graphics stage rather than being tiled from font cells the way Gen 1
    -- and Gen 2 do.  `frame = "drawn"` stays as the floor under both records
    -- below: a cache extracted before the frame stage existed still gets a
    -- rectangle rather than a box with no border at all.
    frame = "drawn",
    frames = winFrames.standard,
    dialogueFrame = winFrames.dialogue,
    source = ("ROM:pl_font.narc NFGR (%d glyphs, %dx%d, %d charmap entries)")
      :format(index.fonts[PRIMARY].glyphs, page.glyphWidth, page.glyphHeight,
              #charmap),
  })
end

-- ---------------------------------------------------------------------------
-- The stand-in tileset
-- ---------------------------------------------------------------------------

-- Gen 4's world is 3D -- an NSBMD mesh and a texture set per chunk -- and
-- there is no tileset in the Gen 1-3 sense anywhere in the cartridge.
-- MapLoader pairs every map def with one anyway, so until the mesh pipeline
-- exists a Platinum map cannot be BUILT, never mind drawn.
--
-- So one is synthesised: a flat colour per terrain class, keyed by the
-- behaviour byte every permission cell already carries.  It is shaped exactly
-- like a Gen 3 tileset, which is what makes it cost nothing -- TileRenderer
-- takes any tileset whose blockTiles is 2 and hands it to Gen3Tiles, so this
-- goes down the path Hoenn already uses and the renderer needs no Gen 4 branch
-- at all.
--
-- TWO RECORDS, as Gen 3 writes: the raw tileset the compositor reads
-- (map_tilesets) and the pair record a map def names (tilesets).
function RomExtractorGen4:extractTilesets()
  self:beginStage("tilesets")

  local primary = Gen4Tileset.primary()
  local pair = Gen4Tileset.pair()

  self:write("map_tilesets", { [Gen4Tileset.PRIMARY_ID] = primary })
  self:write("tilesets", { [Gen4Tileset.ID] = pair })

  -- The atlas is for looking at rather than for drawing -- Gen3Tiles
  -- composites from `tiles` and `palettes` -- but a picture of the colour key
  -- is worth having when a map comes out the wrong colour.
  self:saveImage("tileset/standin", Gen4Tileset.atlas(), { key = true })

  -- How many of the 256 BEHAVIOUR VALUES land in each class.  Not how many
  -- cells: only 75 of the 256 values occur anywhere in this cartridge, so the
  -- unknown bucket is large here and vanishingly small on the map -- 14 cells
  -- out of 346,819, every one of them a value the cartridge itself calls
  -- UNKNOWN_xNN.  Naming the field for what it counts is the difference
  -- between that being obvious and it reading as a broken classifier.
  local valuesPerClass = {}
  for behaviour = 0, 255 do
    local class = Gen4Tileset.classOf(behaviour)
    valuesPerClass[class.name] = (valuesPerClass[class.name] or 0) + 1
  end

  self.tilesetReport = {
    classes = #Gen4Tileset.CLASSES,
    valuesPerClass = valuesPerClass,
  }
  return pair
end

-- ---------------------------------------------------------------------------
-- Constants and the type chart
-- ---------------------------------------------------------------------------

-- The tables the ENGINE asks for by name, rather than the ones the cartridge
-- happens to have.
--
-- Everything above this point writes what Platinum contains. This writes what
-- src/core/Data.lua opens, and the difference between the two is why a cache
-- full of correct data still does not boot: Data requires `constants`, `maps`,
-- `pokemon`, `moves`, `items`, `text`, `type_chart` and the rest by those
-- exact names, and a table called `gen4_species` is not one of them however
-- right it is.
--
-- `constants.gen` alone is read in seventy-one places. It is the value the
-- whole engine branches on, and without it nothing downstream knows which
-- generation it is running.
function RomExtractorGen4:extractConstants()
  self:beginStage("constants")

  -- The type chart, out of the battle overlay. See Gen4TypeChart for why the
  -- search is structural and why stopping at the first terminator would make
  -- Normal do neutral damage to Ghost.
  local chart, parsed
  for overlay = 0, 130 do
    local ok, bytes = pcall(function() return self.rom:overlay(overlay) end)
    if ok and bytes and #bytes > 0 then
      local at = Gen4TypeChart.find(bytes)
      if at then
        parsed = Gen4TypeChart.parse(bytes, at)
        if parsed then
          parsed.overlay = overlay
          chart = Gen4TypeChart.chart(parsed)
          break
        end
      end
    end
    self:tick("constants", overlay + 1, 140)
  end
  if chart then self:write("type_chart", chart) end

  -- The eighteen type names, in the cartridge's own order -- which is how the
  -- type NUMBERING was established rather than assumed. Slot 9 is the unused
  -- "???" type and is kept, because leaving it out shifts every type above it.
  local types = {}
  for i = 0, Gen4TypeChart.TYPE_COUNT - 1 do
    types[i] = self:string(BANK.typeName, i) or Gen4TypeChart.TYPES[i]
  end

  local natures = {}
  for i = 0, 24 do natures[i + 1] = self:string(BANK.nature, i) end

  local function order(count)
    local out = {}
    for i = 1, count do out[i] = i end
    return out
  end

  self:write("constants", {
    -- The one field seventy-one places read.
    gen = 4,
    generation = 4,
    types = types,
    typeCount = Gen4TypeChart.TYPE_COUNT,
    natures = natures,
    natureOrder = order(25),
    speciesOrder = order(508),
    moveOrder = order(471),
    itemOrder = order(446),
    trainerOrder = order(928),
    world = {
      -- A Gen 4 cell is sixteen pixels, and the map defs say so too.
      blockPx = 16,
    },
    source = ("ROM:Platinum (types bank %d, natures bank %d, type chart overlay %s)")
      :format(BANK.typeName, BANK.nature, tostring(parsed and parsed.overlay)),
  })

  self.constantsReport = {
    chartRows = parsed and #parsed.rows or 0,
    chartSections = parsed and parsed.sections or 0,
    chartOverlay = parsed and parsed.overlay or nil,
    types = Gen4TypeChart.TYPE_COUNT,
    natures = #natures,
  }
  return chart
end

-- ---------------------------------------------------------------------------
-- Overworld sprites
-- ---------------------------------------------------------------------------

-- The NPCs, which turn out not to need the 3D pipeline at all.
--
-- mmodel.narc reads as a wall: Gen 4's overworld is 3D, so the people in it
-- must be models, and models mean NSBMD.  They are not.  421 of its 470
-- members are BTX0 -- Nitro TEXTURE archives -- and only 24 are BMD0.  A Gen 4
-- NPC is a flat quad wearing a texture; the geometry is shared and the
-- per-character art is a texture set.  The member names say so outright
-- (`youngster.nsbtx`, `lass.nsbtx`, `hiker.nsbtx`).
--
-- So the whole overworld cast comes out by reading textures, and the mesh
-- work is not on the path to it.

-- The name an overworld sprite is filed under in `data.sprites`.
--
-- KEYED BY MEMBER, NOT BY graphicsId.  This file used to say the map defs'
-- `graphicsId` "indexes this archive" and key the table by it.  It does not
-- index this archive; it is a key into a lookup table in overlay 5, and the
-- difference is not academic -- ZERO of the 3,555 map objects were drawing
-- their own art.  See Gen4ObjectGfx.  The sprite table is therefore keyed by
-- the mmodel MEMBER, which is what actually identifies a picture, and the map
-- objects go through the table to get one.
function RomExtractorGen4.spriteKey(member)
  return ("SPRITE_G4_%03d"):format(member or 0)
end

-- The two pickup tables, read once each: the visible items out of their own
-- script file, the hidden ones out of the ARM9.  See Gen4Pickups for why they
-- cannot be read the same way.
function RomExtractorGen4:pickupTables()
  if self._pickups then return self._pickups.visible, self._pickups.hidden end
  local visible, hidden
  local scripts = self:archive("scripts")
  local names = scripts and Gen4Archives.names(PATH.scripts)
  if scripts and names then
    for index, name in ipairs(names) do
      if name == "scripts_visible_items" then
        visible = Gen4Pickups.visibleItems(scripts:get(index - 1), Gen4Script)
        break
      end
    end
  end
  -- The bound is the ITEM NAME BANK, not pl_item_data.narc: the data archive
  -- has 446 members and item ids run to at least 451, so using its count
  -- truncates the hidden-item run at 216 rows and loses 41 items silently.
  local nameBank = self:bank(BANK.item)
  hidden = Gen4Pickups.hiddenItems(self.rom and self.rom:arm9(),
                                   nameBank and nameBank.count or nil)
  self._pickups = { visible = visible, hidden = hidden }
  return visible, hidden
end

-- The graphicsId -> member table, read once from the cartridge.
function RomExtractorGen4:objectGfxTable()
  if self._objectGfx ~= nil then return self._objectGfx end
  local overlay = self.rom and self.rom:overlay(Gen4ObjectGfx.OVERLAY)
  local members = self:archive("overworld")
  local map = overlay and Gen4ObjectGfx.read(overlay, members and members.count or 470)
  self._objectGfx = map or false
  return self._objectGfx
end

-- spriteFor(graphicsId) -> key, member, reason
-- `reason` is set when the id has no billboard of its own rather than when the
-- lookup failed; the two must not look alike in the index.
function RomExtractorGen4:spriteFor(graphicsId)
  local map = self:objectGfxTable()
  local member = map and map[graphicsId]
  if member then return RomExtractorGen4.spriteKey(member), member, nil end
  return nil, nil, Gen4ObjectGfx.reason(graphicsId) or "unmapped"
end

function RomExtractorGen4:extractOverworld()
  self:beginStage("overworld")

  local arc = self:archive("overworld")
  local index = { sprites = {}, skipped = {}, counts = {} }
  if not arc then
    self:write("gen4_overworld", index)
    return index
  end

  local names = Gen4Archives.names(PATH.overworld)
  local frames = 0

  for member = 0, arc.count - 1 do
    local bytes = arc:get(member)
    if bytes and Gen4Graphics.isCompressed(bytes) then
      bytes = Gen4Graphics.decompress(bytes)
    end

    if bytes and bytes:sub(1, 4) == "BTX0" then
      local raw = names and names[member + 1] or ("sprite_%03d"):format(member)
      local label = raw:gsub("%.nsbtx$", ""):gsub("[^%w_]", "_")

      local sheet, report = Gen4Models.sheet(bytes)
      if sheet then
        local entry = self:saveImage("overworld/" .. label, sheet, {
          member = member,
          frames = sheet.frames,
          frameWidth = sheet.frameWidth,
          frameHeight = sheet.frameHeight,
          -- What the member held besides the character.  Recorded rather than
          -- dropped: a sprite set that suddenly stops reporting the slots it
          -- always had is a change worth seeing.
          otherSizes = report and report.otherSize or nil,
          undecodable = report and report.undecodable or nil,
        })
        if entry then
          index.sprites[label] = entry
          frames = frames + sheet.frames
          local key = ("%dx%d"):format(sheet.frameWidth, sheet.frameHeight)
          index.counts[key] = (index.counts[key] or 0) + 1
        end
      else
        -- A member whose textures are all a format this does not read, or
        -- whose modal size is far too large to be a person.  Named, so the
        -- gap is a list rather than a number.
        index.skipped[#index.skipped + 1] = {
          member = member, name = label,
          reason = report and (report.oversize and ("oversize " .. tostring(report.modal))
                               or "no decodable frames") or "not parsed",
        }
      end
    end
    self:tick("overworld", member + 1, arc.count)
  end

  self:write("gen4_overworld", index)

  -- ...and the same sheets under the names src/render/SpriteRenderer.lua
  -- reads.  `data.sprites` is a flat map of key to sheet in every generation,
  -- and the fields are the ones a Gen 3 entry carries, because the renderer
  -- is generation-agnostic and a Gen 4 spelling would mean a branch wherever
  -- an NPC is drawn.
  --
  -- `trueColor` is true because these are real colours out of the cartridge's
  -- own palettes, not a four-shade Game Boy set the renderer has to map; it is
  -- what makes SpriteRenderer use the PNG as it is.  `walker` says the frames
  -- are a walk cycle rather than an arbitrary sequence, so it is false for the
  -- single-frame props -- the item ball, the cut tree, the boulder -- which
  -- have exactly one picture and nothing to step through.
  local sprites = {}
  for _, entry in pairs(index.sprites) do
    local key = RomExtractorGen4.spriteKey(entry.member)
    sprites[key] = {
      id = key,
      image = entry.path,
      frames = entry.frames,
      frameWidth = entry.frameWidth,
      frameHeight = entry.frameHeight,
      walker = (entry.frames or 1) > 1,
      trueColor = true,
      source = ("ROM:mmodel.narc[%d]"):format(entry.member),
    }
  end
  self:write("sprites", sprites)

  self.overworldReport = {
    frames = frames, skipped = #index.skipped, sprites = (function()
      local n = 0
      for _ in pairs(sprites) do n = n + 1 end
      return n
    end)(),
  }
  return index
end

-- Species battle pictures.
--
-- The rest of this file extracts things the engine had never seen; this stage
-- fills in the one gap that makes a battle screen possible at all, and it does
-- it by writing the SAME FIELDS Gen 3 writes.  `Sprites.path` reads
-- `def.spriteFront` and `def.spriteBack` off the species row for every
-- generation, and `PicAnim` reads `def.picAnim`; a Gen 4 spelling of either
-- would mean a generation branch in every screen that draws a Pokemon.
--
-- THE FILENAME CARRIES BOTH THE ID AND THE NAME.  Gen 3 names its files by
-- the species slug alone, which it can because a Gen 3 row is keyed by a
-- SPECIES_* constant.  A Gen 4 row is keyed by its integer id and the NAMES
-- COLLIDE -- Nidoran-f and Nidoran-m slug identically -- so a slug-only path
-- would have one species quietly overwrite another's picture.  "029_nidoran"
-- is unique by construction and still readable to whoever writes an override.
-- "029_nidoran" rather than "nidoran": see the stage below for why both
-- halves are needed.  Everything outside [a-z0-9] folds to an underscore and
-- runs collapse, so the two Nidoran, Mr. Mime, Farfetch'd, Ho-Oh and the
-- Porygon numerals all produce a path a filesystem will take.
function RomExtractorGen4.speciesSlug(species, def)
  local name = def and def.name
  if type(name) ~= "string" or name == "" then
    return ("%03d"):format(species)
  end
  local slug = name:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if slug == "" then return ("%03d"):format(species) end
  return ("%03d_%s"):format(species, slug)
end

-- Alternate forms, the Substitute doll and the in-battle shadows.
--
-- Run from the same stage as the base pictures because it is the same decoder
-- on the same shape -- 20x10 tiles, encrypted, linear, two frames side by
-- side -- and differs only in where the numbers come from.  See Gen4Otherpoke
-- for why those numbers are a table rather than arithmetic.
function RomExtractorGen4:extractFormSprites(index, mons)
  local arc = self:archive("otherpoke")
  if not arc then return end

  local function sheetAt(member)
    if not member then return nil end
    local bytes = arc:get(member)
    if not bytes or #bytes == 0 then return nil end
    local info = Gen4Graphics.tiles(bytes)
    if not (info and info.tilesX and info.tilesY) then return nil end
    return {
      pixels = Gen4Graphics.decryptSprite(info.pixels),
      width = info.tilesX * 8, height = info.tilesY * 8,
    }
  end

  local written, borrowed = 0, 0

  for _, row in ipairs(Gen4Otherpoke.FORMS) do
    local normalMember, shinyMember, didBorrow = Gen4Otherpoke.palettes(row)
    if didBorrow then borrowed = borrowed + 1 end
    local normal = normalMember and Gen4Graphics.palette(arc:get(normalMember))
    local shiny = shinyMember and Gen4Graphics.palette(arc:get(shinyMember))
    local key = Gen4Otherpoke.key(row)
    local record = {
      species = row.species, name = row.name, form = row.form,
      borrowedPalette = didBorrow or nil,
    }

    for _, face in ipairs({ "front", "back" }) do
      local sheet = sheetAt(row[face])
      if sheet then
        for _, tone in ipairs({ { "", normal }, { "shiny_", shiny } }) do
          if tone[2] then
            local image = Gen4Pokegra.frame(sheet, tone[2], 1)
            local entry = image and self:saveImage(
              ("battle/forms/%s%s/%s"):format(tone[1], face, key), image,
              { species = row.species, form = row.form })
            if entry then
              record[tone[1] .. face] = entry.path
              written = written + 1
            end
          end
        end
        if face == "front" and normal then
          local strip = Gen4Pokegra.strip(sheet, normal)
          local entry = strip and self:saveImage(
            ("battle/forms/anim/%s"):format(key), strip,
            { species = row.species, form = row.form })
          if entry then
            record.picAnim = {
              sheet = entry.path, count = Gen4Pokegra.FRAMES,
              width = floor(entry.width / Gen4Pokegra.FRAMES),
              height = entry.height, play = GEN4_PIC_ANIM_PLAY,
              source = ("ROM:pl_otherpoke.narc[%d]"):format(row.front),
            }
            written = written + 1
            if shiny then
              local shinyStrip = Gen4Pokegra.strip(sheet, shiny)
              local shinyEntry = shinyStrip and self:saveImage(
                ("battle/forms/anim/shiny/%s"):format(key), shinyStrip,
                { species = row.species, form = row.form })
              if shinyEntry then
                record.picAnim.shinySheet = shinyEntry.path
                written = written + 1
              end
            end
          end
        end
      end
    end

    index.forms[key] = record

    -- ...and onto the species row, under the form name.  Additive: nothing
    -- reads `def.forms` yet, and the fields inside it are spelled exactly like
    -- the ones beside it, so whatever does read it needs no new vocabulary.
    local def = mons and mons[row.species]
    if def and row.species > 0 then
      def.forms = def.forms or {}
      def.forms[row.form] = record
    end
  end

  -- THE SUBSTITUTE DOLL AND THE SHADOWS, which are not a Pokemon and would
  -- have no row to sit on.  Both are wanted by any battle that runs: the doll
  -- the moment something uses Substitute, the shadow under every battler.
  local subSheet = sheetAt(Gen4Otherpoke.SUBSTITUTE.front)
  local subBack = sheetAt(Gen4Otherpoke.SUBSTITUTE.back)
  local subPalette = Gen4Graphics.palette(arc:get(Gen4Otherpoke.SUBSTITUTE.palette))
  local shadowSheet = sheetAt(Gen4Otherpoke.SHADOWS.sheet)
  local shadowPalette = Gen4Graphics.palette(arc:get(Gen4Otherpoke.SHADOWS.palette))

  index.extras = {}
  local function extra(name, sheet, palette)
    if not (sheet and palette) then return end
    local entry = self:saveImage("battle/" .. name, Gen4Pokegra.strip(sheet, palette))
    if entry then
      index.extras[name] = entry.path
      written = written + 1
    end
  end
  extra("substitute_front", subSheet, subPalette)
  extra("substitute_back", subBack, subPalette)
  extra("shadows", shadowSheet, shadowPalette)

  index.counts.formImages = written
  index.counts.forms = #Gen4Otherpoke.FORMS
  index.counts.borrowedPalettes = borrowed
end

function RomExtractorGen4:extractSpeciesSprites()
  self:beginStage("species_sprites")

  local index = { species = {}, forms = {}, missing = {}, counts = {} }
  local arc = self:archive("pokegra")
  local mons = self._pokemon
  if not arc then
    self:write("gen4_species_sprites", index)
    return index
  end
  local heights = self:archive("pokeHeight")
  local total = Gen4Pokegra.speciesCount(arc)

  local written, fellBack, femaleSheets, animated = 0, 0, 0, 0

  for species = 1, total - 1 do
    local normal = Gen4Graphics.palette(arc:get(species * 6 + Gen4Pokegra.SLOT.normalPalette))
    local shiny = Gen4Graphics.palette(arc:get(species * 6 + Gen4Pokegra.SLOT.shinyPalette))
    local def = mons and mons[species]
    local record = { id = species }
    local slug = RomExtractorGen4.speciesSlug(species, def)

    for _, face in ipairs({ "front", "back" }) do
      local sheet, slot = Gen4Pokegra.sheet(arc, Gen4Graphics, species, face)
      if not sheet then
        index.missing[#index.missing + 1] = { species = species, face = face }
      else
        if slot == Gen4Pokegra.FACES[face].fallback then fellBack = fellBack + 1 end

        -- The still picture is frame 1 of the pair, in each palette.
        for _, tone in ipairs({ { "", normal }, { "shiny_", shiny } }) do
          local image = Gen4Pokegra.frame(sheet, tone[2], 1)
          local entry = image and self:saveImage(
            ("battle/%s%s/%s"):format(tone[1], face, slug), image,
            { species = species, face = face, slot = slot })
          if entry then
            written = written + 1
            record[tone[1] .. face] = entry.path
            if def then
              local key = (face == "front")
                and (tone[1] == "" and "spriteFront" or "spriteShiny")
                or (tone[1] == "" and "spriteBack" or "spriteShinyBack")
              def[key] = entry.path
            end
          end
        end

        -- ...and the two-frame strip, which needs no restacking because the
        -- cartridge already stores the pair side by side at exactly the pitch
        -- PicAnim cuts at.
        if face == "front" then
          local strip = Gen4Pokegra.strip(sheet, normal)
          local entry = strip and self:saveImage(
            ("battle/anim/%s"):format(slug), strip, { species = species })
          if entry and def then
            def.picAnim = {
              sheet = entry.path,
              count = Gen4Pokegra.FRAMES,
              width = floor(entry.width / Gen4Pokegra.FRAMES),
              height = entry.height,
              play = GEN4_PIC_ANIM_PLAY,
              source = ("ROM:pl_pokegra.narc[%d]"):format(species * 6 + slot),
            }
            local shinyStrip = Gen4Pokegra.strip(sheet, shiny)
            local shinyEntry = shinyStrip and self:saveImage(
              ("battle/anim/shiny/%s"):format(slug), shinyStrip,
              { species = species })
            -- A shiny that loses its colours for the two frames it is moving
            -- and gets them back when it settles is the Gen 3 bug this avoids:
            -- the cartridge loads ONE palette for the battler and draws every
            -- frame through it, so the strip is decoded twice here.
            if shinyEntry then def.picAnim.shinySheet = shinyEntry.path end
            animated = animated + 1
          end
          if entry then written = written + 1 end
        end

        -- The distinct female art, only where it IS distinct: 89 species,
        -- against 322 whose female member repeats the male byte for byte.
        if Gen4Pokegra.femaleDiffers(arc, species, face) then
          local femaleSheet = Gen4Pokegra.sheetAt(arc, Gen4Graphics, species,
            Gen4Pokegra.FACES[face].fallback)
          local image = femaleSheet and Gen4Pokegra.frame(femaleSheet, normal, 1)
          local entry = image and self:saveImage(
            ("battle/female_%s/%s"):format(face, slug), image,
            { species = species, face = face })
          if entry then
            record["female" .. face] = entry.path
            if def then
              def[(face == "front") and "spriteFrontFemale" or "spriteBackFemale"] = entry.path
            end
            femaleSheets = femaleSheets + 1
            written = written + 1
          end
        end
      end

      -- Where the picture SITS.  height.narc is four one-byte members per
      -- species in the same slot order as the sheets, and a missing entry is
      -- left nil rather than defaulted to 0 -- a real 0 and "no such sheet"
      -- mean different things to whatever places the sprite.
      local slotIndex = Gen4Pokegra.FACES[face].preferred
      local offset = Gen4Pokegra.offset(heights, species, slotIndex)
        or Gen4Pokegra.offset(heights, species, Gen4Pokegra.FACES[face].fallback)
      if offset then record[face .. "Offset"] = offset end
    end

    if next(record) and record.id then index.species[species] = record end
    self:tick("species_sprites", species, total)
  end

  index.counts = {
    images = written, viaFemaleSlot = fellBack,
    femaleVariants = femaleSheets, animated = animated,
  }
  self:extractFormSprites(index, mons)
  self:write("gen4_species_sprites", index)

  -- The species module is rewritten because the paths were stamped onto its
  -- own rows above.  extractSpecies has already run and self._pokemon IS the
  -- table it wrote, so this is the whole of the wiring.
  if mons then self:write("pokemon", mons) end

  self.speciesSpriteReport = index.counts
  self.speciesSpriteReport.missing = #index.missing
  return index
end


-- The height field, which is the half of "3D map" that is not art.
--
-- Everything else about a Gen 4 map treats it as a grid: the permission word
-- says what a tile IS, and that is enough to walk on a flat world.  It is not
-- enough for Sinnoh, where a bridge crosses a path and the two share an (x, z),
-- and where a slope rises between two tiles that are both "ground".  The BDHC
-- block in each land chunk is the cartridge's own answer and it is small,
-- self-checking and independent of the mesh, so it comes out now while the
-- NSBMD does not.
--
-- WHAT IT IS NOT: a walkability map.  Measured rather than assumed -- tiles the
-- permission grid calls void are covered by a plate 75.6% of the time and real
-- ground 72.3%, which is no correlation at all.  The two answer different
-- questions and neither can be derived from the other; where no plate covers a
-- point the game LEAVES THE HEIGHT ALONE (CalculateObjectHeight returns FALSE),
-- so plates are the exceptions rather than the surface.
function RomExtractorGen4:extractHeights()
  self:beginStage("heights")

  local land = self:archive("land")
  local index = { chunks = {}, counts = {}, failed = {} }
  if not land then
    self:write("gen4_map_heights", index)
    return index
  end

  local totals = { points = 0, normals = 0, constants = 0,
                   plates = 0, strips = 0, access = 0 }
  local parsed, empty = 0, 0

  for member = 0, land.count - 1 do
    local chunk = Gen4Maps.land(land:get(member))
    local block = chunk and chunk.bdhc
    if not block or #block == 0 then
      empty = empty + 1
    else
      local bdhc, why = Gen4Bdhc.parse(block)
      if not bdhc then
        index.failed[#index.failed + 1] = { member = member, reason = why }
      else
        parsed = parsed + 1
        for key in pairs(totals) do totals[key] = totals[key] + bdhc.counts[key] end
        -- Kept in the cartridge's own indexed shape rather than flattened into
        -- one rectangle per plate.  It is smaller, and it keeps the strip
        -- index, which is how the game narrows the search -- flattening would
        -- throw away the only structure here that is not derivable.
        index.chunks[member] = {
          points = bdhc.points, normals = bdhc.normals,
          constants = bdhc.constants, plates = bdhc.plates,
          strips = bdhc.strips, access = bdhc.access,
        }
      end
    end
    self:tick("heights", member + 1, land.count)
  end

  index.counts = totals
  index.counts.chunks = parsed
  index.counts.empty = empty
  index.counts.failed = #index.failed
  -- The units, stated once so no caller has to rediscover them: a land chunk
  -- is 32x32 tiles and its plate coordinates run -256..256, so a tile is 16
  -- world units and THE CHUNK IS CENTRED ON THE ORIGIN, not cornered at it.
  -- Tile (tx, tz) has its centre at ((tx + 0.5) * 16 - 256, (tz + 0.5) * 16 - 256).
  index.tileSize = Gen4Bdhc.TILE_UNITS
  index.chunkOrigin = -Gen4Bdhc.CHUNK_UNITS / 2

  self:write("gen4_map_heights", index)
  self.heightReport = index.counts
  return index
end


-- WHERE A NEW GAME STARTS.  The stage that stops Platinum opening in Red's
-- bedroom.
--
-- Data.lua's overlay is ADDITIVE: a module a version does not write resolves to
-- the ROOT cache, which is Red's.  `field.lua` used to be blocked from that for
-- a stated reason -- "field.lua is where boot.startMap and boot.screens live
-- ... which is how NEW GAME on Emerald opened Red's intro in Red's house" --
-- and it was unblocked when Gen 3 learned to write one.  Gen 4 did not, so the
-- first New Game on Platinum took `REDS_HOUSE_2F` and died in MapLoader.  The
-- fix is the one Gen 3 got.
--
-- `screens.newGame = false` is not decoration: Game.lua reads that key and, if
-- it is NIL rather than false, pushes "OakSpeech" for any non-Gen-2 version.
-- Platinum's opening is Rowan's, not Oak's, and neither is built -- so the
-- honest value is an explicit false, which means "this version has no new-game
-- screen", not "nobody said".
function RomExtractorGen4:extractField()
  self:beginStage("field")

  local headers = self._mapHeaders
  local maps = self._mapDefs
  local start, respawn, at, spawns, spawnAt =
    Gen4Field.find(self.rom and self.rom:arm9(), headers, maps,
                   headers and self._mapHeaderCount or nil)

  local out = { source = "ROM:Platinum" }
  if not start then
    -- Reported rather than guessed.  A field table with an invented start map
    -- is worse than none: it boots, walks into a map that is not there, and
    -- looks like a map bug rather than a missing table.
    out.error = tostring(respawn)
    self:write("field", out)
    self.fieldReport = { found = false, reason = out.error }
    return out
  end

  local function nameFor(id)
    local header = headers and headers[id]
    return header and header.internalName or nil
  end

  local startMap = nameFor(start.mapHeaderID)
  local healMap = nameFor(spawns[1].blackOutMap)

  out.boot = {
    startMap = startMap,
    startX = start.x, startY = start.z,
    startFacing = start.facing,
    -- Where a blackout sends you before you have seen a Pokemon Centre: the
    -- first spawn row's BLACKOUT half, which is the player's own ground floor.
    lastHeal = healMap and { map = healMap, x = spawns[1].blackOutX,
                             y = spawns[1].blackOutZ } or nil,
    -- THE BOOT SCREENS, NAMED HERE BECAUSE NOBODY ELSE CAN NAME THEM.
    --
    -- Data.lua seeds a default for each of these and then overrides the ones
    -- it still recognises as the default -- Gen 2 takes Gen2Intro, Gen 3 takes
    -- Gen3Title, and a Gen 4 cache that named none of them would keep RED'S.
    -- Writing them outright is also what makes them stick: every override in
    -- seedDefaults is guarded by `== BOOT_DEFAULTS.screens.x`, so a value this
    -- stage states is left alone by all of them.
    --
    -- `newGame = false` is deliberate and is not a gap.  OakSpeech replays a
    -- professor's intro out of text Platinum does not have; Platinum's own
    -- opening is Rowan's, which is a scripted scene on the intro map rather
    -- than a screen, so there is nothing to push here.
    screens = {
      splash = "Gen4Intro",
      title = "Gen4Title",
      -- WAS `false`, AND THAT WAS THE WHOLE OF "NEW GAME HAS NO INTRO".
      -- OakSpeech replays a professor's intro out of text Platinum does not
      -- have, so there was nothing to put here and the game opened straight
      -- into the bedroom.  There is something now: the `intro` stage extracts
      -- the television broadcast and Rowan's script, and Gen4RowanIntro plays
      -- them.
      newGame = "Gen4RowanIntro",
      -- Named for the same reason as the two above: left at the default this
      -- resolves to the Game Boy OPTION screen, whose rows are Gen 1's and
      -- whose FRAME row cannot reach Platinum's twenty message boxes.
      options = "Gen4Options",
    },
  }

  -- The fly and blackout destinations, named rather than numbered, because a
  -- header id means nothing to the code that will eventually draw a town map.
  out.healLocations = {}
  for index, row in ipairs(spawns) do
    out.healLocations[index] = {
      index = index - 1,
      blackOut = { map = nameFor(row.blackOutMap), header = row.blackOutMap,
                   x = row.blackOutX, y = row.blackOutZ },
      fly = { map = nameFor(row.flyMap), header = row.flyMap,
              x = row.flyX, y = row.flyZ },
      isWarpPos = row.isWarpPos == 1,
      unlockOnMapEntry = row.unlockOnMapEntry == 1,
      firstArrival = row.firstArrival,
    }
  end

  -- THE PLAYER'S OWN SHEETS, WHICH ARE NOT AN NPC'S.
  --
  -- Reported from play, and visible in one line of the log: `player sheet:
  -- SPRITE_RED -> ninja_boy`.  With no `field.playerSprites` the avatar falls
  -- back to a GAME BOY sprite id, which a Gen 4 cache resolves through its own
  -- sprite table to whatever happens to sit there -- `ninja_boy` is mmodel
  -- member 1 and the player is member 0, so the hero walked Sinnoh as a
  -- passer-by and nothing reported an error.
  --
  -- Found by NAME rather than by graphics id.  `player_m` and `player_f` are
  -- what the object-graphics table calls them, and a name cannot be off by one
  -- the way an id can -- which is exactly the mistake this is fixing.
  out.playerSprites, out.playerForms = self:playerSheets()

  out.source = ("ROM:Platinum (locations arm9+0x%X, spawns arm9+0x%X)")
    :format(at, spawnAt)
  self:write("field", out)
  self.fieldReport = {
    found = true, startMap = startMap, startX = start.x, startY = start.z,
    facing = start.facing, healLocations = #spawns,
  }
  return out
end

-- ---------------------------------------------------------------------------
-- The main menu
-- ---------------------------------------------------------------------------

-- What the title screen and the main menu need that is not a picture: the
-- words, the layout and the two colours.
--
-- The pictures are already written -- the graphics stage composes titledemo
-- into `gen4_graphics.screens` under `title/...` -- so this stage's job is to
-- say which of them is which, and to hand over the strings in the cartridge's
-- own words rather than in English this file typed out.
--
-- THE STRINGS ARE READ, NOT ASSUMED.  Bank 550 is stated in Gen4Menus and
-- checked here: if entry 0 does not come back as something, the record says so
-- rather than shipping a menu whose rows are blank.
function RomExtractorGen4:extractMenus()
  self:beginStage("menus")

  local out = {
    bank = BANK.mainMenu,
    layout = Gen4Menus.LAYOUT,
    colors = {
      background = Gen4Menus.rgb(Gen4Menus.COLORS.background),
      unfocused = Gen4Menus.rgb(Gen4Menus.COLORS.unfocused),
    },
    source = ("ROM:Platinum (bank %d, titledemo.narc)"):format(BANK.mainMenu),
  }

  local text = {}
  for key, index in pairs(Gen4Menus.TEXT) do
    text[key] = self:string(BANK.mainMenu, index)
  end
  out.text = text

  -- The rows this port offers, each already carrying its own words so the
  -- screen has no bank lookup to do and no English of its own to fall back on.
  out.rows = {}
  for _, row in ipairs(Gen4Menus.ROWS) do
    out.rows[#out.rows + 1] = {
      id = row.id,
      lines = row.lines,
      label = (row.text and self:string(BANK.mainMenu, row.text))
        or row.fallback,
      -- Whether the cartridge has this row at all.  OPTION does not exist on
      -- Platinum's main menu and is this engine's addition; saying so here is
      -- cheaper than a reader later mistaking it for extracted data.
      fromCartridge = row.fromCartridge,
    }
  end

  out.continueRows = {}
  for _, row in ipairs(Gen4Menus.CONTINUE_ROWS) do
    out.continueRows[#out.continueRows + 1] = {
      label = self:string(BANK.mainMenu, row.label),
      value = row.value,
      needsPokedex = row.needsPokedex or nil,
    }
  end

  -- The warning NEW GAME arms when a save already exists, in the cartridge's
  -- own wording.
  out.newGameWarning = self:string(BANK.mainMenuAlert, Gen4Menus.ALERT_NEW_GAME)

  -- THE POKETCH.  The order is one bank's and the names are another's, and
  -- the pairing is checked rather than assumed: every coloured name must open
  -- exactly one description in the ordered bank.
  local names = {}
  for i = 0, Gen4Menus.POKETCH_COUNT - 1 do
    local text = self:string(BANK.poketchName, Gen4Menus.POKETCH_NAME_FIRST + i)
    local name = Gen4Menus.poketchName(text)
    if name then names[#names + 1] = name end
  end
  out.poketch = {
    descBank = BANK.poketchDesc, nameBank = BANK.poketchName,
    border = Gen4Menus.POKETCH_BORDER,
    unavailable = Gen4Menus.POKETCH_UNAVAILABLE,
    digits = Gen4Menus.POKETCH_DIGITS,
    apps = {}, unpaired = {},
  }
  -- THE LONGEST NAME THE DESCRIPTION CONTAINS, not the one it starts with.
  --
  -- Matching on the opening "The <name>" paired twenty-four of the
  -- twenty-five and left the Calendar out, because its description is the one
  -- that does not begin that way: "Use the monthly Calendar to make a note of
  -- important dates."  Matching anywhere instead needs LONGEST, because
  -- "Counter" occurs inside "Trainer Counter" -- and then the twenty-five
  -- assignments have to be a permutation, which is the check that says the
  -- looser match did not fold two apps onto one name.
  local used = {}
  for i = 0, Gen4Menus.POKETCH_COUNT - 1 do
    local description = self:string(BANK.poketchDesc, Gen4Menus.POKETCH_DESC_FIRST + i)
    local found = nil
    for _, name in ipairs(names) do
      if type(description) == "string" and description:find(name, 1, true) then
        if not found or #name > #found then found = name end
      end
    end
    if not found or used[found] then
      out.poketch.unpaired[#out.poketch.unpaired + 1] = i
    end
    if found then used[found] = true end
    out.poketch.apps[i + 1] = {
      id = i,
      name = found,
      description = description,
      art = found and Gen4Menus.POKETCH_ART[found] or nil,
      live = found and Gen4Menus.POKETCH_LIVE[found] or nil,
    }
  end

  -- THE SUMMARY PAGES.  Every word on them, and the rows they sit in.
  out.summary = { bank = BANK.summary, layout = Gen4Menus.SUMMARY_LAYOUT,
                  pages = {}, text = {}, natures = {}, characteristics = {} }
  for key, index in pairs(Gen4Menus.SUMMARY_TEXT) do
    out.summary.text[key] = self:string(BANK.summary, index)
  end
  for i = 0, Gen4Menus.SUMMARY_NATURES - 1 do
    out.summary.natures[i + 1] =
      self:string(BANK.summary, Gen4Menus.SUMMARY_NATURE_FIRST + i)
  end
  for i = 0, Gen4Menus.SUMMARY_CHARACTERISTICS - 1 do
    out.summary.characteristics[i + 1] =
      self:string(BANK.summary, Gen4Menus.SUMMARY_CHARACTERISTIC_FIRST + i)
  end
  for i, page in ipairs(Gen4Menus.SUMMARY_PAGES) do
    out.summary.pages[i] = {
      key = page.key, art = page.art,
      title = self:string(BANK.summary, Gen4Menus.SUMMARY_TEXT[page.title]),
    }
  end

  -- THE BAG.  Eight pocket names and where the screen puts things; the art
  -- itself is already in `gen4_graphics.screens` under `bag/`.
  out.bag = { bank = BANK.bagPockets, pockets = {}, layout = Gen4Menus.BAG_LAYOUT,
              icon = Gen4Menus.BAG_ICON, iconColumns = Gen4Menus.BAG_ICON_COLUMNS }
  for i = 0, Gen4Menus.BAG_POCKETS - 1 do
    out.bag.pockets[i + 1] = self:string(BANK.bagPockets, i)
  end

  -- THE OPTIONS SCREEN, in the cartridge's words and the cartridge's order.
  --
  -- The order is the point.  Platinum lists STEREO before MONO and Emerald
  -- lists MONO before STEREO, so a screen that reused the Gen 3 row would show
  -- the right two words, store the wrong one, and look entirely correct doing
  -- it.  What is written here is the enum order out of the cartridge, row by
  -- row, with each row's own description line beside it.
  out.options = { bank = BANK.options,
                  title = self:string(BANK.options, Gen4Menus.OPTIONS_TITLE),
                  rows = {} }
  for _, row in ipairs(Gen4Menus.OPTION_ROWS) do
    local values
    if row.values == "frames" then
      values = {}
      for index = Gen4Menus.FRAME_FIRST, Gen4Menus.FRAME_LAST do
        values[#values + 1] = self:string(BANK.options, index)
      end
    elseif type(row.values) == "table" then
      values = {}
      for _, index in ipairs(row.values) do
        values[#values + 1] = self:string(BANK.options, index)
      end
    end
    out.options.rows[#out.options.rows + 1] = {
      key = row.key,
      label = self:string(BANK.options, row.label),
      values = values,
      description = row.description
        and self:string(BANK.options, row.description) or nil,
    }
  end
  -- CHOOSING A STARTER, in the cartridge's words and its own order.
  --
  -- The species ids come from `choose_starter_app.c`, the offer lines from
  -- bank 360, and the ball models from ev_pokeselect -- three separate lists
  -- that have to agree.  They are checked against each other here: the species
  -- the id names must be the one the offer line is about, or the record says
  -- so rather than shipping a briefcase that hands over the wrong Pokemon.
  out.starter = { bank = BANK.starter, rows = {},
    intro = self:string(BANK.starter, Gen4Menus.STARTER_TEXT.theseArePokeBalls),
    choose = self:string(BANK.starter, Gen4Menus.STARTER_TEXT.nowChoose) }
  for _, row in ipairs(Gen4Menus.STARTERS) do
    local name = self:string(BANK.species, row.species)
    out.starter.rows[#out.starter.rows + 1] = {
      species = row.species,
      name = name,
      model = row.model,
      offer = self:string(BANK.starter, row.text),
      -- Set only when the species id and the name bank disagree with what the
      -- cartridge's own source says this slot holds.  Nothing should ever read
      -- it; it exists so that if the three lists ever drift, the drift is in
      -- the data rather than in somebody's memory.
      mismatch = (name ~= row.expect) and
        ("expected %s, species %d is %s"):format(row.expect, row.species,
                                                 tostring(name)) or nil,
    }
  end

  -- Extracted and not offered as a row; see Gen4Menus.OPTIONS_CONFIRM for why.
  out.options.confirm = {
    label = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.label),
    dialog = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.dialog),
    yes = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.yes),
    no = self:string(BANK.options, Gen4Menus.OPTIONS_CONFIRM.no),
  }

  -- The title sequence's pictures, by role.  The paths are what the graphics
  -- stage already wrote; naming them here means the title screen does not have
  -- to know what an archive member is called.
  --
  -- AND WITH EACH ONE, WHERE ITS ARTWORK ACTUALLY IS.  Every sheet here is
  -- 256x192 or 256x256 and most of it is empty: the logo's artwork occupies
  -- rows 27 to 148 of its own sheet, the copyright's four lines rows 64 to 119.
  -- A screen that draws these at 0,0 and trusts the sheet size puts the logo
  -- forty rows lower than it belongs and clips "VERSION" off the bottom -- which
  -- it did, and it looked like a layout choice rather than a measurement that
  -- was never taken.  So the box is measured here, off the composed pixels, and
  -- the screen positions by it.
  local screens = (self._graphicsIndex or {}).screens or {}
  local titleJobs = Gen4Screens.plan(PATH.title, { tilesWide = 8 }) or {}
  local titleArc = self:archiveAt(PATH.title)
  local boxes = {}
  for _, job in ipairs(titleJobs) do
    local image = titleArc and self:composeJob(titleArc, job)
    boxes[job.name] = image and contentBox(image) or nil
  end
  local function art(name, role)
    local entry = screens["title/" .. name]
    if not entry then return nil end
    return { path = entry.path, width = entry.width, height = entry.height,
             content = boxes[name], role = role }
  end
  out.title = {
    logo = art("logo", "logo"),
    logoJP = art("logo_jp", "logo"),
    copyright = art("copyright", "copyright"),
    presents = art("gf_presents", "card"),
    topBorder = art("top_screen_border", "field"),
    bottomBorder = art("bottom_screen_border", "field"),
  }
  -- The centrepiece is a 3D model (giratina.nsbmd) and there is no 3D path
  -- yet, so the title screen shows the logo over the border rather than over
  -- Giratina.  Recorded rather than left to be rediscovered as a bug.
  out.title.missing = { "giratina.nsbmd (the animated centrepiece)" }

  self:write("gen4_menus", out)
  self.menusReport = {
    rows = #out.rows,
    continueRows = #out.continueRows,
    haveContinue = text.continue ~= nil,
    optionRows = #out.options.rows,
    art = (out.title.logo and 1 or 0) + (out.title.copyright and 1 or 0)
      + (out.title.presents and 1 or 0) + (out.title.topBorder and 1 or 0),
    logoBox = out.title.logo and out.title.logo.content or nil,
  }
  return out
end

-- ---------------------------------------------------------------------------
-- The opening: the television, and Rowan
-- ---------------------------------------------------------------------------

-- What a NEW GAME on Platinum actually opens with, which until now was
-- nothing: a news broadcast on a television, then Professor Rowan asking who
-- you are.  Both live in archives with NO NAME TABLE, so this stage cannot go
-- through the generic screen planner and every member index comes out of
-- Gen4IntroScene, where it is transcribed from the cartridge's own loaders.
--
-- EVERY PICTURE IS COMPOSED AND THEN LOOKED AT, because a wrong member index
-- here does not fail: it decodes, it composes, and it writes a picture.  The
-- television is the case in point -- composed with the palette its first load
-- names, the broadcast is a black rectangle with coloured noise in it.
function RomExtractorGen4:extractIntro()
  self:beginStage("intro")

  local out = {
    text = {}, tv = {}, backdrops = {}, figures = {},
    source = ("ROM:Platinum (banks %d/%d, %s, %s)"):format(
      BANK.rowanIntro, BANK.rowanIntroTv,
      Gen4IntroScene.PATH, Gen4IntroScene.TV_PATH),
  }

  -- The script, by the names Gen4IntroScene gives the entries rather than by
  -- index, so the screen that plays it never spells a bank index itself.
  for key, index in pairs(Gen4IntroScene.TEXT) do
    out.text[key] = self:string(BANK.rowanIntro, index)
  end
  out.text.tv = self:string(BANK.rowanIntroTv, Gen4IntroScene.TV_TEXT)

  out.controlInfo = {}
  for _, index in ipairs(Gen4IntroScene.CONTROL_INFO) do
    out.controlInfo[#out.controlInfo + 1] = self:string(BANK.rowanIntro, index)
  end
  out.adventureInfo = {}
  for _, index in ipairs(Gen4IntroScene.ADVENTURE_INFO) do
    out.adventureInfo[#out.adventureInfo + 1] = self:string(BANK.rowanIntro, index)
  end

  -- The rival's eight preset names, with "New name!" at the head of the list
  -- the way the cartridge's own menu orders them.  The first entry is the
  -- prompt to type one, not a name, and is marked rather than left for the
  -- screen to know by position.
  out.rivalNames = {}
  for index = Gen4IntroScene.RIVAL_NAME_FIRST, Gen4IntroScene.RIVAL_NAME_LAST do
    out.rivalNames[#out.rivalNames + 1] = {
      label = self:string(BANK.rowanIntro, index),
      custom = (index == Gen4IntroScene.RIVAL_NAME_FIRST) or nil,
    }
  end

  out.script = Gen4IntroScene.SCRIPT
  out.role = Gen4IntroScene.ROLE

  -- ------------------------------------------------------------ television --
  local tvArc = self:archive("introTv")
  if tvArc then
    -- The background palette as the app actually builds it: member 6 whole,
    -- then member 9 over colours 32 upwards.  See Gen4IntroScene.TV_PALETTE.
    local base = self:paletteMember(tvArc, Gen4IntroScene.TV_PALETTE)
    local over = self:paletteMember(tvArc, Gen4IntroScene.TV_PALETTE_OVERLAY)
    local palette = base
    if base and over then
      palette = {}
      for i = 1, #base do palette[i] = base[i] end
      local first = Gen4IntroScene.TV_OVERLAY_FIRST
      for i = first + 1, math.min(first + Gen4IntroScene.TV_OVERLAY_COUNT, #over) do
        palette[i] = over[i]
      end
    end
    for _, layer in ipairs(Gen4IntroScene.TV_LAYERS) do
      local image = palette and self:composeWith(tvArc, layer.tiles,
                                                layer.tilemap, palette)
      local entry = self:saveImage("intro/tv_" .. layer.name, image, {
        tiles = layer.tiles, tilemap = layer.tilemap,
      })
      if entry then out.tv[layer.name] = entry end
    end
  end

  -- --------------------------------------------------------------- Rowan ---
  local arc = self:archive("intro")
  if arc then
    local backdropPalette =
      self:paletteMember(arc, Gen4IntroScene.BACKDROP_PALETTE.platinum)
    for index, member in ipairs(Gen4IntroScene.BACKDROP_MAPS) do
      local role = Gen4IntroScene.BACKDROP_ROLE[index] or ("backdrop_" .. index)
      local image = backdropPalette
        and self:composeWith(arc, Gen4IntroScene.BACKDROP_TILES, member,
                             backdropPalette)
      local entry = self:saveImage("intro/backdrop_" .. role, image, {
        tilemap = member, role = role,
      })
      if entry then out.backdrops[role] = entry end
    end

    for _, figure in ipairs(Gen4IntroScene.FIGURES) do
      local own = self:paletteMember(arc, figure.palette)
      -- Replicated across every palette row; see Gen4IntroScene.FIGURE_ROWS
      -- for why that is the same picture the hardware draws rather than a
      -- shortcut around the cell rewrite.
      local palette
      if own then
        palette = {}
        for row = 0, Gen4IntroScene.FIGURE_ROWS - 1 do
          for colour = 1, 16 do
            palette[row * 16 + colour] = own[colour] or own[1]
          end
        end
      end
      local image = palette
        and self:composeWith(arc, figure.tiles,
                             Gen4IntroScene.FIGURE_TILEMAP, palette)
      local entry = self:saveImage("intro/figure_" .. figure.name, image, {
        tiles = figure.tiles, palette = figure.palette,
      })
      if entry then out.figures[figure.name] = entry end
    end
  end

  self:write("gen4_intro", out)

  local backdrops, figures = 0, 0
  for _ in pairs(out.backdrops) do backdrops = backdrops + 1 end
  for _ in pairs(out.figures) do figures = figures + 1 end
  self.introReport = {
    backdrops = backdrops, figures = figures,
    tv = (out.tv.broadcast and 1 or 0) + (out.tv.bezel and 1 or 0)
      + (out.tv.scanlines and 1 or 0),
    haveHello = out.text.hello ~= nil,
    rivalNames = #out.rivalNames,
  }
  return out
end

-- The player's walking, cycling, surfing, fishing and Poke-Ball sheets, for
-- both characters, in the two shapes `Player:refreshForm` reads:
-- `field.playerSprites` (the default pair) and `field.playerForms[gender]`
-- (the override the intro's boy-or-girl answer selects).
--
-- A sheet the cartridge does not have, or one whose graphics id has no
-- billboard, is simply absent: refreshForm keeps whatever it had for that
-- slot, which is better than pointing it at a sprite that is not the player.
function RomExtractorGen4:playerSheets()
  -- graphics id by NAME, built once.  Gen4ObjectGfx.name answers nil past the
  -- end of its list, which is the stop condition.
  if not self._gfxIdByName then
    local byName = {}
    local id = 0
    while true do
      local name = Gen4ObjectGfx.name(id)
      if not name then break end
      if byName[name] == nil then byName[name] = id end
      id = id + 1
      if id > 4096 then break end
    end
    self._gfxIdByName = byName
  end

  local function sheet(name)
    local id = self._gfxIdByName[name]
    if not id then return nil end
    local key = self:spriteFor(id)
    return key
  end

  local function formFor(prefix, label)
    local form = {
      label = label,
      walk = sheet(prefix),
      bike = sheet(prefix .. "_bike"),
      surf = sheet(prefix .. "_surf"),
      fieldMove = sheet(prefix .. "_holding_poke_ball"),
      fishing = sheet(prefix .. "_fishing"),
    }
    return form.walk and form or nil
  end

  local boy = formFor("player_m", "BOY")
  local girl = formFor("player_f", "GIRL")
  if not (boy or girl) then return nil, nil end

  local default = boy or girl
  local forms = { order = {} }
  if boy then forms.order[#forms.order + 1] = "boy"; forms.boy = boy end
  if girl then forms.order[#forms.order + 1] = "girl"; forms.girl = girl end

  return {
    walk = default.walk, bike = default.bike, surf = default.surf,
    fieldMove = default.fieldMove, fishing = default.fishing,
  }, forms
end

-- ---------------------------------------------------------------------------
-- 3D models
-- ---------------------------------------------------------------------------

-- WHICH ARCHIVES' MODELS ARE PUBLISHED, and why this is a list rather than
-- "all of them".
--
-- The cartridge holds 1,030 models and the whole lot packs to under 4 MB, so
-- size is not the reason.  The reason is that a model in the cache is only
-- worth having when something draws it, and exactly one screen does so far.
-- Publishing the other twenty archives now would put twenty archives' worth of
-- geometry in every player's cache to be read by nothing, and would make the
-- import slower for no one's benefit.  Each entry moves here when the screen
-- that needs it exists.
local MODEL_ARCHIVES = {
  { path = "/graphic/ev_pokeselect.narc", out = "starter",
    label = "starter selection" },
  -- THE FIELD'S OWN ANIMATION ARCHIVE, and it holds no models at all: 72
  -- texture-pattern flipbooks, 98 texture scrolls and the doors, laid over the
  -- map meshes.  Nothing consumes these yet -- the map meshes are not built --
  -- so they are extracted and checked rather than drawn.  They are here now
  -- because they are what makes water move, and because an animation archive
  -- with no models beside it is exactly the case a reader that assumed models
  -- would get wrong quietly.
  { path = "/arc/bm_anime.narc", out = "field",
    label = "field animations" },
}

-- Platinum's 3D, in the shape the engine can load: packed geometry, the
-- textures as ordinary PNGs, and the animations that drive each model.
--
-- THE GEOMETRY IS VERIFIED TWICE, and the second one is the one that matters
-- here.  Gen4Nsbmd already checks every model against the counts its own
-- header states -- that is what makes the decode trustworthy.  This stage then
-- packs each model into two binary strings and UNPACKS THEM AGAIN, requiring
-- every coordinate and every index to come back unchanged.  A packer that
-- drops a field, swaps two, or mis-signs a negative produces a model that
-- still draws, inside out or with a wall missing, and nothing else would
-- notice.
function RomExtractorGen4:extractModels()
  self:beginStage("models")

  local out = { sets = {}, source = "ROM:Platinum (NSBMD/NSBTX/NSBCA)" }
  local totalModels, totalShapes, failed = 0, 0, 0
  local animFailed = 0

  for _, entry in ipairs(MODEL_ARCHIVES) do
    local arc = self:archiveAt(entry.path)
    local set = { label = entry.label, path = entry.path,
                  models = {}, animations = {} }
    -- Joint animations wait until the whole archive has been read: see below
    -- for why their matrices are only written where something can wear them.
    local pending = {}
    if arc then
      for member = 0, arc.count - 1 do
        local bytes = arc:get(member)
        if bytes and Gen4Graphics.isCompressed(bytes) then
          bytes = Gen4Graphics.decompress(bytes)
        end
        local magic = bytes and bytes:sub(1, 4)

        if magic == Gen4Nsbmd.MAGIC then
          local parsed = Gen4Nsbmd.parse(bytes)
          local sections = Gen4Nsbmd.sections(bytes)
          -- The model file carries its own textures in a second section, and
          -- `Gen4Models.parse` has to be told where: reading a model file the
          -- way a texture archive is read finds the MODEL section and builds a
          -- texture table out of geometry.
          local textures = sections and sections.TEX0
            and Gen4Models.parse(bytes, sections.TEX0) or nil
          for _, model in ipairs(parsed and parsed.models or {}) do
            local packed = Gen4ModelPack.pack(model)
            local ok, why = Gen4ModelPack.verify(model, packed)
            if not ok then
              failed = failed + 1
              self.modelFailure = self.modelFailure or why
            end
            packed.member = member
            packed.animations = {}

            -- Each shape's texture, written once per NAME rather than once per
            -- shape: fifteen shapes of the briefcase share three pictures
            -- between them, and saving one file per shape would write the same
            -- image five times.
            local written = {}
            for _, shape in ipairs(packed.shapes) do
              local name = shape.texture
              if name and textures then
                local key = ("%s/%s"):format(model.name, name)
                if written[name] == nil then
                  written[name] = false
                  local index, palette
                  for i, texture in ipairs(textures.textures) do
                    if texture.name == name then index = i end
                  end
                  for i, entry2 in ipairs(textures.palettes) do
                    if entry2.name == shape.palette then palette = i end
                  end
                  local image = index
                    and Gen4Models.decode(textures, bytes, index, palette or 1)
                  local saved = image and self:saveImage(
                    "models/" .. entry.out .. "/" .. key:gsub("[^%w_/%-]", "_"),
                    image, { texture = name, palette = shape.palette })
                  written[name] = saved and saved.path or false
                end
                shape.image = written[name] or nil
              end
              totalShapes = totalShapes + 1
            end

            set.models[#set.models + 1] = packed
            totalModels = totalModels + 1
          end

        elseif magic and Gen4Anim.KINDS[magic] then
          -- The animations are carried beside the models rather than merged
          -- into them, because an animation names what it drives and the
          -- pairing is by NAME -- which is the cross-check, and folding them
          -- together here would throw it away.
          local parsed = Gen4Anim.parse(bytes)
          for _, anim in ipairs(parsed and parsed.animations or {}) do
            local record = {
              name = anim.name, member = member, kind = parsed.kind,
              what = parsed.what, frames = anim.frames,
              joints = anim.nodes, targets = anim.targets,
            }
            -- A JOINT ANIMATION ALSO CARRIES ITS NUMBERS NOW.  The other four
            -- formats are still structure only: what they drive is named and
            -- checked, and nothing reads their values yet.
            if parsed.kind == "BTA0" then
              record.targets = nil
              record.srt = Gen4Anim.textureSrt(bytes, anim)
            elseif parsed.kind == "BTP0" then
              record.targets = nil
              record.pattern = Gen4Anim.texturePattern(bytes, anim)
            elseif parsed.kind == "BMA0" then
              record.targets = nil
              record.colour = Gen4Anim.materialColour(bytes, anim)
            elseif parsed.kind == "BVA0" then
              record.visibility = Gen4Anim.visibility(bytes, anim)
            elseif parsed.kind == "BCA0" then
              -- Decoded below, once it is known whether anything here can be
              -- posed by it.
              pending[#pending + 1] = { record = record, bytes = bytes, anim = anim }
            end
            set.animations[#set.animations + 1] = record
          end
        end
      end
    end
    -- A JOINT ANIMATION'S MATRICES ARE ONLY WRITTEN WHERE A MODEL HERE CAN
    -- WEAR THEM, which is the same pairing `Gen4Anim.resolve` checks: a joint
    -- animation names nothing, so the only thing that can claim it is a model
    -- in the same archive with that many nodes.
    --
    -- This is a size decision as much as a correctness one, and the numbers
    -- are worth recording.  `bm_anime` holds no models at all -- it is 98
    -- animations laid over map meshes that are not built yet -- and writing
    -- its joint matrices anyway cost 2.2 MB of cache for poses nothing could
    -- apply.  Its texture scrolls and flipbooks, which are what make water
    -- move, are 200 KB and are written.
    local wearable = {}
    for _, model in ipairs(set.models) do wearable[#model.nodes] = true end
    for _, item in ipairs(pending) do
      if wearable[item.anim.nodes] then
        local tracks = Gen4Anim.jointMatrices(item.bytes, item.anim)
        item.record.tracks = {}
        for _, joint in ipairs(tracks or {}) do
          local blob = Gen4Anim.packTrack(joint.track)
          local ok, why = Gen4Anim.verifyTrack(joint.track, blob)
          if not ok then
            animFailed = animFailed + 1
            self.animFailure = self.animFailure or why
          end
          item.record.tracks[#item.record.tracks + 1] =
            { index = joint.index, frames = joint.frames, matrices = blob }
        end
      else
        item.record.unworn = true
      end
    end

    out.sets[entry.out] = set
  end

  self:write("gen4_models", out)
  self.modelReport = {
    models = totalModels, shapes = totalShapes, failedRoundTrip = failed,
    reason = self.modelFailure or self.animFailure,
    failedTracks = animFailed,
  }
  return out
end

function RomExtractorGen4:run()
  self:extractText()
  self:extractSpecies()
  self:extractMoves()
  self:extractItems()
  self:extractEncounters()
  self:extractTrainers()
  local headers, names = self:extractMaps()
  local events = self:extractEvents()
  self:extractRegions(events, names)
  self:extractTilesets()
  self:extractConstants()
  self:extractOverworld()
  self:extractSpeciesSprites()
  self:extractHeights()
  self:extractField()
  self:extractScripts()
  self:linkScripts(headers, events, names)
  self:extractGraphics()
  self:extractFonts()
  -- LAST, AND THAT IS THE POINT.  The menus stage names the title art by role
  -- out of the graphics stage's own index, so it cannot run before the pictures
  -- exist -- run earlier it writes a record with every art path nil, which is a
  -- title screen that draws nothing and reports no error.
  self:extractMenus()
  self:extractIntro()
  self:extractModels()
  return self.wrote
end

-- NOT BUILT YET, and each is a seam rather than a detail:
--
--   * RomImporter has to hand this a PATH.  Its `startData` reads the whole
--     file to hash it, which is correct for verification and wrong to carry
--     into extraction at 128 MiB.
--   * A TEXT RENDERER.  The fonts and their widths are extracted now, but
--     nothing draws with them: there is no Gen 4 text box, no line breaking
--     and no colour choice per box.  That is engine work, not extraction.
--   * The sheets with no cell bank ANYWHERE in their archive -- window frames,
--     mail backgrounds, the fonts -- are still laid out at a stated width and
--     still flagged `provisionalLayout`.  Most of those are tilesets rather
--     than sprites, so a bank may not exist to find.
--   * WHAT SWITCHES A FORM.  The form pictures are all extracted now, but
--     nothing chooses between them: Castform still needs the weather, Cherrim
--     the sun, Rotom its appliance, Arceus the held plate, and Unown a letter
--     from its personality value.  That is battle and party logic rather than
--     extraction, and it is the reason `def.forms` is written but not yet read.
--   * The map meshes and the BDHC height blocks, for the same reason.
--   * A map DEFINITION per map -- the grid, the objects with their sprites
--     and positions -- so the overworld has something to load.  The script
--     pool now names every map and its objects' scripts, but nothing yet
--     builds the world those objects stand in.

return RomExtractorGen4
