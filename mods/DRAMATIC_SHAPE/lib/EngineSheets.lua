-- Prepare the flat renderer's newly exposed tilesets before a seam crossing.
-- Voxel meshes and these animated sheets have separate caches. setMap loads
-- another ring of neighbours even when its own voxel mesh is already ready.
local V = ...
local Tiles = require("src.render.Gen3Tiles")
local Renderer = require("src.render.TileRenderer")
local Loader = require("src.world.MapLoader")
local Mods = require("src.mods.Loader")
local M = {}
local active, dataset, seen = nil, nil, {}
local deadline = math.huge
local clock = love.timer.getTime

local function resume()
  local job = active
  local ok, result = coroutine.resume(job.co)
  if not ok or coroutine.status(job.co) == "dead" then
    active = nil
    if not ok then
      require("src.core.Logger").warn("voxel tileset prefetch: %s", tostring(result))
    end
  end
end

-- The engine puts a failure sentinel in its cache while baking. An actual
-- consumer must finish an outstanding bake rather than read that sentinel.
local function finish()
  deadline = math.huge
  while active do resume() end
end

V.require("Rewrap").install({
  { Tiles, "dramaticShapeSheetHook", { "bakeMetatileInto", "drawLayer" } },
  { Renderer, "dramaticShapeSheetHook", { "gen3SheetsFor", "releaseGen3Sheets" } },
  { Mods, "dramaticShapeSheetHook", { "teardown" } },
  { Loader, "dramaticShapeSheetHook", { "trim" } },
}, function()
  for _, name in ipairs({"bakeMetatileInto", "drawLayer"}) do
    local bake = Tiles[name]
    Tiles[name] = function(self, ...)
      local result = bake(self, ...)
      if active and coroutine.running() == active.co and clock() >= deadline then
        coroutine.yield()
      end
      return result
    end
  end
  local trim = Loader.trim
  Loader.trim = function(protected)
    return trim(V.require("ChunkMesher").keepRecentMaps(protected))
  end
  local teardown = Mods.teardown
  Mods.teardown = function(...) finish(); return teardown(...) end
  local sheets, release = Renderer.gen3SheetsFor, Renderer.releaseGen3Sheets
  Renderer.gen3SheetsFor = function(ts, data, ...)
    if active and coroutine.running() ~= active.co and ts and ts.id == active.key then
      finish()
    end
    return sheets(ts, data, ...)
  end
  Renderer.releaseGen3Sheets = function(...)
    finish()
    dataset, seen = nil, {}
    return release(...)
  end
end)

V.require("Rewrap").onUnwind(finish)

function M.pump(state, data, seconds)
  if not (state and state.map and data and data.maps) then return end
  if dataset ~= data then
    finish()
    dataset, seen = data, {}
  end
  -- Prewarming may evict old sheets. Refresh the live pairs first so
  -- switching voxels off can still use their flat renderers safely.
  local livePairs, liveCount = {}, 0
  local function keep(map)
    local key = map and map.tileset and map.tileset.id
    if key and not livePairs[key] then
      livePairs[key], liveCount = true, liveCount + 1
      Renderer.touchGen3(key)
    end
  end
  keep(state.map)
  for _, nb in ipairs(state.neighbors or {}) do keep(nb.map) end
  if not active and liveCount >= (Renderer.GEN3_SHEET_CACHE or 12) then return end
  if not active then
    -- Visit the nearest neighbour's connections first: these are the new
    -- sheets rebuildNeighbors will ask for when that neighbour becomes root.
    local candidates = {}
    local p = state.player or {}
    for _, nb in ipairs(state.neighbors or {}) do
      local def = nb.map.def
      local x, y = (p.px or 0) + 8, (p.py or 0) + 8
      local unit = tonumber(def.blockPx) or 16
      local dx = math.max(nb.ox-x, 0, x-nb.ox-def.width*unit)
      local dy = math.max(nb.oy-y, 0, y-nb.oy-def.height*unit)
      candidates[#candidates+1] = { nb=nb, distance=dx*dx+dy*dy }
    end
    table.sort(candidates, function(a,b) return a.distance < b.distance end)
    for _, candidate in ipairs(candidates) do
      for _, first in pairs(candidate.nb.map.def.connections or {}) do
      for _, conn in ipairs(first.list or { first }) do
        local def = data.maps[conn.map]
        local ts = def and Loader.tilesetFor(data, def)
        if ts and ts.blockTiles == 2 and not seen[ts.id] then
          seen[ts.id] = true
          local job = { key=ts.id }
          job.co = coroutine.create(function()
            Renderer.gen3SheetsFor(ts, data, data.constants and data.constants.gen3Layout)
          end)
          active = job
          break
        end
      end
      if active then break end
      end
      if active then break end
    end
  end
  if active then
    deadline = clock() + (seconds or .001)
    resume()
  end
end

function M.pending() return active ~= nil end
return M
