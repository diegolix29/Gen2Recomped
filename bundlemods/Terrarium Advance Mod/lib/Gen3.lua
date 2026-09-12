-- Minimal Gen 3 voxel support for Terrarium Advance Mod
-- Based on DRAMATIC_SHAPE's comprehensive Gen3.lua but simplified for basic functionality

local V = ...

local Gen3 = {}

-- Constants from DRAMATIC_SHAPE's Gen3.lua
local SHEET_COLS = 16
local CELL = 16          -- a metatile edge, in world pixels
local TILE = 8           -- the mesher's own quad edge
local COURSE = 16        -- one elevation step, in world pixels

-- Elevation constants from DRAMATIC_SHAPE
local ELEV_TRANSITION = 254
local ELEV_MULTI = 255
local ELEV_SURF = 253
local ELEV_DEFAULT = 0
local NEIGHBOURS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }

-- Build elevation ranks function from DRAMATIC_SHAPE
local function buildElevationRanks(cells)
  local seen, list = {}, {}
  for i = 1, #cells do
    local e = cells[i]
    if e and e ~= ELEV_TRANSITION and e ~= ELEV_MULTI and e ~= ELEV_SURF
       and not seen[e] then
      seen[e] = true
      list[#list + 1] = e
    end
  end
  table.sort(list)
  local rank, datum = {}, nil
  for i, e in ipairs(list) do
    rank[e] = i
    if e == ELEV_DEFAULT then datum = i end
  end
  -- No cell on this map is at the default level (an all-terrace interior, or
  -- Pacifidlog, which is water and rafts).  Pin the datum to the LOWEST level
  -- present rather than to nothing, so the map still lands on the world floor.
  if not datum then datum = 1 end
  local height = {}
  for e, i in pairs(rank) do height[e] = (i - datum) * COURSE end
  height[ELEV_SURF] = -COURSE / 8          -- the water class's own recess
  return height, #list
end

Gen3.SHEET_COLS = SHEET_COLS
Gen3.CELL = CELL
Gen3.COURSE = COURSE

-- Engine access functions
local function engineGame()
  local ok, Game = pcall(require, "src.core.Game")
  if ok and type(Game) == "table" and (Game.data or Game.overworld) then
    return Game
  end
  local g = rawget(_G, "Game")
  if type(g) == "table" then return g end
  return (ok and type(Game) == "table") and Game or nil
end

local function engineData()
  local Game = engineGame()
  return Game and Game.data or nil
end

Gen3.engineData = engineData

-- Gen 3 detection
function Gen3.isGen3(tileset)
  if type(tileset) ~= "table" then return false end
  return tonumber(tileset.blockTiles) == 2 and tonumber(tileset.blockCells) == 1
end

function Gen3.mapIsGen3(map)
  return map ~= nil and Gen3.isGen3(map.tileset)
end

-- Improved class determination using gen3_shapes data
local function classFromSpec(spec, behavior, layer)
  if not spec or not spec.behaviors then return nil end
  local entry = spec.behaviors[behavior]
  if not entry then return nil end
  return entry.class
end

-- Synthetic tile ID functions
function Gen3.tileId(metatile, tx, ty)
  return (tonumber(metatile) or 0) * 4 + (ty % 2) * 2 + (tx % 2)
end

function Gen3.tileAt(map, tx, ty)
  if not map then return nil end
  local ts = map.tileset
  if ts and ts.blocks then return map:tileAt(tx, ty) end
  local okB, id = pcall(map.blockAt, map, math.floor(tx / 2), math.floor(ty / 2))
  if not okB or id == nil then return nil end
  return Gen3.tileId(id, tx, ty)
end

function Gen3.metatileOf(tileId)
  return math.floor((tonumber(tileId) or 0) / 4)
end

function Gen3.quadrantOf(tileId)
  return (tonumber(tileId) or 0) % 4
end

function Gen3.tileOrigin(tileId, cols)
  cols = cols or SHEET_COLS
  local id = tonumber(tileId) or 0
  local m, q = math.floor(id / 4), id % 4
  local ax = (m % cols) * CELL + (q % 2) * TILE
  local ay = math.floor(m / cols) * CELL + math.floor(q / 2) * TILE
  return ax, ay
end

function Gen3.tileCount(metatiles)
  return (tonumber(metatiles) or 0) * 4
end

function Gen3.idSpace(tileset, ctx)
  if ctx and (ctx.metatiles or 0) > 0 then return ctx.metatiles end
  local data = engineData()
  local layout = data and data.constants and data.constants.gen3Layout
  local inPrimary = tonumber(layout and layout.metatilesInPrimary) or 512
  local total = tonumber(tileset and tileset.metatileCount) or 0
  return math.max(inPrimary + total, inPrimary * 2)
end

-- Context caching for Gen 3 maps
local ctxCache = setmetatable({}, { __mode = "k" })
local ctxMisses = setmetatable({}, { __mode = "k" })
local CTX_RETRIES = 8

-- Simple Gen 3 context for map
function Gen3.forMap(map)
  if not Gen3.mapIsGen3(map) then return nil end
  local hit = ctxCache[map]
  if hit ~= nil then return hit or nil end

  -- Try to get Gen 3 world from engine
  local Game = engineGame()
  local ow = Game and (Game.overworld or Game.world) or nil
  local world = nil
  if ow and type(ow.gen3WorldFor) == "function" then
    local got, w = pcall(ow.gen3WorldFor, ow, map.def, map, map.tileset)
    if got and type(w) == "table" and w.bottom then
      world = w
    end
  end

  if not world then
    local n = (ctxMisses[map] or 0) + 1
    ctxMisses[map] = n
    if n >= CTX_RETRIES then
      ctxCache[map] = false
      return nil
    end
    return nil
  end
  ctxMisses[map] = nil
  ctxCache[map] = false

  local def = map.def or {}
  local width = tonumber(def.width) or 0
  local height = tonumber(def.height) or 0
  local elevationCells = def.elevationCells
  local collisionCells = def.collisionCells

  -- Build elevation ranks if elevation data exists
  local elevHeight, levels = nil, 0
  if elevationCells then
    elevHeight, levels = buildElevationRanks(elevationCells)
  end

  local ctx = {
    world = world,
    seam = "engine",
    map = map,
    tileset = map.tileset,
    cols = world.cols or SHEET_COLS,
    cell = CELL,
    metatiles = world.metatiles or 0,
    width = width,
    height = height,
    elevationCells = elevationCells,
    collisionCells = collisionCells,
    elevHeight = elevHeight,
    levels = levels,
    spec = nil,
    attrCache = {},
    classCache = {},
  }

  -- Load gen3_metatiles data for advanced role classification
  local roles = nil
  do
    local okR, t = pcall(V.data, "gen3_metatiles")
    if okR and type(t) == "table" then roles = t.roles end
  end
  local ts = map.tileset
  local key = (type(ts) == "table" and tostring(ts.id or ""))
              or (type(ts) == "string" and ts) or ""
  if key == "" and type(map.def) == "table" then
    key = tostring(map.def.tileset or "")
  end
  local p1, s1 = key:match("TILESET_(%x+)_(%x+)")
  if not p1 and type(ts) == "table" then
    p1 = tostring(ts.primaryKey or ""):match("TILESET_(%x+)")
    s1 = tostring(ts.secondaryKey or ""):match("TILESET_(%x+)")
  end
  if not p1 then p1 = key:match("TILESET_(%x+)") end
  ctx.ownerPrimary = p1 and ("P" .. p1) or nil
  ctx.ownerSecondary = s1 and ("S" .. s1) or nil

  local roleMemo = {}

  function ctx.metaRole(m)
    if not roles or not m then return nil end
    local owner = (m < 512) and ctx.ownerPrimary or ctx.ownerSecondary
    local t = owner and roles[owner]
    local r = t and t[m]
    if not r then return nil end
    return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
  end

  -- Basic context functions
  function ctx.indexOf(cx, cy)
    if width <= 0 or height <= 0 then return nil end
    if cx < 0 or cy < 0 or cx >= width or cy >= height then return nil end
    return cy * width + cx + 1
  end

  function ctx.metatileAt(cx, cy)
    if cx < 0 or cy < 0 or cx >= width or cy >= height then
      -- Border handling could be added here
      return nil
    end
    if type(map.blockAt) ~= "function" then return nil end
    local ok, id = pcall(map.blockAt, map, cx, cy)
    if not ok then return nil end
    return id
  end

  function ctx.attributes(metatile)
    local m = tonumber(metatile) or 0
    local c = ctx.attrCache[m]
    if c then return c[1], c[2] end
    local b, l = 0, 0
    if type(world.attributes) == "function" then
      b, l = world.attributes(m)
    end
    ctx.attrCache[m] = { b or 0, l or 0 }
    return b or 0, l or 0
  end

  function ctx.coverAt(metatile)
    if type(world.topIsAbovePlayer) == "function" then
      return world.topIsAbovePlayer(metatile) and true or false
    end
    local _, layer = ctx.attributes(metatile)
    return layer ~= 1
  end

  function ctx.offMap(cx, cy)
    return cx < 0 or cy < 0 or cx >= width or cy >= height
  end

  function ctx.blockedAt(cx, cy)
    if not collisionCells then return false end
    local i = ctx.indexOf(cx, cy)
    if not i then return true end
    return (collisionCells[i] or 0) ~= 0
  end

  function ctx.elevationAt(cx, cy)
    if not elevationCells then return nil end
    local i = ctx.indexOf(cx, cy)
    return i and elevationCells[i] or nil
  end

  -- Simple ground height (can be expanded)
  function ctx.groundHeight(cx, cy)
    if not elevHeight then return 0 end
    local e = ctx.elevationAt(cx, cy)
    if e == nil then return 0 end
    -- Match DRAMATIC_SHAPE's elevation handling
    local ELEV_TRANSITION, ELEV_SURF, ELEV_DEFAULT, ELEV_MULTI = 0, 1, 3, 15
    if e == ELEV_TRANSITION then
      -- For transition cells, use 0 as base height
      return 0
    elseif e == ELEV_SURF then
      -- For surf cells, below datum
      return -COURSE
    elseif e == ELEV_MULTI then
      -- For bridge/multi cells, base height plus lift
      return COURSE
    else
      -- For regular elevation cells, use the rank
      local rank = ctx.levels and ctx.levels[e]
      if rank then
        return rank * COURSE
      end
      return 0
    end
  end

  -- Simple class determination (can be expanded)
  function ctx.classAt(cx, cy, metatile)
    local m = metatile
    if m == nil then m = ctx.metatileAt(cx, cy) end
    if m == nil then return nil end
    local blocked = ctx.blockedAt(cx, cy)
    if not blocked then
      return "floor"
    end
    return "wall"
  end

  ctxCache[map] = ctx
  return ctx
end

-- Placeholder for analysis function (can be expanded)
-- Based on DRAMATIC_SHAPE's Gen3.analyse but simplified
local artCache = setmetatable({}, { __mode = "k" })
local tilesCache = setmetatable({}, { __mode = "k" })
local function colourKey(r, g, b)
  return math.floor(r / 32) * 100 + math.floor(g / 32) * 10 + math.floor(b / 32)
end

local function tilesForTileset(tileset)
  local key = tostring(tileset.id)
  local hit = tilesCache[key]
  if hit ~= nil then return hit or nil end
  tilesCache[key] = false

  local data = engineData()
  local store = data and data.map_tilesets
  local primary = store and store[tileset.primaryKey]
  if not primary then return nil end

  local okMod, Gen3Tiles = pcall(require, "src.render.Gen3Tiles")
  if not (okMod and Gen3Tiles) then return nil end

  local layout = data and data.constants and data.constants.gen3Layout
  local okNew, tiles = pcall(Gen3Tiles.new, {
    primary = primary,
    secondary = tileset.secondaryKey and store[tileset.secondaryKey] or nil,
  }, layout)
  if not (okNew and tiles) then return nil end

  tilesCache[key] = tiles
  return tiles
end

function Gen3.analyse(tileset)
  local key = tostring(tileset.id)
  local hit = artCache[key]
  if hit ~= nil then return hit or nil end
  artCache[key] = false

  local tiles = tilesForTileset(tileset)
  if not tiles then return nil end

  local stats = {}
  local function rec(m)
    local s = stats[m]
    if not s then
      s = { n1 = 0, n2 = 0, solidN = 0, r = 0, g = 0, b = 0,
            leaf = 0, warm = 0, dark = 0, bright = 0,
            top2 = 0, bot2 = 0, topSolid = 0, botSolid = 0, rows2 = {} }
      stats[m] = s
    end
    return s
  end

  local function metaAt(x, y)
    return math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
  end

  -- Simple analysis: count pixels and estimate properties
  local objectHist = {}
  local okTop = pcall(tiles.bakeLayer, tiles, 2, function(x, y, r, g, b)
    local s = rec(metaAt(x, y))
    s.n2 = s.n2 + 1
    local row = y % CELL
    if row < 8 then s.top2 = s.top2 + 1 else s.bot2 = s.bot2 + 1 end
    s.rows2[row] = (s.rows2[row] or 0) + 1
    local c = colourKey(r, g, b)
    objectHist[c] = (objectHist[c] or 0) + 1
    -- Simple leaf detection: green dominant
    if g > r * 1.5 and g > b * 1.5 then
      s.leaf = s.leaf + 1
    end
  end)

  if not okTop then return nil end

  local groundHist = {}
  local okBottom = pcall(tiles.bakeLayer, tiles, 1, function(x, y, r, g, b)
    local s = rec(metaAt(x, y))
    s.n1 = s.n1 + 1
    local c = colourKey(r, g, b)
    groundHist[c] = (groundHist[c] or 0) + 1
  end)

  if not okBottom then return nil end

  -- Determine background color: a colour common enough among ground
  -- samples to be the tileset's own floor art. (`#groundHist` here would be
  -- Lua's length operator on a hash table keyed by arbitrary colour-bucket
  -- numbers, not a 1..n sequence -- an unreliable border, not a count --
  -- so the threshold is taken against the real total instead.)
  local background = {}
  local groundTotal = 0
  for _, n in pairs(groundHist) do groundTotal = groundTotal + n end
  if groundTotal > 0 then
    for c, n in pairs(groundHist) do
      if n >= groundTotal * 0.01 then
        background[c] = true
      end
    end
  end

  -- Mark leafy tiles
  for m, s in pairs(stats) do
    if s.leaf > s.n2 * 0.3 then
      s.leafy = true
    end
  end

  local backgroundColours = 0
  for _ in pairs(background) do backgroundColours = backgroundColours + 1 end

  local art = {
    stats = stats,
    background = background,
    backgroundColours = backgroundColours,
    groundSamples = groundTotal
  }

  artCache[key] = art
  return art
end

-- Load Gen 3 data files
Gen3.spec = function()
  local ok, s = pcall(V.data, "gen3_shapes")
  if ok and type(s) == "table" then return s end
  return nil
end

-- Status function for debugging
function Gen3.status(map)
  if not Gen3.mapIsGen3(map) then return "not a Gen 3 map" end
  local ctx = Gen3.forMap(map)
  if not ctx then return "no Gen 3 context" end
  return "ok"
end

-- Placeholder for solid measurement (can be expanded)
function Gen3.solidForMap(map, metatile)
  return nil
end

-- Art, material, cap, face, kind, motif for one metatile, or nil.
-- Delegates to the context's metaRole function if available
function Gen3.metaRole(map, metatile)
  local ctx = Gen3.forMap(map)
  if not (ctx and ctx.metaRole) then return nil end
  local ok, a, b, c, d, e, f = pcall(ctx.metaRole, metatile)
  if not ok then return nil end
  return a, b, c, d, e, f
end

-- The art record for one metatile: `{ leafy, overhead, warmth, darkness,
-- mr, mg, mb, n1, n2, top2, bot2, solid }`, or nil when the pair has no
-- pixels to read (a headless host, a bake that failed).
function Gen3.artOf(tileset, metatile)
  local art = Gen3.analyse(tileset)
  if not art then return nil end
  return art.stats[tonumber(metatile) or -1]
end

local LINEAR_COLS = 16          -- tiles per row, matching `tilesPerRow or 16`
local atlasInfoCache = setmetatable({}, { __mode = "k" })

function Gen3.atlasInfoFor(tileset)
  local key = tostring(tileset.id)
  local hit = atlasInfoCache[key]
  if hit then return hit end
  local ids = Gen3.idSpace(tileset, nil)
  local tiles = ids * 4
  local rows = math.ceil(tiles / LINEAR_COLS)
  local info = { perRow = LINEAR_COLS, width = LINEAR_COLS * 8,
                 height = math.max(8, rows * 8), tiles = tiles, metatiles = ids }
  atlasInfoCache[key] = info
  return info
end

function Gen3.atlasInfo(ctx)
  return Gen3.atlasInfoFor(ctx.tileset)
end

-- Tell the tileset record what its atlas looks like, so every reader that asks
-- `tileset.tilesPerRow / imageWidth / imageHeight` -- which is all of them --
-- gets the truth instead of the Gen 1 fallbacks (16 / 128 / 48). Set once, and
-- only fields a Gen 3 pair does not otherwise carry: the engine's own Gen 3
-- path draws from `gen3SheetsFor` and reads none of these.
function Gen3.describe(tileset)
  local info = Gen3.atlasInfoFor(tileset)
  if tileset.tilesPerRow == nil then tileset.tilesPerRow = info.perRow end
  if tileset.imageWidth == nil then tileset.imageWidth = info.width end
  if tileset.imageHeight == nil then tileset.imageHeight = info.height end
  return info
end

-- ---------------------------------------------------------------------------
-- THE TEXTURE.
--
-- Re-lay the engine's two baked metatile sheets (16x16-pixel cells, "two
-- 256x656 sheets" per the engine's own log) as one ordinary 8x8-tile sheet,
-- in the same synthetic order Gen3.tileId already uses (4*metatile+quadrant)
-- and Gen3.describe already reports (LINEAR_COLS tiles per row). Two
-- consumers need exactly this image, and neither had it:
--
-- 1. TerrainAtlas.forMap binds it as the terrain's texture. Without it, the
--    only thing TerrainAtlas otherwise has to hand back -- `map.renderer
--    .image` -- is nil for every Gen 3 pair (a pair has no flat-game sheet
--    on disk to be one), so TerrainAtlas.forMap returns nil, the mesh binds
--    no texture, and the world meshes with real geometry but nothing
--    painted on it: a blank, grey, placeholder-looking ground.
--
-- 2. Structures' local `pixels(tileset)` needs the same pixels to carve
--    real shapes -- tree hulls, roofs, fences -- out of the art instead of
--    falling back to a plain measured box for everything it can't read,
--    which is the "everything is a placeholder box" half of the same bug.
--
-- Baked once per tileset and cached; both consumers share the one image.
-- ---------------------------------------------------------------------------
local atlasCache = setmetatable({}, { __mode = "k" })
local atlasDataCache = setmetatable({}, { __mode = "k" })

local function bakeLinear(tileset)
  local key = tostring(tileset.id)
  local tiles = tilesForTileset(tileset)
  if not tiles then return nil end
  if not (love and love.image and love.image.newImageData
          and love.graphics and love.graphics.newImage) then
    return nil
  end
  local info = Gen3.describe(tileset)
  local W, H = info.width, info.height
  local srcCols = SHEET_COLS

  -- On the CPU with ImageData:setPixel, not through a canvas draw: this
  -- can run from inside an already-active scene/shader (TerrainAtlas is
  -- called mid-frame), and compositing through that live pipeline yields a
  -- texture that reports success but renders solid black.
  local okBake, res = pcall(function()
    local surface = love.image.newImageData(W, H)
    local function plot(x, y, r, g, b)
      -- metatile-sheet coordinates in; synthetic tile-sheet coordinates out
      local m = math.floor(y / CELL) * srcCols + math.floor(x / CELL)
      local q = math.floor((y % CELL) / TILE) * 2 + math.floor((x % CELL) / TILE)
      local t = m * 4 + q
      local dx = (t % LINEAR_COLS) * TILE + (x % TILE)
      local dy = math.floor(t / LINEAR_COLS) * TILE + (y % TILE)
      if dx >= 0 and dy >= 0 and dx < W and dy < H then
        surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
      end
    end
    tiles:bakeLayer(1, plot)
    tiles:bakeLayer(2, plot)
    local img = love.graphics.newImage(surface)
    pcall(img.setFilter, img, "nearest", "nearest")
    return { image = img, data = surface }
  end)
  if not (okBake and res) then
    atlasCache[key] = false
    atlasDataCache[key] = false
    return nil
  end
  atlasCache[key] = res.image
  atlasDataCache[key] = res.data
  return res
end

local function ensureAtlas(tileset)
  local key = tostring(tileset.id)
  if atlasCache[key] ~= nil then
    return atlasCache[key] or nil, atlasDataCache[key] or nil
  end
  local res = bakeLinear(tileset)
  return res and res.image or nil, res and res.data or nil
end

-- The re-laid image itself: what TerrainAtlas binds as the terrain texture.
function Gen3.atlasForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local img = ensureAtlas(tileset)
  return img
end

-- The same bake's raw pixels: what Structures' shape passes carve from.
function Gen3.atlasDataForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local _, data = ensureAtlas(tileset)
  return data
end

function Gen3.atlas(map)
  if not Gen3.mapIsGen3(map) then return nil end
  return Gen3.atlasForTileset(map.tileset)
end

function Gen3.atlasData(map)
  if not Gen3.mapIsGen3(map) then return nil end
  return Gen3.atlasDataForTileset(map.tileset)
end

-- ---------------------------------------------------------------------------
-- THE SHAPE SURFACE: the same sheet, with the ground cut out of it.
--
-- The plain atlas above is fully opaque -- Emerald's art has no
-- transparency at the composite, because the bottom layer always paints
-- some ground under whatever stands on it. Handing THAT to Structures'
-- alpha-based carving (every pass finds background by testing `a == 0`)
-- gets back a solid rectangle every time: houses and trees stay boxes,
-- just boxes with real pixels now instead of none. Unlocking the pixels is
-- necessary and not sufficient.
--
-- So this is a second bake of the exact same sheet, in the exact same
-- layout, except that a ground-coloured pixel (Gen3.analyse's own
-- `background` set) is written fully transparent instead of opaque. That
-- is what gives a roof an outline and a tree a silhouette to carve.
local shapeCache = setmetatable({}, { __mode = "k" })

local function bakeShape(tileset)
  local key = tostring(tileset.id)
  local art = Gen3.analyse(tileset)
  local tiles = art and tilesForTileset(tileset)
  if not (art and tiles) then
    shapeCache[key] = false
    return nil
  end
  if not (love and love.image and love.image.newImageData) then return nil end

  local info = Gen3.describe(tileset)
  local W, H = info.width, info.height
  local background = art.background or {}

  local okBake, res = pcall(function()
    local surface = love.image.newImageData(W, H)
    local function place(x, y)
      local m = math.floor(y / CELL) * SHEET_COLS + math.floor(x / CELL)
      local q = math.floor((y % CELL) / TILE) * 2 + math.floor((x % CELL) / TILE)
      local t = m * 4 + q
      return (t % LINEAR_COLS) * TILE + (x % TILE),
             math.floor(t / LINEAR_COLS) * TILE + (y % TILE)
    end
    -- bottom layer: ground colours become holes, everything else is body
    tiles:bakeLayer(1, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      if background[colourKey(r, g, b)] then
        surface:setPixel(dx, dy, 0, 0, 0, 0)
      else
        surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
      end
    end)
    -- top layer: object art, always body, drawn over whatever is beneath
    tiles:bakeLayer(2, function(x, y, r, g, b)
      local dx, dy = place(x, y)
      if dx < 0 or dy < 0 or dx >= W or dy >= H then return end
      surface:setPixel(dx, dy, r / 255, g / 255, b / 255, 1)
    end)
    return surface
  end)
  if not (okBake and res) then
    shapeCache[key] = false
    return nil
  end
  shapeCache[key] = res
  return res
end

-- The pixels the shape passes read: opaque where the art is an object,
-- transparent where it is ground. This is what Structures' local
-- `pixels(tileset)` answers with on Gen 3.
function Gen3.shapeDataForTileset(tileset)
  if not Gen3.isGen3(tileset) then return nil end
  local key = tostring(tileset.id)
  local hit = shapeCache[key]
  if hit ~= nil then return hit or nil end
  return bakeShape(tileset)
end

-- The pair-level carve is what this answers with -- NOT the further
-- per-map refinement dramatic_mod adds (widening the background set with
-- an indoor room's own floor colours, for a floor pattern the pair-level
-- guess misses). That needs `ctx.floorMetatiles`, which this mod's
-- `Gen3.forMap` does not compute; every indoor Gen 3 room is carved from
-- the pair's own background guess only, which is right outdoors and for
-- most interiors, and merely unrefined for the rest.
function Gen3.shapeDataForMap(map)
  if not Gen3.mapIsGen3(map) then return nil end
  return Gen3.shapeDataForTileset(map.tileset)
end

function Gen3.releaseAtlases()
  atlasCache = setmetatable({}, { __mode = "k" })
  atlasDataCache = setmetatable({}, { __mode = "k" })
  shapeCache = setmetatable({}, { __mode = "k" })
end

-- Add waterRocks detection for Gen 3 maps (from DRAMATIC_SHAPE)
-- This detects rocks standing in water that should be rendered as 3D structures
local originalForMap = Gen3.forMap
Gen3.forMap = function(map)
  local ctx = originalForMap(map)
  if not ctx then return ctx end
  
  -- Only add waterRocks detection if not already present
  if ctx.waterRocks then return ctx end
  
  -- Get behaviour names from spec if available
  local spec = Gen3.spec()
  local behaviourNames = (spec or {}).behaviour or {}
  
  -- Get art analysis
  local art = Gen3.analyse(map.tileset)
  local stats = art and art.stats or {}
  
  local width = ctx.width or 0
  local height = ctx.height or 0
  
  -- Helper functions for water/rock detection
  local function idx(cx, cy)
    return cy * width + cx + 1
  end
  
  local function waterCell(cx, cy)
    if cx < 0 or cy < 0 or cx >= width or cy >= height then return true end
    local m = ctx.metatileAt(cx, cy)
    if m == nil then return false end
    local b, _ = ctx.attributes(m)
    return behaviourNames[b] == "water"
  end
  
  local function rockCell(cx, cy)
    if cx < 0 or cy < 0 or cx >= width or cy >= height then return false end
    if not ctx.blockedAt(cx, cy) then return false end
    local m = ctx.metatileAt(cx, cy)
    if m == nil then return false end
    local b, _ = ctx.attributes(m)
    local bn = behaviourNames[b]
    -- Check if it's a ground-like behaviour
    if bn ~= nil and bn ~= "ground" and bn ~= "grass" then return false end
    local st = stats[m]
    -- Check if it's solid and not foliage
    return (st and st.solid and st.solid > 0.4 and not st.leafy and not st.overhead) or false
  end
  
  -- Detect water rocks and scenery (trees, bushes, boulders)
  ctx.waterRocks = {}
  ctx.scenery = {}
  ctx.sceneryScale = {}
  
  if ctx.outdoor then
    local scenery = {}
    local claimed = {}
    
    -- First detect water rocks
    for cy = 0, height - 2 do
      for cx = 0, width - 2 do
        if rockCell(cx, cy) and rockCell(cx + 1, cy)
           and rockCell(cx, cy + 1) and rockCell(cx + 1, cy + 1)
           and not scenery[idx(cx, cy)] then
          -- Check if surrounded mostly by water
          local ringed, sea = true, 0
          for _, d in ipairs({ { -1, -1 }, { 0, -1 }, { 1, -1 }, { 2, -1 },
                               { -1, 0 }, { 2, 0 }, { -1, 1 }, { 2, 1 },
                               { -1, 2 }, { 0, 2 }, { 1, 2 }, { 2, 2 } }) do
            local nx, ny = cx + d[1], cy + d[2]
            if waterCell(nx, ny) then
              sea = sea + 1
            elseif not rockCell(nx, ny) then
              ringed = false
              break
            end
          end
          if sea < 7 then ringed = false end
          if ringed then
            for dy = 0, 1 do
              for dx = 0, 1 do
                scenery[idx(cx + dx, cy + dy)] = "water"
              end
            end
            ctx.waterRocks[#ctx.waterRocks + 1] = { cx, cy }
          end
        end
      end
    end
    
    -- Then detect trees and other scenery (simplified version from DRAMATIC_SHAPE)
    for cy = 0, height - 2 do
      for cx = 0, width - 2 do
        local i = idx(cx, cy)
        if not claimed[i] then
          local mA = ctx.metatileAt(cx, cy)
          local mB = ctx.metatileAt(cx + 1, cy)
          local mC = ctx.metatileAt(cx, cy + 1)
          local mD = ctx.metatileAt(cx + 1, cy + 1)
          
          -- Check if this is a 2x2 tree pattern
          local isTree = false
          if mA and mB and mC and mD then
            local stA = stats[mA]
            local stB = stats[mB]
            local stC = stats[mC]
            local stD = stats[mD]
            
            -- Check if all are leafy and solid
            if stA and stB and stC and stD then
              if stA.leafy and stB.leafy and stC.leafy and stD.leafy and
                 stA.solid > 0.5 and stB.solid > 0.5 and 
                 stC.solid > 0.5 and stD.solid > 0.5 then
                -- Check if they're different metatiles (indicating a tree pattern)
                if mA ~= mB and mA ~= mC and mA ~= mD then
                  isTree = true
                end
              end
            end
          end
          
          if isTree then
            claimed[i] = true
            claimed[idx(cx + 1, cy)] = true
            claimed[idx(cx, cy + 1)] = true
            claimed[idx(cx + 1, cy + 1)] = true
            scenery[i] = "canopy"
            scenery[idx(cx + 1, cy)] = "cylinder"
            scenery[idx(cx, cy + 1)] = "cylinder"
            scenery[idx(cx + 1, cy + 1)] = "cylinder"
            ctx.sceneryScale[i] = 2
          end
        end
      end
    end
    
    ctx.scenery = scenery
  end
  
  -- Add scenerySpan function for Structures.lua to query tree sizes
  function ctx.scenerySpan(cx, cy)
    local i = idx(cx, cy)
    if ctx.sceneryScale and ctx.sceneryScale[i] then
      return ctx.sceneryScale[i]
    end
    return 2  -- default to 2x2 for trees
  end
  
  return ctx
end

return Gen3
