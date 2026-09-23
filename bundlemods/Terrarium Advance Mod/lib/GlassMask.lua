-- Voxel world mode: the glass in the windows, found rather than listed.
--
-- Buildings and doors in the overworld art carry small panes -- framed in
-- black, with a diagonal shine drawn in. This module finds them by SHAPE in
-- the tileset image itself: a border row of black texels, some rows of
-- black-flanked non-black glass under it, and a closing border row. No tile
-- ids are hardcoded, so a total conversion that draws its own windows in
-- the same idiom gets glass for free, and art with no windows gets an empty
-- mask and costs nothing.
--
-- "Some rows" of "a" width covers most of what's out there (see WIDTHS and
-- ROWS_MIN/ROWS_MAX below), but not everything: a handful of real panes are
-- drawn in ways the shape rules still can't safely generalize to without
-- also catching art that isn't glass (see the MANUAL table -- each entry
-- there was checked by hand against the actual tileset, not guessed).
--
-- The scan slides at PIXEL granularity because the art does: the building
-- window sits a row down inside its tile, and the door's pane straddles a
-- 2x2 tile block entirely -- a per-tile matcher finds neither.
--
-- What the scan yields is a MASK TEXTURE the same size as the tileset
-- atlas: opaque white on glass texels, transparent everywhere else. Terrain
-- meshes sample the atlas by normalized coordinates (ChunkMesher.uvRect),
-- so the scene shader can sample this mask with the SAME coordinates and
-- know, per fragment, whether it is drawing glass -- on any wall, at any
-- angle, in free-roam or a staged battle, with no geometry work anywhere.
-- The recoloured atlases (display modes, RED++) keep the tileset's layout,
-- so the alignment holds under every palette.
--
-- What the shader does with the answer (Voxel3D): by day a thin glint
-- sweeps across the panes -- a pseudo reflection, view-anchored, preserving
-- the art under it -- and after dark the panes are LIT: the texel's own
-- shine pattern, warmed and brightened, exempt from the sun, the shadow
-- map and the hour's tint, as a window with a lamp behind it is.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")

local GlassMask = {}

-- pane geometry the scan accepts. Kanto's simplest door/building panes are
-- six glass texels across with 4 or 5 rows between the two border rows, but
-- that turned out to be the FLOOR of what the art actually draws, not the
-- whole of it: Johto (and a couple of spots in Kanto itself) use wider
-- panes, taller multi-storey panes with no black divider between floors,
-- and small accent windows. Rather than one fixed width and two exact row
-- counts, the scan now tries a short list of widths and accepts any row
-- count in a range -- still found by shape, still no tile ids hardcoded.
GlassMask.WIDTHS = { 6, 8 }      -- glass texels across a pane
GlassMask.ROWS_MIN = 3
GlassMask.ROWS_MAX = 16

-- kept for anything still reading the old names
GlassMask.GLASS_W = GlassMask.WIDTHS[1]
GlassMask.ROWS = { 4, 5 }

-- Whether a channel triple is the border black. The raw tileset art is the
-- four DMG greys, so black is genuinely zero; the threshold forgives a
-- rescaled asset without accepting the dark grey rung (85/255 = 0.33).
local function isBlack(r, g, b)
  return r < 0.12 and g < 0.12 and b < 0.12
end

GlassMask._isBlack = isBlack     -- named for the suite

-- A few panes are drawn in a way the shape rules above still don't cover,
-- checked by hand against the actual art (not guessed): a 4-pane lattice
-- window whose glass strips are a single texel wide (any WIDTHS entry that
-- narrow matches far too much incidental art to scan for generally), a
-- small accent window the same width, and a barred window whose bottom
-- edge is never closed by a black row in the source art at all -- it just
-- runs into the wall texture below it. Keyed by the tileset's `id` when the
-- caller has one, and by the basename of `image` otherwise, so this covers
-- a tileset under whichever name the engine hands GlassMask. Rects are
-- glass-only, in the same {x, y, w, h} convention `scan` returns.
local johtoOverworldPanes = {
  { x = 59, y = 12, w = 2, h = 3 },   -- small accent window
  { x = 60, y = 28, w = 8, h = 4 },   -- barred window, open bottom edge
  { x = 36, y = 56, w = 1, h = 4 },   -- 4-pane lattice, outer-left
  { x = 38, y = 56, w = 1, h = 4 },   -- 4-pane lattice, inner-left
  { x = 49, y = 56, w = 1, h = 4 },   -- 4-pane lattice, inner-right
  { x = 51, y = 56, w = 1, h = 4 },   -- 4-pane lattice, outer-right
}

-- The Gen-1 Overworld sheet and Gen-2's Johto sheet were the same bytes
-- when this was checked, but key BOTH names: whichever one the engine's
-- asset paths actually use still gets the fix, and a future re-export that
-- makes them diverge doesn't silently drop Johto's half again.
GlassMask.MANUAL = {
  ["overworld"] = johtoOverworldPanes,
  ["0.png"] = johtoOverworldPanes,
  ["tileset0.png"] = johtoOverworldPanes,
  ["johto"] = johtoOverworldPanes,
  ["tilesetjohto"] = johtoOverworldPanes,
  ["johto.png"] = johtoOverworldPanes,
}

-- Candidate lookup keys for a tileset, tried in order: its engine id (raw,
-- and lowercased with any TILESET_ prefix stripped), then the basename of
-- its image path (with or without the extension). Whichever of these was
-- actually used to key GlassMask.MANUAL above is the one that matches.
local function manualKeysFor(tileset)
  local keys = {}
  local id = tileset and tileset.id
  if type(id) == "string" then
    keys[#keys + 1] = id:lower()
    keys[#keys + 1] = id:gsub("^TILESET_", ""):lower()
  end
  local path = tileset and tileset.image
  if type(path) == "string" then
    local base = path:match("([^/\\]+)$") or path
    keys[#keys + 1] = base:lower()
    keys[#keys + 1] = (base:gsub("%.%w+$", "")):lower()
  end
  return keys
end

local function manualRectsFor(tileset)
  for _, key in ipairs(manualKeysFor(tileset)) do
    local hit = GlassMask.MANUAL[key]
    if hit then return hit end
  end
  return nil
end

-- Find every pane in an image, through a pure reader so the geometry is
-- testable headless: `getPixel(x, y)` returns r, g, b in 0..1 for 0-based
-- coordinates. Returns { {x=, y=, w=, h=}, ... } rects of GLASS texels
-- (the border is the detector's evidence, not part of the answer).
--
-- A closing border row is REQUIRED, same as before -- that's what keeps
-- this from also matching a flat counter or sign board (checked against
-- the actual tileset art: loosening this to accept any run that simply
-- ends up matching a shop counter in forest.png that plainly isn't glass).
-- The one real pane that has no closing row in its art at all -- its
-- bottom edge blends straight into the wall below it -- is handled by the
-- verified MANUAL table instead of loosening this rule for everyone.
function GlassMask.scan(getPixel, w, h)
  local function black(x, y)
    if x < 0 or x >= w or y < 0 or y >= h then return false end
    return isBlack(getPixel(x, y))
  end
  local function borderRow(x, y, gw)
    for c = 1, gw do
      if not black(x + c, y) then return false end
    end
    return true
  end
  local function glassRow(x, y, gw)
    if not (black(x, y) and black(x + gw + 1, y)) then return false end
    for c = 1, gw do
      if black(x + c, y) then return false end
    end
    return true
  end

  local rects = {}
  for y = 0, h - 1 do
    for _, gw in ipairs(GlassMask.WIDTHS) do
      for x = 0, w - gw - 2 do
        if borderRow(x, y, gw) then
          local n = 0
          while y + 1 + n < h and glassRow(x, y + 1 + n, gw) do
            n = n + 1
          end
          if n >= GlassMask.ROWS_MIN and n <= GlassMask.ROWS_MAX
             and y + 1 + n < h and borderRow(x, y + 1 + n, gw) then
            rects[#rects + 1] = { x = x + 1, y = y + 1, w = gw, h = n }
          end
        end
      end
    end
  end
  return rects
end

-- ------- the runtime cache, one entry per tileset image

local cache = {}       -- image path -> { rects, texture (or false) }

local function entry(tileset)
  local path = tileset and tileset.image
  if not path then return nil end
  local hit = cache[path]
  if hit then return hit end
  local ok, data = pcall(Assets.imageData, path)
  if not (ok and data) then
    -- unreadable art is a verdict for the session, not a retry loop
    cache[path] = { rects = {}, texture = false }
    return cache[path]
  end
  local w, h = data:getDimensions()
  local rects = GlassMask.scan(function(x, y)
    return data:getPixel(x, y)
  end, w, h)
  local manual = manualRectsFor(tileset)
  if manual then
    for _, r in ipairs(manual) do
      rects[#rects + 1] = { x = r.x, y = r.y, w = r.w, h = r.h }
    end
  end
  local texture = false
  if #rects > 0 and love.image and love.image.newImageData
     and love.graphics and love.graphics.newImage then
    local built = pcall(function()
      local mask = love.image.newImageData(w, h)
      for _, r in ipairs(rects) do
        for yy = r.y, r.y + r.h - 1 do
          for xx = r.x, r.x + r.w - 1 do
            mask:setPixel(xx, yy, 1, 1, 1, 1)
          end
        end
      end
      texture = love.graphics.newImage(mask)
      texture:setFilter("nearest", "nearest")
    end)
    if not built then texture = false end
  end
  cache[path] = { rects = rects, texture = texture }
  return cache[path]
end

-- The panes found in a tileset's art, as glass rects in atlas pixels.
function GlassMask.rects(tileset)
  local e = entry(tileset)
  return e and e.rects or {}
end

-- The mask texture for a tileset, or nil when it has no panes (or the art
-- is unreadable, or there is no GPU) -- callers bind the blank instead.
function GlassMask.texture(tileset)
  local e = entry(tileset)
  return (e and e.texture) or nil
end

-- A 1x1 transparent stand-in, for the frames (and drivers) with no mask:
-- the scene shader always declares the sampler, and an unbound sampler is
-- a driver-dependent crash rather than a fallback.
local blank = nil

function GlassMask.blank()
  if blank == nil then
    local ok, img = pcall(function()
      local data = love.image.newImageData(1, 1)
      data:setPixel(0, 0, 0, 0, 0, 0)
      return love.graphics.newImage(data)
    end)
    blank = (ok and img) or false
  end
  return blank or nil
end

-- Drop the GPU objects (window resize, hot reload). The rects survive --
-- they are a fact about the art -- but textures are rebuilt on demand.
function GlassMask.invalidate()
  for _, e in pairs(cache) do
    if e.texture and e.texture.release then pcall(e.texture.release, e.texture) end
    e.texture = false
  end
  cache = {}
  blank = nil
end

return GlassMask