-- Gen4Rocks: small grey voxel rocks standing where Platinum's route rocks are.
--
-- WHAT PLATINUM DRAWS
--
-- Route clutter and fence runs share the terrain texture `imped` (found with
-- the Gen4Lawn colour probe). Both are flat cards, like the tree cards
-- Gen4Trees replaces:
--   * a roughly square card is a rock sprite
--   * a long banner -- wide (east/west) OR tall (north/south / standing) -- is a fence
-- Only the square cards become voxel rocks. Banner cards are Gen4Fence's: it
-- stands real 3D fences on them (and falls back to leaving them native).
--
-- WHAT THIS BUILDS INSTEAD
--
-- For every card of an `imped` shape: a low-poly boulder (a lumpy 80-facet
-- sphere, flattened underneath and planted in the ground) plus one or two small
-- satellite stones. Shape, squash and lumps come from a hash of the card's
-- position, so rocks differ but never change between frames. Each facet is lit
-- flat from the upper-front (so the rock reads as faceted stone, not a block)
-- and wears a grey texel with the odd darker crack / lighter face / mossy tint.
--
-- HIDING THE NATIVE CARD
--
-- Gen4Hide drops a native `imped` shape only when EVERY card in that shape
-- converted to a rock. A shape that is all fence banners, or mixed, keeps
-- drawing natively so fences never vanish. Lawn no longer paints the whole
-- `imped` material transparent (that was turning fences into holes).
--
-- THE ROCK'S SURFACE
--
-- If assets/ground/grass/rock.png exists, every facet is painted with a piece of it:
-- the picture is laid over the whole rock as ONE continuous surface (each facet is
-- projected flat from the rock's centre, so neighbours line up), turned a different
-- amount per rock, and filtered smoothly. The facet shading (lit from the upper
-- front) is kept on top. Without that file the built-in 8x8 grey stone is used, as
-- before, and the log says so once. Rocks.TEXTURE_FILE / Rocks.USE_FILE /
-- Rocks.TEX_WINDOW / Rocks.FILTER / Rocks.TEX_MAX change this.
-- The picture is shrunk to TEX_MAX (box-averaged) and uploaded with mipmaps: raw,
-- a big picture on a small rock is what reads as grain.
--
-- SEA ROCKS
--
-- The `searock` terrain texture (shore / reef rock; Gen4Lawn lists it) gets the same
-- boulders, a little bigger. A long card becomes a loose string of rocks (varied sizes,
-- gaps, pushed off the line); a flat polygon gets boulders scattered over it. The
-- native shape is hidden once rocks stand in (SEA_HIDE_FLAT covers flat ones too).
-- Knobs: SEA_BASE_W, SEA_W_VAR, SEA_MIN_W, SEA_MAX_W, SEA_SPACING, SEA_KEEP,
-- SEA_JITTER, SEA_SINK, SEA_FLAT, SEA_FLAT_CELL, SEA_FLAT_MAX, SEA_HIDE_FLAT.
--
-- KNOBS: Rocks.SIZE, MIN_W, MAX_W, FENCE_ASPECT, FENCE_MIN_W, Y_OFFSET, SINK,
-- WINDOW, USE_FILE, TEXTURE_FILE, TEX_WINDOW, enabled. Bridge.disabled.rocks turns it off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local Rocks = {
  enabled = true,
  TEXTURES = { imped = true },   -- terrain texture names that are rocks OR fence banners
  -- SEA ROCKS (`searock`, the shore/reef rock Gen4Lawn names): the same boulders, a bit
  -- bigger than a route rock. A long card is NOT one rock per card in a straight line:
  -- it gets a loose string of rocks of different sizes, some gaps, pushed off the line.
  -- A flat searock polygon gets boulders scattered over it.
  SEA_TEXTURES = { searock = true },
  SEA_BASE_W = 30,               -- typical sea rock width (an `imped` rock is ~22; a tile is 16)
  SEA_W_VAR = 0.25,              -- each rock is BASE x (1 +- this)
  SEA_MIN_W = 18,                -- width limits
  SEA_MAX_W = 42,
  SEA_SPACING = 26,              -- along a long card: about one rock this often
  SEA_KEEP = 0.68,               -- ...and this fraction of those spots get one (the rest are gaps) - reduced from 0.8 for ~15% less density
  SEA_JITTER = 9,                -- ...each pushed up to this far off the card's line, either side
  SEA_SINK = 2.0,                -- planted deeper: the shore is wet and uneven
  SEA_SATELLITES = 1,
  SEA_FLAT = true,               -- scatter boulders over a flat searock polygon
  SEA_FLAT_CELL = 30,            -- ...about one boulder per CELL x CELL units of it - increased from 26 for ~15% less density
  SEA_FLAT_MAX = 51,             -- ...and never more than this many per land - reduced from 60 for ~15% less density
  -- Hide the native searock shape even when it holds a flat polygon (the picture you
  -- see is usually that polygon). Turn off if hiding it ever leaves a hole in the shore.
  SEA_HIDE_FLAT = true,
  WINDOW = 2,                    -- lands each way around the camera
  SIZE = 1.35,                    -- rock width as a fraction of the card's width
  MIN_W = 14,                    -- never narrower than this (world units; a tile is 16)
  MAX_W = 28,                    -- ...never wider than this
  FENCE_ASPECT = 1.75,           -- longest/shortest edge at or above this is a banner
  FENCE_MIN_W = 40,              -- ...or any card this long in XZ or Y (a rock is one tile)
  USE_FILE = true,               -- wear assets/ground/grass/<TEXTURE_FILE> when it exists
  TEXTURE_FILE = "rock.png",
  TEX_WINDOW = 1.0,              -- fraction of the picture one rock shows (1 = all of it; less = a different part per rock)
  TEX_MAX = 64,                  -- shrink rock.png to at most this many pixels a side (averaged), then mipmap it
  FILTER = "linear",             -- "linear" is smooth; "nearest" keeps hard pixels (reads as grain on a small picture)
  HEIGHT = 0.9,                 -- rock height as a fraction of its width
  LUMP = 0.30,                   -- how lumpy the surface is (0 = smooth egg, 0.4 = very rough)
  SATELLITES = 2,                -- up to this many small stones beside each rock
  -- Trees need Y_OFFSET = -10 because a tall card still shows after the sink.
  -- A rock is only ~8 units tall: the same -10 buries the whole mesh under the
  -- terrain, Lawn then hides the native card, and nothing is left on screen.
  Y_OFFSET = 0,
  SINK = 1.0,                    -- planted this far into the ground
  BUILDS_PER_FRAME = 4,
  MAX_RESIDENT = 20,
  LOG = true,
  version = 0,                   -- bumps whenever the set of built lands changes
}

local FX16, UV_UNITS = 4096, 16
local LIGHT = { 0.35, 0.80, 0.50 }      -- toward the light: up and a little to the front

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Rocks: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

-- ---------------------------------------------------------------- texture --

-- An 8x8 picture generated here (no file to ship). Rows 0-5 are the stone
-- (mid greys, a hint of warm/cool), row 6 darker cracks, row 7 lighter faces and
-- a mossy tint. Each facet samples ONE texel, picked by hash.
local GRID = 8
local texture                 -- Image | false
local fileMode = false        -- true: `texture` is rock.png and meshes carry picture UVs

-- The picture's bytes: love.filesystem, then the engine's Assets, then plain io
-- (the same fallbacks Gen4Flowers uses to read grass.png).
local function readBytes(rel, abs)
  if love and love.filesystem and love.filesystem.read then
    for _, p in ipairs({ rel, abs }) do
      local ok, data = pcall(love.filesystem.read, p)
      if ok and type(data) == "string" and #data > 0 then return data end
    end
  end
  local okA, Assets = pcall(require, "src.render.Assets")
  if okA and Assets and Assets.read then
    for _, p in ipairs({ abs, rel }) do
      local ok, data = pcall(Assets.read, p)
      if ok and type(data) == "string" and #data > 0 then return data end
    end
  end
  if io and io.open then
    local f = io.open(abs, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      if type(data) == "string" and #data > 0 then return data end
    end
  end
  return nil
end

-- Shrink an ImageData to at most `limit` pixels a side by AVERAGING the pixels each
-- new one covers (a box filter, up to 6x6 samples per pixel). A big picture drawn on
-- a rock a few dozen screen pixels wide, sampled raw, is what reads as grain: every
-- screen pixel lands on a different speck of it.
local function shrink(data, limit)
  local w, h = data:getWidth(), data:getHeight()
  if math.max(w, h) <= limit then return data, w, h end
  local scale = limit / math.max(w, h)
  local nw, nh = math.max(1, math.floor(w * scale + 0.5)), math.max(1, math.floor(h * scale + 0.5))
  local out = love.image.newImageData(nw, nh)
  local fx, fy = w / nw, h / nh
  local nx, ny = math.max(1, math.min(6, math.ceil(fx))), math.max(1, math.min(6, math.ceil(fy)))
  for y = 0, nh - 1 do
    for x = 0, nw - 1 do
      local r, g, b, a, n = 0, 0, 0, 0, 0
      for sy = 0, ny - 1 do
        for sx = 0, nx - 1 do
          local px = math.min(w - 1, math.floor((x + (sx + 0.5) / nx) * fx))
          local py = math.min(h - 1, math.floor((y + (sy + 0.5) / ny) * fy))
          local pr, pg, pb, pa = data:getPixel(px, py)
          r, g, b, a, n = r + pr, g + pg, b + pb, a + (pa or 1), n + 1
        end
      end
      out:setPixel(x, y, r / n, g / n, b / n, a / n)
    end
  end
  return out, nw, nh
end

-- assets/ground/grass/rock.png. Preferred route: decode it here, shrink it to
-- TEX_MAX, and upload it with MIPMAPS and smooth filtering, so it stays calm at any
-- distance. If the bytes cannot be read, fall back to the engine's Assets image
-- (smooth filtering only). nil when the file is not there at all.
local function loadFileTexture()
  if not Rocks.USE_FILE then return nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  local rel = "assets/ground/grass/" .. tostring(Rocks.TEXTURE_FILE)
  local abs = tostring(V.path or "") .. "/" .. rel
  local exists = false
  if okA and Assets and Assets.exists then
    local okE, e = pcall(Assets.exists, abs)
    exists = okE and e and true or false
  end
  local filter = Rocks.FILTER or "linear"

  local bytes = readBytes(rel, abs)
  if bytes and love and love.image and love.filesystem and love.filesystem.newFileData then
    local ok, img, info = pcall(function()
      local raw = love.image.newImageData(love.filesystem.newFileData(bytes, tostring(Rocks.TEXTURE_FILE)))
      local ow, oh = raw:getWidth(), raw:getHeight()
      local data, w, h = shrink(raw, Rocks.TEX_MAX or 64)
      local image = love.graphics.newImage(data, { mipmaps = true })
      image:setFilter(filter, filter)
      if image.setMipmapFilter then pcall(image.setMipmapFilter, image, "linear", 0) end
      return image, { ow = ow, oh = oh, w = w, h = h }
    end)
    if ok and img then
      once("size", "rock.png is %dx%d, used at %dx%d with mipmaps", info.ow, info.oh, info.w, info.h)
      return img
    end
    once("decode", "could not decode rock.png here (%s) -- using the engine's copy", tostring(img))
  end

  if not exists then return nil end
  local ok, img = pcall(Assets.image, abs)
  if not (ok and img) then return nil end
  pcall(img.setFilter, img, filter, filter)
  return img
end

-- The texture the rocks wear. Decided BEFORE any rock mesh is built (prepare calls
-- it first): the two surfaces need different UVs.
local function rockTexture()
  if texture ~= nil then return texture or nil end
  local file = loadFileTexture()
  if file then
    texture, fileMode = file, true
    once("file", "rocks wear assets/ground/grass/%s", tostring(Rocks.TEXTURE_FILE))
    return texture
  end
  fileMode = false
  if Rocks.USE_FILE then
    once("nofile", "no assets/ground/grass/%s -- rocks keep the built-in grey stone",
         tostring(Rocks.TEXTURE_FILE))
  end
  local ok, img = pcall(function()
    local data = love.image.newImageData(GRID, GRID)
    for y = 0, GRID - 1 do
      for x = 0, GRID - 1 do
        local n = ((x * 7 + y * 13 + x * y * 3) % 6) / 5           -- 0..1
        local g = 0.46 + 0.14 * n
        local r, gg, b = g * 1.02, g, g * 0.97                       -- slightly warm stone
        if x % 2 == 1 then r, gg, b = g * 0.97, g, g * 1.04 end     -- ...and slightly cool
        if y == 6 then r, gg, b = g * 0.62, g * 0.62, g * 0.64       -- cracks / shadowed
        elseif y == 7 then
          if x < 5 then r, gg, b = g * 1.28, g * 1.28, g * 1.25      -- light faces
          else r, gg, b = g * 0.85, g * 1.05, g * 0.72 end           -- moss
        end
        data:setPixel(x, y, math.min(r, 1), math.min(gg, 1), math.min(b, 1), 1)
      end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
  end)
  texture = ok and img or false
  if not texture then once("tex", "could not build the rock texture: %s", tostring(img)) end
  return texture or nil
end

-- ---------------------------------------------------------------- decoding --

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

local function readShape(ground, s, posScale)
  local vdata, idata = s.vertices, s.indices
  if type(vdata) ~= "string" or type(idata) ~= "string" then
    vdata = ground:slice(s.vertexAt, s.vertexBytes)
    idata = ground:slice(s.indexAt, s.indexBytes)
  end
  local count, tris = s.vertexCount or 0, s.triangleCount or 0
  if not (vdata and idata) or count < 3 or tris < 1 then return nil end
  local stride = math.floor(#vdata / count)
  if stride < 10 then return nil end
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = { s16(vdata, at) / FX16 * posScale,
               s16(vdata, at + 2) / FX16 * posScale,
               s16(vdata, at + 4) / FX16 * posScale }
  end
  local list = {}
  for t = 0, tris - 1 do
    local a1, a2, b1, b2, c1, c2 = idata:byte(t * 6 + 1, t * 6 + 6)
    if not c2 then break end
    list[#list + 1] = { a1 + a2 * 256 + 1, b1 + b2 * 256 + 1, c1 + c2 * 256 + 1 }
  end
  return pos, list
end

local function posKey(p)
  return string.format("%.2f,%.2f,%.2f", p[1], p[2], p[3])
end

-- Pair consecutive triangles into cards: each pair that shares an edge has four
-- distinct corners. Returns { {cx, baseY, cz, planeW, planeH}, ... }.
local function cardsOf(positions, tris)
  local cards = {}
  local i = 1
  while i < #tris do
    local seen, corners = {}, {}
    for _, t in ipairs({ tris[i], tris[i + 1] }) do
      for k = 1, 3 do
        local p = positions[t[k]]
        if p then
          local key = posKey(p)
          if not seen[key] then seen[key] = true; corners[#corners + 1] = p end
        end
      end
    end
    if #corners == 4 then
      local sx, sz, ymin, ymax = 0, 0, math.huge, -math.huge
      local xmin, xmax, zmin, zmax = math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(corners) do
        sx, sz = sx + p[1], sz + p[3]
        ymin, ymax = math.min(ymin, p[2]), math.max(ymax, p[2])
        xmin, xmax = math.min(xmin, p[1]), math.max(xmax, p[1])
        zmin, zmax = math.min(zmin, p[3]), math.max(zmax, p[3])
      end
      local planeW = math.max(xmax - xmin, zmax - zmin)
      local planeH = math.max(0.01, ymax - ymin)
      cards[#cards + 1] = { sx / 4, ymin, sz / 4, planeW, planeH, corners = corners,
                            x0 = xmin, x1 = xmax, z0 = zmin, z1 = zmax }
      i = i + 2
    else
      i = i + 1        -- not a pair: slide by one and try again
    end
  end
  return cards
end

-- Banners share `imped` with rocks. Horizontal runs are wide in XZ; vertical
-- runs are tall in Y. Either way the card is elongated -- a rock is square.
local function isFenceCard(c)
  local w, h = c[4] or 0, math.max(c[5] or 0, 0.01)
  local long, short = w, h
  if h > w then long, short = h, w end
  if long >= (Rocks.FENCE_MIN_W or 40) then return true end
  return (long / short) >= (Rocks.FENCE_ASPECT or 1.75)
end
-- Gen4Fence classifies cards with this same test, so a card is never both a
-- boulder and a fence.
Rocks.isFenceCard = isFenceCard

-- ------------------------------------------------------------------ mesh --

local function hash(x, z)
  local h = math.floor(x * 73.1 + z * 151.7) % 2147483647
  h = (h * 1103515245 + 12345) % 2147483648
  return h / 2147483648
end

-- Unit icosphere, subdivided once: 42 vertices, 80 triangles. Built once.
local template
local function icosphere()
  if template then return template end
  local t = (1 + math.sqrt(5)) / 2
  local v = {
    { -1, t, 0 }, { 1, t, 0 }, { -1, -t, 0 }, { 1, -t, 0 },
    { 0, -1, t }, { 0, 1, t }, { 0, -1, -t }, { 0, 1, -t },
    { t, 0, -1 }, { t, 0, 1 }, { -t, 0, -1 }, { -t, 0, 1 },
  }
  local function norm(p)
    local l = math.sqrt(p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
    return { p[1] / l, p[2] / l, p[3] / l }
  end
  for i = 1, #v do v[i] = norm(v[i]) end
  local f = {
    { 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 },
    { 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
    { 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 },
    { 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 },
  }
  local cache, out = {}, {}
  local function mid(a, b)
    local key = a < b and (a .. ":" .. b) or (b .. ":" .. a)
    local hit = cache[key]
    if hit then return hit end
    local pa, pb = v[a], v[b]
    v[#v + 1] = norm({ (pa[1] + pb[1]) / 2, (pa[2] + pb[2]) / 2, (pa[3] + pb[3]) / 2 })
    cache[key] = #v
    return #v
  end
  for _, tri in ipairs(f) do
    local a, b, c = tri[1], tri[2], tri[3]
    local ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
    out[#out + 1] = { a, ab, ca }
    out[#out + 1] = { b, bc, ab }
    out[#out + 1] = { c, ca, bc }
    out[#out + 1] = { ab, bc, ca }
  end
  template = { verts = v, faces = out }
  return template
end

-- One boulder centred at (cx, cz), standing on baseY. `w` is its width.
local function boulder(b, cx, baseY, cz, w, seed, sink)
  local tpl = icosphere()
  local r1, r2, r3, r4 = hash(seed, 1.7), hash(2.3, seed), hash(seed + 4.1, seed - 9.2), hash(seed * 0.37, 5.5)
  local ax, az = 0.5 * w * (0.85 + 0.35 * r1), 0.5 * w * (0.85 + 0.35 * r2)   -- half widths
  local hy = w * Rocks.HEIGHT * (0.8 + 0.4 * r3) * 0.5                          -- half height
  local yaw = r4 * 6.2832
  local cs, sn = math.cos(yaw), math.sin(yaw)
  local turn = hash(seed * 1.7, 3.3) * 6.2832          -- how far this rock's picture is turned
  local cosT, sinT = math.cos(turn), math.sin(turn)
  local p1, p2, p3 = r1 * 6.28, r2 * 6.28, r3 * 6.28
  local flatY = -0.38                                  -- unit-sphere y below which it is cut flat
  local pts = {}
  for i, u in ipairs(tpl.verts) do
    -- smooth lumps (three low-frequency sines) plus a little per-vertex jitter
    local lump = math.sin(u[1] * 2.3 + p1) * math.sin(u[2] * 2.9 + p2)
               + 0.6 * math.sin(u[3] * 3.1 + p3 + u[1])
    local jit = hash(seed + i * 0.731, i * 1.37 + seed) - 0.5
    local r = 1 + Rocks.LUMP * 0.5 * lump + Rocks.LUMP * 0.45 * jit
    local x, y, z = u[1] * r, u[2] * r, u[3] * r
    if y < flatY then y = flatY end                    -- flat underside that sits in the ground
    local lx, lz = x * ax, z * az
    pts[i] = { cx + lx * cs - lz * sn, y * hy, cz + lx * sn + lz * cs }
  end
  local lift = baseY - (sink or Rocks.SINK) - flatY * hy       -- put the flat underside at the ground (minus the sink)
  for fi, face in ipairs(tpl.faces) do
    local a, c2, d = pts[face[1]], pts[face[2]], pts[face[3]]
    -- face normal, oriented away from the rock's centre
    local ux, uy, uz = c2[1] - a[1], c2[2] - a[2], c2[3] - a[3]
    local vx, vy, vz = d[1] - a[1], d[2] - a[2], d[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local len = math.sqrt(nx * nx + ny * ny + nz * nz)
    if len > 1e-6 then
      nx, ny, nz = nx / len, ny / len, nz / len
      local mx, my, mz = (a[1] + c2[1] + d[1]) / 3 - cx, (a[2] + c2[2] + d[2]) / 3, (a[3] + c2[3] + d[3]) / 3 - cz
      if nx * mx + ny * my + nz * mz < 0 then nx, ny, nz = -nx, -ny, -nz end
      local lit = math.max(0, nx * LIGHT[1] + ny * LIGHT[2] + nz * LIGHT[3])
      local shade = math.min(1.0, 0.50 + 0.55 * lit)
      if ny > 0.55 then shade = -shade end             -- faces the sky (same flag the voxel trees use)
      -- texel: mostly stone, sometimes a crack / light face / moss
      local base = #b.verts
      if fileMode then
        -- rock.png laid over the WHOLE rock as one continuous picture: each facet is
        -- projected flat along its dominant axis, from the rock's own centre, so
        -- neighbouring facets line up instead of each showing a different crop (that
        -- read as noise). Per rock: a turn of the picture and, when TEX_WINDOW < 1, a
        -- different part of it. UVs are clamped to 0..1, so no wrap mode is needed.
        local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
        local k = (Rocks.TEX_WINDOW or 1) * 0.55 / w
        local slack = (1 - (Rocks.TEX_WINDOW or 1)) * 0.5
        local ccu = 0.5 + (hash(seed, 9.1) - 0.5) * 2 * slack
        local ccv = 0.5 + (hash(9.7, seed) - 0.5) * 2 * slack
        local function uv(p)
          local p1, p2
          if ay >= ax and ay >= az then p1, p2 = p[1] - cx, p[3] - cz      -- faces up/down
          elseif ax >= az then p1, p2 = p[3] - cz, p[2] * 1.0              -- faces east/west
          else p1, p2 = p[1] - cx, p[2] * 1.0 end                          -- faces north/south
          local ru, rv = p1 * cosT - p2 * sinT, p1 * sinT + p2 * cosT
          return math.max(0, math.min(1, ccu + ru * k)), math.max(0, math.min(1, ccv + rv * k))
        end
        local ua, va = uv(a)
        local ub, vb = uv(c2)
        local uc, vc = uv(d)
        b.verts[base + 1] = { a[1], a[2] + lift, a[3], ua, va, shade, 0 }
        b.verts[base + 2] = { c2[1], c2[2] + lift, c2[3], ub, vb, shade, 0 }
        b.verts[base + 3] = { d[1], d[2] + lift, d[3], uc, vc, shade, 0 }
      else
        local roll = hash(seed + fi * 3.3, fi + seed * 0.1)
        local cell
        if roll < 0.82 then cell = math.floor(hash(fi, seed) * 48)
        elseif roll < 0.90 then cell = 48 + math.floor(hash(seed, fi) * 8)
        else cell = 56 + math.floor(hash(fi * 2.1, seed) * 8) end
        local u = ((cell % GRID) + 0.5) / GRID
        local v = (math.floor(cell / GRID) % GRID + 0.5) / GRID
        b.verts[base + 1] = { a[1], a[2] + lift, a[3], u, v, shade, 0 }
        b.verts[base + 2] = { c2[1], c2[2] + lift, c2[3], u, v, shade, 0 }
        b.verts[base + 3] = { d[1], d[2] + lift, d[3], u, v, shade, 0 }
      end
      b.map[#b.map + 1], b.map[#b.map + 2], b.map[#b.map + 3] = base + 1, base + 2, base + 3
    end
  end
end

-- `width` (optional) sets a sea rock's width directly; imped rocks size from the card.
local function buildRock(b, cx, baseY, cz, cardW, sea, width)
  local w, sink, satellites
  if sea then
    w = math.max(Rocks.SEA_MIN_W, math.min(Rocks.SEA_MAX_W, width or Rocks.SEA_BASE_W))
    sink, satellites = Rocks.SEA_SINK, Rocks.SEA_SATELLITES or 0
  else
    w = math.max(Rocks.MIN_W, math.min(Rocks.MAX_W, cardW * Rocks.SIZE))
    sink, satellites = Rocks.SINK, Rocks.SATELLITES or 0
  end
  boulder(b, cx, baseY, cz, w, cx * 0.91 + cz * 1.73, sink)
  local extra = math.min(satellites, math.floor(hash(cx + 5.5, cz - 1.1) * 3))
  for k = 1, extra do
    local ang = hash(cx * k, cz + k) * 6.2832
    local dist = w * (0.55 + 0.25 * hash(cz, cx * k + 2))
    local sw = w * (0.28 + 0.2 * hash(cx + k, cz * 2.3))
    boulder(b, cx + math.cos(ang) * dist, baseY, cz + math.sin(ang) * dist, sw, cx * 0.57 + cz * 2.11 + k * 7.7, sink)
  end
  return 80
end

-- A random-looking width for a sea rock standing at (x, z).
local function seaWidth(x, z)
  local v = Rocks.SEA_W_VAR or 0.25
  return (Rocks.SEA_BASE_W or 30) * (1 - v + 2 * v * hash(x * 1.3 + 7.1, z * 0.7 - 3.3))
end

-- One searock card -> a loose string of rocks along it (or one, for a compact card).
-- Positions along the card are jittered, some are skipped, and each rock is pushed
-- off the card's line by a different amount, so a long card never reads as a row.
local function seaBouldersOnCard(b, c, ground)
  local ex, ez = c.x1 - c.x0, c.z1 - c.z0
  local alongX = ex >= ez
  local len = alongX and ex or ez
  local spacing = math.max(8, Rocks.SEA_SPACING or 26)
  local n = math.max(1, math.floor(len / spacing + 0.5))
  local mx, mz = (c.x0 + c.x1) * 0.5, (c.z0 + c.z1) * 0.5
  local made = 0
  local function waterY(x, z)
    if ground and ground.groundY then
      return ground:groundY(x, z) or c[2]
    end
    return c[2]
  end
  for i = 1, n do
    if n == 1 then
      local wy = waterY(c[1], c[3])
      buildRock(b, c[1], wy, c[3], c[4], true, seaWidth(c[1], c[3]))
      made = made + 1
    elseif hash(c[1] * i + 1.3, c[3] + i * 2.9) < (Rocks.SEA_KEEP or 0.8) then
      local t = (i - 0.5) / n + (hash(c[1] + i * 3.1, c[3] * 0.4) - 0.5) * 0.7 / n
      local lat = (hash(c[3] + i * 1.7, c[1] * 0.3 + i) - 0.5) * 2 * (Rocks.SEA_JITTER or 9)
      local px, pz
      if alongX then px, pz = c.x0 + t * ex, mz + lat else px, pz = mx + lat, c.z0 + t * ez end
      local wy = waterY(px, pz)
      buildRock(b, px, wy, pz, c[4], true, seaWidth(px, pz))
      made = made + 1
    end
  end
  if made == 0 then      -- every spot happened to be a gap: keep the card's middle
    local wy = waterY(c[1], c[3])
    buildRock(b, c[1], wy, c[3], c[4], true, seaWidth(c[1], c[3]))
    made = 1
  end
  return made
end

-- ------------------------------------------------------------------ lands --

local landEntries = setmetatable({}, { __mode = "k" })   -- land -> { mesh, rocks, shapes }
local resident = 0
local list = {}
local window = {}
local tick = 0
Rocks.active = {}
Rocks.coverVersion = 0
local lastCoverSig = ""

-- Which kind of rock shape is this? -> nil | "imped" | "sea"
local function shapeKind(s)
  local tex = tostring(s.texture or s.srcTexture or ""):lower()
  local mat = tostring(s.material or s.srcMaterial or ""):lower()
  if Rocks.SEA_TEXTURES[tex] or Rocks.SEA_TEXTURES[mat] then return "sea" end
  for name in pairs(Rocks.SEA_TEXTURES) do
    if tex:find(name, 1, true) or mat:find(name, 1, true) then return "sea" end
  end
  if Rocks.TEXTURES[tex] or Rocks.TEXTURES[mat]
      or tex:find("imped", 1, true) or mat:find("imped", 1, true) then
    return "imped"
  end
  return nil
end

-- Split a shape's triangles: up-facing (a floor) and the rest (standing cards).
local function splitFlat(positions, tris)
  local flat, upright, area = {}, {}, 0
  for _, t in ipairs(tris) do
    local a, b, c = positions[t[1]], positions[t[2]], positions[t[3]]
    if a and b and c then
      local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
      local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
      local len = math.sqrt(nx * nx + ny * ny + nz * nz)
      if len > 1e-6 then
        if math.abs(ny) / len >= 0.6 then
          flat[#flat + 1] = { a, b, c, len * 0.5 }
          area = area + len * 0.5
        else
          upright[#upright + 1] = t
        end
      end
    end
  end
  return flat, upright, area
end

local function buildLand(ground, land)
  local out = { rocks = 0, fences = 0, seaRocks = 0, shapes = {} }
  local record = ground.terrain.chunks[land]
  if not (record and record.shapes) then return out end
  local b = { verts = {}, map = {} }
  local shapesSeen, leftover, seaShapes = 0, 0, 0
  local seaCards, seaFlat, seaHidden = 0, 0, 0
  for _, s in ipairs(record.shapes) do
    local kind = shapeKind(s)
    if kind == "imped" then
      shapesSeen = shapesSeen + 1
      local positions, tris = readShape(ground, s, record.posScale or 1)
      if positions then
        local cards = cardsOf(positions, tris)
        if #cards == 0 then leftover = leftover + 1 end
        local rockN, fenceN = 0, 0
        for _, c in ipairs(cards) do
          if isFenceCard(c) then
            fenceN = fenceN + 1
            out.fences = out.fences + 1
          else
            buildRock(b, c[1], c[2], c[3], c[4])
            rockN = rockN + 1
            out.rocks = out.rocks + 1
          end
        end
        -- Hide this native shape only when it was rocks all the way through.
        -- A banner, or a mix, stays on screen so fences are never replaced.
        if rockN > 0 and fenceN == 0 then
          out.shapes[#out.shapes + 1] = s
        end
      end
    elseif kind == "sea" then
      seaShapes = seaShapes + 1
      local positions, tris = readShape(ground, s, record.posScale or 1)
      if positions then
        local flat, upright, area = splitFlat(positions, tris)
        -- every upright card becomes a string of sea rocks
        local cards = (#upright > 0) and cardsOf(positions, upright) or {}
        local made = 0
        for _, c in ipairs(cards) do
          if #b.verts < 60000 then
            local n = seaBouldersOnCard(b, c, ground)
            made, out.seaRocks = made + n, out.seaRocks + n
          end
        end
        -- a flat polygon: scatter boulders over it, thinned to the per-land cap
        if Rocks.SEA_FLAT and #flat > 0 then
          local cell = math.max(8, Rocks.SEA_FLAT_CELL or 26)
          local expectedAll = area / (cell * cell)
          local scale = expectedAll > Rocks.SEA_FLAT_MAX and (Rocks.SEA_FLAT_MAX / expectedAll) or 1
          local function waterY(x, z)
            if ground and ground.groundY then
              return ground:groundY(x, z) or 0
            end
            return 0
          end
          for _, tri in ipairs(flat) do
            local a, bb, c = tri[1], tri[2], tri[3]
            local expected = tri[4] / (cell * cell) * scale
            local mx, mz = (a[1] + bb[1] + c[1]) / 3, (a[3] + bb[3] + c[3]) / 3
            local n = math.floor(expected)
            if hash(mx, mz + 91) < expected - n then n = n + 1 end
            for i = 1, n do
              if #b.verts >= 60000 then break end
              local r1, r2 = hash(mx * i, mz + i * 3.7), hash(mx + i * 5.1, mz * i)
              if r1 + r2 > 1 then r1, r2 = 1 - r1, 1 - r2 end
              local x = a[1] + r1 * (bb[1] - a[1]) + r2 * (c[1] - a[1])
              local z = a[3] + r1 * (bb[3] - a[3]) + r2 * (c[3] - a[3])
              local y = waterY(x, z)
              buildRock(b, x, y, z, 0, true, seaWidth(x, z))
              made, out.seaRocks = made + 1, out.seaRocks + 1
            end
          end
        end
        seaCards, seaFlat = seaCards + #cards, seaFlat + #flat
        -- Hide the native shape once rocks stand in. A flat polygon is hidden too
        -- unless SEA_HIDE_FLAT is off (then it stays, and Gen4Lawn repaints it).
        if made > 0 and (#flat == 0 or Rocks.SEA_HIDE_FLAT) then
          out.shapes[#out.shapes + 1] = s
          seaHidden = seaHidden + 1
        end
      end
    end
  end
  if #b.verts > 0 then out.mesh = Voxel3D.newMesh(b.verts, b.map) end
  if Rocks.LOG and shapesSeen > 0 then
    once("land" .. tostring(land),
         "land %s: %d imped shape(s) -> %d rocks, %d fence banner(s) left native (%d shape(s) had no usable cards)",
         tostring(land), shapesSeen, out.rocks, out.fences, leftover)
  end
  if Rocks.LOG and seaShapes > 0 then
    once("sea" .. tostring(land),
         "land %s: %d searock shape(s) (%d upright card(s), %d flat triangle(s)) -> %d sea rocks; %d native shape(s) hidden",
         tostring(land), seaShapes, seaCards, seaFlat, out.seaRocks, seaHidden)
  end
  return out
end

function Rocks.isBuilt(land)
  local e = land ~= nil and landEntries[land]
  return (e and e.mesh) and true or false
end

local function prepare(ground)
  rockTexture()          -- picks file vs built-in surface before any mesh is built
  local view = ground and ground.view3d
  if not (Rocks.enabled and ground and view and ground.grid and ground.terrain
          and ground.slice and ground.chunkPx and ground.half) then
    list = {}
    return
  end
  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)
  local qx, qy = math.floor(view.x * 4 / px), math.floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx and window.qy == qy then
    list = window.list
    return
  end
  tick = tick + 1
  local want = {}
  local W = Rocks.WINDOW
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        if land then
          local dx, dz = cx - camCx, cy - camCy
          want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
        end
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)
  local builds, pending, out = 0, 0, {}
  local changed = false
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = landEntries[land]
    if not entry then
      if builds < Rocks.BUILDS_PER_FRAME and Budget.allow(false) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "rocks")
        if not ok then
          once("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { rocks = 0 }
        end
        landEntries[land] = built
        entry = built
        resident = resident + 1
        changed = true
      else
        pending = pending + 1
      end
    end
    if entry then
      entry.used = tick
      if entry.mesh then out[#out + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half } end
    end
  end
  if changed then Rocks.version = Rocks.version + 1 end
  -- evict the oldest lands past the cap
  if resident > Rocks.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(landEntries) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land, e } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while resident > Rocks.MAX_RESIDENT and old[i] do
      local e = old[i][3]
      if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
      landEntries[old[i][2]] = nil
      resident = resident - 1
      Rocks.version = Rocks.version + 1
      i = i + 1
    end
  end
  list = out
  window.ground, window.qx, window.qy, window.list, window.done = ground, qx, qy, out, (pending == 0)

  local active, sig = {}, {}
  for _, w in ipairs(want) do
    local entry = landEntries[w[4]]
    if entry then
      for _, s in ipairs(entry.shapes or {}) do
        active[s] = true
        sig[#sig + 1] = tostring(s)
      end
    end
  end
  Rocks.active = active
  local coverSig = table.concat(sig, ",")
  if coverSig ~= lastCoverSig then
    lastCoverSig = coverSig
    Rocks.coverVersion = Rocks.coverVersion + 1
  end
end

function Rocks.prepare(ground)
  prepare(ground)
end

function Rocks.isCovered(record)
  return record ~= nil and Rocks.active[record] == true
end

function Rocks.draw(scene)
  if not Rocks.enabled then return end
  local tex = rockTexture()
  if not tex then return end
  prepare(scene.ground)
  if #list == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  local visible = scene.sphereVisible
  local radius = ((scene.ground and scene.ground.chunkPx) or 512) * 0.72 + 80
  for _, item in ipairs(list) do
    if (not visible) or visible(item.x, 0, item.z, radius) then
      Voxel3D.draw(item.entry.mesh, tex, Mat4.translate(item.x, Rocks.Y_OFFSET or 0, item.z), 0, nil, 0, false)
    end
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

function Rocks.invalidate()
  for _, e in pairs(landEntries) do
    if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
  end
  landEntries = setmetatable({}, { __mode = "k" })
  resident, list, window = 0, {}, {}
  texture = nil
  Rocks.version = Rocks.version + 1
end

return Rocks