-- WHICH THEME A DS BATTLE OPENS ON, AND WHICH JINGLE ENDS IT -- read from
-- each cartridge's own tables, written as the cache module `gen4_battle_music`:
--
--   { family, byClass = { [class] = seq }, trainer = seq, wild = seq,
--     bySpecies = { [species] = seq }, kanto = { [seq] = seq },
--     winByClass = { [class] = seq }, trainerWin, wildWin }
--
-- PLATINUM (ARM9 0x020EC208, 35 rows of { u16 transition, u16 seq }): the row
-- comes from a switch on the trainer class (ARM9 0x02051C20, `subs r0, #62 /
-- movs r1, #33 / cmp r0, #40` then a 41-entry jump table whose targets are
-- each `movs r1, #row`). Default row 33 (Pokemon Trainer theme), wild row 34.
--
-- HEARTGOLD / SOULSILVER (pokeheartgold asm/unk_020517A4.s): the same row
-- table (45 rows) with, right before it, 32 u16 { class | row << 10 } and 11
-- u16 { species | row << 10 }. Default row 41 (VS_TRAINER); a wild battle
-- in Kanto plays the Kanto wild / trainer theme instead
-- (BattleSetup_GetWildBattleMusic). The jingle: WIN3 for the leaders, the
-- Elite Four and the Champion, WINBRAIN for the Frontier Brains, WIN1 for
-- everyone else, WIN2 after a wild battle (battle_controller_player.c).
--
-- BLACK / WHITE (overlay 21 0x021CF748): a 28-entry ARM9 table (0x0209FEE4)
-- of u16 { class (7 bits) | index << 7 }; an index below 11 picks from
-- overlay 21's list (rival, rival, gym, Elite Four, Champion, N, N, N 2,
-- Ghetsis, Plasma, Cynthia), anything else -- a class not in the table --
-- plays VS_TRAINER.

local M = {}

local function u16(s, at) local a, b = s:byte(at, at + 1); return b and a + b * 256 end

-- the { transition, seq } rows, found by their first four: classes' rows
-- 12..15 all on the first gym theme
local function rows(arm9)
  for seq = 1100, 1200 do
    local sig = {}
    for k = 0, 3 do
      sig[#sig + 1] = string.char(12 + k, 0, seq % 256, math.floor(seq / 256))
    end
    local at = arm9:find(table.concat(sig), 1, true)
    if at then
      local out, n = {}, 0
      while true do
        local t, s = u16(arm9, at + n * 4), u16(arm9, at + n * 4 + 2)
        if not s or s < 1000 or s > 1400 or not (t < 64 or t == 0xFFFF) then break end
        out[n] = s
        n = n + 1
      end
      return out, at, n
    end
  end
end

local function platinum(arm9, out, rowSeq)
  -- the class switch: `subs r0, #62; movs r1, #33; cmp r0, #40; bhi`
  local at = arm9:find(string.char(0x3E, 0x38, 0x21, 0x21, 0x28, 0x28), 1, true)
  if not at then return end
  local first, default, count = 0x3E, 0x21, 0x28 + 1
  -- adds r0,r0,r0 / add r0,pc / ldrh r0,[r0,#6] ... add pc,r0: the table
  -- starts 6 bytes past `add r0, pc`'s pc (its address + 4)
  local addR0Pc = at + 8 + 2               -- 1-based offset of `add r0, pc`
  local pcBase = (addR0Pc - 1) + 4          -- zero-based pc for it
  local tableAt = pcBase + 6                -- zero-based
  local addPc = addR0Pc + 8                 -- `add pc, r0`
  local branchBase = (addPc - 1) + 4        -- zero-based pc for it
  for k = 0, count - 1 do
    local off = u16(arm9, tableAt + 2 * k + 1)
    if not off then break end
    if off >= 32768 then off = off - 65536 end
    local target = branchBase + off
    local lo, hi = arm9:byte(target + 1, target + 2)
    if hi == 0x21 and lo ~= default and rowSeq[lo] then
      out.byClass[first + k] = rowSeq[lo]
    end
  end
  out.trainer = rowSeq[default]
  out.wild = rowSeq[default + 1]
end

local function hgss(arm9, out, rowSeq, at)
  -- 32 u16 classes and 11 u16 species, packed with their row
  local classAt, speciesAt = at - 64, at - 64 - 22
  for k = 0, 31 do
    local v = u16(arm9, classAt + 2 * k)
    if v and rowSeq[math.floor(v / 1024)] then out.byClass[v % 1024] = rowSeq[math.floor(v / 1024)] end
  end
  for k = 0, 10 do
    local v = u16(arm9, speciesAt + 2 * k)
    if v and rowSeq[math.floor(v / 1024)] then out.bySpecies[v % 1024] = rowSeq[math.floor(v / 1024)] end
  end
  out.trainer = rowSeq[41]
  out.wild = rowSeq[42]
end

-- parse(arm9, overlay21, family, symbols) -> record or nil, why
function M.parse(arm9, ov21, family, symbols)
  if type(arm9) ~= "string" then return nil, "no arm9" end
  symbols = symbols or {}
  local out = { family = family, byClass = {}, bySpecies = {}, kanto = {}, winByClass = {} }
  if family == "bw" then
    -- the class table: Cheren (37, index 0), Bianca (38, 1), Cilan (10, 2)
    local packed = function(c, i) local v = c + i * 128 + 17 * 2048; return string.char(v % 256, math.floor(v / 256)) end
    local at = arm9:find(packed(37, 0) .. packed(38, 1) .. packed(10, 2), 1, true)
    local list = {}
    local la = type(ov21) == "string" and ov21:find(string.char(0x6D, 4, 0x6D, 4, 0x6C, 4, 0x6F, 4), 1, true)
    if la then for k = 0, 10 do list[k] = u16(ov21, la + 2 * k) end end
    if at and la then
      for k = 0, 27 do
        local v = u16(arm9, at + 2 * k)
        if not v or v == 0 then break end
        local seq = list[math.floor(v / 128) % 16]
        if seq then out.byClass[v % 128] = seq end
      end
    end
    out.trainer, out.wild = symbols.SEQ_BGM_VS_TRAINER, symbols.SEQ_BGM_VS_NORAPOKE
    out.trainerWin, out.wildWin = symbols.SEQ_BGM_WIN2, symbols.SEQ_BGM_WIN1
    local gymWin = symbols.SEQ_BGM_WIN3
    for class, seq in pairs(out.byClass) do
      if gymWin and (seq == symbols.SEQ_BGM_VS_GYMLEADER or seq == symbols.SEQ_BGM_VS_SHITENNO
                     or seq == symbols.SEQ_BGM_VS_CHAMP) then
        out.winByClass[class] = gymWin
      end
    end
    return out
  end
  local rowSeq, at = rows(arm9)
  if not rowSeq then return nil, "battle music rows not found" end
  if family == "hgss" then
    hgss(arm9, out, rowSeq, at)
    local wildJ, wildK = symbols.SEQ_GS_VS_NORAPOKE, symbols.SEQ_GS_VS_NORAPOKE_KANTO
    local trJ, trK = symbols.SEQ_GS_VS_TRAINER, symbols.SEQ_GS_VS_TRAINER_KANTO
    if wildJ and wildK then out.kanto[wildJ] = wildK end
    if trJ and trK then out.kanto[trJ] = trK end
    out.trainerWin, out.wildWin = symbols.SEQ_GS_WIN1, symbols.SEQ_GS_WIN2
    local big = {
      [symbols.SEQ_GS_VS_GYMREADER or -1] = true, [symbols.SEQ_GS_VS_GYMREADER_KANTO or -1] = true,
      [symbols.SEQ_GS_VS_CHAMP or -1] = true,
    }
    for class, seq in pairs(out.byClass) do
      if big[seq] then out.winByClass[class] = symbols.SEQ_GS_WIN3
      elseif seq == symbols.SEQ_GS_BA_BRAIN then out.winByClass[class] = symbols.SEQ_GS_WINBRAIN end
    end
  else
    platinum(arm9, out, rowSeq)
    out.trainerWin, out.wildWin = symbols.SEQ_WINTRAIN, symbols.SEQ_WINPOKE
    for class, seq in pairs(out.byClass) do
      if seq == symbols.SEQ_BA_GYM or seq == symbols.SEQ_BA_TENNO then out.winByClass[class] = symbols.SEQ_WINTGYM
      elseif seq == symbols.SEQ_BA_CHANP then out.winByClass[class] = symbols.SEQ_WINCHAMP
      elseif seq == symbols.SEQ_PL_BA_BRAIN and symbols.SEQ_PL_WINBRAIN then out.winByClass[class] = symbols.SEQ_PL_WINBRAIN end
    end
  end
  return out
end

-- extract(x, family, sdatPath) -> battle record, eyes record: the ARM9,
-- overlay 21 (BW) and the SDAT's own sequence names
M.SDAT = { platinum = "/data/sound/pl_sound_data.sdat", hgss = "/data/sound/gs_sound_data.sdat",
           bw = "/wb_sound_data.sdat" }
function M.extract(x, family)
  local rom = x and x.rom
  if not rom then return nil end
  local symbols = {}
  local S = require("src.import.Gen4Sdat")
  local raw = rom:read(M.SDAT[family] or M.SDAT.platinum)
  local sdat = raw and S.open(raw)
  if sdat then
    for i = 0, S.count(sdat, S.SEQ) - 1 do
      local name = S.name(sdat, S.SEQ, i)
      if name then symbols[name] = i end
    end
  end
  local arm9 = rom:arm9()
  local ov21 = family == "bw" and rom.overlay and rom:overlay(21) or nil
  return M.parse(arm9, ov21, family, symbols), M.eyes(arm9, family, symbols)
end

-- THE EYES-MEET THEMES for the two cartridges Gen4TrainerMusic does not read,
-- in its `{ byClass, default }` shape:
--   HGSS (field_bgm.c sTrainerEncounterMusicParam): rows of u16 { class,
--     Johto theme, Kanto theme }, found by Youngster's / Lass's first two;
--     a class not listed gets SEQ_GS_EYE_J_SHOUNEN.
--   BW (ARM9 0x020A75A8 in Black): rows of u16 { class, theme }, found by
--     Youngster / Lass / School Kids (2..5 on EYE_01 / EYE_02).
function M.eyes(arm9, family, symbols)
  if type(arm9) ~= "string" then return nil end
  symbols = symbols or {}
  local out = { byClass = {}, kantoByClass = {} }
  local function pair(a, b) return string.char(a % 256, math.floor(a / 256), b % 256, math.floor(b / 256)) end
  if family == "hgss" then
    local j, k = symbols.SEQ_GS_EYE_J_SHOUNEN or 1108, symbols.SEQ_GS_EYE_K_SHOUJO or 1113
    local at
    for p = 1, #arm9 - 12, 2 do
      if u16(arm9, p + 2) == j and u16(arm9, p + 4) == j and u16(arm9, p + 8) == k and u16(arm9, p + 10) == k then
        at = p break
      end
    end
    if not at then return nil end
    local n = 0
    while true do
      local c, a, b = u16(arm9, at + n * 6), u16(arm9, at + n * 6 + 2), u16(arm9, at + n * 6 + 4)
      if not b or c > 255 or a < 1100 or a > 1130 or b < 1100 or b > 1130 then break end
      if out.byClass[c] == nil then out.byClass[c] = a; out.kantoByClass[c] = b end
      n = n + 1
    end
    out.default, out.rows = j, n
  elseif family == "bw" then
    local e1, e2 = symbols.SEQ_BGM_EYE_01 or 1114, symbols.SEQ_BGM_EYE_02 or 1115
    local at = arm9:find(pair(2, e1) .. pair(3, e2) .. pair(4, e1) .. pair(5, e2), 1, true)
    if not at then return nil end
    local n = 0
    while true do
      local c, s = u16(arm9, at + n * 4), u16(arm9, at + n * 4 + 2)
      if not s or c > 255 or s < 1100 or s > 1200 then break end
      if out.byClass[c] == nil then out.byClass[c] = s end
      n = n + 1
    end
    out.rows = n
  else
    return nil
  end
  return out
end

-- ---------------------------------------------------------------------------
-- runtime
-- ---------------------------------------------------------------------------

local function inKanto(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  local header = def and def.gen4Header
  local region = (header and header.region) or (def and def.region)
  return tonumber(region) ~= nil and tonumber(region) ~= 0
end

-- choose(data, battle) -> seq (the opening theme) or nil
function M.choose(data, battle)
  local rec = data and data.gen4_battle_music
  if not (rec and battle) then return nil end
  local seq
  if battle.kind == "trainer" and battle.trainer then
    seq = rec.byClass[tonumber(battle.trainer.class)] or rec.trainer
  else
    local mon = battle.enemy and battle.enemy.mon
    seq = (mon and rec.bySpecies[tonumber(mon.species)]) or rec.wild
  end
  if seq and rec.kanto and rec.kanto[seq] and inKanto(battle.game) then seq = rec.kanto[seq] end
  return seq
end

-- victory(data, battle) -> seq or nil
function M.victory(data, battle)
  local rec = data and data.gen4_battle_music
  if not (rec and battle) then return nil end
  if battle.kind == "trainer" and battle.trainer then
    return rec.winByClass[tonumber(battle.trainer.class)] or rec.trainerWin
  end
  return rec.wildWin
end

return M
