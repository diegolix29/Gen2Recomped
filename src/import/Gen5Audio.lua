-- BLACK AND WHITE'S SOUND (/wb_sound_data.sdat), catalogued in the shape
-- Gen4Audio writes for Platinum, so Music / NitroAudio play it unchanged.
--
-- The SDAT is the DS's own format (SYMB names survive: SEQ_BGM_VS_TRAINER,
-- SEQ_BGM_EYE_01 ...), so Gen4Sdat reads it as it reads Platinum's.
--
-- A ZONE'S MUSIC is four u16 at zone header +0x0C (Gen5Maps `music`), one per
-- season -- spring, summer, autumn, winter. The season is the month's place
-- in a four-month cycle (January spring ... April winter, May spring again),
-- so `mapSongs` carries the current season's and `mapSeasonSongs` all four.
--
-- The battle themes are the SDAT's names; which trainer gets which is
-- Gen4BattleMusic's job (by class), these are the defaults and the jingles.

local S = require("src.import.Gen4Sdat")
local A = {}

A.PATH = "/wb_sound_data.sdat"

function A.season(month)
  month = tonumber(month) or tonumber(os.date("%m")) or 1
  return (month - 1) % 4 + 1
end

function A.catalogue(sdat, zones)
  local out = { songs = {}, sfx = {}, mapSongs = {}, mapNightSongs = {}, mapSeasonSongs = {},
                outdoorSongs = {}, special = {}, battle = {} }
  local symbols = {}
  for i = 0, S.count(sdat, S.SEQ) - 1 do
    local seq, name = S.sequence(sdat, i), S.name(sdat, S.SEQ, i)
    if seq and name then
      local def = { nds = i, name = name }
      out.songs[i] = def; out.songs[name] = def
      out.sfx[i] = def; out.sfx[name] = def
      symbols[name] = i
    end
  end
  local season = A.season()
  for id, z in pairs(zones or {}) do
    local m = z.music
    if type(m) == "table" and m[1] then
      local key = ("Z%03d"):format(id)
      out.mapSeasonSongs[key] = { m[1], m[2], m[3], m[4] }
      local song = m[season] or m[1]
      if song and song ~= 0 and song ~= 0xFFFF then out.mapSongs[key] = song end
    end
  end
  local s = symbols
  out.special = {
    -- overlay 88's title proc plays 0x3EF (SEQ_BGM_POKEMON_THEME); the opening
    -- movies play SEQ_BGM_TITLE / TITLE01 (overlay 179's scripts)
    title = s.SEQ_BGM_POKEMON_THEME or s.SEQ_BGM_TITLE, opening = s.SEQ_BGM_TITLE,
    evolution = s.SEQ_BGM_SHINKA, evolved = s.SEQ_ME_SHINKAOME,
    bike = s.SEQ_BGM_BICYCLE, surf = s.SEQ_BGM_NAMINORI,
    heal = s.SEQ_ME_ASA,
    -- Juniper's speech ("Introduction") and its closing part, and the two
    -- versions' opening movies
    professor = s.SEQ_BGM_STARTING, professorEnd = s.SEQ_BGM_STARTING2,
    openingBlack = s.SEQ_BGM_OPENING_TITLE_B, openingWhite = s.SEQ_BGM_OPENING_TITLE_W,
  }
  out.battle = {
    wild = s.SEQ_BGM_VS_NORAPOKE, strongWild = s.SEQ_BGM_VS_TSUYOPOKE,
    trainer = s.SEQ_BGM_VS_TRAINER, gym = s.SEQ_BGM_VS_GYMLEADER,
    rival = s.SEQ_BGM_VS_RIVAL, plasma = s.SEQ_BGM_VS_PLASMA,
    eliteFour = s.SEQ_BGM_VS_SHITENNO, champion = s.SEQ_BGM_VS_CHAMP, final = s.SEQ_BGM_VS_CHAMP,
    n = s.SEQ_BGM_VS_N, ghetsis = s.SEQ_BGM_VS_G_CIS, subway = s.SEQ_BGM_VS_SUBWAY_TRAINER,
    wildWin = s.SEQ_BGM_WIN1, trainerWin = s.SEQ_BGM_WIN2, gymWin = s.SEQ_BGM_WIN3,
    championWin = s.SEQ_BGM_WIN3, finalWin = s.SEQ_BGM_WIN3,
  }
  for role, name in pairs({ PkmnHealed = "SEQ_ME_ASA" }) do
    if s[name] then out.sfx[role] = out.sfx[s[name]] end
  end
  return out
end

-- build(x, zones) -> audio record (and the SDAT copied into the cache)
function A.build(x, zones)
  local raw = x.rom:read(A.PATH)
  local sdat = raw and S.open(raw)
  if not sdat then return nil end
  local audio = A.catalogue(sdat, zones)
  audio.ndsArchive = x:saveBinary("sound/wb_sound_data.sdat", raw)
  audio.source = "ROM:" .. tostring(x.version) .. " " .. A.PATH
  return audio
end

return A
