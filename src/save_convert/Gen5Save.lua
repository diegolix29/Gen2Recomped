-- Gen5Save -- the Black/White battery codec.
--
-- BW keeps its whole save as seventy fixed blocks between 0x00000 and
-- 0x23FFF, each followed by a u16 save counter and a u16 CRC16-CCITT, with a
-- table of every block's CRC at 0x23F00 (itself checksummed at 0x23F9A), and a
-- complete backup of the same 0x24000 bytes at 0x24000. The block list is
-- PKHeX's SaveBlockAccessor5BW, checked against a save the cartridge wrote
-- (every block, both copies). Pokemon records are Gen 4's encryption with a
-- 220-byte party form.
--
-- As with Gen4Save, an import keeps the image (`save.rawImport`) and an
-- export patches the port's state onto it, so the Musical, the Entralink,
-- the C-Gear and the Subway records ride through untouched.

local NdsSave = require("src.save_convert.NdsSave")
local bit = require("bit")

local Gen5Save = {}

Gen5Save.SAVE_SIZE = NdsSave.SIZE
Gen5Save.BACKUP = 0x24000
Gen5Save.DEX_MAGIC = 0xBEEFCAFE

-- { offset, length, checksum offset, checksum mirror }
local BLOCKS = {
  { 0x00000, 0x03E0, 0x003E2, 0x23F00 },
}
for i = 0, 23 do
  BLOCKS[#BLOCKS + 1] = { 0x00400 + i * 0x1000, 0x0FF0, 0x013F2 + i * 0x1000, 0x23F02 + i * 2 }
end
for _, b in ipairs({
  { 0x18400, 0x09C0 }, { 0x18E00, 0x0534 }, { 0x19400, 0x0068 }, { 0x19500, 0x009C },
  { 0x19600, 0x1338 }, { 0x1AA00, 0x07C4 }, { 0x1B200, 0x0D54 }, { 0x1C000, 0x002C },
  { 0x1C100, 0x0658 }, { 0x1C800, 0x0A94 }, { 0x1D300, 0x01AC }, { 0x1D500, 0x03EC },
  { 0x1D900, 0x005C }, { 0x1DA00, 0x01E0 }, { 0x1DC00, 0x00A8 }, { 0x1DD00, 0x0460 },
  { 0x1E200, 0x1400 }, { 0x1F700, 0x02A4 }, { 0x1FA00, 0x02DC }, { 0x1FD00, 0x034C },
  { 0x20100, 0x03EC }, { 0x20500, 0x00F8 }, { 0x20600, 0x02FC }, { 0x20900, 0x0094 },
  { 0x20A00, 0x035C }, { 0x20E00, 0x01CC }, { 0x21000, 0x0168 }, { 0x21200, 0x00EC },
  { 0x21300, 0x01B0 }, { 0x21500, 0x001C }, { 0x21600, 0x04D4 }, { 0x21B00, 0x0034 },
  { 0x21C00, 0x003C }, { 0x21D00, 0x01AC }, { 0x21F00, 0x0B90 }, { 0x22B00, 0x009C },
  { 0x22C00, 0x0850 }, { 0x23500, 0x0028 }, { 0x23600, 0x0284 }, { 0x23900, 0x0010 },
  { 0x23A00, 0x005C }, { 0x23B00, 0x016C }, { 0x23D00, 0x0040 }, { 0x23E00, 0x00FC },
}) do
  local n = #BLOCKS
  BLOCKS[n + 1] = { b[1], b[2], b[1] + b[2] + 2, 0x23F00 + n * 2 }
end
BLOCKS[#BLOCKS + 1] = { 0x23F00, 0x008C, 0x23F9A, 0x23F9A }
Gen5Save.BLOCKS = BLOCKS

local OFS = {
  boxLayout = 0x00000, boxes = 0x00400, boxStride = 0x1000,
  bag = 0x18400, party = 0x18E00, trainer = 0x19400, position = 0x19500,
  mystery = 0x1C800, records = 0x1DA00, events = 0x20100, gimmick = 0x20900,
  battleBox = 0x20A00, daycare = 0x20E00, boulders = 0x21000, misc = 0x21200,
  unk54 = 0x21500, dex = 0x21600, forest = 0x22C00,
}
Gen5Save.OFS = OFS

local POCKETS = { -- bwPocket -> { offset, slots }
  [0] = { 0x000, 310 }, [4] = { 0x4D8, 83 }, [2] = { 0x624, 109 }, [1] = { 0x7D8, 48 }, [3] = { 0x898, 64 },
}
local VAR_COUNT, FLAG_COUNT, FLAG_BASE = 0x13E, 0xB60, 0x27C
local TRAINER_FLAG_BASE = 0x58C -- ov10 0x0215A4EC: flag = 0x58C + trainer
local BOXES, BOX_SLOTS = 24, 30
local PARTY_SIZE = NdsSave.PARTY5
local GAME_IDS = { black = 21, white = 20 }

-- ----------------------------------------------------------------- blocks --
local function copyValid(buf, base)
  for _, b in ipairs(BLOCKS) do
    local crc = NdsSave.crc16(buf, base + b[1], b[2])
    if buf:u16(base + b[3]) ~= crc then return false end
  end
  return true
end

function Gen5Save.readImage(bytes)
  local buf = NdsSave.buffer(bytes)
  if copyValid(buf, 0) then return buf, 0 end
  if copyValid(buf, Gen5Save.BACKUP) then return buf, Gen5Save.BACKUP end
  return nil, "neither copy of this Black/White save passes its checksums"
end

local function commit(buf, base)
  -- the counters after each block go up by one, like a real save
  for i, b in ipairs(BLOCKS) do
    if i < #BLOCKS then
      local at = base + b[1] + b[2]
      buf:set16(at, (buf:u16(at) + 1) % 65536)
    end
  end
  for _, b in ipairs(BLOCKS) do
    local crc = NdsSave.crc16(buf, base + b[1], b[2])
    buf:set16(base + b[3], crc)
    buf:set16(base + b[4], crc)
  end
  local other = base == 0 and Gen5Save.BACKUP or 0
  buf:copy(other, base, Gen5Save.BACKUP)
  return buf:string()
end

-- ---------------------------------------------------------- the crosswalk --
local function context(data, version, player)
  local Gen4Save = require("src.save_convert.Gen4Save")
  local ctx = Gen4Save.context(data, "pt", version, player)
  ctx.gen, ctx.family = 5, "bw"
  ctx.text = NdsSave.textCodec(5)
  ctx.gameId = GAME_IDS[version] or 21
  ctx.eggName = "Egg"
  return ctx
end

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

local FACING = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }

-- ----------------------------------------------------------------- decode --
function Gen5Save.decode(bytes, data, version)
  local buf, base = Gen5Save.readImage(bytes)
  if not buf then error(base) end
  local B = base
  local ctx = context(data, version)
  local warnings = {}
  local T = B + OFS.trainer
  local id32 = buf:u32(T + 0x14)
  local player = {
    name = readText(buf, T + 4, 8, ctx),
    id = id32 % 65536,
    secretId = math.floor(id32 / 65536),
    gender = buf:u8(T + 0x21) == 1 and "girl" or "boy",
  }
  ctx.player = player
  -- a save the cartridge initialised but nobody has played: no name, no
  -- time, no zone -- the game itself offers only NEW GAME for it
  if player.name == "" and buf:u32(B + OFS.position + 0x80) == 0 and buf:u16(T + 0x24) == 0 then
    error("this save has no adventure in it yet (start a game and save first)", 0)
  end
  local save = {
    meta = { format = "gen5_import" },
    version = version,
    player = player,
    money = buf:u32(B + OFS.misc),
    playTime = buf:u16(T + 0x24) * 3600 + buf:u8(T + 0x26) * 60 + buf:u8(T + 0x27),
    inventory = {}, bagOrder = {},
    flags = {}, gen4Vars = {}, gen4TrainerFlags = {},
    badges = {}, party = {}, boxes = {},
    pokedex = { seen = {}, owned = {} },
    ndsLanguage = buf:u8(T + 0x1E),
  }

  local badgeBits = buf:u8(B + OFS.misc + 4)
  for i, row in ipairs((data.constants or {}).badges or {}) do
    if math.floor(badgeBits / 2 ^ (i - 1)) % 2 == 1 then
      local id = type(row) == "table" and row.id or row
      save.badges[id] = true
      save.inventory[id] = 1
    end
  end

  local P = B + OFS.party
  for i = 0, math.min(6, buf:u8(P + 4)) - 1 do
    local canon, ok = NdsSave.decryptPkm(buf:sub(P + 8 + i * PARTY_SIZE, PARTY_SIZE))
    if not ok then warnings[#warnings + 1] = ("party slot %d failed its checksum"):format(i + 1) end
    local mon = NdsSave.decodeMon(canon, ctx, true)
    if mon then save.party[#save.party + 1] = mon end
  end

  save.currentBox = buf:u8(B + OFS.boxLayout) + 1
  for b = 0, BOXES - 1 do
    local box = { name = readText(buf, B + OFS.boxLayout + 4 + b * 0x28, 10, ctx) }
    for slot = 0, BOX_SLOTS - 1 do
      local at = B + OFS.boxes + b * OFS.boxStride + slot * NdsSave.STORED
      local canon, ok = NdsSave.decryptPkm(buf:sub(at, NdsSave.STORED))
      local mon = NdsSave.decodeMon(canon, ctx, false)
      if mon then
        if not ok then warnings[#warnings + 1] = ("box %d slot %d failed its checksum"):format(b + 1, slot + 1) end
        box[#box + 1] = mon
      end
    end
    save.boxes[b + 1] = box
  end

  for _, pocket in ipairs({ 0, 4, 2, 1, 3 }) do
    local p = POCKETS[pocket]
    for i = 0, p[2] - 1 do
      local at = B + OFS.bag + p[1] + i * 4
      local id, n = buf:u16(at), buf:u16(at + 2)
      if id ~= 0 and n > 0 then
        save.inventory[id] = (save.inventory[id] or 0) + n
        save.bagOrder[#save.bagOrder + 1] = id
      end
    end
  end

  local E = B + OFS.events
  for i = 0, VAR_COUNT - 1 do
    local v = buf:u16(E + i * 2)
    if v ~= 0 then save.gen4Vars[0x4000 + i] = v end
  end
  local trainerCount = 0
  for id in pairs(data.trainers or {}) do
    if type(id) == "number" and id > trainerCount then trainerCount = id end
  end
  for i = 1, FLAG_COUNT - 1 do
    if math.floor(buf:u8(E + FLAG_BASE + math.floor(i / 8)) / 2 ^ (i % 8)) % 2 == 1 then
      save.flags[("FLAG_G4_%04X"):format(i)] = true
      local tr = i - TRAINER_FLAG_BASE
      if tr > 0 and tr <= trainerCount then save.gen4TrainerFlags[tr] = true end
    end
  end

  local D = B + OFS.dex
  for sp = 1, 649 do
    local byte, bitn = math.floor((sp - 1) / 8), (sp - 1) % 8
    local function on(off) return math.floor(buf:u8(D + off + byte) / 2 ^ bitn) % 2 == 1 end
    if on(0x08) then save.pokedex.owned[sp] = true end
    for r = 0, 3 do if on(0x5C + r * 0x54) then save.pokedex.seen[sp] = true end end
  end
  if buf:u32(D + 4) % 2 == 1 then save.pokedex.national = true end
  if next(save.pokedex.seen) then save.flags.ENGINE_POKEDEX = true end

  -- position: the zone and the world position in fx32, sixteen units a tile
  local Pos = B + OFS.position
  local zone = buf:u32(Pos + 0x80)
  local gx, gz = math.floor(buf:u16(Pos + 0x86) / 16), math.floor(buf:u16(Pos + 0x8E) / 16)
  local Gen4Save = require("src.save_convert.Gen4Save")
  local mapId, lx, ly = Gen4Save.portLocation(data, zone, gx, gz)
  if mapId then
    player.map, player.x, player.y, player.facing = mapId, lx, ly, "down"
  else
    warnings[#warnings + 1] = ("zone %d is not one this cache knows"):format(zone)
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
-- What the cartridge's own init leaves where zero is not "empty" (compared
-- with a save Black wrote on its first boot): encrypted empty Pokemon in the
-- boxes, party, Battle Box and day care; the encrypted-but-empty Mystery Gift,
-- records and Entralink Forest blocks; box names; the dex magic.
local function cryptRegion(buf, off, len, seed)
  local s = buf:sub(off, len)
  local t = {}
  for i = 1, #s do t[i - 1] = s:byte(i) end
  for o = 0, len - 2, 2 do
    local lo = (seed * 0x4E6D) % 4294967296
    local hi = ((seed * 0x41C6) % 65536) * 65536
    seed = (lo + hi + 0x6073) % 4294967296
    local x = math.floor(seed / 65536)
    t[o] = bit.bxor(t[o], x % 256); t[o + 1] = bit.bxor(t[o + 1], math.floor(x / 256))
  end
  local parts = {}
  for i = 0, len - 1 do parts[#parts + 1] = string.char(t[i]) end
  buf:put(off, table.concat(parts))
end

local function blankImage(ctx)
  local buf = NdsSave.buffer(string.rep("\255", NdsSave.SIZE))
  buf:fill(0, Gen5Save.BACKUP * 2, 0)
  local emptyBox = NdsSave.emptyPkm(NdsSave.STORED)
  local emptyParty = NdsSave.emptyPkm(PARTY_SIZE)
  for b = 0, BOXES - 1 do
    writeText(buf, OFS.boxLayout + 4 + b * 0x28, 10, ("BOX %d"):format(b + 1), ctx)
    buf:set8(OFS.boxLayout + 0x3C4 + b, b % 16)
    for slot = 0, BOX_SLOTS - 1 do buf:put(OFS.boxes + b * OFS.boxStride + slot * NdsSave.STORED, emptyBox) end
  end
  buf:set8(OFS.boxLayout + 0x3DD, 8) -- boxes unlocked at the start
  buf:set32(OFS.party, 6)
  for i = 0, 5 do buf:put(OFS.party + 8 + i * PARTY_SIZE, emptyParty) end
  for i = 0, 5 do buf:put(OFS.battleBox + i * NdsSave.STORED, emptyBox) end
  for i = 0, 1 do buf:put(OFS.daycare + i * (PARTY_SIZE + 8) + 4, emptyParty) end
  cryptRegion(buf, OFS.mystery, 0xA90, 0)
  cryptRegion(buf, OFS.records + 4, 0x1D8, 0)
  cryptRegion(buf, OFS.forest, 0x84C, 0)
  buf:fill(OFS.boulders, 0x168, 0xFF)
  buf:set32(OFS.gimmick, 0xFFFFFFFF)
  buf:set8(OFS.trainer, 1); buf:set8(OFS.trainer + 1, 2)
  buf:set8(OFS.trainer + 0x1E, 2); buf:set8(OFS.trainer + 0x1F, ctx.gameId)
  buf:set32(OFS.dex, Gen5Save.DEX_MAGIC)
  return buf
end

function Gen5Save.encode(save, data, template, version)
  version = version or (save and save.version)
  local image = template or (save and save.rawImport)
  local player = save.player or {}
  local ctx = context(data, version, player)
  local buf, B
  if image then
    if type(image) ~= "string" or #image ~= NdsSave.SIZE then
      error(("a DS save image is %d bytes"):format(NdsSave.SIZE))
    end
    buf, B = Gen5Save.readImage(image)
    if not buf then error(B) end
  else
    buf, B = blankImage(ctx), 0
  end

  local T = B + OFS.trainer
  writeText(buf, T + 4, 8, player.name or "", ctx)
  buf:set32(T + 0x14, (tonumber(player.id) or 0) % 65536 + (tonumber(player.secretId) or 0) * 65536)
  buf:set8(T + 0x21, (player.gender == "girl" or player.gender == "female") and 1 or 0)
  local seconds = math.floor(tonumber(save.playTime) or 0)
  buf:set16(T + 0x24, math.min(999, math.floor(seconds / 3600)))
  buf:set8(T + 0x26, math.floor(seconds / 60) % 60)
  buf:set8(T + 0x27, seconds % 60)

  buf:set32(B + OFS.misc, math.max(0, math.min(999999, tonumber(save.money) or 0)))
  local Badges = require("src.inventory.Badges")
  local bits = 0
  for i, row in ipairs((data.constants or {}).badges or {}) do
    local entry = type(row) == "table" and row or { id = row }
    if i <= 8 and Badges.has(save, entry) then bits = bits + 2 ^ (i - 1) end
  end
  buf:set8(B + OFS.misc + 4, bits)

  local P = B + OFS.party
  local n = 0
  for i = 1, 6 do
    local mon = (save.party or {})[i]
    local at = P + 8 + (i - 1) * PARTY_SIZE
    if mon then
      buf:put(at, NdsSave.encryptPkm(NdsSave.encodeMon(mon, ctx, PARTY_SIZE))); n = n + 1
    else
      buf:put(at, NdsSave.emptyPkm(PARTY_SIZE))
    end
  end
  buf:set8(P + 4, n)

  local unwritable = {}
  buf:set8(B + OFS.boxLayout, math.max(0, math.min(BOXES - 1, (tonumber(save.currentBox) or 1) - 1)))
  for b = 1, BOXES do
    local box = (save.boxes or {})[b] or {}
    if box.name and box.name ~= "" then writeText(buf, B + OFS.boxLayout + 4 + (b - 1) * 0x28, 10, box.name, ctx) end
    local slot = 0
    for _, mon in ipairs(box) do
      if slot < BOX_SLOTS then
        buf:put(B + OFS.boxes + (b - 1) * OFS.boxStride + slot * NdsSave.STORED,
          NdsSave.encryptPkm(NdsSave.encodeMon(mon, ctx, NdsSave.STORED)))
        slot = slot + 1
      else
        unwritable[#unwritable + 1] = mon
      end
    end
    for s = slot, BOX_SLOTS - 1 do
      buf:put(B + OFS.boxes + (b - 1) * OFS.boxStride + s * NdsSave.STORED, NdsSave.emptyPkm(NdsSave.STORED))
    end
  end

  local inv, items = save.inventory or {}, data.items or {}
  local pockets, placed = {}, {}
  for p = 0, 4 do pockets[p] = {} end
  local function place(id)
    id = tonumber(id)
    if not id or placed[id] or (tonumber(inv[id]) or 0) <= 0 then return end
    local def = items[id]
    local pocket = def and tonumber(def.bwPocket) or 0
    if not POCKETS[pocket] then pocket = 0 end
    placed[id] = true
    local list = pockets[pocket]
    list[#list + 1] = { id, math.min(tonumber(inv[id]), 999) }
  end
  for _, id in ipairs(save.bagOrder or {}) do place(id) end
  local rest = {}
  for id in pairs(inv) do if type(id) == "number" then rest[#rest + 1] = id end end
  table.sort(rest)
  for _, id in ipairs(rest) do place(id) end
  for p = 0, 4 do
    local spec = POCKETS[p]
    for i = 0, spec[2] - 1 do
      local row = pockets[p][i + 1]
      local at = B + OFS.bag + spec[1] + i * 4
      buf:set16(at, row and row[1] or 0); buf:set16(at + 2, row and row[2] or 0)
    end
  end

  local E = B + OFS.events
  local vars = save.gen4Vars or {}
  for i = 0, VAR_COUNT - 1 do buf:set16(E + i * 2, tonumber(vars[0x4000 + i]) or 0) end
  local flags, tflags = save.flags or {}, save.gen4TrainerFlags or {}
  for byte = 0, FLAG_COUNT / 8 - 1 do
    local v = 0
    for b = 0, 7 do
      local i = byte * 8 + b
      local on = flags[("FLAG_G4_%04X"):format(i)]
      local tr = i - TRAINER_FLAG_BASE
      if tr > 0 and tflags[tr] then on = true end
      if on then v = v + 2 ^ b end
    end
    buf:set8(E + FLAG_BASE + byte, v)
  end

  -- the dex: caught; seen + displayed in the region the species' genders allow
  local D = B + OFS.dex
  local dex = save.pokedex or {}
  local pokemon = data.pokemon or {}
  for sp = 1, 649 do
    local byte, bitn = math.floor((sp - 1) / 8), 2 ^ ((sp - 1) % 8)
    local function get(off) return math.floor(buf:u8(D + off + byte) / bitn) % 2 == 1 end
    local function set(off, on)
      local v = buf:u8(D + off + byte)
      local has = math.floor(v / bitn) % 2 == 1
      if on and not has then v = v + bitn elseif has and not on then v = v - bitn end
      buf:set8(D + off + byte, v)
    end
    local owned = (dex.owned or {})[sp] and true or false
    local seen = owned or ((dex.seen or {})[sp] and true or false)
    set(0x08, owned)
    local any = false
    for r = 0, 3 do if get(0x5C + r * 0x54) then any = true end end
    if seen and not any then
      local female = (tonumber((pokemon[sp] or {}).genderRatio) or 0) == 254
      set(0x5C + (female and 1 or 0) * 0x54, true)
      set(0x1AC + (female and 1 or 0) * 0x54, true)
    elseif not seen and any then
      for r = 0, 3 do set(0x5C + r * 0x54, false); set(0x1AC + r * 0x54, false) end
    end
  end
  buf:set32(D, Gen5Save.DEX_MAGIC)
  local packed = buf:u32(D + 4)
  buf:set32(D + 4, packed - packed % 2 + (dex.national and 1 or 0))

  local Gen4Save = require("src.save_convert.Gen4Save")
  local zone, gx, gz = Gen4Save.cartLocation(data, player.map, player.x, player.y)
  if zone then
    local Pos = B + OFS.position
    buf:set32(Pos + 0x80, zone)
    buf:set32(Pos + 0x84, (gx * 16 + 8) * 65536)
    buf:set32(Pos + 0x8C, (gz * 16 + 8) * 65536)
  end

  return commit(buf, B), (#unwritable > 0) and unwritable or nil
end

return Gen5Save
