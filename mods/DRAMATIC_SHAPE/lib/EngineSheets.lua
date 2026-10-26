-- Prepare the flat renderer's newly exposed tilesets before a seam crossing.
-- Voxel meshes and these animated sheets have separate caches. setMap loads
-- another ring of neighbours even when its own voxel mesh is already ready.
local V = ...
local Tiles = require("src.render.Gen3Tiles")
local Renderer = require("src.render.TileRenderer")
local Loader = require("src.world.MapLoader")
local Mods = require("src.mods.Loader")
local M = {}
local Budget=V.require("BuildBudget")
local active, dataset, seen = nil, nil, {}
local exhaustedMap,exhaustedNeighbors
local discoveryMap,discoveryNeighbors
local livePairs={}
local artSeen={}
local futureMaps
local deadline = math.huge
local clock = love.timer.getTime

V.require("EnginePixelCanvas").install(Renderer.gen3SheetsFor)

local function resume()
  local job = active
  local ok, result = coroutine.resume(job.co)
  if not ok or coroutine.status(job.co) == "dead" then
    job.result=ok and result or nil
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
  { Tiles, "dramaticShapeSheetHook", { "bakeMetatileInto", "drawLayer", "entries" } },
  { Renderer, "dramaticShapeSheetHook", { "gen3SheetsFor", "releaseGen3Sheets" } },
  { Mods, "dramaticShapeSheetHook", { "teardown" } },
  { Loader, "dramaticShapeSheetHook", { "trim" } },
}, function()
  -- entries also runs in animatedMetatiles BEFORE any layer is baked. That
  -- initial all-metatile scan otherwise bypasses both drawing checkpoints.
  for _, name in ipairs({"bakeMetatileInto", "drawLayer", "entries"}) do
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
  local function prepared(ts,data,...)
    local record=sheets(ts,data,...)
    if record and Renderer.gen3QuadsFor then
      Renderer.gen3QuadsFor(record,function()
        if active and coroutine.running()==active.co and clock()>=deadline then coroutine.yield() end
      end)
    end
    return record
  end
  Renderer.gen3SheetsFor = function(ts, data, ...)
    if ts and Budget.active() then
      -- Keep engine baking in its OWN coroutine. A cancelled voxel job must
      -- not abandon the renderer's in-progress cache sentinel or animation
      -- state. Prefetch can finish this job after its original caller leaves.
      local function advance()
        deadline=clock()+.001
        resume()
        Budget.check()
      end
      while active and active.key~=ts.id do advance() end
      local job=active
      if not job then
        local args,n={...},select("#",...)
        local unpackValues=table.unpack or unpack
        job={key=ts.id}
        job.co=coroutine.create(function()return prepared(ts,data,unpackValues(args,1,n))end)
        active=job
        if dataset~=data then
          dataset,seen=data,{};exhaustedMap,exhaustedNeighbors=nil,nil
          discoveryMap,discoveryNeighbors=nil,nil;futureMaps=nil;artSeen={}
        end
      end
      while active==job do advance() end
      return job.result
    end
    if active and coroutine.running() ~= active.co and ts and ts.id == active.key then
      finish()
    end
    return prepared(ts, data, ...)
  end
  Renderer.releaseGen3Sheets = function(...)
    finish()
    dataset, seen = nil, {}
    exhaustedMap,exhaustedNeighbors=nil,nil
    discoveryMap,discoveryNeighbors=nil,nil;futureMaps=nil;artSeen={}
    return release(...)
  end
end)

V.require("Rewrap").onUnwind(function()
  finish()
  if Renderer.pinGen3Sheets then Renderer.pinGen3Sheets(nil) end
end)

function M.pump(state, data, seconds)
  if not (state and state.map and data and data.maps) then return end
  if not require('src.core.GameVersion').isGen3() then return end
  if dataset ~= data then
    finish()
    dataset, seen = data, {}
    exhaustedMap,exhaustedNeighbors=nil,nil
    discoveryMap,discoveryNeighbors=nil,nil;futureMaps=nil;artSeen={}
  end
  -- Prewarming may evict old sheets. Refresh the live pairs first so
  -- switching voxels off can still use their flat renderers safely.
  for key in pairs(livePairs)do livePairs[key]=nil end
  local liveCount = 0
  local function keep(map)
    local key = map and map.tileset and map.tileset.id
    if key and not livePairs[key] then
      livePairs[key], liveCount = true, liveCount + 1
      Renderer.touchGen3(key)
    end
  end
  keep(state.map)
  for _, nb in ipairs(state.neighbors or {}) do keep(nb.map) end
  if Renderer.pinGen3Sheets then Renderer.pinGen3Sheets(livePairs) end
  if discoveryMap~=state.map or discoveryNeighbors~=state.neighbors then
    discoveryMap,discoveryNeighbors=state.map,state.neighbors
    seen={}
    artSeen={}
    futureMaps=nil
    exhaustedMap,exhaustedNeighbors=nil,nil
  end
  -- rebuildNeighbors replaces this list on a map/topology change. Once its
  -- candidates are exhausted, walking in the same neighbourhood needs only
  -- the LRU touches above, not fresh sort tables and tileset lookups per frame.
  if not active and exhaustedMap==state.map and exhaustedNeighbors==state.neighbors then return end
  if not active then
    local future=futureMaps
    if not future then
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
    future={}
    local known={}
    local function add(id)
      if id and not known[id] then known[id]=true;future[#future+1]=id end
    end
    for _, candidate in ipairs(candidates) do
      -- Entry rebuilds a whole view-sized neighbour set, not only the new
      -- root's direct connections. Prepare that exact expanded set too.
      local nb=candidate.nb
      if nb.map.id and state.neighborReachBuiltW and state.neighborReachBuiltH then
        local compute=state.computeNeighbors or require('src.world.OverworldController').computeNeighbors
        local hops=require('src.world.FieldDefaults').world(data,'neighborHops') or 2
        for _,n in ipairs(compute(data.maps,nb.map.id,hops,state.neighborReachBuiltW,state.neighborReachBuiltH)) do add(n.id) end
      end
      for _, first in pairs(candidate.nb.map.def.connections or {}) do
      for _, conn in ipairs(first.list or { first }) do
        add(conn.map)
      end
      end
    end
    futureMaps=future
    end
    local reserved=liveCount
    for key in pairs(seen)do if not livePairs[key] then reserved=reserved+1 end end
    for _,id in ipairs(future) do
        local def = data.maps[id]
        local ts = def and Loader.tilesetFor(data, def)
        if ts and ts.blockTiles == 2 and not seen[ts.id]
           and (not livePairs[ts.id] or not Renderer.hasGen3Sheets or not Renderer.hasGen3Sheets(ts.id))
           and (livePairs[ts.id] or reserved<(Renderer.GEN3_SHEET_CACHE or 12)) then
          seen[ts.id] = true
          local job = { key=ts.id }
          job.co = coroutine.create(function()
            Renderer.gen3SheetsFor(ts, data, data.constants and data.constants.gen3Layout)
          end)
          active = job
          break
        end
    end
    if not active and data.sprites then
      -- Warm only image resources, never spawn/move future NPCs or evaluate
      -- their map-entry scripts. Each upload gets its own pump slice.
      for _,id in ipairs(future)do
        for _,obj in ipairs(data.maps[id] and data.maps[id].objects or {})do
          local def=data.sprites[obj.sprite]
          local path=def and def.image
          if path and not artSeen[path] then
            artSeen[path]=true
            active={co=coroutine.create(function()require('src.render.Assets').image(path)end)}
            break
          end
        end
        if active then break end
      end
    end
    if not active then exhaustedMap,exhaustedNeighbors=state.map,state.neighbors end
  end
  if active then
    deadline = clock() + (seconds or .001)
    resume()
  end
end

function M.pending() return active ~= nil end
return M
