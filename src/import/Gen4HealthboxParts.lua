-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4HealthboxParts.lua -- THE PIECES A HEALTHBOX IS FINISHED WITH.
--
-- Everything else on a Platinum healthbox comes out of an archive: the frame is
-- an NCGR paired with a cell bank, the palette is the family's NCLR. THE GAUGES
-- ARE NOT. `healthbox.c` reaches for them through
--
--     GetHealthBoxPartsTile(part) -> &sHealthBoxPartsBitmap[part * 32]
--
-- and `sHealthBoxPartsBitmap` is
-- `#include "res/graphics/battle/healthbox/healthbox_parts.4bpp.h"` -- A PLAIN
-- ARRAY COMPILED INTO THE BATTLE OVERLAY. That is why the graphics stage, which
-- walks archives, has never seen it: it is not in one.
--
-- 78 TILES, 4bpp, in the order `enum HealthBoxPart` declares. The gauges are
-- four nine-tile ramps inside it, and the rest is the furniture the box is
-- lettered with -- the "HP" glyphs, the slash, the two digit strips, the bar
-- end, the six status icons, the gendered "Lv" cells and the caught-species
-- ball.
--
-- ---------------------------------------------------------------------------
-- HOW IT IS FOUND, AND WHY NOT BY ADDRESS
--
-- A hard-coded offset is a fact about ONE build. The port already scans the
-- overlays for the type chart and for the object-graphics table rather than
-- naming an address, and this follows them -- but the signature is structural
-- rather than a run of bytes, so nothing cartridge-derived is written down here.
--
-- TWO PROPERTIES, BOTH OUT OF THE ENUM:
--
--  1. GREEN_FILL_0, YELLOW_FILL_0 and RED_FILL_0 are the SAME TILE. An empty
--     gauge looks the same whatever colour it would have filled in, and the
--     enum spaces the three ramps exactly nine tiles apart -- so three
--     byte-identical 32-byte blocks at 288-byte spacing. Cheap, and it is the
--     prefilter.
--  2. Within a ramp, tile k differs from tile 0 in EXACTLY k times a constant
--     number of nibbles -- one more pixel column filled per step, over however
--     many rows that gauge is tall. Four ramps must verify at +2, +11, +20 and
--     +29 tiles from the blob's start.
--
-- MEASURED OVER THE WHOLE CARTRIDGE -- the ARM9 binary and all 122 overlays --
-- property 2 alone matches in exactly FOUR places, and all four are the four
-- ramps, consecutive, in overlay 16. The battle overlay. Property 1 alone
-- matches 542 times, which is why it is only the prefilter; together they are
-- unique.
--
-- The HP ramps step over TWO rows and the EXP ramp over ONE, and that is not
-- a detail: it is the same one-versus-two the assembled box art shows, where
-- the HP trough is two pixels deep at rows 35-36 and the EXP groove is a single
-- row at 50. Two unrelated readings of the same fact.

local Gen4HealthboxParts = {}

-- enum HealthBoxPart, in declaration order (src/battle/healthbox.c).
Gen4HealthboxParts.PARTS = {
  "hp_h", "hp_p",
  "hp_green_fill_0", "hp_green_fill_1", "hp_green_fill_2", "hp_green_fill_3",
  "hp_green_fill_4", "hp_green_fill_5", "hp_green_fill_6", "hp_green_fill_7",
  "hp_green_fill_8",
  "hp_yellow_fill_0", "hp_yellow_fill_1", "hp_yellow_fill_2",
  "hp_yellow_fill_3", "hp_yellow_fill_4", "hp_yellow_fill_5",
  "hp_yellow_fill_6", "hp_yellow_fill_7", "hp_yellow_fill_8",
  "hp_red_fill_0", "hp_red_fill_1", "hp_red_fill_2", "hp_red_fill_3",
  "hp_red_fill_4", "hp_red_fill_5", "hp_red_fill_6", "hp_red_fill_7",
  "hp_red_fill_8",
  "exp_fill_0", "exp_fill_1", "exp_fill_2", "exp_fill_3", "exp_fill_4",
  "exp_fill_5", "exp_fill_6", "exp_fill_7", "exp_fill_8",
  "status_healthy_0", "status_healthy_1", "status_healthy_2",
  "status_paralysis_0", "status_paralysis_1", "status_paralysis_2",
  "status_freeze_0", "status_freeze_1", "status_freeze_2",
  "status_sleep_0", "status_sleep_1", "status_sleep_2",
  "status_poison_0", "status_poison_1", "status_poison_2",
  "status_burn_0", "status_burn_1", "status_burn_2",
  "empty_0", "empty_1", "empty_2",
  "caught_indicator",
  "level_female_top_0", "level_female_top_1",
  "level_male_top_0", "level_male_top_1",
  "level_genderless_top_0", "level_genderless_top_1",
  "hp_h_2", "hp_p_2", "bar_end", "slash",
  "numbers_left", "numbers_right",
  "level_female_bottom_0", "level_female_bottom_1",
  "level_male_bottom_0", "level_male_bottom_1",
  "level_genderless_bottom_0", "level_genderless_bottom_1",
}

Gen4HealthboxParts.COUNT = #Gen4HealthboxParts.PARTS   -- 78
Gen4HealthboxParts.TILE_BYTES = 32                      -- TILE_SIZE_4BPP
Gen4HealthboxParts.TILES_WIDE = 9                       -- one ramp per row

-- The four ramps, as ZERO-BASED part indices of their FILL_0, straight off the
-- enum: HP_GREEN is part 2, and each ramp is nine tiles.
Gen4HealthboxParts.RAMPS = {
  { name = "hp_green",  at = 2,  cells = 6,  rows = 2 },
  { name = "hp_yellow", at = 11, cells = 6,  rows = 2 },
  { name = "hp_red",    at = 20, cells = 6,  rows = 2 },
  { name = "exp",       at = 29, cells = 12, rows = 1 },
}
Gen4HealthboxParts.RAMP_TILES = 9      -- FILL_0 .. FILL_8
Gen4HealthboxParts.RAMP_SPACING = 9    -- tiles between one FILL_0 and the next

-- HEALTHBOX_HP_CELL_COUNT 6 / HEALTHBOX_EXP_CELL_COUNT 12, and CalcGaugeFill's
-- own comment: "gauges have 8 pixels per 'square' of fill". 48 and 96 pixels.
Gen4HealthboxParts.HP_CELLS, Gen4HealthboxParts.EXP_CELLS = 6, 12
Gen4HealthboxParts.CELL_PX = 8

local function nibbleDiff(a, b)
  local d = 0
  for i = 1, #a do
    local x, y = a:byte(i), b:byte(i)
    if x % 16 ~= y % 16 then d = d + 1 end
    if math.floor(x / 16) ~= math.floor(y / 16) then d = d + 1 end
  end
  return d
end

-- Is there a nine-tile ramp at `at` (a 1-based byte offset into `bin`)?
-- Returns the per-step nibble count, which is the gauge's height in rows.
function Gen4HealthboxParts.rampAt(bin, at)
  local T = Gen4HealthboxParts.TILE_BYTES
  if at < 1 or at + T * Gen4HealthboxParts.RAMP_TILES - 1 > #bin then return nil end
  local first = bin:sub(at, at + T - 1)
  local step = nibbleDiff(first, bin:sub(at + T, at + 2 * T - 1))
  -- A step of zero is a flat run of identical tiles (there are many in a
  -- binary); a step above eight cannot be "one more pixel column" in an
  -- eight-wide tile.
  if step < 1 or step > 8 then return nil end
  for k = 2, Gen4HealthboxParts.RAMP_TILES - 1 do
    local t = bin:sub(at + T * k, at + T * (k + 1) - 1)
    if nibbleDiff(first, t) ~= step * k then return nil end
  end
  return step
end

-- Find sHealthBoxPartsBitmap in one overlay's bytes.
-- Returns a 1-based byte offset of PART 0, or nil.
function Gen4HealthboxParts.find(bin)
  if type(bin) ~= "string" then return nil end
  local T = Gen4HealthboxParts.TILE_BYTES
  local span = T * Gen4HealthboxParts.RAMP_SPACING          -- 288
  local blobBytes = T * Gen4HealthboxParts.COUNT            -- 2496
  local zero = string.rep("\0", T)
  local at = 1
  while at + 2 * span + T - 1 <= #bin do
    local blk = bin:sub(at, at + T - 1)
    -- The prefilter: three identical non-blank tiles, nine tiles apart.
    if blk ~= zero
       and bin:sub(at + span, at + span + T - 1) == blk
       and bin:sub(at + 2 * span, at + 2 * span + T - 1) == blk then
      -- `at` would be GREEN_FILL_0, which the enum puts at part 2.
      local blob = at - 2 * T
      if blob >= 1 and blob + blobBytes - 1 <= #bin then
        local ok = true
        for _, ramp in ipairs(Gen4HealthboxParts.RAMPS) do
          local step = Gen4HealthboxParts.rampAt(bin, blob + ramp.at * T)
          -- The step is the gauge's height in rows, and the enum says which
          -- gauge this is -- so a ramp that steps over the wrong number of rows
          -- is not the ramp we are looking for.
          if step ~= ramp.rows then ok = false break end
        end
        if ok then return blob end
      end
    end
    at = at + 4                 -- the array is word-aligned, not tile-aligned
  end
  return nil
end

return Gen4HealthboxParts
