-- THE LAKE OF RAGE'S MAGIKARP LENGTH RECORD (pokeheartgold
-- src/scrcmd_size_record.c): a Pokemon's length is its species' Pokedex
-- height scaled by a 16-bit hash of its personality and IVs, read through
-- sBigMonSizeTable, and shown in inches to a tenth. The fisherman keeps the
-- best hash (the new game seeds 56150, overlay_36.c -- 3'6" for a Magikarp).

local S = {}

S.DEFAULT_RECORD = 56150

-- { base, divisor, threshold }
S.TABLE = {
  { 290,  1,   0     }, { 300,  1,   10    }, { 400,  2,   110   },
  { 500,  4,   310   }, { 600,  20,  710   }, { 700,  50,  2710  },
  { 800,  100, 7710  }, { 900,  150, 17710 }, { 1000, 150, 32710 },
  { 1100, 100, 47710 }, { 1200, 50,  57710 }, { 1300, 20,  62710 },
  { 1400, 5,   64710 }, { 1500, 2,   65210 }, { 1600, 1,   65410 },
  { 1700, 1,   65510 },
}

local bxor = (bit and bit.bxor) or function(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

-- GetMonSizeHash: the personality's low half and each IV's low nibble
function S.hash(mon)
  local pid = math.floor(tonumber(mon and mon.personality) or 0) % 65536
  local iv = (mon and mon.ivs) or {}
  local function n(k) return math.floor(tonumber(iv[k]) or 0) % 16 end
  local ret = (bxor(bxor(n("spdef"), n("spatk")) * n("speed"), math.floor(pid / 256))) % 65536
  local ret2 = (bxor(bxor(n("attack"), n("defense")) * n("hp"), pid % 256)) % 65536
  return (ret + ret2 * 256) % 65536
end

-- TranslateBigMonSizeTableIndex (0-based row)
function S.row(hash)
  local i = 1
  while i < #S.TABLE - 1 do
    if hash < S.TABLE[i + 1][3] then return i - 1 end
    i = i + 1
  end
  return i
end

-- GetMonSize: millimetres, the dex height in decimetres times the scale / 10
function S.size(height, hash)
  local r = S.TABLE[S.row(hash) + 1]
  local scale = r[1] + math.floor((hash - r[3]) / r[2])
  return math.floor((tonumber(height) or 0) * scale / 10)
end

-- LengthConvertToImperial: tenths of an inch
function S.imperial(mm)
  return math.floor((math.floor(mm * 1000 / 254) + 5) / 10)
end

function S.heightOf(data, species)
  local h = data and data.constants and data.constants.dexHeights
  return h and tonumber(h[species]) or 0
end

-- the record's hash, as the save holds it
function S.record(save)
  return tonumber(save and save.hgssSizeRecord) or S.DEFAULT_RECORD
end

-- SizeRecordCompare: 2 when the mon beats the record, 0 when it falls short,
-- 1 when they read the same in inches (the cartridge's own equal case
-- yields a frame and leaves the var alone; the script reads it as "same")
function S.compare(data, save, mon)
  local species = tonumber(mon and mon.species) or 0
  local h = S.heightOf(data, species)
  local mine = S.imperial(S.size(h, S.hash(mon)))
  local best = S.imperial(S.size(h, S.record(save)))
  if mine == best then return 1 end
  return mine > best and 2 or 0
end

-- FormatSizeRecord: whole inches and the tenth, as two strings
function S.format(data, species, hash)
  local tenths = S.imperial(S.size(S.heightOf(data, species), hash))
  return tostring(math.floor(tenths / 10)), tostring(tenths % 10)
end

return S
