-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S RADIO IN THE FIELD.
--
-- Leaving the Pokegear's radio with a station tuned does not bring the map's
-- music back (Radio_VideoUnload: only an untuned dial, the jingle or the
-- commercials fade to `mapMusicID`), so the station's sequence keeps playing
-- on the radio player while the player walks -- until something else takes
-- the music (a new map, a battle).
--
-- GetRadioMusicPlayingSeq (src/field/overlay_2_gear_phone.c) reads that
-- player and answers one of:
--
--   0 NONE  1 MARCH  2 LULLABY  3 HOENN SOUNDS  4 SINNOH SOUNDS
--   5 POKE FLUTE  6 UNOWN
--
-- which the field reads: Route 12's / Route 11's Snorlax wakes only to the
-- Poke Flute (`RadioMusicIsPlaying 5`), and encounter_check.c's rate and slots
-- answer the march, the lullaby and the two Sounds.

local M = {}

M.NONE, M.MARCH, M.LULLABY, M.HOENN, M.SINNOH, M.POKEFLUTE, M.UNOWN = 0, 1, 2, 3, 4, 5, 6

M.SEQ = {
  SEQ_GS_RADIO_MARCH = 1, SEQ_GS_P_RADIO_MARCH = 1,
  SEQ_GS_RADIO_KOMORIUTA = 2, SEQ_GS_P_RADIO_KOMORIUTA = 2,
  SEQ_GS_RADIO_R_101 = 3,
  SEQ_GS_RADIO_R_201 = 4,
  SEQ_GS_HUE = 5, SEQ_GS_P_HUE = 5,
  SEQ_GS_RADIO_UNKNOWN = 6,
}

local function Music()
  local ok, m = pcall(require, "src.core.Music")
  return ok and m or nil
end

local function mapId(game)
  local states = game and game.stack and game.stack.states or {}
  for i = #states, 1, -1 do
    local st = states[i]
    if type(st) == "table" and st.player and st.map then return st.map.id end
  end
  local player = game and game.save and game.save.player
  return player and player.map
end

-- the radio app is closing on `song` (a SEQ_* label) -- it keeps playing
function M.keep(game, song)
  if type(game) ~= "table" then return end
  if not (song and M.SEQ[song]) then game.hgssRadioSong = nil return end
  local mu = Music()
  game.hgssRadioSong = { song = song, playing = mu and mu.current() or nil, map = mapId(game) }
end

function M.clear(game)
  if type(game) == "table" then game.hgssRadioSong = nil end
end

-- GetRadioMusicPlayingSeq. Still playing while the music is the label the
-- radio left on; with no audio (a headless run) the label is never set, and
-- the map the player tuned it on stands in for it.
function M.current(game)
  local rec = type(game) == "table" and game.hgssRadioSong
  if not rec then return M.NONE end
  local mu = Music()
  local now = mu and mu.current() or nil
  local live
  if rec.playing ~= nil then live = (now == rec.playing)
  else live = (now == nil and rec.map == mapId(game)) end
  if not live then game.hgssRadioSong = nil return M.NONE end
  return M.SEQ[rec.song] or M.NONE
end

return M
