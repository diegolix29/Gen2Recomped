-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S ITEM RECORDS, COMPLETED FOR THE BAG AND THE BATTLE.
--
-- A BW item record (/a/0/2/4, 0x24 bytes) is Platinum's ItemData laid out
-- again: the u16 at +0x08 packs the natural gift type (5 bits), two flags,
-- the field pocket (4 bits, `bwPocket`) and -- bits 11..15 -- the BATTLE
-- POCKET MASK, the same five bits Platinum reads (bit 0 Poke Balls, 1 battle
-- items, 2 HP / PP restore, 3 status restore, 4 PP restore). +0x0C is
-- `partyUse` and +0x10..+0x23 the twenty-byte ItemPartyParam, laid out
-- exactly as Platinum's (status bits, revive / level / evolve and the stat
-- stage nibbles, PP flags, the six EV bits, HP and PP amounts, three
-- friendship steps). +0x0D is the item's kind (0 medicine, 1 held, 2 general,
-- 3 battle, 4 ball, 5 mail) -- which the first BW importer filed as
-- `battlePocket`.
--
-- !! "WHEN USING ITEMS LIKE POKEBALLS IN BLACK AND WHITE THEY PLAY A WEIRD
-- MESSAGE AND DON'T LET YOU THROW THE BALLS". The importer kept neither the
-- mask nor the party block, so nothing told the bag a Poke Ball was a ball
-- (Platinum's balls are found by `pocket = "POKE_BALLS"`, a BW item has no
-- such string) or a Potion a medicine. Every item fell through to the
-- engine's refusal, which `Gen4ItemUse.rowanLine` turned into Platinum's
-- common_strings bank 213 line 36 -- and in Black's bank 213, line 36 is
-- Alder's speech about the Dragonspiral tower. That was the weird message.
--
-- `src/import/Gen5Data.lua` reads the mask and the block now. For a cache
-- imported before that, `ensure` fills them in from the table below -- the
-- 124 records that carry a battle pocket or a party block, written as the
-- non-zero bytes of the block (index = byte of the ItemPartyParam). Black
-- and White's tables are identical; checked against both ROMs.

local G = {}

-- id -> { battle pocket mask, { [byte] = value } of the party block }
G.FALLBACK = {
  [1] = { 1 },
  [2] = { 1 },
  [3] = { 1 },
  [4] = { 1 },
  [5] = { 1 },
  [6] = { 1 },
  [7] = { 1 },
  [8] = { 1 },
  [9] = { 1 },
  [10] = { 1 },
  [11] = { 1 },
  [12] = { 1 },
  [13] = { 1 },
  [14] = { 1 },
  [15] = { 1 },
  [16] = { 1 },
  [17] = { 4, { [5] = 4, [13] = 20 } },
  [18] = { 8, { [0] = 2 } },
  [19] = { 8, { [0] = 4 } },
  [20] = { 8, { [0] = 8 } },
  [21] = { 8, { [0] = 1 } },
  [22] = { 8, { [0] = 16 } },
  [23] = { 12, { [0] = 63, [5] = 4, [13] = 255 } },
  [24] = { 4, { [5] = 4, [13] = 255 } },
  [25] = { 4, { [5] = 4, [13] = 200 } },
  [26] = { 4, { [5] = 4, [13] = 50 } },
  [27] = { 8, { [0] = 63 } },
  [28] = { 8, { [1] = 1, [13] = 254 } },
  [29] = { 8, { [1] = 1, [13] = 255 } },
  [30] = { 4, { [5] = 4, [13] = 50 } },
  [31] = { 4, { [5] = 4, [13] = 60 } },
  [32] = { 4, { [5] = 4, [13] = 80 } },
  [33] = { 4, { [5] = 4, [13] = 100 } },
  [34] = { 4, { [5] = 4, [6] = 28, [13] = 50, [15] = 251, [16] = 251, [17] = 246 } },
  [35] = { 4, { [5] = 4, [6] = 28, [13] = 200, [15] = 246, [16] = 246, [17] = 241 } },
  [36] = { 8, { [0] = 63, [6] = 28, [15] = 251, [16] = 251, [17] = 246 } },
  [37] = { 8, { [1] = 1, [6] = 28, [13] = 255, [15] = 241, [16] = 241, [17] = 236 } },
  [38] = { 4, { [5] = 1, [14] = 10 } },
  [39] = { 4, { [5] = 1, [14] = 127 } },
  [40] = { 4, { [5] = 2, [14] = 10 } },
  [41] = { 4, { [5] = 2, [14] = 127 } },
  [42] = { 8, { [0] = 63 } },
  [43] = { 4, { [5] = 4, [13] = 20 } },
  [44] = { 0, { [1] = 3, [5] = 4, [13] = 255 } },
  [45] = { 0, { [5] = 8, [6] = 28, [7] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [46] = { 0, { [5] = 16, [6] = 28, [8] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [47] = { 0, { [5] = 32, [6] = 28, [9] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [48] = { 0, { [5] = 64, [6] = 28, [10] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [49] = { 0, { [5] = 128, [6] = 28, [11] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [50] = { 0, { [1] = 5, [6] = 28, [15] = 5, [16] = 3, [17] = 2 } },
  [51] = { 0, { [4] = 64, [6] = 28, [15] = 5, [16] = 3, [17] = 2 } },
  [52] = { 0, { [6] = 29, [12] = 10, [15] = 5, [16] = 3, [17] = 2 } },
  [53] = { 0, { [4] = 128, [6] = 28, [15] = 5, [16] = 3, [17] = 2 } },
  [54] = { 8, { [0] = 63 } },
  [55] = { 2, { [0] = 128, [6] = 12, [15] = 1, [16] = 1 } },
  [56] = { 2, { [4] = 16, [6] = 12, [15] = 1, [16] = 1 } },
  [57] = { 2, { [1] = 16, [6] = 12, [15] = 1, [16] = 1 } },
  [58] = { 2, { [2] = 1, [6] = 12, [15] = 1, [16] = 1 } },
  [59] = { 2, { [3] = 16, [6] = 12, [15] = 1, [16] = 1 } },
  [60] = { 2, { [4] = 1, [6] = 12, [15] = 1, [16] = 1 } },
  [61] = { 2, { [2] = 16, [6] = 12, [15] = 1, [16] = 1 } },
  [62] = { 2, { [3] = 1 } },
  [63] = { 2 },
  [64] = { 2 },
  [65] = { 0, { [0] = 1 } },
  [66] = { 0, { [0] = 32 } },
  [67] = { 0, { [0] = 64 } },
  [80] = { 0, { [1] = 8 } },
  [81] = { 0, { [1] = 8 } },
  [82] = { 0, { [1] = 8 } },
  [83] = { 0, { [1] = 8 } },
  [84] = { 0, { [1] = 8 } },
  [85] = { 0, { [1] = 8 } },
  [107] = { 0, { [1] = 8 } },
  [108] = { 0, { [1] = 8 } },
  [109] = { 0, { [1] = 8 } },
  [110] = { 0, { [1] = 8 } },
  [134] = { 4, { [5] = 4, [6] = 28, [13] = 20, [15] = 1, [16] = 1, [17] = 1 } },
  [149] = { 8, { [0] = 16 } },
  [150] = { 8, { [0] = 1 } },
  [151] = { 8, { [0] = 2 } },
  [152] = { 8, { [0] = 4 } },
  [153] = { 8, { [0] = 8 } },
  [154] = { 4, { [5] = 1, [14] = 10 } },
  [155] = { 4, { [5] = 4, [13] = 10 } },
  [156] = { 8, { [0] = 32 } },
  [157] = { 8, { [0] = 63 } },
  [158] = { 4, { [5] = 4, [13] = 253 } },
  [169] = { 0, { [5] = 8, [6] = 28, [7] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [170] = { 0, { [5] = 16, [6] = 28, [8] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [171] = { 0, { [5] = 32, [6] = 28, [9] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [172] = { 0, { [5] = 128, [6] = 28, [11] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [173] = { 0, { [6] = 29, [12] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [174] = { 0, { [5] = 64, [6] = 28, [10] = 246, [15] = 10, [16] = 5, [17] = 2 } },
  [504] = { 4, { [5] = 4, [13] = 20 } },
  [565] = { 0, { [5] = 8, [6] = 30, [7] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [566] = { 0, { [5] = 16, [6] = 30, [8] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [567] = { 0, { [5] = 32, [6] = 30, [9] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [568] = { 0, { [5] = 128, [6] = 30, [11] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [569] = { 0, { [6] = 31, [12] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [570] = { 0, { [5] = 64, [6] = 30, [10] = 1, [15] = 3, [16] = 2, [17] = 1 } },
  [576] = { 1 },
  [577] = { 2 },
  [591] = { 8, { [0] = 63 } },
  [592] = { 0, { [4] = 32 } },
  [593] = { 0, { [3] = 32 } },
  [594] = { 0, { [2] = 32 } },
  [595] = { 0, { [3] = 2 } },
  [596] = { 0, { [2] = 2 } },
  [597] = { 0, { [1] = 32 } },
  [598] = { 0, { [4] = 2 } },
  [599] = { 0, { [3] = 48 } },
  [600] = { 0, { [2] = 48 } },
  [601] = { 0, { [3] = 3 } },
  [602] = { 0, { [2] = 3 } },
  [603] = { 0, { [1] = 48 } },
  [604] = { 0, { [4] = 3 } },
  [605] = { 0, { [3] = 96 } },
  [606] = { 0, { [2] = 96 } },
  [607] = { 0, { [3] = 6 } },
  [608] = { 0, { [2] = 6 } },
  [609] = { 0, { [1] = 96 } },
  [610] = { 0, { [4] = 6 } },
  [615] = { 0, { [4] = 48 } },
}

G.MASK = { BALLS = 1, BATTLE = 2, HP = 4, STATUS = 8, PP = 16 }

local function isGen5(data)
  if data and data.gen5_version then return true end
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.isGen5 and GV.isGen5() or false
end

local function blob(sparse)
  local bytes = {}
  for i = 0, 19 do bytes[i + 1] = string.char(sparse[i] or 0) end
  return table.concat(bytes)
end

-- item tables already seen (weak: a reloaded cache is a new table)
G.seen = setmetatable({}, { __mode = "k" })

-- ensure(data): stamp `battleMask`, `partyUse` and `partyUseParam` on a BW
-- cache's items that were imported without them. Once per items table.
function G.ensure(data)
  local items = data and data.items
  if type(items) ~= "table" or G.seen[items] then return items end
  G.seen[items] = true
  if not isGen5(data) then return items end
  for id, row in pairs(G.FALLBACK) do
    local def = items[id]
    if type(def) == "table" then
      if def.battleMask == nil then def.battleMask = row[1] end
      if row[2] and def.partyUseParam == nil then
        def.partyUse = 1
        def.partyUseParam = blob(row[2])
      end
    end
  end
  return items
end

-- the battle pocket mask of an item record (0 when it has none)
function G.mask(def)
  if type(def) ~= "table" then return 0 end
  local m = tonumber(def.battleMask)
  if m then return m end
  local row = G.FALLBACK[tonumber(def.id) or -1]
  return row and row[1] or 0
end

local function has(mask, bit) return math.floor(mask / bit) % 2 == 1 end
G.has = has

-- what the battle bag does with it: "ball", "escape", "battle", "medicine" or nil
function G.battleKind(def)
  if type(def) ~= "table" then return nil end
  local m = G.mask(def)
  local use = tonumber(def.battleUse) or 0
  if use == 1 or has(m, G.MASK.BALLS) then return "ball" end
  if use == 3 then return "escape" end
  if has(m, G.MASK.BATTLE) then return "battle" end
  if has(m, G.MASK.HP) or has(m, G.MASK.STATUS) or has(m, G.MASK.PP) then return "medicine" end
  return nil
end

-- the party block as bytes [0..19] (nil when the item has none)
function G.param(def)
  local s = type(def) == "table" and def.partyUseParam
  if type(s) ~= "string" or #s < 20 then
    local row = type(def) == "table" and G.FALLBACK[tonumber(def.id) or -1]
    if not (row and row[2]) then return nil end
    s = blob(row[2])
  end
  local b = {}
  for i = 0, 19 do b[i] = s:byte(i + 1) end
  return b
end

return G
