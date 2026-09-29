-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PATCH OF DARK UNDER EVERYBODY, which Sinnoh has and this port did not.
--
-- Reported from play: *"things ... are missing the shadows completely"*.  They
-- were, and every part of the answer is in the cartridge rather than in a
-- judgement call, which is why this file is mostly citations.
--
-- WHO CASTS ONE.  `gObjectEventGfxRenderDetailsTable`
-- (overlay005/object_event_gfx_data.c) is one row per graphics id:
--
--     u32 graphicsID;
--     u32 modelType:4 | hasShadow:2 | trackType:4 | hasReflection:2 | pad:20
--
-- terminated by a row whose id is 0xFFFF.  **259 rows, 230 of them casting a
-- shadow** and 243 carrying a reflection -- which is also, incidentally, the
-- table that says which sprites leave footprints.
--
-- FOUND BY SHAPE, not transcribed.  The first six rows are 48 bytes and they
-- occur EXACTLY ONCE in the 128 MB cartridge, at ROM offset 0x17CA14 -- inside
-- overlay 5, at 0x2B414, which is the overlay the source file is named after.
-- Read back and compared against all 259 of pret's rows: identical, every
-- field.  So the port reads the cartridge and pret is the check, rather than
-- the other way round.
--
-- WHEN IT IS SUPPRESSED.  `sub_02063A78` / `sub_02063B20` (map_object_move.c)
-- turn the shadow off when the tile underfoot is tall grass, very tall grass,
-- water, a puddle, shallow water, snow, mud, mud-with-grass or reflective --
-- nine behaviours, and the ninth is why a character standing on a polished
-- floor has a reflection instead.
--
-- WHAT IT LOOKS LIKE.  `data/mmodel/fldeff.narc` member 0x11 is an NSBMD named
-- `kage` -- Japanese for shadow -- 12 vertices in 4 quads at posScale 2.0,
-- with its texture EMBEDDED: `kage`, 16x16, format 2, worn with palette
-- `kage_pl`.  (Members 0x12 and 0x13 are `red_mark` and `blue_mark`, which the
-- same renderer holds and which are not shadows.)
--
-- HOW BIG.  `Unk_ov5_02200284` is five sizes in world units -- 14, 18, 18, 8,
-- 4 -- and `Unk_ov5_022002E4` five XYZ scales to go with them.  The object's
-- own `hasShadow` picks which.

local Gen4Shadow = {}

Gen4Shadow.ROW_BYTES = 8
Gen4Shadow.SENTINEL = 0xFFFF

-- The model, and the texture inside it.
Gen4Shadow.ARCHIVE = "/data/mmodel/fldeff.narc"
Gen4Shadow.MEMBER = 0x11
Gen4Shadow.TEXTURE = "kage"
Gen4Shadow.PALETTE = "kage_pl"

-- `Unk_ov5_02200284`, in world units across.  One tile is 16, so the ordinary
-- shadow is a little narrower than the tile it sits on and the largest is a
-- little wider.
Gen4Shadow.SIZES = { 14, 18, 18, 8, 4 }

-- `Unk_ov5_022002E4`, the XYZ multiplier each size is drawn with.  Y is 1 on
-- every one of them, which is what says these are flat on the ground.
Gen4Shadow.SCALES = {
  { x = 1,      y = 1, z = 1      },
  { x = 1.25,   y = 1, z = 1.25   },
  { x = 1.25,   y = 1, z = 1      },
  { x = 1.125,  y = 1, z = 1      },
  { x = 0.875,  y = 1, z = 0.875  },
}

-- The nine behaviours that turn it off, by the cartridge's own NAMES rather
-- than by a list of numbers: the numbering is this cartridge's and the names
-- are what `TileBehavior_IsTallGrass` and its eight siblings are asking about.
Gen4Shadow.SUPPRESS_PATTERNS = {
  "GRASS",           -- tall grass, very tall grass, and mud-with-grass
  "^MUD",            -- mud
  "^PUDDLE",         -- puddles
  "SHALLOW_WATER",   -- shallow water
  "^WATER",          -- water
  "^SNOW",           -- snow
  "REFLECT",         -- a reflective floor: you get a reflection instead
}

-- Which behaviour values those come to on this cartridge.
function Gen4Shadow.suppressed(Gen4Behaviors)
  local out, seen = {}, {}
  for _, pattern in ipairs(Gen4Shadow.SUPPRESS_PATTERNS) do
    for _, value in ipairs(Gen4Behaviors.matching(pattern) or {}) do
      if not seen[value] then seen[value] = true; out[#out + 1] = value end
    end
  end
  -- ...and everything the cartridge calls surfable, which is the water test
  -- `MapObject_IsOnWater` makes and is a flag rather than a name.
  for _, value in ipairs(Gen4Behaviors.group("surfable") or {}) do
    if not seen[value] then seen[value] = true; out[#out + 1] = value end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------------------

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- The first six rows: graphics ids 0..5, every one of them a billboard with a
-- shadow, footsteps and a reflection (`1 | 1<<4 | 1<<6 | 1<<10` = 0x451).
Gen4Shadow.ANCHOR = (function()
  local out = {}
  for id = 0, 5 do
    out[#out + 1] = string.char(id, 0, 0, 0, 0x51, 0x04, 0, 0)
  end
  return table.concat(out)
end)()

-- parse(bytes, at) -> { [graphicsId] = { model, shadow, track, reflection } }
function Gen4Shadow.parse(bytes, at)
  if type(bytes) ~= "string" or type(at) ~= "number" then return nil end
  local out, rows = {}, 0
  local p = at
  while p + Gen4Shadow.ROW_BYTES - 1 <= #bytes do
    local id, bits = u32(bytes, p - 1), u32(bytes, p + 3)
    if not bits then break end
    if id == Gen4Shadow.SENTINEL then break end
    out[id] = {
      model = bits % 16,
      shadow = math.floor(bits / 16) % 4,
      track = math.floor(bits / 64) % 16,
      reflection = math.floor(bits / 1024) % 4,
    }
    rows = rows + 1
    p = p + Gen4Shadow.ROW_BYTES
    -- A table that never reaches its sentinel is a wrong anchor, not a long
    -- table.  The cartridge's is 259 rows.
    if rows > 1024 then return nil, "runaway" end
  end
  if rows == 0 then return nil, "empty" end
  return out, rows
end

-- Where the table is in a binary, and how many places it could be.
function Gen4Shadow.find(bytes)
  if type(bytes) ~= "string" then return nil end
  local at, first, hits = 1, nil, 0
  while true do
    local found = bytes:find(Gen4Shadow.ANCHOR, at, true)
    if not found then break end
    if Gen4Shadow.parse(bytes, found) then
      hits = hits + 1
      first = first or found
    end
    at = found + 1
  end
  return first, hits
end

return Gen4Shadow
