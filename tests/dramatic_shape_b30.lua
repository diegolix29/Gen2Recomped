-- Regression test for the Dramatic Shape B30 (Pokemon Tower) profile.
-- This is intentionally ROM-free: the profile is data-driven and should be
-- loadable without booting the game or importing a ROM.

local profile = dofile("mods/DRAMATIC_SHAPE/data/voxel_heights.lua")
local entries = assert(profile.buildings and profile.buildings.OVERWORLD,
  "Dramatic Shape OVERWORLD building profiles are missing")

local tower
for _, entry in ipairs(entries) do
  if entry.id == "pokemon_tower" then
    tower = entry
    break
  end
end

assert(tower, "B30 must have a pokemon_tower profile")
assert(tower.silhouette == "footprint",
  "B30 must use the explicit footprint silhouette")
assert(tower.roofRows == 0,
  "B30 must remain roofless; do not restore the synthetic roof")
assert(tower.slab == 0 and tower.frontEave == 0,
  "B30's roofless profile must not add a synthetic cap or eave")
assert(#tower.tiles == 8 and #tower.tiles[1] == 12,
  "B30's matched footprint must remain 12x8 tiles")
assert(tower.topRows and #tower.topRows == 12,
  "B30 must retain the twelve rows carried by the map boundary")

local claimOnly
for _, entry in ipairs(entries) do
  if entry.id == "pokemon_tower_top" then
    claimOnly = entry
    break
  end
end
assert(claimOnly and claimOnly.claimOnly,
  "B30's off-map half must remain claim-only")

print("PASS Dramatic Shape B30 profile")
