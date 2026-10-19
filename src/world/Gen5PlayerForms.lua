-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK AND WHITE'S PLAYER SHEETS: walk, bike and surf.
--
-- The BW sprite table (gen5_sprite_table, Gen5Field) lists the player's
-- sheets three to a gender: row 1 walk / run (32 frames), row 2 the BICYCLE
-- (16 frames: up, down, left, right three each, as the walk), row 3 the SURF
-- rider (4 frames, one a facing, seated -- the sea_ride model goes under it);
-- rows 4..6 are the heroine's. The first importer took row 3 for the bike, so
-- the player rode a bicycle sitting cross-legged on nothing and surfed as a
-- walker with no mount. Measured off the sheets: scratch_claude/bw_field/z7.png
-- and z8.png.

local P = {}

P.SURF_FACINGS = { up = { 0, 0, 0 }, down = { 1, 1, 1 }, left = { 2, 2, 2 }, right = { 3, 3, 3 } }

local function id(n) return n and ("SPRITE_G4_%03d"):format(n) or nil end

-- the surf sheets' frame order, on the sprite records themselves
function P.facings(sprites, spriteTable)
  if not (sprites and spriteTable) then return end
  for _, row in ipairs({ 3, 6 }) do
    local def = sprites[id(spriteTable[row])]
    if def and not def.facings and (tonumber(def.frames) or 0) == 4 then
      def.facings = P.SURF_FACINGS
      def.walker = true
    end
  end
end

-- fix(data, form) -> the form with bike / surf as the table states them, for
-- a cache imported before the importer knew (Player.refreshForm calls this)
function P.fix(data, form)
  if not (data and type(form) == "table" and require("src.core.GameVersion").isGen5()) then return form end
  local n = tonumber(tostring(form.walk or ""):match("^SPRITE_G4_(%d+)$"))
  if not n then return form end
  local sprites = data.sprites or {}
  -- the runtime does not load gen5_sprite_table; the three sheets are
  -- consecutive members (6 / 7 / 8 and 9 / 10 / 11), checked by shape
  if not form.surf then
    local bike, surf = sprites[id(n + 1)], sprites[id(n + 2)]
    if bike and (tonumber(bike.frames) or 0) >= 12 and surf and (tonumber(surf.frames) or 0) == 4 then
      form.bike, form.surf = id(n + 1), id(n + 2)
      if not surf.facings then surf.facings, surf.walker = P.SURF_FACINGS, true end
    end
  end
  -- THE ROD: /a/0/4/9 members 156 / 157 (texture t8x8fishgirl.., 64 x 64
  -- frames): four a facing -- up 0-3, down 4-7, left 8-11, right the left
  -- mirrored -- raise, draw back, swing, line out (Gen4FishingTask.BW_POSE)
  if not form.fishing then
    local fish = sprites[id(n + 150)]
    if fish and (tonumber(fish.frames) or 0) == 12 then form.fishing = id(n + 150) end
  end
  return form
end

return P
