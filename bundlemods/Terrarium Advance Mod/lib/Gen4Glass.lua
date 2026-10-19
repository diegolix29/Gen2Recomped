-- Gen4Glass: window glass on Platinum's own buildings -- the Gen 4 half of
-- lib/GlassMask.
--
-- WHY GLASSMASK ITSELF DOES NOT APPLY HERE
--
-- On Gen 1-3 the glass is a MASK the size of the tileset atlas, and the scene
-- shader samples it with the same UVs as the terrain mesh. Gen 4 has no tileset
-- atlas: the engine draws the cartridge's own NSBMD buildings with its own
-- shader, one texture per material. So the mask has to be per TEXTURE, and the
-- glass has to be drawn by us, on top of the engine's building, through the
-- Voxel3D shader that already knows what to do with a mask (lit panes after
-- dark, the movement-fed glint by day).
--
-- WHAT GEN 4 SAYS ABOUT ITS WINDOWS (there is no id list -- read this)
--
-- Gen 3 has a hand-made catalog (src/world/Gen3WindowMetatiles.lua). Gen 4 has
-- no counterpart: nothing in the engine lists window ids. What it DOES carry,
-- on every building shape, is the material name, the texture name and the
-- texture's own picture (`shape.image`, `shape.material`, `shape.texture`).
-- Two facts about Platinum's art are already established in the engine and are
-- used here instead of inventing a rule:
--
--   1. A glass MATERIAL is named for it: `wtk_kabe_garasu3` (garasu = glass,
--      stated translucent) -- Gen4Terrain.lua. Such a texture is glass whole.
--   2. A window PAINTED INTO A WALL TEXTURE is drawn at the palette's pure
--      white, and nothing else in a house wall is -- Gen4Model.splitWallBand
--      measured t1_s01 (glass 1.000 against siding 0.756..0.871).
--
-- So a texture's mask is "pure white texels" (or every texel, for a garasu
-- material). A texture whose white is most of the picture is not a window
-- texture (a white wall, a sign board) and is left alone -- MAX_FRACTION.
--
-- HOW IT DRAWS
--
-- For each land near the camera the placed buildings (Gen4Ground:objectsFor)
-- are walked; every TRIANGLE of a shape that wears a glass texture AND whose
-- UVs touch a glass texel is copied, PLACED, into one mesh per texture. The mesh
-- is drawn over the engine's building with the texture's glass-only copy as both
-- the texture and the mask: non-glass texels are alpha 0 and the scene shader
-- discards them, so only the panes are drawn. `pull` nudges the overlay toward
-- the eye so it never z-fights the surface it sits on. Outdoors only, exactly
-- like the Gen 1-3 glass.
--
-- By default only the NIGHT lamps are drawn (the overlay's lit colour does not
-- depend on how the engine shaded the wall, so nothing can mismatch). The day
-- glint is DAY_GLINT: it lifts the overlay's own base colour, which is not
-- guaranteed to match the engine's shading of the same wall, so it is off until
-- it has been looked at in play.
--
-- PERFORMANCE (what changed from version 1, and the knobs)
--
--   * Only triangles that can show glass are kept. Version 1 copied every
--     triangle of a glass-bearing shape (roofs, side walls...) and let the pixel
--     shader throw them away, and Gen4Light then lit the same full meshes again.
--     The test is conservative: a triangle is kept when its UV bounding box
--     covers any glass texel (a summed-area table makes that O(1)), so a pane is
--     never dropped, only needless geometry is.
--   * The land window is WINDOW = 2 (5x5 lands, was 3 = 7x7) and is also bounded
--     by Gen4Distance (the G4 DRAW DIST row), so NEAR / MID / FAR also shrink or
--     grow the glass. The haze has swallowed anything further anyway.
--   * By day nothing is built (BUILD_BY_DAY = false). Lands fill in over the first
--     dusk frames, spread by Gen4Budget, while the lamps are still fading in.
--   * Pieces are drawn grouped by texture, so the glass uniforms are sent once per
--     texture instead of once per piece.
--   * The pane light list, the wall piece list and the hour's brightness are
--     cached instead of being rebuilt, sorted and re-queried several times a frame.
--   * Texel tests read a Lua table instead of pcall(ImageData:getPixel).
--
-- BRIGHTNESS knobs (all live, nothing needs a restart):
--
--   PANE_BRIGHTNESS  scales the lamp colour the panes are painted with. 1.0 is the
--                    old look (a flat, full-strength lamp colour); lower is dimmer.
--   SCREEN_POWER     how strongly a pane lights the road and wall around it.
--   SCREEN_RADIUS    how far that light reaches, in world units.
--   SCREEN_LIMIT     how many pane sources are handed on (Gen4Light, Gen4Tint).
--   (Gen4Light.PANE_STRENGTH / PANE_LIMIT / WALL_LIGHTS and Gen4Tint.TOWN_FLOOR
--    are the matching knobs on the receiving side.)
--
-- TUNING: with LOG on, every texture analysed writes one line (grep
-- "Gen4Glass:") giving its names, size, glass texel count and verdict. A white
-- wall that lights up like a lamp is a texture to add to DENY_NAMES; a window
-- that never lights is a texture to add to ALLOW.
--
-- NOT VERIFIED IN GAME: written without a ROM or a LOVE runtime to hand. The pure
-- logic (texel masks, triangle filtering, clustering, nearest-light selection) is
-- exercised by a stub harness; the drawing itself has not been looked at. It is
-- isolated the way the other Gen 4 passes are (Bridge disables an effect that
-- throws). Bridge.setEffect("glass", false) turns it off.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Assets = require("src.render.Assets")

local function optional(name)
  local ok, mod = pcall(V.require, name)
  return ok and mod or nil
end

local DayNight = optional("DayNight")
local Budget = optional("Gen4Budget") or { allow = function() return true end, charge = function() end }
local Distance = optional("Gen4Distance")
local clock = (love and love.timer and love.timer.getTime) or os.clock

local floor, min, max, sqrt, abs = math.floor, math.min, math.max, math.sqrt, math.abs

local Glass = {
  enabled = true,

  -- substrings of a shape's TEXTURE or MATERIAL name that make the whole
  -- texture glass (Gen4Terrain: `wtk_kabe_garasu3`)
  GLASS_NAMES = { "garasu", "glass" },
  -- substrings that are never scanned: shadows, water, sky, snow
  DENY_NAMES = { "kage", "shadow", "shade", "water", "sea", "kumo", "cloud",
                 "snow", "yuki" },
  -- exact lower-case texture names forced to glass whole (tuning)
  -- c1_lamp01 / c1_lamp02: city building lights (not street posts).
  ALLOW = { c1_lamp01 = true, c1_lamp02 = true },

  WHITE = 0.88,-- every channel at least this: the palette's white
  MIN_TEXELS = 4,       -- fewer glass texels than this is noise, not a pane
  MAX_FRACTION = 0.45,  -- more of the picture than this and it is not a window
  MAX_SAT_TEXELS = 262144, -- bigger textures skip the fast triangle test (all kept)

  WINDOW = 2,           -- lands each way around the camera (was 3)
  REACH_SLACK = 0.35,   -- chunks past Gen4Distance's reach a land is still kept
  PULL = 0.6,           -- toward the eye, world units: the overlay's depth bias
  SHADE = 0.1,          -- the overlay's own vertex shade (day glint's base only)

  NIGHT_MIN = 0.02,     -- below this the lamps are out and nothing is drawn
  BUILD_BY_DAY = false, -- true: build the meshes by day so dusk never builds anything
  DAY_GLINT = false,    -- see the header
  GLINT_RATE = 0.05,    -- radians of sweep per world unit travelled
  GLINT_IN = 0.12,      -- strength gained per moving frame
  GLINT_OUT = 0.08,     -- ...and lost per resting frame
  GLINT_MIN = 0.02,

  BUILDS_PER_FRAME = 3,
  MAX_RESIDENT = 30,
  MAX_VERTS = 60000,    -- split a mesh before it needs 32-bit indices
  LOG = true,

  -- BRIGHTNESS (see the header)
  PANE_BRIGHTNESS = 0.7,  -- 1.0 = the old, full-strength lamp colour on the panes
  SCREEN_POWER = 0.3,     -- pane light on roads / walls (was 0.4)
  SCREEN_RADIUS = 100,    -- ...and its reach in world units (was 192)
  SCREEN_LIMIT = 16,      -- pane sources handed on per frame (was 32)

  -- Point lights from the glass MASK itself (pane centroids, not the land
  -- centre). The shader only has eight lamp slots, shared with street lamps.
  LIGHT_RADIUS = 48,
  LIGHT_LIMIT = 8,
  LIGHT_CLUSTER = 20,   -- merge pane samples this close (one window, one flame)

  stats = { textures = 0, glassTextures = 0, lands = 0, shapes = 0 },
  version = 2,
}

local FX16, UV_UNITS = 4096, 16

local warned = {}
local function note(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  if V.mod and V.mod.log then
    -- already formatted: a leftover "%" (e.g. "17%") must not be re-parsed
    V.mod.log:info("%s", "Gen4Glass: " .. fmt:format(...))
  end
end

local function lowered(s) return tostring(s or ""):lower() end

local function hasAny(name, list)
  for _, sub in ipairs(list) do
    if name:find(sub, 1, true) then return true end
  end
  return false
end

-- Modules that are looked up every frame are looked up once.
local Mat4
local function mat4()
  if not Mat4 then Mat4 = V.require("Mat4") end
  return Mat4
end

local spawnMod
local function spawn()
  if spawnMod == nil then spawnMod = optional("Gen4Spawn") or false end
  return spawnMod or nil
end

-- The hour changes over minutes; asking DayNight for it (a table of phase
-- weights each time) five times a frame bought nothing. 0.1 s is invisible.
local HOUR_TTL = 0.1
local nightAt, nightVal = -1, 0
local function nightNow()
  if not DayNight then return 0 end
  local t = clock()
  if t < nightAt or t - nightAt > HOUR_TTL then
    local ok, n = pcall(DayNight.windowLight)
    nightVal = ok and tonumber(n) or 0
    nightAt = t
  end
  return nightVal
end

local lampAt, lampVal = -1, nil
local function lampNow()
  local t = clock()
  if t < lampAt or t - lampAt > HOUR_TTL or not lampVal then
    local c
    if DayNight then
      local ok, got = pcall(DayNight.lampColor)
      if ok and type(got) == "table" then c = got end
    end
    lampVal = c or Voxel3D.lampColor or { 1.0, 0.84, 0.5 }
    lampAt = t
  end
  return lampVal
end

-- ------------------------------------------------------- the texture masks --

-- Summed-area table of the glass texels, so "is there any glass in this
-- rectangle of the picture" is four reads. sat[y * (w + 1) + x + 1] holds the
-- number of glass texels with texel x' < x and y' < y.
local function buildSat(bits, w, h)
  local W1 = w + 1
  local sat = {}
  for i = 1, W1 * (h + 1) do sat[i] = 0 end
  for y = 1, h do
    local rowSum = 0
    local rowBase = (y - 1) * w
    for x = 1, w do
      if bits[rowBase + x] then rowSum = rowSum + 1 end
      sat[y * W1 + x + 1] = sat[(y - 1) * W1 + x + 1] + rowSum
    end
  end
  return sat
end

-- glass texels in the inclusive texel rectangle [x0..x1] x [y0..y1]
local function satCount(sat, w, x0, x1, y0, y1)
  local W1 = w + 1
  return sat[(y1 + 1) * W1 + x1 + 2] - sat[(y1 + 1) * W1 + x0 + 1]
       - sat[y0 * W1 + x1 + 2] + sat[y0 * W1 + x0 + 1]
end

-- The texels a span [lo, hi] (texel units, repeat wrap) touches: one or two
-- inclusive ranges (c = -1 when there is only one). A span of a whole picture
-- or more is every texel.
local function texelSpan(lo, hi, n)
  local a, b = floor(lo), floor(hi)
  if b - a + 1 >= n then return 0, n - 1, -1, -1 end
  a, b = a % n, b % n
  if a <= b then return a, b, -1, -1 end
  return a, n - 1, 0, b
end

-- Could a triangle whose UVs span this box (normalised, repeat wrap) show any
-- glass? Conservative: true whenever the BOX covers a glass texel, so a pane is
-- never dropped (the cost of a wrong yes is a few triangles drawn for nothing).
local function boxHasGlass(entry, u0, u1, v0, v1)
  if entry.whole or not entry.sat then return true end
  local sat, w, h = entry.sat, entry.w, entry.h
  local xa, xb, xc, xd = texelSpan(u0 * w, u1 * w, w)
  local ya, yb, yc, yd = texelSpan(v0 * h, v1 * h, h)
  if satCount(sat, w, xa, xb, ya, yb) > 0 then return true end
  if yc >= 0 and satCount(sat, w, xa, xb, yc, yd) > 0 then return true end
  if xc >= 0 then
    if satCount(sat, w, xc, xd, ya, yb) > 0 then return true end
    if yc >= 0 and satCount(sat, w, xc, xd, yc, yd) > 0 then return true end
  end
  return false
end

-- image path -> { image, w, h, texels, bits, sat, whole } for a texture with
-- glass in it, or false for one without (or unreadable: a verdict for the
-- session, no retry loop)
local textures = {}

local function analyse(path, textureName, materialName)
  local hit = textures[path]
  if hit ~= nil then return hit or nil end
  textures[path] = false
  Glass.stats.textures = Glass.stats.textures + 1

  local tex, mat = lowered(textureName), lowered(materialName)
  if hasAny(tex, Glass.DENY_NAMES) or hasAny(mat, Glass.DENY_NAMES) then
    if Glass.LOG then note("deny:" .. path, "%s (%s): skipped, name is denied", tex, mat) end
    return nil
  end

  -- `Assets.image` hands back a placeholder for a path that is not there, so
  -- the pixels are read with the call that RAISES (as Gen4Model.splitWallBand)
  local okData, data = pcall(function()
    return love.image.newImageData(Assets.resolve(path))
  end)
  if not (okData and data) then
    note("read:" .. path, "%s: could not read the texture", tostring(path))
    return nil
  end
  local w, h = data:getDimensions()
  if w < 1 or h < 1 then return nil end

  local whole = Glass.ALLOW[tex] == true
                or hasAny(tex, Glass.GLASS_NAMES) or hasAny(mat, Glass.GLASS_NAMES)
  local white = Glass.WHITE
  local out = love.image.newImageData(w, h)
  local bits = (not whole) and {} or nil     -- which texels are glass, 1-based
  local count = 0
  for y = 0, h - 1 do
    local row = y * w + 1
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      if a >= 0.5 and (whole or (r >= white and g >= white and b >= white)) then
        out:setPixel(x, y, r, g, b, 1)
        count = count + 1
        if bits then bits[row + x] = true end
      else
        out:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  pcall(data.release, data)

  local fraction = count / (w * h)
  local keep = count >= Glass.MIN_TEXELS and (whole or fraction <= Glass.MAX_FRACTION)
  if Glass.LOG then
    note("tex:" .. path, "%s (%s) %dx%d: %d glass texels (%.0f%%)%s -> %s",
         tex, mat, w, h, count, fraction * 100, whole and ", whole pane" or "",
         keep and "GLASS" or "no glass")
  end
  if not keep then
    pcall(out.release, out)
    return nil
  end

  local okImg, image = pcall(love.graphics.newImage, out)
  pcall(out.release, out)                    -- the GPU has its own copy now
  if not (okImg and image) then
    note("img:" .. path, "%s: could not make the glass image", tostring(path))
    return nil
  end
  image:setFilter("nearest", "nearest")
  image:setWrap("repeat", "repeat")       -- Gen 4 UVs run far past 0..1
  local sat = (bits and w * h <= Glass.MAX_SAT_TEXELS) and buildSat(bits, w, h) or nil
  local entry = { image = image, bits = bits, sat = sat, w = w, h = h,
                  texels = count, whole = whole }
  textures[path] = entry
  Glass.stats.glassTextures = Glass.stats.glassTextures + 1
  return entry
end

-- ------------------------------------------------------------ the geometry --

local function s16(data, at)                 -- `at` is 0-based
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- Gen4Ground's `placement`, as a row-major 3x4: scale, then an optional turn
-- about the vertical, then translate. (Gen4Ground keeps its own copy local.)
local function placementOf(object)
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  local yaw = object.rotY and object.rotY ~= 0 and math.rad(object.rotY) or nil
  if yaw then
    local c, s = math.cos(yaw), math.sin(yaw)
    return { c * sx, 0, s * sz, object.x or 0,
             0, sy, 0, object.y or 0,
             -s * sx, 0, c * sz, object.z or 0 }
  end
  return { sx, 0, 0, object.x or 0,
           0, sy, 0, object.y or 0,
           0, 0, sz, object.z or 0 }
end

local function newBucket(entry)
  return { entry = entry, verts = {}, n = 0, map = {}, mapN = 0,
           meshes = {}, lightPts = {} }
end

-- True when this UV lands on a glass texel of the mask (repeat wrap).
local function glassAt(entry, u, v)
  if not entry then return false end
  if entry.whole or not entry.bits then return true end
  u = u - floor(u)
  v = v - floor(v)
  local w, h = entry.w, entry.h
  local x = min(w - 1, max(0, floor(u * w)))
  local y = min(h - 1, max(0, floor(v * h)))
  return entry.bits[y * w + x + 1] == true
end

local function cellKey(cx, cz) return cx * 100003 + cz end

-- Merge samples closer than `radius` into one point each (a window is one
-- flame, not one per triangle). Greedy from the first unused sample, like the
-- plain pairwise version it replaces, but through a grid so a land with
-- thousands of pane triangles does not cost thousands squared.
local function clusterPoints(pts, radius)
  local n = #pts
  if n == 0 then return {} end
  local r2 = radius * radius
  local grid, cxs, czs = {}, {}, {}
  for i = 1, n do
    local p = pts[i]
    local cx, cz = floor(p[1] / radius), floor(p[3] / radius)
    cxs[i], czs[i] = cx, cz
    local k = cellKey(cx, cz)
    local list = grid[k]
    if not list then list = {}; grid[k] = list end
    list[#list + 1] = i
  end
  local out, used = {}, {}
  for i = 1, n do
    if not used[i] then
      local p = pts[i]
      used[i] = true
      local sx, sy, sz, c = p[1], p[2], p[3], 1
      for ox = -1, 1 do
        for oz = -1, 1 do
          local list = grid[cellKey(cxs[i] + ox, czs[i] + oz)]
          if list then
            for li = 1, #list do
              local j = list[li]
              if not used[j] then
                local q = pts[j]
                local dx, dz = q[1] - p[1], q[3] - p[3]
                if dx * dx + dz * dz <= r2 then
                  used[j] = true
                  sx, sy, sz, c = sx + q[1], sy + q[2], sz + q[3], c + 1
                end
              end
            end
          end
        end
      end
      out[#out + 1] = { x = sx / c, y = sy / c, z = sz / c }
    end
  end
  return out
end

local function seal(bk)
  if bk.n == 0 then return end
  local mesh = Voxel3D.newMesh(bk.verts, bk.map)
  if mesh then bk.meshes[#bk.meshes + 1] = mesh end
  bk.verts, bk.map, bk.n, bk.mapN = {}, {}, 0, 0
end

-- One packed shape, placed, into its texture's bucket. Layout (Gen4ModelPack):
-- 16 bytes a vertex -- x y z u v as s16, then colour and normal -- and u16
-- indices into the shape's OWN vertex array.
local function buildingLightNames()
  local names = { c1_lamp01 = true, c1_lamp02 = true }
  local Lawn = optional("Gen4Lawn")
  if Lawn and Lawn.buildingLightIds then
    local ok, got = pcall(Lawn.buildingLightIds)
    if ok and type(got) == "table" then
      for k, v in pairs(got) do
        if v then names[tostring(k):lower()] = true end
      end
    end
  end
  return names
end

local function readTerrainPos(ground, s, posScale)
  local vdata = s.vertices
  if type(vdata) ~= "string" then
    vdata = ground:slice(s.vertexAt, s.vertexBytes)
  end
  local count = s.vertexCount or 0
  if not vdata or count < 3 then return nil end
  local stride = floor(#vdata / count)
  if stride < 10 then return nil end
  local pos = {}
  for i = 1, count do
    local at = (i - 1) * stride
    pos[i] = {
      s16(vdata, at) / FX16 * posScale,
      s16(vdata, at + 2) / FX16 * posScale,
      s16(vdata, at + 4) / FX16 * posScale,
    }
  end
  return pos
end

-- texel -> 0..1 of THIS picture (no V flip: Gen4Model does none)
local function uvOf(vdata, stride, idx, tw, th)
  local at = idx * stride
  return s16(vdata, at + 6) / UV_UNITS / tw, s16(vdata, at + 8) / UV_UNITS / th
end

-- A shape vertex, placed, into the bucket (once per shape: `remap` is the
-- shape's own index -> the bucket's index).
local function placeVertex(bk, vdata, stride, idx, posScale, m, tw, th, remap)
  local hit = remap[idx]
  if hit then return hit end
  local at = idx * stride
  local x = s16(vdata, at) / FX16 * posScale
  local y = s16(vdata, at + 2) / FX16 * posScale
  local z = s16(vdata, at + 4) / FX16 * posScale
  local n = bk.n + 1
  bk.n = n
  bk.verts[n] = {
    m[1] * x + m[2] * y + m[3] * z + m[4],
    m[5] * x + m[6] * y + m[7] * z + m[8],
    m[9] * x + m[10] * y + m[11] * z + m[12],
    s16(vdata, at + 6) / UV_UNITS / tw,
    s16(vdata, at + 8) / UV_UNITS / th,
    Glass.SHADE, 0,
  }
  remap[idx] = n
  return n
end

-- Only the triangles that can show a pane are kept. Version 1 kept them all and
-- let the pixel shader discard the rest: every roof and side wall of a
-- glass-bearing shape was rasterised (and, in Gen4Light, lit by a per-pixel loop
-- over the lamps) for nothing.
local function addShape(bk, s, posScale, m)
  local vdata, idata = s.vertices, s.indices
  if type(vdata) ~= "string" or type(idata) ~= "string" then return false end
  local count, tris = s.vertexCount or 0, s.triangleCount or 0
  if count < 3 or tris < 1 then return false end
  local stride = floor(#vdata / count)
  if stride ~= 14 and stride ~= 16 then return false end
  local entry = bk.entry
  local tw, th = entry.w, entry.h
  local remap, kept = {}, 0
  local map, verts = bk.map, bk.verts
  for t = 0, tris - 1 do
    local a1, a2, b1, b2, c1, c2 = idata:byte(t * 6 + 1, t * 6 + 6)
    if not c2 then break end
    local ia, ib, ic = a1 + a2 * 256, b1 + b2 * 256, c1 + c2 * 256
    if ia < count and ib < count and ic < count then
      local ua, va = uvOf(vdata, stride, ia, tw, th)
      local ub, vb = uvOf(vdata, stride, ib, tw, th)
      local uc, vc = uvOf(vdata, stride, ic, tw, th)
      if boxHasGlass(entry, min(ua, ub, uc), max(ua, ub, uc),
                     min(va, vb, vc), max(va, vb, vc)) then
        local A = placeVertex(bk, vdata, stride, ia, posScale, m, tw, th, remap)
        local B = placeVertex(bk, vdata, stride, ib, posScale, m, tw, th, remap)
        local C = placeVertex(bk, vdata, stride, ic, posScale, m, tw, th, remap)
        local mn = bk.mapN
        map[mn + 1], map[mn + 2], map[mn + 3] = A, B, C
        bk.mapN = mn + 3
        kept = kept + 1
        -- One sample per triangle that actually hits the mask: the overlay's
        -- own verts, so the flame sits on the pane rather than on the land.
        local pa, pb, pc = verts[A], verts[B], verts[C]
        if glassAt(entry, pa[4], pa[5]) or glassAt(entry, pb[4], pb[5])
           or glassAt(entry, pc[4], pc[5])
           or glassAt(entry, (pa[4] + pb[4] + pc[4]) / 3, (pa[5] + pb[5] + pc[5]) / 3) then
          bk.lightPts[#bk.lightPts + 1] = {
            (pa[1] + pb[1] + pc[1]) / 3,
            (pa[2] + pb[2] + pc[2]) / 3,
            (pa[3] + pb[3] + pc[3]) / 3,
          }
        end
      end
    end
  end
  if kept == 0 then return false end
  Glass.stats.shapes = Glass.stats.shapes + 1
  if bk.n > Glass.MAX_VERTS then seal(bk) end
  return true
end

-- Everything on one land that wears glass: { pieces = { {mesh, entry}, ... } }
local function harvestBuildingTerrain(ground, record, pts)
  local building = buildingLightNames()
  if not (record and record.shapes) then return end
  for _, s in ipairs(record.shapes) do
    local tex = lowered(s.texture or s.srcTexture)
    if building[tex] then
      local pos = readTerrainPos(ground, s, record.posScale or 1)
      if pos and #pos > 0 then
        local sx, sy, sz, n = 0, 0, 0, 0
        for _, p in ipairs(pos) do
          sx, sy, sz, n = sx + p[1], sy + p[2], sz + p[3], n + 1
        end
        pts[#pts + 1] = { sx / n, sy / n, sz / n }
      end
    end
  end
end

local function buildLand(ground, land)
  local out = { pieces = {}, lights = {} }
  local record = ground.terrain and ground.terrain.chunks and ground.terrain.chunks[land]
  if not record then return out end
  local set = ground.buildingSet
  local objects
  if set and set.models then
    if type(ground.objectsFor) == "function" then
      local ok, list = pcall(ground.objectsFor, ground, land, record)
      objects = ok and list or nil
    end
    objects = objects or record.objects
  end

  local buckets, order = {}, {}
  for _, object in ipairs(objects or {}) do
    -- a fldeff prop is a sign or a mailbox; a live one is a moving platform
    if object.archive ~= "fldeff" and not object.live then
      local packed = set.models[(tonumber(object.model) or -1) + 1]
      if packed and packed.shapes then
        local m, posScale = nil, packed.posScale or 1
        for _, s in ipairs(packed.shapes) do
          if s.image then
            local entry = analyse(s.image, s.texture, s.material)
            if entry then
              m = m or placementOf(object)
              local bk = buckets[s.image]
              if not bk then
                bk = newBucket(entry)
                buckets[s.image] = bk
                order[#order + 1] = bk
              end
              addShape(bk, s, posScale, m)
            end
          end
        end
      end
    end
  end
  local pts = {}
  for _, bk in ipairs(order) do
    seal(bk)
    for _, mesh in ipairs(bk.meshes) do
      out.pieces[#out.pieces + 1] = { mesh = mesh, entry = bk.entry }
    end
    for _, p in ipairs(bk.lightPts or {}) do
      pts[#pts + 1] = p
    end
  end
  harvestBuildingTerrain(ground, record, pts)
  out.lights = clusterPoints(pts, Glass.LIGHT_CLUSTER)
  Glass.stats.lands = Glass.stats.lands + 1
  if Glass.LOG and #out.lights > 0 then
    note("lights:" .. tostring(land),
         "land %s: %d glass flame(s) from %d pane triangle(s)",
         tostring(land), #out.lights, #pts)
  end
  return out
end

-- ------------------------------------------------------- the land window --

-- ground -> { lands = { [land] = entry }, resident = n }. Per ground because
-- a map can edit a chunk's props (def.gen4ModelEdits), so two maps drawing the
-- same chunk can disagree about what stands on it.
local perGround = setmetatable({}, { __mode = "k" })
local window = {}
local tick = 0

local function release(entry)
  for _, p in ipairs(entry.pieces or {}) do
    if p.mesh and p.mesh.release then pcall(p.mesh.release, p.mesh) end
  end
end

-- How far, in world units, a land may be from the eye and still be kept: the
-- G4 DRAW DIST row (Gen4Distance) plus a little slack, never past the window.
local function reachFor(px)
  local cap = (Glass.WINDOW + 0.5) * px
  if not (Distance and Distance.reach) then return cap end
  local ok, r = pcall(Distance.reach, px)
  r = ok and tonumber(r) or cap
  return min(r + Glass.REACH_SLACK * px, cap)
end

-- Is a square land (centre cx, cz; side px) within `reach` of the eye? The
-- distance is to the NEAREST POINT of the land.
local function inReach(ex, ez, cx, cz, px, reach)
  local h = px * 0.5
  local dx = max(abs(ex - cx) - h, 0)
  local dz = max(abs(ez - cz) - h, 0)
  return dx * dx + dz * dz <= reach * reach
end

-- Everything the frame needs from the window, laid out once when the window
-- changes instead of rebuilt every frame:
--   groups  the pieces by texture, so the glass uniforms go out once a texture
--   walls   { mesh, x, z } for Gen4Light
--   flat    every pane flame in world space, for the nearest-N pick
local function index(win)
  local groups, byEntry, walls, flat = {}, {}, {}, {}
  for _, item in ipairs(win.list) do
    for _, piece in ipairs(item.entry.pieces or {}) do
      local g = byEntry[piece.entry]
      if not g then
        g = { entry = piece.entry, n = 0 }
        byEntry[piece.entry] = g
        groups[#groups + 1] = g
      end
      g.n = g.n + 1
      g[g.n] = { mesh = piece.mesh, item = item }
      walls[#walls + 1] = { mesh = piece.mesh, x = item.x, z = item.z }
    end
    for _, p in ipairs(item.entry.lights or {}) do
      flat[#flat + 1] = { x = p.x + item.x, y = p.y or 0, z = p.z + item.z }
    end
  end
  win.groups, win.walls, win.flat = groups, walls, flat
end

local function prepare(ground, view)
  local grid, px, half = ground.grid, ground.chunkPx, ground.half
  if not (grid and px and half and ground.terrain) then window = {} return end
  local cache = perGround[ground]
  if not cache then cache = { lands = {}, resident = 0 } perGround[ground] = cache end

  local reach = reachFor(px)
  local camCx, camCy = floor(view.x / px), floor(view.z / px)
  local qx, qy = floor(view.x * 4 / px), floor(view.z * 4 / px)
  if window.done and window.ground == ground and window.qx == qx and window.qy == qy
     and window.version == Glass.version and window.reach == reach then
    return
  end
  tick = tick + 1

  local want = {}
  local W = Glass.WINDOW
  for cy = camCy - W, camCy + W do
    for cx = camCx - W, camCx + W do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        if land and inReach(view.x, view.z, cx * px + half, cy * px + half, px, reach) then
          local dx, dz = cx - camCx, cy - camCy
          want[#want + 1] = { dx * dx + dz * dz, cx, cy, land }
        end
      end
    end
  end
  table.sort(want, function(a, b) return a[1] < b[1] end)

  local builds, pending, list = 0, 0, {}
  for _, w in ipairs(want) do
    local land = w[4]
    local entry = cache.lands[land]
    if not entry then
      if builds < Glass.BUILDS_PER_FRAME and Budget.allow(false) then
        builds = builds + 1
        local t0 = clock()
        local ok, built = pcall(buildLand, ground, land)
        Budget.charge(t0, "glass")
        if not ok then
          note("build", "a land failed to build and was skipped: %s", tostring(built))
          built = { pieces = {} }
        end
        cache.lands[land] = built
        cache.resident = cache.resident + 1
        entry = built
      else
        pending = pending + 1
      end
    end
    if entry then
      entry.used = tick
      if #entry.pieces > 0 or #(entry.lights or {}) > 0 then
        list[#list + 1] = { entry = entry, x = w[2] * px + half, z = w[3] * px + half }
      end
    end
  end

  -- evict the oldest lands past the cap
  if cache.resident > Glass.MAX_RESIDENT then
    local old = {}
    for land, e in pairs(cache.lands) do
      if e.used ~= tick then old[#old + 1] = { e.used or 0, land, e } end
    end
    table.sort(old, function(a, b) return a[1] < b[1] end)
    local i = 1
    while cache.resident > Glass.MAX_RESIDENT and old[i] do
      release(old[i][3])
      cache.lands[old[i][2]] = nil
      cache.resident = cache.resident - 1
      i = i + 1
    end
  end

  window = { ground = ground, qx = qx, qy = qy, list = list,
             done = (pending == 0), version = Glass.version, reach = reach }
  index(window)
end

-- ------------------------------------------------------------ the lighting --

local glint = { x = nil, z = nil, phase = 0, amp = 0 }

-- A reflection is something the viewpoint does (VoxelScene.glintStep): the
-- phase is fed by the camera's own travel, the strength dies when it stops.
local function glintStep(x, z)
  local dist = 0
  if glint.x then dist = abs(x - glint.x) + abs(z - glint.z) end
  glint.x, glint.z = x, z
  if dist > 64 then dist = 0 end            -- a warp is not travel
  glint.phase = (glint.phase + dist * Glass.GLINT_RATE) % (2 * math.pi)
  if dist > 0.05 then
    glint.amp = min(1, glint.amp + Glass.GLINT_IN)
  else
    glint.amp = max(0, glint.amp - Glass.GLINT_OUT)
  end
end

-- Under the open sky? Gen4Spawn.isOutdoor is the real answer on Platinum
-- (Map.isOutdoor reads Gen 1/2 header fields); `ground.outdoors` is the
-- engine's own reading of the same fact. The answer is a fact about the map, so
-- it is asked twice a second, not every frame.
local outdoorCache = { map = nil, ground = nil, at = -1, value = false }
local OUTDOOR_TTL = 0.5

local function outdoorNow(ground)
  if ground.outdoors == false then return false end
  local map = ground.terrariumMap
  local Spawn = spawn()
  if map and Spawn and Spawn.isOutdoor then
    local c, t = outdoorCache, clock()
    if c.map == map and c.ground == ground and t >= c.at and t - c.at < OUTDOOR_TTL then
      return c.value
    end
    local ok, r = pcall(Spawn.isOutdoor, map)
    if ok then
      c.map, c.ground, c.at, c.value = map, ground, t, (r and true or false)
      return c.value
    end
  end
  return ground.outdoors == true
end

-- The `limit` flames nearest (wx, wz), nearest first, without sorting them all:
-- ids into `flat` and their squared distances, and how many.
local function nearest(flat, wx, wz, limit)
  local ids, d2s, n = {}, {}, 0
  for i = 1, #flat do
    local p = flat[i]
    local dx, dz = p.x - wx, p.z - wz
    local d = dx * dx + dz * dz
    if n < limit or d < d2s[n] then
      local pos = (n < limit) and (n + 1) or n
      while pos > 1 and d2s[pos - 1] > d do
        ids[pos], d2s[pos] = ids[pos - 1], d2s[pos - 1]
        pos = pos - 1
      end
      ids[pos], d2s[pos] = i, d
      if n < limit then n = n + 1 end
    end
  end
  return ids, d2s, n
end

-- -------------------------------------------------------------------- draw --

local dimLamp = { 1, 0.84, 0.5 }          -- reused every frame: the lamp, scaled

function Glass.draw(scene)
  if not (Glass.enabled and DayNight and scene and scene.ground and scene.view) then return end
  local ground, view = scene.ground, scene.view
  if not outdoorNow(ground) then return end

  glintStep(scene.eye[1], scene.eye[3])

  local night = nightNow()
  local wantNight = night > Glass.NIGHT_MIN
  local wantGlint = Glass.DAY_GLINT and glint.amp > Glass.GLINT_MIN
  -- By day nothing is drawn, so by day nothing is built either (see the header).
  if not (wantNight or wantGlint or Glass.BUILD_BY_DAY) then return end

  prepare(ground, view)
  local groups, list = window.groups, window.list
  if not groups or #groups == 0 or not list then return end
  if not (wantNight or wantGlint) then return end

  -- which lands are on screen, once, not once per texture
  local visible = scene.sphereVisible
  local radius = (ground.chunkPx or 512) * 0.72 + 80
  local any = false
  for _, item in ipairs(list) do
    local v = (not visible) or visible(item.x, 0, item.z, radius)
    item.vis = v and true or false
    if v then any = true end
  end
  if not any then return end

  -- the lamp colour the panes are painted with, scaled by PANE_BRIGHTNESS
  local lamp = lampNow()
  local k = Glass.PANE_BRIGHTNESS
  dimLamp[1], dimLamp[2], dimLamp[3] = lamp[1] * k, lamp[2] * k, lamp[3] * k

  local M = mat4()
  Voxel3D.seams(false)
  Voxel3D.glass(true)
  scene.blend()
  if wantNight then
    Voxel3D.flatten(dimLamp, min(1, 0.50 + 0.50 * night))
  end
  local phase, glintAmp = glint.phase, wantGlint and glint.amp or 0
  local nightArg = wantNight and night or 0
  local drawn = 0
  for gi = 1, #groups do
    local g = groups[gi]
    local image = g.entry.image
    local bound = false
    for i = 1, g.n do
      local d = g[i]
      local item = d.item
      if item.vis then
        if not bound then
          -- the glass-only copy is both the texture (non-glass texels are alpha 0
          -- and discarded) and the mask (alpha 1 on every pane texel); sent once
          -- for all the pieces of this texture
          Voxel3D.glassPass(image, nightArg, dimLamp, phase, glintAmp)
          bound = true
        end
        local model = item.model
        if not model then
          model = M.translate(item.x, 0, item.z)
          item.model = model
        end
        Voxel3D.draw(d.mesh, image, model, Glass.PULL, nil, 0, false)
        drawn = drawn + 1
      end
    end
  end
  if wantNight then Voxel3D.flatten(nil) end
  scene.opaque()
  Voxel3D.glassPass(nil)                  -- the blank mask and the scene's own light
  Voxel3D.seams(true)
  Voxel3D.glass(true)

  -- Log once when glass is first drawn
  if drawn > 0 and Glass.LOG then
    note("draw", "drew %d glass piece(s) at night=%.2f", drawn, night)
  end
end

-- Point lights from the glass MASK: each clustered pane, in the same format
-- as StreetLamps.lights(). The shader hangs the flame `lampHeight` above
-- lamp.y, so y is the pane height minus that offset -- otherwise a window
-- would light the sky 19 units above the glass.
function Glass.lights(wx, wz, limit)
  if not (Glass.enabled and DayNight) then return {} end

  local night = nightNow()
  if night <= Glass.NIGHT_MIN then return {} end

  local flat = window.flat
  if not flat or #flat == 0 then return {} end

  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0
  limit = max(1, min(Glass.LIGHT_LIMIT, limit or Glass.LIGHT_LIMIT))
  local flame = Voxel3D.lampHeight or Voxel3D.LAMP_HEIGHT or 19

  local ids, d2s, n = nearest(flat, wx, wz, limit)
  local out = {}
  for i = 1, n do
    local p = flat[ids[i]]
    out[i] = {
      x = p.x,
      y = (p.y or 0) - flame,
      z = p.z,
      radius = Glass.LIGHT_RADIUS,
      power = night * 0.75,
      d2 = d2s[i],
    }
  end
  return out
end

-- Pane + building-wall light sources for Gen4Light (the world-space receiver on
-- Platinum's own roads and walls) and Gen4Tint, nearest first. y is the pane
-- itself; the receiver lights from there, so a window lights the wall around it
-- and the street below it, not the sky above.
--
-- Called by Gen4Bridge AND Gen4Light every frame with the same camera, so the
-- answer is kept until the camera, the hour or the window changes. The returned
-- list is shared: read it, do not edit it.
function Glass.screenLights(wx, wz)
  if not (Glass.enabled and DayNight) then return {} end
  local night = nightNow()
  if night <= Glass.NIGHT_MIN then return {} end
  local flat = window.flat
  if not flat or #flat == 0 then return {} end
  wx, wz = tonumber(wx) or 0, tonumber(wz) or 0

  local c = window.sl
  if c and c.wx == wx and c.wz == wz and c.night == night
     and c.limit == Glass.SCREEN_LIMIT and c.power == Glass.SCREEN_POWER
     and c.radius == Glass.SCREEN_RADIUS then
    return c.out
  end

  local limit = max(1, Glass.SCREEN_LIMIT)
  local ids, d2s, n = nearest(flat, wx, wz, limit)
  local power, radius = night * Glass.SCREEN_POWER, Glass.SCREEN_RADIUS
  local out = {}
  for i = 1, n do
    local p = flat[ids[i]]
    out[i] = { x = p.x, y = p.y or 0, z = p.z, radius = radius, power = power, d2 = d2s[i] }
  end
  window.sl = { wx = wx, wz = wz, night = night, out = out, limit = Glass.SCREEN_LIMIT,
                power = Glass.SCREEN_POWER, radius = Glass.SCREEN_RADIUS }
  return out
end

-- The glass-bearing building meshes of the lands around the camera, with their
-- land origin: { { mesh, x, z }, ... }. Gen4Light draws these (additive, depth
-- tested) so a lit window lights the WALL it is in, not just the pane. Built
-- once per window; shared, so read it, do not edit it.
function Glass.wallPieces()
  return window.walls or {}
end

-- Called from Gen4Bridge before the scene opens, so the first night frame
-- already has pane lights (draw's prepare would otherwise run too late).
function Glass.collectLights(scene)
  if not (scene and scene.ground and scene.view) then return {} end
  if not outdoorNow(scene.ground) then return {} end
  prepare(scene.ground, scene.view)
  return Glass.lights(scene.view.x, scene.view.z)
end

-- Drop every GPU object (graphics reset, mod reload). The decisions about which
-- textures hold glass are facts about the art and survive; the images and the
-- meshes are rebuilt on demand.
function Glass.invalidate()
  for _, cache in pairs(perGround) do
    for _, e in pairs(cache.lands) do release(e) end
  end
  perGround = setmetatable({}, { __mode = "k" })
  for path, entry in pairs(textures) do
    if entry and entry.image and entry.image.release then
      pcall(entry.image.release, entry.image)
    end
    textures[path] = nil
  end
  window = {}
  outdoorCache.map, outdoorCache.ground, outdoorCache.at = nil, nil, -1
  nightAt, lampAt, lampVal = -1, -1, nil
  Glass.version = Glass.version + 1
end

-- Read-only, for the console / a test: the glass texture verdicts so far.
function Glass.report()
  local out = {}
  for path, entry in pairs(textures) do
    if entry then out[#out + 1] = { path = path, w = entry.w, h = entry.h, texels = entry.texels } end
  end
  table.sort(out, function(a, b) return a.path < b.path end)
  return out
end

-- Named for the suite (tools/test_gen4_glass.lua): the pure parts.
Glass._buildSat = buildSat
Glass._boxHasGlass = boxHasGlass
Glass._clusterPoints = clusterPoints
Glass._nearest = nearest
Glass._glassAt = glassAt
Glass._addShape = addShape
Glass._newBucket = newBucket
Glass._analyse = analyse

return Glass
