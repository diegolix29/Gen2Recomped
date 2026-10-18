-- src/import/Gen5Trades.lua -- BLACK AND WHITE'S IN-GAME TRADES.
--
-- THE TABLE is /a/1/6/5 (archive 165, the id the trade code passes the
-- archive loader, ov21 0x021CBFE0), one member per trade, each member 108
-- bytes = TWENTY-SEVEN u32. The same 13 members in Black and White: the
-- versions differ in which record their scripts ask for, not in the table.
-- Field by field, from the routine that builds the Pokemon (ov21 0x021CC098,
-- each word handed to the parameter setter 0x02017E40 under the parameter id
-- shown) and the two that read the request (0x021CC060 / 0x021CC068):
--
--   +00 id            the record's own index
--   +04 species       +08 form (param 0x6F)   +0C level
--   +10..+24 IVs      HP Atk Def Spe SpA SpD (params 0x46..0x4B, in order)
--   +28 abilitySlot   0 / 1 / 2 -> the personal record's ability 1 / 2 / hidden
--   +2C nature        (param 0x70; Gen 5 keeps it apart from the PID)
--   +30 gender        0 male, 1 female, 2 genderless -- fed to the PID maker
--   +34 otId          (TID in the low half, SID 0 in the high)
--   +38..+48          five words to params 0x13..0x17 (the contest conditions
--                     in Gen 4's numbering), all zero in the shipping table
--   +4C heldItem      (param 6)     +50 otGender (param 0x9A, 1 = female)
--   +54 unused        +58 language (param 0x0C; 2 = English)
--   +5C requestedSpecies   +60 requestedGender (2 = either; 0x1BF compares
--                     it with the offered Pokemon's when it is not 2)
--   +64 nicknameEntry +68 otNameEntry -- entries of SYSTEM BANK 35 (the trade
--                     code opens /a/0/0/2 member 0x23, ov21 0x021CC07C)
--
-- RECORDS 7-12 carry level-50 placeholders with EMPTY names in bank 35 and no
-- script asks for them (0x1BF / 0x1BE are passed 0..6 only); they are kept in
-- the table, marked `unused`.
--
-- THE PID is not random: 0x0201862C builds it from the OT id, the species'
-- gender ratio and the record's gender --
--
--     hi = ((tid ^ sid) & 0xFF00) ^ 0xFF00      -- so (tid^sid^hi^lo) >= 0xFF00:
--     pid = hi << 16                            --   never shiny for its OT
--     if the ratio is not fixed (0 / 254 / 255):
--       pid = pid | ratio ; if female then pid = pid - 1
--
-- which makes Petilil's (OT 39922 = 0x9BF2) 0x64000000.

local T = {}

T.PATH = "/a/1/6/5"
T.NAME_BANK = 35
T.RECORD_BYTES = 108
T.FIELDS = {
  "id", "species", "form", "level",
  "hpIV", "atkIV", "defIV", "speedIV", "spAtkIV", "spDefIV",
  "abilitySlot", "nature", "gender", "otId",
  "cool", "beauty", "cute", "smart", "tough",
  "heldItem", "otGender", "unused", "language",
  "requestedSpecies", "requestedGender", "nicknameEntry", "otNameEntry",
}
T.IV_FIELDS = { "hpIV", "atkIV", "defIV", "speedIV", "spAtkIV", "spDefIV" }

-- which record each version's script asks for, by zone (0x1BF / 0x1BE
-- operands; Nacrene and Driftveil choose by the 0x0E0 version id, 21 Black)
T.SITES = {
  { zone = 23, place = "Nacrene City", black = 0, white = 1 },
  { zone = 101, place = "Driftveil City", black = 2, white = 3 },
  { zone = 343, place = "Route 7", black = 4, white = 4 },
  { zone = 415, place = "Undella Town", black = 5, white = 5 },
  { zone = 382, place = "Route 15", black = 6, white = 6 },
}

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

function T.parse(record)
  if type(record) ~= "string" or #record < T.RECORD_BYTES then
    return nil, ("trade record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, T.RECORD_BYTES)
  end
  local out = {}
  for i, name in ipairs(T.FIELDS) do out[name] = u32(record, (i - 1) * 4) end
  return out
end

local function bxor16(a, b)
  local r, bit = 0, 1
  for _ = 1, 16 do
    if (a % 2) ~= (b % 2) then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end

-- 0x0201862C, as above. `ratio` is the personal record's gender byte.
function T.pid(otId, ratio, gender)
  otId = tonumber(otId) or 0
  local tid, sid = otId % 65536, math.floor(otId / 65536) % 65536
  local x = bxor16(tid, sid)
  local hi = bxor16(math.floor(x / 256) % 256 * 256, 0xFF00)
  local pid = hi * 65536
  ratio = tonumber(ratio)
  if ratio and ratio ~= 0 and ratio ~= 254 and ratio ~= 255 then
    pid = pid + ratio
    if tonumber(gender) == 1 then pid = pid - 1 end
  end
  return pid
end

-- every record as the runtime reads it. `names` is system bank 35 as a
-- zero-based table (entry -> string).
function T.all(narc, names)
  local out = {}
  local id = 0
  while narc do
    local bytes = narc:get(id)
    if not bytes then break end
    local p = T.parse(bytes)
    if p then
      local ivs = {}
      for i, f in ipairs(T.IV_FIELDS) do ivs[i] = p[f] end
      local nick = names and names[p.nicknameEntry]
      local ot = names and names[p.otNameEntry]
      out[id + 1] = {
        id = id, species = p.species, form = p.form, level = p.level,
        ivs = ivs, abilitySlot = p.abilitySlot, nature = p.nature,
        gender = p.gender, otId = p.otId,
        otGender = p.otGender == 1 and "girl" or "boy",
        item = p.heldItem, language = p.language,
        request = p.requestedSpecies, requestGender = p.requestedGender,
        nickname = nick, otName = ot,
        nicknameEntry = p.nicknameEntry, otNameEntry = p.otNameEntry,
        conditions = { p.cool, p.beauty, p.cute, p.smart, p.tough },
        unused = (nick == nil or nick == "") or nil,
      }
    end
    id = id + 1
  end
  return out
end

-- RomExtractorGen5 (x:string reads the system bank)
function T.build(x)
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(T.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local names = {}
  for i = 0, 63 do
    local s = x:string(T.NAME_BANK, i)
    if s == nil then break end
    names[i] = s
  end
  return T.all(arc, names)
end

return T
