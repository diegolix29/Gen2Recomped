-- Voxel world mode: per-tile-id texture overrides for the Gen 1-2 atlases.
--
-- Voxel terrain samples ONE atlas image per map, addressed by tile id (an 8x8
-- slot at ((id % perRow) * 8, floor(id / perRow) * 8) -- see ChunkMesher's
-- tileOrigin).  So "tile id N should wear another PNG" is a statement about
-- slot N of that atlas, and this module is the half of it that knows WHICH
-- slots and WHAT pixels.  TerrainAtlas does the other half: it copies the
-- atlas, calls stamp() on the copy, and hands the copy to the mesh -- the
-- engine's own atlas (which the 2D view still draws from) is never touched.
--
-- Config lives in data/tile_overrides.lua, keyed by tileset id (the same keys
-- data/voxel_heights.lua uses: OVERWORLD, TilesetJohto, ...).  The key "*" is
-- the entry for every tileset that has none of its own.  Per tileset:
--
--   tiles  = { [0x05] = "sand.png" }       explicit id -> file
--   random = { seed = 1, ids = { 5, 6 },   ids that get a seeded-random pick
--              pool = { "grass.png" } }    from the pool (default: top-level pool)
--
-- Explicit `tiles` win over `random`.  Files are looked up under `dir`
-- (default assets/ground/grass/) in the mod root.
--
-- ID OVERLAY (`idOverlay`): stamps EVERY tile slot of the atlas with its own id
-- as two hex digits on an id-coloured square, so the number you need is simply
-- readable off the voxel world -- cliff faces, mountains, roofs, everything --
-- instead of guessed.  `idOverlay = true` covers every Gen 1-2 tileset, or give
-- a list of tileset ids.  Explicit `tiles` / `random` picks still win.  Ids at
-- 256 and up show their low byte.
--
-- THE PICTURE IS SHRUNK TO 8x8.  The atlas slot is 8x8 texels, so a 500px
-- photo-texture is box-averaged down to one tile.  It reads as the texture's
-- colour and rough pattern, which is what an id test needs; real detail would
-- take a bigger atlas (and UV maths that follows it), which this does not do.
--
-- Alpha: a texel that is not fully opaque is composited OVER the slot's
-- original art, so a cut-out texture keeps the tile showing through.
--
-- Everything here is defensive on purpose: a missing file, a bad config or a
-- machine with no pixel access costs the override and nothing else -- the map
-- draws with its normal atlas.

local V = ...

local Assets = require("src.render.Assets")

local TileOverrides = {}

local DEFAULT_DIR = "assets/ground/grass/"
local TILE = 8

local config = nil          -- the parsed data file | false (unusable) | nil (not read)
local plans = {}            -- tileset key -> plan | false (nothing to do)
local tiles8 = {}           -- file -> 8x8 ImageData | false (unreadable)
local logged = {}

local function log(key, fmt, ...)
  if logged[key] then return end
  logged[key] = true
  local ok, msg = pcall(string.format, fmt, ...)
  msg = ok and msg or fmt
  if V and V.mod and V.mod.log and V.mod.log.info then
    pcall(V.mod.log.info, V.mod.log, "TileOverrides: " .. msg)
  end
end

-- ------------------------------------------------------------ id overlay --

local FONT = {   -- 3x5 hex digits, one string per row, top to bottom
  ["0"] = { "111", "101", "101", "101", "111" },
  ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" },
  ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" },
  ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" },
  ["7"] = { "111", "001", "001", "010", "010" },
  ["8"] = { "111", "101", "111", "101", "111" },
  ["9"] = { "111", "101", "111", "001", "111" },
  ["A"] = { "010", "101", "111", "101", "101" },
  ["B"] = { "110", "101", "110", "101", "110" },
  ["C"] = { "011", "100", "100", "100", "011" },
  ["D"] = { "110", "101", "101", "101", "110" },
  ["E"] = { "111", "100", "110", "100", "111" },
  ["F"] = { "111", "100", "110", "100", "100" },
}

local function hsv(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v end
  return v, p, q
end

local idTiles = {}      -- id -> 8x8 ImageData

-- One tile: the id's low byte as two hex digits, black on a colour that
-- differs from its neighbours' (so a wall of different ids reads as different
-- blocks even before the numbers are legible).
local function idTile(id)
  local hit = idTiles[id]
  if hit then return hit end
  local out = love.image.newImageData(TILE, TILE)
  local br, bg, bb = hsv(((id * 47) % 360) / 360, id >= 256 and 0.25 or 0.55, 0.95)
  for y = 0, TILE - 1 do
    for x = 0, TILE - 1 do out:setPixel(x, y, br, bg, bb, 1) end
  end
  local hex = string.format("%02X", id % 256)
  for n = 1, 2 do
    local glyph = FONT[hex:sub(n, n)]
    local ox = (n - 1) * 4        -- digit 1 at x 0-2, digit 2 at x 4-6
    for gy = 1, 5 do
      for gx = 1, 3 do
        if glyph[gy]:sub(gx, gx) == "1" then
          out:setPixel(ox + gx - 1, gy, 0, 0, 0, 1)
        end
      end
    end
  end
  idTiles[id] = out
  return out
end

-- ---------------------------------------------------------------- config --

-- Read fresh off the mod (not through V.data's permanent cache) so that the
-- engine's hot-reload flush, which empties our caches below, also picks up an
-- edited data file.
local function loadConfig()
  if config ~= nil then return config or nil end
  config = false
  local source = nil
  if V and V.mod and V.mod.read then
    local ok, text = pcall(V.mod.read, V.mod, "data/tile_overrides.lua")
    if ok and type(text) == "string" and #text > 0 then source = text end
  end
  local value = nil
  if source then
    local chunk, err = load(source, "@data/tile_overrides.lua")
    if not chunk then
      log("cfg-compile", "data/tile_overrides.lua did not compile: %s", tostring(err))
      return nil
    end
    local ok, result = pcall(chunk, V)
    if ok and type(result) == "table" then value = result
    else log("cfg-run", "data/tile_overrides.lua failed: %s", tostring(result)) end
  elseif V and V.data then
    local ok, result = pcall(V.data, "tile_overrides")
    if ok and type(result) == "table" then value = result end
  end
  if type(value) ~= "table" or value.enabled == false then return nil end
  config = value
  return config
end

-- A deterministic generator of our own.  math.random's sequence differs
-- between Lua builds and anything else that seeds it would reshuffle the
-- test; a fixed LCG (exact in a double: 2^32 * 1664525 < 2^53) means the same
-- seed picks the same textures everywhere.
local function newRng(seed)
  local s = math.floor(tonumber(seed) or 1) % 4294967296
  return function(n)
    s = (s * 1664525 + 1013904223) % 4294967296
    return math.floor(s / 4294967296 * n) + 1      -- 1..n
  end
end

-- id -> file for one tileset: the random picks first, then the explicit pins
-- on top.
local function resolveFiles(cfg, spec)
  local out = {}
  local rnd = type(spec.random) == "table" and spec.random or nil
  if rnd and type(rnd.ids) == "table" then
    local pool = rnd.pool or cfg.pool
    if type(pool) == "table" and #pool > 0 then
      local pick = newRng(rnd.seed)
      -- shuffle a copy so ids get DIFFERENT textures until the pool runs out
      local deck = {}
      for i, f in ipairs(pool) do deck[i] = f end
      for i = #deck, 2, -1 do
        local j = pick(i)
        deck[i], deck[j] = deck[j], deck[i]
      end
      for n, id in ipairs(rnd.ids) do
        out[id] = deck[(n - 1) % #deck + 1]
      end
    end
  end
  if type(spec.tiles) == "table" then
    for id, file in pairs(spec.tiles) do
      if type(id) == "number" and type(file) == "string" then out[id] = file end
    end
  end
  return out
end

-- ---------------------------------------------------------------- pixels --

-- A file's pixels boiled down to one 8x8 tile: premultiplied box average, so a
-- half-transparent texel does not drag the colour toward black.
local function shrinkTo8(src)
  local w, h = src:getDimensions()
  if w < 1 or h < 1 then return nil end
  local out = love.image.newImageData(TILE, TILE)
  for ty = 0, TILE - 1 do
    local y0 = math.floor(ty * h / TILE)
    local y1 = math.max(y0 + 1, math.floor((ty + 1) * h / TILE))
    local ystep = math.max(1, math.floor((y1 - y0) / 16))
    for tx = 0, TILE - 1 do
      local x0 = math.floor(tx * w / TILE)
      local x1 = math.max(x0 + 1, math.floor((tx + 1) * w / TILE))
      local xstep = math.max(1, math.floor((x1 - x0) / 16))
      local r, g, b, a, n = 0, 0, 0, 0, 0
      for y = y0, y1 - 1, ystep do
        for x = x0, x1 - 1, xstep do
          local pr, pg, pb, pa = src:getPixel(x, y)
          r = r + pr * pa
          g = g + pg * pa
          b = b + pb * pa
          a = a + pa
          n = n + 1
        end
      end
      if a > 0 then
        out:setPixel(tx, ty, r / a, g / a, b / a, a / n)
      else
        out:setPixel(tx, ty, 0, 0, 0, 0)
      end
    end
  end
  return out
end

local function tileFor(dir, file)
  local hit = tiles8[file]
  if hit ~= nil then return hit or nil end
  tiles8[file] = false
  if not (love and love.image and love.image.newImageData) then return nil end
  local path = tostring((V and V.path) or "") .. "/" .. dir .. file
  local okE, exists = pcall(Assets.exists, path)
  if not (okE and exists) then
    log("miss:" .. file, "no %s%s -- tiles that name it keep their own art", dir, file)
    return nil
  end
  local ok, tile = pcall(function()
    return shrinkTo8(Assets.imageData(path))
  end)
  if not (ok and tile) then
    log("bad:" .. file, "%s%s could not be read (%s)", dir, file, tostring(tile))
    return nil
  end
  tiles8[file] = tile
  return tile
end

-- ------------------------------------------------------------------- API --

local function overlayOn(cfg, spec, id)
  if type(spec) == "table" and spec.overlay ~= nil then return spec.overlay == true end
  local o = cfg and cfg.idOverlay
  if o == true then return true end
  if type(o) == "table" then
    for k, v in pairs(o) do
      if v == id or (k == id and v == true) then return true end
    end
  end
  return false
end

-- Say, once per tileset, which key the config needs and how big its atlas is.
-- The ids in data/tile_overrides.lua are per tileset, so "which tileset is
-- this map?" has to be answerable from the log.
function TileOverrides.noteTileset(tileset, mapId, atlas)
  local id = tileset and tileset.id
  if id == nil or logged["seen:" .. tostring(id)] then return end
  local w, h = 0, 0
  if atlas and atlas.getDimensions then
    local ok, aw, ah = pcall(atlas.getDimensions, atlas)
    if ok then w, h = aw or 0, ah or 0 end
  end
  log("seen:" .. tostring(id), "tileset %s seen on map %s (atlas %dx%d, %s tiles per row)",
      tostring(id), tostring(mapId), w, h, tostring(tileset.tilesPerRow or 16))
end

-- The overrides for one tileset: { tiles = { [id] = 8x8 ImageData },
-- overlay = bool, key = s }, or nil when the tileset has none.  `key` changes
-- whenever the resolved set does, so a caller can cache a stamped atlas
-- against it.
function TileOverrides.planFor(tileset)
  local id = tileset and tileset.id
  if id == nil then return nil end
  id = tostring(id)
  local hit = plans[id]
  if hit ~= nil then return hit or nil end
  plans[id] = false

  local cfg = loadConfig()
  if not cfg then return nil end
  -- a tileset's own entry, else the ["*"] entry that covers every tileset
  local specs = type(cfg.tilesets) == "table" and cfg.tilesets or nil
  local spec = specs and (specs[id] or specs["*"]) or nil
  if type(spec) ~= "table" then spec = nil end
  local overlay = overlayOn(cfg, spec, id)
  if not spec and not overlay then
    log("none:" .. id, "tileset %s has no entry under `tilesets` (add one, or use [\"*\"] to cover every tileset)", id)
    return nil
  end

  local dir = cfg.dir or DEFAULT_DIR
  if dir:sub(-1) ~= "/" then dir = dir .. "/" end

  local files = spec and resolveFiles(cfg, spec) or {}
  local ids = {}
  for tile in pairs(files) do ids[#ids + 1] = tile end
  table.sort(ids)

  local plan = { tiles = {}, key = "", files = {}, overlay = overlay }
  local keyParts, lines = {}, {}
  for _, tile in ipairs(ids) do
    local pixels = tileFor(dir, files[tile])
    if pixels then
      plan.tiles[tile] = pixels
      plan.files[tile] = files[tile]
      keyParts[#keyParts + 1] = tile .. "=" .. files[tile]
      lines[#lines + 1] = string.format("$%02X=%s", tile, files[tile])
    end
  end
  if #keyParts == 0 and not overlay then return nil end
  if overlay then keyParts[#keyParts + 1] = "overlay" end
  plan.key = table.concat(keyParts, ",")
  plans[id] = plan
  log("plan:" .. id, "%s: %s%s", id, overlay and "ID OVERLAY on  " or "",
      table.concat(lines, "  "))
  return plan
end

-- Write the plan's tiles into `data` (an ImageData copy of the atlas) whose
-- tiles run `perRow` to a row.  Returns how many slots were written.
function TileOverrides.stamp(data, perRow, plan)
  if not (data and plan and plan.tiles) then return 0 end
  perRow = perRow or 16
  local w, h = data:getDimensions()
  local count = 0

  -- the id overlay goes down first, on every slot; the explicit picks below
  -- then replace the slots they name
  if plan.overlay then
    for tile = 0, perRow * math.floor(h / TILE) - 1 do
      if not plan.tiles[tile] then
        local dx, dy = (tile % perRow) * TILE, math.floor(tile / perRow) * TILE
        if dx + TILE <= w and dy + TILE <= h then
          data:paste(idTile(tile), dx, dy, 0, 0, TILE, TILE)
          count = count + 1
        end
      end
    end
  end

  for tile, art in pairs(plan.tiles) do
    local dx, dy = (tile % perRow) * TILE, math.floor(tile / perRow) * TILE
    if dx + TILE <= w and dy + TILE <= h then
      for y = 0, TILE - 1 do
        for x = 0, TILE - 1 do
          local r, g, b, a = art:getPixel(x, y)
          if a < 1 then
            -- over the slot's own art, so a cut-out keeps the tile behind it
            local or_, og, ob, oa = data:getPixel(dx + x, dy + y)
            r = r * a + or_ * (1 - a)
            g = g * a + og * (1 - a)
            b = b * a + ob * (1 - a)
            a = a + oa * (1 - a)
          end
          data:setPixel(dx + x, dy + y, r, g, b, a)
        end
      end
      count = count + 1
    end
  end
  return count
end

-- Drop everything derived: the config, the plans and the decoded tiles.
-- Called off Assets' hot-reload flush, so editing the data file or swapping a
-- PNG takes effect on the next flush.
function TileOverrides.invalidate()
  config = nil
  plans = {}
  tiles8 = {}
  idTiles = {}
  logged = {}
end

Assets.register(TileOverrides.invalidate)

return TileOverrides
