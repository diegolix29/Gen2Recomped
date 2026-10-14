-- BLACK AND WHITE OUT OF THE CARTRIDGE (generation 5).
--
-- A DS cartridge, like Platinum's: a filesystem the extractor opens itself
-- (RomImporter hands it a path), every archive a NARC under /a/x/y/z. Each
-- archive below was IDENTIFIED BY LOOKING -- member counts, record sizes and
-- the records themselves -- because pokeblack names none of them yet:
--
--   /a/0/0/2  system text, 288 banks  (species 70, moves 203, items 54 ...)
--   /a/0/0/3  story text, 472 banks
--   /a/0/1/6  personal data, 669 x 0x3C (the 649 species and their forms)
--   /a/0/1/8  learnsets, 668          /a/0/1/9  evolutions, 668 x 42
--   /a/0/2/1  moves, 560 x 0x24       /a/0/2/4  items, 627 x 0x24
--   /a/0/9/2  trainers, 616 x 0x14    /a/0/9/3  their parties
--
-- The text banks were found the same way: bank 70 begins "Bulbasaur",
-- "Ivysaur", and its 495th is "Snivy"; 203 begins "Pound"; 54 "Master Ball";
-- 24 "Hardy"; 199 "Normal"; 191 "PKMN Trainer", "Youngster"; 190 the trainer
-- names (stored 9-bit compressed); 89 the places ("Nuvema Town" at 4); 235
-- the dex entries; 260 the categories ("Seed Pokemon"); 53 and 202 the item
-- and move descriptions.
--
-- WHAT RUNS TODAY is the data the battle and the menus need: text, species
-- (with learnsets and evolutions), moves, items and trainers. Maps, events,
-- scripts, encounters and every piece of art are Gen 5 formats this port has
-- not read yet, and are written to the report as not ported rather than
-- guessed at. The field will render through the Gen 4 3D ground so that it
-- shares Platinum's camera and its controls, and the second screen comes from
-- GameVersion.isDualScreen -- neither needs anything from this file.
--
-- Black and White share every path and bank here; the version exclusives are
-- in the data itself.

local NdsRom = require("src.import.NdsRom")
local Narc = require("src.import.NarcArchive")
local Text = require("src.import.Gen5Text")
local D = require("src.import.Gen5Data")
local LuaWriter = require("src.import.LuaWriter")

local X = {}
X.__index = X

X.PATH = {
  systemText = "/a/0/0/2", storyText = "/a/0/0/3",
  personal = "/a/0/1/6", learnsets = "/a/0/1/8", evolutions = "/a/0/1/9",
  moves = "/a/0/2/1", items = "/a/0/2/4",
  trainerData = "/a/0/9/2", trainerParty = "/a/0/9/3",
}
X.BANK = {
  species = 70, speciesUpper = 284, move = 203, moveUpper = 286, moveDescription = 202,
  item = 54, itemDescription = 53, nature = 24, typeName = 199, typeUpper = 287,
  trainer = 190, trainerClass = 191, mapLabel = 89, dexEntry = 235, dexCategory = 260,
}
X.STAGES = { "text", "species", "moves", "items", "trainers", "maps", "field", "constants", "encounters", "fonts", "scripts", "species_sprites" }
X.ALL_STAGES = { "text", "species", "moves", "items", "trainers", "abilities", "encounters", "maps", "events",
  "scripts", "graphics", "fonts", "overworld", "species_sprites", "trainer_sprites", "cries", "models", "field" }
X.SPECIES_COUNT = 649

-- what a finished Gen 5 import has written (RomImporter.requiredFiles)
X.REQUIRED_FILES = {
  "data/generated/text.lua", "data/generated/text_pointers.lua", "data/generated/pokemon.lua",
  "data/generated/moves.lua", "data/generated/items.lua", "data/generated/trainers.lua",
  "data/generated/gen5_version.lua",
}

function X.new(romPath, version, manifest, progress)
  local rom, err = NdsRom.open(romPath)
  if not rom then return nil, err end
  return setmetatable({ rom = rom, version = version, manifest = manifest, progress = progress,
    stage = 0, wrote = {}, _archives = {}, _banks = {} }, X)
end

function X:close() if self.rom then self.rom:close() end self.rom = nil end

function X:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, #X.STAGES, name, 0, 1) end
end

function X:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
  self.wrote[#self.wrote + 1] = name
end

function X:archive(key)
  if self._archives[key] then return self._archives[key] end
  local path = X.PATH[key]
  local bytes = path and self.rom:read(path)
  if not bytes then return nil, ("no %s in the cartridge"):format(tostring(path)) end
  local arc = Narc.parse(bytes)
  self._archives[key] = arc
  return arc
end

function X:bank(n)
  if self._banks[n] ~= nil then return self._banks[n] end
  local arc = self:archive("systemText")
  local b = arc and Text.bank(arc:get(n)) or false
  self._banks[n] = b
  return b or nil
end
function X:string(bankId, index)
  local b = self:bank(bankId)
  return b and b[index]
end

-- every bank of both archives, and the flat labels the engine reads
function X:extractText()
  self:beginStage("text")
  local out, flat, strings = { system = {}, story = {} }, {}, 0
  for _, which in ipairs({ "system", "story" }) do
    local arc = assert(self:archive(which .. "Text"))
    for b = 0, arc.count - 1 do
      local bank = Text.bank(arc:get(b))
      if bank then
        out[which][b] = bank
        for i, s in pairs(bank) do
          flat[Text.label(which, b, i)] = s
          -- a map script's lines are its zone's STORY bank, looked up by the
          -- Gen 4 script engine as TEXT_B<bank>_<entry> -- so the story banks
          -- answer to that spelling too
          if which == "story" then flat[("TEXT_B%04d_%05d"):format(b, i)] = s end
          strings = strings + 1
        end
      end
    end
  end
  self:write("gen5_text", out)
  self:write("text", flat)
  self:write("text_pointers", {})
  self.textReport = { strings = strings }
  return out
end

function X:extractSpecies()
  self:beginStage("species")
  local personal = assert(self:archive("personal"))
  local learn = assert(self:archive("learnsets"))
  local evo = assert(self:archive("evolutions"))
  local out = {}
  for id = 0, X.SPECIES_COUNT do
    local p = D.personal(personal:get(id))
    if p then
      p.id, p.dex = id, id
      p.name = self:string(X.BANK.species, id)
      p.learnset = D.learnset(learn:get(id))
      p.evolutions = D.evolutions(evo:get(id))
      p.dexEntry = self:string(X.BANK.dexEntry, id)
      p.category = self:string(X.BANK.dexCategory, id)
      out[id] = p
    end
  end
  -- the extra forms past the species, by index (Gen 5's form table)
  local forms = {}
  for id = X.SPECIES_COUNT + 1, personal.count - 1 do forms[id] = D.personal(personal:get(id)) end
  self:write("pokemon", out)
  self:write("gen5_forms", forms)
  self._pokemon = out
  return out
end

function X:extractMoves()
  self:beginStage("moves")
  local arc = assert(self:archive("moves"))
  local out = {}
  for id = 0, arc.count - 1 do
    local m = D.move(arc:get(id))
    if m then
      m.id = id
      m.name = self:string(X.BANK.move, id)
      m.description = self:string(X.BANK.moveDescription, id)
      out[id] = m
    end
  end
  self:write("moves", out)
  return out
end

function X:extractItems()
  self:beginStage("items")
  local arc = assert(self:archive("items"))
  local out = {}
  for id = 0, arc.count - 1 do
    local it = D.item(arc:get(id))
    if it then
      it.id = id
      it.name = self:string(X.BANK.item, id)
      it.description = self:string(X.BANK.itemDescription, id)
      out[id] = it
    end
  end
  -- THE MACHINES' MOVES: a flat u16 table in the ARM9 (0x9AAA0 in Black),
  -- TM01..TM92, HM01..HM06, TM93..TM95, then 0 -- the order of the item ids
  -- 328..419, 420..425 and 618..620. Found by its first five moves (Hone
  -- Claws, Dragon Claw, Psyshock, Calm Mind, Roar). Stamped as `machine`,
  -- the record the TM name buffer and the bag read (Platinum's one run of
  -- ids does not hold here, so ItemEffects' join cannot place them).
  local arm9 = self.rom:arm9()
  local at = arm9 and arm9:find(string.char(0xD4, 0x01, 0x51, 0x01, 0xD9, 0x01, 0x5B, 0x01, 0x2E, 0x00), 1, true)
  if at then
    local ids = {}
    for id = 328, 425 do ids[#ids + 1] = id end
    for id = 618, 620 do ids[#ids + 1] = id end
    for k, id in ipairs(ids) do
      local o = at + (k - 1) * 2
      local move = arm9:byte(o) + arm9:byte(o + 1) * 256
      if move > 0 and out[id] then
        out[id].machine = { move = move, index = k - 1, hm = (k > 92 and k <= 98) or nil }
      end
    end
  end
  self:write("items", out)
  return out
end

function X:extractTrainers()
  self:beginStage("trainers")
  local data, party = assert(self:archive("trainerData")), assert(self:archive("trainerParty"))
  local out = {}
  for id = 0, data.count - 1 do
    local tr = D.trainer(data:get(id))
    if tr then
      tr.id = id
      tr.name = self:string(X.BANK.trainer, id)
      tr.className = self:string(X.BANK.trainerClass, tr.class)
      tr.party = D.party(party:get(id), tr)
      out[id] = tr
    end
  end
  self:write("trainers", out)
  -- WHAT EACH TRAINER SAYS: Platinum's two-file index in the same shape --
  -- /a/0/9/0 the flat { u16 trainer, u16 type } records (1,762, one per line
  -- of system bank 189) and /a/0/9/1 one u16 byte offset per trainer (616).
  -- Gen4TrainerMessages' walk reaches all 1,762 with no duplicates; types
  -- 0 / 1 / 2 are the challenge, the defeat and the after-battle line as on
  -- Platinum (Waiter Maxwell: "Welcome to Striaton Gym!", "Yow!", ...).
  local Narc = require("src.import.NarcArchive")
  local tblBytes, ofsBytes = self.rom:read("/a/0/9/0"), self.rom:read("/a/0/9/1")
  local tbl, ofs = tblBytes and Narc.parse(tblBytes), ofsBytes and Narc.parse(ofsBytes)
  if tbl and ofs then
    local index = require("src.import.Gen4TrainerMessages").all(tbl:get(0), ofs:get(0))
    self:write("gen4_trainer_messages", index)
  end
  return out
end

-- Pictures and side-car binaries go where Gen 4's do (CacheFs, under the
-- version's own prefix), so the Gen 4 renderer finds them by the same paths.
function X:saveImage(relative, image, extra)
  if not image then return nil end
  local ImageWriter = require("src.import.ImageWriter")
  local data = ImageWriter.fromRGBA8(image.width, image.height, image.rgba)
  if not data then return nil end
  local path = "assets/generated/gen4/" .. relative .. ".png"
  ImageWriter.save(data, path)
  local entry = { path = path, width = image.width, height = image.height }
  for k, v in pairs(extra or {}) do entry[k] = v end
  return entry
end

function X:saveBinary(relative, bytes)
  local path = "assets/generated/gen4/" .. relative
  local ok, why = require("src.import.CacheFs").write(path, bytes)
  if not ok then error("could not write " .. path .. ": " .. tostring(why)) end
  return path
end

-- THE FIELD, as Gen4Ground reads it (src/import/Gen5Field.lua): zones as map
-- headers, the matrices, every chunk's model and permissions, the texture
-- sets, and a map def per zone -- plus the stand-in tileset and an empty
-- script pool, which the Gen 4 loader requires of a cache of this shape.
function X:extractField()
  self:beginStage("field")
  local out, report = require("src.import.Gen5Field").build(self, {
    image = function(rel, image, extra) return self:saveImage(rel, image, extra) end,
    binary = function(rel, bytes) return self:saveBinary(rel, bytes) end,
  })
  self:write("gen4_map_headers", out.headers)
  self:write("gen4_map_matrices", out.matrices)
  self:write("gen4_map_permissions", out.permissions)
  self:write("map_layouts", out.layouts)
  self:write("maps", out.maps)
  self:write("gen5_rails", out.rails or {})
  self:write("gen4_terrain", out.terrain)
  self:write("gen5_zones", out.zones)
  self:write("gen4_models", out.models)
  self:write("sprites", out.sprites)
  self:write("gen5_sprite_table", out.spriteTable)
  -- the player: sprite id 1 is Hilbert (32 frames, walk then run); the field
  -- record says which sheet the player wears, as Platinum's does
  local hero = out.spriteTable[1] and ("SPRITE_G4_%03d"):format(out.spriteTable[1])
  if hero and out.sprites[hero] then
    -- WHERE A NEW GAME STARTS. The new-game location setter (ARM9 0x2014204)
    -- is called with zone 391, the player's room, and takes the standing
    -- spot from that zone's header (+0x24 / +0x2C, Gen5Maps' spawnX / Z) with
    -- facing 2 -- "left" in Gen 4's order (BW's own direction enum is not yet
    -- confirmed). The first blackout point is the floor below (zone 390's own
    -- spot). BW's intro is not ported, so a new game opens in the room.
    local room, below = out.zones and out.zones[391], out.zones and out.zones[390]
    local boot = room and {
      startMap = "Z391", startX = room.spawnX, startY = room.spawnZ, startFacing = "left",
      lastHeal = below and { map = "Z390", x = below.spawnX, y = below.spawnZ } or nil,
      screens = { splash = "Gen4Intro", title = "Gen4Title", newGame = false, options = "Gen4Options" },
    } or nil
    self:write("field", { source = "ROM:" .. tostring(self.version), boot = boot,
      playerSprites = { walk = hero }, playerForms = { order = { "boy" }, boy = { label = "BOY", walk = hero } } })
  end
  local Tileset = require("src.import.Gen4Tileset")
  self:write("map_tilesets", { [Tileset.PRIMARY_ID] = Tileset.primary() })
  self:write("tilesets", { [Tileset.ID] = Tileset.pair() })
  self:saveImage("tileset/standin", Tileset.atlas(), { key = true })
  -- the script pool (Gen5ScriptLink), once the scripts stage has the widths
  local pool, linkReport = { source = "RomExtractorGen4", scripts = {}, maps = {}, bands = {} }, nil
  local scriptBytes = self._scriptWidths and self.rom:read("/a/0/5/7")
  if scriptBytes then
    local Link = require("src.import.Gen5ScriptLink")
    self._scriptBands = self._scriptBands or Link.findBands(self.rom)
    pool, linkReport = Link.pool(Narc.parse(scriptBytes),
      self._scriptWidths, out.zones, out.maps, self._scriptBands)
  end
  self:write("map_scripts", pool)
  self.linkReport = linkReport
  self.fieldReport = report
  return out
end

-- CONSTANTS, the part of the Gen 4 table that is not Sinnoh's: the types
-- (bank 199) and natures (bank 24), the growth curves -- /a/0/1/7, eight
-- members of 404 bytes, 101 u32 apiece, the shape of Gen 4's growth table,
-- and its first six in the same order (medium slow reaches 1,059,860) -- and
-- Unova's eight badges. The message window is Gen 4's rectangle until Black
-- and White's own is identified.
X.GROWTH = { "MEDIUM_FAST", "ERRATIC", "FLUCTUATING", "MEDIUM_SLOW", "FAST", "SLOW" }
X.BADGES = { "TRIO", "BASIC", "INSECT", "BOLT", "QUAKE", "JET", "FREEZE", "LEGEND" }
function X:extractConstants()
  self:beginStage("constants")
  local function order(n) local t = {} for i = 1, n do t[i] = i end return t end
  local types, natures = {}, {}
  for i = 0, 16 do types[i] = self:string(X.BANK.typeName, i) or D.TYPES[i] end
  for i = 0, 24 do natures[i + 1] = self:string(X.BANK.nature, i) end
  local curves
  local bytes = self.rom:read("/a/0/1/7")
  local growth = bytes and Narc.parse(bytes)
  if growth then
    curves = {}
    for i, name in ipairs(X.GROWTH) do
      local m = growth:get(i - 1)
      if m and #m >= 404 then
        local curve = {}
        for level = 0, 100 do
          local a, b, c, d = m:byte(level * 4 + 1, level * 4 + 4)
          curve[level + 1] = a + b * 256 + c * 65536 + d * 16777216
        end
        curves[name] = curve
      end
    end
  end
  local badges = {}
  for i, id in ipairs(X.BADGES) do badges[i] = { id = "BADGE_" .. id } end
  local constants = {
    gen = 5, generation = 5, family = "bw",
    experienceTables = curves, badges = badges,
    types = types, typeCount = 17, natures = natures,
    natureOrder = order(25), speciesOrder = order(X.SPECIES_COUNT),
    gen4MessageWindow = { left = 2, top = 19, width = 27, height = 4, source = "Gen 4's rectangle" },
    gen4Screen = { width = 256, height = 192 },
    world = { blockPx = 16, stepFrames = 8, runStepFrames = 4 },
    source = ("ROM:%s (types bank %d, natures bank %d, curves /a/0/1/7)")
      :format(tostring(self.version), X.BANK.typeName, X.BANK.nature),
  }
  -- the flags and vars a new game opens with (Gen5ScriptLink.newGame)
  local scriptBytes = self.rom:read("/a/0/5/7")
  local scriptArc = scriptBytes and Narc.parse(scriptBytes)
  if scriptArc then
    local Link = require("src.import.Gen5ScriptLink")
    local derived = require("src.import.Gen5ScriptOps").derive(self.rom, scriptArc)
    self._scriptBands = self._scriptBands or Link.findBands(self.rom)
    constants.gen4NewGame = derived and Link.newGame(scriptArc, derived.widths, self._scriptBands) or nil
    -- 0x232's table: Nimbasa's park visitor, by season x 2 + badges
    constants.gen5ParkVisitors = derived and require("src.import.Gen5ScriptOps").handlerTable(self.rom, derived, 0x232, 16) or nil
  end
  self:write("constants", constants)
  return constants
end

-- THE TYPE CHART: a 17 x 17 byte table, attacker by defender in Gen 5's type
-- order (Gen5Data.TYPES), each byte 0 / 2 / 4 / 8 for x0 / x0.5 / x1 / x2.
-- Found by its Normal row -- neutral but x0.5 against Rock and Steel and x0
-- against Ghost -- with Fighting's x2 against Normal under it, and every one of
-- the 289 bytes one of the four values (overlay 93 in Black). Written in the
-- Gen 4 chart's shape: the non-neutral matchups, multipliers in tenths.
function X.findTypeChart(bytes)
  local ok = { [0] = true, [2] = true, [4] = true, [8] = true }
  for i = 1, #bytes - 289 do
    if bytes:byte(i) == 4 and bytes:byte(i + 5) == 2 and bytes:byte(i + 7) == 0
       and bytes:byte(i + 8) == 2 and bytes:byte(i + 17) == 8 then
      local good = true
      for k = 0, 288 do if not ok[bytes:byte(i + k)] then good = false break end end
      if good then return i - 1 end
    end
  end
  return nil
end

function X:extractTypeChart()
  local found, overlay, at
  for o = 0, 160 do
    local okRead, b = pcall(function() return self.rom:overlay(o) end)
    if okRead and b and #b > 289 then
      local p = X.findTypeChart(b)
      if p then found, overlay, at = b, o, p break end
    end
  end
  if not found then return nil end
  local TENTHS = { [0] = 0, [2] = 5, [4] = 10, [8] = 20 }
  local out = { matchups = {}, types = {}, ids = {},
                source = ("ROM:%s overlay %d+0x%X, 17x17"):format(tostring(self.version), overlay, at) }
  for i = 0, 16 do
    local name = D.TYPES[i]
    out.ids[name] = i
    out.types[name] = { name = name }
  end
  for a = 0, 16 do
    for d = 0, 16 do
      local v = found:byte(at + a * 17 + d + 1)
      if v ~= 4 then
        out.matchups[#out.matchups + 1] = { attacker = D.TYPES[a], defender = D.TYPES[d], multiplier = TENTHS[v] }
      end
    end
  end
  self:write("type_chart", out)
  self.typeChartReport = { overlay = overlay, at = at, matchups = #out.matchups }
  return out
end

function X:extractEncounters()
  self:beginStage("encounters")
  local bytes = self.rom:read("/a/1/2/6")
  local out = bytes and require("src.import.Gen5Encounters").all(Narc.parse(bytes)) or {}
  self:write("encounters", out)
  return out
end

-- THE FONT (/a/0/2/3 member 0, the 12 x 15 message font; Gen5Font), as the
-- `font` table Gen 4's writer makes: one sheet, the measured widths, and a
-- charmap from glyph code to UTF-8 -- the Gen 5 text banks are UTF-16, which
-- Gen5Text renders straight to UTF-8, so the code map IS the charmap.
function X:extractFont()
  self:beginStage("fonts")
  local bytes = self.rom:read("/a/0/2/3")
  local arc = bytes and Narc.parse(bytes)
  local F = require("src.import.Gen5Font")
  local font = arc and F.parse(arc:get(0))
  if not font then return nil end
  local sheet = F.sheet(font, { columns = 32 })
  local entry = sheet and self:saveImage("font/font_message_sheet", sheet,
    { glyphs = font.numGlyphs, glyphWidth = font.pixelWidth, glyphHeight = font.pixelHeight, columns = 32 })
  local widths = {}
  for i = 0, font.numGlyphs - 1 do widths[i + 1] = font.widths[i] end
  local page = { image = entry and entry.path or nil, base = 1, glyphsPerRow = 32,
                 glyphWidth = font.pixelWidth, glyphHeight = font.pixelHeight,
                 advance = font.maxWidth, widths = widths, preTinted = true }
  local def = { pages = { message = page }, charmap = F.charmap(font, 1), frame = "drawn",
                source = ("ROM:%s /a/0/2/3[0] NFTR (%d glyphs, %dx%d)")
                  :format(tostring(self.version), font.numGlyphs, font.pixelWidth, font.pixelHeight) }
  self:write("font", def)
  return def
end

-- SCRIPTS (Gen5ScriptOps): the command widths derived from the cartridge's own
-- handlers, and every script file's entry points. What the commands MEAN is
-- not identified yet, so nothing is lowered; this is the decode the lowering
-- will stand on.
function X:extractScripts()
  self:beginStage("scripts")
  local Ops = require("src.import.Gen5ScriptOps")
  local Script = require("src.import.Gen4Script")
  local bytes = self.rom:read("/a/0/5/7")
  local arc = bytes and Narc.parse(bytes)
  if not arc then return nil end
  local derived = Ops.derive(self.rom, arc)
  if not derived then return nil end
  local files, blocks, clean = {}, 0, 0
  for m = 0, arc.count - 1 do
    local d = arc:get(m)
    local entries = Script.entries(d)
    files[m] = entries
    for _, at in ipairs(entries) do
      blocks = blocks + 1
      local _, why = Ops.decode(d, at, derived.widths)
      if why == "end" then clean = clean + 1 end
    end
  end
  local out = { widths = derived.widths, offset = derived.offset, table = derived.table,
                entries = files, report = { entries = blocks, clean = clean,
                  secondBestOffset = derived.report.secondBest } }
  self:write("gen5_scripts", out)
  self.scriptReport = out.report
  self._scriptWidths = derived.widths
  return out
end

-- THE BATTLE PICTURES (src/import/Gen5BattleSprites.lua): every species'
-- front, back, shiny and female stills, stamped on its species row the way
-- Platinum's are, then the species module written again with them
function X:extractBattleSprites()
  self:beginStage("species_sprites")
  local index = require("src.import.Gen5BattleSprites").build(self)
  self:write("gen4_species_sprites", index)
  if self._pokemon then self:write("pokemon", self._pokemon) end
  self.battleSpriteReport = index.counts
  -- ...and the battle's own interface (src/import/Gen5BattleUi.lua)
  local ui = require("src.import.Gen5BattleUi").build(self)
  if ui then self:write("gen5_battle_ui", ui) end
end

function X:run()
  self:extractConstants()
  self:extractScripts()
  self:extractFont()
  self:extractTypeChart()
  self:extractEncounters()
  self:extractText()
  self:extractSpecies()
  self:extractMoves()
  self:extractItems()
  self:extractTrainers()
  self:extractField()
  self:extractBattleSprites()
  local skipped = {}
  for _, name in ipairs(X.ALL_STAGES) do
    local done = false
    for _, n in ipairs(X.STAGES) do if n == name then done = true end end
    if not done then skipped[#skipped + 1] = name end
  end
  self.notPorted = skipped
  self:write("gen5_version", { version = self.version, family = "bw", stages = X.STAGES, notPorted = skipped,
                               scriptBands = self._scriptBands })
  return self.wrote
end

return X
