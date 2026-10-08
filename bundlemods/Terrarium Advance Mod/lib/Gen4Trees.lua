-- Gen4Trees: round, low-poly trees standing in Gen 4's world.
--
-- WHAT PLATINUM DRAWS
--
-- A Sinnoh tree is a FLAT CARD: a 4-vertex quad leaning back toward the
-- cartridge's camera (normal (0, 0.819, 0.575)), many per terrain shape
-- (`tree01`, `tree2_01`, `tree04_2`, `tree3_02`, `bf_tree03`) plus the
-- `conttree*` forest-border strips (one wide card = several trees tiled).
--
-- WHAT THIS BUILDS INSTEAD: A LOW-POLY ROUND TREE (the Gen4Rocks recipe)
--
-- The old build cut the card into square blocks and stacked them as discs, which
-- is why trees looked like staircases. Now each tree is built the way Gen4Rocks
-- builds a boulder -- a smooth faceted solid with flat-lit facets:
--   * the card's art is still sampled on a grid, but only to read the tree's
--     SILHOUETTE: for every row, where the opaque pixels start and stop gives a
--     centre and a half-width (so the canopy bulges and the trunk stays slim);
--   * those rows become RINGS of SIDES points (a lathe / surface of revolution),
--     joined into triangles, closed at the top with a pole. Smoothing the
--     profile and a little hash-driven lumpiness (GT.LUMP) turn the stair-steps
--     into a round, slightly irregular crown that differs tree to tree but never
--     changes between frames;
--   * every triangle wears ONE texel of the card's own art. With GT.SHELL (the
--     default) the texel depends only on WHERE the facet sits on the tree, never
--     on which way the camera looks: its height picks the sprite row, a facet
--     facing UP wears the sprite's top rows (the little "hat" of the canopy seen
--     from above, so it shows from every side), the body takes the middle of its
--     row with a stable scatter of leaf clumps, and the underside takes the edge
--     (outline) texel. Lighting depends only on how far up a facet faces. The
--     tree is round in plan, so it reads the same from every orbit angle;
--   * with GT.SHELL = false each facet instead takes the texel the sprite shows
--     at its x / y when seen from the front, lit flat from the upper front.
--
-- BORDER TREES (`conttree*`)
--
-- A strip is split on each texture repeat and every repeat becomes its own
-- tree, so the border matches the trees inside the map. A sprite window that
-- is (nearly) all opaque has no outline to follow, so it is rounded to an
-- ellipse instead of being built as a slab (GT.DENSE_FRACTION).
--
-- WHEN A NATIVE CARD IS HIDDEN (Gen4Hide)
--
-- Per cache shape, by record, and only while this module has trees for it.
-- When a built shape lost its record pointer, Gen4Hide falls back to
-- isCoveredName: texture/material names only, and only names that converted
-- in every land of the window, so a name is never hidden where it was not built.
--
-- COST: baked ONCE PER LAND CHUNK, one mesh per texture. The first fill of a
-- window uses a bigger frame budget (WARM_BUDGET) so the whole window is
-- trees within a moment, not a trickle of pop-in.
--
-- DRAW DISTANCE (lib/Gen4Distance.lua, row "G4 DRAW DIST"): only lands within
-- the chosen reach of the camera get trees, built or drawn. Farther lands
-- keep Platinum's flat cards (Gen4Hide hides cards only on covered lands), and
-- baked lands the camera has left are released (GT.MAX_RESIDENT).
--
-- KNOBS: GT.enabled, GT.WINDOW, GT.TEX_STEP, GT.SIDES, GT.MAX_RINGS, GT.LUMP,
-- GT.SCALE, GT.SHELL, GT.DEPTH, GT.SMOOTH, GT.FLIP_SPRITE, GT.FLIP_WINDING, GT.MAX_QUADS, GT.WARM_BUDGET,
-- GT.HYSTERESIS, GT.MAX_RESIDENT.
-- Bridge.disabled.trees turns the effect off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Mat4 = V.require("Mat4")

local GT = {
  enabled = true,
  WINDOW = 2,             -- chunks each way: the MOST lands ever considered (same window as Gen4Ground / water)
  HYSTERESIS = 1.15,      -- a land already built stays covered out to this multiple of the draw-distance reach, so the edge does not flicker
  MAX_RESIDENT = 14,      -- built lands kept in memory when the draw distance is limited (the rest are released, oldest first)
  MAX_RESIDENT_MAX = 30,  -- ...and at MAX, which has no distance limit
  TEX_STEP = 1,           -- texels per sampling cell of the art (1 = every texel is read, so tiny details like snow specks survive; 2 = coarser, 4x less sampling)
  MAX_BLOCKS = 40,        -- most cells across one card, whatever the step says

  -- SHAPE OF A TREE (the "less blocky" knobs)
  SCALE = 0.95,           -- overall tree size (1.0 = the card's size; planted at the trunk's foot, so it shrinks toward the ground)
  SIDES = 16,             -- facets around a tree (10 = chunky gem, 16-20 = fine detail, more triangles)
  MAX_RINGS = 28,         -- most height slices of one tree (fewer = fewer triangles, coarser silhouette)
  SHELL = true,           -- colour the tree as a shell that looks the same from every angle (see header); false = project the sprite from the front only
  LUMP = 0.08,            -- how irregular the crown is (0 = perfectly smooth, 0.25 = very bushy)
  DEPTH = 1.0,            -- tree depth (front to back) as a fraction of its width; 1.0 = perfectly round in plan (same width from every angle)
  SMOOTH = true,          -- soften the pixel staircase of the silhouette before building rings
  FLIP_SPRITE = true,     -- mirror the sprite left-to-right before building (set false if trees come out mirrored the wrong way)
  FLIP_WINDING = nil,     -- nil = ask the engine which triangle winding is a front face (see windingFlip); true / false forces it
  MIN_HALF = 1,           -- a tree is never thinner (front to back) than this many cells
  MAX_HALF = 18,          -- a tree is never deeper than 2x this many world units, however wide it is

  MAX_TREE_H = 220,       -- a card taller than this is not a tree
  MIN_TREE_H = 0.5,       -- ...nor one flatter than this (a ground quad)
  TREE_UNIT = 33,         -- width of one tree on a card (an ordinary Sinnoh tree card): wider cards are split into this many trees
  Y_OFFSET = -10,          -- the WHOLE tree layer is moved this far along y when drawn (negative = down). The quick fix for floating trees
  SINK = 1.5,             -- planted this far below the card's base (world units; a tile is 16)
  PAD_SINK = true,        -- also sink by the transparent rows at the foot of the art, so the trunk (not the empty padding) meets the ground
  MAX_PAD_FRAC = 0.35,    -- ...but never by more than this fraction of the tree's height
  MAX_QUADS = 450000,     -- stop covering shapes in a land past this many quads (a quad = 2 triangles; walkable trees go first, then the border)
  BUILDS_PER_FRAME = 4,
  BUILD_BUDGET = 0.006,   -- seconds, steady state
  WARM_BUDGET = 0.04,     -- seconds per frame while the window is still filling
  DENSE_FRACTION = 0.92,  -- a sprite window this opaque has no silhouette to follow (no real alpha, or a wall tile): it is rounded, never built as a slab
  LOG = true,
  coverVersion = 0,       -- bumps whenever the set of covered shapes changes
  active = {},            -- cache shape record -> true (covered AND in the window)
  coveredNames = {},      -- texture/material names that converted in EVERY land of the window (Gen4Hide's fallback when a shape has no cache pointer)
  coveredLands = {},      -- land id -> true for every land inside the draw distance (Gen4Hide's name fallback is only valid there)
  limited = false,        -- true while a finite draw distance is in force
}

-- the cartridge's tree lean, the same constants Gen4Model classifies by
local TREE_NY, TREE_NZ, TREE_TOL = 0.819, 0.575, 0.04
local STRIP_REPEATS = 1.25
local FX16, UV_UNITS = 4096, 16
local LIGHT = { 0.30, 0.75, 0.55 }      -- toward the light: up and a little to the front (+z is the camera side)

local warned = {}
local function once(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then V.mod.log:info("Gen4Trees: " .. fmt:format(...)) end
end

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

-- One shared per-frame build budget (lib/Gen4Budget.lua); see Gen4Sand. The
-- old private WARM_BUDGET (40 ms a frame) is gone: it was the biggest single
-- hitch on desktop and a multi-second freeze on a phone.
local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local clock = (love and love.timer and love.timer.getTime) or os.clock

-- G4 DRAW DIST (lib/Gen4Distance.lua). Absent = the old behaviour, every land.
local Distance = optional("Gen4Distance")

-- Land meshes, keyed by the engine's land id (shared across crops of the
-- same grid). A route swap builds a new Ground, so a weak Ground-keyed cache
-- dropped every tree and let native cards flash back. Number keys stay;
-- table keys (a land record) go with the record. Dropped only by invalidate().
local landEntries = setmetatable({}, { __mode = "k" })
local window = {}
local resident = 0     -- built lands in landEntries
local tick = 0         -- bumps per window recompute; entry.used = last tick the land was wanted

-- ----------------------------------------------------------- decoding --

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- A shape's vertices { x, y, z, u, v } (u, v in TEXELS) and triangles, read the
-- way Gen4Model.new reads them. Stride is measured off the buffer.
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
  -- Vertex layout (both the 14- and 16-byte strides, see Gen4Model.new):
  -- pos s16 x3 at +0, u s16 at +6, v s16 at +8, colour at +10, normal at +13.
  -- The UV is ALWAYS at +6 / +8. It was read from the end of the vertex
  -- (stride - 4) before, which landed on the normal bytes, so every vertex had
  -- the same "UV" and every sprite sampled ONE texel -- a solid green block.
  local uvAt = 6
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
      s16(vdata, at + uvAt) / UV_UNITS,
      s16(vdata, at + uvAt + 2) / UV_UNITS,
    }
  end
  local triList = {}
  for t = 0, tris - 1 do
    local a1, a2, b1, b2, c1, c2 = idata:byte(t * 6 + 1, t * 6 + 6)
    if not c2 then break end
    triList[#triList + 1] = { a1 + a2 * 256 + 1, b1 + b2 * 256 + 1, c1 + c2 * 256 + 1 }
  end
  return pos, triList
end

-- Is this triangle one half of a tree card? The cartridge lean is
-- (0, 0.819, 0.575) toward the default camera, but trees also face east/west
-- and some caches store an upright billboard. Match any yaw of that lean, or
-- a nearly-vertical card.
local function isCardTri(pa, pb, pc)
  local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
  local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local len = math.sqrt(nx * nx + ny * ny + nz * nz)
  if len < 1e-6 then return false end
  nx, ny, nz = nx / len, ny / len, nz / len
  if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
  local horiz = math.sqrt(nx * nx + nz * nz)
  return math.abs(ny - TREE_NY) < TREE_TOL and math.abs(horiz - TREE_NZ) < TREE_TOL
end

local TREE_SUB = { "tree", "palm", "yashi", "matsu", "sugi" }

local function namesOf(s)
  return (tostring(s.texture or "") .. "\n" .. tostring(s.material or "")
          .. "\n" .. tostring(s.name or "")):lower()
end

-- The names a covered shape may be hidden by when its cache-record pointer is
-- missing: texture and material only. The shape's own name ("polygon8") is
-- NOT one -- it is reused by unrelated shapes in other lands.
local function nameKeys(s)
  local out = {}
  -- explicit fields, NOT ipairs over a table literal: ipairs stops at the first
  -- nil, and a cache record has no srcTexture (so nothing was ever registered)
  local fields = { s.srcTexture, s.texture, s.srcMaterial, s.material }
  for i = 1, 4 do
    local k = tostring(fields[i] or ""):lower()
    if k ~= "" and k ~= "nil" then out[#out + 1] = k end
  end
  return out
end

function GT.isTreeName(s)
  local n = namesOf(s):gsub("street", "")
  -- conttree IS a tree: the void-fill border, same sprite, tiled
  for _, sub in ipairs(TREE_SUB) do
    if n:find(sub, 1, true) then return true end
  end
  return false
end

-- Pair triangles into 4-corner cards. NSBMD tree quads often duplicate
-- vertices, so the two halves do not share indices -- matching only on
-- index would leave every tree native. Union-find on shared vertices would
-- glue neighbouring trees into one blob. Consecutive tris (the usual export
-- order) plus unique XYZ is the pairing that actually finds a card.
local function posKey(p)
  return string.format("%.3f:%.3f:%.3f", p[1], p[2], p[3])
end

local function uniquePosList(positions, a, b)
  local seen, list = {}, {}
  local function add(i)
    local p = positions[i]
    if not p then return end
    local k = posKey(p)
    if not seen[k] then seen[k] = i; list[#list + 1] = i end
  end
  for k = 1, 3 do add(a[k]) end
  for k = 1, 3 do add(b[k]) end
  return list
end

local function uvSpanU(positions, verts)
  local lo, hi = math.huge, -math.huge
  for _, i in ipairs(verts) do
    local u = positions[i][4]
    if u < lo then lo = u end
    if u > hi then hi = u end
  end
  return hi - lo
end

local function acceptCard(positions, verts, maxUvW)
  if #verts ~= 4 then return false end
  return not maxUvW or uvSpanU(positions, verts) <= maxUvW
end

local function cardsFromTris(positions, tris, maxUvW, leanOnly)
  local used, cards = {}, {}
  -- a triangle that is not itself a tree card (ground, wall, roof) is never
  -- paired: two ground triangles share an edge and would pass as a "card"
  local isCard = {}
  for i, t in ipairs(tris) do
    local pa, pb, pc = positions[t[1]], positions[t[2]], positions[t[3]]
    if not leanOnly or (pa and pb and pc and isCardTri(pa, pb, pc)) then isCard[i] = true else used[i] = 'x' end
  end
  for i = 1, #tris - 1, 2 do
    local verts = uniquePosList(positions, tris[i], tris[i + 1])
    if isCard[i] and isCard[i + 1] and acceptCard(positions, verts, maxUvW) then
      used[i], used[i + 1] = true, true
      cards[#cards + 1] = verts
    end
  end
  for i = 1, #tris do
    if not used[i] then
      local bestJ, bestN
      for j = i + 1, #tris do
        if not used[j] then
          local verts = uniquePosList(positions, tris[i], tris[j])
          if acceptCard(positions, verts, maxUvW) then
            local n = #verts
            if not bestN or n < bestN then bestJ, bestN = j, n end
          end
        end
      end
      if bestJ then
        used[i], used[bestJ] = true, true
        cards[#cards + 1] = uniquePosList(positions, tris[i], tris[bestJ])
      end
    end
  end
  local leftover = 0
  for i = 1, #tris do
    if used[i] ~= true then leftover = leftover + 1 end
  end
  return cards, leftover
end

-- ----------------------------------------------------------- textures --

local textures = {}   -- path -> { data, image, w, h } | false

local function textureFor(ground, s, set)
  set = set or ground.set
  local list = set and set.textures
  if not list then return nil end
  local rec = (s.palette and list[tostring(s.texture) .. "#" .. s.palette]) or list[s.texture]
  local path = rec and rec.path
  if not path then return nil end
  local hit = textures[path]
  if hit ~= nil then return hit or nil end
  local okA, Assets = pcall(require, "src.render.Assets")
  local okD, data = pcall(function()
    return love.image.newImageData(okA and Assets.resolve(path) or path)
  end)
  if not (okD and data) then textures[path] = false; return nil end
  local okI, image = pcall(love.graphics.newImage, data)
  if not (okI and image) then textures[path] = false; return nil end
  image:setFilter("nearest", "nearest")
  image:setWrap("clamp", "clamp")
  local w, h = data:getDimensions()
  hit = { data = data, image = image, w = w, h = h, path = path }
  textures[path] = hit
  return hit
end

-- ------------------------------------------------------------ meshing --

-- A stable pseudo-random number in 0..1 from two numbers (same as Gen4Rocks's
-- idea): trees differ from each other but never change between frames. A small
-- multiplier keeps every product exact in a double.
local function hash(x, z)
  local h = math.floor(x * 73.1 + z * 151.7) % 2147483647
  if h == 0 then h = 1 end
  h = (h * 16807) % 2147483647
  h = (h * 16807) % 2147483647
  return h / 2147483647
end

local function nearBase(positions, comp, ymin)
  local sx, sz, n = 0, 0, 0
  for _, i in ipairs(comp) do
    if positions[i][2] - ymin <= 0.5 then
      sx, sz, n = sx + positions[i][1], sz + positions[i][3], n + 1
    end
  end
  if n < 1 then
    for _, i in ipairs(comp) do
      sx, sz, n = sx + positions[i][1], sz + positions[i][3], n + 1
    end
  end
  if n < 1 then return 0, 0 end
  return sx / n, sz / n
end

local function meanWhere(positions, comp, axis, value, tol, field)
  local sum, n = 0, 0
  for _, i in ipairs(comp) do
    if math.abs(positions[i][axis] - value) <= tol then
      sum, n = sum + positions[i][field], n + 1
    end
  end
  if n == 0 then return nil end
  return sum / n
end

-- The sampled art of one sprite window, kept and reused: every tree of a kind
-- reads the same texels, and at TEX_STEP = 1 that is a lot of getPixel calls.
-- Read-only once stored. Dropped by GT.invalidate().
local gridCache, gridCacheN = {}, 0

-- WHICH WINDING IS A FRONT FACE? The engine draws only the front of a triangle,
-- and "front" depends on the order of its corners. Trees were coming out
-- inside-out (the far inner wall showing, lit backwards) because that order was
-- assumed. So ask Voxel3D itself: build its six cube faces from FACE_CORNERS in
-- the order pushQuad indexes them, and check whether the first triangle of each
-- runs counter-clockwise around the face's outward normal (the way this file
-- builds its own triangles) or the other way round. Face ids as the old meshing
-- used them: 1 = +x, 2 = -x, 3 = top, 4 = bottom, 5 = +z (front), 6 = -z (back).
local engineFlip
local function windingFlip()
  if GT.FLIP_WINDING ~= nil then return GT.FLIP_WINDING and true or false end
  if engineFlip ~= nil then return engineFlip end
  engineFlip = false
  local ok, why = pcall(function()
    local normals = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
    local map = {}
    Voxel3D.pushQuad(map, 0)
    local lowest = math.huge
    for i = 1, 3 do lowest = math.min(lowest, map[i]) end
    local score = 0
    for f = 1, 6 do
      local corners = Voxel3D.FACE_CORNERS[f]
      local p, q, s = corners[map[1] - lowest + 1], corners[map[2] - lowest + 1], corners[map[3] - lowest + 1]
      local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
      local vx, vy, vz = s[1] - p[1], s[2] - p[2], s[3] - p[3]
      local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
      local n = normals[f]
      local d = cx * n[1] + cy * n[2] + cz * n[3]
      if d > 1e-9 then score = score + 1 elseif d < -1e-9 then score = score - 1 end
    end
    engineFlip = score < 0
  end)
  if not ok then
    engineFlip = false
    once("windingFail", "could not read the engine's face winding (%s); using the rock winding", tostring(why))
  else
    once("winding", "engine front-face winding %s the rock winding -> trees %s",
         engineFlip and "is the OPPOSITE of" or "matches", engineFlip and "are flipped" or "are not flipped")
  end
  return engineFlip
end

-- ONE TREE, built like a Gen4Rocks boulder (see the header). `uL..uR` /
-- `vB..vT` is the art's texel window, `pivX/pivZ` the trunk's foot, `width` /
-- `height` the card's size in world units. Returns the quads it made (two
-- triangles count as one) -- or 0 and a reason.
local function emitTree(b, tex, uL, uR, vB, vT, pivX, baseY, pivZ, width, height)
  if width < 1 or height < 1 then return 0 end
  local nx = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(uR - uL) / GT.TEX_STEP + 0.5)))
  local ny = math.max(1, math.min(GT.MAX_BLOCKS, math.floor(math.abs(vB - vT) / GT.TEX_STEP + 0.5)))
  local sx, sy = width / nx, height / ny
  local originX = pivX - width * 0.5

  -- sample the art; row 1 is the top. The same sprite window recurs on every
  -- tree of a kind, so the grid is sampled once and reused (read-only).
  local gkey = string.format("%s|%.2f|%.2f|%.2f|%.2f|%d|%d|%s", tostring(tex.path), uL, uR, vB, vT,
                             nx, ny, GT.FLIP_SPRITE and "f" or "n")
  local grid, lo, any
  local hit = gridCache[gkey]
  if hit then
    grid, lo, any = hit.grid, hit.lo, hit.any
  else
    grid, lo, any = {}, {}, false
    for j = 1, ny do
      local row = {}
      local v = vT + (vB - vT) * ((j - 0.5) / ny)
      local ty = math.floor(v) % tex.h
      for i = 1, nx do
        -- FLIP_SPRITE reads the art right-to-left, so the whole tree (silhouette
        -- AND colours, everything below is built from this grid) is mirrored
        local col = GT.FLIP_SPRITE and (nx - i + 1) or i
        local u = uL + (uR - uL) * ((col - 0.5) / nx)
        local tx = math.floor(u) % tex.w
        local okP, r, g, bl, a = pcall(tex.data.getPixel, tex.data, tx, ty)
        if not okP then r, g, bl, a = 0, 0, 0, 0 end
        if a > 1 then r, g, bl, a = r / 255, g / 255, bl / 255, a / 255 end
        if a >= 0.5 then
          row[i] = { u = (tx + 0.5) / tex.w, v = (ty + 0.5) / tex.h }
          lo[j] = lo[j] or i
          any = true
        end
      end
      grid[j] = row
    end
    -- A window that is (nearly) all opaque has no tree outline to follow: the
    -- texture has no real alpha, or it is a forest-wall tile. Built as-is it would
    -- be one solid slab -- the "big green block". Give it the outline a tree has
    -- instead: an ellipse inscribed in the window, cut from the same texels.
    -- Real sprites (corners transparent, far below DENSE_FRACTION) never reach this.
    if any then
      local opaque = 0
      for j = 1, ny do for i = 1, nx do if grid[j][i] then opaque = opaque + 1 end end end
      if opaque >= GT.DENSE_FRACTION * nx * ny then
        for j = 1, ny do
          local ey = ((j - 0.5) / ny) * 2 - 1
          local half = math.sqrt(math.max(0, 1 - ey * ey))
          for i = 1, nx do
            local ex = ((i - 0.5) / nx) * 2 - 1
            if math.abs(ex) > half then grid[j][i] = nil end
          end
        end
      end
    end
    if gridCacheN > 400 then gridCache, gridCacheN = {}, 0 end
    gridCache[gkey] = { grid = grid, lo = lo, any = any }
    gridCacheN = gridCacheN + 1
  end
  if not any then return 0, "empty" end   -- nothing opaque: nothing to draw, and nothing native to keep

  -- FLOATING TREES: a sprite is usually drawn with a few empty rows under the
  -- trunk, and the tree stood on the card's base with that padding underneath
  -- it. Drop the whole tree by the empty rows so the lowest opaque block, the
  -- trunk's foot, sits where the card's base is.
  if GT.PAD_SINK then
    local lastRow = ny
    while lastRow > 1 and not lo[lastRow] do lastRow = lastRow - 1 end
    local pad = math.min((ny - lastRow) * sy, height * GT.MAX_PAD_FRAC)
    baseY = baseY - pad
  end

  -- 1. THE PROFILE. Every row that still has opaque cells gives one slice of
  -- the tree: where it starts and stops across the card = a centre and a
  -- half-width. (A tree sprite is one blob per row, so first..last is enough.)
  local prof, fallback, spans, topJ = {}, nil, {}, nil
  for j = 1, ny do
    local row = grid[j]
    local first, last
    for i = 1, nx do
      if row[i] then first = first or i; last = i end
    end
    if first then
      fallback = fallback or row[first]
      spans[j] = { first, last }
      topJ = topJ or j
      prof[#prof + 1] = { j = j,
                          y = baseY + (ny - j + 0.5) * sy,
                          cx = originX + (first - 1 + last) * 0.5 * sx,
                          hw = (last - first + 1) * 0.5 * sx }
    end
  end
  if #prof == 0 then return 0, "empty" end

  -- soften the pixel staircase: a [1 2 1] blur of centre and half-width
  if GT.SMOOTH and #prof > 2 then
    local sm = {}
    for n, p in ipairs(prof) do
      local a, c = prof[n > 1 and n - 1 or n], prof[n < #prof and n + 1 or n]
      sm[n] = { j = p.j, y = p.y,
                cx = (a.cx + 2 * p.cx + c.cx) * 0.25,
                hw = (a.hw + 2 * p.hw + c.hw) * 0.25 }
    end
    prof = sm
  end

  -- keep the triangle count in check: at most MAX_RINGS slices, evenly spread
  local cap = math.max(2, math.floor(GT.MAX_RINGS))
  if #prof > cap then
    local pick = {}
    for q = 0, cap - 1 do
      pick[#pick + 1] = prof[1 + math.floor((#prof - 1) * q / (cap - 1) + 0.5)]
    end
    prof = pick
  end

  local maxHw = 0
  for _, p in ipairs(prof) do if p.hw > maxHw then maxHw = p.hw end end

  -- rings, top to bottom: a pole above the first row (radius 0), the slices,
  -- then one more ring at the foot of the last row so the trunk reaches the ground
  local rings = {}
  rings[1] = { y = baseY + (ny - prof[1].j + 1) * sy, cx = prof[1].cx, hw = 0 }
  for _, p in ipairs(prof) do rings[#rings + 1] = p end
  local last = prof[#prof]
  rings[#rings + 1] = { y = baseY + (ny - last.j) * sy, cx = last.cx, hw = last.hw }

  -- 2. THE POINTS. Each ring is SIDES points around the tree's axis; the radius
  -- gets a smooth lump (a few low-frequency sines) plus a little per-vertex
  -- jitter, strongest on the crown and nearly zero on the trunk.
  local sides = math.max(5, math.floor(GT.SIDES))
  local turn = 6.2831853
  local seed = pivX * 0.91 + pivZ * 1.73
  local phase = hash(seed, 1.3) * turn / sides
  local p1, p2, p3 = hash(seed, 1.7) * turn, hash(2.3, seed) * turn, hash(seed + 4.1, seed - 9.2) * turn
  for r, ring in ipairs(rings) do
    local pts = {}
    ring.pts = pts
    if ring.hw <= 0 then
      for k = 1, sides do pts[k] = { ring.cx, ring.y, pivZ } end
    else
      local amp = GT.LUMP * math.min(1, ring.hw / (0.6 * maxHw))
      local yn = (ring.y - baseY) / height
      local depth = math.max(GT.MIN_HALF * sx * 0.5, math.min(ring.hw * GT.DEPTH, GT.MAX_HALF))
      for k = 1, sides do
        local th = phase + (k - 1) * turn / sides
        local c, s = math.cos(th), math.sin(th)
        local lump = math.sin(c * 2.3 + p1) * math.sin(yn * 5.3 + p2)
                   + 0.6 * math.sin(s * 3.1 + p3 + yn * 4.0)
        local jit = hash(seed + r * 0.731, k * 1.37 + seed) - 0.5
        local scale = 1 + amp * (0.5 * lump + 0.45 * jit)
        pts[k] = { ring.cx + ring.hw * scale * c, ring.y, pivZ + depth * scale * s }
      end
    end
  end

  -- 3. THE COLOUR. A facet wears the texel of the art where it sits (the card's
  -- x and y), so the front still looks like the sprite and the rim carries the
  -- outline. A spot outside the art (a lump pushed out) takes the nearest opaque cell.
  local function cellNear(i, j)
    i = math.max(1, math.min(nx, i))
    j = math.max(1, math.min(ny, j))
    local cell = grid[j][i]
    if cell then return cell end
    for rad = 1, 4 do
      for dj = -rad, rad do
        local row = grid[j + dj]
        if row then
          for di = -rad, rad do
            local c = row[i + di]
            if c then return c end
          end
        end
      end
    end
    return fallback
  end

  local function rowAt(my)
    return math.max(1, math.min(ny, ny - math.floor((my - baseY) / sy)))
  end

  -- front projection (SHELL = false): the texel the sprite shows at this x / y
  local function colourAt(mx, my)
    return cellNear(math.floor((mx - originX) / sx) + 1, rowAt(my))
  end

  -- SHELL: the texel depends on the facet's height and tilt only, never on the
  -- viewing side. `fy` is the facet's up-ness (1 = faces the sky), `n` its index
  -- (a stable seed for the scatter).
  local function shellColour(my, fy, n)
    local j = rowAt(my)
    local h1 = hash(seed + n * 1.7, n * 0.37 + seed)
    local h2 = hash(n * 2.9 + seed, seed * 0.13 + n)
    local spread = 1.2
    if fy > 0.55 then
      -- the hat: facets facing the sky wear the sprite's top rows (up to three)
      j = math.min(ny, topJ + math.floor((1 - fy) / 0.45 * 2.999))
      spread = 0.6
    end
    local sp = spans[j] or spans[topJ]
    if not sp then return cellNear(math.floor(nx / 2) + 1, j) end
    local i
    if fy < -0.25 or (fy <= 0.55 and h1 > 0.88) then
      i = (h2 < 0.5) and sp[1] or sp[2]        -- outline: the underside, and the odd clump edge
    else
      i = math.floor((sp[1] + sp[2]) * 0.5 + (h2 - 0.5) * spread * (sp[2] - sp[1]) * 0.5 + 0.5)
    end
    return cellNear(i, j)
  end

  -- 4. THE FACETS. Each triangle is lit flat from the upper front and takes one
  -- texel (one flat colour), exactly like a rock facet.
  local count = 0
  local flip = windingFlip()
  local S = GT.SCALE or 1
  local function tri(p, q, s)
    local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
    local vx, vy, vz = s[1] - p[1], s[2] - p[2], s[3] - p[3]
    local fx, fy, fz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local len = math.sqrt(fx * fx + fy * fy + fz * fz)
    if len < 1e-6 then return end            -- the pole's collapsed triangles
    fx, fy, fz = fx / len, fy / len, fz / len  -- outward by construction (see below)
    local my = (p[2] + q[2] + s[2]) / 3
    local cell
    if GT.SHELL then
      cell = shellColour(my, fy, count)
    else
      cell = colourAt((p[1] + q[1] + s[1]) / 3, my)
    end
    if not cell then return end
    local shade
    if GT.SHELL then
      shade = 0.82 + 0.18 * math.max(0, fy)      -- only up-ness lights it: the same from every side
    else
      local lit = math.max(0, fx * LIGHT[1] + fy * LIGHT[2] + fz * LIGHT[3])
      shade = math.min(1.0, 0.64 + 0.50 * lit)
    end
    -- a hair of facet-to-facet variation so the planes read as planes
    shade = math.min(1.0, shade * (0.94 + 0.10 * hash(seed + count * 3.3, count + seed * 0.1)))
    if fy > 0.55 then shade = -shade end       -- faces the sky (same flag the rocks and old trees use)
    if flip then q, s = s, q end                -- the engine's front is the other way round
    -- SCALE shrinks the finished tree toward its foot (colour and light were
    -- worked out above at full size; a uniform scale leaves the normals alone)
    local base = #b.verts
    b.verts[base + 1] = { pivX + (p[1] - pivX) * S, baseY + (p[2] - baseY) * S, pivZ + (p[3] - pivZ) * S, cell.u, cell.v, shade, 0 }
    b.verts[base + 2] = { pivX + (q[1] - pivX) * S, baseY + (q[2] - baseY) * S, pivZ + (q[3] - pivZ) * S, cell.u, cell.v, shade, 0 }
    b.verts[base + 3] = { pivX + (s[1] - pivX) * S, baseY + (s[2] - baseY) * S, pivZ + (s[3] - pivZ) * S, cell.u, cell.v, shade, 0 }
    local m = #b.map
    b.map[m + 1], b.map[m + 2], b.map[m + 3] = base + 1, base + 2, base + 3
    count = count + 1
  end

  -- Rings run top to bottom and points run round with rising angle, so the
  -- triangle order (A, B, C) / (A, C, D) has its cross product pointing OUT --
  -- the same winding the Gen4Rocks icosphere uses.
  for r = 1, #rings - 1 do
    local A, B = rings[r].pts, rings[r + 1].pts
    for k = 1, sides do
      local k2 = k % sides + 1
      tri(A[k], A[k2], B[k2])
      tri(A[k], B[k2], B[k])
    end
  end

  return count * 0.5
end

-- One card -> trees in bucket `b`. A wide card is the same sprite tiled
-- (`conttree*`): one tree per texture repeat.
local function buildCard(b, tex, positions, comp, strip)
  local xmin, xmax, ymin, ymax = math.huge, -math.huge, math.huge, -math.huge
  local zmin, zmax = math.huge, -math.huge
  local umin, umax, vmin, vmax = math.huge, -math.huge, math.huge, -math.huge
  for _, i in ipairs(comp) do
    local p = positions[i]
    if p[1] < xmin then xmin = p[1] end
    if p[1] > xmax then xmax = p[1] end
    if p[2] < ymin then ymin = p[2] end
    if p[2] > ymax then ymax = p[2] end
    if p[3] < zmin then zmin = p[3] end
    if p[3] > zmax then zmax = p[3] end
    if p[4] < umin then umin = p[4] end
    if p[4] > umax then umax = p[4] end
    if p[5] < vmin then vmin = p[5] end
    if p[5] > vmax then vmax = p[5] end
  end
  local spanX, spanZ = xmax - xmin, zmax - zmin
  -- WHICH WAY THE CARD RUNS comes from its NORMAL. A card leans back 35 degrees,
  -- so a TALL narrow tree has more z extent than x extent (height * 0.575 >
  -- width once it is taller than ~1.7x its width). Comparing the extents took
  -- every such tree for a card running along z: it sampled one texel column,
  -- came out as a deep green slab, and was given the wrong height. The
  -- normal's horizontal part points across the card, so the card runs along
  -- the OTHER axis.
  local alongZ
  do
    local best, bx, bz = 0, 0, 0
    local n = #comp
    for a = 1, n - 2 do
      for c = a + 1, n - 1 do
        for d = c + 1, n do
          local pa, pb, pc = positions[comp[a]], positions[comp[c]], positions[comp[d]]
          local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
          local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
          local nx = uy * vz - uz * vy
          local ny = uz * vx - ux * vz
          local nz = ux * vy - uy * vx
          local len = nx * nx + ny * ny + nz * nz
          if len > best then best, bx, bz = len, nx, nz end
        end
      end
    end
    if math.abs(bx) > 1e-9 or math.abs(bz) > 1e-9 then
      alongZ = math.abs(bx) > math.abs(bz)
    else
      alongZ = spanZ > spanX            -- a flat quad: no lean to read
    end
  end
  local width = alongZ and spanZ or spanX
  local lean = alongZ and spanX or spanZ     -- the extent the card's lean adds
  local height = math.sqrt((ymax - ymin) ^ 2 + lean ^ 2)
  if width < 1 or height < 1 then return 0, true end
  -- not a tree: a flat quad, or something far bigger than any tree
  if (ymax - ymin) < GT.MIN_TREE_H or height > GT.MAX_TREE_H then
    once("flat:" .. tostring(tex.path), "card '%s' is not a tree: dy %.1f height %.1f", tostring(tex.path), ymax - ymin, height)
    return 0, true
  end

  local uL, uR
  if not alongZ then
    uL = meanWhere(positions, comp, 1, xmin, 0.5, 4) or umin
    uR = meanWhere(positions, comp, 1, xmax, 0.5, 4) or umax
  else
    uL = meanWhere(positions, comp, 3, zmin, 0.5, 4) or umin
    uR = meanWhere(positions, comp, 3, zmax, 0.5, 4) or umax
  end
  local vB = meanWhere(positions, comp, 2, ymin, 0.5, 5) or vmax
  local vT = meanWhere(positions, comp, 2, ymax, 0.5, 5) or vmin

  local pivX, pivZ = nearBase(positions, comp, ymin)
  local baseY = ymin - GT.SINK
  -- ONE TREE PER TREE-WIDTH of card: an ordinary card is one tree (~33 wide),
  -- a border strip is several side by side, each its own slice of the art
  local trees = math.max(1, math.floor(width / GT.TREE_UNIT + 0.5))
  if strip then
    -- a border strip is the sprite tiled: one tree per texture REPEAT, so each
    -- slice is exactly one drawn tree (slicing by world width cut repeats in
    -- half, which is what turned borders into slabs)
    local repeats = math.abs(uR - uL) / math.max(1, tex.w)
    if repeats >= 1.5 then trees = math.floor(repeats + 0.5) end
  end
  local each = width / trees
  local made, solid = 0, nil
  for k = 0, trees - 1 do
    local a = uL + (uR - uL) * (k / trees)
    local c = uL + (uR - uL) * ((k + 1) / trees)
    local mid = -width * 0.5 + (k + 0.5) * each
    local px, pz = pivX, pivZ
    if alongZ then pz = pivZ + mid else px = pivX + mid end
    local m = emitTree(b, tex, a, c, vB, vT, px, baseY, pz, each, height)
    made = made + m
  end
  once("card:" .. tostring(tex.path),
       "card '%s' tex %dx%d: width %.1f height %.1f dy %.1f -> %d tree(s) of %.1f; u %.1f..%.1f v %.1f..%.1f",
       tostring(tex.path), tex.w, tex.h, width, height, ymax - ymin, trees, each,
       uL, uR, vB, vT)
  return made, false
end

local function packedFor(ground, object)
  local index = object.model
  if index == nil then return nil end
  if object.archive == "fldeff" then
    local set = ground.fldeffSet
    local at = set and set.byMember and set.byMember[index]
    return at and set.models and set.models[at], set
  end
  local set = ground.buildingSet
  return set and set.models and set.models[index + 1], set
end

local function objectPlace(object)
  local function scale(v) return (v and v ~= 0) and v or 1 end
  local yaw = object.yaw or object.rotY or object.rotationY or 0
  if math.abs(yaw) > 8 then yaw = math.rad(yaw) end
  return { sx = scale(object.scaleX), sy = scale(object.scaleY), sz = scale(object.scaleZ),
           x = object.x or 0, y = object.y or 0, z = object.z or 0, yaw = yaw }
end

local function applyPlace(positions, place)
  if not place then return positions end
  local c, s = math.cos(place.yaw or 0), math.sin(place.yaw or 0)
  local out = {}
  for i, p in ipairs(positions) do
    local x, y, z = p[1] * place.sx, p[2] * place.sy, p[3] * place.sz
    out[i] = { x * c - z * s + place.x, y + place.y, x * s + z * c + place.z, p[4], p[5] }
  end
  return out
end

-- One land chunk -> { buckets = {{mesh, tex}}, shapes = {record,...}, quads }
local function buildLand(ground, land)
  local record = ground.terrain.chunks[land]
  local out = { buckets = {}, shapes = {}, quads = 0, failed = {} }
  if not (record and record.shapes) then return out end
  local byPath, order = {}, {}
  local skipped = {}

  local function takeShape(s, posScale, texSet, place)
    local skip
    local named = GT.isTreeName(s)
    local strip = namesOf(s):find("conttree", 1, true) ~= nil
    if out.quads >= GT.MAX_QUADS then
      skip = "quad budget"
    end
    local positions, tris, tex, comps
    if not skip then
      positions, tris = readShape(ground, s, posScale)
      if not positions then skip = "unreadable" end
    end
    if not skip then
      positions = applyPlace(positions, place)
      if not named then
        local allCards = true
        for _, t in ipairs(tris) do
          local pa, pb, pc = positions[t[1]], positions[t[2]], positions[t[3]]
          if not (pa and pb and pc and isCardTri(pa, pb, pc)) then
            allCards = false
            break
          end
        end
        if not allCards then skip = "not all cards" end
      end
    end
    if not skip then
      tex = textureFor(ground, s, texSet)
      if not tex then skip = "no texture" end
    end
    if not skip then
      local leftover
      comps, leftover = cardsFromTris(positions, tris, (not strip) and STRIP_REPEATS * tex.w or nil, false)
      -- a tree-named shape is trees all through: stray triangles are dropped
      -- with it rather than keeping the whole shape native
      if #comps == 0 or leftover > 0 then skip = "not all cards" end
    end

    if skip then
      skipped[skip] = (skipped[skip] or 0) + 1
      if named then
        for _, k in ipairs(nameKeys(s)) do out.failed[k] = true end
        once("named:" .. tostring(land) .. tostring(s.texture or s.name) .. skip,
             "land %s: tree shape '%s' left native: %s", tostring(land), (namesOf(s):gsub("\n", "|")), skip)
      end
      return
    end
    local b = byPath[tex.path]
    if not b then
      b = { verts = {}, map = {}, tex = tex.image }
      byPath[tex.path] = b
      order[#order + 1] = b
    end
    -- ALL OR NOTHING PER SHAPE. A shape is hidden once it is covered, so every
    -- card in it has to have become trees; if one did not, undo the lot and
    -- leave the native shape drawing (it used to vanish with 0 quads).
    local v0, m0, built, ok, bad = #b.verts, #b.map, 0, true, 0
    for _, comp in ipairs(comps) do
      local n, failed = buildCard(b, tex, positions, comp, strip)
      if failed then bad = bad + 1 end
      built = built + n
    end
    -- A card that is not a tree (flat, giant, degenerate) draws nothing, as it
    -- always did; it must not put the shape's real trees back to native cards.
    -- Only a shape that built nothing at all stays native.
    if built <= 0 then ok = false end
    if not ok or built <= 0 then
      for i = #b.verts, v0 + 1, -1 do b.verts[i] = nil end
      for i = #b.map, m0 + 1, -1 do b.map[i] = nil end
      skipped["card unusable"] = (skipped["card unusable"] or 0) + 1
      for _, k in ipairs(nameKeys(s)) do out.failed[k] = true end
      once("unusable:" .. tostring(s.texture or s.name),
           "shape '%s' left native: nothing built from %d cards (%d not trees)", (namesOf(s):gsub("\n", "|")), #comps, bad)
      return
    end
    out.quads = out.quads + built
    out.shapes[#out.shapes + 1] = s
    once("ok:" .. tostring(s.texture or s.name),
         "shape '%s' built: %d cards (%d skipped as not trees), %d quads (land %s)", (namesOf(s):gsub("\n", "|")), #comps, bad, built, tostring(land))
  end

  local function isStrip(s) return namesOf(s):find("conttree", 1, true) ~= nil end
  for pass = 1, 2 do
    local wantStrip = (pass == 2)
    for _, s in ipairs(record.shapes) do
      if isStrip(s) == wantStrip then
        local okS, errS = pcall(takeShape, s, record.posScale or 1, ground.set, nil)
        if not okS then
          skipped["error"] = (skipped["error"] or 0) + 1
          for _, k in ipairs(nameKeys(s)) do out.failed[k] = true end
          once("shape:" .. tostring(s.texture or s.name), "tree shape '%s' ERRORED and was left native: %s", tostring(s.texture or s.name), tostring(errS))
        end
      end
    end
    for _, object in ipairs(record.objects or {}) do
      local packed, texSet = packedFor(ground, object)
      if packed and packed.shapes then
        local place = objectPlace(object)
        for _, s in ipairs(packed.shapes) do
          if isStrip(s) == wantStrip then
            local okS, errS = pcall(takeShape, s, packed.posScale or 1, texSet, place)
            if not okS then
              skipped["error"] = (skipped["error"] or 0) + 1
              for _, k in ipairs(nameKeys(s)) do out.failed[k] = true end
              once("shape:" .. tostring(s.texture or s.name), "prop tree shape '%s' ERRORED and was left native: %s", tostring(s.texture or s.name), tostring(errS))
            end
          end
        end
      end
    end
  end

  for _, b in ipairs(order) do
    local mesh = Voxel3D.newMesh(b.verts, b.map)
    if mesh then out.buckets[#out.buckets + 1] = { mesh = mesh, tex = b.tex } end
  end
  out.coveredKeys = {}
  for _, s in ipairs(out.shapes) do
    for _, k in ipairs(nameKeys(s)) do out.coveredKeys[k] = true end
  end
  if GT.LOG and (#out.shapes > 0 or next(skipped)) then
    local why = {}
    for k, n in pairs(skipped) do why[#why + 1] = ("%d %s"):format(n, k) end
    once("land" .. tostring(land),
         "land %s: %d tree shapes built (%d quads); left native: %s",
         tostring(land), #out.shapes, out.quads, #why > 0 and table.concat(why, ", ") or "none")
  end
  return out
end

-- ------------------------------------------------------------- window --

local lastSignature = ""

-- Hide native cards for this land's live shape records (the current Ground's
-- copies, which are not the pointers stored when the land was first built).
local function coverLiveShapes(ground, land, entry, active, names)
  local keys = entry.coveredKeys
  if not keys then
    keys = {}
    for _, s in ipairs(entry.shapes or {}) do
      for _, k in ipairs(nameKeys(s)) do keys[k] = true end
    end
    entry.coveredKeys = keys
  end
  for _, s in ipairs(entry.shapes or {}) do
    active[s] = true
    for _, k in ipairs(nameKeys(s)) do names[k] = true end
  end
  local record = ground.terrain and ground.terrain.chunks and ground.terrain.chunks[land]
  if not record then return end
  local function consider(s)
    for _, k in ipairs(nameKeys(s)) do
      if keys[k] then
        active[s] = true
        names[k] = true
        return
      end
    end
  end
  for _, s in ipairs(record.shapes or {}) do consider(s) end
  for _, object in ipairs(record.objects or {}) do
    local packed = packedFor(ground, object)
    if packed and packed.shapes then
      for _, s in ipairs(packed.shapes) do consider(s) end
    end
  end
end

-- Work out which lands are in the window, build what the budget allows, and
-- publish GT.active (shape records covered RIGHT NOW). Idempotent per frame;
-- Gen4Hide calls it before the native pass, GT.draw calls it again.
function GT.prepare(ground)
  local view = ground and ground.view3d
  if not (GT.enabled and ground and view and ground.grid and ground.terrain
          and ground.slice and ground.chunkPx and ground.half and ground.set) then
    GT.active, GT.list, GT.coveredNames, GT.coveredLands = {}, {}, {}, {}
    return
  end

  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  local W = GT.WINDOW
  local camCx, camCy = math.floor(view.x / px), math.floor(view.z / px)

  -- DRAW DISTANCE. Only lands within `reach` of the eye get trees; past
  -- it Platinum's flat cards keep drawing (Gen4Hide only hides covered lands).
  local reach = math.huge
  if Distance and Distance.reach then
    local okR, r = pcall(Distance.reach, px)
    if okR and tonumber(r) then reach = r end
  end
  GT.limited = reach ~= math.huge

  -- MEMO. Once every land of the window is built, the answer (which shapes are
  -- covered, which lands to draw) only changes when the camera moves a quarter
  -- chunk (the reach is measured to a land's NEAREST EDGE, so the chunk the
  -- camera stands in is not fine enough) -- or when Ground is replaced (new
  -- shape pointers to hide), or the draw distance changes.
  local qx, qy = math.floor(view.x * 4 / px), math.floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx
      and window.qy == qy and window.W == W and window.reach == reach then
    GT.active, GT.list, GT.coveredNames, GT.coveredLands =
      window.active, window.list, window.names, window.lands
    return
  end

  tick = tick + 1
  local want = {}
  local keepReach = reach * GT.HYSTERESIS
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local lx, lz = cx * px + half, cy * px + half
        -- built lands get the wider (hysteresis) reach; new ones must be inside the plain one
        local r = (land and landEntries[land]) and keepReach or reach
        if Distance and Distance.landInReach then
          if Distance.landInReach(view.x, view.z, lx, lz, px, r) then
            local dx, dz = lx - view.x, lz - view.z
            want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
          end
        else
          local dx, dz = cx - camCx, cy - camCy
          want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
        end
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local builds = 0
  local sig = {}
  local failedNames = {}
  local missing = 0
  for _, w in ipairs(want) do
    if not landEntries[w[4]] then missing = missing + 1 end
  end
  -- a window that is still filling gets the larger shared limit, so the old
  -- cards are not on screen beside the new trees for long
  local warm = missing > 1
  local cap = Budget.covered and 12 or GT.BUILDS_PER_FRAME
  local pending = 0
  local active, list, names, lands = {}, {}, {}, {}
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = land and landEntries[land]
    if not entry then
      if builds < cap and Budget.allow(warm) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "trees")
        if ok then
          entry = built
        else
          entry = { buckets = {}, shapes = {}, quads = 0, failed = {}, coveredKeys = {} }
          once("build", "a land chunk failed to build and was skipped: %s", tostring(built))
        end
        landEntries[land] = entry
        resident = resident + 1
      else
        pending = pending + 1
      end
    end
    if entry then
      entry.used = tick
      lands[land] = true
      sig[#sig + 1] = tostring(land)
      coverLiveShapes(ground, land, entry, active, names)
      for k in pairs(entry.failed or {}) do failedNames[k] = true end
      if #entry.buckets > 0 then
        list[#list + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half }
      end
    end
  end
  -- a name that failed in ANY land of the window is not safe to hide by name
  for k in pairs(failedNames) do names[k] = nil end
  local signature = table.concat(sig, ",")
  if signature ~= lastSignature or window.ground ~= ground then
    lastSignature = signature
    GT.coverVersion = GT.coverVersion + 1
  end

  -- Publish after the fill so a Ground swap does not clear hide/draw for a
  -- frame while overlapping lands are already in landEntries.
  GT.active, GT.list, GT.coveredNames, GT.coveredLands = active, list, names, lands
  window.ground, window.qx, window.qy, window.W, window.reach = ground, qx, qy, W, reach
  window.active, window.list, window.names, window.lands = active, list, names, lands
  window.done = pending == 0

  -- EVICT. landEntries was never freed before invalidate(), so every land the
  -- player had ever walked past kept its baked trees in GPU memory. Keep the
  -- most recently wanted ones and release the rest (oldest first); a released
  -- land simply rebuilds if the player walks back.
  local cap = GT.limited and GT.MAX_RESIDENT or GT.MAX_RESIDENT_MAX
  if resident > cap then
    local old = {}
    for land, entry in pairs(landEntries) do
      if entry.used ~= tick then old[#old + 1] = { entry.used or 0, land, entry } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while resident > cap and old[i] do
      local item = old[i]
      for _, b in ipairs(item[3].buckets or {}) do
        if b.mesh and b.mesh.release then pcall(b.mesh.release, b.mesh) end
      end
      landEntries[item[2]] = nil
      resident = resident - 1
      i = i + 1
    end
    once("evict", "released baked tree lands past the draw distance (keeping %d)", cap)
  end
end

-- Gen4Hide asks this per cache shape record.
function GT.isCovered(record)
  return record ~= nil and GT.active[record] == true
end

-- The fallback Gen4Hide uses when a built shape did not keep its cache `src`
-- pointer (so `isCovered` cannot answer): hide by texture / material name --
-- but only names that converted in EVERY land of the window (see `prepare`),
-- and never by the shape's own name. This is what lets BOTH kinds of tree
-- lose their native card once their new tree is standing.
function GT.isCoveredName(shape, land)
  local names = GT.coveredNames
  if not (shape and names) then return false end
  -- With a finite draw distance a name covers only the lands inside it: a
  -- terrain shape of a FAR land keeps its native cards (nothing replaces them).
  if land ~= nil and GT.limited and not GT.coveredLands[land] then return false end
  for _, k in ipairs(nameKeys(shape)) do
    if names[k] then return true end
  end
  return false
end

-- ---------------------------------------------------------------- draw --

function GT.draw(scene)
  if not GT.enabled then return end
  GT.prepare(scene.ground)
  if #GT.list == 0 then return end
  Voxel3D.seams(false)
  Voxel3D.glass(false)
  -- Every land in the window used to be drawn whatever the camera was looking
  -- at (~2M quads on Route 202). Skip the lands that are wholly outside the
  -- view cone; the radius is the land's half-diagonal plus tree height and
  -- terrain relief, so a visible tree is never dropped.
  local visible = scene.sphereVisible
  local ground = scene.ground
  local radius = ((ground and ground.chunkPx) or 512) * 0.72 + 160
  local drawn = 0
  for _, item in ipairs(GT.list) do
    if (not visible) or visible(item.x, 0, item.z, radius) then
      drawn = drawn + 1
      for _, b in ipairs(item.entry.buckets) do
        Voxel3D.draw(b.mesh, b.tex, Mat4.translate(item.x, GT.Y_OFFSET or 0, item.z), 0, nil, 0, false)
      end
    end
  end
  GT.lastDrawn, GT.lastTotal = drawn, #GT.list
  if visible and drawn < #GT.list then
    once("cull", "view culling skips tree lands the camera cannot see (%d of %d drawn this frame)",
         drawn, #GT.list)
  end
  Voxel3D.seams(true)
  Voxel3D.glass(true)
end

-- Drop every baked tree: a map was edited, or the mod was reloaded.
function GT.invalidate()
  for _, entry in pairs(landEntries) do
    for _, b in ipairs(entry.buckets or {}) do
      if b.mesh and b.mesh.release then pcall(b.mesh.release, b.mesh) end
    end
  end
  landEntries = setmetatable({}, { __mode = "k" })
  resident = 0
  window = {}
  lastSignature = ""
  textures = {}
  gridCache, gridCacheN = {}, 0
  GT.active, GT.list, GT.coveredNames, GT.coveredLands = {}, {}, {}, {}
  GT.coverVersion = GT.coverVersion + 1
end

-- built lands currently held (tests and the log read this)
function GT.residentCount() return resident end

return GT