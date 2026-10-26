-- Gen4Save -- the Platinum and HeartGold/SoulSilver battery codec.
--
-- A Gen 4 save is two partitions of 256 KiB (0x00000 and 0x40000), each
-- holding a GENERAL block (trainer, party, bag, flags, the dex, the field
-- state) and a STORAGE block (the eighteen PC boxes), each with a footer the
-- cartridge validates: the save counter, the block size, the 0x20060623
-- signature, the block id and a CRC16 of everything before the footer.
-- Whichever partition holds the higher counter is current, per block.
--
-- Offsets are pokeplatinum / pokeheartgold's structs as PKHeX lays them out
-- (SAV4Pt.cs, SAV4HGSS.cs, the bag and dex classes) -- see LAYOUT below.
--
-- An import keeps the whole image as `save.rawImport`, and an export writes
-- the port's state ONTO it, so every system the port does not model (the
-- Underground, the Frontier, mail, ribbons, Hall of Fame) survives a round
-- trip. A playthrough begun in the port gets a blank image built for it the
-- way the cartridge's own Init functions would leave one.

local NdsSave = require("src.save_convert.NdsSave")

local Gen4Save = {}

Gen4Save.SAVE_SIZE = NdsSave.SIZE
Gen4Save.PARTITION = 0x40000
Gen4Save.SIGNATURE = 0x20060623
Gen4Save.DEX_MAGIC = 0xBEEFCAFE

local LAYOUT = {
  pt = {
    generalSize = 0xCF2C, storageOffset = 0xCF2C, storageSize = 0x121E4, footer = 0x14,
    trainer = 0x68, party = 0xA0, bag = 0x630,
    pockets = { -- fieldPocket -> { offset, slots }
      [0] = { 0x000, 165 }, [7] = { 0x294, 50 }, [3] = { 0x35C, 100 }, [5] = { 0x4EC, 12 },
      [1] = { 0x51C, 40 }, [4] = { 0x5BC, 64 }, [2] = { 0x6BC, 15 }, [6] = { 0x6F8, 30 },
    },
    vars = 0xDAC, varCount = 0x120, flags = 0xFEC, flagCount = 2912,
    poketch = 0x1160, location = 0x1280, rival = 0x27E8, posMirror = 0x287E,
    dex = 0x1328, dexObtained = 0x318, dexNational = 0x319, dexLanguages = 0x128,
    daycare = 0x1654,
    boxBase = 4, boxStride = 0xFF0, currentBox = 0, boxNames = 4 + 18 * 0xFF0,
    gameIds = { platinum = 12 }, trainerFlagBase = 0x550,
  },
  hgss = {
    generalSize = 0xF628, storageOffset = 0xF700, storageSize = 0x12310, footer = 0x10,
    trainer = 0x64, party = 0x98, bag = 0x644,
    pockets = {
      [0] = { 0x000, 165 }, [7] = { 0x294, 50 }, [3] = { 0x35C, 101 }, [5] = { 0x4F0, 12 },
      [1] = { 0x520, 40 }, [4] = { 0x5C0, 64 }, [2] = { 0x6C0, 24 }, [6] = { 0x720, 30 },
    },
    vars = 0xDE4, varCount = 0x170, flags = 0x10C4, flagCount = 2912,
    location = 0x1234, rival = 0x22D4, posMirror = 0x236E,
    dex = 0x12B8, dexObtained = 0x336, dexNational = 0x337, dexLanguages = 0x144,
    daycare = 0x15FC,
    boxBase = 0, boxStride = 0x1000, currentBox = 18 * 0x1000, boxNames = 0x12008,
    gameIds = { heartgold = 7, soulsilver = 8 }, trainerFlagBase = 0x550,
  },
}
Gen4Save.LAYOUT = LAYOUT

local BOXES, BOX_SLOTS = 18, 30
local PARTY_SIZE = NdsSave.PARTY4

local function familyOf(version)
  if version == "heartgold" or version == "soulsilver" then return "hgss" end
  local okG, GameVersion = pcall(require, "src.core.GameVersion")
  if okG and GameVersion.VERSIONS and GameVersion.VERSIONS[version or ""] then
    local fam = (GameVersion.VERSIONS[version] or {}).family
    if fam == "hgss" then return "hgss" end
  end
  return "pt"
end
Gen4Save.familyOf = familyOf

-- ----------------------------------------------------------------- blocks --
local function footerAt(L, start, size) return start + size - L.footer end

local function blockValid(buf, L, start, size, id)
  local f = footerAt(L, start, size)
  if L.footer == 0x14 then
    if buf:u32(f + 8) ~= size or buf:u32(f + 12) ~= Gen4Save.SIGNATURE or buf:u8(f + 16) ~= id then return false end
    return NdsSave.crc16(buf, start, size - L.footer) == buf:u16(f + 18)
  end
  if buf:u32(f + 4) ~= size or buf:u32(f + 8) ~= Gen4Save.SIGNATURE or buf:u16(f + 12) ~= id then return false end
  return NdsSave.crc16(buf, start, size - L.footer) == buf:u16(f + 14)
end

local function counters(buf, L, start, size)
  local f = footerAt(L, start, size)
  if L.footer == 0x14 then return buf:u32(f), buf:u32(f + 4) end
  return buf:u32(f), 0
end

-- the newer valid copy of one block: returns its partition base (0 / 0x40000)
local function pickBlock(buf, L, offset, size, id)
  local best, bestA, bestB
  for _, part in ipairs({ 0, Gen4Save.PARTITION }) do
    local start = part + offset
    if blockValid(buf, L, start, size, id) then
      local a, b = counters(buf, L, start, size)
      local newer = best == nil
      if not newer then
        -- 0xFFFFFFFF is the counter before a first save, and wraps past 0
        if a ~= bestA then
          newer = (a > bestA and not (a == 4294967295 and bestA == 0)) or (a == 0 and bestA == 4294967295)
        else newer = b > bestB end
      end
      if newer then best, bestA, bestB = part, a, b end
    end
  end
  return best, bestA, bestB
end

function Gen4Save.readBlocks(bytes, family)
  local L = LAYOUT[family]
  local buf = NdsSave.buffer(bytes)
  local g, gA, gB = pickBlock(buf, L, 0, L.generalSize, 0)
  local s, sA, sB = pickBlock(buf, L, L.storageOffset, L.storageSize, 1)
  if not g then return nil, "neither copy of the save's general block is intact (checksum)" end
  if not s then return nil, "neither copy of the save's PC box block is intact (checksum)" end
  return { buf = buf, L = L, general = g, storage = s + L.storageOffset,
    counter = math.max(gA, sA), blockCounters = { gB, sB } }
end

-- write the general and storage blocks (already in buf at blocks.general /
-- blocks.storage) to BOTH partitions with fresh footers: two identical
-- copies leave the cartridge nothing to disagree about
local function writeFooters(buf, L, start, size, id, counter, blockCounter)
  local f = footerAt(L, start, size)
  if L.footer == 0x14 then
    buf:set32(f, counter); buf:set32(f + 4, blockCounter); buf:set32(f + 8, size)
    buf:set32(f + 12, Gen4Save.SIGNATURE); buf:set8(f + 16, id); buf:set8(f + 17, 0)
    buf:set16(f + 18, NdsSave.crc16(buf, start, size - L.footer))
  else
    buf:set32(f, counter); buf:set32(f + 4, size); buf:set32(f + 8, Gen4Save.SIGNATURE)
    buf:set16(f + 12, id); buf:set16(f + 14, NdsSave.crc16(buf, start, size - L.footer))
  end
end

local function commit(blocks, counter)
  local buf, L = blocks.buf, blocks.L
  local gSrc, sSrc = blocks.general, blocks.storage
  for _, part in ipairs({ 0, Gen4Save.PARTITION }) do
    if part ~= gSrc then buf:copy(part, gSrc, L.generalSize) end
    local sDst = part + L.storageOffset
    if sDst ~= sSrc then buf:copy(sDst, sSrc, L.storageSize) end
  end
  for _, part in ipairs({ 0, Gen4Save.PARTITION }) do
    writeFooters(buf, L, part, L.generalSize, 0, counter, (blocks.blockCounters[1] or 0) + 1)
    writeFooters(buf, L, part + L.storageOffset, L.storageSize, 1, counter, (blocks.blockCounters[2] or 0) + 1)
  end
  return buf:string()
end

-- ---------------------------------------------------------- the crosswalk --
local function context(data, family, version, player)
  local ctx = { gen = 4, family = family, data = data, language = 2,
    gameId = LAYOUT[family].gameIds[version] or (family == "hgss" and 7 or 12),
    player = player or {} }
  local font = data.font or {}
  ctx.text = NdsSave.textCodec(4, font)
  local okA, Gen4Abilities = pcall(require, "src.import.Gen4Abilities")
  ctx.abilityByName = {}
  if okA and Gen4Abilities.NAMES then
    for id, name in pairs(Gen4Abilities.NAMES) do ctx.abilityByName[name] = id end
  end
  local constants = data.constants or {}
  ctx.natureOrder = constants.natureOrder
  ctx.natureIndex = {}
  for i, n in ipairs(constants.natureOrder or {}) do ctx.natureIndex[n] = i - 1 end
  local okF, Forms = pcall(require, "src.pokemon.Gen4Forms")
  if okF and Forms.definition then ctx.formDefinition = Forms.definition end
  local okG, Growth = pcall(require, "src.pokemon.Growth")
  ctx.levelFor = function(def, exp)
    if not (okG and def and Growth.levelForExp) then return 1 end
    local ok, lv = pcall(Growth.levelForExp, def.growthRate, exp)
    return ok and lv or 1
  end
  local okS, Stats = pcall(require, "src.pokemon.Stats")
  ctx.statsFor = function(def, mon)
    if not (okS and def) then return nil end
    return Stats.calc(def, mon.level or 1, mon.ivs, nil, mon.evs, mon.nature)
  end
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  ctx.genderOf = function(mon)
    if okP and Pokemon.genderOf then
      local ok, g = pcall(Pokemon.genderOf, data, mon)
      if ok then return g end
    end
  end
  return ctx
end
Gen4Save.context = context

local function readText(buf, off, n, ctx)
  local words = {}
  for i = 0, n - 1 do words[i + 1] = buf:u16(off + i * 2) end
  return ctx.text.decode(words)
end
local function writeText(buf, off, n, s, ctx)
  local words = ctx.text.encode(s or "", n - 1)
  for i = 0, n - 1 do
    local v = words[i + 1]
    if v == nil then v = (i == #words) and 0xFFFF or 0 end
    buf:set16(off + i * 2, v)
  end
end

-- map header id + cartridge tiles <-> the port's map id + local tiles
local function mapIndex(data)
  local byHeader = {}
  for id, m in pairs(data.maps or {}) do
    if type(m) == "table" and m.header then
      local list = byHeader[m.header] or {}
      list[#list + 1] = { id = id, x = tonumber(m.originX) or 0, y = tonumber(m.originY) or 0,
        w = tonumber(m.width) or 0, h = tonumber(m.height) or 0 }
      byHeader[m.header] = list
    end
  end
  return byHeader
end
Gen4Save.mapIndex = mapIndex

function Gen4Save.portLocation(data, header, gx, gz)
  local list = mapIndex(data)[header]
  if not list then return nil end
  table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
  local pick = list[1]
  for _, m in ipairs(list) do
    if gx >= m.x and gx < m.x + math.max(1, m.w) and gz >= m.y and gz < m.y + math.max(1, m.h) then pick = m break end
  end
  return pick.id, gx - pick.x, gz - pick.y
end

function Gen4Save.cartLocation(data, mapId, x, y)
  local m = (data.maps or {})[mapId]
  if not (type(m) == "table" and m.header) then return nil end
  return m.header, (tonumber(m.originX) or 0) + (tonumber(x) or 0), (tonumber(m.originY) or 0) + (tonumber(y) or 0)
end

local FACING = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
local FACING_ID = { up = 0, down = 1, left = 2, right = 3 }
Gen4Save.FACING, Gen4Save.FACING_ID = FACING, FACING_ID

-- ----------------------------------------------------------------- decode --
function Gen4Save.decode(bytes, data, version)
  local family = familyOf(version)
  local blocks, err = Gen4Save.readBlocks(bytes, family)
  if not blocks then error(err) end
  local buf, L = blocks.buf, blocks.L
  local G, S = blocks.general, blocks.storage
  local T = G + L.trainer
  local ctx = context(data, family, version)
  local warnings = {}

  local player = {
    name = readText(buf, T, 8, ctx),
    id = buf:u16(T + 0x10),
    secretId = buf:u16(T + 0x12),
    gender = buf:u8(T + 0x18) == 1 and "girl" or "boy",
    rival = readText(buf, G + L.rival, 8, ctx),
  }
  ctx.player = player
  if player.name == "" and buf:u16(T + 0x22) == 0 and buf:u8(T + 0x24) == 0 then
    error("this save has no adventure in it yet (start a game and save first)", 0)
  end
  local save = {
    meta = { format = "gen4_import" },
    version = version,
    player = player,
    money = buf:u32(T + 0x14),
    coins = buf:u16(T + 0x20),
    playTime = buf:u16(T + 0x22) * 3600 + buf:u8(T + 0x24) * 60 + buf:u8(T + 0x25),
    inventory = {}, bagOrder = {},
    flags = {}, gen4Vars = {}, gen4TrainerFlags = {},
    badges = {},
    party = {}, boxes = {},
    pokedex = { seen = {}, owned = {} },
    ndsLanguage = buf:u8(T + 0x19),
  }
  if player.rival == "" then player.rival = nil end

  -- badges: the eight Johto (or Sinnoh) bits, and HGSS's eight Kanto ones
  local badgeRows = (data.constants or {}).badges or {}
  local bits = buf:u8(T + 0x1A) + (family == "hgss" and buf:u8(T + 0x1F) * 256 or 0)
  for i, row in ipairs(badgeRows) do
    if math.floor(bits / 2 ^ (i - 1)) % 2 == 1 then
      local id = type(row) == "table" and row.id or row
      save.badges[id] = true
      save.inventory[id] = 1
    end
  end
  local progress = buf:u8(T + 0x1D)
  if progress % 2 == 1 then save.ndsGameClear = true end

  -- party
  local count = buf:u8(G + L.party - 4)
  for i = 0, math.min(6, count) - 1 do
    local canon, ok = NdsSave.decryptPkm(buf:sub(G + L.party + i * PARTY_SIZE, PARTY_SIZE))
    if not ok then warnings[#warnings + 1] = ("party slot %d failed its checksum"):format(i + 1) end
    local mon = NdsSave.decodeMon(canon, ctx, true)
    if mon then save.party[#save.party + 1] = mon end
  end

  -- boxes
  save.currentBox = buf:u8(S + L.currentBox) + 1
  for b = 0, BOXES - 1 do
    local box = { name = readText(buf, S + L.boxNames + b * 40, 20, ctx) }
    for slot = 0, BOX_SLOTS - 1 do
      local at = S + L.boxBase + b * L.boxStride + slot * NdsSave.STORED
      local canon, ok = NdsSave.decryptPkm(buf:sub(at, NdsSave.STORED))
      local mon = NdsSave.decodeMon(canon, ctx, false)
      if mon then
        if not ok then warnings[#warnings + 1] = ("box %d slot %d failed its checksum"):format(b + 1, slot + 1) end
        box[#box + 1] = mon
      end
    end
    save.boxes[b + 1] = box
  end

  -- bag, pocket by pocket in the cartridge's own order
  for pocket = 0, 7 do
    local p = L.pockets[pocket]
    for i = 0, p[2] - 1 do
      local at = G + L.bag + p[1] + i * 4
      local id, n = buf:u16(at), buf:u16(at + 2)
      if id ~= 0 and n > 0 then
        save.inventory[id] = (save.inventory[id] or 0) + n
        save.bagOrder[#save.bagOrder + 1] = id
      end
    end
  end

  -- flags (trainer defeats are a bank inside the same array) and vars
  local trainerCount = 0
  for id in pairs(data.trainers or {}) do
    if type(id) == "number" and id > trainerCount then trainerCount = id end
  end
  for i = 1, L.flagCount - 1 do
    local byte = buf:u8(G + L.flags + math.floor(i / 8))
    if math.floor(byte / 2 ^ (i % 8)) % 2 == 1 then
      save.flags[("FLAG_G4_%04X"):format(i)] = true
      local tr = i - L.trainerFlagBase
      if tr > 0 and tr <= trainerCount then save.gen4TrainerFlags[tr] = true end
    end
  end
  for i = 0, L.varCount - 1 do
    local v = buf:u16(G + L.vars + i * 2)
    if v ~= 0 then save.gen4Vars[0x4000 + i] = v end
  end

  -- the Pokedex
  local D = G + L.dex
  local maxSpecies = 493
  for sp = 1, maxSpecies do
    local byte, bitn = math.floor((sp - 1) / 8), (sp - 1) % 8
    if math.floor(buf:u8(D + 4 + byte) / 2 ^ bitn) % 2 == 1 then save.pokedex.owned[sp] = true end
    if math.floor(buf:u8(D + 0x44 + byte) / 2 ^ bitn) % 2 == 1 then save.pokedex.seen[sp] = true end
  end
  if buf:u8(D + L.dexObtained) ~= 0 then save.flags.ENGINE_POKEDEX = true end
  if buf:u8(D + L.dexNational) ~= 0 or math.floor(progress / 2) % 2 == 1 then save.pokedex.national = true end

  -- Platinum's Pokétch: enabled bit and the registered apps
  if L.poketch then
    local P = G + L.poketch
    local packed = buf:u8(P)
    local poketch = { registered = {} }
    if packed % 2 == 1 then poketch.enabled = true end
    for app = 0, 24 do
      if buf:u8(P + 3 + app) ~= 0 then poketch.registered[app] = true end
    end
    poketch.steps = buf:u32(P + 0x24)
    save.poketch = poketch
  end

  -- where the player stands
  local loc = G + L.location
  local header, gx, gz = buf:u32(loc), buf:u32(loc + 8), buf:u32(loc + 12)
  local mapId, lx, ly = Gen4Save.portLocation(data, header, gx, gz)
  if mapId then
    player.map, player.x, player.y = mapId, lx, ly
    player.facing = FACING[buf:u32(loc + 16)] or "down"
  else
    warnings[#warnings + 1] = ("map header %d is not one this cache knows"):format(header)
  end
  if not player.map then
    -- the game's own first map (field.lua's boot spawn), not a guess
    local boot = ((data.field or {}).boot) or (data.field or {})
    player.map, player.x, player.y = boot.startMap, boot.startX, boot.startY
  end

  save.warnings = warnings
  save.rawImport = bytes
  return save
end

-- ----------------------------------------------------------------- encode --
local function blankImage(family)
  local L = LAYOUT[family]
  local buf = NdsSave.buffer(string.rep("\255", NdsSave.SIZE))
  buf:fill(0, L.generalSize, 0)
  buf:fill(L.storageOffset, L.storageSize, 0)
  return buf
end

-- what the cartridge's Init functions leave in the blocks (the parts whose
-- zero is not "empty"): encrypted empty Pokemon, the dex magic and its "no
-- form seen" bytes, box names and wallpapers, the field warps
local function initBlank(buf, L, ctx)
  local G, S = 0, L.storageOffset
  local emptyParty = NdsSave.emptyPkm(PARTY_SIZE)
  local emptyBox = NdsSave.emptyPkm(NdsSave.STORED)
  for i = 0, 5 do buf:put(G + L.party + i * PARTY_SIZE, emptyParty) end
  for i = 0, 1 do buf:put(G + L.daycare + i * PARTY_SIZE, emptyBox) end
  for b = 0, BOXES - 1 do
    for slot = 0, BOX_SLOTS - 1 do
      buf:put(S + L.boxBase + b * L.boxStride + slot * NdsSave.STORED, emptyBox)
    end
    writeText(buf, S + L.boxNames + b * 40, 20, ("BOX %d"):format(b + 1), ctx)
    buf:set8(S + L.boxNames + BOXES * 40 + b, b % 16)
  end
  local D = G + L.dex
  buf:set32(D, Gen4Save.DEX_MAGIC)
  buf:set8(D + 0x43, 0xFF); buf:set8(D + 0x83, 0xFF) -- Deoxys forms unseen
  buf:fill(D + 0x108, 4, 0xFF)                          -- Shellos..Wormadam
  buf:fill(D + 0x10C, 28, 0xFF)                         -- Unown
  if L.dexLanguages == 0x144 then buf:fill(D + 0x128, 28, 0xFF) end -- HGSS caught Unown
  -- Rotom (u32), Shaymin, Giratina, and HGSS's Spiky-eared Pichu
  buf:fill(D + L.dexNational + 1 + (L.dexNational % 4 == 3 and 0 or 2),
    L.dexLanguages == 0x144 and 7 or 6, 0xFF)
  buf:set16(G + L.location + 5 * 20 + 4, 1) -- blackOutWarpId: the default heal spot
end

local function setLocation(buf, at, header, gx, gz, facing)
  buf:set32(at, header); buf:set32(at + 4, 0xFFFFFFFF)
  buf:set32(at + 8, gx); buf:set32(at + 12, gz); buf:set32(at + 16, facing or 1)
end

function Gen4Save.encode(save, data, template, version)
  version = version or (save and save.version)
  local family = familyOf(version)
  local L = LAYOUT[family]
  local image = template or (save and save.rawImport)
  local blocks
  local player = save.player or {}
  local ctx = context(data, family, version, player)
  if image then
    if type(image) ~= "string" or #image ~= NdsSave.SIZE then
      error(("a DS save image is %d bytes"):format(NdsSave.SIZE))
    end
    local err
    blocks, err = Gen4Save.readBlocks(image, family)
    if not blocks then error(err) end
  else
    local buf = blankImage(family)
    initBlank(buf, L, ctx)
    blocks = { buf = buf, L = L, general = 0, storage = L.storageOffset, counter = 0, blockCounters = { 0, 0 } }
  end
  local buf = blocks.buf
  local G, S = blocks.general, blocks.storage
  local T = G + L.trainer

  -- trainer
  writeText(buf, T, 8, player.name or "", ctx)
  buf:set16(T + 0x10, tonumber(player.id) or 0)
  buf:set16(T + 0x12, tonumber(player.secretId) or 0)
  buf:set32(T + 0x14, math.max(0, math.min(999999, tonumber(save.money) or 0)))
  buf:set8(T + 0x18, (player.gender == "girl" or player.gender == "female") and 1 or 0)
  if not image then buf:set8(T + 0x19, 2); buf:set8(T + 0x1C, ctx.gameId) end
  local badgeRows = (data.constants or {}).badges or {}
  local lo, hi = 0, 0
  local Badges = require("src.inventory.Badges")
  for i, row in ipairs(badgeRows) do
    local entry = type(row) == "table" and row or { id = row }
    if Badges.has(save, entry) then
      if i <= 8 then lo = lo + 2 ^ (i - 1) else hi = hi + 2 ^ (i - 9) end
    end
  end
  buf:set8(T + 0x1A, lo)
  if family == "hgss" then buf:set8(T + 0x1F, hi) end
  local progress = buf:u8(T + 0x1D)
  progress = progress - progress % 4
    + ((save.ndsGameClear or (save.flags or {}).FLAG_G4_0964) and 1 or 0)
    + (((save.pokedex or {}).national) and 2 or 0)
  buf:set8(T + 0x1D, progress)
  buf:set16(T + 0x20, math.max(0, math.min(50000, tonumber(save.coins) or 0)))
  local seconds = math.floor(tonumber(save.playTime) or 0)
  buf:set16(T + 0x22, math.min(999, math.floor(seconds / 3600)))
  buf:set8(T + 0x24, math.floor(seconds / 60) % 60)
  buf:set8(T + 0x25, seconds % 60)
  if player.rival and player.rival ~= "" then writeText(buf, G + L.rival, 8, player.rival, ctx) end

  -- party
  local party = save.party or {}
  local n = 0
  for i = 1, 6 do
    local mon = party[i]
    local at = G + L.party + (i - 1) * PARTY_SIZE
    if mon then
      buf:put(at, NdsSave.encryptPkm(NdsSave.encodeMon(mon, ctx, PARTY_SIZE)))
      n = n + 1
    else
      buf:put(at, NdsSave.emptyPkm(PARTY_SIZE))
    end
  end
  buf:set8(G + L.party - 4, n)

  -- boxes
  local unwritable = {}
  local boxes = save.boxes or {}
  buf:set8(S + L.currentBox, math.max(0, math.min(BOXES - 1, (tonumber(save.currentBox) or 1) - 1)))
  for b = 1, BOXES do
    local box = boxes[b] or {}
    if box.name and box.name ~= "" then writeText(buf, S + L.boxNames + (b - 1) * 40, 20, box.name, ctx) end
    -- BY SLOT, each at its own place: a box keeps emptied slots as holes
    -- (Boxes.used), and walking it with ipairs stopped at the first one --
    -- every Pokemon after a gap was left out of the written save
    for s = 0, BOX_SLOTS - 1 do
      local mon = box[s + 1]
      buf:put(S + L.boxBase + (b - 1) * L.boxStride + s * NdsSave.STORED,
        mon and NdsSave.encryptPkm(NdsSave.encodeMon(mon, ctx, NdsSave.STORED)) or NdsSave.emptyPkm(NdsSave.STORED))
    end
    for k, mon in pairs(box) do
      if type(k) == "number" and k > BOX_SLOTS and type(mon) == "table" then unwritable[#unwritable + 1] = mon end
    end
  end

  -- bag: the template's order first for what is still held, then the rest
  local inv = save.inventory or {}
  local items = data.items or {}
  local pockets = {}
  for p = 0, 7 do pockets[p] = {} end
  local placed = {}
  local function place(id)
    id = tonumber(id)
    if not id or placed[id] then return end
    local count = tonumber(inv[id]) or 0
    if count <= 0 then return end
    local def = items[id]
    local pocket = def and tonumber(def.fieldPocket) or 0
    if not L.pockets[pocket] then pocket = 0 end
    placed[id] = true
    local list = pockets[pocket]
    list[#list + 1] = { id, math.min(count, 999) }
  end
  for _, id in ipairs(save.bagOrder or {}) do place(id) end
  local rest = {}
  for id in pairs(inv) do if type(id) == "number" then rest[#rest + 1] = id end end
  table.sort(rest)
  for _, id in ipairs(rest) do place(id) end
  for p = 0, 7 do
    local spec = L.pockets[p]
    for i = 0, spec[2] - 1 do
      local row = pockets[p][i + 1]
      local at = G + L.bag + spec[1] + i * 4
      buf:set16(at, row and row[1] or 0); buf:set16(at + 2, row and row[2] or 0)
    end
  end

  -- flags and vars
  local flags = save.flags or {}
  local tflags = save.gen4TrainerFlags or {}
  for byte = 0, L.flagCount / 8 - 1 do
    local v = 0
    for b = 0, 7 do
      local i = byte * 8 + b
      local on = flags[("FLAG_G4_%04X"):format(i)]
      local tr = i - L.trainerFlagBase
      if tr > 0 and tflags[tr] then on = true end
      if on then v = v + 2 ^ b end
    end
    buf:set8(G + L.flags + byte, v)
  end
  local vars = save.gen4Vars or {}
  for i = 0, L.varCount - 1 do buf:set16(G + L.vars + i * 2, tonumber(vars[0x4000 + i]) or 0) end

  -- the Pokedex: seen / caught bits, obtained, national
  local D = G + L.dex
  local dex = save.pokedex or {}
  for byte = 0, 0x3F do
    local seen, owned = 0, 0
    for b = 0, 7 do
      local sp = byte * 8 + b + 1
      if (dex.owned or {})[sp] then owned = owned + 2 ^ b end
      if (dex.seen or {})[sp] or (dex.owned or {})[sp] then seen = seen + 2 ^ b end
    end
    -- the last byte of each region carries Deoxys' form nibbles
    if byte == 0x3F then
      owned = owned % 32 + buf:u8(D + 4 + byte) - buf:u8(D + 4 + byte) % 32
      seen = seen % 32 + buf:u8(D + 0x44 + byte) - buf:u8(D + 0x44 + byte) % 32
    end
    buf:set8(D + 4 + byte, owned); buf:set8(D + 0x44 + byte, seen)
  end
  buf:set32(D, Gen4Save.DEX_MAGIC)
  if (save.flags or {}).ENGINE_POKEDEX or next(dex.seen or {}) then buf:set8(D + L.dexObtained, 1) end
  buf:set8(D + L.dexNational, dex.national and 1 or 0)

  -- Pokétch
  if L.poketch and save.poketch then
    local P = G + L.poketch
    local p = save.poketch
    local packed = buf:u8(P)
    packed = packed - packed % 2 + (p.enabled and 1 or 0)
    buf:set8(P, packed)
    local count = 0
    for app = 0, 24 do
      local on = p.registered and p.registered[app]
      buf:set8(P + 3 + app, on and 1 or 0)
      if on then count = count + 1 end
    end
    buf:set8(P + 1, count)
  end

  -- where the player stands
  local header, gx, gz = Gen4Save.cartLocation(data, player.map, player.x, player.y)
  if header then
    local face = FACING_ID[player.facing or "down"] or 1
    setLocation(buf, G + L.location, header, gx, gz, face)
    if not image then
      for k = 1, 4 do setLocation(buf, G + L.location + k * 20, header, gx, gz, face) end
    end
    buf:set16(G + L.posMirror, gx); buf:set16(G + L.posMirror + 4, gz)
  end

  local counter = (blocks.counter or 0) + 1
  if counter >= 4294967295 then counter = 1 end
  return commit(blocks, counter), (#unwritable > 0) and unwritable or nil
end

return Gen4Save
