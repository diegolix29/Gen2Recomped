-- PAL PARK'S SPECIES TABLE (Platinum /arc/ppark.narc, HeartGold / SoulSilver
-- /a/1/2/5 -- the same 2958 bytes in both), for the Catching Show
-- (src/world/Gen4PalPark.lua).
--
-- Member 0 is one six-byte record per national dex number from 1, read by
-- `BufferSpeciesData` (catching_show.c) at `(species - 1) * 6`:
--
--   0  landArea        1 forest, 2 mountain, 3 field (0: lives in water)
--   1  waterArea       2 pond, 4 sea (0: lives on land)
--   2  catchingPoints  what catching it is worth
--   3  rarity          its weight in the area's encounter roll
--   4, 5               unused by the show
--
-- extract(x) -> { species = { [dex] = { land, water, points, rarity } }, count }

local M = {}

M.PATHS = { platinum = "/arc/ppark.narc", hgss = "/a/1/2/5" }
M.RECORD = 6

function M.parse(bytes)
  if type(bytes) ~= "string" then return nil, "no species table" end
  local species, n = {}, 0
  for dex = 1, math.floor(#bytes / M.RECORD) do
    local at = (dex - 1) * M.RECORD
    local land, water, points, rarity = bytes:byte(at + 1, at + 4)
    species[dex] = { land = land, water = water, points = points, rarity = rarity }
    n = dex
  end
  return { species = species, count = n }
end

function M.extract(x)
  local family = require("src.import.Gen4Versions").family(x.version)
  local path = M.PATHS[family] or M.PATHS.platinum
  local ok, raw = pcall(x.rom.read, x.rom, path)
  if not (ok and raw) then return nil, "no " .. path end
  local narc, why = require("src.import.NarcArchive").parse(raw)
  if not narc then return nil, why end
  local member = narc:get(0)
  if not member then return nil, path .. " has no member 0" end
  return M.parse(member)
end

return M
